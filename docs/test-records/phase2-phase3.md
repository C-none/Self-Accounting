# Phase 2/3 Test Record

测试日期：2026-06-02（Asia/Shanghai）。备份文件名使用服务端 UTC 时间戳。

## 本次功能切片

- Phase 2：附件上传 API、FFmpeg JPG/缩略图压缩、Flutter 照片选择与缩略图展示、生产 HTTPS 配置校验、admin checkpoint/backup、恢复流程文档。
- Phase 3：Android SMS platform channel、短信权限、在线广播内存队列、手动重扫、本地解析、确认导入 UI、SMS import API、`sms_hash` 去重。
- 额外修复：备份与附件压缩共用服务端存储锁，避免备份包复制半成品 JPG；短信权限授权后不自动扫描历史短信，必须用户点击“重新扫描”。

## 本机服务端

启动方式：

```powershell
dist\ledger-server.exe --config config.visual-test.json
```

访问地址：

- Web/API：`http://127.0.0.1:18080`
- Android Emulator：`http://10.0.2.2:18080`

健康检查：

```json
{"database":"ok","journal_mode":"wal","status":"ok"}
```

## 自动化与构建

通过：

```powershell
go test ./...
go build -trimpath -ldflags="-s -w" -o dist\ledger-server.exe .\server\cmd\ledger-server
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080
flutter build apk --release --target-platform android-arm64 --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080
```

构建产物：

- `dist/ledger-server.exe`：10,855,936 bytes。
- `client/build/web`：38 files，42,815,441 bytes；`main.dart.js` 2,899,348 bytes。
- `app-debug.apk`：155,220,724 bytes。
- `app-release.apk`：18,526,018 bytes。

注意：`image_picker_android` 当前仍提示使用 Kotlin Gradle Plugin，Flutter 本次构建通过；后续 Flutter 版本可能要求插件迁移到 Built-in Kotlin。

## Web 测试结果

API 闭环：

- Web 设备 bootstrap 返回 `features.sms=false`。
- 新增交易写入 `source='web'`。
- `POST /api/attachments` 上传 PNG 成功，服务端返回 `compression_status='done'`。
- `GET /api/transactions/{id}/attachments` 返回 1 条附件。
- `GET /api/attachments/{id}/thumbnail` 通过 bearer token 返回 JPG，缩略图样例 1,702 bytes。
- `POST /api/admin/checkpoint` 返回 `busy=0`。
- `POST /api/admin/backup` 生成 `ledger-backup-20260601-174638.zip`，12,805 bytes。
- 备份样例已归档到 `docs/test-records/artifacts/ledger-backup-20260601-174638.zip`。

备份恢复检查：

- 解压备份包后执行 `sqlite3 app.db "PRAGMA integrity_check;"` 返回 `ok`。
- zip 包包含 `manifest.json`、`app.db`、`config.export.json`、`photos/`、`thumbnails/`。
- zip entry 不包含 Windows 盘符绝对路径或反斜杠路径。
- 本机未安装 WSL/Ubuntu，真实 Windows -> Ubuntu / Ubuntu -> Windows 恢复演练未执行。

视觉检查：

- Playwright 390x844 截图：`docs/test-records/artifacts/web-phase23-pairing-mobile.png`。
- 布局指标：`scrollWidth=390`、`clientWidth=390`、无水平溢出。
- Web 首屏未展示短信入口。

## Android 模拟器测试结果

设备：

- AVD：`Pixel_9_Pro`
- adb serial：`emulator-5554`

已验证：

- Debug APK 可安装运行并连接 `http://10.0.2.2:18080`。
- Android bootstrap 启用短信 tab，Web 不启用短信 tab。
- 短信权限申请弹窗可触发并授权。
- 模拟短信：

```powershell
adb -s emulator-5554 emu sms send 95555 "尾号1234账户消费45.67元，商户：咖啡店"
```

- 授权后不会自动扫描历史短信；点击“重新扫描”后显示候选。
- 确认候选后服务端写入 `transactions.source='sms'`，`amount_cent` 在 SQLite 中为 integer，`sms_imports.status='confirmed'`。
- SMS import API 拒绝包含 `raw_body` 的请求，重复 `sms_hash` 返回 HTTP 409。
- 新增交易表单的照片区在 Android 视觉检查中显示“拍照/相册”入口，无明显遮挡或溢出：`docs/test-records/artifacts/android-phase23-photo-form-invalid-token.png`。

视觉证据：

- `android-phase23-sms-before-permission.png`
- `android-phase23-sms-candidate.png`
- `android-phase23-sms-imported.png`
- `android-phase23-sms-manual-rescan.png`
- `android-phase23-current.png`
- `android-phase23-photo-form-invalid-token.png`

## 未测试项及原因

- Ubuntu 真实恢复演练：本机 `wsl -l -v` 显示未安装 Linux 发行版；已完成备份包完整性、SQLite integrity 和跨平台相对路径检查。
- Android 断网收到新短信：代码路径为 receiver 检测无网络即返回，不入队、不解析；本轮没有稳定完成 emulator 网络断开状态下的广播复现。
- Android 实机相机拍照：模拟器视觉确认照片入口，真实压缩上传链路用 API 文件上传验证；未用实体摄像头拍照。

## 发现并修复的问题

- Windows 上 `image_picker_android` 触发 Kotlin incremental cache 异常；在 `client/android/gradle.properties` 中关闭 Kotlin incremental 并使用 in-process 编译后，debug/release APK 构建通过。
- 初版短信页在授权后会自动扫描历史短信；已改为仅更新权限状态，历史扫描必须用户点击“重新扫描”。
- 初版备份可与附件压缩并发；已增加服务端存储锁，备份和 FFmpeg 最终 JPG/缩略图写入互斥。
