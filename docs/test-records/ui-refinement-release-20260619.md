# UI refinement release package - 2026-06-19

## Slice

- Rebuilt release artifacts for the Flutter UI refinement slice.
- Set Flutter package version to `1.3.0+13000`.
- Android release APKs display version name `1.3.0`.

## Build Commands

```powershell
go test ./...
cd client
dart format lib test
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run --no-pub
flutter build apk --release --split-per-abi --no-pub
```

Server release binaries:

```powershell
go build -trimpath -ldflags="-s -w" -o dist\release\windows-amd64\ledger-server.exe .\server\cmd\ledger-server
$env:GOOS='linux'; $env:GOARCH='amd64'; $env:CGO_ENABLED='0'
go build -trimpath -ldflags="-s -w" -o dist\release\ubuntu-amd64\ledger-server .\server\cmd\ledger-server
```

## Artifacts

```text
dist/release/android/app-armeabi-v7a-release.apk: 16,517,271 bytes
dist/release/android/app-arm64-v8a-release.apk: 19,071,797 bytes
dist/release/android/app-x86_64-release.apk: 20,528,932 bytes
dist/release/web/main.dart.js: 3,154,700 bytes
dist/release/windows-amd64/ledger-server.exe: 11,024,384 bytes
dist/release/ubuntu-amd64/ledger-server: 10,690,722 bytes
dist/release/ledger-node-ubuntu-amd64.tar.gz: 45,297,134 bytes
dist/release/ledger-node-ubuntu-amd64.zip: 46,419,822 bytes
```

## Verification

- `go test ./...` passed.
- `dart format lib test` passed with no changes.
- `flutter analyze` passed.
- `flutter test` passed, 16 tests.
- Flutter Web release build passed; existing Cupertino icon-font warning remained.
- Android split-per-ABI release build passed.
- `dist/release/web/version.json` reports `version=1.3.0`, `build_number=13000`.
- `apkanalyzer manifest version-name` reports `1.3.0` for all three split APKs.
- Split APK version codes:
  - `armeabi-v7a`: `14000`
  - `arm64-v8a`: `15000`
  - `x86_64`: `17000`
- Ubuntu tar package contains `ledger-server`, `web/index.html`, `scripts/ubuntu/install.sh`, and `app-arm64-v8a-release.apk`.
- Windows release server smoke-started with `dist/release/web`; `GET /api/health` returned `status=ok`, `database=ok`, `journal_mode=wal`.

## Not Covered

- Release APK was not installed on a physical Android phone in this packaging pass.
- Ubuntu `install-release.sh` was not executed on a real Ubuntu server.
