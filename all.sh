#!/bin/bash

echo "请选择要执行的操作:"
echo "1. 更新并安装必要的软件包 (wget, curl, unzip, jq)"
echo "2. 启用 BBR 和优化网络配置"
echo "3. 执行 x-ui 安装脚本"
echo "4. 执行 x-ui 更新脚本"
echo "5. 执行 DDNS 更新脚本"
echo "6. 安装并运行 Gost"
echo "7. 执行 Docker 安装脚本并重启"
echo "8. 执行 EU_docker_Up.sh 脚本"
echo "9. 执行所有步骤"

read -p "请输入操作编号 (1-9): " option

case $option in
    1)
        echo "正在更新并安装必要的软件包..."
        sudo apt update -y && \
        sudo apt install wget curl unzip jq -y
        ;;
    2)
        echo "正在启用 BBR 和优化网络配置..."
        echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf > /dev/null && \
        echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf > /dev/null && \
        sudo sysctl -p && \
        sudo modprobe tcp_bbr && \
        lsmod | grep bbr
        ;;
    3)
        echo "正在执行 x-ui 安装脚本..."
        bash <(curl -Ls https://raw.githubusercontent.com/teIegraph/script/main/x-ui.sh)
        ;;
    4)
        echo "正在执行 x-ui 更新脚本..."
        bash <(curl -Ls https://raw.githubusercontent.com/teIegraph/script/main/x-ui-update.sh)
        ;;
    5)
        echo "正在执行 DDNS 更新脚本..."
        bash <(curl -Ls https://raw.githubusercontent.com/teIegraph/script/main/install-ddns-go.sh)
        ;;
    6)
        echo "正在安装并运行 Gost..."
        wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh && \
        chmod +x gost.sh && \
        ./gost.sh
        ;;
    7)
        echo "正在执行 Docker 安装脚本并重启..."
        wget -N https://raw.githubusercontent.com/teIegraph/script/main/install_docker_and_restart.sh && \
        bash install_docker_and_restart.sh
        ;;
    8)
        echo "正在执行 EU_docker_Up.sh 脚本..."
        bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/tools/main/EU_docker_Up.sh)
        ;;
    9)
        echo "正在执行所有步骤..."
        sudo apt update -y && \
        sudo apt install wget curl unzip jq -y && \
        echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf > /dev/null && \
        echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf > /dev/null && \
        sudo sysctl -p && \
        sudo modprobe tcp_bbr && \
        lsmod | grep bbr && \
        bash <(curl -Ls https://raw.githubusercontent.com/teIegraph/script/main/x-ui.sh) && \
        bash <(curl -Ls https://raw.githubusercontent.com/teIegraph/script/main/x-ui-update.sh) && \
        bash <(curl -Ls https://raw.githubusercontent.com/teIegraph/script/main/ddns.sh) && \
        wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh && \
        chmod +x gost.sh && \
        ./gost.sh && \
        wget -N https://raw.githubusercontent.com/teIegraph/script/main/install_docker_and_restart.sh && \
        bash install_docker_and_restart.sh && \
        bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/tools/main/EU_docker_Up.sh)
        ;;
    *)
        echo "无效选项，请输入 1-9 之间的数字"
        exit 1
        ;;
esac
