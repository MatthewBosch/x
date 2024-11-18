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
echo "请输入 EVM 钱包信息（格式: Wallet 1: Public Key: 0x..., Private Key: 0x...），一行一个："

# 循环接收钱包信息
for ((i = 1; i <= yml_count; i++)); do
  read -p "Wallet $i: " wallet_info
  
  # 使用正则表达式精确提取公钥和私钥，去掉多余的逗号和空格
  public_key=$(echo $wallet_info | grep -oP 'Public Key: 0x[a-fA-F0-9]{40}' | cut -d ' ' -f 3)
  private_key=$(echo $wallet_info | grep -oP 'Private Key: 0x[a-fA-F0-9]{64}' | cut -d ' ' -f 3)
  
  # 检查公钥和私钥是否提取成功
  if [[ -z "$public_key" || -z "$private_key" ]]; then
    echo "输入格式有误，请确保格式为: Wallet X: Public Key: 0x..., Private Key: 0x..."
    exit 1
  fi

  # 将提取到的钱包信息存入数组
  wallets[$i]="Public Key: $public_key, Private Key: $private_key"
done

# 起始 HTTP 端口， 每个容器递增 100
base_http_port=16010
# 起始 P2P 端口， 每个容器递增 100
base_p2p_port=16020
# 起始 Typesense 端口， 每个容器递增 10
base_typesense_port=8208

# 循环生成 yml 文件
for ((i = 0; i < yml_count; i++)); do
  # 计算当前容器编号（从 start_index 开始）
  current_index=$((start_index + i))

  # 计算 HTTP 和 P2P 相关端口
  ocean_http_port=$((base_http_port + (current_index - 1) * 100))
  p2p_ipv4_tcp_port=$((base_p2p_port + (current_index - 1) * 100))
  p2p_ipv4_ws_port=$((p2p_ipv4_tcp_port + 1))
  p2p_ipv6_tcp_port=$((p2p_ipv4_tcp_port + 2))
  p2p_ipv6_ws_port=$((p2p_ipv4_tcp_port + 3))

  # 计算 Typesense 端口
  typesense_port=$((base_typesense_port + (current_index - 1) * 10))

  # 获取对应的钱包地址
  evm_address=$(echo ${wallets[$((i + 1))]} | cut -d ' ' -f 3)

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
      PRIVATE_KEY: '${wallets[$((i + 1))]#*, Private Key: }'
      RPCS: '{"1":{"rpc":"https://ethereum-rpc.publicnode.com","fallbackRPCs":["https://rpc.ankr.com/eth","https://1rpc.io/eth","https://eth.api.onfinality.io/public"],"chainId":1,"network":"mainnet","chunkSize":100},"10":{"rpc":"https://mainnet.optimism.io","fallbackRPCs":["https://optimism-mainnet.public.blastapi.io","https://rpc.ankr.com/optimism","https://optimism-rpc.publicnode.com"],"chainId":10,"network":"optimism","chunkSize":100},"137":{"rpc":"https://polygon-rpc.com/","fallbackRPCs":["https://polygon-mainnet.public.blastapi.io","https://1rpc.io/matic","https://rpc.ankr.com/polygon"],"chainId":137,"network":"polygon","chunkSize":100},"23294":{"rpc":"https://sapphire.oasis.io","fallbackRPCs":["https://1rpc.io/oasis/sapphire"],"chainId":23294,"network":"sapphire","chunkSize":100},"23295":{"rpc":"https://testnet.sapphire.oasis.io","chainId":23295,"network":"sapphire-testnet","chunkSize":100},"11155111":{"rpc":"https://eth-sepolia.public.blastapi.io","fallbackRPCs":["https://1rpc.io/sepolia","https://eth-sepolia.g.alchemy.com/v2/demo"],"chainId":11155111,"network":"sepolia","chunkSize":100},"11155420":{"rpc":"https://sepolia.optimism.io","fallbackRPCs":["https://endpoints.omniatech.io/v1/op/sepolia/public","https://optimism-sepolia.blockpi.network/v1/rpc/public"],"chainId":11155420,"network":"optimism-sepolia","chunkSize":100}}'            
      DB_URL: 'http://typesense:8108/?apiKey=xyz'
      IPFS_GATEWAY: 'https://ipfs.io/'
      ARWEAVE_GATEWAY: 'https://arweave.net/'
#      LOAD_INITIAL_DDOS: ''
#      FEE_TOKENS: ''
#      FEE_AMOUNT: ''
#      ADDRESS_FILE: ''
#      NODE_ENV: ''
#      AUTHORIZED_DECRYPTERS: ''
#      OPERATOR_SERVICE_URL: ''
      INTERFACES: '["HTTP","P2P"]'
#      ALLOWED_VALIDATORS: ''
#      INDEXER_NETWORKS: '[]'
      ALLOWED_ADMINS: '["$evm_address"]'
#      INDEXER_INTERVAL: ''
      DASHBOARD: 'true'
#      RATE_DENY_LIST: ''
#      MAX_REQ_PER_SECOND: ''
#      MAX_CHECKSUM_LENGTH: ''
#      LOG_LEVEL: ''
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
#      P2P_ANNOUNCE_PRIVATE: ''
#      P2P_pubsubPeerDiscoveryInterval: ''
#      P2P_dhtMaxInboundStreams: ''
#      P2P_dhtMaxOutboundStreams: ''
#      P2P_mDNSInterval: ''
#      P2P_connectionsMaxParallelDials: ''
#      P2P_connectionsDialTimeout: ''
#      P2P_ENABLE_UPNP: ''
#      P2P_ENABLE_AUTONAT: ''
#      P2P_ENABLE_CIRCUIT_RELAY_SERVER: ''
#      P2P_ENABLE_CIRCUIT_RELAY_CLIENT: ''
#      P2P_BOOTSTRAP_NODES: ''
#      P2P_FILTER_ANNOUNCED_ADDRESSES: ''
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

# 询问是否执行生成的 yml 文件
read -p "是否执行生成的 yml 文件？(yes/no): " execute_choice

if [[ "$execute_choice" == "yes" ]]; then
  
  # 首先检查系统上是否有 `docker-compose` 或 `docker compose`
  if command -v docker-compose &> /dev/null; then
    docker_cmd="docker-compose"
  elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker_cmd="docker compose"
  else
    echo "未检测到 docker-compose 或 docker compose，无法继续执行。"
    exit 1
  fi

  for ((i = 0; i < yml_count; i++)); do
    current_index=$((start_index + i))
    folder="ocean$current_index"
    cd $folder
    echo "正在使用 $docker_cmd up -d 在文件夹: $folder"
    $docker_cmd up -d
    cd ..
  done
  echo "所有 yml 文件已执行完毕。"
else
  echo "yml 文件已生成，但未执行。"
fi
