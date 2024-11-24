#!/bin/bash

# 清屏
clear

# 询问需要生成的 yml 文件数量
read -p "请输入需要生成的 yml 文件数量: " yml_count

# 询问容器编号的起始值
read -p "请输入容器编号的起始值（例如，如果输入3，则容器将从 ocean-node-3 开始）: " start_index

# 接收 IP 地址
read -p "请输入 P2P 绑定的 IP 地址: " ip_address

# 提示用户一次性输入钱包信息
echo "请一次性输入所有钱包信息（格式: Wallet X: Public Key: 0x..., Private Key: 0x...）。输入完成后按 Ctrl+D 结束："

# 读取用户的多行输入
wallet_data=$(cat)

# 初始化一个数组存储解析后的钱包信息
declare -A wallets

# 解析钱包信息
wallet_index=1
while IFS= read -r line; do
  # 提取 Public Key 和 Private Key
  public_key=$(echo "$line" | grep -oP 'Public Key:\s*0x[a-fA-F0-9]{40}' | awk -F ': ' '{print $2}')
  private_key=$(echo "$line" | grep -oP 'Private Key:\s*0x[a-fA-F0-9]{64}' | awk -F ': ' '{print $2}')

  # 检查提取结果是否有效
  if [[ -n "$public_key" && -n "$private_key" ]]; then
    wallets[$wallet_index]="$public_key,$private_key"
    ((wallet_index++))
  fi
done <<< "$wallet_data"

# 检查是否有足够的钱包数量
if [[ ${#wallets[@]} -lt $yml_count ]]; then
  echo "错误：输入的钱包数量不足以生成 $yml_count 个 yml 文件。"
  exit 1
fi

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
  wallet_info=${wallets[$((i + 1))]}
  evm_address=$(echo "$wallet_info" | cut -d ',' -f 1)
  private_key=$(echo "$wallet_info" | cut -d ',' -f 2)

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
      PRIVATE_KEY: '$private_key'
      RPCS: '{"1":{"rpc":"https://ethereum-rpc.publicnode.com","fallbackRPCs":["https://rpc.ankr.com/eth","https://1rpc.io/eth","https://eth.api.onfinality.io/public"],"chainId":1,"network":"mainnet","chunkSize":100},"10":{"rpc":"https://mainnet.optimism.io","fallbackRPCs":["https://optimism-mainnet.public.blastapi.io","https://rpc.ankr.com/optimism","https://optimism-rpc.publicnode.com"],"chainId":10,"network":"optimism","chunkSize":100},"137":{"rpc":"https://polygon-rpc.com/","fallbackRPCs":["https://polygon-mainnet.public.blastapi.io","https://1rpc.io/matic","https://rpc.ankr.com/polygon"],"chainId":137,"network":"polygon","chunkSize":100},"23294":{"rpc":"https://sapphire.oasis.io","fallbackRPCs":["https://1rpc.io/oasis/sapphire"],"chainId":23294,"network":"sapphire","chunkSize":100},"23295":{"rpc":"https://testnet.sapphire.oasis.io","chainId":23295,"network":"sapphire-testnet","chunkSize":100},"11155111":{"rpc":"https://eth-sepolia.public.blastapi.io","fallbackRPCs":["https://1rpc.io/sepolia","https://eth-sepolia.g.alchemy.com/v2/demo"],"chainId":11155111,"network":"sepolia","chunkSize":100},"11155420":{"rpc":"https://sepolia.optimism.io","fallbackRPCs":["https://endpoints.omniatech.io/v1/op/sepolia/public","https://optimism-sepolia.blockpi.network/v1/rpc/public"],"chainId":11155420,"network":"optimism-sepolia","chunkSize":100}}'
      DB_URL: 'http://typesense:8108/?apiKey=xyz'
      IPFS_GATEWAY: 'https://ipfs.io/'
      ARWEAVE_GATEWAY: 'https://arweave.net/'
      INTERFACES: '["HTTP","P2P"]'
      ALLOWED_ADMINS: '["$evm_address"]'
      DASHBOARD: 'true'
      HTTP_API_PORT: '$ocean_http_port'
      P2P_ENABLE_IPV4: 'true'
      P2P_ENABLE_IPV6: 'false'
      P2P_ipV4BindAddress: '0.0.0.0'
      P2P_ipV4BindTcpPort: '$p2p_ipv4_tcp_port'
      P2P_ipV4BindWsPort: '$p2p_ipv4_ws_port'
      P2P_ipV6BindAddress: '::'
      P2P_ipV6BindTcpPort: '$p2p_ipv6_tcp_port'
      P2P_ipV6BindWsPort: '$p2p_ipv6_ws_port'
      P2P_ANNOUNCE_ADDRESSES: '["/ip4/$ip_address/tcp/$p2p_ipv4_tcp_port", "/ip4/$ip_address/ws/tcp/$p2p_ipv4_ws_port"]'
    networks:
      - ocean_network
    depends_on:
      - typesense

  typesense:
    image: typesense/typesense:26.0
    container_name: typesense-$current_index
    ports:
      - "$typesense_port:$typesense_port"
    networks:
      - ocean_network
    volumes:
      - typesense-data:/data
    command: '--data-dir /data --api-key=xyz'

volumes:
  typesense-data:
    driver: local

networks:
  ocean_network:
    driver: bridge
EOL

  echo "已生成文件: $folder/docker-compose.yml"
done