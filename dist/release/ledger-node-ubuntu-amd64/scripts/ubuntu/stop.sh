#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${LEDGER_APP_DIR:-/opt/ledger-node}"
PID_FILE="$APP_DIR/run/ledger-server.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "ledger-server is not running: pid file not found"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if [ -z "$PID" ] || ! kill -0 "$PID" >/dev/null 2>&1; then
  rm -f "$PID_FILE"
  echo "ledger-server is not running"
  exit 0
fi

kill "$PID"
for _ in $(seq 1 30); do
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    rm -f "$PID_FILE"
    echo "ledger-server stopped"
    exit 0
  fi
  sleep 1
done

echo "ledger-server did not stop within 30 seconds; pid $PID is still running" >&2
exit 1
