#!/bin/bash

# 脚本配置
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/azure_dns_config.env"
readonly LOG_FILE="${SCRIPT_DIR}/azure_dns.log"
readonly LOCK_FILE="${SCRIPT_DIR}/.azure_dns.lock"
readonly CRON_TASK="* * * * * ${SCRIPT_DIR}/check_ip.sh"

# 下载的辅助脚本路径
readonly AZURE_DNS_SCRIPT="${SCRIPT_DIR}/azure.sh"
readonly CHECK_IP_SCRIPT="${SCRIPT_DIR}/check_ip.sh"

# 日志函数
log() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    log "ERROR" "$1"
    [ -f "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
    exit 1
}

# 检查依赖
check_dependencies() {
    local deps=(curl jq nano)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            handle_error "缺少依赖: $dep，请先安装"
        fi
    done
}

# 函数：下载辅助脚本
download_scripts() {
    log "INFO" "开始下载脚本..."

    # Azure DNS 更新脚本
    cat > "$AZURE_DNS_SCRIPT" << 'EOFINNER1'
#!/bin/bash

set -euo pipefail

CONFIG_FILE="$(dirname "$0")/azure_dns_config.env"
LOCK_FILE="$(dirname "$0")/.azure_dns.lock"
LOG_FILE="$(dirname "$0")/azure_dns.log"

# 日志函数
log() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "$LOG_FILE"
}

# IP服务列表
IP_SERVICES=(
    "https://api.ipify.org"
    "https://ipecho.net/plain"
    "https://checkip.amazonaws.com"
    "https://icanhazip.com"
)

# 获取当前IP
get_current_ip() {
    local ip
    for service in "${IP_SERVICES[@]}"; do
        ip=$(curl -s4 --connect-timeout 5 "$service")
        if [[ -n "$ip" && ! "$ip" =~ [^0-9.] ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

# 主逻辑
main() {
    # 检查配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "配置文件不存在"
        exit 1
    fi

    # 加载配置
    source "$CONFIG_FILE"

    # 获取当前IP
    CURRENT_IP=$(get_current_ip)
    if [ -z "$CURRENT_IP" ]; then
        log "ERROR" "无法获取当前IP地址"
        exit 1
    fi

    # 获取访问令牌
    local access_token
    access_token=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "scope=https://management.azure.com/.default" \
        -d "grant_type=client_credentials" | jq -r '.access_token')

    if [ -z "$access_token" ] || [ "$access_token" == "null" ]; then
        log "ERROR" "获取Azure访问令牌失败"
        exit 1
    fi

    # 获取当前DNS记录
    local azure_ip
    azure_ip=$(curl -s -X GET "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/dnsZones/$DNS_ZONE/A/$RECORD_NAME?api-version=2018-05-01" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" | jq -r '.properties.ARecords[0].ipv4Address')

    # 检查是否需要更新
    if [ "$CURRENT_IP" == "$azure_ip" ]; then
        log "INFO" "IP无需更新: $CURRENT_IP"
        return 0
    fi

    # 准备更新负载
    local update_payload
    update_payload=$(cat << EOF
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

    # 更新DNS记录
    local response
    response=$(curl -s -w "%{http_code}" -X PUT "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/dnsZones/$DNS_ZONE/A/$RECORD_NAME?api-version=2018-05-01" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$update_payload")

    if [ "$response" -ne 200 ]; then
        log "ERROR" "更新DNS记录失败，HTTP状态码: $response"
        exit 1
    fi

    log "INFO" "DNS记录已更新: $CURRENT_IP"
}

# 运行主函数
(
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        log "WARNING" "另一个实例正在运行"
        exit 1
    fi

    trap 'rm -rf "$LOCK_FILE"' EXIT
    main
)
EOFINNER1

    # IP检查脚本
    cat > "$CHECK_IP_SCRIPT" << 'EOFINNER2'
#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/azure_dns.log"
LAST_IP_FILE="${SCRIPT_DIR}/.last_ip"

# 日志函数
log() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "$LOG_FILE"
}

# IP服务列表
IP_SERVICES=(
    "https://api.ipify.org"
    "https://ipecho.net/plain"
    "https://checkip.amazonaws.com"
    "https://icanhazip.com"
)

# 获取当前IP
get_current_ip() {
    local ip
    for service in "${IP_SERVICES[@]}"; do
        ip=$(curl -s4 --connect-timeout 5 "$service")
        if [[ -n "$ip" && ! "$ip" =~ [^0-9.] ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

# 主逻辑
main() {
    local current_ip
    current_ip=$(get_current_ip)
    
    if [ -z "$current_ip" ]; then
        log "ERROR" "无法获取当前IP地址"
        exit 1
    fi

    # 检查是否需要更新
    if [ -f "$LAST_IP_FILE" ]; then
        local last_ip
        last_ip=$(cat "$LAST_IP_FILE")
        if [ "$current_ip" == "$last_ip" ]; then
            log "INFO" "IP未变更: $current_ip"
            exit 0
        fi
    fi

    # 更新DNS记录
    if "${SCRIPT_DIR}/azure.sh"; then
        echo "$current_ip" > "$LAST_IP_FILE"
        log "INFO" "IP已更新: $current_ip"
    else
        log "ERROR" "更新DNS记录失败"
        exit 1
    fi
}

# 运行主函数
main
EOFINNER2

    chmod +x "$AZURE_DNS_SCRIPT" "$CHECK_IP_SCRIPT"
    log "INFO" "脚本下载完成，权限已设置"
}

# 函数：验证配置
validate_config() {
    local required_vars=("CLIENT_ID" "CLIENT_SECRET" "TENANT_ID" "SUBSCRIPTION_ID" 
                        "RESOURCE_GROUP" "DNS_ZONE" "RECORD_NAME")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        handle_error "缺少必要的配置变量: ${missing_vars[*]}"
    fi
}

# 函数：管理变量
manage_variables() {
    echo "1. 添加/更新变量"
    echo "2. 查看当前配置"
    read -p "请选择操作: " choice

    case $choice in
        1)
            read -p "CLIENT_ID: " CLIENT_ID
            read -p "CLIENT_SECRET: " CLIENT_SECRET
            read -p "TENANT_ID: " TENANT_ID
            read -p "SUBSCRIPTION_ID: " SUBSCRIPTION_ID
            read -p "RESOURCE_GROUP: " RESOURCE_GROUP
            read -p "DNS_ZONE: " DNS_ZONE
            read -p "RECORD_NAME: " RECORD_NAME
            read -p "TTL [300]: " TTL
            TTL=${TTL:-300}

            # 验证输入
            validate_config

            # 保存配置
            cat > "$CONFIG_FILE" << EOF
CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET
TENANT_ID=$TENANT_ID
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RESOURCE_GROUP=$RESOURCE_GROUP
DNS_ZONE=$DNS_ZONE
RECORD_NAME=$RECORD_NAME
TTL=$TTL
EOF
            log "INFO" "配置已保存至 $CONFIG_FILE"
            ;;
        2)
            if [ -f "$CONFIG_FILE" ]; then
                echo "当前配置:"
                grep -v "SECRET" "$CONFIG_FILE"
                echo "CLIENT_SECRET=********"
            else
                log "WARNING" "配置文件不存在"
            fi
            ;;
        *)
            log "WARNING" "无效选项"
            ;;
    esac
}

# 函数：管理Cron任务
manage_cron() {
    echo "1. 添加cron任务 (每1分钟检查)"
    echo "2. 删除cron任务"
    read -p "请选择操作: " choice

    case $choice in
        1)
            if ! crontab -l 2>/dev/null | grep -q "$CHECK_IP_SCRIPT"; then
                (crontab -l 2>/dev/null; echo "$CRON_TASK") | crontab -
                log "INFO" "Cron任务已添加"
            else
                log "WARNING" "Cron任务已存在"
            fi
            ;;
        2)
            crontab -l 2>/dev/null | grep -v "$CHECK_IP_SCRIPT" | crontab -
            log "INFO" "Cron任务已删除"
            ;;
        *)
            log "WARNING" "无效选项"
            ;;
    esac
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n=== Azure DNS动态更新管理器 ==="
        echo "1. 下载并设置脚本"
        echo "2. 管理配置"
        echo "3. 管理定时任务"
        echo "4. 查看日志"
        echo "5. 退出"
        
        read -p "请选择操作 [1-5]: " choice
        
        case $choice in
            1) check_dependencies && download_scripts ;;
            2) manage_variables ;;
            3) manage_cron ;;
            4) tail -n 50 "$LOG_FILE" ;;
            5) log "INFO" "退出脚本管理器"; exit 0 ;;
            *) log "WARNING" "无效选项，请重新选择" ;;
        esac
    done
}

# 创建必要的目录和文件
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# 启动主菜单
main_menu
