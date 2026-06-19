# Flutter UI refinement test record - 2026-06-19

## Slice

- Transaction page filter layout: fixed rows for `方向/分类` and `使用人/账户`, full-width start/end date rows, and `MM-DD-YYYY` transaction date filter text.
- Transaction row detail line: `详细描述 · 交易对象`, with bank/account omitted and the line hidden when both values are empty.
- Statistics charts: medium-dark Morandi-style colors aligned with the green theme, plus the follow-up fix aligning the `清除过滤` button height with filter fields.
- Master-data management: compact direction sections for `支出`、`收入`、`转账`, compact `新增` buttons, independent item cards, and long-press three-line drag handles.
- SMS import page: `清除本机短信隐藏记录` moved into the SMS import AppBar immediately left of refresh.

No server API, database schema, backup script, or SMS parsing behavior was changed.

## Server

- Started local server with:
  - `go run ./server/cmd/ledger-server --config ./config.visual-test.json`
- API/Web URL:
  - `http://127.0.0.1:18080`
- Android emulator API URL:
  - `http://10.0.2.2:18080`
- Health check returned `status=ok`, `database=ok`, `journal_mode=wal`.

## Automated Checks

- `go test ./...` passed.
- `cd client; dart format lib test` passed.
- `cd client; flutter analyze` passed.
- `cd client; flutter test` passed, 16 tests.
- `cd client; flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18080 --dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/` passed.
  - Existing Cupertino icon-font warning remained; build still completed.
  - The local CanvasKit define was used because the Playwright browser could not load the remote CanvasKit asset from `gstatic.com`.
- `cd client; flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080` passed.

## Web Verification

Artifacts are under `docs/test-records/artifacts/ui-refinement-20260619/`.

- `web-paired.png`
  - Transaction filters show `方向 : 分类 = 2 : 4` and `使用人 : 账户 = 2 : 4`.
  - Start/end transaction date filters each occupy a full row and display `06-12-2026` / `06-19-2026`.
  - Transaction rows show detail/counterparty without bank account on the second line.
  - Web navigation has no SMS tab.
- `web-stats-aligned.png`
  - Statistics chart colors render with the muted Morandi palette.
  - Desktop `清除过滤` button height aligns with the dense filter controls.
- `web-settings.png`
  - Settings page still has no SMS import entry on Web.
- `web-master.png`
  - Master-data category sections use compact add buttons, independent cards, and three-line drag handles.

## Android Emulator Verification

- Initial `adb devices` was empty.
- Started `Pixel_9_Pro` headless with a cold boot; final serial was `emulator-5554`.
- Installed `client/build/app/outputs/flutter-apk/app-debug.apk`.
- A previous higher-version install caused `INSTALL_FAILED_VERSION_DOWNGRADE`; resolved by uninstalling `com.example.ledger_client` before installing the debug APK.
- A later reinstall hit `INSTALL_FAILED_INSUFFICIENT_STORAGE`; resolved by uninstalling and reinstalling the debug APK.
- App paired through the real Android UI against `http://10.0.2.2:18080`.
- Taps for settings navigation used the Android UI tree bounds; screenshots were captured with `adb exec-out screencap`.

Artifacts:

- `android-transactions.png`
  - Android transaction filters use the fixed two-column rows and full-width date rows.
  - Transaction rows show `通勤 · 地铁` and `早餐拿铁 · 咖啡店` without bank account on the second line.
  - Android navigation includes the SMS tab.
- `android-stats.png`
  - Mobile `清除过滤` button height matches the surrounding filter fields.
  - Statistics chart colors use the muted Morandi palette.
- `android-sms.png`
  - SMS import AppBar shows `清除本机短信隐藏记录` immediately left of refresh.
  - The large body clear-hidden-records button is absent.
- `android-settings.png`
  - Settings page remains the entry point for `基础资料管理`.
- `android-master.png`
  - Category section add buttons are compact on Android.
  - Category items and expanded child categories render as independent cards with three-line drag handles.
- `android-master-transfer.png`
  - `收入` and `转账` sections use the same compact add-button and independent-card pattern.
  - Member and account rows keep the same card and drag-handle pattern.

## Not Fully Covered

- Real SMS import candidate generation was not rerun; this slice only moved the hidden-record clear action within `SmsImportPage`.
- Photo upload, FFmpeg compression, backup/checkpoint, and Ubuntu restore flows were not rerun because this slice did not touch those paths.
- Drag handles and optimistic reorder code paths were visually verified on Web and Android. A manual reorder mutation was not persisted during this run to avoid changing the shared visual-test master data order.

## Issues Found And Fixed

- Flutter Web initially rendered a blank page in Playwright because the browser could not fetch remote CanvasKit. Rebuilt Web with the local `FLUTTER_WEB_CANVASKIT_URL=canvaskit/` define for verification.
- Android emulator first launch did not attach to ADB. Restarted the emulator headless with `-no-snapshot-load` and verified boot completion.
- Category reorder used a deprecated `ReorderableListView.onReorder`; replaced it with `onReorderItem` before the final analyzer run.
- The statistics `清除过滤` button was still shorter than mobile filter fields after the desktop alignment fix; changed it to use a responsive height so desktop uses the dense field height and narrow/mobile uses the standard field height.
