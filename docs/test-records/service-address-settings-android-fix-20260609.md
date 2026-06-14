# Service address settings Android fix test record - 2026-06-09

## Feature slice

- Fix Android settings service-address editing crash:
  `'package:flutter/src/widgets/framework.dart': Failed assertion: line 6268 pos 12: '_dependents.isEmpty': is not true`.
- Keep both places for manual service address entry:
  - Pairing page: host/IP and port fields.
  - Settings page: inline host/IP and port editor in the service-address card.

## Local server

- Command: `go run ./server/cmd/ledger-server -config ./var/test-runs/service-address-dialog-fix-20260609/config.json`
- Host API: `http://127.0.0.1:18083`
- Android emulator API entered in UI: host `10.0.2.2`, port `18083`
- Health check: `GET /api/health` returned `status=ok`, `database=ok`, `journal_mode=wal`.
- Test database: `var/test-runs/service-address-dialog-fix-20260609/data/app.db`

## Android emulator test result

- Device: `emulator-5554`.
- Package: `com.example.ledger_client`.
- Build: `flutter analyze` passed; `flutter build apk --debug` passed.
- Fresh install after uninstall succeeded.
- Pairing:
  - Pairing page initially showed `当前服务地址：未设置`.
  - Entered host `10.0.2.2` and port `18083`.
  - Requested pairing code from Android; server logged `POST /api/pair/start 200`.
  - Confirmed pairing with server console code; server logged `POST /api/pair/confirm 200`, `GET /api/bootstrap 200`, and `GET /api/transactions 200`.
- Settings save:
  - Settings page displayed `http://10.0.2.2:18083`.
  - Tapping edit expanded inline `服务 IP/主机` and `端口` fields.
  - Saving the unchanged address collapsed the inline editor and showed `服务地址已保存，后续请求将使用新地址`.
  - No red error screen appeared.
- Settings cancel:
  - Reopened inline editor and tapped `取消`.
  - Editor collapsed back to the settings card without error.
- Persistence:
  - Force-stopped and relaunched the app.
  - App opened directly to the transaction page.
  - Server logged fresh `GET /api/bootstrap 200` and `GET /api/transactions 200`, proving stored address and token were reused.
- Logs:
  - `adb logcat` scan found no `_dependents.isEmpty`, `Failed assertion`, `FlutterError`, `Another exception`, or `framework.dart` patterns after the passing run.

## Evidence

- `var/test-runs/service-address-dialog-fix-20260609/settings-inline-expanded.png`
- `var/test-runs/service-address-dialog-fix-20260609/settings-inline-after-save.png`
- `var/test-runs/service-address-dialog-fix-20260609/settings-inline-after-cancel.png`
- `var/test-runs/service-address-dialog-fix-20260609/after-restart.png`
- `var/test-runs/service-address-dialog-fix-20260609/logcat-inline-pass.txt`
- `var/test-runs/service-address-dialog-fix-20260609/logcat-after-restart.txt`

## Issues found and fixed

- The original settings edit flow used a dialog. Saving that dialog repeatedly reproduced the Flutter debug assertion on Android.
- Removing the post-save bootstrap refresh did not resolve the assertion.
- Replacing context-dependent focus cleanup with `FocusManager.instance.primaryFocus?.unfocus()` did not resolve the assertion by itself.
- The settings service-address editor was changed from a dialog to inline card editing, so saving/canceling no longer pops a dialog route. This fixed the assertion in emulator testing.
- `AppController.updateServiceEndpoint` keeps the new base URL in memory and secure storage without notifying the root tree; subsequent requests and cold start use the saved address.

## Web test result

- Not run in this fix slice.
- Reason: the reported failure was Android-only and the requested verification was Android emulator validation. Shared `flutter analyze` passed.

## Untested items

- Physical Android phone on a LAN IP.
- Production HTTPS service address.
- Switching to a different paired server after saving a new address.
- Full transaction CRUD, attachments, statistics, backup/checkpoint, and SMS import were not repeated in this crash-fix slice.
