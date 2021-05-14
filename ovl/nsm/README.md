# nsm-test ovl - nsm

Network Service Mesh [NSM](https://networkservicemesh.io/)
([github](https://github.com/networkservicemesh/networkservicemesh/))
next-generation in xcluster.

## Variables

Some variables affects the setup. These may be set manually for some
tests but other tests may need a defined forwarder and will set the
variables.


```
# The forwarder to use. Values; vpp|generic|generic-vlan|kernel. Default; vpp
export xcluster_NSM_FORWARDER=generic

# The NSE to use; Values; icmp-responder|generic. Default; icmp-responder
export xcluster_NSM_NSE=generic

# The callout script if NSM_FORWARDER=generic or NSM_FORWARDER=generic-vlan is used.
# Values; (varies); Default; /bin/forwarder.sh
export xcluster_NSM_FORWARDER_CALLOUT=/bin/forwarder.sh

# The forwarder preferred by nsc to handle the service request.
# Values; vpp|generic|kernel. Default; not set
export xcluster_NSM_SELECT_FORWARDER=generic

# The forwarder preferred by nse to handle the service request.
# Values; vpp|generic|kernel. Default; not set
export xcluster_NSM_NSE_SELECT_FORWARDER=generic
```

## Tests

Secondary networks are supposed to be used so the
[multilan](https://github.com/Nordix/xcluster/tree/master/ovl/network-topology#multilan)
network topology is used.

Always run a regression test before push;
```
xcadmin k8s_test nsm > $log
```

### Basic test

```
log=/tmp/$USER/xcluster.log
xcadmin k8s_test --no-stop nsm basic > $log
# Login and investigate things, e.g. kubectl logs ...
# Investigate logs;
./nsm.sh get_logs
./nsm.sh readlog /tmp/$USER/nsm-logs/nsmgr-local.log | less
```

Setup NSM and start a NSC on vm-002 and a NSE on vm-003. Injected
interfaces are checked and a simple ping nsc->nse is tested.

### IPVLAN test

```
log=/tmp/$USER/xcluster.log
xcadmin k8s_test nsm ipvlan > $log
# Scale
pods -l app=nsc
kubectl scale deployment/nsc --replicas=9
```

Setup NSM and start NSE and 10xNSC as a deployment with `replicas:
10`. IPVLAN on `eth3` connects all NSC's and the NSE in a fully mesh
L2 network. Interfaces are checked and ping from the NSE to all 10
NSC's is tested.

### VLAN test

Setup NSM and start a NSC on vm-002 and a NSE on vm-003. Interfaces are checked
on NSC and the NSE. On NSE should not be injected any interface.

#### Using generic forwarder;

```
log=/tmp/$USER/xcluster.log
xcadmin k8s_test nsm vlan_generic > $log
```

#### Vlan forwarder;

```
log=/tmp/$USER/xcluster.log
xcadmin k8s_test nsm vlan > $log
```

#### To check the interfaces and vlanID manually;

```
for pod in $(kubectl get pods -l app=nsc -o name); do kubectl exec $pod -- ip address show nsm-1 > ~/tmp_file; inet=$(grep -oE '169\.254\.0\.[0-9]+' ~/tmp_file); echo "NSC $pod; nsm-1, $inet"; rm ~/tmp_file; done
for pod in $(kubectl get pods -l app=nsc -o name); do echo "NSC $pod"; kubectl exec $pod -- tail -1 /proc/net/vlan/config; done
```


## Load the local registry

Refresh from registry.nordix.org;
```
images lreg_missingimages default/
for x in cmd-nsmgr cmd-nsc cmd-registry-memory cmd-nse-icmp-responder \
  cmd-forwarder-vpp; do
  images lreg_cache registry.nordix.org/cloud-native/nsm/$x:latest
done
for x in wait-for-it:latest \
  spire-agent:0.10.0 spire-server:0.10.0; do
  images lreg_cache gcr.io/spiffe-io/$x
done
```

Additional images for vlan forwarder test;
```
images lreg_cache registry.nordix.org/cloud-native/nsm/forwarder-vlan:latest
xtag=vlan-0.2
images lreg_cache registry.nordix.org/cloud-native/nsm/nse-generic:$xtag
```

Local built image;
```
x=cmd-nsc
cd $GOPATH/src/github.com/networkservicemesh/$x
docker build --target=runtime --tag=registry.nordix.org/cloud-native/nsm/$x:latest .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/$x:latest
```
For building vlan forwarder and required components see [Build nsm components for vlan forwarder using vlan mechanism](../../doc/vlan-forwarder-build.md)


## Data plane (forwarder) selection 

Until upstream introduces support to select a forwarder when running with multiple forwarders, a temporary
forwarder selection implementation can be used.

Requirements:

- NSMgr:
	- NSC label based selection: `registry.nordix.org/cloud-native/nsm/cmd-nsmgr:fwsel0`  
	(Or build locally using a modified nsm sdk: https://github.com/Nordix/nsm-sdk/tree/forwarder-select)
	- NSC or NSE label based selection (NSC has priority): `registry.nordix.org/cloud-native/nsm/cmd-nsmgr:fwsel1`  
	(Or build locally using a modified nsm sdk: https://github.com/Nordix/nsm-sdk/tree/nse-forwarder-select)
- Forwarder:
	- Built to both parse `NSM_LABELS` env variables and send them during registration to nsmgr  
	(vpp forwarder: `registry.nordix.org/cloud-native/nsm/cmd-forwarder-vpp:fwsel0`)
	- Modified manifest file using `NSM_LABELS` to identify the forwarder
- NSC: Modified manifest file using labels either through `NSM_LABELS` or through `NSM_NETWORK_SERVICES` to
select a forwarder for the service request. (Have to match all labels of a forwarder to be selected.)  
- NSE: Modified manifest file using labels through `NSE_LABELS` to select a forwarder.  
(Only applicable when using NSMgr alternate where NSE labels are also considered. Takes effect in case no NSC 
labels are present for the service request.)

Using an up to date version of nsm-test ensures that proper docker images of nsmgr (tag: `fwsel1`) and forwarder-vpp 
(tag: `fwsel0`) are used, while providing tuned nsmgr.yaml and forwarder-vpp.yaml files to support forwarder selection.

Also, an up to date nsm-forwarder-generic repository contains manifest files extended with NSM_LABELS for both
the generic and kernel forwarders, and the forwarder codes are updated so that they can utilize forwarder selection.
(The forwarder images have to be built manually, unless they are made available by someone.)

By default forwarder manifest files have one label with key `forwarder` and value `forwarder-[type]` (e.g: forwarder-vpp, forwarder-kernel).

In case (for whatever reason) NSMgr fails to select a forwarder based on labels, then it will fallback to
its legacy behaviour, that is it will pick the forwarder who registered first. 

#### Examples

Set preferred forwarder in NSC (the test modifies the deployed nsc manifest based on this):

```
export xcluster_NSM_SELECT_FORWARDER=generic
```

Run test starting multiple forwarders (vpp, generic and kernel), and set preference in nsc:

```
export xcluster_NSM_SELECT_FORWARDER=generic
log=/tmp/$USER/xcluster.log
xcadmin k8s_test --no-stop nsm multi > $log
```

Run test starting vpp forwarder:

```
export xcluster_NSM_FORWARDER=vpp
export xcluster_NSM_SELECT_FORWARDER=vpp
log=/tmp/$USER/xcluster.log
xcadmin k8s_test --no-stop nsm basic > $log
```

Set preferred forwarder only in NSE (the test modifies the deployed nse manifest based on this):
```
export xcluster_NSM_NSE_SELECT_FORWARDER=generic
```

Run test starting multiple forwarders, and set preference in nse:

```
export xcluster_NSM_NSE_SELECT_FORWARDER=generic
log=/tmp/$USER/xcluster.log
xcadmin k8s_test --no-stop nsm multi > $log
```

Run test starting multiple forwarders, and set preference both in nsc and nse:

```
export xcluster_NSM_SELECT_FORWARDER=vpp
# nse labels will be ignored as nsc preference prevails
export xcluster_NSM_NSE_SELECT_FORWARDER=generic
log=/tmp/$USER/xcluster.log
xcadmin k8s_test --no-stop nsm multi > $log
```

Notes:  
- Check NSM_NETWORK_SERVICES label in nsc manifest (e.g. kernel://icmp-responder/nsm-1?forwarder=forwarder-vpp)
- Check NSE_LABELS in nse manifest (e.g. value: forwarder:forwarder-generic)
- Based on nsc container's logs the path of the service request can be checked.
- On the other hand look for `interposeCandidateServer` logs in nsmgr to see if the request matched any forwarders.

#### Code changes in a forwarder

To support forwarder selection in case of a _new_ forwarder, the following changes have to be implemented
(if not present).

```go
type Config struct {
    Name             string            `default:"forwarder" desc:"Name of Endpoint"`
    NSName           string            `default:"xconnectns" desc:"Name of Network Service to Register with Registry"`
    TunnelIP         net.IP            `desc:"IP to use for tunnels" split_words:"true"`
    ConnectTo        url.URL           `default:"unix:///connect.to.socket" desc:"url to connect to" split_words:"true"`
    MaxTokenLifetime time.Duration     `default:"24h" desc:"maximum lifetime of tokens" split_words:"true"`
+   Labels           map[string]string `default:"" desc:"Endpoint labels"`
}


    _, err = registryClient.Register(ctx, &registryapi.NetworkServiceEndpoint{
            Name:                config.Name,
            NetworkServiceNames: []string{config.NSName},
            Url:            listenOn.String(),
            ExpirationTime: expireTime,
+           NetworkServiceLabels: map[string]*registryapi.NetworkServiceLabels{
+               config.NSName: {
+                   Labels: config.Labels,
+               },
+           },
    })

```

