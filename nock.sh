#!/usr/bin/env bash
# install_nockchain.sh: Enhanced interactive installer and manager for Nockchain
# Usage: sudo ./install_nockchain.sh

set -euo pipefail
IFS=$'\n\t'

# ========= 色彩定义 / Color Constants =========
RESET='\033[0m'
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'

# ========= 项目路径 / Project Directory =========
NCK_DIR="$HOME/nockchain"

# ========= GitHub API 信息 / GitHub Info =========
GITHUB_API_REPO="https://api.github.com/repos/zorp-corp/nockchain"

# ========= 横幅与署名 / Banner & Signature =========
show_banner() {
  clear
  echo -e "${BOLD}${BLUE}"
  echo "==============================================="
  echo "         Nockchain 安装助手 / Setup Tool        "
  echo "==============================================="
  echo -e "${RESET}"
  echo "📌 作者: K2 节点教程分享"
  echo "🔗 Telegram: https://t.me/+EaCiFDOghoM3Yzll"
  echo "🐦 Twitter:  https://x.com/BtcK241918"
  echo "-----------------------------------------------"
  echo ""
}

# ========= 检查命令是否存在 / Check command =========
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ========= 停止运行中的节点 / Stop running nodes =========
stop_nodes() {
  echo -e "[*] 检测并停止运行中的节点 / Stopping running nodes if any..."
  for session in leader follower; do
    if screen -list | grep -q "\.${session}[[:space:]]"; then
      echo -e "  停止 $session 节点 (screen: $session) / Stopping $session..."
      screen -S $session -X quit || true
    fi
  done
}

# ========= 提示输入 CPU 核心数 / Prompt core count =========
prompt_core_count() {
  read -rp "[?] 请输入用于编译的 CPU 核心数量 / Enter number of CPU cores for compilation: " CORE_COUNT
  if ! [[ "$CORE_COUNT" =~ ^[0-9]+$ ]] || [[ "$CORE_COUNT" -lt 1 ]]; then
    echo -e "${RED}[-] 输入无效，默认使用 1 核心 / Invalid input. Using 1 core.${RESET}"
    CORE_COUNT=1
  fi
}

# ========= 安装系统依赖 & Rust & Hoon / Install prerequisites =========
install_prerequisites() {
  echo -e "[*] 安装系统依赖 / Installing system dependencies..."
  apt-get update && apt install -y sudo
  sudo apt install -y screen curl git wget make gcc build-essential \
    jq pkg-config libssl-dev libleveldb-dev clang unzip nano \
    autoconf automake htop ncdu bsdmainutils tmux lz4 iptables nvme-cli libgbm1

  echo -e "[*] 安装 Rust / Installing Rust..."
  if ! command_exists rustup; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    rustup default stable
  else
    echo "Rustup already installed."
  fi

  echo -e "[*] 安装 Hoon 编译器 / Installing Hoon compiler..."
  if ! command_exists hoonc; then
    echo "[*] hoonc not found, building from upstream..."
    tmpdir=$(mktemp -d)
    if git clone https://github.com/urbit/hoon.git "$tmpdir/hoon" \
         && cd "$tmpdir/hoon" \
         && make \
         && sudo make install; then
      echo "[+] hoonc installed successfully."
    else
      echo -e "${YELLOW}[!] Failed to build hoonc; please install it manually if needed.${RESET}"
    fi
    cd - >/dev/null
    rm -rf "$tmpdir"
  else
    echo "Hoon compiler already present."
  fi

  echo -e "${GREEN}[+] 环境准备完成 / Prerequisites ready.${RESET}"
}

# ========= 一键安装并构建 / Full setup =========
setup_all() {
  show_banner
  install_prerequisites

  echo -e "[*] 获取或更新仓库 / Cloning or updating repository..."
  if [ -d "$NCK_DIR" ]; then
    cd "$NCK_DIR" && git pull
  else
    git clone --depth=1 https://github.com/zorp-corp/nockchain "$NCK_DIR"
    cd "$NCK_DIR"
  fi

  stop_nodes
  prompt_core_count
  echo -e "[*] 编译源码 / Building with ${CORE_COUNT} cores..."
  if command_exists hoonc; then
    echo "[*] 编译 Hoon 代码 / Building Hoon artifacts..."
    make -j$CORE_COUNT build-hoon-all
  else
    echo -e "${YELLOW}[!] 未检测到 hoonc，跳过 Hoon 代码编译 / hoonc not found, skipping build-hoon-all.${RESET}"
  fi
  make -j$CORE_COUNT build

  echo -e "[*] 安装 Wallet & Node / Installing Wallet & Nockchain..."
  make -j$CORE_COUNT install-nockchain-wallet
  make -j$CORE_COUNT install-nockchain

  echo -e "[*] 配置环境变量 / Setting environment variables..."
  RC_FILE="$HOME/.bashrc"
  [[ "$SHELL" == *"zsh"* ]] && RC_FILE="$HOME/.zshrc"
  grep -qxF "export PATH=\"\$PATH:$HOME/.cargo/bin:$NCK_DIR/target/release\"" "$RC_FILE" || \
    echo "export PATH=\"\$PATH:$HOME/.cargo/bin:$NCK_DIR/target/release\"" >> "$RC_FILE"
  grep -qxF "export RUST_LOG=info" "$RC_FILE" || echo "export RUST_LOG=info" >> "$RC_FILE"
  source "$RC_FILE"

  echo -e "${GREEN}[+] 安装完成 / Setup complete.${RESET}"
  pause_and_return
}

# ========= 生成钱包 / Generate Wallet =========
generate_wallet() {
  show_banner
  echo -e "[*] 生成钱包助记词 / Generating wallet seed..."
  if ! command_exists nockchain-wallet; then
    echo -e "${RED}[-] 错误：找不到 wallet 可执行文件，请确保编译成功。${RESET}"
    pause_and_return
    return
  fi
  nockchain-wallet keygen
  echo -e "${GREEN}[+] 助记词生成完毕，请妥善保存 / Seed generated. Save it securely.${RESET}"
  pause_and_return
}

# ========= 设置挖矿公钥 / Configure Mining Key =========
configure_mining_key() {
  show_banner
  if [ ! -f "$NCK_DIR/Makefile" ]; then
    echo -e "${RED}[-] 找不到 Makefile，无法设置公钥！${RESET}"
    pause_and_return
    return
  fi
  read -rp "[?] 输入你的挖矿公钥 / Enter your mining public key: " key
  sed -i "s|^export MINING_PUBKEY :=.*$|export MINING_PUBKEY := $key|" "$NCK_DIR/Makefile"
  echo -e "${GREEN}[+] 挖矿公钥已更新 / Mining key updated.${RESET}"
  pause_and_return
}

# ========= 启动 Leader 节点 / Start Leader Node =========
start_leader_node() {
  show_banner
  echo -e "[*] 启动 Leader 节点 / Starting leader node..."
  screen -S leader -dm bash -c "cd '$NCK_DIR' && make run-nockchain-leader"
  echo -e "${GREEN}[+] Leader 节点运行中 / Leader node running.${RESET}"
  echo -e "${YELLOW}[!] 正在进入日志界面，按 Ctrl+A+D 可退出 / Ctrl+A+D to detach.${RESET}"
  sleep 2
  screen -r leader
  pause_and_return
}

# ========= 启动 Follower 节点 / Start Follower Node =========
start_follower_node() {
  show_banner
  echo -e "[*] 启动 Follower 节点 / Starting follower node..."
  screen -S follower -dm bash -c "cd '$NCK_DIR' && make run-nockchain-follower"
  echo -e "${GREEN}[+] Follower 节点运行中 / Follower node running.${RESET}"
  echo -e "${YELLOW}[!] 正在进入日志界面，按 Ctrl+A+D 可退出 / Ctrl+A+D to detach.${RESET}"
  sleep 2
  screen -r follower
  pause_and_return
}

# ========= 查看节点日志 / View Logs =========
view_logs() {
  show_banner
  echo "查看节点日志 / View screen logs:"
  echo "  1) Leader 节点"
  echo "  2) Follower 节点"
  echo "  0) 返回主菜单 / Return to menu"
  read -rp "选择查看哪个节点日志 / Choose log to view: " log_choice
  case "$log_choice" in
    1) screen -r leader || echo -e "${RED}[-] Leader 节点未运行${RESET}" ;;  
    2) screen -r follower || echo -e "${RED}[-] Follower 节点未运行${RESET}" ;;  
    0) return ;;  
    *) echo -e "${RED}[-] 无效选项${RESET}" ;;  
  esac
  pause_and_return
}

# ========= 暂停并返回 / Pause & Return =========
pause_and_return() {
  read -n1 -rp "按任意键返回主菜单 / Press any key to return to menu..." _
  main_menu
}

# ========= 主菜单 / Main Menu =========
main_menu() {
  show_banner
  echo "请选择操作 / Please choose an option:"
  echo "  1) 一键安装并构建 / Install & Build"
  echo "  2) 生成钱包 / Generate Wallet"
  echo "  3) 设置挖矿公钥 / Set Mining Public Key"
  echo "  4) 启动 Leader 节点 / Start Leader Node (实时日志)"
  echo "  5) 启动 Follower 节点 / Start Follower Node (实时日志)"
  echo "  6) 查看节点日志 / View Node Logs"
  echo "  0) 退出 / Exit"
  read -rp "请输入编号 / Enter your choice: " choice

  case "$choice" in
    1) setup_all ;;
    2) generate_wallet ;;
    3) configure_mining_key ;;
    4) start_leader_node ;;
    5) start_follower_node ;;
    6) view_logs ;;
    0) echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
    *) echo -e "${RED}[-] 无效选项 / Invalid option.${RESET}"; pause_and_return ;;
  esac
}

# ========= 启动脚本 / Entry =========
main_menu
