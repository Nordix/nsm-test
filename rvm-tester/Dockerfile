FROM networkstatic/iperf3

RUN apt-get update \
    && apt-get install -y iproute2 ethtool tcpdump ncat telnet procps psmisc\
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT [ "tail", "-f", "/dev/null" ]
