#!/bin/sh

dir=$(dirname $0); dir=$(readlink -f $dir)

die() {
    echo "ERROR: $*" >&2
    exit 1
}

test -n "$__e2elog" && echo "========== test.sh $1" >> $__e2elog

case $1 in
	init|configuration_new_ip_revert)
		kubectl patch configmap meridio-configuration-trench-a -n red \
			--patch-file $dir/default.yaml;;
	end)
	;;
	configuration_new_ip)
		kubectl patch configmap meridio-configuration-trench-a -n red \
			--patch-file $dir/new-ip.yaml;;
	*)
		die "Invalid command [$1]";;
esac
