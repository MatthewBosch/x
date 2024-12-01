#!/bin/bash

# 清屏
clear

# 替换 RPC 的新内容（你的新 RPCS 值）
new_rpcs='{"1":{"rpc":"https://eth-mainnet.g.alchemy.com/v2/fRuFIqwIJ8AoWTfWJ_LZQH8Nzo_vCxi0","fallbackRPCs":["https://rpc.ankr.com/eth","https://1rpc.io/eth","https://eth.api.onfinality.io/public"],"chainId":1,"network":"mainnet","chunkSize":100},"10":{"rpc":"https://opt-mainnet.g.alchemy.com/v2/fRuFIqwIJ8AoWTfWJ_LZQH8Nzo_vCxi0","fallbackRPCs":["https://optimism-mainnet.public.blastapi.io","https://rpc.ankr.com/optimism","https://optimism-rpc.publicnode.com"],"chainId":10,"network":"optimism","chunkSize":100},"137":{"rpc":"https://polygon-mainnet.g.alchemy.com/v2/fRuFIqwIJ8AoWTfWJ_LZQH8Nzo_vCxi0","fallbackRPCs":["https://polygon-mainnet.public.blastapi.io","https://1rpc.io/matic","https://rpc.ankr.com/polygon"],"chainId":137,"network":"polygon","chunkSize":100},"23294":{"rpc":"https://sapphire.oasis.io","fallbackRPCs":["https://1rpc.io/oasis/sapphire"],"chainId":23294,"network":"sapphire","chunkSize":100},"23295":{"rpc":"https://testnet.sapphire.oasis.io","chainId":23295,"network":"sapphire-testnet","chunkSize":100},"11155111":{"rpc":"https://eth-sepolia.g.alchemy.com/v2/fRuFIqwIJ8AoWTfWJ_LZQH8Nzo_vCxi0","fallbackRPCs":["https://1rpc.io/sepolia","https://eth-sepolia.g.alchemy.com/v2/demo"],"chainId":11155111,"network":"sepolia","chunkSize":100},"11155420":{"rpc":"https://opt-sepolia.g.alchemy.com/v2/fRuFIqwIJ8AoWTfWJ_LZQH8Nzo_vCxi0","fallbackRPCs":["https://endpoints.omniatech.io/v1/op/sepolia/public","https://optimism-sepolia.blockpi.network/v1/rpc/public"],"chainId":11155420,"network":"optimism-sepolia","chunkSize":100}}'

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
      echo "[ERROR] 无效的输入范围: $part"
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

  # 检查文件夹和文件是否存在
  if [[ -d "$folder" && -f "$yml_file" ]]; then
    # 创建临时文件
    temp_file=$(mktemp)

    # 是否找到 RPCS 行的标志
    found_rpcs_line=false

    # 逐行读取并修改文件
    while IFS= read -r line; do
      if [[ "$line" =~ ^([[:space:]]*)RPCS: ]]; then
        # 提取前面的缩进
        indentation="${BASH_REMATCH[1]}"
        # 替换为新的 RPCS 内容，保留缩进
        echo "${indentation}RPCS: '$new_rpcs'" >> "$temp_file"
        found_rpcs_line=true
      else
        # 保留其他行
        echo "$line" >> "$temp_file"
      fi
    done < "$yml_file"

    if [[ "$found_rpcs_line" == false ]]; then
      echo "[WARNING] 未找到 RPCS 行，跳过修改: $yml_file"
      continue
    fi

    # 将修改写回原文件
    mv "$temp_file" "$yml_file"

    # 删除对应的容器
    ocean_node_container="ocean-node-$index"
    typesense_container="typesense-$index"

    docker rm -f "$ocean_node_container" "$typesense_container" >/dev/null 2>&1

    # 重新启动 docker-compose
    cd "$folder"
    if command -v docker-compose &> /dev/null; then
      docker-compose up -d
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
      docker compose up -d
    else
      echo "[ERROR] 未检测到 docker-compose 或 docker compose，无法启动容器。"
      exit 1
    fi
    cd - >/dev/null
    echo "[INFO] 成功更新并重启容器：ocean$index"
  else
    echo "[WARNING] 文件夹 $folder 或文件 $yml_file 不存在，跳过。"
  fi
done

echo "[INFO] 所有操作完成！"
