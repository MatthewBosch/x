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

# ========= Banner & Signature =========
show_banner() {
  clear
  echo -e "${BOLD}${BLUE}"
  echo "==============================================="
  echo "         Nockchain 安装助手 / Setup Tool        "
  echo "==============================================="
  echo -e "${RESET}"
  echo "📌 作者: Fsociety"
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
  sudo apt-get update
  sudo apt-get install -y screen curl git wget make gcc build-essential \
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
    make install-hoonc
  else
    echo "Hoon compiler already present."
  fi
  echo -e "${GREEN}[+] 环境准备完成 / Prerequisites ready.${RESET}"
}

# ========= 一键安装并构建 / Full setup =========
# 包括: 安装依赖、克隆/更新仓库、停止节点、编译、安装 Wallet 与 Node
setup_all() {
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
  make -j$CORE_COUNT build-hoon-all
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

# ========= 更新并构建 / Update & Build =========
# 拉取最新代码、停止节点并重新编译
update_and_build() {
  if [ ! -d "$NCK_DIR" ]; then
    echo -e "${RED}未找到本地仓库，请先使用选项 1 克隆或构建${RESET}"
    pause_and_return; return
  fi
  cd "$NCK_DIR"
  echo -e "[*] 拉取最新代码 / Pulling latest code..."
  git pull
  stop_nodes
  prompt_core_count
  echo -e "[*] 编译源码 / Building with ${CORE_COUNT} cores..."
  make -j$CORE_COUNT build
  echo -e "${GREEN}[+] 更新并构建完成 / Update & Build complete.${RESET}"
  pause_and_return
}

# ========= 安装钱包 / Install Wallet =========
install_wallet() {
  if [ ! -d "$NCK_DIR" ]; then
    echo -e "${RED}未找到本地仓库，请先使用选项 1 克隆或构建${RESET}"
    pause_and_return; return
  fi
  cd "$NCK_DIR"
  echo -e "[*] 安装钱包 / Installing Wallet..."
  make install-nockchain-wallet
  echo -e "${GREEN}[+] 钱包安装完成 / Wallet inaugurated.${RESET}"
  pause_and_return
}

# ========= 生成钱包 / Generate Wallet =========
generate_wallet() {
  if ! command_exists nockchain-wallet; then
    echo -e "${RED}钱包二进制未找到，请先安装钱包${RESET}"
    pause_and_return; return
  fi
  echo -e "[*] 生成钱包助记词 / Generating wallet seed..."
  nockchain-wallet keygen
  echo -e "${GREEN}[+] 助记词生成完毕，请妥善保存 / Seed generated. Save it securely.${RESET}"
  pause_and_return
}

# ========= 设置挖矿公钥 / Configure Mining Key =========
configure_mining_key() {
  if [ ! -d "$NCK_DIR" ]; then
    echo -e "${RED}未找到本地仓库，请先使用选项 1 克隆并构建${RESET}"
    pause_and_return; return
  fi
  cd "$NCK_DIR"
  read -rp "[?] 输入你的挖矿公钥 / Enter your mining public key: " key
  sed -i "s|^export MINING_PUBKEY :=.*$|export MINING_PUBKEY := $key|" Makefile
  echo -e "${GREEN}[+] 挖矿公钥已更新 / Mining key updated.${RESET}"
  pause_and_return
}

# ========= 检查 GitHub 更新 / Check for updates =========
check_updates() {
  echo -e "[*] 检查 GitHub 远端更新 / Checking GitHub for latest commit..."
  if [ -d "$NCK_DIR" ]; then
    cd "$NCK_DIR"
    git fetch origin
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    DATE=$(git log origin/$BRANCH -1 --format='%ci')
    echo -e "${GREEN}[+] 本地分支 $BRANCH, 远端最新提交: $DATE${RESET}"
  else
    DEFAULT_BRANCH=$(curl -s $GITHUB_API_REPO | jq -r .default_branch)
    DATE=$(curl -s "$GITHUB_API_REPO/commits/$DEFAULT_BRANCH" | jq -r .commit.committer.date)
    echo -e "${GREEN}[+] GitHub 默认分支 $DEFAULT_BRANCH 最新提交: $DATE${RESET}"
  fi
  pause_and_return
}

# ========= 启动 Leader 节点 / Start Leader Node =========
start_leader_node() {
  screen -S leader -dm bash -c "cd '$NCK_DIR' && make run-nockchain-leader"
  echo -e "${GREEN}[+] Leader 节点已启动 (screen: leader)${RESET}"
  pause_and_return
}

# ========= 启动 Follower 节点 / Start Follower Node =========
start_follower_node() {
  screen -S follower -dm bash -c "cd '$NCK_DIR' && make run-nockchain-follower"
  echo -e "${GREEN}[+] Follower 节点已启动 (screen: follower)${RESET}"
  pause_and_return
}

# ========= 查看节点日志 / View Node Logs =========
view_logs() {
  echo "选择日志查看 / Choose log to view:"
  echo "  1) Leader"
  echo "  2) Follower"
  echo "  0) 返回 / Back"
  read -rp "Choice: " log_choice
  case "$log_choice" in
    1) screen -r leader || echo -e "${RED}Leader 未运行${RESET}" ;;  
    2) screen -r follower || echo -e "${RED}Follower 未运行${RESET}" ;;  
    0) return ;;  
    *) echo -e "${RED}无效选项${RESET}" ;;  
  esac
  pause_and_return
}

# ========= 暂停并返回 / Pause & Return =========
pause_and_return() {
  read -n1 -rp "按任意键返回主菜单 / Press any key to return..." _
  main_menu
}

# ========= 主菜单 / Main Menu =========
main_menu() {
  show_banner
  echo "  1) 一键安装并构建 / Install & Build (依赖、更新、编译、安装)"
  echo "  2) 更新并构建 / Update & Build (拉取最新代码、停止节点、重编译)"
  echo "  3) 安装钱包 / Install Wallet"
  echo "  4) 生成钱包 / Generate Wallet"
  echo "  5) 设置挖矿公钥 / Set Mining Public Key"
  echo "  6) 检查 GitHub 更新 / Check GitHub Updates"
  echo "  7) 安装节点 / Install Nockchain Node"
  echo "  8) 启动 Leader 节点 / Start Leader Node"
  echo "  9) 启动 Follower 节点 / Start Follower Node"
  echo " 10) 查看节点日志 / View Node Logs"
  echo "  0) 退出 / Exit"
  echo ""
  read -rp "请输入编号 / Enter your choice: " choice
  case "$choice" in
    1) setup_all ;; 2) update_and_build ;; 3) install_wallet ;; 4) generate_wallet ;; 5) configure_mining_key ;; 6) check_updates ;; 7) install_nockchain ;; 8) start_leader_node ;; 9) start_follower_node ;; 10) view_logs ;; 0) echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;; *) echo -e "${RED}无效选项${RESET}"; pause_and_return ;;
  esac
}

# ========= 启动脚本 / Entry =========
main_menu
