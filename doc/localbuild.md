# Build nsm components locally

General build;
```
x=cmd-forwarder-vpp
cd $GOPATH/src/github.com/networkservicemesh/$x
docker build --target=runtime --tag=registry.nordix.org/cloud-native/nsm/$x:latest .
# Upload to the xcluster local registry if needed;
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/$x:latest
```

## Use local SDKs

The problem is that the SDKs are not taken from your local versions
and that's where most of the code is.

You must add a "replace" section in `go.mod`, example;

```
replace (
  github.com/networkservicemesh/sdk-vpp => /home/uablrek/go/src/github.com/networkservicemesh/sdk-vpp
)
```

Now you can build the component with a local sdk;
```
# In cmd-forwarder-vpp;
go build -o forwarder .
```

But you can't build the image because your local sdk does not exist in
the docker "build" container.

```
docker build --target=runtime --tag=registry.nordix.org/cloud-native/nsm/cmd-forwarder-vpp:latest .
...
go: github.com/networkservicemesh/sdk-vpp@v0.0.0-20210224165530-9431fc53d3c2: parsing /home/uablrek/go/src/github.com/networkservicemesh/sdk-vpp/go.mod: open /home/uablrek/go/src/github.com/networkservicemesh/sdk-vpp/go.mod: no such file or directory
The command '/bin/sh -c go build ./internal/imports' returned a non-zero code: 1
```

You want to use your already-built component not build it again in the
non-working docker container. So...

First build the component statically since you can't know that all
libraries exist in the final image;

```
CGO_ENABLED=0 GOOS=linux go build -ldflags "-extldflags '-static'" -o forwarder .
strip forwarder
```

Now you must create a `Dockerfile` that takes your local build
component as-is. Use the existing and remove everything except the
"runtime" target. Modify the `COPY` command to take your local built
component. Here is an example for cmd-forwarder-vpp;

```
ARG VPP_VERSION=v20.09
FROM ghcr.io/edwarnicke/govpp/vpp:${VPP_VERSION} as runtime
COPY forwarder /bin/forwarder
CMD /bin/forwarder
```

Then build as usual;
```
cp Dockerfile Dockerfile.local
vi Dockerfile.local  # Remove all except "runtime" targets
x=cmd-forwarder-vpp
docker build --target=runtime --tag=registry.nordix.org/cloud-native/nsm/$x:latest -f Dockerfile.local .
```
