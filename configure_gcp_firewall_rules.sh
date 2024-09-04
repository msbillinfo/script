#!/bin/bash

# 创建允许所有 IPv4 入站流量的防火墙规则
gcloud compute firewall-rules create allow-all-ingress \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=all \
    --source-ranges=0.0.0.0/0 \
    --description="Allow all inbound traffic from any IP"

# 创建允许所有 IPv4 出站流量的防火墙规则
gcloud compute firewall-rules create allow-all-egress \
    --direction=EGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=all \
    --destination-ranges=0.0.0.0/0 \
    --description="Allow all outbound traffic to any IP"

# 创建允许所有 IPv6 入站流量的防火墙规则
gcloud compute firewall-rules create allow-all-ingress-ipv6 \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=all \
    --source-ranges=::/0 \
    --description="Allow all inbound traffic from any IPv6 address"

# 创建允许所有 IPv6 出站流量的防火墙规则
gcloud compute firewall-rules create allow-all-egress-ipv6 \
    --direction=EGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=all \
    --destination-ranges=::/0 \
    --description="Allow all outbound traffic to any IPv6 address"

echo "所有防火墙规则已成功创建。"
