#! /bin/sh
##
## nsm.sh --
##
##   Test script for NSM in xcluster.
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
		retrun 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}

##   test --list
##   test [--xterm] [test...] > logfile
##     Test k3s
##
cmd_test() {
	if test "$__list" = "yes"; then
		grep '^test_' $me | cut -d'(' -f1 | sed -e 's,test_,,'
		return 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)

	start=starts
	test "$__xterm" = "yes" && start=start

	# Remove overlays
	rm -f $XCLUSTER_TMP/cdrom.iso
	
	if test -n "$1"; then
		for t in $@; do
			test_$t
		done
	else
		export xcluster_NSM_FORWARDER=vpp
		unset xcluster_NSM_NSE
		unset xcluster_INTERFACE
		test_basic
		export xcluster_NSE_HOST=vm-002
		test_basic
		export xcluster_NSM_FORWARDER=generic
		export xcluster_NSM_NSE=generic
		unset xcluster_NSE_HOST
		test_basic
		export xcluster_NSE_HOST=vm-002
		test_basic
		unset xcluster_NSE_HOST
		test_vlan_generic
		test_ipvlan
		test_ovs
		test_vlan
		export xcluster_NSE_HOST=vm-002
		test_ovs
	fi	

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}


test_start_base() {
	test -n "$TOPOLOGY" || TOPOLOGY=multilan
	export TOPOLOGY
	. "$($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings"
	test -n "$__mode" || __mode=dual-stack
	export xcluster___mode=$__mode
	export __mem1=2048
	export __mem=1536
	xcluster_prep $__mode
	xcluster_start nsm network-topology

	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
	otc 1 start_spire
}
test_start_nextgen() {
	test_start
	log "OBSOLETE; start_nextgen. Use; start"
}
test_start() {
	test_start_base
	otc 1 start_nsm_next_gen
	otcw init_interface
}
test_basic_nextgen() {
	test_basic
	log "OBSOLETE; basic_nextgen. Use; basic"
}
test_basic() {
	if test "$xcluster_NSE_HOST" = "vm-002"; then
		tlog "=== nsm; basic LOCAL"
	else
		tlog "=== nsm; basic REMOTE"
	fi
	test_start
	otc 1 start_nsc_nse
	otc 1 check_interfaces
	xcluster_stop
}

test_basic_ipv6() {
	tlog "=== nsm; basic IPv6"
	test_start
	otc 1 start_nsc_nse_ipv6
	xcluster_stop
}

test_ipvlan() {
	tlog "=== nsm; IPVLAN"
	export xcluster_NSM_FORWARDER=generic
	export xcluster_NSM_NSE=generic
	export xcluster_INTERFACE=eth2
	export xcluster_NSM_FORWARDER_CALLOUT=/bin/ipvlan.sh
	test_start
	otc 1 start_nsc_nse_l2
	otc 1 check_interfaces_ipvlan
	xcluster_stop
}

test_vlan() {
        tlog "=== nsm; VLAN in NSC only"
        export xcluster_NSM_VLAN=true
        export xcluster_NSM_FORWARDER=vlan
	export xcluster_NSM_NSE=generic-vlan
	test_start
	otc 1 start_nsc_nse
	otc 1 check_interfaces_vlan
	otc 1 ping_interfaces_vlan
	otc 1 start_nsc_nse_trench
	otc 1 check_interfaces_vlan_trench
	xcluster_stop
	unset xcluster_NSM_VLAN
	unset xcluster_NSM_NSE
	unset xcluster_NSM_FORWARDER
}

test_vpp_vlan() {
	tlog "=== nsm; VPP with VLAN SUPPORT"
	export xcluster_NSM_FORWARDER=vpp
	export xcluster_NSM_NSE=new-vlan
	test_start
	otc 1 start_nsc_nse
	otc 201 check_vlan
	unset xcluster_NSM_NSE
        unset xcluster_NSM_FORWARDER
}

test_vlan_generic() {
	tlog "=== nsm; GENERIC VLAN"
	export xcluster_NSM_FORWARDER=generic-vlan
	export xcluster_NSM_NSE=generic
	export xcluster_NSM_FORWARDER_CALLOUT=/bin/vlan-forwarder.sh
	test_start
	otc 1 start_nsc_nse
	otc 1 check_interfaces_vlan
	xcluster_stop
}

test_bird_poc_nse() {
    tlog "=== nsm; VLAN in NSC only; multus VLAN in NSE; BIRD (BGP); NSC <-> NSE"
    export xcluster_NSM_FORWARDER=vlan
    #export xcluster_NSM_FORWARDER=kernel
    export xcluster_NSM_NSE=generic-vlan
    #export xcluster_NSM_NSE=generic-vlan-oneleg
    export xcluster_NSM_VLAN=true
    #export xcluster_NSM_XTAG=vlan-0.2
    test -n "$xcluster_NSM_BASE_INTERFACE" || export xcluster_NSM_BASE_INTERFACE=eth2
    test -n "$xcluster_NSM_VLAN_ID" || export xcluster_NSM_VLAN_ID=100
    test -n "$xcluster_TEST_NET_CIDDR_PREFIX" || export xcluster_TEST_NET_CIDDR_PREFIX=169.254.0.0/24
    test -n "$xcluster_TEST_GW4_CIDDR_PREFIX" || export xcluster_TEST_GW4_CIDDR_PREFIX=169.254.0.254/24
    test -n "$xcluster_TEST_GW6_CIDDR_PREFIX" || export xcluster_TEST_GW6_CIDDR_PREFIX=fe80::beef/64
    export XCLUSTER_INSTALL_MULTUS
    test_start
    otcw up_base_interface
    otc 1 label_nodes_nsc
    otc 1 start_multus
    otc 1 create_vlan_nad
    # adjust manifests on all the worker nodes...
    otcw annotate_nad_nse
    otcw set_affinity_nsc
    otcw config_nse
    otcw add_bird_nsc
    otcw add_bird_nse
    otc 1 start_nsc_nse
    otc 1 check_ext_interfaces_nse_ping
    xcluster_stop
    unset xcluster_NSM_VLAN
    #unset xcluster_NSM_XTAG
    unset xcluster_NSM_NSE
    unset XCLUSTER_INSTALL_MULTUS
    unset xcluster_NSM_FORWARDER
}

test_bird_poc_gw() {
    # NSE is merely part of control plane, a separate POD acts as GW
    tlog "=== nsm; VLAN in NSC only; multus VLAN in GW; BIRD (BGP); NSC <-> GW"
    export xcluster_NSM_FORWARDER=vlan
    #export xcluster_NSM_FORWARDER=kernel
    export xcluster_NSM_NSE=generic-vlan
    #export xcluster_NSM_NSE=generic-vlan-oneleg
    export xcluster_NSM_VLAN=true
    #export xcluster_NSM_XTAG=vlan-0.2
    test -n "$xcluster_NSM_BASE_INTERFACE" || export xcluster_NSM_BASE_INTERFACE=eth2
    test -n "$xcluster_NSM_VLAN_ID" || export xcluster_NSM_VLAN_ID=100
    test -n "$xcluster_TEST_NET_CIDDR_PREFIX" || export xcluster_TEST_NET_CIDDR_PREFIX=169.254.0.0/24
    test -n "$xcluster_TEST_GW4_CIDDR_PREFIX" || export xcluster_TEST_GW4_CIDDR_PREFIX=169.254.0.254/24
    test -n "$xcluster_TEST_GW6_CIDDR_PREFIX" || export xcluster_TEST_GW6_CIDDR_PREFIX=fe80::beef/64
    export XCLUSTER_INSTALL_MULTUS
    test_start
    otcw up_base_interface
    otc 1 label_nodes_nsc
    otc 1 start_multus
    otc 1 create_vlan_nad
    # adjust manifests on all the worker nodes...
    otcw set_affinity_nsc
    otcw add_bird_nsc
    otcw config_nse
    otc 1 start_gateway_with_bird
    otc 1 start_nsc_nse
    otc 1 check_ext_interfaces_ping
    xcluster_stop
    unset xcluster_NSM_VLAN
    #unset xcluster_NSM_XTAG
    unset xcluster_NSM_NSE
    unset XCLUSTER_INSTALL_MULTUS
    unset xcluster_NSM_FORWARDER
}

test_bird_poc_gw_trenches() {
    # NSE is merely part of control plane, a separate POD acts as GW (two "trenches")
    tlog "=== nsm; VLAN in NSC only; multus VLAN in GW; BIRD (BGP); 2 x [NSC <-> GW]"
    export xcluster_NSM_FORWARDER=vlan
    #export xcluster_NSM_FORWARDER=kernel
    export xcluster_NSM_NSE=generic-vlan
    #export xcluster_NSM_NSE=generic-vlan-oneleg
    export xcluster_NSM_VLAN=true
    #export xcluster_NSM_XTAG=vlan-0.2
    test -n "$xcluster_NSM_BASE_INTERFACE" || export xcluster_NSM_BASE_INTERFACE=eth2
    test -n "$xcluster_NSM_VLAN_ID" || export xcluster_NSM_VLAN_ID=100
    test -n "$xcluster_TEST_NET_CIDDR_PREFIX" || export xcluster_TEST_NET_CIDDR_PREFIX=169.254.0.0/24
    test -n "$xcluster_TEST_GW4_CIDDR_PREFIX" || export xcluster_TEST_GW4_CIDDR_PREFIX=169.254.0.254/24
    test -n "$xcluster_TEST_GW6_CIDDR_PREFIX" || export xcluster_TEST_GW6_CIDDR_PREFIX=fe80::beef/64
    export XCLUSTER_INSTALL_MULTUS
    test_start
    otcw up_base_interface
    otcw backup_nsc_nse
    otc 1 label_nodes_nsc
    otc 1 start_multus
    otc 1 create_vlan_nad
    # adjust manifests on all the worker nodes...
    otcw set_affinity_nsc
    otcw add_bird_nsc
    otcw config_nse
    otc 1 start_gateway_with_bird
    otc 1 start_nsc_nse
    otc 1 check_ext_interfaces_ping
    tlog "Deploy a second set of NSC - NSE - GW"
    # start nsc2, nse2, gateway2
    otcw restore_nsc_nse
    otc 1 create_second_vlan_nad
    otcw update_second_nsc
    otcw set_affinity_second_nsc
    otcw add_bird_second_nsc
    otcw update_second_nse
    otcw config_second_nse
    otc 1 start_second_gateway_with_bird
    otc 1 start_second_nsc_nse
    otc 1 check_second_ext_interfaces_ping

    xcluster_stop
    unset xcluster_NSM_VLAN
    #unset xcluster_NSM_XTAG
    unset xcluster_NSM_NSE
    unset XCLUSTER_INSTALL_MULTUS
    unset xcluster_NSM_FORWARDER
}

test_bird_poc_gw_ecfe() {
    # NSE is merely part of control plane, separate PODs act as GW
    # Use a setup like ECFE does:
    # - 2 GWs each expecting VIP routes through BGP
    # - GWs do not advertise routes to FEs - instead a static "VRRP" GW is used on FE side)
	tlog "=== nsm; VLAN in NSC only; multus VLAN in GW; BIRD (\"ECFE\" BGP); NSC <-> [GW1, GW2]"
	export xcluster_NSM_FORWARDER=vlan
    #export xcluster_NSM_FORWARDER=kernel
    export xcluster_NSM_NSE=generic-vlan
    #export xcluster_NSM_NSE=generic-vlan-oneleg
    export xcluster_NSM_VLAN=true
    #export xcluster_NSM_XTAG=vlan-0.2
    test -n "$xcluster_NSM_BASE_INTERFACE" || export xcluster_NSM_BASE_INTERFACE=eth2
    test -n "$xcluster_NSM_VLAN_ID" || export xcluster_NSM_VLAN_ID=100
    test -n "$xcluster_TEST_NET_CIDDR_PREFIX" || export xcluster_TEST_NET_CIDDR_PREFIX=169.254.0.0/24
    test -n "$xcluster_TEST_GW4_CIDDR_PREFIX" || export xcluster_TEST_GW4_CIDDR_PREFIX=169.254.0.253/24
    test -n "$xcluster_TEST_GW6_CIDDR_PREFIX" || export xcluster_TEST_GW6_CIDDR_PREFIX=fe80::bee1/64
    export XCLUSTER_INSTALL_MULTUS
    test_start
    otcw up_base_interface
    otcw backup_nsc_nse
    otc 1 label_nodes_nsc
    otc 1 start_multus
    otc 1 create_vlan_nad
    # adjust manifests on all the worker nodes...
    otcw set_affinity_nsc
    otcw add_ecfe_bird_nsc
    otcw config_nse
    otc 1 start_ecfe_gateways_with_bird
    otc 1 start_nsc_nse
    otc 1 check_ext_interfaces_ecfe

    xcluster_stop
    unset xcluster_NSM_VLAN
    #unset xcluster_NSM_XTAG
    unset xcluster_NSM_NSE
    unset XCLUSTER_INSTALL_MULTUS
    unset xcluster_NSM_FORWARDER
}

test_multi_sel() {
	unset xcluster_NSM_NO_VLAN_MECH
	unset xcluster_NSM_SELECT_FORWARDER
	unset xcluster_NSM_NSE_SELECT_FORWARDER
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=vpp
	unset xcluster_NSM_NSE_SELECT_FORWARDER
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	unset xcluster_NSM_SELECT_FORWARDER
	export xcluster_NSM_NSE_SELECT_FORWARDER=vpp
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=vpp
	export xcluster_NSM_NSE_SELECT_FORWARDER=vpp
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=vpp
	export xcluster_NSM_NSE_SELECT_FORWARDER=vlan
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=vlan
	unset xcluster_NSM_NSE_SELECT_FORWARDER
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	unset xcluster_NSM_SELECT_FORWARDER
	export xcluster_NSM_NSE_SELECT_FORWARDER=vlan
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=vlan
	export xcluster_NSM_NSE_SELECT_FORWARDER=vlan
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=vlan
	export xcluster_NSM_NSE_SELECT_FORWARDER=generic
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=generic
	unset xcluster_NSM_NSE_SELECT_FORWARDER
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	unset xcluster_NSM_SELECT_FORWARDER
	export xcluster_NSM_NSE_SELECT_FORWARDER=generic
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=generic
	export xcluster_NSM_NSE_SELECT_FORWARDER=generic
	test_multi
	
	unset xcluster_NSM_NO_VLAN_MECH
	export xcluster_NSM_SELECT_FORWARDER=generic
	export xcluster_NSM_NSE_SELECT_FORWARDER=vlan
	test_multi
}

test_multi() {
	# vlan-forwarder:vlan-0.2 supports vlan through a newly introduced nsm vlan mechanism, while
	# it does not understand kernel mechanism.
	# This means that nsc can not blindly stick to the kernel mech by default. Therefore some default
	# forwarder selection is always set for this test. And in case the preferred forwarder is not set
	# to vlan-forwarder, nsc is notified not to use vlan mech (via xcluster_NSM_NO_VLAN_MECH).
	test -n "$xcluster_NSM_SELECT_FORWARDER" -o -n "$xcluster_NSM_NSE_SELECT_FORWARDER" || export xcluster_NSM_SELECT_FORWARDER=vpp
	
	if test -n "$xcluster_NSM_SELECT_FORWARDER" -a "$xcluster_NSM_SELECT_FORWARDER" != "vlan" || \
	test -z "$xcluster_NSM_SELECT_FORWARDER" -a -n "$xcluster_NSM_NSE_SELECT_FORWARDER" -a "$xcluster_NSM_NSE_SELECT_FORWARDER" != "vlan"; then
		export xcluster_NSM_NO_VLAN_MECH="true"
	fi
	unset xcluster_NSM_FORWARDER
	# vlan mech requires dedicated nsc and nse (they support vlan mech as well)
	# note: nse-generic registers nsm service with payload=IP, however vpp forwarder
	# requires payload=ETHERNET. Use icmp-responder until nse-generic is updated...
	if test -n "$xcluster_NSM_NO_VLAN_MECH" -a "$xcluster_NSM_NO_VLAN_MECH" = "true"; then
	        export xcluster_NSM_NSE=icmp-responder
	        unset xcluster_NSM_VLAN
		checker=check_interfaces
	else
	        export xcluster_NSM_NSE=generic-vlan
	        export xcluster_NSM_VLAN=true
		checker=check_interfaces_vlan
	fi
	test_start
	otc 1 start_forwarder_vlan
	otc 1 start_forwarder_generic
	otc 1 start_nsc_nse
	otc 1 $checker
	xcluster_stop
}

test_ovs() {
	if test "$xcluster_NSE_HOST" = "vm-002"; then
		tlog "=== nsm; OVS LOCAL"
	else
		tlog "=== nsm; OVS REMOTE"
	fi
	export xcluster_NSM_FORWARDER=generic
	export xcluster_INTERFACE=eth2
	export xcluster_NSM_FORWARDER_CALLOUT=/var/lib/networkservicemesh/ovs.sh
	test_start
	otc 1 start_nsc_nse
	otc 1 check_interfaces
	xcluster_stop
}

cmd_get_logs() {
	# kubectl get pod nse-58cc4f847-rx9v5 -o json | jq .metadata.labels
	local dst=/tmp/$USER/nsm-logs
	rm -rf $dst
	mkdir -p $dst
	test -n "$xcluster_NSM_FORWARDER" || xcluster_NSM_FORWARDER=vpp
	local pod n ip
	local sed=$dst/pods.sed

	for n in NSC nsmgr-local forwarder-local \
		nsmgr-remote forwarder-remote NSE; do
		case $n in
			nsmgr-local)
				pod=$(get_pod app=nsmgr vm-002);;
			forwarder-local)
				pod=$(get_pod app=forwarder-$xcluster_NSM_FORWARDER vm-002);;
			nsmgr-remote)
				pod=$(get_pod app=nsmgr vm-003);;
			forwarder-remote)
				pod=$(get_pod app=forwarder-$xcluster_NSM_FORWARDER vm-003);;
			NSC)
				pod=$(get_pod app=nsc);;
			NSE)
				pod=$(get_pod app=nse);;
		esac
		ip=$($kubectl get pod $pod -o json | jq -r .status.podIP)
		tlog "Get logs for $n ($pod, $ip)..."
		echo "s,$pod,$n,g" >> $sed
		echo "s,$ip,$ip[$n],g" >> $sed
		$kubectl logs $pod > $dst/$n.log
	done
}

##  readlog <nsm-log>
##    Filter an nsm-log. Example;
##    ./nsm.sh readlog /tmp/$USER/nsm-logs/nsmgr-local.log | less
##
cmd_readlog() {
	test -n "$1" || die "No log"
	test -r "$1" || die "Not readable [$1]"
	local log="$1"
	local pods=$(dirname $log)/pods.sed
	test -r $pods || die "Not readable [$pods]"

	if grep -qE 'request-diff|response-diff' $log; then
		# An original NSM log
		local pat='request|request-diff|response|response-diff'
		grep -oE "($pat).*" $log | sed -Ee 's, *span=.*,,' \
			| sed -Ee "s,($pat)=(.*),{\"\\1\": \\2}," |  jq . | grep -v token \
			| sed -f $pods
	else
		# Some *-generic log
		sed -f $pods < $log
	fi
}


. $($XCLUSTER ovld test)/default/usr/lib/xctest
indent=''


# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 || die "Invalid command [$cmd]"

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
