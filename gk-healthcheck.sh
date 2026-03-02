#!/usr/bin/env bash
set -euo pipefail

# =======================
# Defaults (usually stable)
# =======================
NODE_RPC="${NODE_RPC:-http://node1.gonka.ai:8000/chain-rpc/}"
REST="${REST:-http://node1.gonka.ai:8000/chain-api}"

# Optional overrides
PUBLIC_URL="${PUBLIC_URL:-}"   # if unset, will try to infer from PUBLIC_IP
PUBLIC_IP="${PUBLIC_IP:-}"

# Required for panel(staking) check, but we can prompt interactively
COLD_ADDR="${COLD_ADDR:-}"

ok(){ echo -e "✅ $*"; }
warn(){ echo -e "⚠️  $*"; }
bad(){ echo -e "❌ $*"; }

need_jq(){ command -v jq >/dev/null 2>&1; }

# ===== infer PUBLIC_IP / PUBLIC_URL automatically =====
# 1) if PUBLIC_URL given -> derive PUBLIC_IP
if [[ -z "${PUBLIC_IP:-}" && -n "${PUBLIC_URL:-}" ]]; then
  PUBLIC_IP="$(echo "$PUBLIC_URL" | sed -E 's#^https?://([^:/]+).*#\1#')"
fi
# 2) if still no PUBLIC_IP -> query
if [[ -z "${PUBLIC_IP:-}" ]]; then
  PUBLIC_IP="$(curl -s --max-time 3 ifconfig.me || true)"
fi
# 3) if no PUBLIC_URL but have PUBLIC_IP -> default to :8000
if [[ -z "${PUBLIC_URL:-}" && -n "${PUBLIC_IP:-}" ]]; then
  PUBLIC_URL="http://${PUBLIC_IP}:8000"
fi

# ===== prompt for COLD_ADDR if missing (interactive only) =====
if [[ -z "${COLD_ADDR:-}" ]]; then
  echo "============================================================"
  echo "COLD_ADDR is required for panel(staking) consensus_pubkey check."
  echo "Example: gonka1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  echo "Tip: you can also run non-interactively:"
  echo "  COLD_ADDR=gonka1... bash <(wget -qO- <raw-url>)"
  echo "============================================================"
  if [[ -t 0 ]]; then
    read -r -p "Enter COLD_ADDR (gonka1...): " COLD_ADDR
  fi
  if [[ -z "${COLD_ADDR:-}" ]]; then
    warn "COLD_ADDR not provided -> panel(staking) check will be skipped."
  else
    ok "Using COLD_ADDR=$COLD_ADDR"
  fi
fi

# 你的 inference participant 地址（可不填：不填就只做 staking/panel + node/tmkms/local）
PARTICIPANT_ADDR="${PARTICIPANT_ADDR:-}"
