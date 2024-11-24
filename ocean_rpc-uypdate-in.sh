#!/bin/bash

# 清屏
clear

# 替换 RPC 的新内容
new_rpcs='{"1":{"rpc":"https://ethereum-rpc.publicnode.com","fallbackRPCs":["https://rpc.ankr.com/eth","https://1rpc.io/eth","https://eth.api.onfinality.io/public"],"chainId":1,"network":"mainnet","chunkSize":100},"10":{"rpc":"https://mainnet.optimism.io","fallbackRPCs":["https://optimism-mainnet.public.blastapi.io","https://rpc.ankr.com/optimism","https://optimism-rpc.publicnode.com"],"chainId":10,"network":"optimism","chunkSize":100},"137":{"rpc":"https://polygon-rpc.com/","fallbackRPCs":["https://polygon-mainnet.public.blastapi.io","https://1rpc.io/matic","https://rpc.ankr.com/polygon"],"chainId":137,"network":"polygon","chunkSize":100},"23294":{"rpc":"https://sapphire.oasis.io","fallbackRPCs":["https://1rpc.io/oasis/sapphire"],"chainId":23294,"network":"sapphire","chunkSize":100},"23295":{"rpc":"https://testnet.sapphire.oasis.io","chainId":23295,"network":"sapphire-testnet","chunkSize":100},"11155111":{"rpc":"https://eth-sepolia.public.blastapi.io","fallbackRPCs":["https://1rpc.io/sepolia","https://eth-sepolia.g.alchemy.com/v2/demo"],"chainId":11155111,"network":"sepolia","chunkSize":100},"11155420":{"rpc":"https://sepolia.optimism.io","fallbackRPCs":["https://endpoints.omniatech.io/v1/op/sepolia/public","https://optimism-sepolia.blockpi.network/v1/rpc/public"],"chainId":11155420,"network":"optimism-sepolia","chunkSize":100}}'

# 接收用户输入的编号范围（例如 1,2-5,9）
read -p "请输入需要操作的编号范围（例如 1,2-5,9）: " input_ranges

# 展开编号范围到具体的编号列表
expand_ranges() {
  local ranges="$1"
  local expanded=()

  # 使用逗号分隔每个范围
  IFS=',' read -ra parts <<< "$ranges"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      # 单个编号
      expanded+=("$part")
    elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      # 范围编号，展开为具体编号
      for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do
        expanded+=("$i")
      done
    else
      echo "无效的输入范围: $part"
      exit 1
    fi
  done

  # 返回展开的编号列表
  echo "${expanded[@]}"
}

# 展开输入的编号范围为具体编号列表
target_indices=($(expand_ranges "$input_ranges"))

# 遍历每个目标编号
for index in "${target_indices[@]}"; do
  folder="ocean$index"
  yml_file="$folder/docker-compose.yml"

  # 检查文件夹是否存在
  if [[ -d "$folder" && -f "$yml_file" ]]; then
    echo "正在处理文件夹: $folder"

    # 提取并替换 RPCS 行
    rpcs_line=$(grep 'RPCS:' "$yml_file")

    if [[ -n "$rpcs_line" ]]; then
      # 替换整行 RPCS 内容
      sed -i "s|^\s*RPCS:.*|      RPCS: '$new_rpcs'|g" "$yml_file"
      echo "已成功替换 $yml_file 中的 RPCS 行"
    else
      echo "未找到 $yml_file 中的 RPCS 行，跳过替换"
    fi

    # 删除对应的容器
    ocean_node_container="ocean-node-$index"
    typesense_container="typesense-$index"

    echo "删除容器: $ocean_node_container 和 $typesense_container"
    docker rm -f "$ocean_node_container" "$typesense_container" 2>/dev/null

    # 重新启动 docker-compose
    echo "重新启动容器: $folder"
    cd "$folder"
    if command -v docker-compose &> /dev/null; then
      docker-compose up -d
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
      docker compose up -d
    else
      echo "未检测到 docker-compose 或 docker compose，无法启动容器。"
      exit 1
    fi
    cd - &> /dev/null
  else
    echo "文件夹 $folder 或文件 $yml_file 不存在，跳过。"
  fi
done

echo "所有操作完成！"
