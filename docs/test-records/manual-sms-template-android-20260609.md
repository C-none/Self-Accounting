# Manual SMS template Android closed-loop test record - 2026-06-09

## Feature slice

- Replaced local SMS auto-learning with Android manual SMS templates.
- Verified enabled manual template matching and brace-field extraction on Android.
- Verified confirmed SMS import writes structured server data without uploading SMS raw body.

## Local server

- Command: `go run ./server/cmd/ledger-server -config ./var/test-runs/manual-sms-template-20260609/config.json`
- Host API: `http://127.0.0.1:18081`
- Android emulator API: `http://10.0.2.2:18081`
- Test database: `var/test-runs/manual-sms-template-20260609/data/app.db`
- Test storage: `var/test-runs/manual-sms-template-20260609/data`
- Server health: `/api/health` returned `status=ok`, `database=ok`, `journal_mode=wal`.

## Android emulator test result

- Device: `emulator-5554`.
- Package: `com.example.ledger_client`.
- Build: `flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:18081` passed.
- Install: uninstall + fresh install succeeded after one ambiguous reinstall output.
- Pairing:
  - Android requested a console-only pairing code.
  - Android completed pairing.
  - Settings displayed service URL `http://10.0.2.2:18081`.
- Test account setup:
  - Created server account `示例银行` with masked identifier `4412`.
  - Android restart refreshed bootstrap and showed the account in template scope.
- Manual template page:
  - Page displayed rule text, example template, and slot word chips.
  - Selected account `示例银行 尾号4412`.
  - Entered sender `106900000006`.
  - Saved enabled template:
    - `BANK card {card_tail} at {merchant} {direction} RMB{amount}, time:{date_time}, balance:{balance}`
  - Template list showed 1 enabled template with fields `amount, balance, card_tail, date_time, direction, merchant`.
- SMS scan:
  - Cleared emulator SMS provider with `content://sms`.
  - Injected SMS from `106900000006`:
    - `BANK card 4412 at JD 支出 RMB89.90, time:2026-06-06 15:22, balance:6500.10`
  - Permission flow displayed Android SMS permission dialog and Allow was selected.
  - Before permission, `重新扫描` was disabled.
  - After permission, `重新扫描` was enabled.
  - Manual rescan produced one candidate:
    - Counterparty `JD`.
    - Time `2026-06-06 15:22`.
    - Account `示例银行 尾号4412`.
    - Amount `¥89.90`.
    - Local raw SMS body displayed only in Android UI.
- Confirmation/import:
  - Confirm page showed amount `89.90`, direction `支出`, account `示例银行 尾号4412`, counterparty `JD`, and local SMS body.
  - `POST /api/sms/imports` returned 201.
  - Candidate was hidden after successful import.
- Evidence:
  - `docs/test-records/artifacts/manual-sms-template-android-20260609/android-sms-after-import.png`

## Database verification

- Latest SMS transaction query returned:
  - `source=sms`
  - `amount_cent=8990`
  - `typeof(amount_cent)=integer`
  - `counterparty=JD`
  - `account=示例银行`
  - `masked_identifier=4412`
- Latest `sms_imports` row returned:
  - `parsed_amount_cent=8990`
  - `parsed_direction=expense`
  - `parsed_counterparty=JD`
  - `parsed_account_hint=尾号4412`
  - `sender_masked=106**06`
- Checked concatenated stored SMS import structured fields for the injected raw prefix; raw SMS body was not found in those fields.

## Web test result

- Not run.
- Reason: this slice is Android-only SMS template setup and SMS scanning. Web must not expose SMS scanning by project baseline.

## Untested items

- Physical Android phone.
- Exact Chinese H template text entered through UI; adb text input for Chinese fixed template content is unstable, so this run used an equivalent ASCII fixed template with the same brace-field extraction path.
- Background SMS receiver flow; this run verified manual rescan.
- Attachment, statistics, backup/checkpoint, transaction edit, and soft delete were not repeated in this SMS-template-focused slice.

## Issues found

- Initial reinstall output showed both `Success` and `INSTALL_FAILED_INSUFFICIENT_STORAGE`; package existed, but to avoid stale build risk the app was uninstalled and freshly installed.
- First pairing attempt used the stale/ambiguous install and did not reach the test server for `pair/confirm`; fresh install fixed it.
