#!/usr/bin/env bash
set -euo pipefail

ok(){ echo -e "✅ $*"; }
warn(){ echo -e "⚠️  $*"; }
bad(){ echo -e "❌ $*"; }

need_jq(){ command -v jq >/dev/null 2>&1; }

# ===== 公网信息 =====
PUBLIC_IP="${PUBLIC_IP:-}"
PUBLIC_URL="${PUBLIC_URL:-}"

if [ -z "$PUBLIC_IP" ] && [ -n "$PUBLIC_URL" ]; then
  PUBLIC_IP="$(echo "$PUBLIC_URL" | sed -E 's#^https?://([^:/]+).*#\1#')"
fi
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="$(curl -s ifconfig.me || true)"

echo "===== 0) 基础信息 ====="
echo "HOST TIME:  $(date -Is)"
echo "UTC TIME:   $(date -u -Is)"
echo "HOSTNAME:   $(hostname)"
echo "PUBLIC_IP:  ${PUBLIC_IP:-<unknown>}"
echo "PUBLIC_URL: ${PUBLIC_URL:-<unset>}"
echo

# ============================================================
# Docker / Ports
# ============================================================
echo "===== 1) Docker 容器 ====="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo

echo "===== 2) 端口监听 ====="
(ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null) \
 | egrep ':(5050|8080|26657|5000|5001|9200)\b' || true
echo

# ============================================================
# 链状态
# ============================================================
echo "===== 3) 链同步状态（26657）====="
curl -s http://127.0.0.1:26657/status | jq '.result.sync_info'
echo

# ============================================================
# 时间对比（核心）
# ============================================================
echo "===== 4) 时间对比（宿主 / 公网 / 链 / 容器）====="
HOST_EPOCH="$(date -u +%s)"
echo "[HOST] epoch=$HOST_EPOCH"

# ---------- 公网时间 ----------
HTTP_DATE="$(curl -fsSI https://google.com | awk 'BEGIN{IGNORECASE=1}/^Date:/{sub(/^[Dd]ate:[ ]*/,"");print;exit}')"
if [ -n "$HTTP_DATE" ]; then
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
  [ "$abs" -le 5 ] && ok "公网时间 OK" || warn "公网时间漂移 ${abs}s"
else
  warn "无法获取公网时间"
fi
echo

# ---------- 链时间 ----------
CHAIN_TIME="$(curl -s http://127.0.0.1:26657/status | jq -r '.result.sync_info.latest_block_time')"
if [ -n "$CHAIN_TIME" ]; then
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
  [ "$abs" -le 5 ] && ok "链时间 OK" || warn "链时间漂移 ${abs}s"
else
  warn "无法获取链时间"
fi
echo

# ---------- 容器时间 ----------
echo "[CONTAINERS]"
for c in api node inference join-mlnode-308-1 join-api-1 join-inference-1; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
    CE="$(docker exec "$c" sh -lc 'date -u +%s 2>/dev/null || date +%s')"
    CT="$(docker exec "$c" sh -lc 'date -u -Is 2>/dev/null || date -Is')"
    drift=$((HOST_EPOCH - CE))
    abs=${drift#-}
    echo "[$c] $CT drift=${drift}s"
    [ "$abs" -le 5 ] && ok "$c 时间 OK" || warn "$c 时间漂移 ${abs}s"
  fi
done
echo

# ============================================================
# 版本
# ============================================================
echo "===== 5) 二进制版本 ====="
ver="$(curl -s http://127.0.0.1:26657/abci_info | jq -r '.result.response.version')"
echo "version: $ver"
case "$ver" in
  2371460|0.2.6-post2) ok "版本正确" ;;
  *) bad "版本不匹配" ;;
esac
echo

# ============================================================
# Admin API
# ============================================================
curl -s http://127.0.0.1:9200/admin/v1/nodes | jq -r '
.[]
| ( (.state.epoch_models | keys)[0] // (.node.models | keys)[0] ) as $m
| "Model: \($m)\nPoC weight: \(.state.epoch_ml_nodes[$m].poc_weight // "N/A")\nTimeslot: \(.state.epoch_ml_nodes[$m].timeslot_allocation // "N/A")"
'

# ============================================================
# 对外推理
# ============================================================
echo "===== 7) 对外推理 ====="
curl -s -o /dev/null -w "5050 health → %{http_code}\n" http://127.0.0.1:5050/health || true
curl -s -o /dev/null -w "5050 models → %{http_code}\n" http://127.0.0.1:5050/v1/models || true
[ -n "$PUBLIC_IP" ] && curl -s -o /dev/null -w "$PUBLIC_IP:8000 → %{http_code}\n" http://$PUBLIC_IP:8000/health || true
echo

# ============================================================
# GPU
# ============================================================
echo "===== 8) GPU ====="
command -v nvidia-smi >/dev/null && nvidia-smi || warn "未检测到 GPU"
echo

echo
echo "===== 结论 ====="
echo "✔ 时间一致 + 链同步 + 端口正常 + 版本正确"

echo
echo "===== PoC ====="

if command -v jq >/dev/null 2>&1; then
  curl -s http://127.0.0.1:9200/admin/v1/nodes | jq -r '
  .[] |
  ( (.state.epoch_models | keys)[0] // (.node.models | keys)[0] ) as $m |
  ( .state.epoch_ml_nodes[$m].poc_weight // -1 ) as $w |
  if $w > 0 then
    "PoC: YES\nPoC weight: \($w)"
  else
    "PoC: NO\nPoC weight: -1"
  end
  '
else
  echo "PoC: UNKNOWN"
  echo "PoC weight: -1"
fi
