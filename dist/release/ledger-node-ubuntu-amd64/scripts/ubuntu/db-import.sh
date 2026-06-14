#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <ledger-db-export.tar.gz|ledger-backup.zip>" >&2
  exit 1
fi

ARCHIVE="$1"
APP_DIR="${LEDGER_APP_DIR:-/opt/ledger-node}"
CONFIG_FILE="$APP_DIR/config.json"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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

if [ ! -f "$ARCHIVE" ]; then
  echo "archive not found: $ARCHIVE" >&2
  exit 1
fi

"$SCRIPT_DIR/stop.sh"

DB_PATH="$(abs_path "$(config_value database.path ./data/app.db)")"
PHOTOS_DIR="$(abs_path "$(config_value storage.photos_dir ./data/photos)")"
THUMBNAILS_DIR="$(abs_path "$(config_value storage.thumbnails_dir ./data/thumbnails)")"
SECRET_PATH="$(abs_path "$(config_value security.secret_path ./server-secret.key)")"

STAMP="$(date -u +%Y%m%d-%H%M%S)"
IMPORT_BACKUP_DIR="$APP_DIR/imports/before-import-$STAMP"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$IMPORT_BACKUP_DIR"
[ -d "$(dirname "$DB_PATH")" ] && cp -a "$(dirname "$DB_PATH")" "$IMPORT_BACKUP_DIR/data"
[ -f "$CONFIG_FILE" ] && cp -a "$CONFIG_FILE" "$IMPORT_BACKUP_DIR/config.json"
[ -f "$SECRET_PATH" ] && cp -a "$SECRET_PATH" "$IMPORT_BACKUP_DIR/server-secret.key"

case "$ARCHIVE" in
  *.zip)
    if ! command -v unzip >/dev/null 2>&1; then
      echo "unzip is required to import zip backups" >&2
      exit 1
    fi
    unzip -q "$ARCHIVE" -d "$TMP_DIR"
    ;;
  *)
    tar -C "$TMP_DIR" -xzf "$ARCHIVE"
    ;;
esac

if [ -f "$TMP_DIR/data/app.db" ]; then
  SRC_DB="$TMP_DIR/data/app.db"
  SRC_PHOTOS="$TMP_DIR/data/photos"
  SRC_THUMBNAILS="$TMP_DIR/data/thumbnails"
elif [ -f "$TMP_DIR/app.db" ]; then
  SRC_DB="$TMP_DIR/app.db"
  SRC_PHOTOS="$TMP_DIR/photos"
  SRC_THUMBNAILS="$TMP_DIR/thumbnails"
else
  echo "import archive does not contain app.db" >&2
  exit 1
fi

mkdir -p "$(dirname "$DB_PATH")" "$PHOTOS_DIR" "$THUMBNAILS_DIR" "$(dirname "$SECRET_PATH")"
rm -f "$DB_PATH" "$DB_PATH-wal" "$DB_PATH-shm"
rm -rf "$PHOTOS_DIR" "$THUMBNAILS_DIR"
mkdir -p "$PHOTOS_DIR" "$THUMBNAILS_DIR"

cp -a "$SRC_DB" "$DB_PATH"
[ -d "$SRC_PHOTOS" ] && cp -a "$SRC_PHOTOS/." "$PHOTOS_DIR/"
[ -d "$SRC_THUMBNAILS" ] && cp -a "$SRC_THUMBNAILS/." "$THUMBNAILS_DIR/"

if [ -f "$TMP_DIR/server-secret.key" ]; then
  cp -a "$TMP_DIR/server-secret.key" "$SECRET_PATH"
  chmod 0600 "$SECRET_PATH"
else
  echo "warning: server-secret.key not found in archive; paired devices may need to pair again" >&2
fi

if [ "${LEDGER_IMPORT_CONFIG:-0}" = "1" ] && [ -f "$TMP_DIR/config.json" ]; then
  cp -a "$TMP_DIR/config.json" "$CONFIG_FILE"
fi

if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$DB_PATH" "PRAGMA integrity_check;"
else
  echo "sqlite3 not found; skipped integrity_check"
fi

echo "Imported database package from: $ARCHIVE"
echo "Previous data snapshot: $IMPORT_BACKUP_DIR"
echo "Start with: $SCRIPT_DIR/start.sh"
