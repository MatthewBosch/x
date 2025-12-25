#!/usr/bin/env bash
set -euo pipefail

ok(){ echo -e "✅ $*"; }
warn(){ echo -e "⚠️  $*"; }
bad(){ echo -e "❌ $*"; }

need_jq(){ command -v jq >/dev/null 2>&1; }

# ========= 结果汇总变量（结论必须基于它们） =========
TIME_OK=1
CHAIN_OK=1
PORT_OK=1
VERSION_OK=1

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

echo "===== 1) Docker 容器 ====="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | sed -n '1,200p'
echo

echo "===== 2) 端口监听（宿主机） ====="
(ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null) \
 | egrep ':(5050|8080|26657|5000|5001|9200|8000)\b' || true
echo

# ============================================================
# 链状态（26657）
# ============================================================
echo "===== 3) 链同步状态（26657）====="
if ! need_jq; then
  warn "未安装 jq：sudo apt-get update && sudo apt-get install -y jq"
  CHAIN_OK=0
else
  # status 是否可访问
  if ! check_http "26657 /status" "http://127.0.0.1:26657/status"; then
    CHAIN_OK=0
  fi

  SYNC_JSON="$(curl -sS http://127.0.0.1:26657/status | jq '.result.sync_info' 2>/dev/null || true)"
  if [ -z "$SYNC_JSON" ]; then
    bad "无法解析 26657/status 的 sync_info"
    CHAIN_OK=0
  else
    echo "$SYNC_JSON"
    catching="$(echo "$SYNC_JSON" | jq -r '.catching_up')"
    if [ "$catching" = "false" ]; then
      ok "catching_up=false（已同步）"
    else
      bad "catching_up=$catching（未同步/追块中）"
      CHAIN_OK=0
    fi
  fi
fi
echo

# ============================================================
# 时间对比（宿主 / 公网 / 链 / 容器）
# ============================================================
echo "===== 4) 时间对比（宿主 / 公网 / 链 / 容器）====="
HOST_EPOCH="$(date -u +%s)"
echo "[HOST] epoch=$HOST_EPOCH"

# --- 公网时间（HTTP Date） ---
HTTP_DATE="$(curl -fsSI --max-time 5 https://google.com \
  | awk 'BEGIN{IGNORECASE=1}/^Date:/{sub(/^[Dd]ate:[ ]*/,"");print;exit}' || true)"

if [ -n "$HTTP_DATE" ] && command -v python3 >/dev/null 2>&1; then
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
  if [ "$abs" -le 5 ]; then
    ok "公网时间 OK"
  elif [ "$abs" -le 30 ]; then
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

# --- 链时间（latest_block_time） ---
if need_jq && command -v python3 >/dev/null 2>&1; then
  CHAIN_TIME="$(curl -sS http://127.0.0.1:26657/status | jq -r '.result.sync_info.latest_block_time // empty' 2>/dev/null || true)"
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
    # 说明：这反映“最新区块时间距现在多久”，不等于系统时间错误
    if [ "$abs" -le 30 ]; then
      ok "链最新块时间差 ${abs}s（正常范围内）"
    elif [ "$abs" -le 120 ]; then
      warn "链最新块时间差 ${abs}s（可能网络/出块间隔/轻微延迟）"
      # 不把 TIME_OK 置 0，避免误报；真正同步用 catching_up 判定
    else
      warn "链最新块时间差 ${abs}s（若高度不增长/ catching_up=true 才算异常）"
    fi
  else
    warn "无法获取链 latest_block_time"
  fi
else
  warn "缺 jq 或 python3，跳过链时间对比"
fi
echo

# --- 容器时间 vs 宿主机 ---
echo "[CONTAINERS]"
for c in api node inference join-mlnode-308-1 join-api-1 join-inference-1; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
    CE="$(docker exec "$c" sh -lc 'date -u +%s 2>/dev/null || date +%s 2>/dev/null' 2>/dev/null || true)"
    CT="$(docker exec "$c" sh -lc 'date -u -Is 2>/dev/null || date -Is 2>/dev/null' 2>/dev/null || true)"
    if [ -n "$CE" ]; then
      drift=$((HOST_EPOCH - CE))
      abs=${drift#-}
      echo "[$c] ${CT:-<no-date>} drift=${drift}s"
      if [ "$abs" -le 5 ]; then
        ok "$c 时间 OK"
      elif [ "$abs" -le 30 ]; then
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
# 版本检查
# ============================================================
echo "===== 5) 二进制版本 ====="
if need_jq; then
  ver="$(curl -sS http://127.0.0.1:26657/abci_info | jq -r '.result.response.version // empty' 2>/dev/null || true)"
  echo "version: ${ver:-<empty>}"
  case "$ver" in
    2371460|0.2.6-post2) ok "版本正确" ;;
    *) bad "版本不匹配（需要 2371460 或 0.2.6-post2）"; VERSION_OK=0 ;;
  esac
else
  warn "无 jq，跳过版本判定"
  VERSION_OK=0
fi
echo

# ============================================================
# Admin API（输出模型、权重等；并生成 PoC 汇总）
# ============================================================
echo "===== 6) Admin API ====="
POC_YES=0
POC_WEIGHT=-1

if need_jq; then
  ADMIN_JSON="$(curl -sS http://127.0.0.1:9200/admin/v1/nodes 2>/dev/null || true)"
  if [ -z "$ADMIN_JSON" ]; then
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

    # 计算 PoC（按你定义：无 weight => NO, weight=-1）
    POC_WEIGHT="$(echo "$ADMIN_JSON" | jq -r '
      .[0] as $x
      | ( ($x.state.epoch_models|keys)[0] // ($x.node.models|keys)[0] ) as $m
      | ($x.state.epoch_ml_nodes[$m].poc_weight // -1)
    ' 2>/dev/null || echo -1)"

    if [ "${POC_WEIGHT:- -1}" -gt 0 ] 2>/dev/null; then
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
# 推理入口 / 可达性（5050 / 8000）
# ============================================================
echo "===== 7) 推理入口可达性 ====="
check_http "5050 /health" "http://127.0.0.1:5050/health" || true
check_http "5050 /v1/models" "http://127.0.0.1:5050/v1/models" || true

if [ -n "${PUBLIC_IP:-}" ]; then
  check_http "PUBLIC :8000 /health" "http://${PUBLIC_IP}:8000/health" || true
else
  warn "未能确定 PUBLIC_IP，跳过外网 :8000 检查"
  PORT_OK=0
fi
echo

# ============================================================
# GPU
# ============================================================
echo "===== 8) GPU ====="
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,utilization.gpu,temperature.gpu --format=csv,noheader || true
else
  warn "未检测到 nvidia-smi"
fi
echo

# ============================================================
# 动态结论（必须基于前面的判断变量）
# ============================================================
echo "===== 结论 ====="
if [ "$TIME_OK" -eq 1 ] && [ "$CHAIN_OK" -eq 1 ] && [ "$PORT_OK" -eq 1 ] && [ "$VERSION_OK" -eq 1 ]; then
  echo "✔ 时间一致 + 链同步 + 端口正常 + 版本正确"
else
  echo "⚠️ 节点存在问题："
  [ "$TIME_OK" -ne 1 ] && echo "  - 时间检查未通过（宿主/公网/容器漂移）"
  [ "$CHAIN_OK" -ne 1 ] && echo "  - 链同步异常（catching_up!=false 或 26657 不通）"
  [ "$PORT_OK" -ne 1 ] && echo "  - 端口/可达性异常（5050/8000/9200/容器接口）"
  [ "$VERSION_OK" -ne 1 ] && echo "  - 二进制版本不符合要求"
fi
echo

echo "===== PoC ====="
if [ "$POC_YES" -eq 1 ]; then
  echo "PoC: YES"
  echo "PoC weight: ${POC_WEIGHT}"
else
  echo "PoC: NO"
  echo "PoC weight: -1"
fi
