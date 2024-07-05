#!/bin/bash

# 安装 screen（如果尚未安装）
sudo apt-get update
sudo apt-get install -y screen

# 下载并设置 aioznode
curl -LO https://github.com/AIOZNetwork/aioz-dcdn-cli-node/files/13561211/aioznode-linux-amd64-1.1.0.tar.gz
tar xzf aioznode-linux-amd64-1.1.0.tar.gz
mv aioznode-linux-amd64-1.1.0 aioznode

# 检查是否已存在私钥文件
if [ ! -f privkey.json ]; then
    echo "生成新的私钥..."
    ./aioznode keytool new --save-priv-key privkey.json
else
    echo "使用现有的私钥文件."
fi

# 创建日志目录
mkdir -p logs

# 创建一个新的 screen 会话并在其中启动 aioznode，将输出重定向到日志文件
screen -dmS aioznode bash -c './aioznode start --home nodedata --priv-key-file privkey.json > logs/aioznode.log 2>&1; exec bash'

echo "aioznode 已在 screen 会话中启动。"
echo "日志文件位置: $(pwd)/logs/aioznode.log"
echo "要查看实时日志，请运行: tail -f logs/aioznode.log"
echo "要进入 screen 会话，请运行: screen -r aioznode"
echo "要退出 screen 会话而不停止进程，请按 Ctrl+A 然后按 D"

# 显示最新的日志内容
echo "最新的日志内容："
tail -n 20 logs/aioznode.log
