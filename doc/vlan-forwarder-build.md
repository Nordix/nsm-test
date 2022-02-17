# (DEPRECATED) Build nsm components for vlan forwarder using vlan mechanism

This description details the steps of building components locally from source using local API and SDK.

## Local SDK and API

Clone nsm-api and nsm-sk-kernel from Nordix. The location of the local clone may be important for building the cloned project.

- Clone and build nsm-api;
```
git clone git@github.com:Nordix/nsm-api.git
cd nsm-api
git checkout vlan-forwarder
go build ./...
```
- Clone and build nsm-sdk;
```
git clone git@github.com:Nordix/nsm-sdk.git
cd nsm-sdk
git checkout vlan-forwarder
go build ./...
```
- Clone nsm-sdk-kernel;
```
git clone git@github.com:Nordix/nsm-sdk-kernel.git
cd nsm-sdk-kernel
git checkout vlan-forwarder
```

To use local nsm-api add a "replace" section in go.mod, example;

```
replace github.com/networkservicemesh/api => /home/ljkiraly/work/code/src/github.com/Nordix/nsm-api
```
- Build the sdk-kernel;
```
go build ./...
```

## Generic Vlan Forwarder

- Clone nsm-forwarder-generic repositoyr from Nordix;
```
git clone git@github.com:Nordix/nsm-forwarder-generic.git
cd nsm-forwarder-generic
git checkout vlan-forwarder
```

For building the vlan forwarder also a replace section must be added to go.mod file (`cmd/nsm-forwarder-vlan/go.mod`), example;

```
replace (
  github.com/networkservicemesh/sdk-kernel => /home/ljkiraly/work/code/src/github.com/Nordix/nsm-sdk-kernel
  github.com/networkservicemesh/api => /home/ljkiraly/work/code/src/github.com/Nordix/nsm-api
)
```

Now the build can be done using local API and SDK;

```
./build.sh go --forwarder=forwarder-vlan
./build.sh image --forwarder=forwarder-vlan --tag=registry.nordix.org/cloud-native/nsm/forwarder-vlan:latest
```

## Generic NSE with VLAN Mechanism Support

Clone *nsm-nse-generic* from Nordix and check out the *vlan-forwarder* branch;

```
git clone git@github.com:Nordix/nsm-nse-generic.git
cd nsm-nse-generic 
git checkout vlan-forwarder
```

For building the generic NSE add the replace section to go.mod file (`cmd/nsm-nse-generic/go.mod`), example;

```
replace (
  github.com/networkservicemesh/sdk-kernel => /home/ljkiraly/work/code/src/github.com/Nordix/nsm-sdk-kernel
  github.com/networkservicemesh/sdk => /home/ljkiraly/work/code/src/github.com/Nordix/nsm-sdk
  github.com/networkservicemesh/api => /home/ljkiraly/work/code/src/github.com/Nordix/nsm-api
)
```

Now the build can be done using local API and SDK;

```
./build.sh go
./build.sh image --tag=registry.nordix.org/cloud-native/nsm/nse-vlan:latest
```

## NSC with VLAN Mechanism Support
Clone *nsm-cmd-nsc* repository from Nordix and check out the *vlan-forwarder* branch;
```
git clone git@github.com:Nordix/nsm-cmd-nsc.git
cd nsm-cmd-nsc
git checkout vlan-forwarder
```
Create a local directory and clone the api and sdk locally or from Nordix. Check out the *vlan-forwarder* branch in each repository. Example;
```
mkdir local
cd local
git clone -l ~/work/code/src/github.com/Nordix/nsm-api
git clone -l ~/work/code/src/github.com/Nordix/nsm-sdk-kernel
cd nsm-api
git checkout vlan-forwarder
cd ../nsm-sdk-kernel
git checkout vlan-forwarder
```

Add this replace section to go.mod file;
```
replace (
        github.com/networkservicemesh/api => ./local/nsm-api
        github.com/networkservicemesh/sdk-kernel => ./local/nsm-sdk-kernel
)
```

Patch the Dockerfile or edit manually. Add copy command of local directory to the target to be able to build the image using the local api and sdk. Example;

```
cp Dockerfile Dockerfile.local
patch -p1 Dockerfile.local << EOF
--- Dockerfile2021-04-20 17:28:19.153085061 +0200
+++ Dockerfile.local2021-04-20 17:28:50.932974261 +0200
@@ -12,2 +12,3 @@
 COPY go.mod go.sum ./
+COPY ./local ./local
 COPY ./internal/imports imports
EOF
```
Build the image;
```
docker build --target=runtime --tag=registry.nordix.org/cloud-native/nsm/cmd-nsc:latest -f Dockerfile.local .
```

Upload to the xcluster local registry if needed;
```
for x in forwarder-vlan cmd-nsc nse-vlan; do
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/$x:latest
done
```
