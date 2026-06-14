# Server migration redeploy closed-loop test - 2026-06-13

## Slice

- Package a Windows server node and redeploy it into a new directory.
- Verify the migrated server starts with the copied SQLite data and secret.
- Verify Web pairing against the migrated server and confirm the transaction list is unchanged.

## Local server

- Source node: `var/test-runs/server-migration-20260613-125654/source-node`
- Target node: `var/test-runs/server-migration-20260613-125654/target-node`
- Source URL: `http://127.0.0.1:18161`
- Target URL: `http://127.0.0.1:18162`
- Source start command: `.\ledger-server.exe --config .\config.json`
- Target start command: `.\ledger-server.exe --config .\config.json`
- Target test service was stopped after verification.

## Packaging and redeploy

- Built server binary with `go build -trimpath -ldflags="-s -w"`.
- Built Flutter Web with `flutter build web --release`.
- Created a source node containing `ledger-server.exe`, `config.json`, `web/`, `data/`, `backups/`, `tmp/`, and `server-secret.key`.
- Created one source transaction:
  - description: `MigrationKeep-20260613-125654`
  - counterparty: `迁移验证商户`
  - amount: `¥123.45`
- Called `POST /api/admin/checkpoint` before packaging.
- Compressed the whole source node to `ledger-node.zip`, expanded it to the target node, and changed only target listen/public URL port.

## Verification

- API before migration: keyword query for `MigrationKeep-20260613-125654` returned `total=1`.
- API after redeploy: same keyword query on target server returned `total=1`.
- SQLite target integrity check: `ok`.
- Target SQLite active transaction count: `1`; max description was `MigrationKeep-20260613-125654`.
- Web target flow:
  - Opened migrated Go-hosted Web at `http://127.0.0.1:18162`.
  - Requested target pairing code from Web pairing page.
  - Completed Web pairing against migrated target server.
  - Transaction list displayed `迁移验证商户 2026-06-13 12:57 · 餐饮 · 本人 · 现金 ¥123.45`.
- Screenshot: `docs/test-records/artifacts/server-migration-20260613/target-transactions.png`

## Size record

- `ledger-server.exe`: `10,979,840` bytes.
- Web directory: `43,531,270` bytes.
- Packaged zip: `19,834,584` bytes.

## Not tested

- Ubuntu Linux restore was not executed in this Windows-only run.
- Attachment/photo restore was not covered because this slice focused on server package redeploy and transaction retention.
- Android emulator was not run; requested verification was through Web.

## Issues found

- No migration data-loss issue found in this run.
