#!/bin/bash

# Azure API 配置信息
CLIENT_ID="azure"      # 应用程序客户端 ID
CLIENT_SECRET="azure" # 应用程序客户端密钥
TENANT_ID="azure"      # 租户 ID
SUBSCRIPTION_ID="azure" # 订阅 ID
RESOURCE_GROUP="azure"   # 资源组名称
DNS_ZONE="azure"       # DNS 区域名称
RECORD_NAME="azure"                  # DNS 记录名称

# 配置 TTL（单位：秒）
TTL=1  # 默认为 5 分钟

# 获取当前 IP 地址，优先获取 IPv4
CURRENT_IP=$(curl -s ifconfig.me)

# 如果当前 IP 地址是 IPv6，则获取 IPv4
if [[ "$CURRENT_IP" == *":"* ]]; then
    CURRENT_IP=$(curl -s ipv4.ifconfig.me)
fi

# 获取 Azure API 访问令牌
ACCESS_TOKEN=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials" | jq -r '.access_token')

# 获取当前的 DNS 记录 IP
AZURE_IP=$(curl -s -X GET "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/dnsZones/$DNS_ZONE/A/$RECORD_NAME?api-version=2018-05-01" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.properties.ARecords[0].ipv4Address')

# 如果 IP 不变，则不更新
if [ "$CURRENT_IP" == "$AZURE_IP" ]; then
    echo "No update needed. Current IP: $CURRENT_IP"
    exit 0
fi

# 更新 DNS 记录
UPDATE_PAYLOAD=$(cat <<EOF
{
  "properties": {
    "TTL": $TTL,
    "ARecords": [
      {
        "ipv4Address": "$CURRENT_IP"
      }
    ]
  }
}
EOF
)

curl -s -X PUT "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/dnsZones/$DNS_ZONE/A/$RECORD_NAME?api-version=2018-05-01" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATE_PAYLOAD"

echo "DNS record updated to IP: $CURRENT_IP"
