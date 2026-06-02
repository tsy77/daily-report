#!/usr/bin/env bash
set -euo pipefail

DATE="${1:?usage: verify-pages.sh YYYY-MM-DD URL}"
URL="${2:?usage: verify-pages.sh YYYY-MM-DD URL}"
MAX_WAIT="${PAGES_VERIFY_TIMEOUT:-180}"
INTERVAL="${PAGES_VERIFY_INTERVAL:-10}"
START=$(date +%s)

while true; do
  code=$(curl -sS -L -o /dev/null -w '%{http_code}' "$URL" || true)
  if [ "$code" = "200" ]; then
    echo "GitHub Pages verified: $URL"
    exit 0
  fi

  # If the deploy workflow already failed, stop waiting immediately.
  if command -v gh >/dev/null 2>&1; then
    conclusion=$(gh run list --workflow "Deploy to GitHub Pages" --branch main --limit 1 --json conclusion,headSha,status \
      --jq '.[0] | select(.status=="completed") | .conclusion' 2>/dev/null || true)
    if [ "$conclusion" = "failure" ] || [ "$conclusion" = "cancelled" ]; then
      echo "GitHub Pages deploy workflow ${conclusion}; URL returned HTTP ${code}: ${URL}" >&2
      exit 1
    fi
  fi

  now=$(date +%s)
  if [ $((now - START)) -ge "$MAX_WAIT" ]; then
    echo "GitHub Pages verification timed out after ${MAX_WAIT}s; last HTTP ${code}: ${URL}" >&2
    exit 1
  fi
  sleep "$INTERVAL"
done
