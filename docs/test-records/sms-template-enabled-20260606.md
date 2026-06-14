# SMS template enabled-filter test record - 2026-06-06

## Feature slice

- Android local SMS template learning from `msg_test.md` samples.
- Multiple templates per sender/account.
- User-enabled templates are used for extraction; disabled templates are ignored.

## Local server

- Existing server process: `var/test-runs/sms-template-msg-test/ledger-server.exe`
- Host API: `http://127.0.0.1:18080`
- Android emulator API: `http://10.0.2.2:18080`
- Test database: `var/test-runs/sms-template-msg-test/data/app.db`
- Reset before test:
  - Cleared `transactions`, `sms_imports`, transaction/SMS audit rows, and attachments.
  - Preserved baseline accounts: `现金`, `GZBANK` tail `3949`, `ICBC` tail `0973`.
  - Removed Android local `sms_templates_v1` only; preserved device token.

## Web test result

- Not run.
- Reason: SMS scanning and template learning are Android-only by project baseline. Web must not expose SMS scanning.

## Android emulator test result

- Device: `emulator-5554`.
- App package: `com.example.ledger_client`.
- Provider setup:
  - Cleared `content://sms`.
  - Injected 9 `msg_test.md` sample SMS rows by `adb emu sms send`.
  - Verified provider query returned 9 rows.
- Template learning:
  - Template page initially showed `已生成 0 个模板`.
  - A account `GZBANK 尾号3949` + sender `106980096655` learned 2 templates:
    - Balance template: sample count 3, initially disabled.
    - No-balance template: sample count 2, initially disabled.
  - B account `ICBC 尾号0973` + sender `95588` learned 1 template:
    - Balance template: sample count 4, initially disabled.
- Enabled-template extraction:
  - B only enabled: SMS scan showed 4 ICBC candidates.
  - A balance template only enabled, bank filter `GZBANK`: scan showed 3 GZBANK candidates.
  - A no-balance template only enabled, bank filter `GZBANK`: scan showed 2 GZBANK candidates.
  - A both templates enabled, bank filter `GZBANK`: scan showed 5 GZBANK candidates.
- Evidence:
  - `docs/test-records/artifacts/sms-template-enabled-20260606/android-b-template-scan.png`
  - `docs/test-records/artifacts/sms-template-enabled-20260606/android-a-both-templates-scan.png`

## Automated tests

- `flutter test` passed.
- `go test ./...` passed.
- Flutter unit coverage confirms `msg_test.md` learns A=2 templates and B=1 template, enabled templates filter extraction, and parsed candidates include amount, balance, bank, card tail, transaction time, direction, and merchant/counterparty.

## Untested items

- Physical Android phone.
- Import confirmation submission for these exact `msg_test.md` candidates.
- Web visual check in this run, because this slice is Android SMS-only.

## Issues found

- `adb shell content delete --uri content://sms/inbox` is not supported on this AVD; `content://sms` delete worked.
- `uiautomator dump` left one automation-process crash in crash buffer due to `UiAutomationService already registered`; the app process remained running. The crash buffer was cleared after verification.
