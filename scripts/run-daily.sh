#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKDIR"

DATE="${DAILY_REPORT_DATE:-$(date +%Y-%m-%d)}"
LOGDIR="$WORKDIR/output"
LOGFILE="$LOGDIR/run-${DATE}.log"
STATUS_FILE="$LOGDIR/status-${DATE}.json"
mkdir -p "$LOGDIR" docs

PIPELINE_STATUS="running"
CURRENT_STEP="init"
CURRENT_STEP_INDEX="0"
PUBLISH_ERROR=""

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

write_status() {
  local status="$1"
  local step="$2"
  local index="$3"
  local message="$4"
  local error="${5:-}"
  local summary="${6:-}"
  local report_url="${7:-}"
  local now
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  python3 - "$STATUS_FILE" <<'PY' "$status" "$step" "$index" "$message" "$error" "$summary" "$report_url" "$now" "$DATE" "$LOGFILE" "$$"
import json, os, sys
path, status, step, index, message, error, summary, report_url, now, date, logfile, pid = sys.argv[1:]
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    data = {"date": date, "started_at": now}
data.update({
    "date": date,
    "status": status,
    "step": step,
    "step_index": int(index),
    "total_steps": 5,
    "message": message,
    "updated_at": now,
    "pid": int(pid),
    "log": logfile,
})
if error:
    data["error"] = error
else:
    data.pop("error", None)
if summary:
    data["summary"] = summary
if report_url:
    data["url"] = report_url
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
}

log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOGFILE"
}

fail() {
  local msg="$1"
  PIPELINE_STATUS="failed"
  log "✗ $msg"
  write_status "failed" "$CURRENT_STEP" "$CURRENT_STEP_INDEX" "$msg" "$msg"
  echo "ERROR: $msg" >&2
  exit 1
}

on_interrupt() {
  local msg="pipeline interrupted while running step ${CURRENT_STEP}"
  PIPELINE_STATUS="failed"
  log "✗ $msg"
  write_status "failed" "$CURRENT_STEP" "$CURRENT_STEP_INDEX" "$msg" "interrupted"
  exit 130
}

trap on_interrupt INT TERM HUP

run_with_timeout() {
  local seconds="$1"
  local label="$2"
  shift 2
  log "  timeout=${seconds}s command=$*"
  set +e
  python3 "$WORKDIR/scripts/with-timeout.py" "$seconds" "$@" >> "$LOGFILE" 2>&1
  local code=$?
  set -e
  if [ "$code" -ne 0 ]; then
    fail "$label failed or timed out after ${seconds}s (exit ${code})"
  fi
}

# Resolve claude binary (nvm not loaded in non-interactive shells)
source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
CLAUDE=$(which claude 2>/dev/null || echo "/Users/tsy/.nvm/versions/node/v22.22.0/bin/claude")
if ! command -v "$CLAUDE" >/dev/null 2>&1; then
  fail "claude not found"
fi

# Start a fresh dated log for each run, but keep status visible.
: > "$LOGFILE"
write_status "running" "init" "0" "daily report pipeline started"

# ── Step 1: Fetch & export scored signals ──
CURRENT_STEP="signal_export"
CURRENT_STEP_INDEX="1"
write_status "running" "$CURRENT_STEP" "1" "fetching and exporting scored ecommerce signals"
log "▶ Step 1: signal:export"
if [ "${DAILY_REPORT_RESUME:-0}" = "1" ] && [ -s "$LOGDIR/signals.json" ]; then
  log "  resume enabled: using existing output/signals.json"
else
  run_with_timeout "${SIGNAL_EXPORT_TIMEOUT:-240}" "signal:export" npm run signal:export
fi
log "  done"

# ── Step 1.5: Trim & split into batches ──
CURRENT_STEP="split_batches"
CURRENT_STEP_INDEX="2"
write_status "running" "$CURRENT_STEP" "2" "splitting top signals into Claude analysis batches"
log "▶ Step 1.5: split into batches"
node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('output/signals.json','utf8'));
const top = s.slice(0, 150);
const N = 5;
const batchSize = Math.max(1, Math.ceil(top.length / N));
for (let i = 0; i < N; i++) {
  fs.writeFileSync(
    'output/batch-' + i + '.json',
    JSON.stringify(top.slice(i * batchSize, (i + 1) * batchSize), null, 2)
  );
}
console.log('Split ' + top.length + ' signals into ' + N + ' batches');
" >> "$LOGFILE" 2>&1
log "  done"

# ── Step 2a: 并行启动 5 个 claude -p 分析 batch ──
CURRENT_STEP="cluster_batches"
CURRENT_STEP_INDEX="3"
write_status "running" "$CURRENT_STEP" "3" "running 5 parallel Claude clustering jobs"
log "▶ Step 2a: parallel clustering (5 batches)"
rm -f "$LOGDIR"/cluster-*.json "$LOGDIR"/cluster-*.log
PIDS=()
ANALYSIS_PROMPT='你是电商信号分析师。读取 output/batch-BATCH.json，分析这些电商信号，识别用户痛点并聚类。
输出 JSON 数组到 output/cluster-BATCH.json，格式：
[{"theme":"主题","why_now":"为什么是现在","possible_product":"可能的产品","today_action":"验证动作","score":8,"signal_titles":["标题1","标题2"]}]

规则：
- 每个 batch 产出 3-6 个聚类
- score 1-10，10 最值得关注
- 只输出 JSON，不要其他内容
- 用 Write tool 写文件'

for i in 0 1 2 3 4; do
  PROMPT=$(echo "$ANALYSIS_PROMPT" | sed "s/BATCH/$i/g")
  python3 "$WORKDIR/scripts/with-timeout.py" "${CLUSTER_BATCH_TIMEOUT:-900}" "$CLAUDE" -p "$PROMPT" --allowedTools "Read,Write,Bash" >> "$LOGDIR/cluster-${i}.log" 2>&1 &
  PIDS+=($!)
  log "  batch $i → PID $!"
done

FAIL=0
for i in "${!PIDS[@]}"; do
  if wait "${PIDS[$i]}"; then
    log "  batch $i ✓"
  else
    log "  batch $i ✗ (exit $?)"
    FAIL=$((FAIL + 1))
  fi
  write_status "running" "$CURRENT_STEP" "3" "completed $((i + 1))/5 cluster batches; failures=${FAIL}"
done

if [ "$FAIL" -eq 5 ]; then
  fail "all Claude cluster batches failed"
fi
[ "$FAIL" -gt 0 ] && log "⚠ $FAIL 个 batch 失败，用剩余结果继续"

# ── Step 2b: 合并聚类 + 生成 HTML ──
CURRENT_STEP="merge_generate_html"
CURRENT_STEP_INDEX="4"
write_status "running" "$CURRENT_STEP" "4" "merging clusters and generating self-contained HTML"
log "▶ Step 2b: merge clusters + generate HTML"
run_with_timeout "${MERGE_TIMEOUT:-120}" "merge clusters + generate HTML" \
  node "$WORKDIR/scripts/merge-generate-html.mjs" "$DATE"
log "  done"

# ── Step 3: Deploy to GitHub Pages ──
CURRENT_STEP="deploy"
CURRENT_STEP_INDEX="5"
write_status "running" "$CURRENT_STEP" "5" "copying HTML report and pushing GitHub Pages"
HTML_SRC="$WORKDIR/output/signal-${DATE}.html"
HTML_DST="$WORKDIR/docs/signal-${DATE}.html"

if [ -f "$HTML_SRC" ]; then
  cp "$HTML_SRC" "$HTML_DST"
  if [ "${DAILY_REPORT_SKIP_DEPLOY:-0}" = "1" ]; then
    log "▶ Step 3: deploy skipped by DAILY_REPORT_SKIP_DEPLOY=1"
  else
    log "▶ Step 3: git push to GitHub Pages"
    git add "docs/signal-${DATE}.html"
    git diff --cached --quiet || git commit -m "signal report ${DATE}" >> "$LOGFILE" 2>&1
    run_with_timeout "${GIT_PUSH_TIMEOUT:-180}" "git push" git push
    log "  git push done"
    if [ "${VERIFY_PAGES_AFTER_DEPLOY:-1}" = "1" ]; then
      REPORT_URL="https://tsy77.github.io/daily-report/signal-${DATE}.html"
      log "  verifying GitHub Pages URL: ${REPORT_URL}"
      set +e
      PAGES_VERIFY_OUTPUT=$(PAGES_VERIFY_TIMEOUT="${PAGES_VERIFY_TIMEOUT:-180}" PAGES_VERIFY_INTERVAL="${PAGES_VERIFY_INTERVAL:-10}" \
        /bin/bash "$WORKDIR/scripts/verify-pages.sh" "$DATE" "$REPORT_URL" 2>&1)
      PAGES_VERIFY_CODE=$?
      set -e
      if [ "$PAGES_VERIFY_CODE" -eq 0 ]; then
        log "  $PAGES_VERIFY_OUTPUT"
      else
        PUBLISH_ERROR="$PAGES_VERIFY_OUTPUT"
        log "⚠ GitHub Pages verification failed: $PUBLISH_ERROR"
      fi
    fi
  fi
else
  fail "HTML report not found: $HTML_SRC"
fi

# ── Step 4: Summary for stdout / direct send ──
CURRENT_STEP="send"
CURRENT_STEP_INDEX="5"
REPORT_URL="https://tsy77.github.io/daily-report/signal-${DATE}.html"
THEME=$(node -e "
const fs = require('fs');
const files = fs.readdirSync('output').filter(f => f.startsWith('cluster-') && f.endsWith('.json'));
let all = [];
for (const f of files) {
  try { all.push(...JSON.parse(fs.readFileSync('output/' + f, 'utf8'))); } catch {}
}
all.sort((a, b) => (b.score || 0) - (a.score || 0));
console.log(all[0]?.theme || 'daily signal report');
" 2>/dev/null || echo "daily signal report")

SUMMARY="📡 每日信号雷达 ${DATE} | 主题: ${THEME} | 详情: ${REPORT_URL}"
if [ -n "$PUBLISH_ERROR" ]; then
  SUMMARY="📡 每日信号雷达 ${DATE} | 主题: ${THEME} | 报告已生成，但 GitHub Pages 发布失败，线上链接暂不可用。错误: ${PUBLISH_ERROR}"
fi
echo "$SUMMARY"
if [ -n "$PUBLISH_ERROR" ]; then
  write_status "completed_with_publication_error" "publish" "5" "report generated but GitHub Pages verification failed" "$PUBLISH_ERROR" "$SUMMARY" "$REPORT_URL"
else
  write_status "completed" "completed" "5" "daily report completed" "" "$SUMMARY" "$REPORT_URL"
fi
PIPELINE_STATUS="completed"

send_via_hermes() {
  local target="$1"
  local message="$2"
  local attempts="${HERMES_SEND_ATTEMPTS:-3}"
  local delay="${HERMES_SEND_RETRY_DELAY:-60}"
  local output

  for attempt in $(seq 1 "$attempts"); do
    if output=$("$HOME/.local/bin/hermes" send --to "$target" "$message" 2>&1); then
      log "✓ Hermes send attempt $attempt succeeded: $output"
      return 0
    fi

    LAST_SEND_ERROR="$output"
    log "⚠ Hermes send attempt $attempt failed: $output"
    if [ "$attempt" -lt "$attempts" ]; then
      log "  retrying Hermes send in ${delay}s"
      sleep "$delay"
    fi
  done

  return 1
}

enqueue_delivery_retry() {
  local target="$1"
  if [ "${HERMES_ENABLE_DELAYED_RETRY:-1}" != "1" ]; then
    log "delayed delivery retry disabled"
    return 0
  fi
  if [ ! -x "$WORKDIR/scripts/retry-delivery.sh" ]; then
    log "delayed delivery retry script missing or not executable"
    return 0
  fi
  /usr/bin/nohup /bin/bash "$WORKDIR/scripts/retry-delivery.sh" "$DATE" "$target" >> "$LOGDIR/delivery-${DATE}.log" 2>&1 < /dev/null &
  log "queued delayed delivery retry PID $! target=${target} delays=${HERMES_DELIVERY_RETRY_DELAYS:-600,1800,3600}"
}

if [ -n "${HERMES_SEND_TO:-}" ] && [ "${DAILY_REPORT_SKIP_SEND:-0}" != "1" ]; then
  CURRENT_STEP="send"
  LAST_SEND_ERROR=""
  write_status "running" "$CURRENT_STEP" "5" "sending summary to ${HERMES_SEND_TO}" "" "$SUMMARY" "$REPORT_URL"
  if send_via_hermes "$HERMES_SEND_TO" "$SUMMARY"; then
    if [ -n "$PUBLISH_ERROR" ]; then
      write_status "completed_with_publication_error" "publish" "5" "daily report sent but GitHub Pages verification failed" "$PUBLISH_ERROR" "$SUMMARY" "$REPORT_URL"
    else
      write_status "completed" "completed" "5" "daily report sent" "" "$SUMMARY" "$REPORT_URL"
    fi
  else
    log "✗ Hermes send failed after retries; report generation remains completed"
    if [ -n "$PUBLISH_ERROR" ]; then
      write_status "completed_with_publication_and_delivery_error" "send" "5" "report generated but publish and Hermes send failed; delayed retry queued" "publish: ${PUBLISH_ERROR}; delivery: ${LAST_SEND_ERROR:-Hermes send failed after retries}" "$SUMMARY" "$REPORT_URL"
    else
      write_status "completed_with_delivery_error" "send" "5" "report generated but Hermes send failed; delayed retry queued" "${LAST_SEND_ERROR:-Hermes send failed after retries}" "$SUMMARY" "$REPORT_URL"
    fi
    enqueue_delivery_retry "$HERMES_SEND_TO"
  fi
fi
