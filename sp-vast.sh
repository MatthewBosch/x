#!/usr/bin/env bash
set -euo pipefail

# =========================
# Spheron Fizz - Vast on-start
# =========================

LOG_BOOT="/root/spheron_fizz_boot.log"
LOG_RUN="/root/fizz.log"
BIN="/usr/local/bin/sphnctl"

# 【方式 A】明文 Token（建议仅自用实例使用）
TOKEN="0x19e7cf920b58bd3ffbfa0a7cfb9b3382994e1cedba6bdbb7c99a7b67579b493774aa06f5e23f598c8f6e322dbb7b2acc1e56d2c4411a91ebfd15effcdc300f8d01"

# 【方式 B】环境变量（如果上面留空，则从 SPHN_TOKEN 读取）
if [[ -z "${TOKEN}" ]]; then
  TOKEN="${SPHN_TOKEN:-}"
fi

# 若仍为空则退出
if [[ -z "${TOKEN}" ]]; then
  echo "[ERROR] No token provided. Set TOKEN in this script or pass SPHN_TOKEN as ENV." | tee -a "$LOG_BOOT"
  exit 1
fi

# 记录所有输出
exec > >(tee -a "$LOG_BOOT") 2>&1

echo "=== [Spheron Fizz Auto Setup @ $(date -u +'%F %TUTC')] ==="

# 1) 基础工具
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get install -y --no-install-recommends curl wget ca-certificates jq screen >/dev/null 2>&1 || true
update-ca-certificates >/dev/null 2>&1 || true

# 2) 安装 sphnctl（不依赖 sudo、不跑他们的 install.sh，以适配容器）
if ! command -v sphnctl >/dev/null 2>&1; then
  echo "[INFO] sphnctl not found, installing..."
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  URL=""
  if [[ "$OS" == "Linux" ]]; then
    if [[ "$ARCH" == "x86_64" ]]; then
      URL="https://release.sphnctl.sh/v2/bins/amd64/spheron"
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
      URL="https://release.sphnctl.sh/v2/bins/arm64/spheron"
    else
      echo "[ERROR] Unsupported arch: $ARCH"
      exit 1
    fi
  else
    echo "[ERROR] Unsupported OS: $OS"
    exit 1
  fi

  curl -fsSL "$URL" -o "$BIN"
  chmod +x "$BIN"
  echo "[INFO] sphnctl installed at $BIN"
fi

# 3) Optional: 显示 GPU（便于排障）
if command -v nvidia-smi >/dev/null 2>&1; then
  echo "[GPU] Detected NVIDIA GPU:"
  nvidia-smi || true
else
  echo "[WARN] nvidia-smi not found. If this machine should have GPU, ensure --gpus all and NVIDIA runtime are enabled."
fi

# 4) 启动 fizz（screen 守护 + 自动重启）
echo "[INFO] Starting Fizz node via screen..."
screen -S fizz -X quit || true
sleep 1
screen -dmS fizz bash -lc "
  echo '[fizz] starting with token...'
  while true; do
    $BIN fizz start --token ${TOKEN} 2>&1 | tee -a '$LOG_RUN'
    echo '[fizz] process exited. Restarting in 10s...'
    sleep 10
  done
"
echo "[OK] Fizz started in screen session 'fizz'. Logs -> $LOG_RUN"

# 5) 启动后检查
sleep 3
screen -ls || true
echo "=== [DONE @ $(date -u +'%F %TUTC')] ==="
echo "Attach:  screen -r fizz"
echo "Logs:    tail -f $LOG_RUN"
