# Xcluster/ovl - nsm-ovs

NSM with [forwarder-ovs](https://github.com/networkservicemesh/cmd-forwarder-ovs).

The same network-setup as for [ovl/nsm-vlan-dpdk](../nsm-vlan-dpdk) is used;

<img src="../nsm-vlan-dpdk/multilan.svg" alt="NSM network-topology" width="70%" />


Most (all?) forwarder-ovs nsm examples says that sr-iov is required,
but it is not so. Sr-iov usage is dictated by the presence of a
[SRIOVConfigFile](https://github.com/networkservicemesh/cmd-forwarder-ovs/blob/8d27622bc2233b15912ca05a6451257b2d728f39/main.go#L271-L275).

A configuration file is to map interfaces to labelSelectors is required by the forwarder;

```yaml
interfaces:
  - name: eth2
    bridge: br0
    matches:
       - labelSelector:
           - via: service.domain.2
```

The file is at `/etc/nsm/DomainConfigFileOvs` on the
nodes. `/etc/nsm/` is mounted by the forwarder POD and the file is specified with;

```yaml
            - name: NSM_L2_RESOURCE_SELECTOR_FILE
              value: /etc/nsm/DomainConfigFileOvs
```
in the forwarder manifest. This is similar with the `forwarder-vpp`
(but not exactly the same?).

The NSE defines a service based on the labelSelector;
```yaml
            - name: NSM_SERVICES
              value: "finance-bridge { vlan: 100; via: service.domain.2}"
```

The service is in turn used by the NSCs;

```yaml
            - name: NSM_NETWORK_SERVICES
              value: kernel://finance-bridge/nsm-1
```

The NSCs should not be affected by the forwading mechanism and in the
tests the same NSC can be used with `forwarder-vpp` and `forwarder-ovs`.



## Usage

Prepare [ovl/spire](https://github.com/Nordix/xcluster/tree/master/ovl/spire).

Load the local image registry;
```bash
cdo nsm-ovs
log=/tmp/$USER/xcluster.log   # (assumed to be set)
# Pre-load the local registry;
for n in $(images lreg_missingimages .); do
  images lreg_cache $n
done
# Refresh local registry (when needed);
for n in $(images getimages .); do
  images lreg_cache $n
done
```

The `forwarder-ovs` start ovs itself by default. This may be
undesirable and it can use the ovs on the host instead. This requires
another image and slightly different configuration. In xcluster you
can use `export xcluster_HOST_OVS=yes`.

The tests starts `spire` and the NSM base (nsmgr and registry). Then a
forwarder and NSE is selected based on the `xcluster_NSM_FORWARDER`
variable. The NSC is the same regardless of the forwarder/nse.

Interface `nsm-1` is setup in all NSC PODs and `ping` is
tested between all PODs internally. A vlan tag=100 is setup on router
`vm-202` and ping is tested externally (note that `eth3` on vm-202 is
`eth2` on the VMs). Then intern and extern TCP traffic is tested.


```
#export xcluster_NSM_FORWARDER=vpp  # "ovs" is default
#export xcluster_HOST_OVS=yes       # Use ovs on the host
./nsm-ovs.sh test > $log
# Or;
__nvm=4 xcadmin k8s_test --cni=calico nsm-ovs > $log
# Optional (takes some time because of timeouts)
./nsm-ovs.sh test udp > $log
```


## Build

Until NSM images exists they must be built locally.

Checkout a remote branch;
```
git branch -a
git checkout release/v1.1.1
```

```
#cd $GOPATH/src/github.com/networkservicemesh
#git clone https://github.com/networkservicemesh/cmd-nsmgr.git
cd $GOPATH/src/github.com/networkservicemesh/cmd-nsmgr
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-nsmgr:local .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-nsmgr:local

#cd $GOPATH/src/github.com/networkservicemesh
#git clone https://github.com/networkservicemesh/cmd-registry-k8s.git
cd $GOPATH/src/github.com/networkservicemesh/cmd-registry-k8s
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-registry-k8s:local .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-registry-k8s:local

#cd $GOPATH/src/github.com/networkservicemesh
#git clone https://github.com/networkservicemesh/cmd-forwarder-ovs.git
cd $GOPATH/src/github.com/networkservicemesh/cmd-forwarder-ovs
git pull
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-forwarder-ovs:local .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-forwarder-ovs:local
# use-host-ovs;
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-forwarder-host-ovs:local -f Dockerfile.use-host-ovs .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-forwarder-host-ovs:local

#cd $GOPATH/src/github.com/networkservicemesh
#git clone https://github.com/networkservicemesh/cmd-forwarder-vpp.git
cd $GOPATH/src/github.com/networkservicemesh/cmd-forwarder-vpp
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-forwarder-vpp:local .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-forwarder-vpp:local

#cd $GOPATH/src/github.com/networkservicemesh
#git clone https://github.com/networkservicemesh/cmd-nse-remote-vlan.git
cd $GOPATH/src/github.com/networkservicemesh/cmd-nse-remote-vlan
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-nse-remote-vlan:local .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-nse-remote-vlan:local

#cd $GOPATH/src/github.com/networkservicemesh
#git clone https://github.com/networkservicemesh/cmd-nsc.git
cd $GOPATH/src/github.com/networkservicemesh/cmd-nsc
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-nsc:local .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-nsc:local
```



The manifests are taken from the [deployments-k8s](https://github.com/networkservicemesh/deployments-k8s)
NSM repo with minor adaptations for `xcluster`.


## Troubleshoot

```
pod=$(kubectl get pods -l app=forwarder-ovs -o name | head -1)
kubectl exec -it $pod -- sh
ovs-vsctl show
ovs-appctl dpctl/show
```

### The virtio cksum problem

When a `virtio` nic is used, which is the default in `xcluster`, tcp
cksums are incorrect if tx-checksumming is on. The packets are read by
vpp (with an AF_PACKET socket) and passed on to PODs. The packets are
rejected by the PODs due to incorrect tcp cksum.

#### Work-around 1

Set `ethtool -K eth3 tx off` in `vm-202` (this is set by scripts). This
will force the kernel to calculate the tcp cksum.

#### Work-around 2

Use an emulated HW-NIC instead of `virtio`. This can be tested with;
```
. ./Envsettings
```
