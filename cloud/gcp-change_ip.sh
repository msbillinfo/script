#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 重置颜色

# 初始化
set -eo pipefail
trap "echo -e '${RED}脚本被中断！${NC}'; exit 1" INT

#--------- 功能函数定义 ---------#

# 显示带颜色的状态消息
status_msg() {
  local type="$1"
  local msg="$2"
  case "$type" in
    info) echo -e "${BLUE}▶ ${msg}...${NC}" ;;
    success) echo -e "${GREEN}✓ ${msg}成功！${NC}" ;;
    warning) echo -e "${YELLOW}⚠ ${msg}${NC}" ;;
    error) echo -e "${RED}✗ ${msg}失败！${NC}" >&2 ;;
  esac
}

# 获取虚拟机列表
get_vm_list() {
  status_msg info "正在获取虚拟机实例列表"
  gcloud compute instances list --format="value(name,zone)" || {
    status_msg error "无法获取虚拟机列表"
    exit 1
  }
}

# 显示虚拟机选择菜单
show_vm_menu() {
  declare -n vm_array=$1
  local i=1
  echo -e "${BLUE}请选择要修改外部 IP 地址的虚拟机：${NC}"
  for vm in "${vm_array[@]}"; do
    IFS=' ' read -r name zone <<< "$vm"
    echo "$i) $name ($zone)"
    ((i++))
  done
  echo -e "${YELLOW}提示：可多选，用空格分隔（例如：1 2 3）${NC}"
}

# 验证用户输入
validate_input() {
  local input=$1
  local max=$2
  [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "$max" ]
}

# 更换实例IP
change_instance_ip() {
  local instance_name=$1
  local zone=$2
  local network_tier=$3

  status_msg info "正在处理实例 $instance_name ($zone)"

  # 获取当前配置
  local current_ip=$(gcloud compute instances describe "$instance_name" \
    --zone="$zone" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
  
  local access_config_name=$(gcloud compute instances describe "$instance_name" \
    --zone="$zone" \
    --format="value(networkInterfaces[0].accessConfigs[0].name)")

  echo -e "当前外部 IP: ${BLUE}$current_ip${NC}"

  # 删除旧配置
  status_msg info "正在删除旧的外部访问配置"
  gcloud compute instances delete-access-config "$instance_name" \
    --zone="$zone" \
    --access-config-name="$access_config_name"

  # 添加新配置
  status_msg info "正在添加新的外部访问配置"
  gcloud compute instances add-access-config "$instance_name" \
    --zone="$zone" \
    --access-config-name="$access_config_name" \
    --network-tier="$network_tier"

  # 验证新IP
  local new_ip=$(gcloud compute instances describe "$instance_name" \
    --zone="$zone" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
  
  echo -e "新外部 IP: ${GREEN}$new_ip${NC}"
  echo "---------------------------------------"
}

#--------- 主逻辑流程 ---------#

# 获取并显示虚拟机列表
vm_list=$(get_vm_list)
if [[ -z "$vm_list" ]]; then
  status_msg warning "没有找到任何虚拟机实例"
  exit 0
fi

# 将列表存入数组
declare -a vm_array=()
while IFS= read -r line; do
  vm_array+=("$line")
done <<< "$vm_list"

# 显示选择菜单
show_vm_menu vm_array

# 获取用户选择
read -p "输入对应的虚拟机序号: " -a selected_indexes

# 网络层级选择
echo -e "${BLUE}请选择新的网络类型：${NC}"
echo "1) 标准层级 (STANDARD)"
echo "2) 高级层级 (PREMIUM)"
read -p "输入选项 (默认 2): " network_type

case "$network_type" in
  1) network_tier="STANDARD" ;;
  2|*) network_tier="PREMIUM" ;;
esac

# 处理选择的实例
for index in "${selected_indexes[@]}"; do
  if ! validate_input "$index" "${#vm_array[@]}"; then
    status_msg warning "无效的序号: $index，跳过"
    continue
  fi

  selected_vm="${vm_array[$((index-1))]}"
  IFS=' ' read -r instance_name zone <<< "$selected_vm"
  
  change_instance_ip "$instance_name" "$zone" "$network_tier"
done

status_msg success "所有选择的虚拟机外部 IP 地址更换完毕"
