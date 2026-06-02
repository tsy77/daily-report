#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/Users/tsy/devspace/daily-report"
DATE="${DAILY_REPORT_DATE:-$(date +%Y-%m-%d)}"
REPORT_URL="https://tsy77.github.io/daily-report/signal-${DATE}.html"
WORKER="$HOME/.hermes/scripts/daily-report-worker.sh"
LOGFILE="$WORKDIR/output/hermes-${DATE}.log"
STATUS_FILE="$WORKDIR/output/status-${DATE}.json"
LOCKDIR="$WORKDIR/output/hermes-daily.lock"

mkdir -p "$WORKDIR/output"

summary_from_clusters() {
  node -e "
const fs = require('fs');
const dir = '$WORKDIR/output';
const files = fs.existsSync(dir)
  ? fs.readdirSync(dir).filter(f => f.startsWith('cluster-') && f.endsWith('.json'))
  : [];
let all = [];
for (const f of files) {
  try { all.push(...JSON.parse(fs.readFileSync(dir + '/' + f, 'utf8'))); } catch {}
}
all.sort((a, b) => (b.score || 0) - (a.score || 0));
console.log(all[0]?.theme || 'daily signal report');
" 2>/dev/null || echo "daily signal report"
}

# If today's report already exists, let Hermes cron deliver the cached summary.
if [ -f "$WORKDIR/docs/signal-${DATE}.html" ]; then
  THEME=$(summary_from_clusters)
  echo "📡 每日信号雷达 ${DATE} | 主题: ${THEME} | 详情: ${REPORT_URL}"
  exit 0
fi

# Avoid duplicate daily runs; empty stdout keeps Hermes cron silent.
if [ -d "$LOCKDIR" ] || pgrep -f "$WORKER" >/dev/null 2>&1; then
  exit 0
fi

if [ ! -x "$WORKER" ]; then
  echo "ERROR: worker not executable: $WORKER" >&2
  exit 1
fi

/usr/bin/nohup /bin/bash "$WORKER" "$DATE" >> "$LOGFILE" 2>&1 < /dev/null &
PID=$!

python3 - "$STATUS_FILE" "$DATE" "$LOGFILE" "$PID" <<'PY'
import json, sys, datetime
path, date, logfile, pid = sys.argv[1:]
now = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'
data = {
    'date': date,
    'status': 'running',
    'step': 'queued',
    'step_index': 0,
    'total_steps': 5,
    'message': 'background worker started by Hermes cron wrapper',
    'started_at': now,
    'updated_at': now,
    'pid': int(pid),
    'log': logfile,
}
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY

# Return quickly. Empty stdout means Hermes cron stays silent; the worker sends the final result.
exit 0
