# SMS raw display and imported-filter test record - 2026-06-06

## Feature slice

- Android SMS import candidates display the local SMS body for user verification.
- SMS confirm page displays the local SMS body in a read-only field.
- Successfully imported or server-duplicate SMS hashes are saved locally and hidden from later manual scans and broadcast polling.
- `msg_test.md` now includes additional synthetic SMS formats covering reordered fields, ISO timestamps, sign-prefixed amounts, merchant/location fields, English currency markers, and balance wording variants.

## Local server

- Existing server process: `var/test-runs/sms-template-msg-test/ledger-server.exe`
- Host API: `http://127.0.0.1:18080`
- Android emulator API: `http://10.0.2.2:18080`
- Test database: `var/test-runs/sms-template-msg-test/data/app.db`
- Reset before Android test:
  - Cleared `transactions`, `sms_imports`, transaction/SMS audit rows, and attachments.
  - Added synthetic `示例银行` test accounts for tails `0826`, `3179`, `6405`, `5551`, `7288`, and `4412`.
  - Cleared Android local `sms_templates_v1` and `sms_imported_hashes_v1`, preserving device token.

## Network reference use

- Fetched public bank SMS-notification service references before generating extra synthetic formats.
- The added examples are synthetic and were not copied as real customer SMS. They reflect common notification dimensions: account movement, amount, card tail, merchant/counterparty, transaction time, and balance.

## Web test result

- Not run.
- Reason: this feature is Android-only SMS import behavior. Web must not expose SMS scanning.

## Android emulator test result

- Device: `emulator-5554`.
- APK: debug build with `LEDGER_API_BASE=http://10.0.2.2:18080`.
- Provider setup:
  - Cleared `content://sms`.
  - Injected 24 actual sample rows parsed from `msg_test.md`.
  - Verified provider query returned 24 rows.
- Template generation:
  - Learned H account `示例银行 尾号4412` from sender `106900000006`.
  - UI showed `已学习 2 个模板 已生成 2 个模板`.
  - Enabled both templates.
- Candidate display:
  - Manual scan showed 2 candidates.
  - Candidate tiles displayed merchant/counterparty, amount, account tail, and `短信原文：...`.
  - Confirm page showed amount, direction, account, counterparty, description, and a read-only local SMS body field.
- Imported-filter behavior:
  - Imported one candidate successfully.
  - Candidate list immediately removed the imported SMS.
  - Manual rescan still showed only the remaining candidate; the imported SMS did not reappear.
- Database result:
  - `transactions=1`
  - `sms_imports=1`
  - Latest import stored structured fields only: amount `4260`, counterparty `美团外卖`, account hint `尾号4412`.

## Automated tests

- `flutter test` passed.
- `go test ./...` passed.
- Flutter tests now cover:
  - local raw body on `SmsCandidate`;
  - raw body excluded from `smsImportBody`;
  - A/B existing template counts;
  - C-H synthetic format template learning and enabled-template parsing;
  - H English-currency samples extracting counterparty.

## Untested items

- Physical Android phone.
- Web visual check, because this slice is Android SMS-only.

## Issues found and fixed

- The previous merchant template regex consumed card-tail text for formats where the date is followed by card tail; narrowed that regex so it does not cross a tail marker.
- Added support for `尾数` card-tail wording.
- Added support for ISO-style timestamps, sign-prefixed amounts, `可用余额为`, `对方户名`, and merchant extraction for English-currency payment messages.
