# 设置页设备名与日志查询测试记录

## 功能切片

- 设置页支持修改当前设备名。
- 设置页支持 admin 设备查询最近审计日志摘要。
- 日志摘要只展示时间、实体、动作、设备名和实体短 ID；单条日志可展开查看完整日志 ID、实体 ID、设备 ID、原始动作和原始实体类型；接口不返回 `payload_json`。

## 本机服务端

Web 闭环使用干净临时配置：

```powershell
go run .\server\cmd\ledger-server --config .\var\test-runs\settings-device-log-20260606\config.web.json
```

访问地址：

```text
http://127.0.0.1:18081
```

健康检查结果：

```json
{"database":"ok","journal_mode":"wal","status":"ok"}
```

## Web 测试结果

- 已执行 `flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18081`。
- Web 首台设备通过服务端控制台配对码完成配对，并显示为 `web · 管理员`。
- 设置页点击编辑按钮后，设备名从 `Web日志Admin` 修改为 `Web日志已改名`。
- 修改后设置页刷新显示新设备名，并显示“设备名已保存”。
- admin 日志查询返回最近审计摘要，页面显示 `设备 · 改名`，设备名为 `Web日志已改名`；单条日志可展开查看完整字段，未显示 token、配对码、短信原文或 payload。
- Web 左侧导航只有 `交易 / 统计 / 设置`，未显示短信入口。

截图：

```text
docs/test-records/artifacts/settings-device-log-20260606/web-settings-logs.png
docs/test-records/artifacts/settings-device-log-20260606/web-log-collapse-expanded-fixed.png
docs/test-records/artifacts/settings-device-log-20260606/web-log-collapse-expanded-bottom.png
```

## 日志详情折叠复测

- 已执行 `flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18081`，并清理浏览器 Service Worker/cache 后重新进入 Web。
- 设置页查询最近日志后，日志默认仍为摘要行。
- 点击日志摘要后可展开详情，显示 `时间`、`实体`、`动作`、`实体ID`、`设备名`、`设备ID`、`日志ID`。
- 展开详情不显示 `payload_json`、token、配对码或短信原文。
- 初版展开详情用 `SelectableText` 在 Web 截图中出现灰块，已改为普通可换行文本并复测通过。

## Android 实机测试结果

- 已执行 `adb devices`，结果为空，没有 Android 实机在线。
- 已执行 `flutter devices`，只发现 Windows、Chrome、Edge，没有 Android 设备。
- 已启动用于 Android 真机访问的 LAN 服务：

```powershell
go run .\server\cmd\ledger-server --config .\var\test-runs\settings-device-log-20260606\config.android-lan.json
```

- LAN 服务监听：`0.0.0.0:18082`，健康检查 `http://127.0.0.1:18082/api/health` 返回 `status=ok`、`journal_mode=wal`。
- 已执行 Android 编译：

```powershell
flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://192.168.10.4:18082
```

- APK 已在日志详情折叠改动后重新构建成功：`client/build/app/outputs/flutter-apk/app-debug.apk`。
- 未能执行实机安装、配对、设置页改名和日志查询操作，原因是本机没有连接可用 Android 实机。

## 自动化与静态检查

```powershell
go test ./...
flutter analyze
flutter test
```

结果均通过。

## 未测试项及原因

- Android 实机设置页改名与日志查询：`adb devices` 无设备在线。
- Android 实机短信入口仍存在：无设备在线，无法安装启动验证。

## 发现并处理的问题

- 首次使用已有 `config.visual-test.json` 时，数据库已有 admin 设备，新配对 Web 设备不是 admin，日志查询区按设计不显示。改用 `18081` 干净临时数据库后完成 admin Web 闭环。
