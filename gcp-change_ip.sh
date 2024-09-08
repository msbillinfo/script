#!/bin/bash

# 提示用户输入实例名称和区域
read -p "请输入实例名称: " INSTANCE_NAME
read -p "请输入实例区域 (如 asia-east1-a): " ZONE

# 获取当前外部 IP 地址并保存
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
