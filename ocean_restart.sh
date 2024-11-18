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

    if [ -d "$folder" ]; then
        if [ -f "$yml_file" ]; then
            echo "正在检查 $folder 中的 docker-compose.yml..."

            # 读取 typesense 的端口配置
            current_port=$(grep -A 2 'typesense:' "$yml_file" | grep 'ports:' -A 1 | grep -oP '\d+:\d+')

            if [[ -n "$current_port" ]]; then
                host_port=$(echo "$current_port" | cut -d ':' -f 1)
                container_port=$(echo "$current_port" | cut -d ':' -f 2)
                echo "检测到 typesense 配置，当前 typesense 端口为 $host_port:$container_port。"

                # 提示用户是否修改端口
                read -p "请输入新的 typesense 端口号（回车保持不变，输入 'no' 修改为 $host_port:$host_port）: " user_input

                # 如果用户输入 "no"，将第二个端口改为与第一个端口相同
                if [[ "$user_input" == "no" ]]; then
                    sed -i "s/- \"$host_port:$container_port\"/- \"$host_port:$host_port\"/" "$yml_file"
                    echo "已将 typesense 端口从 $host_port:$container_port 修改为 $host_port:$host_port。"
                elif [[ ! -z "$user_input" ]]; then
                    # 用户输入了具体的端口号，修改为用户输入的端口号
                    sed -i "s/- \"$host_port:$container_port\"/- \"$user_input:$container_port\"/" "$yml_file"
                    echo "已将 typesense 端口从 $host_port:$container_port 修改为 $user_input:$container_port。"
                else
                    # 如果用户按回车，保持不变
                    echo "保持 typesense 端口不变。"
                fi
            else
                echo "警告: 未找到 typesense 服务的端口映射，跳过端口修改。"
            fi

        else
            echo "警告: 未找到 $folder/docker-compose.yml 文件，跳过此文件夹。"
        fi
    else
        echo "警告: 未找到 $folder 文件夹，跳过此文件夹。"
    fi
done

echo "所有文件夹中的 yml 文件处理完毕。"
