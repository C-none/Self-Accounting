# SMS Hash Dedup Android Test - 2026-06-06

功能切片：短信导入去重 hash 更新。

服务端启动方式：

```powershell
go build -o .\var\visual-audit\ledger-server-android-test.exe .\server\cmd\ledger-server
.\var\visual-audit\ledger-server-android-test.exe --config .\config.visual-test.json
```

服务端访问地址：

- Host: `http://127.0.0.1:18080`
- Android emulator: `http://10.0.2.2:18080`

Web 测试结果：

- 本轮未执行 Web UI 闭环；该切片只影响 Android 短信导入。
- 服务端单元测试 `go test ./server/internal/ledger` 通过。
- Flutter 单元测试 `cd client && flutter test` 通过。

Android 模拟器测试结果：

- AVD: `Pixel_9_Pro`, serial `emulator-5554`。
- APK 构建命令：`flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080`。
- Android 配对成功，底部导航显示“交易 / 统计 / 短信 / 设置”。
- 短信页未授权时“短信权限”可用，“重新扫描”禁用；授权后“短信权限”禁用，“重新扫描”可用。
- 在线模拟短信广播可生成候选，确认导入后 `transactions.source='sms'` 和 `sms_imports` 均新增 1 条。
- 新导入记录写入 `sms_received_at_ms`，SQLite 显示该字段为正整数。
- 广播导入后手动重新扫描同一条短信，再次确认导入时服务端返回 `409 duplicate_sms_import`，客户端按成功处理并移除候选。
- 最终 SQLite 计数保持不变，未新增第二条重复交易。
- `adb logcat -b crash` 未发现 crash 输出。

发现并修复的问题：

- 初版 hash 使用毫秒级时间，广播路径和 inbox 扫描路径的同一短信时间戳存在数百毫秒差异，导致重复导入。
- 第一次修正为向下取整秒仍会在秒边界附近失败。
- 最终修正为就近秒归一化参与 hash，仍保存精确 `sms_received_at_ms` 用于审计。

未测试项及原因：

- 未执行断网短信路径；本轮目标是验证新 hash 去重和重复确认处理。
- 未执行照片、统计、交易 CRUD 全量 Android 闭环；这些路径未被本切片改动。
