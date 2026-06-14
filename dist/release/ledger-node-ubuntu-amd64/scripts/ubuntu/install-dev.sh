#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SERVER_SRC="${LEDGER_DEV_SERVER_SRC:-$PACKAGE_ROOT/dist/dev/ubuntu-amd64/ledger-server}"
WEB_SRC="${LEDGER_DEV_WEB_SRC:-$PACKAGE_ROOT/client/build/web}"
APK_SRC="${LEDGER_DEV_APK_SRC:-$PACKAGE_ROOT/client/build/app/outputs/flutter-apk/app-release.apk}"

export LEDGER_DEFAULT_APP_DIR="${LEDGER_DEFAULT_APP_DIR:-/opt/ledger-node-dev}"
export LEDGER_DEFAULT_PUBLIC_BASE_URL="${LEDGER_DEFAULT_PUBLIC_BASE_URL:-http://127.0.0.1:8080}"
export LEDGER_DEFAULT_REQUIRE_HTTPS="${LEDGER_DEFAULT_REQUIRE_HTTPS:-false}"
export LEDGER_INSTALL_LABEL="dev"
export LEDGER_INSTALL_SERVER_SRC="$SERVER_SRC"
export LEDGER_INSTALL_WEB_SRC="$WEB_SRC"
export LEDGER_INSTALL_APK_SRC="$APK_SRC"
export LEDGER_INSTALL_HINT="Build dev artifacts first: GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o dist/dev/ubuntu-amd64/ledger-server ./server/cmd/ledger-server; cd client && flutter build web"

. "$SCRIPT_DIR/install-common.sh"
