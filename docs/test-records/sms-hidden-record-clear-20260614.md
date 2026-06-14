# SMS hidden-record clear record

## Feature slice

- Added an Android-only SMS import page action named "清除本机短信隐藏记录".
- The action deletes only the local `sms_imported_hashes_v1` cache used to hide previously imported or duplicate SMS candidates.
- The action does not delete server transactions, local SMS templates, device tokens, or any SQLite data.
- Empty SMS scans show only local diagnostic counts: read rows, rows in range, 95588 rows, non-empty bodies, template count, template matches, candidates, and hidden hashes.

## Diagnosis context

- Real device checked by ADB: `10AD7E057E001BK`, package `com.example.ledger_client`, version `1.0.0` / `2001`.
- SMS permissions and network permissions were granted.
- Recent local 95588 messages matched the current enabled template, including balances containing comma separators.
- The import page originally showed no candidates, so the hidden-hash cache was made clearable from the UI.
- Real-device diagnostics after clearing showed no app-visible 95588 rows. The debug diagnostic build read 12 SMS rows in the selected range, 0 rows from sender 95588, 12 rows with non-empty bodies, 1 enabled template, 0 template matches, 0 candidates, and 0 hidden hashes. The final release build read 22 SMS rows in the selected range, 0 rows from sender 95588, 22 rows with non-empty bodies, 1 enabled template, 0 template matches, 0 candidates, and 0 hidden hashes.
- ADB shell could still see 36 SMS rows in the same selected range, including 14 rows from 95588, and all 14 matched the current template. This indicates the Vivo system SMS provider is filtering 95588 financial SMS from third-party app queries even though `READ_SMS` is granted.
- No SMS raw body is recorded in this test note.

## Validation

```powershell
go test ./...
cd client
flutter analyze
flutter test
flutter build apk --debug --no-pub
flutter build apk --release --split-per-abi --no-pub
adb -s 10AD7E057E001BK install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

Result: all commands passed.

Release APK artifacts refreshed in `dist/release/android`:

```text
app-armeabi-v7a-release.apk: 16,386,199 bytes
app-arm64-v8a-release.apk: 18,940,725 bytes
app-x86_64-release.apk: 20,397,860 bytes
```

## Database and deployment impact

- No database migration or server redeploy is required for the button itself.
- Users need a rebuilt and reinstalled Android APK to see the new button. The arm64 release APK was installed on the real device for this slice.

## Not covered

- 95588 import could not complete on the Vivo real device because the app-level SMS provider query returned no 95588 rows. ADB shell can see and match those messages, so the remaining blocker is device/OEM SMS privacy behavior rather than the parser template.
