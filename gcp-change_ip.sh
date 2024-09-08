#!/bin/bash

# 获取所有虚拟机实例名称和区域，并保存到数组中
echo "正在获取所有虚拟机实例列表..."
VM_LIST=$(gcloud compute instances list --format="value(name,zone)")

# 检查是否有虚拟机存在
if [[ -z "$VM_LIST" ]]; then
    echo "没有找到任何虚拟机实例。"
    exit 1
fi

# 将虚拟机列表存储在数组中
declare -a VM_ARRAY=()
i=1
echo "请选择要修改外部 IP 地址的虚拟机："
while IFS= read -r line; do
    VM_ARRAY+=("$line")
    NAME=$(echo $line | awk '{print $1}')
    ZONE=$(echo $line | awk '{print $2}')
    echo "$i) $NAME ($ZONE)"
    ((i++))
done <<< "$VM_LIST"

# 让用户选择虚拟机
read -p "输入对应的虚拟机序号: " VM_INDEX

# 检查用户输入的是否为有效的数字
if ! [[ "$VM_INDEX" =~ ^[0-9]+$ ]] || [ "$VM_INDEX" -lt 1 ] || [ "$VM_INDEX" -gt "${#VM_ARRAY[@]}" ]; then
    echo "无效的选择，请输入有效的虚拟机序号。"
    exit 1
fi

# 获取用户选择的虚拟机名称和区域
SELECTED_VM="${VM_ARRAY[$((VM_INDEX-1))]}"
INSTANCE_NAME=$(echo $SELECTED_VM | awk '{print $1}')
ZONE=$(echo $SELECTED_VM | awk '{print $2}')

echo "已选择虚拟机: $INSTANCE_NAME (区域: $ZONE)"

# 获取当前外部 IP 地址并显示
CURRENT_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
echo "当前外部 IP 地址: $CURRENT_IP"

# 删除当前外部 IP 地址
gcloud compute instances delete-access-config $INSTANCE_NAME \
    --access-config-name="External NAT" \
    --zone=$ZONE

# 添加新的外部 IP 地址
gcloud compute instances add-access-config $INSTANCE_NAME \
    --zone=$ZONE \
    --access-config-name="External NAT"

# 获取并显示新的外部 IP 地址
NEW_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
echo "新外部 IP 地址: $NEW_IP"
