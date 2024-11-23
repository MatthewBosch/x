#!/bin/bash

# 定义安装函数
install_config_node() {
    echo "正在安装配置节点所需工具..."
    
    # 添加 Docker GPG 密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # 添加 Docker 软件源
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 更新系统并安装依赖
    sudo apt update && sudo apt install -y sshpass jq

    # 下载并配置脚本
    mkdir -p $HOME/ceremonyclient/node/
    cd $HOME/ceremonyclient/node/
    wget https://github.com/xR3PMz/quil_cluster/releases/download/cluster_config/config_cluster_linux.sh
    chmod +x config_cluster_linux.sh
    wget https://advanced-hash.ai/downloads/para.sh
    chmod +x para.sh

    echo "配置节点工具安装完成！运行以下命令启动配置："
    echo "./config_cluster_linux.sh"
}

install_normal_node() {
    echo "正在安装普通节点所需工具..."
    
    # 安装 sshpass
    sudo apt update && sudo apt install -y sshpass

    # 下载并配置脚本
    mkdir -p $HOME/ceremonyclient/node/
    cd $HOME/ceremonyclient/node/
    wget https://advanced-hash.ai/downloads/para.sh
    chmod +x para.sh

    echo "普通节点工具安装完成！"
}

# 脚本主逻辑
echo "请选择要安装的节点类型："
echo "1. 配置节点 (管理其他节点)"
echo "2. 普通节点 (被管理节点)"
echo -n "请输入数字 [1-2]: "
read choice

case $choice in
    1)
        install_config_node
        ;;
    2)
        install_normal_node
        ;;
    *)
        echo "无效选择，请重新运行脚本并输入正确数字。"
        ;;
esac
