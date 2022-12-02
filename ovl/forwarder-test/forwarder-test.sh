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

findar() {
	ar=$ARCHIVE/$1
	test -r $ar || ar=$HOME/Downloads/$1
	test -r $ar
}

##   env
##     Print environment.
##
cmd_env() {
	test "$env_set" = "yes" && return 0

	test -n "$KIND_CLUSTER_NAME" || export KIND_CLUSTER_NAME=meridio
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
		set | grep -E '^(__.*|MERIDIO.*|KIND_.*)='
		return 0
	fi

	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	test -n "$__out" || __out=$(readlink -f $dir/_output)
	eval $($XCLUSTER env)
	env_set=yes
}

##   private_reg [--localhost]
##     Print the address of the local private registry. --localhost will
##     print "localhost:<port>" which is needed for local upload.
cmd_private_reg() {
	mkdir -p $tmp
	docker inspect registry | jq -r '.[0].NetworkSettings' > $tmp/private_reg \
		|| die "No private registry?"
	local port=$(cat $tmp/private_reg | jq -r '.Ports."5000/tcp"[0].HostPort')
	if test "$__localhost" = "yes"; then
		echo "localhost:$port"
		return 0
	fi
	local adr=$(cat $tmp/private_reg | jq -r .Gateway)
	echo "$adr:$port"
}

# obsolete;
#   generate_e2e --dest=dir
#     Generate Meridio e2e manifests
cmd_generate_e2e() {
	test -n "$__dest" || die "No dest"
	test -d "$__dest" || die "Not a directory [$__dest]"
	cmd_env
	local helmdir=$MERIDIOD/deployments/helm-$__exconnect
	test -d $helmdir || helmdir=$MERIDIOD/deployments/helm
	helm template $helmdir -f $dir/helm/values-a.yaml \
		--generate-name --create-namespace --namespace red \
		--set ipFamily=dualstack > $__dest/trench-a.yaml 2> /dev/null

	helm template $helmdir -f $dir/helm/values-b.yaml \
		--generate-name --create-namespace --namespace blue \
		--set ipFamily=dualstack > $__dest/trench-b.yaml 2> /dev/null

	helm template $MERIDIOD/examples/target/deployments/helm/ --generate-name \
		--create-namespace --namespace red --set applicationName=target-a \
		--set default.trench.name=trench-a > $__dest/target-a.yaml 2> /dev/null

	helm template $MERIDIOD/examples/target/deployments/helm/ --generate-name \
		--create-namespace --namespace blue --set applicationName=target-b \
		--set default.trench.name=trench-b > $__dest/target-b.yaml 2> /dev/null
}
##   helm_template [--dest=...yaml] [--values=] <dir>
##     Generate manifests from a helm template
cmd_helm_template() {
	test -n "$1" || die "No dir"
	test -d "$1" || die "Not a directory [$1]"
	test -n "$__values" || __values=$1/values.yaml
	test -r "$__values" || die "Not readable [$__values]"
	test -n "$__dest" || __dest=/tmp/$USER/helm-manifest.yaml
	if ! test -d "$(dirname $__dest)"; then
		mkdir -p "$(dirname $__dest)" || die "mkdir $(dirname $__dest)"
	fi
	helm template $1 -f $__values > $__dest
}
##   kind_start [--kind-config=]
##     Start a Kubernetes-in-Docker (KinD) cluster for Meridio tests.
##     NOTE: Images are loaded from the private registry!
cmd_kind_start() {
	cmd_kind_stop > /dev/null 2>&1
	if test -z "$__kind_config"; then
		# Use default kind config and alter the private registry if needed
		local private_reg=$(cmd_private_reg)
		log "Using private registry [$private_reg]"
		if test "$private_reg" != "172.17.0.1:80"; then
			cp $dir/kind/meridio.yaml $tmp
			sed -i -e "s,172.17.0.1,$private_reg," $tmp/meridio.yaml
			__kind_config=$tmp/meridio.yaml
		else
			__kind_config=$dir/kind/meridio.yaml
		fi
	fi
	test -r $__kind_config || die "Not readable [$__kind_config]"
	log "Start KinD cluster [$KIND_CLUSTER_NAME] ..."
	kind create cluster --name $KIND_CLUSTER_NAME --config $__kind_config \
		$KIND_CREATE_ARGS || die
	if test -x /usr/bin/busybox; then
		log "Installing busybox on control-plane and worker..."
		docker cp /usr/bin/busybox $KIND_CLUSTER_NAME-control-plane:/bin
		docker cp /usr/bin/busybox $KIND_CLUSTER_NAME-worker:/bin
	fi

	# Install a kubeconfig on workers
	local w
	local k=/etc/kubernetes/kubeconfig
	mkdir -p $tmp
	local kint=$tmp/kubeconfig
	kind get kubeconfig --name $KIND_CLUSTER_NAME --internal > $kint
	for w in $(kind --name=$KIND_CLUSTER_NAME get nodes); do
		echo $w | grep -q control-plane && continue
		cat $kint | docker exec -i $w tee $k > /dev/null
		echo "export KUBECONFIG=$k" | docker exec -i $w \
			tee -a /etc/profile.d/01-locale-fix.sh > /dev/null
	done

	if test "$__multus" = "yes"; then
		local prep=$MERIDIOD/test/e2e/meridio-e2e.sh
		if test -x $prep; then
			log "Multus e2e multus_prepare"
			export KIND_CLUSTER_NAME
			$prep multus_prepare
		else
			log "Installing Multus"
			local d=$($XCLUSTER ovld multus)/default/etc/kubernetes/multus
			kubectl apply -f $d/multus-install.yaml
			# prepare for "node-annotation" ipam
			for w in $(kind --name=$KIND_CLUSTER_NAME get nodes); do
				echo $w | grep -q control-plane && continue
				echo "{ \"kubeconfig\": \"$k\" }" | docker exec -i $w \
					tee /etc/cni/node-annotation.conf > /dev/null
			done
		fi
	fi
}
##   kind_stop
##     Stop and delete KinD cluster
cmd_kind_stop() {
	cmd_env
	kind delete cluster --name $KIND_CLUSTER_NAME
}
##   kind_sh [node]
##     Open a xterm-shell on a KinD node (default control-plane).
cmd_kind_sh() {
	cmd_env
	local node=control-plane
	test -n "$1" && node=$1
	if echo $node | grep -q '^trench'; then
		xterm -bg "#400" -fg wheat -T $node -e docker exec -it $node sh &
		return 0
	fi
	xterm -bg "#040" -fg wheat -T $node -e docker exec -it $KIND_CLUSTER_NAME-$node bash -l &
}
##   kind_annotate
##     Annotate nodes with address ranges for IPAM "node-annotation".
##     Install a multus NAD "meridio-100" using the above.
cmd_kind_annotate() {
	cmd_env
	kubectl annotate node $KIND_CLUSTER_NAME-worker meridio/bridge="\"ranges\": [
  [{ \"subnet\":\"4000::16.0.0.0/120\", \"rangeStart\":\"4000::16.0.0.0\" , \"rangeEnd\":\"4000::16.0.0.7\"}],
  [{ \"subnet\":\"16.0.0.0/24\", \"rangeStart\":\"16.0.0.0\" , \"rangeEnd\":\"16.0.0.7\"}]
]"
	kubectl annotate node $KIND_CLUSTER_NAME-worker2 meridio/bridge="\"ranges\": [
  [{ \"subnet\":\"4000::16.0.0.0/120\", \"rangeStart\":\"4000::16.0.0.8\" , \"rangeEnd\":\"4000::16.0.0.15\"}],
  [{ \"subnet\":\"16.0.0.0/24\", \"rangeStart\":\"16.0.0.8\" , \"rangeEnd\":\"16.0.0.15\"}]
]"
	cat | kubectl apply -f - <<EOF
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: meridio-100
spec:
  config: '{
    "cniVersion": "0.4.0",
    "type": "bridge",
    "bridge": "cbr2",
    "ipam": {
      "type": "node-annotation",
      "annotation": "meridio/bridge"
    }
  }'
EOF
}
##   kind_ovl <ovl> [kind-nodes...]
##     Install an ovl on kind-nodes.
cmd_kind_ovl() {
	cmd_env
	test -n "$1" || die "No ovl"
	local ovl=$($XCLUSTER ovld $1)
	test -n "$ovl" || exit 1
	test -x $ovl/tar || die "Not executable [$ovl/tar]"
	mkdir -p $tmp
	$ovl/tar $tmp/ovl.tar
	shift
	local n
	for n in $@; do
		cat $tmp/ovl.tar | docker exec -i $KIND_CLUSTER_NAME-$n tar -C / --exclude=etc/init.d --no-overwrite-dir -h --no-same-owner -x
	done
}
##   kind_install_ovs
##     Install ovs on node "worker"
cmd_kind_install_ovs() {
	local n=worker
	cmd_kind_ovl ovs $n
	docker cp /lib/x86_64-linux-gnu/libcrypto.so.3 \
		$KIND_CLUSTER_NAME-$n:/lib/x86_64-linux-gnu || die "docker cp"
}
##   kind_start_gw <name>
##     Start a gw-container. ./kind/<name>  mounted under /etc/meridio.
##     By default "bird" is started.
cmd_kind_start_gw() {
	test -n "$1" || die "No name"
	docker kill "$1" > /dev/null 2>&1
	docker rm "$1" > /dev/null 2>&1
	test -d $dir/kind/$1 && cd $dir/kind/$1
	local pwd=$(readlink -f .)
	local image=registry.nordix.org/cloud-native/meridio/meridiogw:local
	docker run -t -d --rm --network="kind" --name=$1 --privileged \
		--volume $pwd:/etc/meridio $image
}
# internal help function
helm_install() {
	mkdir -p $tmp
	local log=$tmp/helm.log
	if ! helm install $@ > $log 2>&1; then
		cat $log
		die "helm install $@"
	fi
	return 0
}
##   kind_start_nsm [--no-kind-start] [--no-spire]
##     Start a KinD cluster with spire and NSM
cmd_kind_start_nsm() {
	cmd_env
	test "$__no_kind_start" = "yes" || cmd_kind_start
	if test "$__no_spire" != "yes"; then
		kubectl apply -k $MERIDIOD/docs/demo/deployments/spire > /dev/null 2>&1 \
			|| die "kubectl apply -k $MERIDIOD/docs/demo/deployments/spire"
	fi
	helm_install $MERIDIOD/docs/demo/deployments/nsm --generate-name \
		--create-namespace --namespace nsm
	cmd_kind_check_nsm > /dev/null
}
cmd_kind_check_nsm() {
	kubectl="kubectl -n spire"
	test_statefulset spire-server 120
	test_daemonset spire-agent 120
	kubectl="kubectl -n nsm"
	test_deployment nsm-registry 120
	test_daemonset nsmgr 120
	test_daemonset forwarder-vpp 120
	test_deployment admission-webhook-k8s 120
}
##   kind_start_e2e
##     Start a KinD cluster for Meridio e2e
KIND_TRENCHES="trench-a trench-b"
KIND_TARGETS="target-a target-b"
cmd_kind_start_e2e() {
	cmd_env
	cmd_kind_stop_e2e > /dev/null 2>&1
	local helmdir=$MERIDIOD/deployments/helm
	test "$__multus" = "yes" && helmdir=$MERIDIOD/deployments/helm-multus
	cmd_kind_start_nsm

	local t vlanid=100 ns=red
	kubectl="kubectl -n $ns"

	for t in $KIND_TRENCHES; do
		cmd_kind_start_gw $t > /dev/null
		helm_install $helmdir --generate-name \
			--create-namespace --namespace $ns --set trench.name=$t \
			--set vlan.id=$vlanid --set ipFamily=dualstack
		vlanid=$((vlanid + 100))
	done
	for t in $KIND_TRENCHES; do
		test_statefulset ipam-$t 120 > /dev/null
		test_statefulset nsp-$t 120 > /dev/null
		test_deployment load-balancer-$t 120 > /dev/null
		test "$__multus" != "yes" && test_deployment nse-vlan-$t 120 > /dev/null
		test_daemonset proxy-$t 120 > /dev/null
	done

	for t in $KIND_TARGETS; do
		local tn=$(echo $t | sed -e 's,target,trench,')
		helm_install meridio-$t $MERIDIOD/examples/target/deployments/helm/ \
			--create-namespace --namespace $ns --set applicationName=$t \
			--set default.trench.name=$tn
	done
	for t in $KIND_TARGETS; do
		test_deployment $t 120 > /dev/null
	done
}
##   kind_stop_e2e
##     Stop a KinD cluster and docker GWs
cmd_kind_stop_e2e() {
	cmd_kind_stop > /dev/null 2>&1
	docker kill trench-a trench-b trench-c > /dev/null 2>&1
	docker rm trench-a trench-b trench-c > /dev/null 2>&1
}
##   kind_e2e [--no-stop]
##     Run Meridio e2e in KinD using the Makefile
cmd_kind_e2e() {
	local start now
	start=$(date +%s)
	cmd_kind_stop_e2e
	cmd_kind_start_e2e
	cd $MERIDIOD
	make e2e || die "make e2e"
	test "$__no_stop" != "yes" && cmd_kind_stop_e2e
	now=$(date +%s)
	echo "Execution time; $((now-start))s"
}
##   e2e [ginkgo-params...]
##     Run Meridio e2e dualstack tests. $FOCUS and $SKIP can be set.
##     Example;
##       ft e2e -v -no-color -dry-run
##       FOCUS='IngressTraffic.*TCP-IPv' ft e2e
cmd_e2e() {
	cmd_env
	local d params
	d=$MERIDIOD/test/e2e

	# Original from $d/environment/kind-helm/dualstack/config.txt
	params=$(grep -v '^#' $dir/kind/data/config.txt)
	out=/tmp/$USER/e2e
	rm -r $out; mkdir -p $out
	ginkgo $@ --output-dir=$out -focus="$FOCUS" -skip="$SKIP" $d/... -- \
		-traffic-generator-cmd="$me generator {trench}" \
		-script=$d/environment/kind-helm/dualstack/test.sh $params
}
cmd_generator() {
	test -n "$GENERATOR_CMD" || GENERATOR_CMD='docker exec -i'
	local cmd="$GENERATOR_CMD $@"
	echo $cmd >> /tmp/$USER/e2e/generator.log
	exec $cmd
}
##   install_e2e
##     Install Meridio for e2e using tunnels
cmd_install_e2e() {
	cmd_env
	local helmdir=$MERIDIOD/deployments/helm-tunnel
	local t ns=red

	for t in trench-a; do
		helm_install meridio-$t $helmdir \
			--create-namespace --namespace $ns --set trench.name=$t
	done
	for t in trench-a; do
		test_statefulset ipam-$t 120 > /dev/null
		test_statefulset nsp-$t 120 > /dev/null
	done

	for t in target-a; do
		local tn=$(echo $t | sed -e 's,target,trench,')
		helm_install meridio-$t $MERIDIOD/examples/target/deployments/helm/ \
			--create-namespace --namespace $ns --set applicationName=$t \
			--set default.trench.name=$tn
	done
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
	__targets="stateless-lb proxy tapa ipam nsp frontend"

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
	done
	#cmds="$cmds $MERIDIOD/examples/target/..."
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
	if test "$__no_target" != "yes"; then
		cd $MERIDIOD/examples/target
		CGO_ENABLED=0 GOOS=linux go build -o $__out \
			-ldflags "-extldflags -static -X main.version=$gitver" \
			./... || die "go build examples/target"
	fi
	strip $__out/*
}

##   build_base_image
##     Build the base image
cmd_build_base_image() {
	cmd_env
	local base=$(grep base_image= $dir/images/Dockerfile.default | cut -d= -f2)
	log "Building base image [$base]"
	local health_probe=$ARCHIVE/grpc_health_probe-linux-amd64
	test -r $health_probe || die "Not readable [$health_probe]"
	local dockerfile=$dir/images/Dockerfile.base
	mkdir -p $tmp/bin
	cp $health_probe $tmp/bin/grpc_health_probe
	chmod a+x $tmp/bin/grpc_health_probe
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
	test -n "$__nfqlb" || __nfqlb=1.1.3

	for n in frontend ipam stateless-lb nsp proxy tapa; do
		x=$__out/$n
		test -x $x || die "Not built [$x]"
		rm -rf $tmp; mkdir -p $tmp/root
		cp $x $tmp/root
		if test "$n" = "stateless-lb"; then
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

	for n in frontend ipam stateless-lb nsp proxy tapa; do
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
##   build_gwimage
##     A GW container used in Meridio e2e tests
cmd_build_gwimage() {
	test -n "$NFQLB_DIR" || NFQLB_DIR=$HOME/tmp/nfqlb
	test -x $NFQLB_DIR/bin/ipu || die "Not executable [$NFQLB_DIR/bin/ipu]"
	test -n "$__registry" || __registry=registry.nordix.org/cloud-native/meridio
	test -n "$__version" || __version=local
	local images=$($XCLUSTER ovld images)/images.sh
	test -x $images || dir "Can't find ovl/images/images.sh"

	rm -rf $tmp; mkdir -p $tmp/root $tmp/usr/bin
	cp $dir/images/gw/meridiogw.sh $tmp/root
	cp $NFQLB_DIR/bin/ipu $tmp/usr/bin
	findar ctraffic.gz || die "Findar ctraffic.gz"
	gzip -dc $ar > $tmp/usr/bin/ctraffic; chmod a+x $tmp/usr/bin/ctraffic
	findar mconnect.xz || die "Findar mconnect.xz"
	xz -dc $ar > $tmp/usr/bin/mconnect; chmod a+x $tmp/usr/bin/mconnect
	
	local dockerfile=$dir/images/Dockerfile.gw
	sed -e "s,/start-command,/meridiogw.sh," < $dockerfile > $tmp/Dockerfile
	docker build -t $__registry/meridiogw:$__version $tmp \
		|| die "docker build meridiogw"
	$images lreg_upload --strip-host $__registry/meridiogw:$__version
}
##   build_init_image
##     Build the meridio init image
cmd_build_init_image() {
	cmd_env
	test -n "$__version" || __version=local
	$MERIDIOD/hack/build.sh init_image --version=$__version || die
	local images=$($XCLUSTER ovld images)/images.sh
	local img=registry.nordix.org/cloud-native/meridio/init
	$images lreg_upload --strip-host $img:$__version
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

##   test start_empty
##     Start an empty cluster
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
	test "$__use_multus" = "yes" && __exconnect=multus  # Backward compatinility
	test -n "$__exconnect" && export __exconnect
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
	test "$__exconnect" = "multus" && otc 1 multus_setup
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
##   test start_dhcp
##     Start cluster with DHCP/SLAAC address allocation for FEs.
##     Multus is enforced.
test_start_dhcp() {
	__exconnect=multus
	unset __bgp
	test_start dhcp
	otcw cni_dhcp_start
}

##   test start_e2e
##     Start cluster with NSM and prepare for e2e or helm load
test_start_e2e() {
	test -n "$__trenches" || __trenches="a b"
	export __e2e=yes
	export xcluster_NSM_NAMESPACE=nsm
	test_start
	test "$__exconnect" = "multus" && \
		kubectl apply -f $dir/default/etc/kubernetes/multus/crd-meridio.yaml
	otc 202 "setup_vlan --tag=100 eth3"
	otc 202 "setup_vlan --tag=200 eth3"
	otc 202 e2e_vip_route
	local t
	for t in $__trenches; do
		otc 1 "e2e_trench --exonnect=$__exconnect $t"
		otc 1 "e2e_target $t"
	done
}

##   test [--trenches=red,...] [--exconnect=] [--bgp] trench (default)
##     Test trenches. The default is to test all 3 trenches
##     Problems has been observed "after some time" so if
##     "--reconnect-delay=sec" is specified the Re-test connectivity
##     is delayed.
test_trench() {
	test -n "$__trenches" || __trenches=red,blue,green
	tlog "=== Test trenches [$__trenches]"
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
	cmd_env
	test -n "$__exconnect" || __exconnect=vlan
	case $__exconnect in
		multus)
			case $1 in
				red|pink)
					otcw "local_vlan --bridge=mbr1 --tag=100 eth2";;
				blue)
					otcw "local_vlan --tag=200 eth2";;
				green)
					otcw "local_vlan --tag=100 eth3";;
				black)
					otc 202 "setup_vlan64 --tag=100 --prefix=fd00:100: eth3"
					otc 202 "radvd_start --prefix=fd00:100: eth3.100"
					otc 202 "dhcpd eth3.100"
					otcw "local_vlan --bridge=mbr1 --tag=100 eth2"
					otc 1 "deploy_trench --exconnect=multus $1"
					return;;
				*) tdie "Invalid trench [$1]";;
			esac
			otc 202 "setup_vlan $1"
			otc 1 "deploy_trench --exconnect=$__exconnect $1";;
		tunnel)
			otc 1 "deploy_trench --exconnect=$__exconnect $1"
			otc 202 "setup_tunnel $1";;
		vlan)
			otc 202 "setup_vlan $1"
			otc 1 "deploy_trench --exconnect=$__exconnect $1";;
		*)
			tdie "Invalid exconnect [$__exconnect]"
	esac
	otc 1 "check_trench $1"
}

trench_test() {
	cmd_add_trench $1
	if test -z "$__bgp"; then
		otc 202 "collect_lb_addresses --prefix=$__prefix $1"
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
		red|black)
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
		pink)
			otc 202 "mconnect_adr 10.0.0.4:$__port"
			otc 202 "mconnect_adr [1000::1:10.0.0.4]:$__port"
			otc 202 "mconnect_adr 10.0.0.64:$__port"
			otc 202 "mconnect_adr [1000::1:10.0.0.64]:$__port"
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

##   test [--no-start] e2e
##     Run the Meridio e2e suite
test_e2e() {
	tlog "=== Meridio e2e"
	test -n "$__e2elog" && rm -f "$__e2elog"
	test "$__no_start" != "yes" && test_start_e2e
	otc 202 "mconnect_adr 20.0.0.1:4000"
	otc 202 "mconnect_adr [2000::1]:4000"
	$dir/kind/data/test.sh init
	cd $MERIDIOD
	make TRAFFIC_GENERATOR_CMD="$me generator_cmd" \
		E2E_SCRIPT="$dir/kind/data/test.sh" e2e 1>&2 || tdie "make e2e"
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
##   test dhcp
##     Test with addresses via DHCP/SLAAC to FEs (multus enforced)
test_dhcp() {
	tlog "Test with addresses via DHCP/SLAAC to FEs (multus enforced)"
	test_start_dhcp
	__prefix=fd00:100:
	trench_test black
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
