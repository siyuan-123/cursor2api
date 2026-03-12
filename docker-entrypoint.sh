#!/bin/sh
set -eu

PORT="${PORT:-3010}"
HEALTHCHECK_INTERVAL="${HEALTHCHECK_INTERVAL:-30}"
HEALTHCHECK_START_PERIOD="${HEALTHCHECK_START_PERIOD:-20}"
HEALTHCHECK_TIMEOUT_MS="${HEALTHCHECK_TIMEOUT_MS:-5000}"
APP_PID=""

healthcheck() {
  node -e "const port=process.env.PORT||3010; const timeoutMs=Number(process.env.HEALTHCHECK_TIMEOUT_MS||5000); fetch('http://127.0.0.1:'+port+'/health', { signal: AbortSignal.timeout(timeoutMs) }).then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1));"
}

forward_term() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
  fi
}

trap 'forward_term' TERM INT

node dist/index.js &
APP_PID=$!

if [ "$HEALTHCHECK_START_PERIOD" -gt 0 ] 2>/dev/null; then
  sleep "$HEALTHCHECK_START_PERIOD"
fi

while kill -0 "$APP_PID" 2>/dev/null; do
  if ! healthcheck; then
    echo "[Watchdog] Health check failed, stopping app for Docker restart..." >&2
    kill -TERM "$APP_PID" 2>/dev/null || true
    sleep 10
    kill -KILL "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" || true
    exit 1
  fi
  sleep "$HEALTHCHECK_INTERVAL"
done

wait "$APP_PID"
EXIT_CODE=$?
exit "$EXIT_CODE"
