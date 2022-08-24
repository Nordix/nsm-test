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

##   env
##     Print environment.
##
cmd_env() {
	if test "$cmd" = "env"; then
		set | grep -E '^(__.*|ARCHIVE)='
		return 0
	fi
	return 0
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
	if test -n "$VLAN_BASE"; then
	   create_vlans
	   mkdir -p /var/run/bird /val/log
	   exec bird -d -c /etc/meridio/bgp.conf -s /var/run/bird/bird.ctl > /var/log/bird.log 2>&1
	fi
	tail -f /dev/null
}

# If this script is started as pid=1 it's supposed to be the start
# command in the Meridio GW container.
test "$$" -eq 1 && container_start

# Get the command
test -n "$1" || help
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
