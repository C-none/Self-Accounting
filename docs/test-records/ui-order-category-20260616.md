# UI order/category slice test record - 2026-06-16

## Slice

- Statistics colors and timeline legend value toggle.
- Transaction list three-line display.
- Single category picker field with bottom two-column category panel.
- Master-data display ordering for categories, members, and accounts.

## Server

- Started local server with:
  - `.\var\codex-ledger-server.exe --config .\config.visual-test.json`
- API/Web URL:
  - `http://127.0.0.1:18080`
- Health check returned `status=ok`, `database=ok`, `journal_mode=wal`.

## Automated Checks

- `go test ./...` passed.
- `dart format client\lib client\test` passed with no changes after final edit.
- `flutter analyze` passed.
- `flutter test` passed, 14 tests.
- `flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18080` passed.
  - Existing icon-font warning remained: Cupertino icon font was not bundled; build still completed.
- `flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080` passed.

## Web Verification

Artifacts are under `docs/test-records/artifacts/ui-order-category-20260616/`.

- `web-transactions.png`
  - Transaction rows show category line, detail line, and `使用人 - HH:mm`.
  - Web navigation has no SMS tab.
- `web-form.png`
  - Transaction form exposes one `分类` field instead of separate first/second category dropdowns.
- `web-category-picker.png`
  - Bottom two-column category picker opens from `分类`.
  - Left side shows first-level categories.
  - Right side shows `仅一级分类` and child items grouped with visible dividers.
  - No visible scrollbars.
- `web-stats-default.png`, `web-stats-line-default-viewport.png`
  - Pie chart uses high-contrast colors and slice separators.
  - Timeline chart does not show amount labels by default.
- `web-stats-legend-selected-viewport.png`
  - Clicking the blue legend shows only the blue series point values.
- `web-master-order.png`, `web-master-order-lower.png`
  - Category, member, and account rows show move-up/move-down controls.

## Android Emulator Verification

- Emulator: `Pixel_9_Pro`, serial `emulator-5554`.
- Installed `client\build\app\outputs\flutter-apk\app-debug.apk`.
- Existing higher-version package in the emulator caused `INSTALL_FAILED_VERSION_DOWNGRADE`; resolved by uninstalling `com.example.ledger_client` from the emulator and installing the debug APK.
- App paired through the real Android UI against `http://10.0.2.2:18080`.

Artifacts:

- `android-transactions.png`
  - Android transaction rows show category line, detail line, and `使用人 - HH:mm`.
  - Android navigation includes the SMS tab.
- `android-form.png`
  - Android transaction form exposes one `分类` field.
- `android-category-picker.png`
  - Bottom two-column category picker opens and shows grouped categories/dividers.
- `android-stats-line.png`
  - Android statistics chart renders high-contrast pie colors and no default timeline amount labels.
- `android-stats-legend-selected.png`
  - Clicking the blue legend shows only blue series amount labels.
- `android-master-order.png`
  - Android master-data category rows show move-up/move-down controls.
- `android-sms-page.png`
  - SMS tab opened after permission refresh and manual rescan.
  - Emulator scan diagnostic after injected SMS: read 2 rows, 95588 rows 1, templates 0, matches 0, candidates 0.

## Not Fully Covered

- SMS confirmation page category picker was not visually reached in this emulator run.
  - Reason: the fresh emulator install had no local enabled SMS templates, and SMS import requires an enabled template before producing candidates.
  - Evidence: scan diagnostic showed `模板0个，匹配0条，候选0条` after granting SMS permissions and injecting a 95588 test SMS.
  - Code path was updated to use the shared category picker in `SmsConfirmPage`; manual transaction form verified the shared picker on Android.
- Real photo upload/FFmpeg compression was not rerun in this slice; this change did not touch attachment upload or compression.

## Issues Found And Fixed

- Timeline chart still drew a max amount label by default; removed it so default line charts show no amount numbers until a legend item is selected.
- Initial Web automation clicked the wrong coordinates for the form/category picker and used too short a Flutter Web first-frame wait; reran with corrected waits and coordinates.
- Android `adb input text` dropped a digit while typing the pairing code; switched to per-digit keyevents and restored the accidentally edited port field.
