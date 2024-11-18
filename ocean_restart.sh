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

# 检查是否安装了 docker-compose 或 docker compose
if command -v docker-compose &> /dev/null; then
    docker_cmd="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker_cmd="docker compose"
else
    echo "未检测到 docker-compose 或 docker compose，无法继续执行。"
    exit 1
fi

# 循环遍历每个 ocean 文件夹
for folder in "${folders[@]}"; do
    yml_file="$folder/docker-compose.yml"
    folder_number=${folder#ocean}  # 提取文件夹编号（例如 ocean5 提取为 5）
    
    if [ -d "$folder" ]; then
        if [ -f "$yml_file" ]; then
            echo "正在检查 $folder 中的 docker-compose.yml..."

            # 检查 typesense 端口
            if grep -q 'typesense:' "$yml_file"; then
                # 提取当前端口
                current_port=$(grep -oP '\d+(?=:8108)' "$yml_file")
                echo "检测到 typesense 配置，当前 typesense 端口为 $current_port:8108。"

                # 提示用户是否修改端口
                read -p "请输入新的 typesense 端口号（回车保持不变，输入 'no' 修改为 $current_port:$current_port）: " user_input

                # 如果用户输入 "no"，将 8108 改为 current_port
                if [[ "$user_input" == "no" ]]; then
                    sed -i "s/- \"$current_port:8108\"/- \"$current_port:$current_port\"/" "$yml_file"
                    echo "已将 typesense 端口从 $current_port:8108 修改为 $current_port:$current_port。"
                
                # 如果用户输入了具体的端口号，则进行替换
                elif [[ ! -z "$user_input" ]]; then
                    sed -i "s/- \"$current_port:8108\"/- \"$user_input:8108\"/" "$yml_file"
                    echo "已将 typesense 端口从 $current_port:8108 修改为 $user_input:8108。"
                
                # 用户回车，不修改端口
                else
                    echo "保持 typesense 端口不变。"
                fi
            else
                echo "警告: 未找到 $folder/docker-compose.yml 文件中的 typesense 配置，跳过端口修改。"
            fi

            # 执行 docker-compose up -d
            echo "正在启动 $folder 中的 docker-compose.yml..."
            cd "$folder"
            $docker_cmd up -d

            # 重启 ocean-node-<编号> 和 typesense-<编号> 容器
            echo "正在重启 ocean-node-$folder_number 和 typesense-$folder_number 容器..."
            $docker_cmd restart ocean-node-$folder_number typesense-$folder_number

            cd ..
        else
            echo "警告: 未找到 $folder/docker-compose.yml 文件，跳过此文件夹。"
        fi
    else
        echo "警告: 未找到 $folder 文件夹，跳过此文件夹。"
    fi
done

echo "所有文件夹中的 yml 文件执行和重启操作完毕。"
