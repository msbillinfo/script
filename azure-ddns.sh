#!/bin/bash

# 脚本配置
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/azure_dns_config.env"
readonly LOG_FILE="${SCRIPT_DIR}/azure_dns.log"
readonly LOCK_FILE="${SCRIPT_DIR}/.azure_dns.lock"
readonly CHECK_IP_CRON="* * * * * ${SCRIPT_DIR}/check_ip.sh"
readonly CLEANUP_LOG_CRON="0 5 * * * truncate -s 0 ${SCRIPT_DIR}/azure_dns.log"


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
    echo "3. 修改配置"
    read -p "请选择操作 [1-3]: " choice

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
        3)
            if [ -f "$CONFIG_FILE" ]; then
                echo "当前配置:"
                grep -v "SECRET" "$CONFIG_FILE"
                echo "CLIENT_SECRET=********"

                # 读取配置文件
                source "$CONFIG_FILE"

                # 允许修改的配置项
                echo "请输入要修改的配置项:"
                echo "1. CLIENT_ID  (客户端 ID)"
                echo "2. CLIENT_SECRET  (客户端密钥)"
                echo "3. TENANT_ID  (租户 ID)"
                echo "4. SUBSCRIPTION_ID  (订阅 ID)"
                echo "5. RESOURCE_GROUP  (资源组)"
                echo "6. DNS_ZONE  (DNS 区域)"
                echo "7. 记录名称 (RECORD_NAME)  (DNS 记录名称)"
                echo "8. TTL  (生存时间)"
                read -p "请选择要修改的配置项 [1-8]: " var_to_modify


                # 修改相应的变量
                case $var_to_modify in
                    1)
                        read -p "新的 CLIENT_ID: " CLIENT_ID
                        ;;
                    2)
                        read -p "新的 CLIENT_SECRET: " CLIENT_SECRET
                        ;;
                    3)
                        read -p "新的 TENANT_ID: " TENANT_ID
                        ;;
                    4)
                        read -p "新的 SUBSCRIPTION_ID: " SUBSCRIPTION_ID
                        ;;
                    5)
                        read -p "新的 RESOURCE_GROUP: " RESOURCE_GROUP
                        ;;
                    6)
                        read -p "新的 DNS_ZONE: " DNS_ZONE
                        ;;
                    7)
                        read -p "新的 RECORD_NAME: " RECORD_NAME
                        ;;
                    8)
                        read -p "新的 TTL [300]: " TTL
                        TTL=${TTL:-300}
                        ;;
                    *)
                        log "WARNING" "无效的配置项"
                        return
                        ;;
                esac

                # 重新写入配置文件
                cat > "$CONFIG_FILE" << EOF
CLIENT_ID=${CLIENT_ID:-$CLIENT_ID}
CLIENT_SECRET=${CLIENT_SECRET:-$CLIENT_SECRET}
TENANT_ID=${TENANT_ID:-$TENANT_ID}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-$SUBSCRIPTION_ID}
RESOURCE_GROUP=${RESOURCE_GROUP:-$RESOURCE_GROUP}
DNS_ZONE=${DNS_ZONE:-$DNS_ZONE}
RECORD_NAME=${RECORD_NAME:-$RECORD_NAME}
TTL=${TTL:-$TTL}
EOF

                log "INFO" "配置已更新至 $CONFIG_FILE"
            else
                log "WARNING" "配置文件不存在"
            fi
            ;;
        *)
            log "WARNING" "无效选项"
            ;;
    esac
}


# 修改：管理Cron任务
manage_cron() {
    echo "1. 添加IP检查cron任务 (每1分钟检查)"
    echo "2. 添加日志清理cron任务 (每天凌晨5点清理)"
    echo "3. 删除IP检查cron任务"
    echo "4. 删除日志清理cron任务"
    echo "5. 查看所有cron任务"
    read -p "请选择操作 [1-5]: " choice

    case $choice in
        1)
            if ! crontab -l 2>/dev/null | grep -q "$CHECK_IP_SCRIPT"; then
                (crontab -l 2>/dev/null; echo "$CHECK_IP_CRON") | crontab -
                log "INFO" "IP检查Cron任务已添加"
            else
                log "WARNING" "IP检查Cron任务已存在"
            fi
            ;;
        2)
            if ! crontab -l 2>/dev/null | grep -q "truncate.*azure_dns.log"; then
                (crontab -l 2>/dev/null; echo "$CLEANUP_LOG_CRON") | crontab -
                log "INFO" "日志清理Cron任务已添加（每天凌晨5点执行）"
            else
                log "WARNING" "日志清理Cron任务已存在"
            fi
            ;;
        3)
            crontab -l 2>/dev/null | grep -v "$CHECK_IP_SCRIPT" | crontab -
            log "INFO" "IP检查Cron任务已删除"
            ;;
        4)
            crontab -l 2>/dev/null | grep -v "truncate.*azure_dns.log" | crontab -
            log "INFO" "日志清理Cron任务已删除"
            ;;
        5)
            echo "当前Cron任务列表："
            crontab -l 2>/dev/null | grep -E "$CHECK_IP_SCRIPT|azure_dns.log"
            ;;
        *)
            log "WARNING" "无效选项"
            ;;
    esac
}
clear_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        log "ERROR" "日志文件不存在"
        return 1
    fi
    
    local log_size
    log_size=$(du -sh "$LOG_FILE" | cut -f1)
    
    echo -e "日志文件当前大小: $log_size\n确定要清理日志吗? (回车默认是 y, 输入 n 取消): "
    read -r confirm
    
    # 如果用户按回车或输入y/y，则清理日志，否则取消
    if [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]]; then
        > "$LOG_FILE"
        log "INFO" "日志已清理"
    else
        log "INFO" "取消日志清理"
    fi
}

# 函数：执行 azure.sh 并返回日志 触发 DNS 更新
run_azure_script() {
    if [ -f "$AZURE_DNS_SCRIPT" ]; then
        log "INFO" "正在执行 azure.sh 脚本..."
        
        # 执行脚本并捕获输出
        output=$("$AZURE_DNS_SCRIPT" 2>&1)  # 捕获标准输出和错误输出
        echo "$output" | tee -a "$LOG_FILE"  # 输出并追加到日志文件
        
        # 如果执行失败，输出错误
        if [ $? -ne 0 ]; then
            log "ERROR" "azure.sh 脚本执行失败"
        else
            log "INFO" "azure.sh 脚本执行成功"
        fi
    else
        log "ERROR" "azure.sh 脚本不存在"
    fi
}


# 主菜单
main_menu() {
    while true; do
        echo -e "\n=== Azure DNS动态更新管理器 ==="
        echo "1. 下载并设置脚本"
        echo "2. 管理配置"
        echo "3. 管理定时任务"
        echo "4. 查看日志"
        echo "5. 清理日志"
        echo "6. 触发 DNS 更新"
        echo "7. 退出"
        
        read -p "请选择操作 [1-7]: " choice
        
        case $choice in
            1) check_dependencies && download_scripts ;;
            2) manage_variables ;;
            3) manage_cron ;;
            4) tail -n 50 "$LOG_FILE" ;;
            5) clear_logs ;;
            6) run_azure_script ;;  # 触发 DNS 更新
            7) log "INFO" "退出脚本管理器"; exit 0 ;;
            *) log "WARNING" "无效选项，请重新选择" ;;
        esac
    done
}

# 创建必要的目录和文件
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# 启动主菜单
main_menu
