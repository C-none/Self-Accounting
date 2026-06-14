# Full Functional Test Record

测试日期：2026-06-03（Asia/Shanghai）

## 功能切片

- 全量隔离复测：服务端 API、Flutter Web、Flutter Android、交易 CRUD、筛选、统计、附件上传/FFmpeg 压缩、backup/checkpoint、短信手动扫描导入、安全边界。
- 测试目录：`var/test-runs/full-functional-20260603/`
- 截图与归档产物：`docs/test-records/artifacts/full-functional-20260603/`

## 本机服务端

- 启动命令：

```powershell
.\var\test-runs\full-functional-20260603\ledger-server.exe --config .\var\test-runs\full-functional-20260603\config.json
```

- Web/API 地址：`http://127.0.0.1:18081`
- Android Emulator 地址：`http://10.0.2.2:18081`
- `/api/health`：`status=ok`，`journal_mode=wal`
- 隔离数据库：`var/test-runs/full-functional-20260603/data/app.db`

## 自动化与 API 验证

通过：

```powershell
go test ./...
flutter analyze
flutter test
flutter build web --release
go build -trimpath -ldflags="-s -w" -o .\var\test-runs\full-functional-20260603\ledger-server.exe .\server\cmd\ledger-server
flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:18081
```

API 脚本：

```powershell
.\var\test-runs\full-functional-20260603\api-test.ps1
```

结果：`API_FULL_FUNCTIONAL_PASS`

覆盖结果：

- 未授权业务 API 返回 401。
- 首台设备为 admin；二次配对码重放返回 400；非 admin 调 admin API 返回 403。
- Web bootstrap 返回 `features.sms=false`，Android bootstrap 返回 `features.sms=true`。
- SQLite 只保存 token hash；服务端日志未出现 token、配对码、短信原文。
- 交易创建、非法金额/方向/分类校验、关键词/日期/方向过滤、编辑 version 增加、软删除和统计排除软删除均通过。
- Web 手动交易写入 `source='web'`，Android/API 手动交易写入 `source='manual'`。
- `amount_cent` 在 Web/manual/SMS 交易中均为 SQLite integer。
- 附件上传后 `compression_status='done'`；缩略图接口未认证返回 401，认证后返回 JPG。
- backup/checkpoint 通过；备份 zip 包含 `manifest.json`、`app.db`、`config.export.json`、`photos/`、`thumbnails/`；解压后 `PRAGMA integrity_check` 返回 `ok`；zip entry 未发现 Windows 盘符路径或反斜杠路径。
- SMS import API：Web/admin token 返回 403；包含 `raw_body` 返回 400；重复 `sms_hash` 返回 409。

产物：

- `api-thumbnail.jpg`
- `ledger-backup-20260603-141742.zip`

## Web 测试结果

- Go 托管 Flutter Web release 入口可打开。
- Web UI 配对成功。
- Web 底部导航只有“交易 / 统计 / 设置”，未展示“短信”入口。
- Web UI 完成新增交易 `¥77.89`、编辑为 `¥88.90`、关键词筛选只显示目标交易、删除后交易从列表消失。
- 统计页显示“分类占比”和“时间趋势”，支出合计与 API 数据一致。
- API 上传附件后，在 Web 编辑页可看到照片缩略图，截图中显示 `receipt-source.png`。
- Web 文件选择器未做自动化上传；原因是 Flutter Web 页面未暴露可直接定位的 `input[type=file]`，本轮用 API 上传 + Web 缩略图展示验证链路。
- 移动视口 390x844：`documentElement.scrollWidth=390`，`innerWidth=390`，页面文本不包含“短信”。

截图：

- `web-desktop-photo.png`
- `web-mobile-photo.png`

## Android 模拟器测试结果

设备：

- AVD：`Pixel_9_Pro`
- adb serial：`emulator-5554`
- Android：16

构建与安装：

```powershell
flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:18081
adb -s emulator-5554 install -r .\client\build\app\outputs\flutter-apk\app-debug.apk
adb -s emulator-5554 shell pm clear com.example.ledger_client
adb -s emulator-5554 shell am start -n com.example.ledger_client/.MainActivity
```

已验证：

- Android UI 配对成功。原 API 预生成配对码因 10 分钟有效期过期；为继续 UI 覆盖，在隔离 SQLite 中插入一条本轮一次性配对码，配对确认仍通过真实 Android UI 和 `/api/pair/confirm`。
- Android 底部导航显示“交易 / 统计 / 短信 / 设置”。
- Android UI 完成手动新增交易、关键词筛选、编辑金额 `¥12.34 -> ¥23.45`、删除后筛选列表显示“暂无交易”。
- 新增交易表单照片区显示 Android-only “拍照 / 相册”入口。
- 统计页显示“分类占比 / 时间趋势”，支出分类为 `餐饮 100.0% ¥277.77`。
- 短信页未授权时：“短信权限”可点，“重新扫描”禁用，显示“暂无候选短信”。
- 授权 SMS 权限后不会自动扫描历史短信；页面仍显示“暂无候选短信”，此时“重新扫描”变为可用。
- 点击“重新扫描”后，授权前发送的模拟短信出现候选：`咖啡店 ¥45.67`。
- 确认导入后，候选列表回到空状态；SQLite 校验最新短信交易为 `source='sms'`、`typeof(amount_cent)='integer'`、`amount_cent=4567`。

截图：

- `android-stats.png`
- `android-sms-before-permission.png`
- `android-sms-after-permission.png`
- `android-sms-candidate.png`
- `android-sms-imported.png`
- `android-sms-broadcast-crash.png`

## 未测试项及原因

- Android 在线短信广播监听：未通过。发送模拟短信后应用崩溃，无法验证 in-memory candidate queue。
- Android 断网收到短信不处理：未覆盖。由于在线广播已触发 crash，断网广播路径无法可靠执行。
- Android 实机相机拍照/图库选择：未执行。模拟器 UI 已确认“拍照 / 相册”入口；服务端压缩链路由 API 上传和 Web 缩略图展示验证。
- Ubuntu 真实恢复演练：未执行。本机未提供 Ubuntu/WSL 目标环境；已完成备份包 manifest、相对路径和 SQLite integrity 检查。

## 发现的问题

- Android SMS broadcast receiver 缺少网络状态权限导致崩溃。
  - 现象：发送在线模拟短信后系统弹出 `ledger_client keeps stopping`。
  - crash log：`android-crash.log`
  - 关键异常：

```text
java.lang.RuntimeException: Unable to start receiver com.example.ledger_client.SmsReceiver
Caused by: java.lang.SecurityException: ConnectivityService: Neither user ... nor current process has android.permission.ACCESS_NETWORK_STATE.
at com.example.ledger_client.SmsBridge.isNetworkAvailable(SmsReceiver.kt:57)
at com.example.ledger_client.SmsReceiver.onReceive(SmsReceiver.kt:17)
```

- Flutter Android debug build 通过但仍提示 `image_picker_android` 使用 Kotlin Gradle Plugin；这是未来 Flutter 版本兼容警告，本轮不阻塞。

## 体积记录

- Go 测试二进制：`ledger-server.exe`，10,855,936 bytes。
- Flutter Web `main.dart.js`：2,899,348 bytes。
- Android debug APK：176,896,183 bytes。
