#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${LEDGER_APP_DIR:-/opt/ledger-node}"
PID_FILE="$APP_DIR/run/ledger-server.pid"
LOG_FILE="$APP_DIR/logs/ledger-server.log"

mkdir -p "$APP_DIR/run" "$APP_DIR/logs" "$APP_DIR/tmp"

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if [ -n "$PID" ] && kill -0 "$PID" >/dev/null 2>&1; then
    echo "ledger-server is already running with pid $PID"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

if [ ! -x "$APP_DIR/ledger-server" ]; then
  echo "missing executable: $APP_DIR/ledger-server" >&2
  exit 1
fi

if [ ! -f "$APP_DIR/config.json" ]; then
  echo "missing config: $APP_DIR/config.json" >&2
  exit 1
fi

cd "$APP_DIR"
nohup ./ledger-server --config ./config.json >>"$LOG_FILE" 2>&1 &
PID="$!"
echo "$PID" >"$PID_FILE"
echo "ledger-server started with pid $PID"
echo "log: $LOG_FILE"
