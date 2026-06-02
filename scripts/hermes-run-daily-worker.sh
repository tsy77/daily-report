#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/Users/tsy/devspace/daily-report"
DATE="${1:-$(date +%Y-%m-%d)}"
LOCKDIR="$WORKDIR/output/hermes-daily.lock"
STATUS_FILE="$WORKDIR/output/status-${DATE}.json"
LOGFILE="$WORKDIR/output/hermes-${DATE}.log"

mkdir -p "$WORKDIR/output"

write_worker_status() {
  local status="$1"
  local step="$2"
  local message="$3"
  local error="${4:-}"
  python3 - "$STATUS_FILE" "$DATE" "$status" "$step" "$message" "$error" "$LOGFILE" "$$" <<'PY'
import json, sys, datetime
path, date, status, step, message, error, logfile, pid = sys.argv[1:]
now = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    data = {'date': date, 'started_at': now}
data.update({
    'date': date,
    'status': status,
    'step': step,
    'message': message,
    'updated_at': now,
    'pid': int(pid),
    'log': logfile,
})
if error:
    data['error'] = error
else:
    data.pop('error', None)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "[$(date '+%H:%M:%S')] another daily report run is active; exiting"
  write_worker_status "running" "locked" "another daily report run is active"
  exit 0
fi

cleanup() {
  rmdir "$LOCKDIR" 2>/dev/null || true
}
trap cleanup EXIT

cd "$WORKDIR"

export DAILY_REPORT_DATE="$DATE"
export HERMES_SEND_TO="${HERMES_SEND_TO:-weixin}"
export HERMES_SEND_ATTEMPTS="${HERMES_SEND_ATTEMPTS:-3}"
export HERMES_SEND_RETRY_DELAY="${HERMES_SEND_RETRY_DELAY:-60}"

write_worker_status "running" "worker_started" "Hermes daily report worker started"
echo "[$(date '+%H:%M:%S')] Hermes worker started for ${DATE}"
if /bin/bash "$WORKDIR/scripts/run-daily.sh"; then
  write_worker_status "completed" "completed" "Hermes daily report worker finished"
  echo "[$(date '+%H:%M:%S')] Hermes worker finished for ${DATE}"
else
  code=$?
  set +e
  python3 - "$STATUS_FILE" "$code" <<'PY'
import json, sys, datetime
path, code = sys.argv[1:]
now = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    data = {}
if data.get('status') == 'failed':
    data['worker_exit_code'] = int(code)
    data['worker_message'] = 'Hermes daily report worker failed'
    data['updated_at'] = now
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
else:
    raise SystemExit(1)
PY
  preserve_status=$?
  set -e
  if [ "$preserve_status" -ne 0 ]; then
    write_worker_status "failed" "worker_failed" "Hermes daily report worker failed" "exit ${code}"
  fi
  echo "[$(date '+%H:%M:%S')] Hermes worker failed for ${DATE}: exit ${code}"
  exit "$code"
fi
