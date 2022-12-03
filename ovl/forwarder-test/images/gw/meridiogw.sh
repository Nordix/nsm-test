#! /bin/sh
##
## meridiogw.sh --
##
##   Help script for the Meridio GW used as traffic-generator and BGP
##   peer in Meridio e2e tests.
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
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
echo "$1" | grep -qi "^help\|-h" && help

log() {
	echo "$prg: $*" >&2
}
dbg() {
	test -n "$__verbose" && echo "$prg: $*" >&2
}

# initvar <variable> [default]
#   Initiate a variable. The __<variable> will be defined if not set,
#   from $TUNNEL_<variable-upper-case> or from the passed default
initvar() {
	local n N v
	n=$1
	v=$(eval "echo \$__$n")
	test -n "$v" && return 0	# Already set
	N=$(echo $n | tr a-z A-Z)
	v=$(eval "echo \$TUNNEL_$N")
	if test -n "$v"; then
		eval "__$n='$v'"
		return 0
	fi
	test -n "$2" && eval "__$n=$2"
	return 0
}

##   env
##     Print environment.
cmd_env() {
	test "$envset" = "yes" && return 0
	params="type|dev|master|peer|id|dport|sport|ipv4|ipv6|remote_ipv4"
	initvar dev vxlan0
	initvar master eth0
	initvar peer
	initvar id
	initvar dport 5533
	initvar sport 5533
	initvar ipv4
	initvar ipv6
	initvar remote_ipv4
	if test "$cmd" = "env"; then
		set | grep -E "^__($params).*=" | sort
		return 0
	fi
	envset=yes
}
##   hold
##     Hold execution
cmd_hold() {
	log "Hold execution"
	tail -f /dev/null
}
##   vxlan --peer=ip-address --id=vni [--master=] [--dev=] \
##       [--dport=] [--sport=]
##     Setup a vxlan tunnel.
cmd_vxlan() {
	cmd_env
	log "Setup a VXLAN tunnel to [$__peer/$__id]"
	test -n "$__peer" || die "No peer address"
	test -n "$__id" || die "No VNI"
	local sport1=$((__sport + 1))
	ip link add $__dev type vxlan id $__id dev $__master remote $__peer \
		dstport $__dport srcport $__sport $sport1
}
##   ping_remote [--remote-ipv4=]
##     Ping the remote end of the tunnel until response. This should
##     initiate a setup through a K8s UDP service.
cmd_ping_remote() {
	cmd_env
	test -n "$__remote_ipv4" || die no address
	log "Ping $__remote_ipv4 ..."
	while ! ping -c1 -W1 $__remote_ipv4; do
		log " ... no response"
		sleep 4
		log "Ping $__remote_ipv4 ..."
	done
	log "Ping $__remote_ipv4 succesful"
}

start_bird() {
	mkdir -p /run/bird
}

create_vlans() {
	local i iface id b
	for i in 0 1 2; do
		iface=vlan$i
		id=$((VLAN_BASE + i))
		ip link add link eth0 name $iface type vlan id $id
		ip link set $iface up
		b=$((100 + i))
		ip addr add 169.254.$b.150/24 dev $iface
		ip -6 addr add 100:$b::150/64 dev $iface
	done
}

container_start() {
	test -x /etc/meridio/init && exec /etc/meridio/init
	test -r /etc/meridio/env && . /etc/meridio/env
	sysctl -w net.ipv6.conf.all.disable_ipv6=0
	sysctl -w net.ipv4.fib_multipath_hash_policy=1
	sysctl -w net.ipv6.fib_multipath_hash_policy=1
	sysctl -w net.ipv6.conf.all.forwarding=1
	sysctl -w net.ipv4.conf.all.forwarding=1
	sysctl -w net.ipv6.conf.all.accept_dad=0
	ethtool -K eth0 tx off
	test -n "$VLAN_BASE" && create_vlans
	if test -r /etc/meridio/bgp.conf; then
		mkdir -p /var/run/bird
		exec bird -d -c /etc/meridio/bgp.conf -s /var/run/bird/bird.ctl
	fi
	tail -f /dev/null
}

##
# Get the command
if test -n "$1"; then
	cmd=$1
	shift
elif test -n "$INIT_FUNCTION"; then
	cmd=$INIT_FUNCTION
else
	# If this script is started as pid=1 it's supposed to be the start
	# command in the Meridio GW container.
	test "$$" -eq 1 && container_start
fi

test -n "$cmd" || help
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
