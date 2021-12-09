# Docker Build for Network Tests and Testing Tools

It is based on networkstatic/iperf3 and contains the following additional packages;

* tcpdump
* ncat
* telnet
* procps (for ps, kill)
* psmisc (for pkill)

## Usage

Example usage in two docker containers

Start and setup containers;

```bash
docker network create bridge-2

docker run --cap-add=NET_ADMIN --rm -d --network bridge-2 --name rvm-tester-1 registry.nordix.org/cloud-native/nsm/rvm-tester:latest tail -f /dev/null
docker exec rvm-tester-1 ip addr add 172.10.0.1/24 dev eth0

docker run --cap-add=NET_ADMIN --rm -d --network bridge-2 --name rvm-tester-2 registry.nordix.org/cloud-native/nsm/rvm-tester:latest tail -f /dev/null
docker exec rvm-tester-2 ip addr add 172.10.0.2/24 dev eth0
```

Start tcpdump;

```bash
docker exec rvm-tester-1 tcpdump -eni eth0 -s0 -vvS tcp
```

Start ncat server in another terminal;

```bash
docker exec rvm-tester-1 ncat -klv
```

Check the server with netstat;

```bash
docker exec rvm-tester-1 ss -nelp | grep ncat
```

Start the client;

```bash
docker exec -it rvm-tester-2 ncat -v 172.10.0.1
```

Type something and check the server and the tcpdump.
Stop the client by ^D and the server by ^C
Stop the containers;

```bash
docker stop rvm-tester-1
docker stop rvm-tester-2
```

## Build

```bash
docker build . -t registry.nordix.org/cloud-native/nsm/rvm-tester:latest
```
