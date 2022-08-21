#! /bin/sh
##
## forwarder-test.sh --
##
##   Help script for the xcluster ovl/forwarder-test.
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
	test "$env_set" = "yes" && return 0

	test -n "$MERIDIOD" || MERIDIOD=$GOPATH/src/github.com/Nordix/Meridio
	test -n "$MERIDIOVER" || MERIDIOVER=local
	test -n "$xcluster_NSM_FORWARDER" || export xcluster_NSM_FORWARDER=vpp
	test -n "$xcluster_FIRST_WORKER" || export xcluster_FIRST_WORKER=1
	if test "$xcluster_FIRST_WORKER" = "1"; then
		export __mem1=4096
		test -n "$__nvm" || __nvm=3
		test "$__nvm" -gt 3 && __nvm=3
		export __mem=3072
	else
		export __mem1=1024
		test -n "$__nvm" || __nvm=4
		test "$__nvm" -gt 4 && __nvm=4
		export __mem=4096
	fi
	export __nvm

	if test "$cmd" = "env"; then
		set | grep -E '^(__.*|MERIDIOD|MERIDIOVER)='
		return 0
	fi

	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	test -n "$__out" || __out=$(readlink -f $dir/_output)
	eval $($XCLUSTER env)
	env_set=yes
}

##   generate_e2e --dest=dir
##     Generate Meridio e2e manifests
cmd_generate_e2e() {
	test -n "$__dest" || die "No dest"
	test -d "$__dest" || die "Not a directory [$__dest]"
	cmd_env

	helm template $MERIDIOD/deployments/helm/ -f $dir/helm/values-a.yaml \
		--generate-name --create-namespace --namespace red \
		> $__dest/trench-a.yaml 2> /dev/null

	helm template $MERIDIOD/deployments/helm/ -f $dir/helm/values-b.yaml \
		--generate-name --create-namespace --namespace red \
		> $__dest/trench-b.yaml 2> /dev/null

	helm template $MERIDIOD/examples/target/helm/ --generate-name \
		--create-namespace --namespace red --set applicationName=target-a \
		--set default.trench.name=trench-a > $__dest/target-a.yaml 2> /dev/null

	helm template $MERIDIOD/examples/target/helm/ --generate-name \
		--create-namespace --namespace red --set applicationName=target-b \
		--set default.trench.name=trench-b > $__dest/target-b.yaml 2> /dev/null
}

##   bird_dir
##   bird_build
##     Build the Bird routing suite
bird_ver=2.0.9
cmd_bird_dir() {
	test -n "$__dest" || __dest=$XCLUSTER_WORKSPACE
	echo $__dest/bird-$bird_ver
}
cmd_bird_build() {
	local dir=$(cmd_bird_dir)
	if test -x $dir/bird; then
		log "Already built in [$dir]"
		return 0
	fi
	local ar=bird-$bird_ver.tar.gz
	if ! test -r $ARCHIVE/$ar; then
		local url=https://bird.network.cz/download/$ar
		curl -L $url > $ARCHIVE/$ar || die "curl $ar"
	fi
	mkdir -p $dir || die Mkdir
	tar -C $dir/.. -xf $ARCHIVE/$ar
	cd $dir
	./configure --with-protocols=bfd,bgp,static || die configure
	make -j$(nproc) || die make
}

##   generate_manifests [--dst=/tmp/$USER/meridio-manifests]
##     Generate manifests from Meridio helm charts.
cmd_generate_manifests() {
	unset KUBECONFIG
	cmd_env
	test -n "$__dst" || __dst=/tmp/$USER/meridio-manifests
	mkdir -p $__dst
	local m
	m=$MERIDIOD/deployments/helm
	test -d $m || die "Not a directory [$m]"
	helm template --generate-name $m > $__dst/meridio.yaml
	m=$MERIDIOD/examples/target/helm
	test -d $m || die "Not a directory [$m]"
	helm template --generate-name $m > $__dst/target.yaml
	echo "Manifests generated in [$__dst]"
}

##   chversion [--old=local] [--dir=manifest-dir] <new-version>
##     Change the image version in manifests.
cmd_chversion() {
	test -n "$1" || die "Missing parameter"
	test -n "$__dir" || die "No manifest-dir"
	test -d "$__dir" || die "Not a directory [$__dir]"
	test -n "$__old" || __old=local
	local f new=$1
	for f in $(find $__dir -name '*.yaml'); do
		sed -i -E "s,image:(.*(frontend|ipam|load-balancer|nsp|proxy|tapa)):$__old,image:\\1:$new," $f
	done
}
##   lreg_cache [version]
##     Cache Meridio images in the local registry. Use $MERIDIOVER by default
cmd_lreg_cache() {
	cmd_env
	local ver=$1
	test -n "$1" || ver=$MERIDIOVER
	local images=$($XCLUSTER ovld images)/images.sh
	local f
	for f in frontend ipam load-balancer nsp proxy tapa; do
		$images lreg_cache \
			registry.nordix.org/cloud-native/meridio/$f:$ver || die
	done
}

##   build_binaries
##     Build binaries. Build in ./_output
cmd_build_binaries() {
	cmd_env
	mkdir -p $__out
	__targets="load-balancer proxy tapa ipam nsp frontend"

	cd $MERIDIOD
	local gitver=$(git describe --dirty --tags)
	log "Building binaries for [$gitver]"
	local n cmds cgo
	for n in $__targets; do
		if echo $n | grep -qE 'ipam|nsp'; then
			# Requires CGO_ENABLED=1
			cgo="$cgo $MERIDIOD/cmd/$n"
		else
			cmds="$cmds $MERIDIOD/cmd/$n"
		fi
		cmds="$cmds $MERIDIOD/test/applications/target-client"
	done
	if test -n "$cmds"; then
		CGO_ENABLED=0 GOOS=linux go build -o $__out \
			-ldflags "-extldflags -static -X main.version=$gitver" $cmds \
			|| die "go build $cmds"
	fi
	if test -n "$cgo"; then
		mkdir -p $tmp
		if ! CGO_ENABLED=1 GOOS=linux go build -o $__out \
			-ldflags "-extldflags -static -X main.version=$gitver" \
			$cgo > $tmp/out 2>&1; then
			cat $tmp/out
			die "go build $cgo"
		fi
	fi
	strip $__out/*
}

##   build_base_image
##     Build the base image
cmd_build_base_image() {
	cmd_env
	local base=$(grep base_image= $dir/images/Dockerfile.default | cut -d= -f2)
	log "Building base image [$base]"
	local dockerfile=$dir/images/Dockerfile.base
	mkdir -p $tmp
	docker build -t $base -f $dockerfile $tmp || die "docker build $base"
}
##   build_images
##     Build local images and upload to the local registry.
cmd_build_images() {
	cmd_build_binaries
	local images=$($XCLUSTER ovld images)/images.sh
	test -x $images || dir "Can't find ovl/images/images.sh"

	test -n "$__registry" || __registry=registry.nordix.org/cloud-native/meridio
	test -n "$__version" || __version=local
	test -n "$__nfqlb" || __nfqlb=1.1.0

	for n in frontend ipam load-balancer nsp proxy tapa; do
		x=$__out/$n
		test -x $x || die "Not built [$x]"
		rm -rf $tmp; mkdir -p $tmp/root
		cp $x $tmp/root
		if test "$n" = "load-balancer"; then
			local ar=$HOME/Downloads/nfqlb-$__nfqlb.tar.xz
			if ! test -r $ar; then
				local url=https://github.com/Nordix/nfqueue-loadbalancer/releases/download
				curl -L $url/$__nfqlb/nfqlb-$__nfqlb.tar.xz > $ar || die Curl
			fi
			tar -C $tmp --strip-components=1 -xf $ar nfqlb-$__nfqlb/bin/nfqlb \
				|| die "tar $ar"
		fi
		dockerfile=$dir/images/Dockerfile.$n
		test -r $dockerfile \
			|| dockerfile=$dir/images/Dockerfile.default
		sed -e "s,/start-command,/$n," < $dockerfile > $tmp/Dockerfile
		docker build -t $__registry/$n:$__version $tmp \
			|| die "docker build $n"
	done

	for n in frontend ipam load-balancer nsp proxy tapa; do
		$images lreg_upload --strip-host $__registry/$n:$__version
	done
}
##   build_app_image
##     Build the "meridio-app" test image
cmd_build_app_image() {
	local images=$($XCLUSTER ovld images)/images.sh
	test -x $images || dir "Can't find ovl/images/images.sh"
	test -n "$__registry" || __registry=registry.nordix.org/cloud-native/meridio
	test -n "$__version" || __version=local
	export __out
	$images mkimage --upload --strip-host --tag=$__registry/meridio-app:$__version $dir/images/meridio-app
}

##
##   test --list
##   test [--xterm] [--no-stop] [--local] [--nsm-local] [test...] > logfile
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
		test_trench
	fi

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"

}

test_start_empty() {
	export TOPOLOGY=multilan-router
	. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	echo "--nvm=$__nvm --mem1=$__mem1 --mem=$__mem"
	# Avoid "Illegal instruction" error (vpp)
	export __kvm_opt='-M q35,accel=kvm,kernel_irqchip=split -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0,max-bytes=1024,period=80000 -cpu host'
	# Required by the vpp-forwarder but not used without dpdk
	export __append1="hugepages=128"
	export __append2="hugepages=128"
	export __append3="hugepages=128"
	test "$__nsm_local" = "yes" && export nsm_local=yes
	xcluster_start network-topology spire k8s-pv nsm-ovs $@ forwarder-test

	otc 1 check_namespaces
	otc 1 check_nodes
}

##   test start
##     Start the cluster with NSM. Default; xcluster_NSM_FORWARDER=vpp
test_start() {
	tcase "Start with NSM, forwarder=$xcluster_NSM_FORWARDER"
	if test -n "$__bgp"; then
		test "$__bgp" = "yes" && __bgp=bgp
		test -n "$xcluster_TRENCH_TEMPLATE" || xcluster_TRENCH_TEMPLATE="$__bgp"
		export xcluster_TRENCH_TEMPLATE
	fi
	if test "$xcluster_NSM_FORWARDER" = "ovs"; then
		export xcluster_HOST_OVS=yes
		test_start_empty ovs $@
	else
		test_start_empty $@
	fi
	otc 202 "conntrack 20000"
	otcw "conntrack 20000"
	test "$__use_multus" = "yes" && otc 1 multus_setup
	otcprog=spire_test
	otc 1 start_spire_registrar
	otcprog=nsm-ovs_test
	local vm
	for vm in $(seq $xcluster_FIRST_WORKER $__nvm); do
		otc $vm "ifup eth2"
		otc $vm "ifup eth3"
	done
	otc 1 start_nsm
	otc 1 start_forwarder
	test "$xcluster_NSM_FORWARDER" = "vpp" && otc 1 vpp_version
	unset otcprog
}

##   test [--trenches=red,...] [--use-multus] [--bgp] trench (default)
##     Test trenches. The default is to test all 3 trenches
##     Problems has been observed "after some time" so if
##     "--reconnect-delay=sec" is specified the Re-test connectivity
##     is delayed.
test_trench() {
	test "$__use_multus" = "yes" && export __use_multus
	test -n "$__trenches" || __trenches=red,blue,green
	tlog "=== forwarder-test: Test trenches [$__trenches]"
	test_start
	local trench
	test -n "$__bgp" && otc 202 "bird --conf=$__bird_conf"
	for trench in $(echo $__trenches | tr , ' '); do
		trench_test $trench
	done
	if test -n "$__reconnect_delay"; then
		tcase "Delay before reconnect $__reconnect_delay sec..."
		sleep $__reconnect_delay
	fi
	tcase "Re-test connectivity with all trenches"
	for trench in $(echo $__trenches | tr , ' '); do
		mconnect_trench $trench
	done
	xcluster_stop
}

cmd_add_trench() {
	test -n "$1" || die 'No trench'
	case $1 in
		red) otc 202 "setup_vlan --tag=100 eth3";;
		blue) otc 202 "setup_vlan --tag=200 eth3";;
		green) otc 202 "setup_vlan --tag=100 eth4";;
		*) tdie "Invalid trench [$1]";;
	esac
	otc 1 "trench $1"
}

cmd_add_multus_trench() {
	cmd_env
	case $1 in
		red)
			otcw "local_vlan --tag=100 eth2"
			otc 202 "setup_vlan --tag=100 eth3";;
		blue)
			otcw "local_vlan --tag=200 eth2"
			otc 202 "setup_vlan --tag=200 eth3";;
		green)
			otcw "local_vlan --tag=100 eth3"
			otc 202 "setup_vlan --tag=100 eth4";;
		*) tdie "Invalid trench [$1]";;
	esac
	otc 1 "trench --use-multus $1"
}

trench_test() {
	if test "$__use_multus" = "yes"; then
		cmd_add_multus_trench $1
	else
		cmd_add_trench $1
	fi
	if test -z "$__bgp"; then
		otc 202 "collect_lb_addresses $1"
		otc 202 "trench_vip_route $1"
	fi
	otc 2 "collect_target_addresses $1"
	otc 2 "ping_lb_target $1"
	#tcase "Sleep 10 sec..."
	sleep 10
	mconnect_trench $1
}

mconnect_trench() {
	test -n "$__port" || __port=5001
	case $1 in
		red)
			otc 202 "mconnect_adr 10.0.0.1:$__port"
			otc 202 "mconnect_adr [1000::1:10.0.0.1]:$__port"
			otc 202 "mconnect_adr 10.0.0.16:$__port"
			otc 202 "mconnect_adr [1000::1:10.0.0.16]:$__port"
		;;
		blue)
			otc 202 "mconnect_adr 10.0.0.2:$__port"
			otc 202 "mconnect_adr [1000::1:10.0.0.2]:$__port"
			otc 202 "mconnect_adr 10.0.0.32:$__port"
			otc 202 "mconnect_adr [1000::1:10.0.0.32]:$__port"
		;;
		green)
			otc 202 "mconnect_adr 10.0.0.3:$__port"
			otc 202 "mconnect_adr [1000::1:10.0.0.3]:$__port"
			otc 202 "mconnect_adr 10.0.0.48:$__port"
			otc 202 "mconnect_adr [1000::1:10.0.0.48]:$__port"
		;;
	esac
}


##   test [--cnt=n] scale
##     Scaling targets. By changing replicas and by disconnect targets
##     from the stream.
test_scale() {
	test -n "$__cnt" || __cnt=1
	tlog "=== forwarder-test: Scale target cnt=$__cnt"
	test_start
	local trench=red
	trench_test $trench
	otc 1 "scale $trench 8"
	otc 1 "check_targets $trench 8"
	while test $__cnt -gt 0; do
		tlog "cnt=$__cnt"
		__cnt=$((__cnt - 1))
		otc 1 "disconnect_targets $trench 3"
		otc 1 "check_targets $trench 5"
		otc 202 "check_connections $trench 5"
		otc 1 "reconnect_targets $trench"
		otc 1 "check_targets $trench 8"
		otc 202 "check_connections $trench 8"
	done
	otc 1 "scale $trench 4"
	otc 1 "check_targets $trench 4"
	xcluster_stop
}

##   test port_nat_basic
##     Test port-NAT. Extra flow with "local-port" are added. Some
##     flows with invalid dport are added that should be ignored.
test_port_nat_basic() {
	tlog "=== forwarder-test: port-NAT."
	test_start
	local trench=red
	trench_test $trench
	otc 1 "configmap $trench conf/port-nat-basic"
	otc 1 "check_flow $trench port-nat"
	tcase "Dealy 5s ..."; sleep 5
	otc 1 "negative_check_flow $trench flow1"
	otc 202 "mconnect_adr 10.0.0.1:7777"
	otc 202 "mconnect_adr [1000::1:10.0.0.1]:7777"
	xcluster_stop
}

##   test port_nat_vip
##     Test port-NAT. VIPs are added and removed. VIP segments are used.
test_port_nat_vip() {
	tlog "=== forwarder-test: port-NAT VIPs."
	test_start
	local trench=red
	trench_test $trench
	__port=7777
	otc 1 "configmap $trench conf/port-nat-basic"
	otc 1 "check_flow $trench port-nat"
	otc 202 "mconnect_adr 10.0.0.1:7777"
	otc 202 "mconnect_adr [1000::1:10.0.0.1]:7777"
	otc 1 "check_flow_vips --cnt=2 $trench"
	otc 1 "configmap $trench conf/port-nat-vip2"
	mconnect_trench $trench
	otc 1 "check_flow_vips --cnt=4 $trench"
	test "$__no_stop" = "yes" && exit 0
	otc 1 "configmap $trench conf/port-nat-basic"
	otc 202 "mconnect_adr 10.0.0.1:7777"
	otc 202 "mconnect_adr [1000::1:10.0.0.1]:7777"
	otc 1 "check_flow_vips --cnt=2 $trench"
	xcluster_stop
}


##   test [--nsm-local] nsm
##     Test without meridio but with NSM in a "meridio alike" way,
##     i.e. NSE and NSC in separate K8s namespaces.
test_nsm() {
	tlog "=== forwarder-test: NSM without Meridio"
	test "$__nsm_local" = "yes" && export nsm_local=yes
	test_start
	otc 1 "nsm red"
	otc 1 "nsm blue"
	otc 1 "nsm green"
	otc 202 "setup_vlan --tag=100 eth3"
	otc 202 "setup_vlan --tag=200 eth3"
	otc 202 "setup_vlan --tag=100 eth4"
	local ns
	if test $xcluster_FIRST_WORKER -gt 1 ; then
		# Some CNI-plugins takes a lot of juice :-(
		tcase "Sleep 5 sec ..."
		sleep 5
	fi
	for ns in red blue green; do
		otc 202 "collect_nsc_addresses $ns"
		otc 202 "ping_nsc_addresses $ns"
	done
	xcluster_stop
}

##   test multus
##     Test Multus setup without NSM or Meridio
test_multus() {
	tlog "=== forwarder-test: Multus without NSM or Meridio"
	export __use_multus=yes
	test_start_empty
	otc 1 multus_setup
	otcw "local_vlan --tag=100 eth2"
	otcw "local_vlan --tag=200 eth2"
	otcw "local_vlan --tag=100 eth3"
	otc 202 "setup_vlan --tag=100 eth3"
	otc 202 "setup_vlan --tag=200 eth3"
	otc 202 "setup_vlan --tag=100 eth4"
	local ns
	for ns in red blue green; do
		otc 1 "multus $ns"
		otc 202 "collect_alpine_addresses $ns"
		otc 202 "ping_alpine_addresses $ns"
	done
	xcluster_stop
}

##   test meridio_e2e
##     Test with meridio_e2e
test_meridio_e2e() {
	tlog "=== forwarder-test: Meridio e2e"
	export xcluster_NSM_NAMESPACE=nsm
	export __nrouters=0
	export __e2e=yes
	test_start
	otc 1 e2e_trenches
	xcbr3_add_vlan 100
	xcbr3_add_vlan 200
	xcbr3_ping_lb 169.254.101.1
	xcbr3_ping_lb 169.254.102.1
	otc 1 e2e_targets
	xcluster_stop
}
xcbr3_add_vlan() {
	local iface=xcbr3.$1
	local adr=169.254.101.250
	test "$1" = "200" && adr=169.254.102.250
	ip link show dev $iface > /dev/null 2>&1 && return 0
	tcase "Setup vlan on host bridge xcbr3 vtag=$1"
	ip link add link xcbr3 name $iface type vlan id $1
	ip link set up dev $iface
	ip addr add $adr/24 dev $iface
	ip -6 addr add 1000::1:$adr/120 dev $iface
}
xcbr3_ping_lb() {
	local adr=$1
	tcase "Ping load-balancer on $adr"
	ping -c1 -W1 $adr 2>&1 || tdie
	tex ping -c1 -W1 1000::1:$adr 2>&1
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
