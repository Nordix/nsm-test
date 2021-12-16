#! /bin/sh
##
## nsm-vlan-dpdk.sh --
##
##   Help script for the xcluster ovl/nsm-vlan-dpdk.
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/${prg}_$$

die() {
    echo "ERROR: $*" >&2
    rm -rf $tmp
    exit 1
}
help() {
    grep '^##' $0 | cut -c3-
    rm -rf $tmp
    exit 0
}
test -n "$1" || help
echo "$1" | grep -qi "^help\|-h" && help

log() {
	echo "$prg: $*" >&2
}
dbg() {
	test -n "$__verbose" && echo "$prg: $*" >&2
}

##  env
##    Print environment.
##
cmd_env() {
	if test "$cmd" = "env"; then
		set | grep -E '^(__.*)='
		return 0
	fi

	cd $dir
	. ./Envsettings
	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}

##   test --list
##   test [--xterm] [test...] > logfile
##     Exec tests
##
cmd_test() {
	if test "$__list" = "yes"; then
        grep '^test_' $me | cut -d'(' -f1 | sed -e 's,test_,,'
        return 0
    fi

	cmd_env
    start=starts
    test "$__xterm" = "yes" && start=start
    rm -f $XCLUSTER_TMP/cdrom.iso

    if test -n "$1"; then
        for t in $@; do
            test_$t
        done
    else
		test_default
    fi      

    now=$(date +%s)
    tlog "Xcluster test ended. Total time $((now-begin)) sec"

}

test_start_empty() {
	test -n "$__mode" || __mode=dual-stack
	export xcluster___mode=$__mode
	xcluster_prep $__mode
	export TOPOLOGY=multilan
	. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	export __smp202=3
	export __nets202=0,1,2,3,4,5
	xcluster_start network-topology nsm-vlan-dpdk spire $@

	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
}
test_start() {
	# Avoid "Illegal instruction" error with -cpu host
	# accel=kvm,kernel_irqchip=split is needed for iommu
    __kvm_opt='-M q35,accel=kvm,kernel_irqchip=split -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0,max-bytes=1024,period=80000 -cpu host'
    export __append1="hugepages=128"
    export __append2="hugepages=128"
    export __append3="hugepages=128"
	if test "$__iommu" = "yes"; then
		# https://gist.github.com/mcastelino/e0cca2af5694ba672af8e274f5dffb47
		__kvm_opt="$__kvm_opt -device intel-iommu,intremap=on,caching-mode=on,device-iotlb=on"
		# https://doc.dpdk.org/guides/linux_gsg/linux_drivers.html
	    export __append1="hugepages=512 iommu=pt intel_iommu=on"
		export __append2="hugepages=512 iommu=pt intel_iommu=on"
		export __append3="hugepages=512 iommu=pt intel_iommu=on"
	fi
	export __kvm_opt
	test_start_empty lspci
	if test "$OVL_SPIRE" != "no"; then
		otcprog=spire_test
		otc 1 start_spire_registrar
		unset otcprog
	else
		otc 1 start_spire
	fi
	otcw "ifup eth2"
	otcw "ifup eth3"
	#otcw "ifup eth4" # eth4 must be down to be grabbed by dpdk
	otc 1 start_nsm_vpp_vlan
	otc 1 nse_nsc_vpp_vlan
}

test_default() {
	tlog "=== nsm-vlan-dpdk: Basic test"
	test_start
	otc 202 vpp_vlan_ping_external
	xcluster_stop
}

. $($XCLUSTER ovld test)/default/usr/lib/xctest
indent=''

# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 $hook || die "Invalid command [$cmd]"

while echo "$1" | grep -q '^--'; do
    if echo $1 | grep -q =; then
	o=$(echo "$1" | cut -d= -f1 | sed -e 's,-,_,g')
	v=$(echo "$1" | cut -d= -f2-)
	eval "$o=\"$v\""
    else
	o=$(echo "$1" | sed -e 's,-,_,g')
	eval "$o=yes"
    fi
    shift
done
unset o v
long_opts=`set | grep '^__' | cut -d= -f1`

# Execute command
trap "die Interrupted" INT TERM
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
