# nsm-test

A common place for documentation and code for testing
[NSM](https://www.networkservicemesh.io/) next-generation.

## Doc

* [Build nsm components locally](doc/localbuild.md)

## Xcluster ovls

Overlays for test with [xcluster](https://github.com/Nordix/xcluster)
are found in the [./ovl](ovl) directory.

Extend your $XCLUSTER_OVLPATH;
```bash
export XCLUSTER_OVLPATH=$GOPATH/src/github.com/Nordix/nsm-test/ovl:$XCLUSTER_OVLPATH
```
