# Editable service address Android closed-loop test record - 2026-06-09

## Feature slice

- Pairing page supports manual service IP/host and port input.
- Settings page supports editing service IP/host and port.
- Android stores the service address locally and uses it after restart.

## Local server

- Command: `go run ./server/cmd/ledger-server -config ./var/test-runs/editable-service-address-20260609/config.json`
- Host API: `http://127.0.0.1:18082`
- Android emulator API entered in UI: host `10.0.2.2`, port `18082`
- Test database: `var/test-runs/editable-service-address-20260609/data/app.db`
- Health check returned `status=ok`, `database=ok`, `journal_mode=wal`.

## Android emulator test result

- Device: `emulator-5554`.
- Package: `com.example.ledger_client`.
- Built APK without `LEDGER_API_BASE`: `flutter build apk --debug`.
- Fresh install succeeded after uninstall.
- Pairing page:
  - Initially showed `当前服务地址：未设置`.
  - Displayed `服务 IP/主机` and `端口` input fields.
  - Entered host `10.0.2.2` and port `18082`.
  - Page displayed `当前服务地址：http://10.0.2.2:18082`.
  - Android request reached server: `POST /api/pair/start 200`.
  - Android completed pairing: `POST /api/pair/confirm 200`.
  - Android loaded bootstrap and transactions through the manually entered address.
- Settings page:
  - Displayed service address `http://10.0.2.2:18082`.
  - Edit button opened a dialog prefilled with host `10.0.2.2` and port `18082`.
  - Saving the dialog showed `服务地址已保存`.
  - Server received a fresh `GET /api/bootstrap 200` after saving.
- Persistence:
  - Force-stopped and relaunched the app.
  - App opened directly to the transaction page instead of pairing.
  - Server received `GET /api/bootstrap 200` and `GET /api/transactions 200` after restart, proving stored service address and token were reused.
- Evidence:
  - `docs/test-records/artifacts/editable-service-address-20260609/android-after-restart.png`

## Web test result

- Not run.
- Reason: this slice was requested as Android emulator closed-loop testing. Web same-origin fallback was preserved by allowing empty service address fields on the pairing page.

## Untested items

- Physical Android phone on a real LAN IP.
- Production HTTPS address entry.
- Changing to a different reachable server after pairing.
- Full transaction CRUD, attachments, statistics, backup/checkpoint, and SMS import were not repeated in this address-setting slice.

## Issues found and fixed

- Android without a compiled `LEDGER_API_BASE` crashed on first frame because `Uri.base.origin` is invalid for `file:///`; fixed by displaying `未设置` when the runtime base URI is not HTTP/HTTPS.
- Service URL normalization briefly displayed `?#` for empty query/fragment; fixed normalization to build `scheme://host:port` explicitly.
- One adb input attempt entered port `082`, causing a network error against port `82`. Retried with a corrected port; this confirms the prior Android “network error” can be caused by an incorrect service address, not only by real network loss.
