# Android SMS Receiver Fix Test Record

测试日期：2026-06-03（Asia/Shanghai）

## 功能切片

- 修复 Android `SMS_RECEIVED` receiver 查询网络状态时缺少 `ACCESS_NETWORK_STATE` 导致的崩溃。
- 保持边界不变：Web 不展示短信入口；短信正文只在 Android 本地解析；断网时不进入后台候选队列。
- 测试目录：`var/test-runs/sms-receiver-fix-20260603/`
- 截图与归档产物：`docs/test-records/artifacts/sms-receiver-fix-20260603/`

## 本机服务端

启动命令：

```powershell
.\var\test-runs\sms-receiver-fix-20260603\ledger-server.exe --config .\var\test-runs\sms-receiver-fix-20260603\config.json
```

- Web/API 地址：`http://127.0.0.1:18081`
- Android Emulator 地址：`http://10.0.2.2:18081`
- `/api/health`：`status=ok`，`journal_mode=wal`
- 隔离数据库：`var/test-runs/sms-receiver-fix-20260603/data/app.db`

## 实现内容

- `client/android/app/src/main/AndroidManifest.xml` 增加 `android.permission.ACCESS_NETWORK_STATE`。
- `SmsBridge.isNetworkAvailable(...)` 捕获 `SecurityException` 并返回 `false`，无法确认在线时按断网处理。
- 同步更新短信模块、Flutter 架构和 TODO 文档。

## 自动化验证

通过：

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:18081
go test ./...
```

- debug merged manifest 已确认包含 `android.permission.ACCESS_NETWORK_STATE`。
- Android debug build 仍有既有 `image_picker_android` Kotlin Gradle Plugin 未来兼容警告，本切片不处理。

## Android 模拟器测试

设备：

- AVD：`Pixel_9_Pro`
- adb serial：`emulator-5554`

结果：

- 首次 AVD 启动进入 `offline`，通过重启 adb/emulator 并使用 `-no-window -no-snapshot-load -no-snapshot-save -gpu swiftshader_indirect` 后正常进入 `device`。
- Android UI 配对成功，底部导航显示“交易 / 统计 / 短信 / 设置”。
- 短信页未授权时“重新扫描”不可用；授权前发送的模拟短信在授权后没有自动变成候选。
- 在线广播短信进入候选列表，显示 `超市 ¥77.77`，crash buffer 为空。
- 点击候选并确认导入后，SQLite 校验：`source='sms'`、`typeof(amount_cent)='integer'`、`amount_cent=7777`。
- 飞行模式下 `mDefaultNetwork=null`，短信页保持“暂无候选短信”，crash buffer 为空。
- emulator 飞行模式会阻止 `adb emu sms send` 写入 inbox；为验证恢复后的手动重扫，在飞行模式下通过 SMS provider 写入一条合成 inbox 短信，页面仍不自动出现候选。
- 恢复网络后 `mDefaultNetwork=105`，点击“重新扫描”后出现 `地铁 ¥13.57` 候选。

归档：

- `android-sms-after-offline-rescan.png`
- `android-crash-final.log`（空文件，表示 crash buffer 无条目）

## Web 回归

- 通过 API 确认 Web 设备 `/api/bootstrap` 返回 `features.sms=false`。
- Flutter Web UI 配对成功后，Playwright accessibility snapshot 中底部导航只有“交易 / 统计 / 设置”，未出现“短信”。
- 截图：`web-after-pair-no-sms.png`
- 快照：`web-after-pair-no-sms-snapshot.md`

## 安全日志检查

- 服务端日志只包含方法、路径、状态码和耗时；未出现 token、配对码、短信正文或 sender。
- 测试产物已清理明文配对码和短信正文；provider probe 中的合成 sender 已脱敏。
- Android crash logs 未出现 `ACCESS_NETWORK_STATE`、`Unable to start receiver` 或 `ConnectivityService: Neither user`。

## 未覆盖项与剩余风险

- 未使用真实 Android 设备。
- emulator 飞行模式不会把 `adb emu sms send` 投递到 inbox；因此“断网期间真实 SMS 广播已送达但 receiver 跳过”的路径无法在该 AVD 上完整证明。本轮已覆盖：在线广播不崩溃并入队、无 active network 时不自动出现候选、恢复后手动重扫本地 inbox 可出现候选。
