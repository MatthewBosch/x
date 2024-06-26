#!/bin/bash

# 卸载旧版本 Docker（如果存在）
sudo apt purge docker-ce docker-ce-cli containerd.io

# 安装依赖
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common

# 添加 Docker 官方 GPG 密钥
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -

# 设置 Docker 仓库
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

# 安装 Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# 启动 Docker 并设置自动启动
sudo systemctl start docker
sudo systemctl enable docker

# 定义 Docker Compose 的版本号
DOCKER_COMPOSE_VERSION="2.2.1"

# 下载 Docker Compose 可执行文件
sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# 添加可执行权限
sudo chmod +x /usr/local/bin/docker-compose

docker-compose up -d

