# Build nsm components for vpp forwarder with remote vlan mechanism support

This description details the steps of building components locally from source using local API and SDKs.

## Building VPP Forwarder

- Clone the `nsm-cmd-forwarder-vpp` from Nordix and select the `vlansup-dev` development branch.

```bash
git clone git@github.com:Nordix/nsm-cmd-forwarder-vpp.git
cd nsm-cmd-forwarder-vpp
git check-out vlansup-dev
```

- Clone `nsm-api` and `nsm-sdk-kernel` from Nordix to `local` subdirectory and checkout the `vlansup-dev` development branch. Build these sources

```bash
cd local
```

```bash
git clone git@github.com:Nordix/nsm-api.git
cd nsm-api
git check-out vlansup-dev
go build ./...
cd ..
git clone git@github.com:Nordix/nsm-sdk-kernel.git
cd nsm-sdk-kernel
git check-out vlansup-dev
go build ./...
cd ..
```

- Clone `nsm-sdk-vpp` from Nordix to `local` subdirectory and checkout the `vlansup-dev` development branch.

```bash
git clone git@github.com:Nordix/nsm-sdk-vpp.git
cd nsm-sdk-vpp
git check-out vlansup-dev
```

- Modify the go.mod file for `nsm-sdk-vpp` to use `nsm-api` and `nsm-sdk-kernel` cloned locally. Build this source.

```go
# slice of go.mod file
replace (
  github.com/networkservicemesh/sdk-kernel => ../nsm-sdk-kernel
  github.com/networkservicemesh/api => ../nsm-api
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
  github.com/networkservicemesh/api => ./local/nsm-api
  github.com/networkservicemesh/sdk-vpp => ./local/nsm-sdk-vpp
)
```

The modification to support labels for forwarder selection is optional.

```bash
go build ./...
docker build --tag registry.nordix.org/cloud-native/nsm/cmd-forwarder-vpp:fwsel0 .
```

- Upload to the local registry (optional)

```bash
images lreg_upload --strip-host registry.nordix.org/cloud-native/nsm/cmd-forwarder-vpp:fwsel0
```

### Configure VPP Forwarder

To use VLAN tagging a base interface must be specified. A new way of configuration of base interface is supported by mapping service domains to PCI addresses. The NSE configures the service domain and the forwarder selects the PCI interface based on this mapping.

```yaml
# sample DomainConfigFile used by forwarder-vpp
physicalFunctions:
  0000:04:00.0:
    pfKernelDriver: pf-driver
    vfKernelDriver: vf-driver
    capabilities:
      - default
    serviceDomains:
      - service.domain.1
  0000:00:05.0:
    pfKernelDriver: pf-driver
    vfKernelDriver: vf-driver
    capabilities:
      - default
    serviceDomains:
      - service.domain.1
      - service.domain.2
```

The path to the 'PCI to service domain' configuration file is set by `NSM_DOMAIN_CONFIG_FILE` environment variable in VPP forwarder.

## Building NSE Element With Remote VLAN Mechanism Support

- Clone the `nsm-nse-generic` from Nordix and select the `vlansup-dev` development branch.

```bash
git clone git@github.com:Nordix/nsm-nse-generic.git
cd nsm-nse-generic
git check-out vlansup-dev
```

- Clone `nsm-api` and `nsm-sdk` from Nordix to `local` subdirectory and checkout the `vlansup-dev` development branch. Build these sources

```bash
git clone git@github.com:Nordix/nsm-api.git
cd nsm-api
git check-out vlansup-dev
go build ./...
cd ..
git clone git@github.com:Nordix/nsm-sdk.git
cd nsm-sdk
git check-out vlansup-dev
go build ./...
cd ..
```

- Modify the go.mod file for `nsm-nse-generic` to use the modules from `local` directory. Build the source and the docker image.

```go
# slice of go.mod file
replace (
  github.com/networkservicemesh/sdk => ./local/nsm-sdk
  github.com/networkservicemesh/api => ./local/nsm-api
)
```

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

- The NSE as a registry regiser itself directly to the registry service. The URL of registry service can be set by `NSM_CONNECT_TO` environment variable. Example; "nsm-registry-svc:5002"

- The NSE as nsmgr and forwarder replies directly to the connection requests coming from local or remote forwarders. The URL (with port) to be listen on can be set by `NSM_LISTEN_ON` environment variable. Example; "tcp://:5003" The port used in this URL must be set in the manifest of the NSE pod. Example:

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

- The NSE as IPAM provider can be configured with the `NSM_CIDR_PREFIX` and `NSM_IPV6_PREFIX` environment variables.

- The NSE as service provider provides multiple services for NSC to connect to. The list of supported services can be set by `NSM_SERVICES` environment variable. Example; "finance-bridge@service-domain.2: { vlan: 100 }, finance-bridge@service-domain.2: { vlan: 200 }, shadow-gw@service-domain.3: { vlan: 1200 }" The service specified by "finance-bridge@service-domain.2: { vlan: 100 }" in this example has the service name "finance-bridge" and the network service domain "service-domain.2".
NSC can request for a service using the service name by using this service name in its `NSM_NETWORK_SERVICES` environment variable ("kernel://finance-bridge/nsm-1"). The forwarder can select a base interface for the network service domain based on its mapping (see #Configure-VPP-Forwarder)
