#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${LEDGER_APP_DIR:-${LEDGER_DEFAULT_APP_DIR:-/opt/ledger-node}}"
RUN_USER="${LEDGER_RUN_USER:-${SUDO_USER:-$(id -un)}}"
LISTEN_ADDR="${LEDGER_LISTEN_ADDR:-0.0.0.0:8080}"
PUBLIC_BASE_URL="${LEDGER_PUBLIC_BASE_URL:-${LEDGER_DEFAULT_PUBLIC_BASE_URL:-http://127.0.0.1:8080}}"
REQUIRE_HTTPS="${LEDGER_REQUIRE_HTTPS:-${LEDGER_DEFAULT_REQUIRE_HTTPS:-false}}"
INSTALL_LABEL="${LEDGER_INSTALL_LABEL:-ledger}"
SERVER_SRC="${LEDGER_INSTALL_SERVER_SRC:?LEDGER_INSTALL_SERVER_SRC is required}"
WEB_SRC="${LEDGER_INSTALL_WEB_SRC:?LEDGER_INSTALL_WEB_SRC is required}"
APK_SRC="${LEDGER_INSTALL_APK_SRC:-}"

if [ ! -x "$SERVER_SRC" ]; then
  echo "$INSTALL_LABEL server executable not found or not executable: $SERVER_SRC" >&2
  [ -n "${LEDGER_INSTALL_HINT:-}" ] && echo "$LEDGER_INSTALL_HINT" >&2
  exit 1
fi

if [ ! -d "$WEB_SRC" ]; then
  echo "$INSTALL_LABEL Flutter Web directory not found: $WEB_SRC" >&2
  [ -n "${LEDGER_INSTALL_HINT:-}" ] && echo "$LEDGER_INSTALL_HINT" >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required when installing outside a writable user directory" >&2
    exit 1
  fi
  SUDO=(sudo)
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

if [ -n "$APK_SRC" ]; then
  if [ -f "$APK_SRC" ]; then
    "${SUDO[@]}" install -m 0644 "$APK_SRC" "$APP_DIR/releases/$(basename "$APK_SRC")"
  elif [ -d "$APK_SRC" ]; then
    while IFS= read -r apk_file; do
      "${SUDO[@]}" install -m 0644 "$apk_file" "$APP_DIR/releases/$(basename "$apk_file")"
    done < <(find "$APK_SRC" -maxdepth 1 -type f -name "*.apk" -print)
  fi
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

echo "Installed $INSTALL_LABEL ledger node to $APP_DIR"
echo "Server source: $SERVER_SRC"
echo "Web source: $WEB_SRC"
echo "Edit $APP_DIR/config.json before public HTTPS deployment."
echo "Start with: $APP_DIR/scripts/start.sh"
