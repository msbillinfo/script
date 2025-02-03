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
echo "请选择要修改外部 IP 地址的虚拟机（用空格分隔多选，例如：1 2 3）："
while IFS= read -r line; do
    VM_ARRAY+=("$line")
    NAME=$(echo $line | awk '{print $1}')
    ZONE=$(echo $line | awk '{print $2}')
    echo "$i) $NAME ($ZONE)"
    ((i++))
done <<< "$VM_LIST"

# 让用户选择虚拟机
read -p "输入对应的虚拟机序号: " -a VM_INDEXES

# 选择网络层级
echo "请选择新的网络类型:"
echo "1) 标准层级的网络"
echo "2) 普通层级"
read -p "输入对应的选项 (1 或 2): " NETWORK_TYPE

# 根据用户选择的网络层级设置相应的值
if [ "$NETWORK_TYPE" -eq 1 ]; then
    NETWORK_TIER="STANDARD"
elif [ "$NETWORK_TYPE" -eq 2 ]; then
    NETWORK_TIER="PREMIUM"
else
    echo "无效的选择，使用普通层级。"
    NETWORK_TIER="PREMIUM"
fi

# 遍历选择的虚拟机序号并执行 IP 更换操作
for INDEX in "${VM_INDEXES[@]}"; do
    if ! [[ "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -lt 1 ] || [ "$INDEX" -gt "${#VM_ARRAY[@]}" ]; then
        echo "无效的虚拟机序号: $INDEX，跳过。"
        continue
    fi

    # 获取用户选择的虚拟机名称和区域
    SELECTED_VM="${VM_ARRAY[$((INDEX-1))]}"
    INSTANCE_NAME=$(echo $SELECTED_VM | awk '{print $1}')
    ZONE=$(echo $SELECTED_VM | awk '{print $2}')

    echo "正在处理虚拟机: $INSTANCE_NAME (区域: $ZONE)"

    # 获取当前外部 IP 地址并显示
    CURRENT_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
    echo "当前外部 IP 地址: $CURRENT_IP"

    # 获取当前的访问配置名称
    ACCESS_CONFIG_NAME=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].name)")
    
    # 删除当前的外部访问配置
    echo "正在删除外部访问配置..."
    gcloud compute instances delete-access-config $INSTANCE_NAME \
        --access-config-name="$ACCESS_CONFIG_NAME" \
        --zone=$ZONE

    # 添加新的外部访问配置
    echo "正在添加新的外部访问配置 (网络层级: $NETWORK_TIER)..."
    gcloud compute instances add-access-config $INSTANCE_NAME \
        --zone=$ZONE \
        --access-config-name="$ACCESS_CONFIG_NAME" \
        --network-tier="$NETWORK_TIER"

    # 获取并显示新的外部 IP 地址
    NEW_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
    echo "新外部 IP 地址: $NEW_IP"
    echo "---------------------------------------"
done

echo "所有选择的虚拟机外部 IP 地址更换完毕。"
