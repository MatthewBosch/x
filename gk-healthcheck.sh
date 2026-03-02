#!/usr/bin/env bash
set -euo pipefail

# =======================
# Defaults (stable)
# =======================
NODE_RPC="${NODE_RPC:-http://node1.gonka.ai:8000/chain-rpc/}"
REST="${REST:-http://node1.gonka.ai:8000/chain-api}"

# Optional overrides
PUBLIC_URL="${PUBLIC_URL:-}"   # if unset, infer from PUBLIC_IP
PUBLIC_IP="${PUBLIC_IP:-}"

# Optional; if empty, we will try interactive prompt; if still empty, panel check is skipped
COLD_ADDR="${COLD_ADDR:-}"

# Optional
PARTICIPANT_ADDR="${PARTICIPANT_ADDR:-}"

ok(){ echo -e "✅ $*"; }
warn(){ echo -e "⚠️  $*"; }
bad(){ echo -e "❌ $*"; }
need_jq(){ command -v jq >/dev/null 2>&1; }

# ===== infer PUBLIC_IP / PUBLIC_URL automatically (best-effort, never hard-fail) =====
if [[ -z "${PUBLIC_IP}" && -n "${PUBLIC_URL}" ]]; then
  PUBLIC_IP="$(echo "$PUBLIC_URL" | sed -E 's#^https?://([^:/]+).*#\1#' || true)"
fi

if [[ -z "${PUBLIC_IP}" ]]; then
  # more robust than ifconfig.me in some regions; still best-effort
  PUBLIC_IP="$(curl -sS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
fi

if [[ -z "${PUBLIC_URL}" && -n "${PUBLIC_IP}" ]]; then
  PUBLIC_URL="http://${PUBLIC_IP}:8000"
fi

# ===== prompt for COLD_ADDR if missing (works even when script is piped) =====
prompt_cold_addr() {
  echo "============================================================"
  echo "COLD_ADDR is for panel(staking) consensus_pubkey check."
  echo "Example: gonka1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  echo "Non-interactive:"
  echo "  COLD_ADDR=gonka1... bash <(wget -qO- <raw-url>)"
  echo "============================================================"
  # Try to read from controlling TTY even if stdin is a pipe
  if [[ -r /dev/tty ]]; then
    read -r -p "Enter COLD_ADDR (gonka1...): " COLD_ADDR </dev/tty || true
  fi
}

if [[ -z "${COLD_ADDR}" ]]; then
  prompt_cold_addr
fi

if [[ -z "${COLD_ADDR}" ]]; then
  warn "COLD_ADDR not provided -> panel(staking) check will be skipped."
else
  ok "Using COLD_ADDR=$COLD_ADDR"
fi

# 你的 inference participant 地址（可不填：不填就只做 staking/panel + node/tmkms/local）
PARTICIPANT_ADDR="${PARTICIPANT_ADDR:-}"
