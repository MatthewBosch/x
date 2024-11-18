#!/bin/bash

# 函数：解析用户输入的范围并生成文件夹列表
parse_range() {
    local input="$1"
    local folders=()
    IFS=',' read -ra parts <<< "$input"
    
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
            start=$(echo "$part" | cut -d '-' -f 1)
            end=$(echo "$part" | cut -d '-' -f 2)
            for ((i=start; i<=end; i++)); do
                folders+=("ocean$i")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            folders+=("ocean$part")
        else
            echo "输入格式错误，请使用 4-10 或 4,5,6-9 这样的格式。"
            exit 1
        fi
    done
    echo "${folders[@]}"
}

# 提示用户输入编号范围
read -p "请输入编号范围（例如 4-10 或 4,5,6-9）: " input_range

# 解析编号范围，生成文件夹列表
folders=($(parse_range "$input_range"))

# 循环遍历每个 ocean 文件夹
for folder in "${folders[@]}"; do
    yml_file="$folder/docker-compose.yml"
    folder_number=${folder#ocean}  # 提取文件夹编号（例如 ocean5 提取为 5）

    if [ -d "$folder" ]; then
        if [ -f "$yml_file" ]; then
            echo "正在检查 $folder 中的 docker-compose.yml..."

            # 搜索 container_name: typesense-<编号>
            # 使用 grep -A 3 找到 container_name 并输出接下来的 3 行（通常包括 ports 配置）
            result=$(grep -A 3 "container_name: typesense-$folder_number" "$yml_file")

            # 提取 ports 行
            port_line=$(echo "$result" | grep 'ports')

            if [[ -n "$port_line" ]]; then
                # 获取端口号
                ports=$(echo "$result" | grep -oP '\d+:\d+')
                echo "检测到 typesense-$folder_number 容器，端口配置为：$ports"
            else
                echo "警告: 未找到 typesense-$folder_number 容器的端口配置，跳过处理。"
            fi
        else
            echo "警告: 未找到 $folder/docker-compose.yml 文件，跳过此文件夹。"
        fi
    else
        echo "警告: 未找到 $folder 文件夹，跳过此文件夹。"
    fi
done

echo "所有文件夹中的 yml 文件处理完毕。"
