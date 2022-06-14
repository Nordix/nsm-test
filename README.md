# nsm-test

A common place for documentation and code for testing
[NSM](https://www.networkservicemesh.io/).

## Doc

* [Build nsm components locally](doc/localbuild.md)
* [OVS based forwarder for NSM next-gen](doc/ovs-forwarder.md)
* [NSM p2mp demo](doc/ovs-nsm-p2mp.pdf)

## Xcluster ovls

Overlays for test with [xcluster](https://github.com/Nordix/xcluster)
are found in the [ovl](ovl) directory.

Extend your $XCLUSTER_OVLPATH;
```bash
export XCLUSTER_OVLPATH=$GOPATH/src/github.com/Nordix/nsm-test/ovl:$XCLUSTER_OVLPATH
```
