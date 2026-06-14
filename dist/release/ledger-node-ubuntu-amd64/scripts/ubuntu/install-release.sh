#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

if [ -x "$PACKAGE_ROOT/ledger-server" ]; then
  SERVER_SRC="$PACKAGE_ROOT/ledger-server"
elif [ -x "$PACKAGE_ROOT/dist/release/ubuntu-amd64/ledger-server" ]; then
  SERVER_SRC="$PACKAGE_ROOT/dist/release/ubuntu-amd64/ledger-server"
else
  echo "release server executable not found in package root or dist/release/ubuntu-amd64" >&2
  exit 1
fi

if [ -d "$PACKAGE_ROOT/web" ]; then
  WEB_SRC="$PACKAGE_ROOT/web"
elif [ -d "$PACKAGE_ROOT/dist/release/web" ]; then
  WEB_SRC="$PACKAGE_ROOT/dist/release/web"
else
  echo "release Flutter Web directory not found in package root or dist/release/web" >&2
  exit 1
fi

APK_SRC=""
if [ -f "$PACKAGE_ROOT/app-release.apk" ]; then
  APK_SRC="$PACKAGE_ROOT/app-release.apk"
elif [ -f "$PACKAGE_ROOT/dist/release/android/app-release.apk" ]; then
  APK_SRC="$PACKAGE_ROOT/dist/release/android/app-release.apk"
fi

export LEDGER_DEFAULT_APP_DIR="${LEDGER_DEFAULT_APP_DIR:-/opt/ledger-node}"
export LEDGER_INSTALL_LABEL="release"
export LEDGER_INSTALL_SERVER_SRC="$SERVER_SRC"
export LEDGER_INSTALL_WEB_SRC="$WEB_SRC"
export LEDGER_INSTALL_APK_SRC="$APK_SRC"

. "$SCRIPT_DIR/install-common.sh"
