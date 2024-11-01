#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    exit 1
fi

# 检查并安装Docker
function check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "未检测到 Docker，正在安装..."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce
        echo "Docker 已安装。"
    else
        echo "Docker 已安装。"
    fi
}

# 添加节点功能
function add_nodes() {
    check_and_install_docker

    # 检查是否已有 validator.env 文件
    if [ ! -f validator.env ]; then
        # 提示用户输入环境变量的值（如果没有 validator.env 文件）
        read -p "请输入验证者节点设备的IP地址: " ip_address
        read -p "请输入验证者节点的显示名称: " validator_name
        read -p "请输入验证者节点的奖励收取地址: " safe_public_address
        read -p "请输入签名者私钥,无需0x: " private_key

        # 将环境变量保存到 validator.env 文件
        cat <<EOF > validator.env
ENV=prod

STRATEGY_EXECUTOR_IP_ADDRESS=${ip_address}
STRATEGY_EXECUTOR_DISPLAY_NAME=${validator_name}
STRATEGY_EXECUTOR_BENEFICIARY=${safe_public_address}
SIGNER_PRIVATE_KEY=${private_key}
EOF

        echo "环境变量已设置并保存到 validator.env 文件。"
    else
        echo "发现已有 validator.env 文件，将直接使用。"
    fi

    # 拉取 Docker 镜像
    docker pull elixirprotocol/validator --platform linux/amd64

    # 提示用户选择平台
    read -p "您是否在Apple/ARM架构上运行？(y/n): " is_arm

    while true; do
        # 提示用户输入要运行的节点数量
        read -p "请输入要运行的节点数量（输入0退出）: " num_nodes
        
        if [ "$num_nodes" -eq 0 ]; then
            break
        fi

        for ((i=1; i<=num_nodes; i++)); do
            container_name="elixir_node_$RANDOM"  # 使用随机数确保唯一性
            
            echo "启动容器 $container_name..."
            
            if [[ "$is_arm" == "y" ]]; then
                # 在Apple/ARM架构上运行
                docker run -it -d \
                  --env-file validator.env \
                  --name "$container_name" \
                  --platform linux/amd64 \
                  elixirprotocol/validator
            else
                # 默认运行
                docker run -it -d \
                  --env-file validator.env \
                  --name "$container_name" \
                  elixirprotocol/validator
            fi
            
            # 每隔 2 秒启动一个新的容器
            sleep 2
        done
    done

    read -p "按任意键返回主菜单..." -n1 -s
    main_menu
}

# 查看Docker日志功能
function check_docker_logs() {
    echo "以下是所有以 elixir_node_ 开头的容器："
    
    # 列出所有以 elixir_node_ 开头的容器
    containers=$(docker ps --filter "name=^elixir_node_" --format "{{.ID}} {{.Names}}")
    
    if [ -z "$containers" ]; then
        echo "没有找到匹配的容器。"
        read -p "按0返回主菜单..." -n1 -s
        main_menu
        return
    fi

    # 显示容器列表及对应数字
    PS3='请选择要查看日志的容器 (输入数字): '
    select container in $(echo "$containers" | awk '{print $2}'); do
        if [ -n "$container" ]; then
            echo "查看 $container Docker容器的日志..."
            docker logs -f "$container"
            break
        else
            echo "无效选择。"
        fi
    done

    read -p "按0返回主菜单..." -n1 -s
    main_menu
}

# 删除指定数量的Docker容器功能
function delete_containers_by_quantity() {
    # 查找所有以 elixir_node_ 开头的容器
    containers=$(docker ps -aq --filter "name=^elixir_node_")

    if [ -z "$containers" ]; then
        echo "没有找到匹配的容器。"
        read -p "按0返回主菜单..." -n1 -s
        main_menu
        return
    fi

    # 显示所有容器的列表
    echo "以下是所有以 elixir_node_ 开头的容器："
    echo "$containers" | nl -w2 -s'. '

    # 提示用户输入要删除的容器数量
    read -p "请输入要删除的容器数量: " num_to_delete

    # 确保输入的数量不超过实际存在的容器数量
    total_containers=$(echo "$containers" | wc -l)
    if [ "$num_to_delete" -gt "$total_containers" ]; then
        echo "数量超出实际存在的容器数量。"
        read -p "按0返回主菜单..." -n1 -s
        main_menu
        return
    fi

    # 获取要删除的容器ID
    containers_to_delete=$(echo "$containers" | head -n
"$num_to_delete")
    
    # 停止并删除指定数量的容器
    echo "删除以下容器: $containers_to_delete"
    docker stop $containers_to_delete
    docker rm $containers_to_delete
    echo "指定数量的 Docker 容器已删除。"

    read -p "按0返回主菜单..." -n1 -s
    main_menu
}

# 更新所有 Docker 容器功能
function update_all_containers() {
    echo "正在更新所有 Docker 容器..."
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower --run-once
    read -p "按0返回主菜单..." -n1 -s
    main_menu
}

# 主菜单
function main_menu() {
    clear
    echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
    echo "=====================Elixir V3节点安装========================="
    echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
    echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
    echo "节点社区 Discord 社群:https://discord.gg/GbMV5EcNWF"
    echo "请选择要执行的操作:"
    echo "1. 添加Elixir mainnet节点"
    echo "2. 查看Docker日志"
    echo "3. 删除指定数量的 Docker 容器"
    echo "4. 更新所有 Docker 容器"
    read -p "请输入选项（1-4）: " OPTION

    case $OPTION in
    1) add_nodes ;;
    2) check_docker_logs ;;
    3) delete_containers_by_quantity ;;
    4) update_all_containers ;;
    *) echo "无效选项。" ;;
    esac
}

# 显示主菜单
main_menu
