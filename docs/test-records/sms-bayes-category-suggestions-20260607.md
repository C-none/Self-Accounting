# SMS Bayesian category suggestions test record - 2026-06-07

## Feature slice

- Added authenticated `POST /api/category-suggestions`.
- Server trains a lightweight Multinomial Naive Bayes classifier from non-deleted historical transactions.
- Android SMS candidates merge high-confidence category suggestions while keeping SMS raw body local.

## Local server

- Unit/integration tests used `httptest` with temporary SQLite databases.
- Persistent local server started with `go run ./server/cmd/ledger-server -config config.dev.json`.
- Host API: `http://127.0.0.1:8080`.
- Health check returned `status=ok` and SQLite `journal_mode=wal`.
- `POST /api/category-suggestions` returned `method=nb` for a structured candidate from the dev database and rejected a request containing `raw_body`.

## Web test result

- `flutter build web --dart-define=LEDGER_API_BASE=http://127.0.0.1:8080` passed.
- Go server returned HTTP 200 for `/`.
- Web device bootstrap check returned `features.sms=false`.
- Browser visual navigation was not run because this slice does not add Web UI.

## Android emulator test result

- Device: `emulator-5554`.
- `flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:8080` passed.
- Installed debug APK with `adb install -r`.
- Launched app with `adb shell monkey`; screenshot captured at `docs/test-records/artifacts/sms-bayes-category-suggestions-20260607/android-launch.png`.
- Full SMS permission, template learning, SMS injection, scan, and candidate import UI flow was not rerun.

## Automated tests

- `go test ./...` passed.
- `flutter test` passed.

Go coverage includes:

- Multiclass Naive Bayes category prediction.
- Unknown-token smoothing.
- Insufficient training data response.
- Rejection of `raw_body` in suggestion requests.
- Soft-deleted transactions excluded from training.

Flutter coverage includes:

- SMS category suggestion request bodies exclude raw SMS text.
- High-confidence suggestions update candidate category.
- Low confidence, weak margin, or missing suggestions keep local category.
- `smsImportBody` still excludes raw SMS text.

## Untested items

- Browser visual pass.
- Android emulator SMS permission, template scan, and candidate UI pass.

## Issues found and fixed

- Kept category suggestion features aligned with the approved slice: account ID, amount bucket, counterparty n-grams, and description n-grams. `transaction_time` remains a validated request field, not a classifier feature.
