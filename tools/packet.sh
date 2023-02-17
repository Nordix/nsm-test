#!/bin/bash
##
## packet.sh
##
## Helper to start packet tracing inside vpp
##

set -e

IFS='
'
VPPCTL_IN=/tmp/vppctl.in
VPPCTL_OUT=/tmp/vppctl.out
TRACE_BUF_SIZE=10000

function init {
    # In case a previous run failed without running cleanup.
    rm -f "$VPPCTL_IN" "$VPPCTL_OUT"

    touch "$VPPCTL_OUT"
    mkfifo "$VPPCTL_IN"
}

function cleanup {
    rm -f "$VPPCTL_IN" "$VPPCTL_OUT"
}

die() {
    echo "ERROR: $*" >&2
    cleanup
    exit 1
}
function help {
    echo "Usage:"
    echo ""
    echo "       $0 <command> [arguments] [-n <kubernetes-namespace>] [-p <kubernetes-pod>...]"
    echo ""
    echo "The commands are:"
    echo ""
    echo "	start - start tracing on different input nodes (clear is included before start)"
    echo "	show  - show trace output with filtering"
    echo "	clear - clear trace buffer"
    echo ""
    echo "Common arguments:"
    echo "	-n kubernetes namespace"
    echo "	-p kubernetes pods"
    echo ""
    echo "Use \"$0 <command> -h\" for more information about a command."
    exit 1
    }

test -n "$1" || help
echo "$1" | grep -qi "^help\|-h" && help

function vppctl {
    echo > "$VPPCTL_OUT"
    echo "$@" >&3
    echo "show version" >&3
    until grep -q 'vpp v[0-9][0-9]\.' "$VPPCTL_OUT"; do
        if [[ "$?" -ne 1 ]]; then
            break # other error
        fi
        sleep 0.05
    done
    head -n -3 "$VPPCTL_OUT"
}

function print_packet {
    echo -e "Packet $1:"
    echo -e "$2"
    echo -e ""
}

function get_vpp_input_node {
    # afpacket aliases
    if [[ "$1" == "afpacket" ]] || [[ "$1" == "af-packet" ]] || [[ "$1" == "veth" ]]; then
        echo "af-packet-input"
    fi

    # tapv1 + tapv2 alias
    if [[ "$1" == "tap" ]]; then
        echo "virtio-input"
    fi

    # tapv1 aliases
    if [[ "$1" == "tap1" ]] || [[ "$1" == "tapv1" ]]; then
        echo "tapcli-rx"
    fi

    # tapv2 aliases
    if [[ "$1" == "tap2" ]] || [[ "$1" == "tapv2" ]]; then
        echo "virtio-input"
    fi

    # dpdk aliases
    if [[ "$1" == "dpdk" ]] || [[ "$1" == "gbe" ]] || [[ "$1" == "phys"* ]]; then
        echo "dpdk-input"
    fi

    # ipsec aliases
    if [[ "$1" == "ipsec" ]] || [[ "$1" == "encrypt"* ]]; then
        echo "dpdk-crypto-input"
        echo "dpdk-esp-encrypt"
    fi
    if [[ "$1" == "ipsec" ]] || [[ "$1" == "decrypt"* ]]; then
        echo "dpdk-esp-decrypt"
        echo "dpdk-esp-decrypt-post"
    fi

    # memif aliases
    if [[ "$1" == "mem"* ]]; then
        echo "memif-input"
    fi
}

function print_start_help_and_exit {
    echo "Usage: $0 start [-i <VPP-IF-TYPE>]... [-n <kubernetes-namespace>] [-p <kubernetes-pod>]..."
    echo '   -i <VPP-IF-TYPE> : VPP interface *type* to run the packet capture on (e.g. dpdk-input, virtio-input, etc.)'
    echo '                       - available aliases:'
    echo '                         - af-packet-input: afpacket, af-packet, veth'
    echo '                         - virtio-input: tap (version determined from the VPP runtime config), tap2, tapv2'
    echo '                         - tapcli-rx: tap (version determined from the VPP config), tap1, tapv1'
    echo '                         - dpdk-input: dpdk, gbe, phys*'
    echo '                         - ipsec encryption: ipsec, encrypt*'
    echo '                         - ipsec decryption: ipsec, decrypt*'
    echo '                         - memif-input: mem*'
    echo '                       - multiple interfaces can be watched at the same time - the option can be repeated with'
    echo '                         different values'
    echo '                       - default = af-packet tap2'
    exit 1
}

cmd_start() {
    INTERFACES=()

    while getopts i:n:p:h option
    do
        case "${option}"
        in
	    n) KNS=(${OPTARG});;
	    p) KPODS+=(${OPTARG});;
            i) INTERFACES+=(${OPTARG});;
            h) print_start_help_and_exit;;
        esac
    done

    # default interfaces
    if [ "${#INTERFACES[@]}" -eq 0 ]; then
        INTERFACES=(af-packet tap2)
    fi

    # get input nodes
    INPUT_NODES=()
    for INTERFACE in "${INTERFACES[@]}"; do
        for NODE in $(get_vpp_input_node "$INTERFACE"); do
            INPUT_NODES+=($NODE)
        done
    done

     # set kubectl prefix
    PREFIX=""
    if [ "${#KPODS[@]}" -ne 0 ]; then
	PREFIX="kubectl exec -n $KNS"
	for KPOD in "${KPODS[@]}"; do
	    PREFIX+=" ${KPOD}"
	    eval "$PREFIX -- vppctl clear trace >/dev/null"
	    for NODE in "${INPUT_NODES[@]}"; do
		eval "$PREFIX -- vppctl trace add ${NODE} ${TRACE_BUF_SIZE} >/dev/null"
            done
	done
    else
	vppctl clear trace >/dev/null
    	for NODE in "${INPUT_NODES[@]}"; do
            vppctl trace add "$NODE" "$TRACE_BUF_SIZE" >/dev/null
    	done
    fi

}

function print_clear_help_and_exit {
    echo 'Clears the packet capture'
    echo "Usage: $0 clear [-n <kubernetes-namespace>] [-p <kubernetes-pod>...]"
    exit 1
}


cmd_clear() {
    while getopts i:n:p:h option
    do
        case "${option}"
        in
	    n) KNS=(${OPTARG});;
	    p) KPODS+=(${OPTARG});;
            h) print_clear_help_and_exit;;
        esac
    done

     # set kubectl prefix
    PREFIX=""
    if [ "${#KPODS[@]}" -ne 0 ]; then
	PREFIX="kubectl exec -n $KNS"
	for KPOD in "${KPODS[@]}"; do
	    PREFIX+=" ${KPOD}"
	    eval "$PREFIX -- vppctl clear trace >/dev/null"
	done
    else
	vppctl clear trace >/dev/null
    fi

}

function print_show_help_and_exit {
    echo "Usage: $0 show [-r] [-f <REGEXP> / <SUBSTRING>] [-n <kubernetes-namespace>] [-p <kubernetes-pod>...]"
    echo '   -r               : apply filter string (passed with -f) as a regexp expression'
    echo '                      - by default the filter is NOT treated as regexp'
    echo '   -f               : filter string that packet must contain (without -r) or match as regexp (with -r) to be printed'
    echo '                      - default is no filtering'
    exit 1
}

cmd_show() {
    INTERFACES=()

    while getopts n:p:rf:h option
    do
        case "${option}"
            in
            n) KNS=(${OPTARG});;
	    p) KPODS+=(${OPTARG});;
            r) IS_REGEXP=1;;
            f) FILTER=${OPTARG};;
            h) print_show_help_and_exit;;
        esac
    done

    if [ "${#KPODS[@]}" -ne 0 ]; then
	    PREFIX="/usr/bin/kubectl exec -n $KNS"
	    for KPOD in "${KPODS[@]}"; do
		PREFIX+=" ${KPOD}"
		echo "==== ${KPOD} ===="
		processor $PREFIX $FILTER $IS_REGEXP
	    done
    else
	processor $PREFIX $FILTER $IS_REGEXP
    fi
}

function processor {
    PREFIX=$1
    test -n "$2" && IS_REGEXP=$2
    test -n "$3" && FILTER=$3

    COUNT=0
    IDX=0
    echo -e "\n Show packet trace (max. ${TRACE_BUF_SIZE})...\n"
	CMD="${PREFIX} -- vppctl show trace max \"${TRACE_BUF_SIZE}\" | tr -d '\0'"
	TRACE=`sh -c ${CMD}`
        STATE=0
        PACKET=""
        PACKETIDX=0
        for LINE in $TRACE; do
            if [[ "$STATE" -eq 0 ]]; then
		# looking for "Packet <number>" of the first unconsumed packet
		if [[ "$LINE" =~ ^Packet[[:space:]]([0-9]+) ]]; then
                        PACKETIDX=${BASH_REMATCH[1]}
                        if [[ "$PACKETIDX" -gt "$IDX" ]]; then
                            STATE=1
                            IDX=$PACKETIDX
                        fi
                    fi
                elif [[ "$STATE" -eq 1 ]]; then
                    # looking for the start of the packet trace
                    if ! [[ "${LINE}" =~ ^[[:space:]]$ ]]; then
                        # found line with non-whitespace character
                        STATE=2
                        PACKET="$LINE"
                    fi
                else
                    # consuming packet trace
                    if [[ "${LINE}" =~ ^[[:space:]]$ ]]; then
                        # end of the trace
                        if [[ -n "${PACKET// }" ]]; then
                            if ([[ -n $IS_REGEXP ]] && [[ "$PACKET" =~ "$FILTER" ]]) || \
                                ([[ -z $IS_REGEXP ]] && [[ "$PACKET" == *"$FILTER"* ]]); then
                                COUNT=$((COUNT+1))
                                print_packet "$COUNT" "$PACKET"
                            fi
                        fi
                        PACKET=""
                        STATE=0
                    else
                        PACKET="$PACKET\n$LINE"
                    fi
                fi
            done
            if [[ -n "${PACKET// }" ]]; then
                if ([[ -n "$IS_REGEXP" ]] && [[ "$PACKET" =~ "$FILTER" ]]) || \
                    ([[ -z "$IS_REGEXP" ]] && [[ "$PACKET" == *"$FILTER"* ]]); then
                    COUNT=$((COUNT+1))
                    print_packet "$COUNT" "$PACKET"
                fi
            fi
            if [[ "$PACKETIDX" -gt $(($TRACE_BUF_SIZE - 20)) ]]; then
                echo -e "\nClearing packet trace (some packets may slip uncaptured)...\n"
                break;
            fi

}

cmd=$1
shift
grep -q "^cmd_$cmd()" $0 $hook || die "Invalid command [$cmd]"

init
trap cleanup EXIT
cmd_$cmd "$@"
status=$?
exit $status
