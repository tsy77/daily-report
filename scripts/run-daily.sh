#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKDIR"

DATE=$(date +%Y-%m-%d)
LOGDIR="$WORKDIR/output"
LOGFILE="$LOGDIR/run-${DATE}.log"

mkdir -p "$LOGDIR" docs

# Resolve claude binary (nvm not loaded in non-interactive shells)
source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
CLAUDE=$(which claude 2>/dev/null || echo "/Users/tsy/.nvm/versions/node/v22.22.0/bin/claude")
if ! command -v "$CLAUDE" >/dev/null 2>&1; then
  echo "ERROR: claude not found" >&2; exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOGFILE"; }

# ── Step 1: Fetch & export scored signals ──
log "▶ Step 1: signal:export"
npm run signal:export >> "$LOGFILE" 2>&1
log "  done"

# ── Step 1.5: Trim & split into batches ──
log "▶ Step 1.5: split into batches"
node -e "
const s = JSON.parse(require('fs').readFileSync('output/signals.json','utf8'));
const top = s.slice(0, 150);
const N = 5;
const batchSize = Math.ceil(top.length / N);
for (let i = 0; i < N; i++) {
  require('fs').writeFileSync(
    'output/batch-' + i + '.json',
    JSON.stringify(top.slice(i * batchSize, (i + 1) * batchSize))
  );
}
console.log('Split ' + top.length + ' signals into ' + N + ' batches');
" >> "$LOGFILE" 2>&1
log "  done"

# ── Step 2a: 并行启动 5 个 claude -p 分析 batch ──
log "▶ Step 2a: parallel clustering (5 batches)"
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
  "$CLAUDE" -p "$PROMPT" --allowedTools "Read,Write,Bash" >> "$LOGDIR/cluster-${i}.log" 2>&1 &
  PIDS+=($!)
  log "  batch $i → PID $!"
done

# 等待所有分析完成，记录失败
FAIL=0
for i in "${!PIDS[@]}"; do
  if wait "${PIDS[$i]}"; then
    log "  batch $i ✓"
  else
    log "  batch $i ✗ (exit $?)"
    FAIL=$((FAIL + 1))
  fi
done

if [ $FAIL -eq 5 ]; then
  log "✗ 所有 batch 分析失败，终止"
  exit 1
fi
[ $FAIL -gt 0 ] && log "⚠ $FAIL 个 batch 失败，用剩余结果继续"

# ── Step 2b: 合并聚类 + 生成 HTML ──
log "▶ Step 2b: merge clusters + generate HTML"
"$CLAUDE" -p "你是信号分析合并器。完成以下任务：

1. 读取所有 output/cluster-*.json 文件（用 Read tool）
2. 合并去重聚类（相似主题合并，score 取最高），按 score 降序排列
3. 参考 output/signal-2026-05-27.html 的样式，生成自包含 HTML 报告（内联 CSS，移动端友好），用 Write tool 保存到 output/signal-${DATE}.html
4. 最后只输出一行 JSON：{\"theme\":\"最值得关注的聚类主题\",\"count\":150,\"clusters\":合并后聚类数}" \
  --allowedTools "Read,Write,Bash" \
  >> "$LOGFILE" 2>&1
log "  done"

# ── Step 3: Deploy to GitHub Pages ──
HTML_SRC="$WORKDIR/output/signal-${DATE}.html"
HTML_DST="$WORKDIR/docs/signal-${DATE}.html"

if [ -f "$HTML_SRC" ]; then
  cp "$HTML_SRC" "$HTML_DST"
  log "▶ Step 3: git push to GitHub Pages"
  git add "docs/signal-${DATE}.html"
  git diff --cached --quiet || git commit -m "signal report ${DATE}" >> "$LOGFILE" 2>&1
  git push >> "$LOGFILE" 2>&1
  log "  done"
else
  log "⚠ HTML report not found: $HTML_SRC"
fi

# ── Step 4: Summary for stdout (hermes → weixin) ──
REPORT_URL="https://tsy77.github.io/daily-report/signal-${DATE}.html"
THEME=$(grep -oP '"theme"\s*:\s*"\K[^"]+' "$LOGFILE" 2>/dev/null | tail -1 || echo "daily signal report")

echo "📡 每日信号雷达 ${DATE} | 主题: ${THEME} | 详情: ${REPORT_URL}"
