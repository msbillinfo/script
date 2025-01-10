#!/bin/bash

# 定义路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"  # 脚本所在目录
AZURE_DNS_SCRIPT="/root/azure_dns.sh"
CHECK_IP_SCRIPT="/root/check_ip.sh"
CONFIG_FILE="/root/azure_dns_config.env"
LOG_FILE="/root/check_ip.log"  # 日志和 IP 信息统一文件

# 定义 cron 任务
CRON_TASK="* * * * * /root/check_ip.sh"

# 下载脚本内容
download_scripts() {
    echo "$(date) - Downloading scripts..." | tee -a "$LOG_FILE"

    # 下载 azure_dns.sh
    cat > "$AZURE_DNS_SCRIPT" <<'EOF'
#!/bin/bash

CONFIG_FILE="/root/azure_dns_config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件不存在，请先添加变量。"
    exit 1
fi

source "$CONFIG_FILE"

CURRENT_IP=$(curl -s ifconfig.me)
if [[ "$CURRENT_IP" == *":"* ]]; then
    CURRENT_IP=$(curl -s ipv4.ifconfig.me)
fi

ACCESS_TOKEN=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials" | jq -r '.access_token')

AZURE_IP=$(curl -s -X GET "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/dnsZones/$DNS_ZONE/A/$RECORD_NAME?api-version=2018-05-01" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.properties.ARecords[0].ipv4Address')

if [ "$CURRENT_IP" == "$AZURE_IP" ]; then
    echo "No update needed. Current IP: $CURRENT_IP" >> "$LOG_FILE"
    exit 0
fi

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

echo "DNS record updated to IP: $CURRENT_IP" >> "$LOG_FILE"
EOF

    # 下载 check_ip.sh
    cat > "$CHECK_IP_SCRIPT" <<EOF
#!/bin/bash

LOG_FILE="/root/check_ip.log"
IP_SERVICES=(
  "https://api.ipify.org"
  "https://ipecho.net/plain"
  "https://checkip.amazonaws.com"
  "https://icanhazip.com"
)

for SERVICE in "\${IP_SERVICES[@]}"; do
  CURRENT_IP=\$(curl -s4 "\$SERVICE")
  if [ ! -z "\$CURRENT_IP" ]; then
    echo "\$(date) - Retrieved IP: \$CURRENT_IP" >> "\$LOG_FILE"
    break
  fi
done

if [ -z "\$CURRENT_IP" ]; then
  echo "\$(date) - Failed to retrieve IP. Exiting." >> "\$LOG_FILE"
  exit 1
fi

LAST_IP=\$(grep -oP '(?<=Current IP: ).*' "\$LOG_FILE" | tail -n 1)

if [ "\$CURRENT_IP" != "\$LAST_IP" ]; then
  echo "\$(date) - IP changed to \$CURRENT_IP. Running /root/azure_dns.sh..." >> "\$LOG_FILE"
  /root/azure_dns.sh
  echo "\$(date) - IP updated to \$CURRENT_IP" >> "\$LOG_FILE"
else
  echo "\$(date) - No IP change." >> "\$LOG_FILE"
fi
EOF

    chmod +x "$AZURE_DNS_SCRIPT" "$CHECK_IP_SCRIPT"
    echo "$(date) - Scripts downloaded and permissions set." >> "$LOG_FILE"
}

# 添加或修改变量
manage_variables() {
    echo "1. 添加变量"
    echo "2. 修改变量"
    read -p "请选择操作: " CHOICE

    if [ "$CHOICE" == "1" ]; then
        echo "添加以下变量："
        read -p "CLIENT_ID: " CLIENT_ID
        read -p "CLIENT_SECRET: " CLIENT_SECRET
        read -p "TENANT_ID: " TENANT_ID
        read -p "SUBSCRIPTION_ID: " SUBSCRIPTION_ID
        read -p "RESOURCE_GROUP: " RESOURCE_GROUP
        read -p "DNS_ZONE: " DNS_ZONE
        read -p "RECORD_NAME: " RECORD_NAME
        read -p "TTL (默认 300): " TTL
        TTL=${TTL:-300}
        cat > "$CONFIG_FILE" <<EOF
CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET
TENANT_ID=$TENANT_ID
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RESOURCE_GROUP=$RESOURCE_GROUP
DNS_ZONE=$DNS_ZONE
RECORD_NAME=$RECORD_NAME
TTL=$TTL
EOF
        echo "变量已添加并保存到 $CONFIG_FILE。" >> "$LOG_FILE"
    elif [ "$CHOICE" == "2" ]; then
        nano "$CONFIG_FILE"
        echo "$(date) - 变量已修改。" >> "$LOG_FILE"
    else
        echo "无效选项。"
    fi
}

# 管理 cron 任务
manage_cron() {
    echo "1. 添加 cron 任务"
    echo "2. 删除 cron 任务"
    read -p "请选择操作: " CHOICE

    if [ "$CHOICE" == "1" ]; then
        (crontab -l 2>/dev/null; echo "$CRON_TASK") | crontab -
        echo "$(date) - Cron 任务已添加。" >> "$LOG_FILE"
    elif [ "$CHOICE" == "2" ]; then
        crontab -l | grep -v "$CHECK_IP_SCRIPT" | crontab -
        echo "$(date) - Cron 任务已删除。" >> "$LOG_FILE"
    else
        echo "无效选项。"
    fi
}

# 菜单
while true; do
    echo "1. 下载并设置脚本"
    echo "2. 管理变量"
    echo "3. 管理 cron 任务"
    echo "4. 退出"
    read -p "请选择操作: " CHOICE

    case $CHOICE in
    1) download_scripts ;;
    2) manage_variables ;;
    3) manage_cron ;;
    4) echo "退出脚本管理器。"; exit 0 ;;
    *) echo "无效选项，请重新选择。" ;;
    esac
done
