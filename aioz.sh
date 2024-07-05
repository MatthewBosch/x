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

# 创建一个新的 screen 会话并在其中启动 aioznode
screen -dmS aioznode bash -c './aioznode start --home nodedata --priv-key-file privkey.json; exec bash'

echo "aioznode 已在 screen 会话中启动。"
echo "要查看 aioznode 输出，请运行: screen -r aioznode"
echo "要退出 screen 会话而不停止进程，请按 Ctrl+A 然后按 D"
