#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Gonka Node Healthcheck (fixed full version)
# - Stable defaults for NODE_RPC/REST
# - AUTO PUBLIC_URL from PUBLIC_IP (or ipify)
# - COLD_ADDR: optional; if missing -> prompt via /dev/tty; if still missing -> skip panel check
# - Consensus key alignment: node/status vs tmkms vs leftover priv_validator_key.json vs panel(staking) vs participant(optional)
# - API callback env dump (api container)
# - Never spam huge outputs; panel/staking prints only the key
# - Avoid "docker exec -it" (TTY breakage in non-interactive runs)
# ============================================================

# -----------------------
# Defaults (usually stable)
# -----------------------
NODE_RPC="${NODE_RPC:-http://node1.gonka.ai:8000/chain-rpc/}"
REST="${REST:-http://node1.gonka.ai:8000/chain-api}"

# Optional overrides
PUBLIC_URL="${PUBLIC_URL:-}"     # if unset, infer from PUBLIC_IP
PUBLIC_IP="${PUBLIC_IP:-}"       # if unset, infer by ipify

# Optional; for panel(staking) consensus_pubkey check
COLD_ADDR="${COLD_ADDR:-}"

# Optional; if you want to compare chain participant.validator_key
PARTICIPANT_ADDR="${PARTICIPANT_ADDR:-}"

# Optional; key name if you later want to use keyring (not required anymore)
COLD_KEY_NAME="${COLD_KEY_NAME:-gonka-account-key}"

ok(){ echo -e "✅ $*"; }
warn(){ echo -e "⚠️  $*"; }
bad(){ echo -e "❌ $*"; }

need_jq(){ command -v jq >/dev/null 2>&1; }

# ========= Summary flags =========
TIME_OK=1
CHAIN_OK=1
PORT_OK=1
CONS_OK=1
CALLBACK_OK=1

# -----------------------
# Helpers
# -----------------------
check_http(){
  local name="$1" url="$2"
  local code
  code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "$url" || echo 000)"
  if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    ok "$name => $code"
    return 0
  else
    bad "$name => $code ($url)"
    PORT_OK=0
    return 1
  fi
}

prompt_cold_addr() {
  echo "============================================================"
  echo "COLD_ADDR is used ONLY for panel(staking) consensus_pubkey check."
  echo "Example: gonka1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  echo "Non-interactive usage:"
  echo "  COLD_ADDR=gonka1... bash <(wget -qO- <raw-url>)"
  echo "============================================================"
  # Read from controlling TTY even when script is piped
  if [[ -r /dev/tty ]]; then
    read -r -p "Enter COLD_ADDR (gonka1...): " COLD_ADDR </dev/tty || true
  fi
}

# Prefer host :26657 if exposed; otherwise inside node container (127.0.0.1:26657)
get_chain_status_json() {
  if curl -fsS --max-time 3 http://127.0.0.1:26657/status >/dev/null 2>&1; then
    curl -fsS --max-time 5 http://127.0.0.1:26657/status
    return 0
  fi
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx node; then
    docker exec node sh -lc 'wget -qO- http://127.0.0.1:26657/status' 2>/dev/null && return 0
  fi
  return 1
}

# Consensus pubkey from comet/tendermint /status
get_node_status_pubkey_b64(){
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx node; then
    docker exec node sh -lc 'wget -qO- http://127.0.0.1:26657/status' 2>/dev/null \
      | jq -r '.result.validator_info.pub_key.value // empty' 2>/dev/null || true
  else
    curl -sS --max-time 5 http://127.0.0.1:26657/status 2>/dev/null \
      | jq -r '.result.validator_info.pub_key.value // empty' 2>/dev/null || true
  fi
}

# Leftover priv_validator_key.json inside node container (should be UNUSED when using tmkms)
get_leftover_privval_pubkey_b64(){
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx node; then
    docker exec node sh -lc 'test -f /root/.inference/config/priv_validator_key.json && cat /root/.inference/config/priv_validator_key.json || true' 2>/dev/null \
      | jq -r '.pub_key.value // empty' 2>/dev/null || true
  else
    echo ""
  fi
}

# TMKMS pubkey: parse recent logs for {"key":"..."} line under "Pubkey:"
get_tmkms_pubkey_b64(){
  local k=""
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx tmkms; then
    k="$(docker logs --tail 600 tmkms 2>/dev/null \
      | sed -n 's/.*"key":[[:space:]]*"\([^"]*\)".*/\1/p' \
      | tail -n 1)"
    echo "${k:-}"
    return 0
  fi
  echo ""
}

# Optional: chain participant.validator_key (inference module), only if PARTICIPANT_ADDR provided
get_chain_participant_validator_key_b64(){
  if [[ -n "${PARTICIPANT_ADDR:-}" ]] && need_jq; then
    ./inferenced query inference show-participant "$PARTICIPANT_ADDR" \
      --node "$NODE_RPC" --chain-id gonka-mainnet -o json 2>/dev/null \
      | jq -r '.participant.validator_key // empty' 2>/dev/null || true
  else
    echo ""
  fi
}

# Panel/staking consensus_pubkey (only prints key, no huge output)
get_panel_consensus_pubkey_b64(){
  local cold_acc="$1"
  ./inferenced query staking delegator-validators "$cold_acc" \
    --node "$NODE_RPC" --chain-id gonka-mainnet -o json 2>/dev/null \
  | jq -r '.validators[0].consensus_pubkey.value // empty' 2>/dev/null || true
}

# -----------------------
# Infer PUBLIC_IP / PUBLIC_URL (best effort; never hard-fail)
# -----------------------
if [[ -z "${PUBLIC_IP}" && -n "${PUBLIC_URL}" ]]; then
  PUBLIC_IP="$(echo "$PUBLIC_URL" | sed -E 's#^https?://([^:/]+).*#\1#' || true)"
fi
if [[ -z "${PUBLIC_IP}" ]]; then
  PUBLIC_IP="$(curl -sS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
fi
if [[ -z "${PUBLIC_URL}" && -n "${PUBLIC_IP}" ]]; then
  PUBLIC_URL="http://${PUBLIC_IP}:8000"
fi

FOLLOW_MODE=0
if [[ "${1:-}" == "--follow" ]]; then
  FOLLOW_MODE=1
fi

# -----------------------
# COLD_ADDR prompt (optional)
# -----------------------
if [[ -z "${COLD_ADDR}" ]]; then
  prompt_cold_addr
fi
if [[ -n "${COLD_ADDR}" ]]; then
  ok "Using COLD_ADDR=$COLD_ADDR"
else
  warn "COLD_ADDR not provided -> panel(staking) check will be skipped."
fi

# ============================================================
# 0) Basic info
# ============================================================
echo "===== 0) 基础信息 ====="
echo "HOST TIME:  $(date -Is)"
echo "UTC TIME:   $(date -u -Is)"
echo "HOSTNAME:   $(hostname)"
echo "NODE_RPC:   $NODE_RPC"
echo "REST:       $REST"
echo "PUBLIC_IP:  ${PUBLIC_IP:-<unknown>}"
echo "PUBLIC_URL: ${PUBLIC_URL:-<unset>}"
echo "COLD_ADDR:  ${COLD_ADDR:-<unset>}"
echo "PARTICIPANT_ADDR: ${PARTICIPANT_ADDR:-<unset>}"
echo

# ============================================================
# 1) Docker containers
# ============================================================
echo "===== 1) Docker 容器 ====="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | sed -n '1,200p' || true
echo

# ============================================================
# 2) Host port listeners (no need to require host 26657)
# ============================================================
echo "===== 2) 端口监听（宿主机） ====="
(ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null || true) \
  | egrep ':(5050|8080|5000|5001|5002|9100|9200|8000)\b' || true
echo

# ============================================================
# 2.5) API callback env (inside api container)
# ============================================================
echo "===== 2.5) API 回调地址（api 容器 env） ====="
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx api; then
  CALLBACK_LINE="$(
    docker exec api sh -lc 'env | egrep -i "DAPI_API__POC_CALLBACK_URL|DAPI_API__PUBLIC_URL|POC_CALLBACK|CALLBACK|WEBHOOK|URL" | sort' \
      2>/dev/null || true
  )"
  if [[ -n "${CALLBACK_LINE}" ]]; then
    ok "api callback env:"
    echo "$CALLBACK_LINE" | sed 's/^/  /'
  else
    warn "api 容器未找到 callback 相关 env（可能变量名不同或未注入）"
    CALLBACK_OK=0
  fi
else
  warn "api 容器未运行，无法读取回调地址"
  CALLBACK_OK=0
fi
echo

# ============================================================
# 3) Chain sync status (/status)
# ============================================================
echo "===== 3) 链同步状态（26657）====="
STATUS_JSON=""
if ! need_jq; then
  warn "未安装 jq：sudo apt-get update && sudo apt-get install -y jq"
  CHAIN_OK=0
else
  STATUS_JSON="$(get_chain_status_json || true)"
  if [[ -z "${STATUS_JSON}" ]]; then
    bad "无法获取链 /status（宿主机和 node 容器都不可达）"
    CHAIN_OK=0
  else
    height="$(echo "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)"
    catching="$(echo "$STATUS_JSON" | jq -r '.result.sync_info.catching_up // empty' 2>/dev/null || true)"
    btime="$(echo "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_time // empty' 2>/dev/null || true)"
    echo "{"
    echo "  \"latest_block_height\": \"${height:-}\""
    echo "  \"catching_up\": ${catching:-null}"
    echo "  \"latest_block_time\": \"${btime:-}\""
    echo "}"
    if [[ "${catching}" == "false" ]]; then
      ok "catching_up=false（已同步）"
    else
      bad "catching_up=${catching:-<empty>}（未同步/追块中）"
      CHAIN_OK=0
    fi
  fi
fi
echo

# ============================================================
# 3.5) Consensus Key alignment
# ============================================================
echo "===== 3.5) Consensus Key 对齐检查（本地/容器/链上/面板） ====="
if ! need_jq; then
  warn "缺 jq，跳过 consensus key 全量比对"
  CONS_OK=0
else
  NODE_STATUS_KEY="$(get_node_status_pubkey_b64 | tr -d '\r\n' || true)"
  TMKMS_KEY="$(get_tmkms_pubkey_b64 | tr -d '\r\n' || true)"
  LEFTOVER_KEY="$(get_leftover_privval_pubkey_b64 | tr -d '\r\n' || true)"
  CHAIN_PART_KEY="$(get_chain_participant_validator_key_b64 | tr -d '\r\n' || true)"

  PANEL_KEY=""
  if [[ -n "${COLD_ADDR}" ]]; then
    PANEL_KEY="$(get_panel_consensus_pubkey_b64 "$COLD_ADDR" | tr -d '\r\n' || true)"
  fi

  echo "=== (B) node /status consensus pubkey ==="
  echo "${NODE_STATUS_KEY:-<empty>}"
  echo
  echo "=== (C) tmkms consensus pubkey (from logs) ==="
  echo "${TMKMS_KEY:-<empty>}"
  echo
  echo "=== (D) leftover priv_validator_key.json pubkey (should be UNUSED) ==="
  echo "${LEFTOVER_KEY:-<empty>}"
  echo
  echo "=== (A) chain participant validator_key (optional) ==="
  echo "${CHAIN_PART_KEY:-<skipped/unset>}"
  echo
  echo "=== (P) panel consensus_pubkey (staking delegator-validators) ==="
  if [[ -n "${COLD_ADDR}" ]]; then
    echo "${PANEL_KEY:-<empty>}"
  else
    echo "<skipped/unset>"
  fi
  echo

  CORE_OK=1

  if [[ -z "${NODE_STATUS_KEY}" || -z "${TMKMS_KEY}" ]]; then
    bad "node/status 或 tmkms pubkey 为空，无法判断对齐"
    CORE_OK=0
  else
    if [[ "${NODE_STATUS_KEY}" == "${TMKMS_KEY}" ]]; then
      ok "核心一致：node/status == tmkms"
    else
      bad "核心不一致：node/status != tmkms"
      CORE_OK=0
    fi
  fi

  if [[ -n "${CHAIN_PART_KEY}" && -n "${NODE_STATUS_KEY}" ]]; then
    if [[ "${CHAIN_PART_KEY}" == "${NODE_STATUS_KEY}" ]]; then
      ok "参与者登记一致：chain participant validator_key == node/status"
    else
      warn "参与者登记不一致：chain participant validator_key != node/status（可能需要重新 submit-new-participant 或 participant 地址不是这台）"
      CORE_OK=0
    fi
  fi

  if [[ -n "${COLD_ADDR}" && -n "${PANEL_KEY}" && -n "${NODE_STATUS_KEY}" ]]; then
    if [[ "${PANEL_KEY}" == "${NODE_STATUS_KEY}" ]]; then
      ok "面板(staking)一致：panel consensus_pubkey == node/status"
    else
      warn "面板(staking)不一致：panel consensus_pubkey != node/status（通常表示：你当前签名身份不属于这个旧 validator）"
      # 注意：不把它算作 CONS_OK 失败（因为你可能正在新旧迁移）
    fi
  fi

  if [[ -n "${LEFTOVER_KEY}" && -n "${NODE_STATUS_KEY}" ]]; then
    if [[ "${LEFTOVER_KEY}" == "${NODE_STATUS_KEY}" ]]; then
      warn "残留 priv_validator_key.json == node/status：你可能仍在用本地 privval（检查 config.toml 是否走 priv_validator_laddr 远程签名）"
      # 这也不强制置失败，但强烈提示
    else
      ok "残留 priv_validator_key.json 与当前共识 pubkey 不同（符合“残留/unused”预期）"
    fi
  fi

  if [[ "$CORE_OK" -ne 1 ]]; then
    CONS_OK=0
  fi
fi
echo

# ============================================================
# 4) Time drift (host vs remote vs chain vs containers)
# ============================================================
echo "===== 4) 时间对比（宿主 / 公网 / 链 / 容器）====="
HOST_EPOCH="$(date -u +%s)"
echo "[HOST] epoch=$HOST_EPOCH"

HTTP_DATE="$(curl -fsSI --max-time 5 https://google.com 2>/dev/null \
  | awk 'BEGIN{IGNORECASE=1}/^Date:/{sub(/^[Dd]ate:[ ]*/,"");print;exit}' || true)"

if [[ -n "$HTTP_DATE" ]] && command -v python3 >/dev/null 2>&1; then
  echo "[HTTP] Date: $HTTP_DATE"
  REMOTE_EPOCH="$(python3 - "$HTTP_DATE" <<'PY'
import email.utils,sys
dt=email.utils.parsedate_to_datetime(sys.argv[1])
print(int(dt.timestamp()))
PY
  )"
  drift=$((HOST_EPOCH - REMOTE_EPOCH))
  abs=${drift#-}
  echo "→ Drift(host-remote): ${drift}s"
  if [[ "$abs" -le 5 ]]; then
    ok "公网时间 OK"
  elif [[ "$abs" -le 30 ]]; then
    warn "公网时间漂移 ${abs}s"
    TIME_OK=0
  else
    bad "公网时间漂移 ${abs}s"
    TIME_OK=0
  fi
else
  warn "无法获取/解析公网时间（curl 或 python3 不可用）"
  TIME_OK=0
fi
echo

if need_jq && command -v python3 >/dev/null 2>&1; then
  if [[ -z "${STATUS_JSON:-}" ]]; then
    STATUS_JSON="$(get_chain_status_json || true)"
  fi
  CHAIN_TIME="$(echo "${STATUS_JSON:-}" | jq -r '.result.sync_info.latest_block_time // empty' 2>/dev/null || true)"
  if [[ -n "$CHAIN_TIME" ]]; then
    echo "[CHAIN] latest_block_time: $CHAIN_TIME"
    CHAIN_EPOCH="$(python3 - "$CHAIN_TIME" <<'PY'
import sys,re,datetime
s=sys.argv[1].replace("Z","+00:00")
m=re.match(r"(.*\.\d{6})\d*(\+00:00)",s)
if m: s=m.group(1)+m.group(2)
dt=datetime.datetime.fromisoformat(s)
print(int(dt.timestamp()))
PY
    )"
    drift=$((HOST_EPOCH - CHAIN_EPOCH))
    abs=${drift#-}
    echo "→ Drift(host-chain): ${drift}s"
    if [[ "$abs" -le 30 ]]; then
      ok "链最新块时间差 ${abs}s（正常范围内）"
    elif [[ "$abs" -le 120 ]]; then
      warn "链最新块时间差 ${abs}s（可能网络/轻微延迟）"
    else
      warn "链最新块时间差 ${abs}s（若高度不增长/ catching_up=true 才算异常）"
    fi
  else
    warn "无法获取链 latest_block_time（/status 不可用或解析失败）"
  fi
else
  warn "缺 jq 或 python3，跳过链时间对比"
fi
echo

echo "[CONTAINERS]"
for c in api node tmkms inference join-mlnode-308-1 join-api-1 join-inference-1; do
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
    CE="$(docker exec "$c" sh -lc 'date -u +%s 2>/dev/null || date +%s 2>/dev/null' 2>/dev/null || true)"
    CT="$(docker exec "$c" sh -lc 'date -u -Is 2>/dev/null || date -Is 2>/dev/null' 2>/dev/null || true)"
    if [[ -n "$CE" ]]; then
      drift=$((HOST_EPOCH - CE))
      abs=${drift#-}
      echo "[$c] ${CT:-<no-date>} drift=${drift}s"
      if [[ "$abs" -le 5 ]]; then
        ok "$c 时间 OK"
      elif [[ "$abs" -le 30 ]]; then
        warn "$c 时间漂移 ${abs}s"
        TIME_OK=0
      else
        bad "$c 时间漂移 ${abs}s"
        TIME_OK=0
      fi
    else
      warn "$c 无法读取时间（镜像无 date？）"
      TIME_OK=0
    fi
  fi
done
echo

# ============================================================
# 5) Admin API
# ============================================================
echo "===== 5) Admin API ====="
POC_YES=0
POC_WEIGHT=-1

if need_jq; then
  ADMIN_JSON="$(curl -sS --max-time 3 http://127.0.0.1:9200/admin/v1/nodes 2>/dev/null || true)"
  if [[ -z "$ADMIN_JSON" ]]; then
    bad "9200/admin/v1/nodes 无响应"
    PORT_OK=0
  else
    echo "$ADMIN_JSON" | jq '.[]
      | {
          node_id:.node.id,
          host:.node.host,
          current_status:.state.current_status,
          intended_status:.state.intended_status,
          models:(.node.models|keys),
          epoch_models:(.state.epoch_models|keys),
          epoch_ml_nodes:(.state.epoch_ml_nodes|to_entries|map({model:.key,poc_weight:(.value.poc_weight//-1),timeslot:.value.timeslot_allocation}))
        }'

    POC_WEIGHT="$(echo "$ADMIN_JSON" | jq -r '
      .[0] as $x
      | ( ($x.state.epoch_models|keys)[0] // ($x.node.models|keys)[0] ) as $m
      | ($x.state.epoch_ml_nodes[$m].poc_weight // -1)
    ' 2>/dev/null || echo -1)"

    if [[ "${POC_WEIGHT:- -1}" -gt 0 ]] 2>/dev/null; then
      POC_YES=1
    else
      POC_YES=0
      POC_WEIGHT=-1
    fi
  fi
else
  warn "无 jq，跳过 Admin API 解析"
  PORT_OK=0
fi
echo

# ============================================================
# 6) Inference endpoints
# ============================================================
echo "===== 6) 推理入口可达性 ====="
check_http "5050 /health" "http://127.0.0.1:5050/health" || true
check_http "5050 /v1/models" "http://127.0.0.1:5050/v1/models" || true

if [[ -n "${PUBLIC_URL:-}" ]]; then
  check_http "PUBLIC /health" "${PUBLIC_URL%/}/health" || true
else
  warn "PUBLIC_URL 未能确定，跳过外网检查"
  PORT_OK=0
fi
echo

# ============================================================
# 7) GPU checks (optional)
# ============================================================
echo "===== 7) GPU / Docker Runtime（重点看 join-mlnode-308-1） ====="
if command -v nvidia-smi >/dev/null 2>&1; then
  echo "[Driver / GPU]"
  nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,utilization.gpu,temperature.gpu \
    --format=csv,noheader || true
else
  warn "未检测到 nvidia-smi（GPU 驱动缺失或此机无 GPU）"
fi
echo

echo "===== mlnode GPU runtime check ====="
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx join-mlnode-308-1; then
  if need_jq; then
    GPU_OK="$(
      docker inspect join-mlnode-308-1 --format '{{json .HostConfig.DeviceRequests}}' 2>/dev/null \
      | jq -e '.[]? | select(.Driver=="nvidia") | select(.Capabilities[]? | index(["gpu"]))' >/dev/null 2>&1 \
      && echo 1 || echo 0
    )"
    if [[ "$GPU_OK" == "1" ]]; then
      ok 'DeviceRequests: Driver="nvidia", Capabilities include gpu'
    else
      bad 'DeviceRequests 未包含 Driver="nvidia" + gpu'
    fi
  else
    warn "缺少 jq，无法解析 DeviceRequests"
  fi
else
  warn "join-mlnode-308-1 未运行（此项跳过）"
fi
echo

# ============================================================
# 8) FOLLOW logs (optional)
# ============================================================
if [[ "$FOLLOW_MODE" -eq 1 ]]; then
  echo "===== 8) FOLLOW: join-mlnode-308-1 关键需求日志（同一时间戳最多2行） ====="
  echo "按 Ctrl+C 退出"
  docker logs -f --timestamps join-mlnode-308-1 2>&1 \
  | egrep --line-buffered --color=always -i \
    '/api/v1/pow/init/(generate|validate)|/api/v1/pow/validate|NotEnoughGPUResources|no GPU support|CUDA is not available|Internal Server Error|vLLM process exited prematurely|Failed to start VLLM' \
  | awk '
      /200 OK/ {next}
      {
        ts=$1
        if (ts != last_ts) { last_ts=ts; cnt=0 }
        if (cnt < 2) { print; cnt++ }
      }'
  exit 0
fi

# ============================================================
# Conclusion
# ============================================================
echo "===== 结论 ====="
if [[ "$TIME_OK" -eq 1 && "$CHAIN_OK" -eq 1 && "$PORT_OK" -eq 1 && "$CONS_OK" -eq 1 ]]; then
  echo "✔ 时间一致 + 链同步 + 端口正常 + 共识 key 核心对齐"
else
  echo "⚠️ 节点存在问题："
  [[ "$TIME_OK" -ne 1 ]] && echo "  - 时间检查未通过（宿主/公网/容器漂移）"
  [[ "$CHAIN_OK" -ne 1 ]] && echo "  - 链同步异常（catching_up!=false 或无法获取 /status）"
  [[ "$PORT_OK" -ne 1 ]] && echo "  - 端口/可达性异常（5050/8000/9200/容器接口）"
  [[ "$CONS_OK" -ne 1 ]] && echo "  - 共识 key 核心不一致（node/status vs tmkms vs chain participant(如启用)）"
  [[ "$CALLBACK_OK" -ne 1 ]] && echo "  - api 回调地址未能确认（容器 env 未发现/容器未运行）"
fi
echo

echo "===== PoC ====="
if [[ "${POC_YES:-0}" -eq 1 ]]; then
  echo "PoC: YES"
  echo "PoC weight: ${POC_WEIGHT}"
else
  echo "PoC: NO"
  echo "PoC weight: -1"
fi
