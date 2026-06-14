# 配对码 console-only 生成闭环记录

日期：2026-06-06

## 功能切片

- 未配对设备调用 `POST /api/pair/start` 时，HTTP 响应不再返回 `pairing_code`。
- 未配对设备只能通过“请求生成配对码”按钮触发服务端命令行打印配对码。
- 如果当前服务端进程内已有未过期、未使用的配对码，重复请求会重新打印同一个配对码。
- 已配对设备可在设置页生成新设备配对码，HTTP 响应返回明文配对码。
- SQLite 仍只保存配对码 hash，不保存明文配对码。

## 本机服务端

- 启动方式：`go run ./server/cmd/ledger-server --config ./config.visual-test.json`
- Web 访问地址：`http://127.0.0.1:18080`
- Android 访问地址：`http://10.0.2.2:18080`
- 状态：已启动并保留运行。

## API 验证

- 未携带 token 调用 `POST /api/pair/start`：
  - 返回 `delivery=server_console`。
  - 返回 `expires_at`。
  - 不返回 `pairing_code`。
- 未携带 token 重复调用 `POST /api/pair/start`：
  - HTTP 仍不返回 `pairing_code`。
  - 服务端重新输出当前有效配对码。
- 携带已配对设备 token 调用 `POST /api/pair/start`：
  - 返回 `pairing_code`。
  - 返回 `delivery=response`。
- 使用已配对设备生成的配对码调用 `POST /api/pair/confirm`：
  - 返回新设备 token。
  - 配对码使用后作废。

## Web 测试结果

- Web release 已构建并由本机服务端提供访问。
- 清除 Web 本地 token 后进入未配对页。
- 未配对页显示新文案：未配对设备不能在页面直接获得配对码，只能请求服务端在命令行打印。
- 点击“请求生成配对码”后，页面只显示服务端命令行打印提示，不显示明文配对码。
- Web 已保留打开在未配对请求结果页。
- 截图：
  - `docs/test-records/artifacts/pairing-console-20260606/web-pairing-page.png`
  - `docs/test-records/artifacts/pairing-console-20260606/web-pairing-requested.png`

## Android 模拟器测试结果

- 模拟器：`emulator-5554`。
- APK：`client/build/app/outputs/flutter-apk/app-debug.apk`。
- 已安装当前 APK。
- 已清空应用数据，确保 Android 处于第一次尝试配对的未配对状态。
- 未配对页显示新文案和“请求生成配对码”按钮。
- 点击按钮后，页面只显示服务端命令行打印提示，不显示明文配对码。
- Android 模拟器和 App 已保留运行，当前停在未配对请求结果页。
- 截图：
  - `docs/test-records/artifacts/pairing-console-20260606/android-pairing-page.png`
  - `docs/test-records/artifacts/pairing-console-20260606/android-pairing-requested.png`

## 构建与自动化验证

- `go test ./...` 通过。
- `flutter analyze` 通过。
- `flutter test` 通过。
- `flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18080` 通过。
- `flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080` 通过。

## 数据与安全检查

- 测试记录不包含配对码、设备 token 或 bearer token。
- 数据库仍只保存配对码 hash。
- 常规请求日志仍只记录方法、路径、状态码和耗时。
- 用户主动请求生成配对码时，服务端控制台输出配对码；这是本次需求明确要求的例外。

## 未测试项及原因

- 没有在 UI 截图中展示已配对设备设置页返回的明文配对码，避免测试产物持久化配对码；该路径已通过 API 验证。

## 发现并修复的问题

- 原逻辑允许首台设备在本机 Web 页面直接拿到配对码，已改为 console-only。
- 原客户端配对页按钮文案会暗示直接生成配对码，已改为“请求生成配对码”。
- 原测试假设非 admin 设备不能生成配对码，已按新需求改为已配对设备均可在账户内部生成。
