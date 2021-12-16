# Xcluster/ovl - nsm-vlan-dpdk

NSM with `forwarder-vpp` with vlan support and `dpdk` enabled.

A variation of the
[multilan](https://github.com/Nordix/xcluster/tree/master/ovl/network-topology#multilan) network topology is used;

<img src="multilan.svg" alt="NSM network-topology" width="70%" />

Router `vm-202` is connected to the secondary networks.


**NOTE**; the dpdk tests requires a kernel with hw support so
  `xcluster` >= v6.1.0 must be used.


## Usage

Prepare;
```bash
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

Automatic Test;
```
# Setup vlan and ping from vm-202
./nsm-vlan-dpdk.sh test > $log
```

Check things out;
```
./nsm-vlan-dpdk.sh test --no-stop > $log
# On a vm;
cat /proc/cmdline
grep Huge /proc/meminfo
lspci
pod=$(kubectl get pods -l app=forwarder-vpp -o name | head -1)
kubectl logs $pod
kubectl exec -it $pod -- vppctl
show dpdk version
show pci
show int
show log
```


## Vlan

A mapping file interfaces->labelSelector must be provided to the
`forwarder-vpp` and passed in the `$NSM_DEVICE_SELECTOR_FILE` variable;

```
interfaces:
  - name: eth2
    matches:
       - labelSelector:
           - via: service.domain.2
```

The NSE must define a service using the domain and a vlan-tag;
```
    - name: NSM_SERVICES
      value: "finance-bridge { vlan: 100; via: service.domain.2}"
```

And finally an NSC must use the service;
```
    - name: NSM_NETWORK_SERVICES
      value: kernel://finance-bridge/nsm-1
```

## Dpdk

Vpp in the `forwarder-vpp` is started with;
```
vpp -c /etc/vpp/helper/vpp.conf
```

Dpdk is configured in the `/etc/vpp/helper/vpp.conf` file. The
`/etc/vpp/` directory i mounted in the `forwarder-vpp` pod, and the
used file is in `default/etc/vpp/helper/vpp.conf`.



### Hugepages

Dpdk requires [hugepages](https://wiki.debian.org/Hugepages).
Hugepages must be configured in `xcluster` and also in the
`forwarder-vpp` manifest to become available inside the container. Please see the [K8s documentation](https://kubernetes.io/docs/tasks/manage-hugepages/scheduling-hugepages/).


### The vfio-pci problem

Dpdk requires an [uio-driver](https://doc.dpdk.org/guides/linux_gsg/linux_drivers.html). It is configured in the `vpp` config file;
```
dpdk {
	dev 0000:00:06.0
	#uio-driver uio_pci_generic
	uio-driver vfio-pci
}
```

The recommended driver is `vfio-pci` and the normal operation is to
use `iommu`. It must be configured in the kernel cmdline with;

```
iommu=pt intel_iommu=on
```
The `intel-iommu` device must also be loaded to `qemu`
described [here](https://gist.github.com/mcastelino/e0cca2af5694ba672af8e274f5dffb47).

To configure iommu, start with;
```
./nsm-vlan-dpdk.sh test --iommu > $log
```
However this makes the `forwarder-vpp` crash. It is hard to trouble-shoot
since the dpdk logs are lost in the crash.

Instead we use vfio with `enable_unsafe_noiommu_mode=1`. Now we get
further, `forwarder-vpp` start and the nic driver is set to
`vfio-pci`, but the device is still not visible in vpp;

```
pod=$(kubectl get pods -l app=forwarder-vpp -o name | head -1)
kubectl exec -it $pod -- vppctl
show log
...
2021/11/19 14:54:13:981 notice     dpdk           EAL: Failed to open VFIO group 0
2021/11/19 14:54:13:981 notice     dpdk           EAL: 0000:00:06.0 not managed by VFIO driver, skipping
```

If we mount `/dev/vfio/` directory from host fs into the
`forwarder-vpp` container with a volumeMount in the manifest it works!

Since dpdk is polling you will see 3 of your cores on your host running at 100%.

Check interfaces in vpp;
```
pod=$(kubectl get pods -l app=forwarder-vpp -o name | head -1)
kubectl exec -it $pod -- vppctl
vpp# show int
              Name               Idx    State  MTU (L3/IP4/IP6/MPLS)     Counter          Count     
GigabitEthernet0/6/0              1     down         9000/0/0/0     
host-eth1                         4      up          1500/0/0/0     rx packets                   645
                                                                    rx bytes                  176201
                                                                    tx packets                     1
                                                                    tx bytes                      42
...
```


### The uio_pci_generic problem

In short, it doesn't work because `/dev/uio0` is created in the host
fs, not in the forwarder-vpp container fs. The mount-trick can't be
used because `/dev/uio0` is not created until the `forwarder-vpp` starts.


