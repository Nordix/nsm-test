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
(but not exectly the same?).

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

Prepare;
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

The tests starts `spire` and the NSM base (nsmgr and registry). Then a
forwarder and NSE is selected based on the `xcluster_NSM_FORWARDER`
variable. The NSC is the same regardless of the forwarder/nse.

Vlan tag=100 on `eth2` is setup in all NSC PODs and `ping` is
tested between all PODs internally. A vlan is setup on router
`vm-202` and ping is tested externally (note that `eth3` on vm-202 is
`eth2` on the VMs).


```
#export xcluster_NSM_FORWARDER=vpp  # "ovs" is default
./nsm-ovs.sh test > $log
```


## Build

Until a release image exists the forwarder-ovs and the nse must be
built locally.

```
#cd $GOPATH/src/github.com/networkservicemesh
#rm -r cmd-forwarder-ovs
#git clone --depth 1 https://github.com/networkservicemesh/cmd-forwarder-ovs.git
cd $GOPATH/src/github.com/networkservicemesh/cmd-forwarder-ovs
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-forwarder-ovs:vlansup .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-forwarder-ovs:vlansup
```

```
#cd $GOPATH/src/github.com/networkservicemesh
#rm -r cmd-nse-remote-vlan
#git clone --depth 1 https://github.com/networkservicemesh/cmd-nse-remote-vlan.git
cd $GOPATH/src/github.com/networkservicemesh/cmd-nse-remote-vlan
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-nse-remote-vlan:vlansup .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-nse-remote-vlan:vlansup
```




## Troubleshoot

```
pod=$(kubectl get pods -l app=forwarder-ovs -o name | head -1)
kubectl exec -it $pod -- sh
ovs-vsctl show
ovs-appctl dpctl/show
```

