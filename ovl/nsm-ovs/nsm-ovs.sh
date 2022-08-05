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

##   env
##     Print environment.
##
cmd_env() {
	test "$env_read" = "yes" && return 0
	test -n "$__nsm_dir" || __nsm_dir=$GOPATH/src/github.com/networkservicemesh

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
	env_read=yes
}


##   clone_nsm [--nsm-dir=dir]
##     Clone repos needed for NSM build if needed
cmd_clone_nsm() {
	cmd_env
	mkdir -p $__nsm_dir
	cd $__nsm_dir
	local c
	for c in cmd-nsmgr cmd-registry-k8s cmd-forwarder-ovs cmd-forwarder-vpp \
		cmd-nsc cmd-nse-remote-vlan deployments-k8s cmd-exclude-prefixes-k8s; do
		if test -d "$__nsm_dir/$c"; then
			echo "Already cloned [$c], git pull..."
			cd "$__nsm_dir/$c"
			git pull || die "git pull"
		else
			git clone https://github.com/networkservicemesh/$c.git || die "clone"
		fi
	done
}
##   generate_manifests [--branch=main] [--dest=/tmp/$USER/nsm-manifests]
##     Generate manifests from deployments-k8s/apps
cmd_generate_manifests() {
	cmd_env
	local apps=$__nsm_dir/deployments-k8s/apps
	test -d $apps || die "Not a directory [$apps]"
	test -n "$__branch" || __branch=main
	cd $apps/..
	git fetch
	mkdir -p $tmp
	local out=$tmp/out
	if ! git switch $__branch > $out; then
		cat $out
		die "git switch"
	fi
	log "On branch $__branch"
	git pull > /dev/null || die "git pull"
	test -n "$__dest" || __dest=/tmp/$USER/nsm-manifests
	mkdir -p $__dest || die "mkdir -p $__dest"
	local c
	for c in forwarder-host-ovs forwarder-ovs forwarder-vpp nse-remote-vlan \
		nsmgr registry-k8s registry-memory nsc-kernel; do
		if ! test -d $apps/$c; then
			log "Not a directory [$apps/$c], skipping..."
			continue
		fi
		kubectl kustomize $apps/$c > $__dest/$c.yaml
	done
	echo "Manifests in [$__dest]"
}
##   compare_manifests [--dest=/tmp/$USER/nsm-manifests]
##     Compare generated manifests with the ones in this ovl.
cmd_compare_manifests() {
	which meld > /dev/null || die "Can't execute meld"
	test -n "$__dest" || __dest=/tmp/$USER/nsm-manifests
	local sdir=$dir/default/etc/kubernetes/nsm
	local c
	for c in forwarder-host-ovs forwarder-ovs forwarder-vpp nsmgr \
		registry-k8s nsc-kernel nse-remote-vlan; do
		if ! test -r $__dest/$c.yaml; then
			log "Not readable [$__dest/$c.yaml]"
			continue
		fi
		test -r $sdir/$c.yaml || die "Not readable [$sdir/$c.yaml]"
		meld $__dest/$c.yaml $sdir/$c.yaml
	done
}
##   set_local_image [yaml-files...]
##     Change image: to locally built ones
cmd_set_local_image() {
	local n
	for n in $@; do
		test -r $n || die "Not readable [$n]"
		test -w $n || die "Not writable [$n]"
		echo "=== $n"
		sed -i -E -e 's,image: ghcr.io/networkservicemesh.*/([^:]+):.*,image: registry.nordix.org/cloud-native/nsm/\1:local,' $n
	done
}
##   set_image_version <version>
##     Change image version in default/
cmd_set_image_version() {
	test -n "$1" || die "No version"
	local n
	for n in $(find $dir/default/etc/kubernetes -name '*.yaml'); do
		echo "=== $(basename $n)"
		sed -i -E -e "s,image: ghcr.io/networkservicemesh.*/([^:]+):.*,image: ghcr.io/networkservicemesh/\\1:$1," $n
	done
}
##   build_nsm_image [--nsm-dir=dir] [--branch=branch] <image>
##     Build a NSM image and upload it to the local registry
cmd_build_nsm_image() {
	test -n "$1" || die 'No image'
	local c=$1
	cmd_env
	test -d "$__nsm_dir/$c" || die "Not a directory [$__nsm_dir/$c]"
	cd $__nsm_dir/$c
	if test -n "$__branch"; then
		git branch -a | grep "origin/$__branch" || die "No [$__branch] in $c"
		git checkout $__branch
		git pull > /dev/null || die "$c: git pull"
	fi
	docker build --tag registry.nordix.org/cloud-native/nsm/$c:local .
	local images="$($XCLUSTER ovld images)/images.sh"
	test -x $images || die "Not executable [$images]"
	$images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/$c:local
}
##   build_nsm [--nsm-dir=dir] [--branch=main]
##     Build all necessary NSM images. Example;
##       ./nsm-ovs.sh build_nsm --branch=release/v1.1.1
cmd_build_nsm() {
	local i
	for i in cmd-nsmgr cmd-registry-k8s cmd-forwarder-ovs cmd-forwarder-vpp \
		cmd-nsc cmd-exclude-prefixes-k8s cmd-registry-memory \
		cmd-nse-remote-vlan; do
		echo "==== Building [$i]"
		cmd_build_nsm_image $i
	done
}

##
##   test --list
##   test [--xterm] [--no-stop] [--local] [test...] > logfile
##     Exec tests. Env;
##     xcluster_NSM_FORWARDER=ovs|vpp
##     xcluster_NSM_REGISTRY=k8s|memory
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
		test_basic
    fi      

    now=$(date +%s)
    tlog "Xcluster test ended. Total time $((now-begin)) sec"

}

test_start_empty() {
	test -n "$__mode" || __mode=dual-stack
	export xcluster___mode=$__mode
	xcluster_prep $__mode
	export TOPOLOGY=multilan-router
	. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	if test "$xcluster_FIRST_WORKER" = "1"; then
		export __mem1=4096
	else
		export __mem1=1024
	fi
	export __mem=3072
	test -n "$__nvm" || __nvm=3
	export __nvm
	test "$__local" = "yes" && export nsm_local=yes
	xcluster_start network-topology nsm-ovs spire lspci $@

	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
	otcw ifup
}

##   test start
##     Start cluster with NSM.
test_start() {
	# Avoid "Illegal instruction" error with -cpu host
	# accel=kvm,kernel_irqchip=split is needed for iommu
	__kvm_opt='-M q35,accel=kvm,kernel_irqchip=split -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0,max-bytes=1024,period=80000 -cpu host'
	export __kvm_opt
	export __append1="hugepages=128"
	export __append2="hugepages=128"
	export __append3="hugepages=128"
	if test "$xcluster_NSM_FORWARDER" = "ovs"; then
		test -n "$xcluster_HOST_OVS" || export xcluster_HOST_OVS=yes
		if test "$xcluster_HOST_OVS" = "yes"; then
			test_start_empty ovs $@
		else
			test_start_empty $@
		fi
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

##   test basic (default)
##     Ping/TCP test
test_basic() {
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

##   test udp
##     UDP test
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

##   test multivlan
##     Multiple vlan-tags
test_multivlan() {
	tlog "=== nsm-ovs: Multiple vlan-tags forwarder=$xcluster_NSM_FORWARDER"
	test_start
	otc 1 start_nse
	otc 1 start_nsc
	otc 1 collect_addresses
	otc 1 internal_ping
	otc 1 "start_nse nse-network2"
	otc 1 "start_nsc nsc-network2"
	otc 1 "collect_addresses nsc-network2"
	otc 1 "internal_ping nsc-network2"
	xcluster_stop
}

##
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
