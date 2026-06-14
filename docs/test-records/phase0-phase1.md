# Phase 0/1 Test Record

Date: 2026-06-01

## 功能切片

- Phase 0：Go 服务端骨架、SQLite WAL 初始化、Flutter Android/Web shell、Go 托管 Flutter Web、体积基线。
- Phase 1：SQLite schema、最小基础数据种子、设备配对、bootstrap、交易新增/列表/过滤/编辑/软删除、统计 API、自绘统计 UI。

## 本机服务端

- 启动命令：

```powershell
dist\ledger-server.exe --config .\config.dev.json
```

- 访问地址：`http://127.0.0.1:8080`
- Android 模拟器访问地址：`http://10.0.2.2:8080`
- `/api/health`：`status=ok`，`journal_mode=wal`
- SQLite 检查：
  - `transactions.amount_cent` 类型为 `INTEGER`
  - 测试交易写入后 `typeof(amount_cent)=integer`
  - 删除后 `deleted_at IS NOT NULL`
  - `devices.token_hash` 长度为 64，未保存 token 明文

## 自动化与命令验证

- `go test ./...`：通过。
- `flutter analyze`：通过。
- `flutter test`：通过，覆盖 RMB 字符串到 `amount_cent` 的整数转换。
- `flutter build web --release`：通过。当前 Flutter 3.44.0 不支持 `flutter build web --analyze-size`。
- `flutter build apk --release --target-platform android-arm64 --analyze-size`：通过。
- API 闭环：本机 REST 完成首台配对、bootstrap、交易新增、过滤查询、编辑、统计、软删除；软删除后默认列表返回 0 条。
- 额外审计：日期范围过滤使用两条不同时间交易验证，`from/to` 范围内只返回目标交易。

## Web 测试结果

- 通过 Go 托管的 release `client/build/web` 访问。
- Playwright 验证：
  - 首台 Web 配对成功。
  - Web 不展示短信入口。
  - 新增交易 `56.78`，列表显示 `¥56.78`。
  - 编辑为 `66.66` 后列表刷新为 `¥66.66`。
  - 统计页显示分类占比和时间趋势图表，数据来自统计 API。
  - 删除最后一条交易后显示“暂无交易”。
- 视觉检查：
  - 桌面和移动宽度截图检查无横向滚动、无文字挤压。
  - 额外审计：当前移动 Web `documentElement.scrollWidth=390`，等于 `innerWidth=390`；页面文本不包含“短信”。
  - 截图产物：`docs/test-records/artifacts/web-stats-desktop.png`、`docs/test-records/artifacts/web-stats-mobile.png`。
  - 发现删除最后一条交易后 `items:null` 导致 Web 页面类型错误，已修复为空数组兼容。
  - 发现默认 Material 3 绿色铺底过重，已调整为中性页面背景和白色卡片。

## Android 模拟器测试结果

- AVD：`Pixel_9_Pro`
- Serial：`emulator-5554`
- 安装方式：

```powershell
flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:8080
adb -s emulator-5554 install -r client\build\app\outputs\flutter-apk\app-debug.apk
adb -s emulator-5554 shell am start -n com.example.ledger_client/.MainActivity
```

- 验证结果：
  - Android 输入配对码后配对成功。
  - Android 交易页显示 Android-only “短信”入口；Web 无此入口。
  - 新增交易 `23.45` 成功，列表显示 `¥23.45`。
  - 打开编辑页并保存，返回列表。
  - 统计页显示 `餐饮 100.0% ¥23.45` 和时间趋势图。
  - 删除交易后列表显示“暂无交易”。
- 视觉检查：
  - 使用 `adb exec-out screencap -p` 和视觉查看检查统计页、交易页。
  - 日期范围过滤按钮在 Pixel_9_Pro 竖屏下无截断或重叠。
  - 截图产物：`docs/test-records/artifacts/android-stats-updated.png`、`docs/test-records/artifacts/android-transactions-updated.png`。

## 性能/体积记录

- Go release binary：`dist/ledger-server.exe`，10,450,432 bytes。
- Flutter Web `client/build/web` 总大小：42,674,971 bytes。
- Web 关键文件：
  - `main.dart.js`：2,772,640 bytes。
  - `flutter.js`：9,553 bytes。
  - `canvaskit.wasm`：构建包含多个 renderer 产物，最大约 7,229,467 bytes。
- Android arm64 release APK：`client/build/app/outputs/flutter-apk/app-release.apk`，18,224,714 bytes，Flutter analyze 输出约 17.4 MB。

## 未测试项及原因

- Ubuntu Linux 未在本机实际启动；当前服务端依赖 Go 标准库和纯 Go SQLite 驱动 `modernc.org/sqlite`，代码路径已按 Windows/Ubuntu 迁移目标设计。
- 照片、FFmpeg 压缩、备份/checkpoint、短信读取均属于 Phase 2/3，未在本次闭环中实现或测试。
- 未执行专门的断网 UI 提交截图；当前客户端没有本地数据库或待同步队列，所有新增/编辑/删除直接调用在线 REST API，网络失败会显示“当前无网络，请联网后重试”。

## 发现并修复的问题

- `go run` 在 Windows 下停止父进程后可能留下临时 `ledger-server.exe` 子进程持有 SQLite 文件锁；测试改用 `dist\ledger-server.exe` 启动。
- `authenticate` 在单 SQLite 连接下读取 rows 时更新 `last_seen_at` 造成自锁；改为关闭 rows 后再更新。
- 删除最后一条交易时服务端空 slice 编码为 `null`，Flutter Web 报类型错误；服务端返回空数组，客户端也兼容 `null`。
- 视觉检查发现默认色彩过于单一；改为中性背景、白色卡片，仅主操作和图表保留绿色。
