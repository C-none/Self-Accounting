# SMS time placeholder and statistics default range - 2026-06-13

## Slice

- SMS template extraction keeps `{date_time}` as a local template placeholder.
- SMS import transaction time uses the Android SMS provider received time, not the plaintext SMS time.
- Statistics page default date range is from one month before today through today.

## Local server

- Not started in this run.
- Reason: no server API or database behavior changed; server validation was covered by `go test ./server/...`.

## Web test result

- Browser closed-loop test not run.
- Covered by Flutter unit test for `defaultStatsDateRange`, including month-end clamping.

## Android emulator test result

- Android emulator closed-loop test not run.
- Covered by Flutter SMS parser/template tests using `msg_test.md` samples. The tests verify enabled-template parsing, `{date_time}` template matching, and `smsTime` equal to received SMS time.

## Commands

- `flutter analyze`: passed.
- `flutter test`: passed.
- `go test ./server/...`: passed.

## Fixed issues found during testing

- Preserved balance prefixes such as `账户余额`, `当前余额`, and `可用余额为` in learned SMS templates so generated templates match the original SMS body.
- Preserved whether currency amounts include a trailing `元`, so `RMB89.90` templates match messages without forcing `元`.
