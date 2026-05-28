#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKDIR"

DATE=$(date +%Y-%m-%d)
LOGDIR="$WORKDIR/output"
LOGFILE="$LOGDIR/run-${DATE}.log"

mkdir -p "$LOGDIR" docs

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOGFILE"; }

# ── Step 1: Fetch & export scored signals ──
log "▶ Step 1: signal:export"
npm run signal:export >> "$LOGFILE" 2>&1
log "  done"

# ── Step 2: Claude clustering + HTML generation ──
log "▶ Step 2: claude clustering + HTML"
claude -p "读取 output/signals.json，按照 processors/cluster.mjs 和 processors/report.mjs 的逻辑做聚类分析，生成一份完整的 HTML 报告（参考 output/signal-2026-05-27.html 的样式），保存到 output/signal-${DATE}.html。HTML 必须是自包含的（内联 CSS），适合移动端阅读。最后输出一行 JSON 到 stdout：{ \"theme\": \"最值得关注的聚类主题\", \"count\": 信号总数, \"clusters\": 聚类数 }" \
  --output-format text \
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

# ── Step 4: Extract summary for stdout (hermes will send this) ──
REPORT_URL="https://tsy77.github.io/daily-report/signal-${DATE}.html"

# Try to extract the theme from the log
THEME=$(grep -oP '"theme"\s*:\s*"\K[^"]+' "$LOGFILE" 2>/dev/null | tail -1 || echo "daily signal report")

# This single line to stdout is what hermes sends to weixin
echo "📡 每日信号雷达 ${DATE} | 主题: ${THEME} | 详情: ${REPORT_URL}"
