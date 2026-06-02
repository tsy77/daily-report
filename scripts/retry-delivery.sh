#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/Users/tsy/devspace/daily-report"
DATE="${1:?usage: retry-delivery.sh YYYY-MM-DD [target]}"
TARGET="${2:-${HERMES_SEND_TO:-weixin}}"
STATUS_FILE="$WORKDIR/output/status-${DATE}.json"
LOGFILE="$WORKDIR/output/delivery-${DATE}.log"
DELAYS="${HERMES_DELIVERY_RETRY_DELAYS:-600,1800,3600}"

mkdir -p "$WORKDIR/output"
cd "$WORKDIR"

log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOGFILE"
}

update_status() {
  local status="$1"
  local message="$2"
  local error="${3:-}"
  python3 - "$STATUS_FILE" "$DATE" "$status" "$message" "$error" "$LOGFILE" "$$" <<'PY'
import json, sys, datetime
path, date, status, message, error, logfile, pid = sys.argv[1:]
now = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    data = {'date': date, 'started_at': now}
data.update({
    'date': date,
    'status': status,
    'step': 'delivery_retry',
    'step_index': 5,
    'total_steps': 5,
    'message': message,
    'updated_at': now,
    'delivery_retry_pid': int(pid),
    'delivery_retry_log': logfile,
})
if error:
    data['delivery_error'] = error
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
}

SUMMARY=$(python3 - "$STATUS_FILE" <<'PY'
import json, sys
try:
    d=json.load(open(sys.argv[1], encoding='utf-8'))
    print(d.get('summary',''))
except Exception:
    print('')
PY
)

if [ -z "$SUMMARY" ]; then
  log "no summary found in $STATUS_FILE; exiting"
  update_status "completed_with_delivery_error" "delivery retry could not find summary" "missing summary"
  exit 1
fi

IFS=',' read -r -a DELAY_ARRAY <<< "$DELAYS"
attempt=0
for delay in "${DELAY_ARRAY[@]}"; do
  attempt=$((attempt + 1))
  delay="$(echo "$delay" | tr -d '[:space:]')"
  if [ -n "$delay" ] && [ "$delay" != "0" ]; then
    log "waiting ${delay}s before delivery retry $attempt"
    sleep "$delay"
  fi

  log "delivery retry $attempt to ${TARGET}"
  set +e
  output=$("$HOME/.local/bin/hermes" send --to "$TARGET" "$SUMMARY" 2>&1)
  code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    log "✓ delivery retry $attempt succeeded: $output"
    update_status "completed" "daily report delivered by delayed retry"
    exit 0
  fi
  log "⚠ delivery retry $attempt failed: $output"
  update_status "completed_with_delivery_error" "delivery retry $attempt failed" "$output"
done

log "all delayed delivery retries failed"
exit 1
