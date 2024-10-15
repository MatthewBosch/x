#!/bin/bash

# 备份钱包
cd ~
echo "正在备份钱包配置文件..."
cp -r ~/ceremonyclient/node/.config ~/config
config_copy_status=$?
config_copy_message="备份成功"
if [ $config_copy_status != 0 ]; then
    config_copy_message="备份失败，请检查！"
fi
echo $config_copy_message

# 建立并备份 ceremonyclient 文件
echo "备份旧的 ceremonyclient 目录..."
mv ceremonyclient ceremonyclient_old
mkdir ceremonyclient && cd ceremonyclient || { echo "无法创建 ceremonyclient 目录"; exit 1; }

# 下载 node 文件
echo "正在下载 node 文件..."
mkdir node && cd node || { echo "无法创建 node 目录"; exit 1; }
echo "... node 目录已重新创建"

release_os="linux"  # 修改为你的 OS
release_arch="arm64"  # 修改为你的架构
files=$(curl -s https://releases.quilibrium.com/release | grep "$release_os-$release_arch")
for file in $files; do
    version=$(echo "$file" | cut -d '-' -f 2)
    if ! test -f "./$file"; then
        curl -s "https://releases.quilibrium.com/$file" -o "$file"
        echo "... 已下载 $file"
    fi
done
chmod +x *
cd ..

# 下载 client
echo "正在下载 client 文件..."
mkdir client && cd client || { echo "无法创建 client 目录"; exit 1; }
echo "... client 目录已重新创建"

files=$(curl -s https://releases.quilibrium.com/qclient-release | grep "$release_os-$release_arch")
for file in $files; do
    clientversion=$(echo "$file" | cut -d '-' -f 2)
    if ! test -f "./$file"; then
        curl -s "https://releases.quilibrium.com/$file" -o "$file"
        echo "... 已下载 $file"
    fi
done
chmod +x *
cp ./qclient-2.0.0.2-linux-arm64 ./qclient
cd ..

# 把备份的钱包导入
echo "恢复钱包配置..."
cp -r ~/config ~/ceremonyclient/node/.config
if [ $? -eq 0 ]; then
    echo "钱包配置已成功恢复"
else
    echo "钱包配置恢复失败"
fi

# 创建运行脚本
echo "创建并执行操作脚本..."

cat << 'EOF' > run_operations.sh
#!/bin/bash

# 提供选择菜单
echo "请选择操作："
echo "1) 查询本机的 Effective seniority score"
echo "2) 查询余额"
echo "3) 运行 ./node-2.0.0.3-linux-arm64"
echo "4) 退出"

# 读取用户输入
read -p "请输入选项 [1-4]: " choice

# 执行相应的操作
case $choice in
  1)
    echo "查询本机的 Effective seniority score..."
    cd ~/ceremonyclient/node/ || { echo "无法进入目录 ~/ceremonyclient/node/"; exit 1; }
    ./../client/qclient-2.0.0.2-linux-arm64 config prover merge --dry-run ~/ceremonyclient/node/.config/ ~/ceremonyclient/node/.config/
    echo "Effective seniority score 查询完毕。"
    ;;
  2)
    echo "查询余额..."
    cd ~/ceremonyclient/node/ || { echo "无法进入目录 ~/ceremonyclient/node/"; exit 1; }
    ./../client/qclient-2.0.0.2-linux-arm64 token balance
    echo "余额查询完毕。"
    ;;
  3)
    echo "运行 ./node-2.0.0.3-linux-arm64..."
    cd ~/ceremonyclient/node/ || { echo "无法进入目录 ~/ceremonyclient/node/"; exit 1; }
    ./node-2.0.0.3-linux-arm64
    echo "./node-2.0.0.3-linux-arm64 已运行。"
    ;;
  4)
    echo "退出脚本。"
    exit 0
    ;;
  *)
    echo "无效的选项，请选择 1-4 之间的数字。"
    ;;
esac
EOF

chmod +x run_operations.sh
echo "脚本创建完毕，可执行 ./run_operations.sh 进行操作。"
