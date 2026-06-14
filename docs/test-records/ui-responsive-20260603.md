# Responsive Web UI Test Record

测试日期：2026-06-04（Asia/Shanghai）

## 功能切片

- Flutter Web/Android 响应式 UI 改造：桌面 Web 使用侧边导航和居中限宽内容区；Android 与窄屏 Web 保留移动底部导航。
- 不新增第三方依赖；不修改服务端 API、数据库 schema 或公开模型。
- 测试目录：`var/test-runs/ui-responsive-20260603/`
- 截图与归档产物：`docs/test-records/artifacts/ui-responsive-20260603/`

## 本机服务端

- 启动命令：

```powershell
.\var\test-runs\ui-responsive-20260603\ledger-server.exe --config .\var\test-runs\ui-responsive-20260603\config.json
```

- Web/API 地址：`http://127.0.0.1:18081`
- Android Emulator 地址：`http://10.0.2.2:18081`
- `/api/health`：`status=ok`，`journal_mode=wal`
- 隔离数据库：`var/test-runs/ui-responsive-20260603/data/app.db`

## 自动化与 API 验证

通过：

```powershell
go test ./...
flutter analyze
flutter test
flutter build web --release
go build -trimpath -ldflags="-s -w" -o .\var\test-runs\ui-responsive-20260603\ledger-server.exe .\server\cmd\ledger-server
flutter build apk --debug --dart-define=LEDGER_API_BASE=http://10.0.2.2:18081
.\var\test-runs\ui-responsive-20260603\api-test.ps1
```

结果：`API_FULL_FUNCTIONAL_PASS`

覆盖范围：

- 配对/auth、401/403 边界、token hash 存储、交易 CRUD/filter/soft delete、统计、附件 FFmpeg 压缩、checkpoint/backup、SMS import API 结构化数据边界均通过。
- 服务端输出文件未命中 token、配对码、短信原文或 bearer token。
- Android crash buffer 为空；未出现 `ACCESS_NETWORK_STATE`、`SecurityException`、`SmsReceiver` 相关崩溃。

构建提示：

- Flutter Web release 构建通过；保留 Flutter 字体/wasm dry-run 警告。
- Android debug APK 构建通过；保留既有 `image_picker_android` Kotlin Gradle Plugin 未来兼容警告。

## Web 测试结果

- 桌面 Web：
  - `1600x900` viewport 下显示左侧 `NavigationRail`，主内容区随宽度扩展到约 1160px 并居中。
  - 交易筛选区在宽屏下 4 列、常规桌面宽度下 2 列，列表卡片不再拉满整屏。
  - 统计页在宽屏下“分类占比 / 时间趋势”并排显示。
- 窄屏 Web：
  - `390x844` viewport 保留底部导航。
  - `documentElement.scrollWidth=390`、`innerWidth=390`，未发现横向溢出。
  - 底部导航只有“交易 / 统计 / 设置”，未展示“短信”入口。
- Web UI 闭环：
  - 完成新增交易、关键词筛选、编辑金额和交易对象、软删除。
  - SQLite 校验 Web UI 删除为软删除，`amount_cent` 仍为 `integer`。
  - API 上传附件后，Web 编辑页可显示认证缩略图。
- 测试注意：
  - Playwright 旧 tab 曾命中 Flutter Web 旧 service worker/cache；本轮清理缓存并使用新 tab 后加载到当前构建。
  - Flutter Web 文件 picker 未做直接自动化驱动；附件链路由 API 上传 + Web 缩略图展示覆盖。

截图：

- `web-desktop-transactions.png`
- `web-wide-stats-loaded.png`
- `web-mobile-transactions.png`
- `web-mobile-attachment-edit.png`

## Android 模拟器测试结果

设备：

- AVD：`Pixel_9_Pro`
- adb serial：`emulator-5554`
- 分辨率/密度：`1280x2856`，`480 dpi`

已验证：

- 安装 debug APK、清空应用数据后，通过 Android UI 完成配对。原预生成 UI 配对码过期后，本轮在隔离 SQLite 内生成新的短效一次性配对码；最终仍通过真实 Android UI 与 `/api/pair/confirm` 完成。
- Android 主界面保留移动底部导航，并显示“交易 / 统计 / 短信 / 设置”四项。
- Android UI 完成手动新增、关键词筛选、编辑金额、软删除。
- SQLite 校验 Android UI 交易 `amount_cent` 为 `integer`，删除为软删除。
- Android 新增/编辑页显示“拍照 / 相册”入口；未执行系统 picker 选图，服务端压缩链路由 API/Web 覆盖。
- Android 统计页显示“分类占比 / 时间趋势”，图表在移动视口下无明显遮挡。
- 短信页：
  - 未授权时显示“短信权限”，重新扫描不可用，空状态正常。
  - 授权后不会自动扫描历史短信，重新扫描变为可用。
  - 在线模拟短信广播生成候选；确认导入后 SQLite 最新短信交易为 `source='sms'`、`amount_cent=1234`、`typeof(amount_cent)='integer'`。
  - 关闭数据网络时发送合成短信，页面未出现新广播候选；恢复网络后点击“重新扫描”，该短信作为历史扫描候选出现在首屏。
  - crash buffer 未出现 SMS receiver 或网络权限异常。

截图：

- `android-after-pair-2.png`
- `android-add-form.png`
- `android-after-add.png`
- `android-after-edit.png`
- `android-after-delete.png`
- `android-stats.png`
- `android-sms-start.png`
- `android-sms-permission-dialog.png`
- `android-sms-broadcast-candidate.png`
- `android-sms-confirm-form.png`
- `android-sms-after-import.png`
- `android-sms-offline-no-candidate.png`
- `android-sms-rescan-dataoff-candidate.png`

## UI 评估

- Web 桌面：侧边导航减少了底部导航在 PC 上的移动端感；内容区居中限宽后，表单和列表扫描距离明显缩短。
- Web 宽屏：统计页可以横向并排，避免大屏下大量空白堆叠。
- Web/Android 窄屏：表单保持单列，按钮和输入框没有横向压缩；底部导航仍符合移动操作习惯。
- 视觉风格：只使用 Material 组件、已有图标和少量布局封装，没有引入字体、图片、动画或 UI kit。

## 未测试项及原因

- Android 系统相册/拍照自动化选图未执行：系统 picker 自动化稳定性差；本轮已验证入口，压缩和缩略图链路由 API/Web 覆盖。
- Ubuntu 真实恢复演练未执行：本机未提供 Ubuntu/WSL 目标环境；本轮沿用 API 脚本的 zip manifest、相对路径和 SQLite integrity 检查。
- Flutter Web service worker 缓存升级路径未作为产品问题修复：本轮仅记录测试时旧 tab 缓存现象，实际发布策略是否需要调整需单独切片评估。

## 体积记录

- Flutter Web `main.dart.js`：2,911,493 bytes。
  - 相比 `full-functional-20260603` 的 2,899,348 bytes 增加 12,145 bytes，约 0.42%。
- Android debug APK：176,898,037 bytes。
  - 相比 `full-functional-20260603` 的 176,896,183 bytes 增加 1,854 bytes，约 0.001%。
- 未新增第三方依赖，体积增长来自响应式布局代码和 Flutter release 输出差异。
