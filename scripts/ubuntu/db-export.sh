#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${LEDGER_APP_DIR:-/opt/ledger-node}"
CONFIG_FILE="$APP_DIR/config.json"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${LEDGER_EXPORT_DIR:-$APP_DIR/exports}"

config_value() {
  local key="$1"
  local default_value="$2"
  if command -v python3 >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
    python3 - "$CONFIG_FILE" "$key" "$default_value" <<'PY'
import json
import sys

path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    value = json.load(open(path, encoding="utf-8"))
    for part in key.split("."):
        value = value[part]
    print(value if isinstance(value, str) else default)
except Exception:
    print(default)
PY
  else
    printf '%s\n' "$default_value"
  fi
}

abs_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$APP_DIR/${1#./}" ;;
  esac
}

"$SCRIPT_DIR/stop.sh"

DB_PATH="$(abs_path "$(config_value database.path ./data/app.db)")"
PHOTOS_DIR="$(abs_path "$(config_value storage.photos_dir ./data/photos)")"
THUMBNAILS_DIR="$(abs_path "$(config_value storage.thumbnails_dir ./data/thumbnails)")"
SECRET_PATH="$(abs_path "$(config_value security.secret_path ./server-secret.key)")"

if [ ! -f "$DB_PATH" ]; then
  echo "database not found: $DB_PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
TMP_DIR="$(mktemp -d)"
OUT_FILE="$OUT_DIR/ledger-db-export-$STAMP.tar.gz"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/data/photos" "$TMP_DIR/data/thumbnails"
cp -a "$DB_PATH" "$TMP_DIR/data/app.db"
[ -d "$PHOTOS_DIR" ] && cp -a "$PHOTOS_DIR/." "$TMP_DIR/data/photos/"
[ -d "$THUMBNAILS_DIR" ] && cp -a "$THUMBNAILS_DIR/." "$TMP_DIR/data/thumbnails/"
[ -f "$CONFIG_FILE" ] && cp -a "$CONFIG_FILE" "$TMP_DIR/config.json"
[ -f "$SECRET_PATH" ] && cp -a "$SECRET_PATH" "$TMP_DIR/server-secret.key"

cat >"$TMP_DIR/manifest.json" <<JSON
{
  "format_version": 1,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "database_file": "data/app.db",
  "photos_dir": "data/photos",
  "thumbnails_dir": "data/thumbnails",
  "config_file": "config.json",
  "secret_file": "server-secret.key",
  "amount_unit": "cent",
  "currency": "CNY"
}
JSON

tar -C "$TMP_DIR" -czf "$OUT_FILE" .
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT_FILE" >"$OUT_FILE.sha256"
fi

echo "Exported database package: $OUT_FILE"
echo "The service is stopped. Start it with: $SCRIPT_DIR/start.sh"
