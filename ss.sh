#!/bin/bash
echo 'net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq' > /etc/sysctl.conf
sysctl -p
wget --no-check-certificate https://raw.githubusercontent.com/teddysun/shadowsocks_install/master/shadowsocksR.sh
chmod +x shadowsocksR.sh
./shadowsocksR.sh
echo '{
    "server":"0.0.0.0",
    "server_ipv6":"[::]",
    "server_port":2333,
    "local_address":"127.0.0.1",
    "local_port":1080,
    "password":"8888",
    "timeout":120,
    "method":"aes-256-cfb",
    "protocol":"auth_sha1_v4",
    "protocol_param":"",
    "obfs":"plain",
    "obfs_param":"",
    "redirect":"",
    "dns_ipv6":false,
    "fast_open":false,
    "workers":1
}' > /etc/shadowsocks.json
/etc/init.d/shadowsocks restart
