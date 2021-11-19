# Build nsm components for vpp forwarder with remote vlan mechanism support

This description details the steps of building components locally from source using local API and SDKs.

## Building VPP Forwarder

- Clone the `nsm-cmd-forwarder-vpp` from Nordix and select the `vlansup-dev` development branch.

```bash
git clone git@github.com:Nordix/nsm-cmd-forwarder-vpp.git
cd nsm-cmd-forwarder-vpp
git checkout vlansup-dev
```

- Clone `nsm-sdk-kernel` from Nordix to `local` subdirectory and checkout the `vlansup-dev` development branch. Build the source

```bash
cd local
git clone git@github.com:Nordix/nsm-sdk-kernel.git
cd nsm-sdk-kernel
git checkout vlansup-dev
go build ./...
cd ..
```

- Clone `nsm-sdk-vpp` from Nordix to `local` subdirectory and checkout the `vlansup-dev` development branch.

```bash
git clone git@github.com:Nordix/nsm-sdk-vpp.git
cd nsm-sdk-vpp
git checkout vlansup-dev
```

- Modify the go.mod file for `nsm-sdk-vpp` to use `nsm-sdk-kernel` cloned locally. Build this source.

```go
# slice of go.mod file
replace (
  github.com/networkservicemesh/sdk-kernel => ../nsm-sdk-kernel
)
```

```bash
go build ./...
cd ../..
```

- Modify the go.mod file for `nsm-cmd-forwarder-vpp` to use the modules from `local` directory. Build the source and the docker image.

```go
# slice of go.mod file
replace (
  github.com/networkservicemesh/sdk-kernel => ./local/nsm-sdk-kernel
  github.com/networkservicemesh/sdk-vpp => ./local/nsm-sdk-vpp
)
```

To build the image run the following command:

```bash
go build ./...
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-forwarder-vpp:vlansup .
```

- Upload to the local registry (optional)

```bash
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-forwarder-vpp:vlansup
```

### Configure VPP Forwarder

To use VLAN tagging a base interface must be specified. A new way of configuration of base interface is supported by mapping 'via' labels to interface names. The NSE configures the 'via' label and sends it in response to connection request to the forwarder. The forwarder selects the interface based on this label by mapping it to the interface name.

```yaml
# sample Device Selector File used by forwarder-vpp
interfaces:
  - name: eth2
    matches:
       - labelSelector:
           - via: gw1
  - name: eth3
    matches:
       - labelSelector:
           - via: gw2
  - name: eth4
    matches:
       - labelSelector:
           - via: gw3

```

The path to the 'Device Selector' configuration file is set by `NSM_DEVICE_SELECTOR_FILE` environment variable in VPP forwarder.

## Building NSE Element With Remote VLAN Mechanism Support

- Clone the `nsm-nse-generic` from Nordix and select the `vlansup-dev` development branch.

```bash
git clone git@github.com:Nordix/nsm-nse-generic.git
cd nsm-nse-generic
git checkout vlansup-dev
```

- Build the source and the docker image.

```bash
go build ./...
docker build . --tag registry.nordix.org/cloud-native/nsm/cmd-nse-vlan:vlansup
```

 Upload to the local registry (optional)

```bash
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-nse-vlan:vlansup
```

### Configure NSE

The NSE in this setup belong to control plain of NSM and playing multiple roles;

- The NSE as a registry - regiser itself directly to the registry service. The URL of registry service can be set by `NSM_CONNECT_TO` environment variable. Example; "nsm-registry-svc:5002"

- The NSE as nsmgr and forwarder - replies directly to the connection requests coming from local or remote forwarders. The URL (with port) to be listen on can be set by `NSM_LISTEN_ON` environment variable. Example; "tcp://:5003" The port used in this URL must be set in the manifest of the NSE pod. Example:

```yaml
apiVersion: apps/v1
kind: Deployment
...
spec:
  ...
  template:
    ...
    spec:
      containers:
      - name: nse
           ports:
            - containerPort: 5003
              hostPort: 5003
              ...     
```

- The NSE as IPAM provider - can be configured with the `NSM_CIDR_PREFIX` and `NSM_IPV6_PREFIX` environment variables.

- The NSE as service provider - provides multiple services for NSC to connect to. The list of supported services can be set by `NSM_SERVICES` environment variable. Example; "finance-bridge { vlan: 100; via: gw1 }, finance-bridge { vlan: 200; via: gw2 }, shadow-gw { vlan: 1200; via: gw2 }" The service specified by "finance-bridge { vlan: 100; via: gw1 }" in this example has the service name "finance-bridge" and the label via="gw-1".
NSC can request for a service using the service name in its `NSM_NETWORK_SERVICES` environment variable (Example; "kernel://finance-bridge/nsm-1"). The forwarder can select a base interface for the 'via' label based on its mapping (see section [Configure VPP Forwarder](https://github.com/Nordix/nsm-test/blob/master/doc/vpp-forwarder-vlansup-build.md#configure-vpp-forwarder))
