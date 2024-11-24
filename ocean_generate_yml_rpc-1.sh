#!/bin/bash

# 清屏
clear

# 询问需要生成的 yml 文件数量
read -p "请输入需要生成的 yml 文件数量: " yml_count

# 询问容器编号的起始值
read -p "请输入容器编号的起始值（例如，如果输入3，则容器将从 ocean-node-3 开始）: " start_index

# 接收 IP 地址
read -p "请输入 P2P 绑定的 IP 地址: " ip_address

# 接收 EVM 钱包地址和私钥
declare -A wallets
echo "请输入 EVM 钱包信息（格式: Wallet X: Public Key: 0x..., Private Key: 0x...），一行一个："

# 循环接收钱包信息
for ((i = 1; i <= yml_count; i++)); do
  wallet_info=""
  while [[ -z "$wallet_info" ]]; do
    read -p "Wallet $i: " wallet_info

    # 清理重复的 "Wallet X: Wallet Y:"
    wallet_info=$(echo "$wallet_info" | sed -E 's/^Wallet [0-9]+:\s*Wallet [0-9]+:/Wallet \1:/')

    # 跳过空行或无效输入
    if [[ -z "$wallet_info" ]]; then
      echo "输入为空，请重新输入。"
      continue
    fi

    # 使用正则表达式提取 Public Key 和 Private Key
    public_key=$(echo "$wallet_info" | grep -oiP 'Public Key:\s*0x[a-fA-F0-9]{40}' | sed 's/Public Key:\s*//I')
    private_key=$(echo "$wallet_info" | grep -oiP 'Private Key:\s*0x[a-fA-F0-9]{64}' | sed 's/Private Key:\s*//I')

    # 检查提取结果是否为空
    if [[ -z "$public_key" || -z "$private_key" ]]; then
      echo "输入格式有误，请确保格式为: Wallet X: Public Key: 0x..., Private Key: 0x..."
      wallet_info=""
    fi
  done

  # 将提取到的钱包信息存入数组
  wallets[$i]="Public Key: $public_key, Private Key: $private_key"
done

# 基本端口号
base_port=16010

# 循环生成 yml 文件
for ((i = 0; i < yml_count; i++)); do
  # 计算当前容器编号（从 start_index 开始）
  current_index=$((start_index + i))

  # 计算 HTTP 和 P2P 相关端口
  ocean_http_port=$((base_port + (current_index - 1) * 100))
  p2p_ipv4_tcp_port=$((ocean_http_port + 10))
  p2p_ipv4_ws_port=$((p2p_ipv4_tcp_port + 1))
  p2p_ipv6_tcp_port=$((p2p_ipv4_tcp_port + 2))
  p2p_ipv6_ws_port=$((p2p_ipv4_tcp_port + 3))

  # 计算 Typesense 端口
  typesense_port=$((28208 + (current_index - 1) * 10))

  # 获取对应的钱包地址和私钥
  evm_address=$(echo ${wallets[$((i + 1))]} | cut -d ' ' -f 3)
  evm_private_key=$(echo ${wallets[$((i + 1))]} | sed 's/.*Private Key: //')

  # 去除 EVM 地址中可能多余的逗号
  evm_address=$(echo $evm_address | sed 's/,$//')

  # 创建对应的文件夹
  folder="ocean$current_index"
  mkdir -p $folder

  # 创建 docker-compose.yml 文件
  cat > $folder/docker-compose.yml <<EOL
services:
  ocean-node:
    image: oceanprotocol/ocean-node:latest
    pull_policy: always
    container_name: ocean-node-$current_index
    restart: on-failure
    ports:
      - "$ocean_http_port:$ocean_http_port"
      - "$p2p_ipv4_tcp_port:$p2p_ipv4_tcp_port"
      - "$p2p_ipv4_ws_port:$p2p_ipv4_ws_port"
      - "$p2p_ipv6_tcp_port:$p2p_ipv6_tcp_port"
      - "$p2p_ipv6_ws_port:$p2p_ipv6_ws_port"
    environment:
      PRIVATE_KEY: '$evm_private_key'
      ALLOWED_ADMINS: '["$evm_address"]'
      HTTP_API_PORT: '$ocean_http_port'
      P2P_ANNOUNCE_ADDRESSES: '["/ip4/$ip_address/tcp/$p2p_ipv4_tcp_port", "/ip4/$ip_address/ws/tcp/$p2p_ipv4_ws_port"]'
    networks:
      - ocean_network

networks:
  ocean_network:
    driver: bridge
EOL

  echo "已生成文件: $folder/docker-compose.yml"
done

echo "所有 yml 文件生成完毕。"
