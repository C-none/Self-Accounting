Ubuntu release bundle

Install:
  bash scripts/ubuntu/install.sh

Optional install variables:
  LEDGER_APP_DIR=/opt/ledger-node
  LEDGER_RUN_USER=ledger
  LEDGER_LISTEN_ADDR=0.0.0.0:8080
  LEDGER_PUBLIC_BASE_URL=https://ledger.example.com
  LEDGER_REQUIRE_HTTPS=true

Start:
  /opt/ledger-node/scripts/start.sh

Stop:
  /opt/ledger-node/scripts/stop.sh

Export database:
  /opt/ledger-node/scripts/db-export.sh

Import database:
  /opt/ledger-node/scripts/db-import.sh /path/to/ledger-db-export.tar.gz
