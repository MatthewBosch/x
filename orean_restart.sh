#!/bin/bash

# 清屏
clear

# 接收用户输入的编号范围
read -p "请输入需要重启容器的编号范围（例如 1,2-5,8,10）: " input_ranges

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

# 遍历每个目标编号并执行 docker restart
for index in "${target_indices[@]}"; do
  typesense_container="typesense-$index"
  ocean_node_container="ocean-node-$index"

  echo "[INFO] 重启容器: $typesense_container 和 $ocean_node_container"
  
  # 执行 docker restart
  docker restart "$typesense_container" >/dev/null 2>&1 && echo "  - $typesense_container 已成功重启" || echo "  - [ERROR] 无法重启 $typesense_container"
  docker restart "$ocean_node_container" >/dev/null 2>&1 && echo "  - $ocean_node_container 已成功重启" || echo "  - [ERROR] 无法重启 $ocean_node_container"
done

echo "[INFO] 操作完成！"
