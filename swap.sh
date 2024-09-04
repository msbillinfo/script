#!/bin/bash

# 设置Swap文件的大小
SWAP_SIZE=512M

# 设置Swap文件的路径
SWAP_FILE=/swapfile

# 检查是否root用户运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以root身份运行" 1>&2
   exit 1
fi

# 检查Swap文件是否已存在
if [ -f "$SWAP_FILE" ]; then
    echo "Swap文件已存在。" 1>&2
    exit 1
fi

# 创建Swap文件
fallocate -l $SWAP_SIZE $SWAP_FILE || {
    echo "创建Swap文件失败。" 1>&2
    exit 1
}

# 设置Swap文件的权限
chmod 600 $SWAP_FILE

# 设置Swap空间
mkswap $SWAP_FILE

# 启用Swap空间
swapon $SWAP_FILE

# 使Swap自动挂载（通过将其添加到fstab中）
echo "$SWAP_FILE none swap sw 0 0" | tee -a /etc/fstab > /dev/null

# 输出当前的Swap信息，确认Swap已经启用
swapon --show

echo "Swap配置完成，大小为$SWAP_SIZE。"
