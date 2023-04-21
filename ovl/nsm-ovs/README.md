# Xcluster/ovl - nsm-ovs

Originally this ovl was a test of the 
[forwarder-ovs](https://github.com/networkservicemesh/cmd-forwarder-ovs)
(hence the name), but it has become a generic ovl for NSM start, test and build.

The same network-setup as for [ovl/nsm-vlan-dpdk](../nsm-vlan-dpdk) is used;

<img src="../nsm-vlan-dpdk/multilan.svg" alt="NSM network-topology" width="70%" />


Most (all?) forwarder-ovs examples in NSM says that sr-iov is required,
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

Prepare:
```bash
images lreg_preload k8s-pv
images lreg_preload spire
images lreg_preload nsm-ovs
#images lreg_preload k8s-cni-calico
cdo ovs
./ovs.sh build
```

Basic test;
```
#export xcluster_NSM_FORWARDER=vpp  # "ovs" is default
#export xcluster_HOST_OVS=yes       # Use ovs on the host
#export xcluster_NSM_NAMESPACE=nsm
./nsm-ovs.sh test > $log
# Or use locally built images (see below);
./nsm-ovs.sh test --local > $log
# Or;
__local=yes __nvm=4 xcadmin k8s_test --cni=calico nsm-ovs > $log
# Optional (takes some time because of timeouts)
./nsm-ovs.sh test udp > $log
```

The tests starts `spire` and the NSM base (nsmgr and registry). Then a
forwarder and NSE is selected based on the `xcluster_NSM_FORWARDER`
variable. The NSC is the same regardless of the forwarder/nse.

Interface `nsm-1` is setup in all NSC PODs and `ping` is
tested between all PODs internally. A vlan tag=100 is setup on router
`vm-202` and ping is tested externally (note that `eth3` on vm-202 is
`eth2` on the VMs). Then intern and extern TCP traffic is tested.

The `forwarder-ovs` start ovs itself by default. This may be
undesirable and it can use the ovs on the host instead. This requires
another image and slightly different configuration. In xcluster you
can use `export xcluster_HOST_OVS=yes`.



### Usage from another ovl

Ovl's that uses NSM *should* use `nsm-ovs` and the `xcluster` test
system for NSM start. This will isolate NSM problems and simplify NSM
(and spire) trouble-shooting. Example;

```
test_start() {
 ...
 xcluster_start network-topology spire k8s-pv nsm-ovs ...
 ...
 otcprog=spire_test
 otc 1 start_spire_registrar
 otcprog=nsm-ovs_test
 otc 1 start_nsm
 otc 1 start_forwarder
 test "$xcluster_NSM_FORWARDER" = "vpp" && otc 1 vpp_version
 unset otcprog
 ...
}
```

## Build

Until NSM release images exists they should be built locally.

```
# Check a remote branches;
cd $GOPATH/src/github.com/networkservicemesh/cmd-nsmgr
git branch -a
cdo nsm-ovs
./nsm-ovs.sh build_nsm --branch=release/v1.1.1
```

The manifests are taken from the
[deployments-k8s](https://github.com/networkservicemesh/deployments-k8s)
NSM repo with minor adaptations for `xcluster`.


## Troubleshoot

```
pod=$(kubectl get pods -l app=forwarder-ovs -o name | head -1)
kubectl exec -it $pod -- sh
ovs-vsctl show
ovs-appctl dpctl/show
pod=$(kubectl get pods -l app=nsc-vlan -o name | head -1)
kubectl exec -it $pod -- sh
ifconfig
```

### The virtio cksum problem

When a `virtio` nic is used, which is the default in `xcluster`, tcp
cksums are incorrect if tx-checksumming is on. The packets are read by
vpp (with an AF_PACKET socket) and passed on to PODs. The packets are
rejected by the PODs due to incorrect tcp cksum.

#### Work-around 1

Set `ethtool -K eth3 tx off` in `vm-202` (this is set by scripts). This
will force the kernel to calculate tcp cksums.

#### Work-around 2

Use an emulated HW-NIC instead of `virtio`. This can be tested with;
```
. ./Envsettings
```
