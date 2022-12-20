# Xcluster/ovl - forwarder-test

Tests of Meridio in [xcluster](https://github.com/Nordix/xcluster).
Originally this ovl was testing different NSM forwarders only, but it
has evolved to generic e2e.

The [ovl/nsm-ovs](https://github.com/Nordix/nsm-test/tree/master/ovl/nsm-ovs)
is used for NSM setup and the same network setup is used;

<img src="https://raw.githubusercontent.com/Nordix/nsm-test/master/ovl/nsm-vlan-dpdk/multilan.svg" alt="NSM network-topology" width="70%" />

Three trenches are defined;
```
Trench:  vm iface:     vm-202 iface:  Net:                 VIP:
red      eth2.100      eth3.100       169.254.101.0/24     10.0.0.1
blue     eth2.200      eth3.200       169.254.102.0/24     10.0.0.2
green    eth3.100      eth4.100       169.254.103.0/24     10.0.0.3

Add "1000::1" for ipv6, e.g. 169.254.101.0/24 -> 1000::1:169.254.101.0/120
```


## Usage

Prerequisites;

* A [ctraffic](https://github.com/Nordix/ctraffic) release must be downloaded.
* The `$MERIDIOD` must point at the Meridio source, default
  "$GOPATH/src/github.com/Nordix/Meridio"

A local registry is *required* (even for KinD). Pre-load if necessary;
```
images lreg_preload k8s-pv
images lreg_preload spire
images lreg_preload nsm-ovs
images lreg_preload ./default
```

Start xcluster with NSM only;
```
./forwarder-test.sh test start > $log
# Or;
#images lreg_preload k8s-cni-calico
xcadmin k8s_test --cni=calico forwarder-test start > $log
```

### Meridio e2e

Meridio e2e uses Kubernetes-in-Docker [KinD](https://kind.sigs.k8s.io).
KinD shall be started in the main netns on your host (not in an xcluster netns).

Build Meridio;
```
eval $(./forwarder-test.sh env | grep MERIDIOD)
private_reg=$(./forwarder-test.sh private_reg --localhost)
cd $MERIDIOD
#make REGISTRY=$private_reg/cloud-native/meridio IMAGES=base-image
#make REGISTRY=$private_reg/cloud-native/meridio IMAGES=example-target
make REGISTRY=$private_reg/cloud-native/meridio \
  IMAGES="stateless-lb proxy tapa ipam nsp frontend"
```
Note the added "cloud-native/" compared to the default registry.

Run e2e;
```
#./forwarder-test.sh build_gwimage
./forwarder-test.sh kind_e2e
```

### OVS forwarder

To use `forwarder-ovs` ovs must be started on the node. This is done
by [ovl/ovs](https://github.com/Nordix/xcluster/tree/master/ovl/ovs)
which in turn needs a locally build kernel.

```
#xc kernel_build   # (if needed)
cdo ovs
./ovs.sh build
# Now forwarder-ovs can be used by Meridio;
cdo forwarder-test
xcluster_NSM_FORWARDER=ovs ./forwarder-test.sh test --trenches=red > $log
```

#### [WIP] OVS forwarder in KinD

**Work in progress!**

Since the `forwarder-ovs` is unprepared for one OvS instance that spans
multiple K8s nodes (as it does in KinD) we must start one single worker.

* Remove one worker in `kind/meridio.yaml`

* Alter vpp->ovs for the image in `docs/demo/deployments/nsm/values.yaml`

Start KinD and manually start ovs;
```
./forwarder-test.sh kind_start
./forwarder-test.sh kind_install_ovs
./forwarder-test.sh kind_sh worker
# On "worker"
SYSTEM_ID=$(cat /etc/machine-id)
mkdir -p /etc/openvswitch
echo $SYSTEM_ID > /etc/openvswitch/system-id.conf
ovsdb-tool create /etc/openvswitch/conf.db /usr/local/share/openvswitch/vswitch.ovsschema
/usr/local/share/openvswitch/scripts/ovs-ctl --system-id=$SYSTEM_ID start
# Back
./forwarder-test.sh kind_start_nsm --no-kind-start
```




## Tests

Simplified Meridio images are used (tag ":local"). The Meridio source
is supposed to be in "$MERIDIOD" which defaults to
`$GOPATH/src/github.com/Nordix/Meridio`. A local `go` is required;

```
#export MERIDIOVER=local  # (the default)
./forwarder-test.sh build_base_image
./forwarder-test.sh build_images
./forwarder-test.sh build_app_image
```

The default test ("trench") starts three trenches and test external
connectivity from `vm-202` using [mconnect](https://github.com/Nordix/mconnect).

```
#images lreg_preload .               # Load local registry if necessary
#export xcluster_NSM_FORWARDER=ovs   # default "vpp"
./forwarder-test.sh  # Help printout
./forwarder-test.sh test > $log
# Or
xcadmin k8s_test --cni=calico forwarder-test --trenches=red > $log
```

Variations;
```
# Use multus to add external interfaces in the FE;
./forwarder-test.sh test --trenches=red --use-multus > $log
# Use BGP (Bird) instead of static routing in the FE
./forwarder-test.sh test --trenches=red --bgp > $log
# Combinations are OK;
./forwarder-test.sh test --trenches=red --use-multus --bgp > $log
```

A problem in the past (that may resurface) is that the NSM setup
"degenerates" after some time. To test this an extra connection test
can be executed after some time;

```
./forwarder-test.sh test --trenches=red --reconnect-delay=120 > $log
```


### Scaling test

The scaling is tested by changing the `replica` count for the targets
and by disconnect/reconnect targets from the stream. An optional `--cnt`
parameter can be set to repeat the disconnect/reconnect test.

```
./forwarder-test.sh test --cnt=5 scale > $log
```


### Port NAT tests

Port NAT is supported in [Meridio](
https://github.com/Nordix/Meridio/blob/master/docs/port-nat.md)
and can be tested with;

```
./forwarder-test.sh test port_nat_basic > $log
./forwarder-test.sh test port_nat_vip > $log
```


## Meridio setup

Meridio is started with K8s manifests. Helm charts or the
`Meridio-Operator` are *not* used. The helm-charts are used as base
for the manifests and base manifests can be generated with;

```
./forwarder-test.sh generate_manifests
```

The process of updating the local manifests when the helm charts
changes is not automatic, it has to be done manually.

The trenches all have different configurations and to make things
easier individual configurations are used. This it the one for trench "red";

```bash
export NAME=red
export NS=red
export CONDUIT1=load-balancer
export STREAM1=stream1
export VIP1=10.0.0.1/32
export VIP2=1000::1:10.0.0.1/128
export NSM_SERVICES="trench-red { vlan: 100; via: service.domain.2}"
export NSM_CIDR_PREFIX="169.254.101.0/24"
export NSM_IPV6_PREFIX="1000::1:169.254.101.0/120"
export NSC_NETWORK_SERVICES="kernel://trench-red/nsm-1"
export GATEWAY4=169.254.101.254
export GATEWAY6=1000::1:169.254.101.254
export POD_CIDR=172.16.0.0
```

The configuration is then used with a template to produce the final
manifest to be loaded with `kubectl`. Test manually with;

```
(. default/etc/kubernetes/forwarder-test/red.conf; \
 envsubst < default/etc/kubernetes/forwarder-test/nse-template.yaml) | less
# (the parentheses uses a sub-shall and prevents polluting your env)
```





## Multus

The external interface in the `load-balancer` POD (the `fe` POD actually)
can be injected using Multus instead of NSM with vlan. This may be
more mainstream in some deployments and gives the opportunity so use
any inteface type supported by Multus (except `ipvlan` which can't
support VIPs).

In this example the same vlan interfaces are used, e.g. `eth3.100` but
a difference is that the device must be create in main netns on the
nodes and then Multus "host-device" is used to move the interface to
the `load-balancer` POD and rename it "nsm-1".

```
./forwarder-test.sh test --exconnect=multus > $log
```

We must assign addresses to the external interface in the
`load-balancer` POD. In this example `node-local` ipam is used which
is a tiny script wrapper around `host-local`. IRL this may be DHCP or
[whereabouts](https://github.com/k8snetworkplumbingwg/whereabouts) or
something else.


## Antrea CNI-plugin and forwarder-ovs

The [Antrea](https://github.com/antrea-io/antrea) CNI-plugin uses
`ovs`. It conflicts with `forwarder-ovs`. Easiest and fastest to test
without Meridio;

```
export xcluster_NSM_FORWARDER=vpp
xcadmin k8s_test --cni=antrea forwarder-test nsm > $log  # Works
export xcluster_NSM_FORWARDER=ovs
xcadmin k8s_test --cni=antrea forwarder-test nsm > $log  # FAILS!
xcadmin k8s_test --cni=calico forwarder-test nsm > $log  # Works
```

There are other CNI-plugins that uses `ovs` but only `Antrea` is
currently available in `xcluster`.
