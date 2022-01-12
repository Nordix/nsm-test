# Xcluster/ovl - nsm-ovs

NSM with [forwarder-ovs](https://github.com/networkservicemesh/cmd-forwarder-ovs).

The same network-setup as for [ovl/nsm-vlan-dpdk](../nsm-vlan-dpdk) is used;

<img src="../nsm-vlan-dpdk/multilan.svg" alt="NSM network-topology" width="70%" />


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

Automatic test;
```
#export xcluster_NSM_FORWARDER=vpp  # "ovs" is default
./nsm-ovs.sh test > $log
```


## Troubleshoot

```
pod=$(kubectl get pods -l app=forwarder-ovs -o name | head -1)
kubectl exec -it $pod -- sh
ovs-vsctl show
ovs-appctl dpctl/show
```

