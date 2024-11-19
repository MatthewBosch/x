#!/bin/bash

# 定义要替换的 RPCS 值
NEW_RPCS='{"1":{"rpc":"https://ethereum-rpc.publicnode.com","fallbackRPCs":["https://rpc.ankr.com/eth","https://1rpc.io/eth","https://eth.api.onfinality.io/public"],"chainId":1,"network":"mainnet","chunkSize":100},"10":{"rpc":"https://mainnet.optimism.io","fallbackRPCs":["https://optimism-mainnet.public.blastapi.io","https://rpc.ankr.com/optimism","https://optimism-rpc.publicnode.com"],"chainId":10,"network":"optimism","chunkSize":100},"137":{"rpc":"https://polygon-rpc.com/","fallbackRPCs":["https://polygon-mainnet.public.blastapi.io","https://1rpc.io/matic","https://rpc.ankr.com/polygon"],"chainId":137,"network":"polygon","chunkSize":100},"23294":{"rpc":"https://sapphire.oasis.io","fallbackRPCs":["https://1rpc.io/oasis/sapphire"],"chainId":23294,"network":"sapphire","chunkSize":100},"23295":{"rpc":"https://testnet.sapphire.oasis.io","chainId":23295,"network":"sapphire-testnet","chunkSize":100},"11155111":{"rpc":"https://eth-sepolia.public.blastapi.io","fallbackRPCs":["https://1rpc.io/sepolia","https://eth-sepolia.g.alchemy.com/v2/demo"],"chainId":11155111,"network":"sepolia","chunkSize":100},"11155420":{"rpc":"https://sepolia.optimism.io","fallbackRPCs":["https://endpoints.omniatech.io/v1/op/sepolia/public","https://optimism-sepolia.blockpi.network/v1/rpc/public"],"chainId":11155420,"network":"optimism-sepolia","chunkSize":100}}'

# 替换 docker-compose.yml 中的 RPCS
if [ -f "docker-compose.yml" ]; then
    echo "正在替换 docker-compose.yml 中的 RPCS..."
    sed -i "s|RPCS: '.*'|RPCS: '$NEW_RPCS'|" docker-compose.yml
    echo "RPCS 替换完毕。"
else
    echo "未找到 docker-compose.yml 文件！"
    exit 1
fi

# 检查是否安装了 docker-compose 或 docker compose
compose_cmd=""
if command -v docker-compose &> /dev/null; then
    compose_cmd="docker-compose"
elif docker compose version &> /dev/null; then
    compose_cmd="docker compose"
else
    echo "ERROR: docker-compose 或 docker compose 未安装。"
    exit 1
fi

# 删除旧的 ocean-node 和 typesense 容器
echo "正在删除 ocean-node 和 typesense 容器..."
docker rm -f ocean-node typesense

# 使用 docker-compose 启动容器
echo "正在启动容器..."
$compose_cmd up -d

echo "操作完成。"
