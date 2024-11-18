#!/bin/bash

# 询问用户文件夹的起始编号和结束编号
read -p "请输入文件夹的起始编号（例如 4）: " start
read -p "请输入文件夹的结束编号（例如 14）: " end

# 检查是否安装了 docker-compose 或 docker compose
if command -v docker-compose &> /dev/null; then
    docker_cmd="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker_cmd="docker compose"
else
    echo "未检测到 docker-compose 或 docker compose，无法继续执行。"
    exit 1
fi

# 循环遍历从 start 到 end 的文件夹并执行 docker-compose.yml
for ((i = start; i <= end; i++)); do
    folder="ocean$i"

    if [ -d "$folder" ]; then
        if [ -f "$folder/docker-compose.yml" ]; then
            echo "正在启动 $folder 中的 docker-compose.yml..."
            cd "$folder"
            $docker_cmd up -d
            cd ..
        else
            echo "警告: 未找到 $folder/docker-compose.yml 文件，跳过此文件夹。"
        fi
    else
        echo "警告: 未找到 $folder 文件夹，跳过此文件夹。"
    fi
done

echo "所有文件夹中的 yml 文件执行完毕。"
