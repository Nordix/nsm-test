# nsm-test ovl - nsm

Network Service Mesh [NSM](https://networkservicemesh.io/)
([github](https://github.com/networkservicemesh/networkservicemesh/))
next-generation in xcluster.

## Variables

Some variables affects the setup. These may be set manually for some
tests but other tests may need a defined forwarder and will set the
variables.


```
# The forwarder to use. Values; vpp|generic|generic-vlan. Default; vpp
export xcluster_NSM_FORWARDER=generic

# The NSE to use; Values; icmp-responder|generic. Default; icmp-responder
export xcluster_NSM_NSE=generic

# The callout script if NSM_FORWARDER=generic or NSM_FORWARDER=generic-vlan is used.
# Values; (varies); Default; /bin/forwarder.sh
export xcluster_NSM_FORWARDER_CALLOUT=/bin/forwarder.sh
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

```
log=/tmp/$USER/xcluster.log
xcadmin k8s_test nsm vlan > $log
# Scale
kubectl scale deployment/nsc --replicas=9
# Check the interfaces and vlanID
for pod in $(kubectl get pods -l app=nsc -o name); do kubectl exec $pod -- ip address show nsm-1 > ~/tmp_file; inet=$(grep -oE '169\.254\.0\.[0-9]+' ~/tmp_file); echo "NSC $pod; nsm-1, $inet"; rm ~/tmp_file; done
for pod in $(kubectl get pods -l app=nsc -o name); do echo "NSC $pod"; kubectl exec $pod -- tail -1 /proc/net/vlan/config; done
```

Interfaces are checked on NSC and the NSE. On NSE should not be injected any
interface.


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

Local built image;
```
x=cmd-nsc
cd $GOPATH/src/github.com/networkservicemesh/$x
docker build --target=runtime --tag=registry.nordix.org/cloud-native/nsm/$x:latest .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/$x:latest
```


