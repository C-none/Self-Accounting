# Android HTTPS 服务地址回填修复记录

## 功能切片

- 修复 Android/Web 共用服务地址编辑逻辑：已保存的 HTTPS 地址回填编辑框时保留 `https://`。
- 未显式填写 scheme 且端口为 443 时，客户端按 HTTPS 规范化，避免保存为 `http://host:443`。
- 更新配对页和设置页服务地址输入提示。
- 重新构建 Web release 和三架构 Android release APK。

## 原因

旧逻辑使用 `Uri.host` 回填“服务 IP/主机”，会把 `https://neeewbieee.duckdns.org` 显示成 `neeewbieee.duckdns.org`。App 重启后用户再请求配对码时，页面会先保存当前服务地址，导致无 scheme 的 `host + 443` 被规范化成 HTTP 地址。

## 验证

```powershell
go test ./...
cd client
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run --no-pub
flutter build apk --release --split-per-abi --no-pub
```

新增单元测试覆盖：

- `https://neeewbieee.duckdns.org:443` 回填后仍保存为 HTTPS。
- `neeewbieee.duckdns.org + 443` 推断为 HTTPS。

## 产物

```text
dist/release/android/app-armeabi-v7a-release.apk: 16,386,079 bytes
dist/release/android/app-arm64-v8a-release.apk: 18,875,069 bytes
dist/release/android/app-x86_64-release.apk: 20,397,740 bytes
dist/release/web/main.dart.js: 3,096,244 bytes
dist/release/ledger-node-ubuntu-amd64.tar.gz: 45,118,647 bytes
dist/release/ledger-node-ubuntu-amd64.zip: 46,230,116 bytes
```

## 未测试项

- 未在真实 Android 手机上安装新 APK 验证重启回填；本轮由单元测试覆盖地址规范化逻辑。
- 未在真实 Ubuntu 服务器重新执行 `install-release.sh`；本轮只刷新 release 目录和 release 包。
