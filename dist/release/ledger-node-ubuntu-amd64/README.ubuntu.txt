Ubuntu release bundle

Release install:
  bash scripts/ubuntu/install-release.sh

Compatibility install:
  bash scripts/ubuntu/install.sh

Dev install:
  bash scripts/ubuntu/install-dev.sh

Optional install variables:
  LEDGER_APP_DIR=/opt/ledger-node
  LEDGER_RUN_USER=ledger
  LEDGER_LISTEN_ADDR=0.0.0.0:8080
  LEDGER_PUBLIC_BASE_URL=https://ledger.example.com
  LEDGER_REQUIRE_HTTPS=true

Release install reads:
  ledger-server or dist/release/ubuntu-amd64/ledger-server
  web/ or dist/release/web

Dev install reads:
  dist/dev/ubuntu-amd64/ledger-server
  client/build/web

Start:
  /opt/ledger-node/scripts/start.sh

Stop:
  /opt/ledger-node/scripts/stop.sh

Export database:
  /opt/ledger-node/scripts/db-export.sh

Import database:
  /opt/ledger-node/scripts/db-import.sh /path/to/ledger-db-export.tar.gz
