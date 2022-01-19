#! /bin/sh
##
## nsm-ovs.sh --
##
##   Help script for the xcluster ovl/nsm-ovs.
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

	test -n "$__tag" || __tag="registry.nordix.org/cloud-native/nsm-ovs:latest"

	if test "$cmd" = "env"; then
		set | grep -E '^(__.*)='
		return 0
	fi

	test -n "$xcluster_NSM_FORWARDER" || export xcluster_NSM_FORWARDER=ovs
	test -n "$xcluster_FIRST_WORKER" || export xcluster_FIRST_WORKER=1
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
	if test "$xcluster_FIRST_WORKER" = "1"; then
		export __mem1=4096
	else
		export __mem1=1024
	fi
	export __mem=3072
	test -n "$__nvm" || __nvm=3
	export __nvm
	xcluster_start network-topology nsm-ovs spire lspci $@

	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
	otcw ifup
}

test_start() {
	# Avoid "Illegal instruction" error with -cpu host
	# accel=kvm,kernel_irqchip=split is needed for iommu
	__kvm_opt='-M q35,accel=kvm,kernel_irqchip=split -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0,max-bytes=1024,period=80000 -cpu host'
	export __kvm_opt
	export __append1="hugepages=128"
	export __append2="hugepages=128"
	export __append3="hugepages=128"
	if test "$xcluster_HOST_OVS" = "yes"; then
		test "$xcluster_NSM_FORWARDER" = "ovs" || tdie "Forwarder must be ovs"
		test_start_empty ovs $@
	else
		test_start_empty $@
	fi

	otcprog=spire_test
	otc 1 start_spire_registrar
	unset otcprog
	otc 1 start_nsm
	otc 1 start_forwarder
	test "$xcluster_NSM_FORWARDER" = "vpp" && otc 1 vpp_version
}

test_default() {
	tlog "=== nsm-ovs: Ping/TCP test forwarder=$xcluster_NSM_FORWARDER"
	test_start
	otc 1 start_nse
	otc 1 start_nsc
	otc 1 collect_addresses
	otc 1 internal_ping
	otc 202 setup_vlan
	otc 202 collect_addresses
	otc 202 external_ping
	otc 1 start_tcp_servers
	otc 1 internal_tcp
	otc 202 external_tcp
	otc 1 stop_tcp_servers
	xcluster_stop
}

test_udp() {
	tlog "=== nsm-ovs: UDP test forwarder=$xcluster_NSM_FORWARDER"
	test_start
	otc 1 start_nse
	otc 1 start_nsc
	otc 1 collect_addresses
	otc 1 internal_udp
	otc 202 setup_vlan
	otc 202 collect_addresses
	otc 202 external_ping
	otc 202 external_udp
	xcluster_stop
}

test_multivlan() {
	tlog "=== nsm-ovs: Multiple vlan-tags forwarder=$xcluster_NSM_FORWARDER"
	test_start
	otc 1 "start_nse nse-vlan"
	otc 1 "start_nsc nsc-vlan"
	otc 1 "collect_addresses nsc-vlan"
	otc 1 internal_ping
	otc 1 "start_nse nse-network2"
	otc 1 "start_nsc nsc-network2"
	otc 1 "collect_addresses nsc-network2"
	otc 1 internal_ping
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
