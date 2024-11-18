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

# 函数：检查 docker-compose 是否为 docker-compose 或 docker compose 命令
check_compose_command() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "ERROR: docker-compose 或 docker compose 未安装" >&2
        exit 1
    fi
}

# 函数：删除旧的容器以避免命名冲突
remove_old_containers() {
    local container_name=$1
    if docker ps -a --format '{{.Names}}' | grep -q "$container_name"; then
        echo "发现旧的容器 $container_name，正在删除..."
        docker rm -f "$container_name"
    else
        echo "未发现旧的容器 $container_name。"
    fi
}

# 提示用户输入编号范围
read -p "请输入编号范围（例如 4-10 或 4,5,6-9）: " input_range

# 解析编号范围，生成文件夹列表
folders=($(parse_range "$input_range"))

# 确定 docker-compose 命令
compose_cmd=$(check_compose_command)

# 循环遍历每个 ocean 文件夹
for folder in "${folders[@]}"; do
    yml_file="$folder/docker-compose.yml"
    folder_number=${folder#ocean}  # 提取文件夹编号（例如 ocean5 提取为 5）

    if [ -d "$folder" ]; then
        if [ -f "$yml_file" ]; then
            echo "正在检查 $folder 中的 docker-compose.yml..."

            # 搜索 container_name: typesense-<编号> 并输出接下来的 3 行
            result=$(grep -A 3 "container_name: typesense-$folder_number" "$yml_file")

            # 提取 ports 行
            port_line=$(echo "$result" | grep 'ports')

            if [[ -n "$port_line" ]]; then
                # 获取端口号
                ports=$(echo "$result" | grep -oP '\d+:\d+')
                host_port=$(echo "$ports" | cut -d ':' -f 1)
                container_port=$(echo "$ports" | cut -d ':' -f 2)

                echo "检测到 typesense-$folder_number 容器，端口配置为：$host_port:$container_port"

                # 提示用户是否修改端口
                read -p "请输入新的 typesense 端口号（回车保持不变，输入 'no' 修改为 $host_port:$host_port）: " user_input

                if [[ "$user_input" == "no" ]]; then
                    # 修改为相同的端口号
                    sed -i "s/$host_port:$container_port/$host_port:$host_port/" "$yml_file"
                    echo "已将 typesense-$folder_number 端口修改为 $host_port:$host_port。"
                elif [[ ! -z "$user_input" ]]; then
                    # 修改为用户指定的端口号
                    sed -i "s/$host_port:$container_port/$user_input:$container_port/" "$yml_file"
                    echo "已将 typesense-$folder_number 端口修改为 $user_input:$container_port。"
                else
                    # 用户按回车，保持不变
                    echo "保持 typesense 端口不变。"
                fi

                # 调用 sync 确保文件修改写入磁盘
                sync
                echo "已确保 docker-compose.yml 文件修改写入磁盘。"

                # 添加适当的延时，确保文件系统处理完成
                sleep 2
                echo "等待 2 秒，确保文件系统处理完成..."

                # 删除旧的容器，避免命名冲突
                remove_old_containers "typesense-$folder_number"
                remove_old_containers "ocean-node-$folder_number"

                # 执行 docker-compose up -d
                echo "正在执行 $compose_cmd up -d..."
                (cd "$folder" && $compose_cmd up -d)

                # 重启 ocean-node 和 typesense 容器
                echo "正在重启 ocean-node-$folder_number 和 typesense-$folder_number 容器..."
                docker restart "ocean-node-$folder_number" "typesense-$folder_number"

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
