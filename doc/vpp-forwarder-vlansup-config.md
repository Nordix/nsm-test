# Configuring nse and vpp forwarder to support remote vlan mechanism

This description details the configuration of [cmd-forwarder-vpp](https://github.com/networkservicemesh/cmd-forwarder-vpp) and [cmd-nse-remote-vlan](https://github.com/networkservicemesh/cmd-forwarder-vpp) components to support vlan.
The diagram below shows the relation and operation of these NSM componenets in high level.

![vrm operation](https://raw.githubusercontent.com/Nordix/nsm-test/09408bfbea6380eda201606cbfb5182a14234634/doc/vrm.svg "remote vlan mechanism in NSM")

## Configure NSE

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

- The NSE as service provider - the NSE provides multiple services for network service client. The list of supported services can be set by `NSM_SERVICES` environment variable. Example; "finance-bridge { vlan: 100; via: gw1 }, finance-bridge { vlan: 200; via: gw2 }, shadow-gw { vlan: 1200; via: gw2 }" The service specified by "finance-bridge { vlan: 100; via: gw1 }" in this example has the service name "finance-bridge" and the label via="gw-1".
NSC can request for a service using the service name in its `NSM_NETWORK_SERVICES` environment variable (Example; "kernel://finance-bridge/nsm-1"). The forwarder can select a base interface for the 'via' label based on its mapping (see next section [Configure VPP Forwarder](https://github.com/Nordix/nsm-test/blob/master/doc/vpp-forwarder-vlansup-config.md#configure-vpp-forwarder))

## Configure VPP Forwarder

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
