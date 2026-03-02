#!/usr/bin/env bash
set -euo pipefail

# ===== user-provided addresses / endpoints =====
COLD_ADDR="${COLD_ADDR:-}"                 # 必填：gonka1... 冷钱包 acc 地址（面板/链上 validator 信息用它查）
NODE_RPC="${NODE_RPC:-http://node1.gonka.ai:8000/chain-rpc/}"
REST="${REST:-http://node1.gonka.ai:8000/chain-api}"
PUBLIC_URL="${PUBLIC_URL:-}"
PUBLIC_IP="${PUBLIC_IP:-}"

# 可选：你的 inference participant 地址（不填就跳过 participant.validator_key 对比）
PARTICIPANT_ADDR="${PARTICIPANT_ADDR:-}"

if [[ -z "$COLD_ADDR" ]]; then
  echo "❌ COLD_ADDR is required (cold account bech32 address, e.g. gonka1...)"
  echo "   Usage: COLD_ADDR=gonka1... bash <(curl -fsSL <raw>)"
  exit 2
fi

ok(){ echo -e "✅ $*"; }
warn(){ echo -e "⚠️  $*"; }
bad(){ echo -e "❌ $*"; }

need_jq(){ command -v jq >/dev/null 2>&1; }

# ========= 结果汇总变量（结论必须基于它们） =========
TIME_OK=1
CHAIN_OK=1
PORT_OK=1
CONS_OK=1
CALLBACK_OK=1

# 端口/HTTP 检测 helper：非 2xx 视为失败
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

# ============================================================
# 链状态（26657） helper：优先宿主机 -> 回退到 node 容器
# ============================================================
get_chain_status_json() {
  if curl -fsS --max-time 3 http://127.0.0.1:26657/status >/dev/null 2>&1; then
    curl -fsS --max-time 5 http://127.0.0.1:26657/status
    return 0
  fi
  if docker ps --format '{{.Names}}' | grep -qx node; then
    docker exec node sh -lc 'wget -qO- http://127.0.0.1:26657/status' 2>/dev/null && return 0
  fi
  return 1
}

# ============================================================
# Consensus Key 相关 helper
# ============================================================
get_node_status_pubkey_b64(){
  local js=""
  js="$(get_chain_status_json 2>/dev/null || true)"
  if [[ -n "${js:-}" ]] && need_jq; then
    echo "$js" | jq -r '.result.validator_info.pub_key.value // empty' 2>/dev/null || true
  else
    echo ""
  fi
}

get_local_privval_pubkey_b64(){
  # node 容器里残留的 priv_validator_key.json (应当 UNUSED)
  if docker ps --format '{{.Names}}' | grep -qx node && need_jq; then
    docker exec node sh -lc 'test -f /root/.inference/config/priv_validator_key.json && cat /root/.inference/config/priv_validator_key.json || true' 2>/dev/null \
      | jq -r '.pub_key.value // empty' 2>/dev/null || true
  else
    echo ""
  fi
}

get_tmkms_pubkey_b64(){
  # 只从 logs 抓，避免误读 softsign 文件内容
  local k=""
  if docker ps --format '{{.Names}}' | grep -qx tmkms; then
    k="$(docker logs --tail 600 tmkms 2>/dev/null \
      | sed -n 's/.*"key":[[:space:]]*"\([^"]*\)".*/\1/p' \
      | tail -n 1 | tr -d '\r\n')"
    echo "$k"
    return 0
  fi
  echo ""
}

get_chain_participant_validator_key_b64(){
  if [[ -n "${PARTICIPANT_ADDR:-}" ]] && need_jq; then
    ./inferenced --node "$NODE_RPC" --chain-id gonka-mainnet \
      query inference show-participant "$PARTICIPANT_ADDR" -o json 2>/dev/null \
      | jq -r '.participant.validator_key // empty' 2>/dev/null || true
  else
    echo ""
  fi
}

get_panel_consensus_pubkey_b64(){
  # “面板”= staking delegator-validators <cold acc address> 的 consensus_pubkey.value
  local cold_acc="$1"
  if need_jq; then
    ./inferenced query staking delegator-validators "$cold_acc" \
      --node "$NODE_RPC" --chain-id gonka-mainnet -o json 2>/dev/null \
    | jq -r '.validators[0].consensus_pubkey.value // empty' 2>/dev/null || true
  else
    echo ""
  fi
}

# ===== 公网信息 =====
if [[ -z "${PUBLIC_IP:-}" ]] && [[ -n "${PUBLIC_URL:-}" ]]; then
  PUBLIC_IP="$(echo "$PUBLIC_URL" | sed -E 's#^https?://([^:/]+).*#\1#')"
fi
[[ -z "${PUBLIC_IP:-}" ]] && PUBLIC_IP="$(curl -s --max-time 3 ifconfig.me || true)"

FOLLOW_MODE=0
[[ "${1:-}" == "--follow" ]] && FOLLOW_MODE=1

echo "===== 0) 基础信息 ====="
echo "HOST TIME:  $(date -Is)"
echo "UTC TIME:   $(date -u -Is)"
echo "HOSTNAME:   $(hostname)"
echo "NODE_RPC:   $NODE_RPC"
echo "REST:       $REST"
echo "COLD_ADDR:  $COLD_ADDR"
echo "PUBLIC_IP:  ${PUBLIC_IP:-<unknown>}"
echo "PUBLIC_URL: ${PUBLIC_URL:-<unset>}"
echo

echo "===== 2.5) API 回调地址（api 容器 env） ====="
if docker ps --format '{{.Names}}' | grep -qx api; then
  CALLBACK_LINE="$(docker exec api sh -lc 'env | egrep -i "DAPI_API__POC_CALLBACK_URL|POC_CALLBACK|CALLBACK|WEBHOOK|DAPI_API__PUBLIC_URL" | sort' 2>/dev/null || true)"
  if [[ -n "${CALLBACK_LINE:-}" ]]; then
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

echo "===== 3) 链同步状态（26657）====="
STATUS_JSON=""
if ! need_jq; then
  warn "未安装 jq：sudo apt-get update && sudo apt-get install -y jq"
  CHAIN_OK=0
else
  STATUS_JSON="$(get_chain_status_json || true)"
  if [[ -z "${STATUS_JSON:-}" ]]; then
    bad "无法获取链 /status（宿主机和 node 容器都不可达）"
    CHAIN_OK=0
  else
    SYNC_BRIEF_RAW="$(echo "$STATUS_JSON" | jq '.result.sync_info | {latest_block_height, catching_up, latest_block_time}' 2>/dev/null || true)"
    if [[ -z "$SYNC_BRIEF_RAW" ]]; then
      bad "无法解析 /status 的 sync_info"
      CHAIN_OK=0
    else
      catching="$(echo "$SYNC_BRIEF_RAW" | jq -r '.catching_up' 2>/dev/null || echo "")"
      height="$(echo "$SYNC_BRIEF_RAW"   | jq -r '.latest_block_height' 2>/dev/null || echo "")"
      btime="$(echo "$SYNC_BRIEF_RAW"    | jq -r '.latest_block_time' 2>/dev/null || echo "")"
      echo "$SYNC_BRIEF_RAW"

      if [[ "$catching" == "false" ]]; then
        ok "catching_up=false（已同步）"
      else
        bad "catching_up=${catching:-<empty>}（未同步/追块中）"
        CHAIN_OK=0
      fi
    fi
  fi
fi
echo

echo "===== 3.5) Consensus Key 对齐检查（本地/容器/链上/面板） ====="
if ! need_jq; then
  warn "缺 jq，跳过 consensus key 全量比对"
  CONS_OK=0
else
  NODE_STATUS_KEY="$(get_node_status_pubkey_b64 | tr -d '\r\n' || true)"
  TMKMS_KEY="$(get_tmkms_pubkey_b64 | tr -d '\r\n' || true)"
  LOCAL_PRIVVAL_KEY="$(get_local_privval_pubkey_b64 | tr -d '\r\n' || true)"
  CHAIN_PARTICIPANT_KEY="$(get_chain_participant_validator_key_b64 | tr -d '\r\n' || true)"
  PANEL_KEY="$(get_panel_consensus_pubkey_b64 "$COLD_ADDR" | tr -d '\r\n' || true)"

  echo "=== (A) chain participant validator_key (optional) ==="
  echo "${CHAIN_PARTICIPANT_KEY:-<skipped/unset>}"
  echo
  echo "=== (B) node /status consensus pubkey ==="
  echo "${NODE_STATUS_KEY:-<empty>}"
  echo
  echo "=== (C) tmkms consensus pubkey (from logs) ==="
  echo "${TMKMS_KEY:-<empty>}"
  echo
  echo "=== (D) leftover priv_validator_key.json pubkey (should be UNUSED) ==="
  echo "${LOCAL_PRIVVAL_KEY:-<empty>}"
  echo
  echo "=== (P) panel consensus_pubkey (staking delegator-validators) ==="
  echo "${PANEL_KEY:-<empty>}"
  echo

  CORE_OK=1
  if [[ -z "${NODE_STATUS_KEY:-}" || -z "${TMKMS_KEY:-}" ]]; then
    bad "node/status 或 tmkms pubkey 为空，无法判断对齐"
    CORE_OK=0
  else
    if [[ "$NODE_STATUS_KEY" == "$TMKMS_KEY" ]]; then
      ok "核心一致：node/status == tmkms"
    else
      bad "核心不一致：node/status != tmkms"
      CORE_OK=0
    fi
  fi

  if [[ -n "${CHAIN_PARTICIPANT_KEY:-}" && -n "${NODE_STATUS_KEY:-}" ]]; then
    if [[ "$CHAIN_PARTICIPANT_KEY" == "$NODE_STATUS_KEY" ]]; then
      ok "参与者登记一致：chain participant validator_key == node/status"
    else
      warn "参与者登记不一致：chain participant validator_key != node/status"
      CORE_OK=0
    fi
  fi

  if [[ -n "${PANEL_KEY:-}" && -n "${NODE_STATUS_KEY:-}" ]]; then
    if [[ "$PANEL_KEY" == "$NODE_STATUS_KEY" ]]; then
      ok "面板(staking)一致：panel consensus_pubkey == node/status"
    else
      warn "面板(staking)不一致：panel consensus_pubkey != node/status（旧 validator 的共识公钥没变/你现在签名身份不是它）"
    fi
  fi

  if [[ -n "${LOCAL_PRIVVAL_KEY:-}" && -n "${NODE_STATUS_KEY:-}" ]]; then
    if [[ "$LOCAL_PRIVVAL_KEY" == "$NODE_STATUS_KEY" ]]; then
      warn "残留 priv_validator_key.json == node/status：可能仍在用本地 privval（检查 config.toml 的 priv_validator_laddr / priv_validator_key_file）"
    else
      ok "残留 priv_validator_key.json 与当前共识 pubkey 不同（符合“残留/unused”预期）"
    fi
  fi

  [[ "$CORE_OK" -ne 1 ]] && CONS_OK=0
fi
echo

echo "===== 4) 时间对比（宿主 / 公网 / 链 / 容器）====="
HOST_EPOCH="$(date -u +%s)"
echo "[HOST] epoch=$HOST_EPOCH"

HTTP_DATE="$(curl -fsSI --max-time 5 https://google.com \
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
  [[ -z "${STATUS_JSON:-}" ]] && STATUS_JSON="$(get_chain_status_json || true)"
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
      warn "链最新块时间差 ${abs}s（可能轻微延迟）"
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
for c in api node inference join-mlnode-308-1 join-api-1 join-inference-1 tmkms; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
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
      warn "$c 无法读取时间"
      TIME_OK=0
    fi
  fi
done
echo

echo "===== 5) Admin API ====="
POC_YES=0
POC_WEIGHT=-1

if need_jq; then
  # 先拿 http code，方便区分 404/拒绝/没监听
  ADMIN_CODE="$(curl -sS -o /tmp/admin_nodes.json -w "%{http_code}" --max-time 3 http://127.0.0.1:9200/admin/v1/nodes || echo 000)"
  if [[ "$ADMIN_CODE" != 2* ]]; then
    bad "9200/admin/v1/nodes 异常：http_code=$ADMIN_CODE"
    PORT_OK=0
  else
    ADMIN_JSON="$(cat /tmp/admin_nodes.json || true)"
    if [[ -z "$ADMIN_JSON" ]]; then
      bad "9200/admin/v1/nodes 返回空 body"
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
  fi
else
  warn "无 jq，跳过 Admin API 解析"
  PORT_OK=0
fi
echo

echo "===== 6) 推理入口可达性 ====="
check_http "5050 /health" "http://127.0.0.1:5050/health" || true
check_http "5050 /v1/models" "http://127.0.0.1:5050/v1/models" || true
if [[ -n "${PUBLIC_IP:-}" ]]; then
  check_http "PUBLIC :8000 /health" "http://${PUBLIC_IP}:8000/health" || true
else
  warn "未能确定 PUBLIC_IP，跳过外网 :8000 检查"
  PORT_OK=0
fi
echo

echo "===== 结论 ====="
if [[ "$TIME_OK" -eq 1 && "$CHAIN_OK" -eq 1 && "$PORT_OK" -eq 1 && "$CONS_OK" -eq 1 ]]; then
  echo "✔ 时间一致 + 链同步 + 端口正常 + 共识 key 核心对齐"
else
  echo "⚠️ 节点存在问题："
  [[ "$TIME_OK" -ne 1 ]] && echo "  - 时间检查未通过"
  [[ "$CHAIN_OK" -ne 1 ]] && echo "  - 链同步异常"
  [[ "$PORT_OK" -ne 1 ]] && echo "  - 端口/可达性异常"
  [[ "$CONS_OK" -ne 1 ]] && echo "  - 共识 key 核心不一致"
  [[ "$CALLBACK_OK" -ne 1 ]] && echo "  - api 回调地址未能确认"
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
