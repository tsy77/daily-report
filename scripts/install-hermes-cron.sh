#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_HOME="$HOME/.hermes"
HERMES_SCRIPTS="$HERMES_HOME/scripts"
JOB_NAME="daily-signal-radar"
SCHEDULE="0 9 * * *"
DELIVER="weixin"

mkdir -p "$HERMES_SCRIPTS"
cp "$WORKDIR/scripts/hermes-run-daily.sh" "$HERMES_SCRIPTS/run-daily.sh"
cp "$WORKDIR/scripts/hermes-run-daily-worker.sh" "$HERMES_SCRIPTS/daily-report-worker.sh"
cp "$WORKDIR/scripts/with-timeout.py" "$HERMES_SCRIPTS/with-timeout.py"
chmod +x "$HERMES_SCRIPTS/run-daily.sh" "$HERMES_SCRIPTS/daily-report-worker.sh" "$HERMES_SCRIPTS/with-timeout.py"

JOB_ID=$(node -e "
const fs = require('fs');
const path = process.env.HOME + '/.hermes/cron/jobs.json';
if (!fs.existsSync(path)) process.exit(0);
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
const job = (data.jobs || []).find(j => j.name === '$JOB_NAME');
if (job) process.stdout.write(job.id);
")

if [ -n "$JOB_ID" ]; then
  hermes cron edit "$JOB_ID" \
    --schedule "$SCHEDULE" \
    --script "$HERMES_SCRIPTS/run-daily.sh" \
    --no-agent \
    --deliver "$DELIVER" \
    --workdir "$WORKDIR"
else
  hermes cron create "$SCHEDULE" \
    --name "$JOB_NAME" \
    --script "$HERMES_SCRIPTS/run-daily.sh" \
    --no-agent \
    --deliver "$DELIVER" \
    --workdir "$WORKDIR"
fi

echo "Installed Hermes cron job: $JOB_NAME"
echo "Schedule: every day at 09:00 local time"
echo "Delivery: $DELIVER"
echo "Check: hermes cron list"
