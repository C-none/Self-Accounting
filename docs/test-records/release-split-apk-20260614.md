# 小小记账 release split APK 记录

## 功能切片

- 将客户端显示名改为“小小记账”。
- Android release APK 改为按 ABI 分包。
- 更新 release 目录和 Ubuntu release 包，使其包含三份 APK。
- 更新 Ubuntu 安装脚本，使 release/dev 安装都能复制 APK 目录中的多个 APK。

## 构建命令

```powershell
go test ./...
cd client
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run --no-pub
flutter build apk --release --split-per-abi --no-pub
```

服务端 release 二进制：

```powershell
go build -trimpath -ldflags="-s -w" -o dist\release\windows-amd64\ledger-server.exe .\server\cmd\ledger-server
$env:GOOS='linux'; $env:GOARCH='amd64'; $env:CGO_ENABLED='0'
go build -trimpath -ldflags="-s -w" -o dist\release\ubuntu-amd64\ledger-server .\server\cmd\ledger-server
```

## 产物

```text
dist/release/android/app-armeabi-v7a-release.apk: 16,386,079 bytes
dist/release/android/app-arm64-v8a-release.apk: 18,875,069 bytes
dist/release/android/app-x86_64-release.apk: 20,397,740 bytes
dist/release/windows-amd64/ledger-server.exe: 10,998,784 bytes
dist/release/ubuntu-amd64/ledger-server: 10,666,146 bytes
dist/release/web/main.dart.js: 3,096,146 bytes
dist/release/ledger-node-ubuntu-amd64.tar.gz: 45,118,427 bytes
dist/release/ledger-node-ubuntu-amd64.zip: 46,229,797 bytes
```

## 验证

- `go test ./...` 通过。
- `flutter analyze` 通过。
- `flutter test` 通过。
- Flutter Web release 构建成功，保留 MaterialIcons tree-shake 警告。
- Android split-per-ABI release 构建成功，产出 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三份 APK。
- `apkanalyzer manifest application-id` 确认 APK 包名仍为 `com.example.ledger_client`，用于保留升级路径。
- `dist/release/web/index.html` 和 `dist/release/web/manifest.json` 已包含“小小记账”。
- Ubuntu release tar 包包含三份 APK、`ledger-server`、`web/index.html` 和 `install-release.sh`。

## 未测试项

- 未安装 release APK 到真实 Android 手机或模拟器。
- 未在真实 Ubuntu 服务器重新执行 `install-release.sh`。
- 本机 `bash` 指向未安装发行版的 WSL，未执行 `bash -n`；脚本变更通过内容检查和包内路径检查验证。
