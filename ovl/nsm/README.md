# nsm-test ovl - nsm

Network Service Mesh [NSM](https://networkservicemesh.io/)
([github](https://github.com/networkservicemesh/networkservicemesh/))
next-generation in xcluster.


## Refresh local image cache
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

## Usage with the test system;

```
#export xcluster_NSM_FORWARDER=generic
#export xcluster_NSM_NSE=generic
#export xcluster_NSM_FORWARDER_CALLOUT=/bin/forwarder.sh
log=/tmp/$USER/xcluster.log
export __get_logs=yes
xcadmin k8s_test --no-stop nsm basic_nextgen > $log
# Login and investigate things, e.g. kubectl logs ...
# Investigate logs;
./nsm.sh readlog /tmp/$USER/nsm-logs/nsmgr-local.log | less
```

## Build local image

```
x=cmd-nsc
cd $GOPATH/src/github.com/networkservicemesh/$x
docker build --target=runtime --tag=registry.nordix.org/cloud-native/nsm/$x:latest .
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/$x:latest
```
