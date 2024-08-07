#!/bin/bash

# 函数：读取多行输入
read_multiline() {
    local arr=()
    for i in {1..12}; do
        read -r line
        arr+=("$line")
    done
    echo "${arr[@]}"
}

# 检查是否有bypass参数
BYPASS="false"
if [[ "$1" == "bypass" ]]; then
    BYPASS="true"
fi

if [[ "$BYPASS" != "true" ]]; then
    # 询问用户输入 12 个 SCOUT_UID
    echo "请输入 12 个 SCOUT_UID，每个一行："
    SCOUT_UIDS=($(read_multiline))
    for i in {0..11}; do
        echo "SCOUT_UID_$((i+1))=${SCOUT_UIDS[$i]}" >> ~/.scout_config
    done

    # 询问用户输入 12 个 WEBHOOK_API_KEY
    echo "请输入 12 个 WEBHOOK_API_KEY，每个一行："
    WEBHOOK_API_KEYS=($(read_multiline))
    for i in {0..11}; do
        echo "WEBHOOK_API_KEY_$((i+1))=${WEBHOOK_API_KEYS[$i]}" >> ~/.scout_config
    done

    # 询问用户输入 12 个 GROQ_API_KEY
    echo "请输入 12 个 GROQ_API_KEY，每个一行："
    GROQ_API_KEYS=($(read_multiline))
    for i in {0..11}; do
        echo "GROQ_API_KEY_$((i+1))=${GROQ_API_KEYS[$i]}" >> ~/.scout_config
    done
else
    # 从配置文件读取所有值
    SCOUT_UIDS=($(grep "^SCOUT_UID_" ~/.scout_config | cut -d '=' -f2))
    WEBHOOK_API_KEYS=($(grep "^WEBHOOK_API_KEY_" ~/.scout_config | cut -d '=' -f2))
    GROQ_API_KEYS=($(grep "^GROQ_API_KEY_" ~/.scout_config | cut -d '=' -f2))
fi

# 定义安装节点的函数
function install_node() {
    # 检查是否已安装 Docker
    if ! command -v docker &> /dev/null; then
        echo "安装 Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
    else
        echo "Docker 已安装，跳过安装步骤。"
    fi

    # 获取当前系统的公网 IP 地址
    ip=$(curl -s4 ifconfig.me/ip)

    # 创建 scout 目录（如果不存在）
    mkdir -p ~/scout

    # 切换到 scout 目录
    cd ~/scout || {
        echo "切换到 scout 目录失败。请检查目录是否存在或权限设置。"
        exit 1
    }

    # 循环创建 12 个实例
    for i in {0..11}; do
        port=$((3001 + i))
        # 构建 webhook 的 URL
        WEBHOOK_URL="http://$ip:$port/"

        # 输出 webhook URL
        echo "Webhook URL for port $port: $WEBHOOK_URL"

        # 创建每个实例的目录
        mkdir -p "scout_$port"
        cd "scout_$port" || exit

        # 使用 tee 命令将内容写入 .env 文件
        tee .env > /dev/null <<EOF
PORT=$port
LOGGER_LEVEL=debug

# Chasm
ORCHESTRATOR_URL=https://orchestrator.chasm.net
SCOUT_NAME=myscout_$port
SCOUT_UID=${SCOUT_UIDS[$i]}
WEBHOOK_API_KEY=${WEBHOOK_API_KEYS[$i]}
# Scout Webhook Url, update based on your server's IP and Port
WEBHOOK_URL=$WEBHOOK_URL

# Chosen Provider (groq, openai)
PROVIDERS=groq
MODEL=gemma2-9b-it
GROQ_API_KEY=${GROQ_API_KEYS[$i]}

# Optional
OPENROUTER_API_KEY=$OPENROUTER_API_KEY
OPENAI_API_KEY=$OPENAI_API_KEY
EOF

        # 输出 .env 文件内容，用于验证
        echo "Contents of .env file for port $port:"
        cat .env

        # 设置防火墙规则允许端口
        echo "设置防火墙规则允许端口 $port..."
        sudo ufw allow $port
        sudo ufw allow $port/tcp

        # 拉取 Docker 镜像并运行
        if docker pull johnsonchasm/chasm-scout; then
            docker run -d --restart=always --env-file ./.env -p $port:$port --name scout_$port johnsonchasm/chasm-scout
        else
            echo "拉取 Docker 镜像失败，请检查网络或稍后重试。"
            exit 1
        fi

        cd ..
    done

    # 输出消息
    echo "所有实例已创建完成，退出脚本。"
    exit 0
}

# 发送 POST 请求到所有 webhook 的函数
function send_webhook_requests() {
    for port in {3001..3012}; do
        cd ~/scout/scout_$port || {
            echo "切换到 scout_$port 目录失败。请检查目录是否存在或权限设置。"
            continue
        }
        source ./.env
        echo "发送请求到端口 $port..."
        curl -X POST \
             -H "Content-Type: application/json" \
             -H "Authorization: Bearer $WEBHOOK_API_KEY" \
             -d '{"body":"{\"model\":\"gemma2-9b-it\",\"messages\":[{\"role\":\"system\",\"content\":\"You are a helpful assistant.\"}]}"}' \
             "$WEBHOOK_URL"
        echo ""  # 添加一个空行以提高可读性
    done
    echo "所有请求已发送完毕。"
}

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "脚本由大赌社区哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
        echo "特别鸣谢 Silent ⚛| validator"
        echo "================================================================"
        echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
        echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
        echo "节点社区 Discord 社群:https://discord.gg/GbMV5EcNWF"
        echo "退出脚本，请按键盘ctrl c退出即可"
        echo "请选择要执行的操作:"
        echo "1. 安装节点 (12个实例)"
        echo "2. 发送 Webhook 请求 (向所有12个实例)"
        read -p "请输入选项（1-2）: " OPTION

        case $OPTION in
        1) install_node ;;
        2) send_webhook_requests ;;
        *) echo "无效选项，请重新输入。" ;;
        esac
        echo "按任意键返回主菜单..."
        read -n 1
    done
}

# 显示主菜单
main_menu
