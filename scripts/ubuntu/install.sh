#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="${LEDGER_APP_DIR:-/opt/ledger-node}"
RUN_USER="${LEDGER_RUN_USER:-${SUDO_USER:-$(id -un)}}"
LISTEN_ADDR="${LEDGER_LISTEN_ADDR:-0.0.0.0:8080}"
PUBLIC_BASE_URL="${LEDGER_PUBLIC_BASE_URL:-http://127.0.0.1:8080}"
REQUIRE_HTTPS="${LEDGER_REQUIRE_HTTPS:-false}"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required when installing outside a writable user directory" >&2
    exit 1
  fi
  SUDO=(sudo)
fi

if [ -x "$PACKAGE_ROOT/ledger-server" ]; then
  SERVER_SRC="$PACKAGE_ROOT/ledger-server"
elif [ -x "$PACKAGE_ROOT/dist/release/ubuntu-amd64/ledger-server" ]; then
  SERVER_SRC="$PACKAGE_ROOT/dist/release/ubuntu-amd64/ledger-server"
else
  echo "ledger-server linux binary not found in package root or dist/release/ubuntu-amd64" >&2
  exit 1
fi

if [ -d "$PACKAGE_ROOT/web" ]; then
  WEB_SRC="$PACKAGE_ROOT/web"
elif [ -d "$PACKAGE_ROOT/dist/release/web" ]; then
  WEB_SRC="$PACKAGE_ROOT/dist/release/web"
elif [ -d "$PACKAGE_ROOT/client/build/web" ]; then
  WEB_SRC="$PACKAGE_ROOT/client/build/web"
else
  echo "Flutter Web release directory not found in package root, dist/release/web or client/build/web" >&2
  exit 1
fi

"${SUDO[@]}" mkdir -p \
  "$APP_DIR" \
  "$APP_DIR/data/photos" \
  "$APP_DIR/data/thumbnails" \
  "$APP_DIR/backups" \
  "$APP_DIR/exports" \
  "$APP_DIR/imports" \
  "$APP_DIR/logs" \
  "$APP_DIR/run" \
  "$APP_DIR/tmp" \
  "$APP_DIR/scripts" \
  "$APP_DIR/releases"

"${SUDO[@]}" install -m 0755 "$SERVER_SRC" "$APP_DIR/ledger-server"
"${SUDO[@]}" rm -rf "$APP_DIR/web"
"${SUDO[@]}" cp -a "$WEB_SRC" "$APP_DIR/web"
"${SUDO[@]}" cp -a "$SCRIPT_DIR/." "$APP_DIR/scripts/"
"${SUDO[@]}" chmod +x "$APP_DIR/scripts/"*.sh

if [ -f "$PACKAGE_ROOT/app-release.apk" ]; then
  "${SUDO[@]}" install -m 0644 "$PACKAGE_ROOT/app-release.apk" "$APP_DIR/releases/app-release.apk"
elif [ -f "$PACKAGE_ROOT/client/build/app/outputs/flutter-apk/app-release.apk" ]; then
  "${SUDO[@]}" install -m 0644 "$PACKAGE_ROOT/client/build/app/outputs/flutter-apk/app-release.apk" "$APP_DIR/releases/app-release.apk"
fi

if [ ! -f "$APP_DIR/config.json" ]; then
  TMP_CONFIG="$(mktemp)"
  cat >"$TMP_CONFIG" <<JSON
{
  "server": {
    "listen_addr": "$LISTEN_ADDR",
    "public_base_url": "$PUBLIC_BASE_URL",
    "require_https": $REQUIRE_HTTPS,
    "web_dir": "./web"
  },
  "database": {
    "path": "./data/app.db",
    "busy_timeout_ms": 5000,
    "synchronous": "NORMAL"
  },
  "storage": {
    "photos_dir": "./data/photos",
    "thumbnails_dir": "./data/thumbnails",
    "tmp_dir": "./tmp"
  },
  "ffmpeg": {
    "path": "ffmpeg",
    "jpg_quality": 18,
    "max_width": 1600,
    "max_height": 1600
  },
  "backup": {
    "dir": "./backups"
  },
  "security": {
    "secret_path": "./server-secret.key"
  }
}
JSON
  "${SUDO[@]}" install -m 0644 "$TMP_CONFIG" "$APP_DIR/config.json"
  rm -f "$TMP_CONFIG"
fi

if [ -f "$APP_DIR/server-secret.key" ]; then
  "${SUDO[@]}" chmod 0600 "$APP_DIR/server-secret.key"
fi

if [ "$(id -u)" -eq 0 ]; then
  chown -R "$RUN_USER:$RUN_USER" "$APP_DIR"
else
  "${SUDO[@]}" chown -R "$RUN_USER:$RUN_USER" "$APP_DIR"
fi

echo "Installed ledger node to $APP_DIR"
echo "Edit $APP_DIR/config.json before public HTTPS deployment."
echo "Start with: $APP_DIR/scripts/start.sh"
