#!/bin/bash

apt update -y && apt install -y sudo wget curl nftables irqbalance haveged chrony

echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
lsmod | grep bbr

echo "127.0.0.1 flexcdn.cn" >> /etc/hosts

bash <(wget -qO- "https://raw.githubusercontent.com/teIegraph/script/main/swap.sh")
bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/tools/main/root.sh) 258456W0zy
