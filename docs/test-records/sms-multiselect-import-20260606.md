# SMS multi-select import test record - 2026-06-06

## Feature slice

- Android SMS import candidate multi-select.
- Select all, cancel all, and import selected candidates in one action.
- Duplicate SMS import handling keeps the existing behavior: already imported SMS is treated as handled and removed from the candidate list.

## Local server

- Command: `go run ./server/cmd/ledger-server -addr 127.0.0.1:18080 -data-dir .\var\visual-audit\data -attachments-dir .\var\visual-audit\attachments`
- Host API: `http://127.0.0.1:18080`
- Android emulator API: `http://10.0.2.2:18080`
- Health check: `GET /api/health` returned OK.

## Web test result

- Not run for this slice.
- Reason: the feature is Android-only SMS import UI behavior; Web does not support SMS scanning by project baseline.

## Android emulator test result

- Device: `emulator-5554`.
- APK: debug build with `LEDGER_API_BASE=http://10.0.2.2:18080`.
- SMS tab displayed two synthetic SMS candidates after emulator SMS injection.
- Entered multi-select mode from the SMS import page.
- Verified initial multi-select state:
  - `全选` visible.
  - `导入选中(0)` disabled.
  - `退出多选` visible.
  - Both candidates showed unchecked checkboxes.
- Tapped `全选`.
- Verified selected state:
  - Button changed to `取消全选`.
  - `导入选中(2)` enabled.
  - Both candidate checkboxes were checked.
- Tapped `取消全选`.
- Verified unselected state:
  - Button changed back to `全选`.
  - `导入选中(0)` disabled.
  - Both candidate checkboxes were unchecked.
- Tapped `全选` again, then tapped `导入选中(2)`.
- UI result after import:
  - Notice displayed `已导入 2 条`.
  - Candidate list displayed `暂无候选短信`.
- Database result:
  - SMS transaction count changed from 5 to 7.
  - `sms_imports` count changed from 5 to 7.
  - Latest imported SMS records had `parsed_amount_cent` values `4222` and `4111`.
  - Latest imported SMS records had positive `sms_received_at_ms`.
- Android crash log buffer was empty after the flow.

## Untested items

- Physical Android phone test.
- Offline SMS arrival and later manual rescan.
- Duplicate re-import by sending the exact same provider SMS row again.

## Issues found and fixed

- Emulator initially appeared offline during setup. Resolved with `adb reconnect offline`.
- No functional issue was found during the multi-select import flow.
