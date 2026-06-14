# 基础资料、日期列表与 Android 构建修复验证记录

日期：2026-06-06

## 本次实现切片

- 基础资料管理入口：设置页进入“基础资料管理”。
- 基础资料 API：分类、使用人、账户支持新增、编辑、软删除。
- 交易列表：按日期分组，每天分界线可折叠当天交易。
- 日期过滤：默认结束日期今天、起始日期一周前；支持 `YYYYMMDD` 纯数字输入和日期选择器。
- 服务地址显示：服务端启动日志输出 Web/API URL，客户端设置页显示服务地址。
- Android 构建超时修复：外部 Flutter 插件不再被强制使用仓库内 `D:` 盘 build 目录。

## APK 构建超时根因

Gradle 日志中出现：

```text
this and base files have different roots:
D:\file\prog\accounting\client\build\flutter_plugin_android_lifecycle
C:\Users\huzhi\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_plugin_android_lifecycle-2.0.34\android
```

原因：`client/android/build.gradle.kts` 把所有 subprojects 的 build 目录强制重定向到仓库 `D:` 盘下；Flutter 插件项目来自 `C:` 盘 Pub Cache，Windows 下 Gradle/Kotlin 在创建部分插件任务时无法对不同盘符路径做相对路径计算。

修复：只对仓库内 Android 子项目重定向 build 目录；外部 Pub Cache 插件保持默认 build 目录。

## 已执行验证

- `go test ./server/internal/ledger`：通过。
- `flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18080`：通过。
- `flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080`：通过，Gradle 阶段 41.6 秒，产物为 `client/build/app/outputs/flutter-apk/app-debug.apk`。
- 最终门禁复跑：
  - `go test ./...`：通过。
  - `go test ./server/internal/ledger`：通过，cached。
  - `flutter analyze`：先发现 `client/test/widget_test.dart` 的 `LedgerAccount` 测试构造缺少新字段 `maskedIdentifier`；补默认空字符串后复跑通过。
  - `flutter test`：通过，4 个测试全部通过。
  - `flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18080`：通过，Web 编译 24.1 秒。
  - `flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080`：通过，Gradle 阶段 4.2 秒。
- 本机服务端：使用 `127.0.0.1:18080` 启动，日志输出 `ledger server listening on 127.0.0.1:18080` 和 `ledger web/API URL: http://127.0.0.1:18080`。
- 基础资料 API CRUD：分类、使用人、账户的新增、编辑、删除均通过本机 API 验证。
- 基础资料 API 引用保护：新建临时分类、使用人、账户和交易后，删除被交易引用的一级分类、二级分类、使用人、账户均返回 HTTP 400 `validation_error`。
- Web 基础资料页：设置页入口可打开，分类新增后可在页面显示。截图：`master-data-web-after-add.png`。
- Web 交易页：日期分界线显示 `2026-06-05`，点击折叠后当天交易项隐藏；`YYYYMMDD` 纯数字起始日期输入可正确过滤。截图：`transactions-date-filter-divider-web-fixed.png`。
- Web 服务地址：设置页显示 `http://127.0.0.1:18080`。截图：`settings-service-url-web.png`。
- Android APK：已安装到 `emulator-5554` 并启动 `com.example.ledger_client/.MainActivity`。
- Android 配对：使用本机服务端测试配对码完成设备配对，交易页可读取服务端交易。
- Android 设置页：显示服务地址 `http://10.0.2.2:18080`，显示“基础资料管理”入口，底部导航保留 Android 专属“短信”入口。
- Android 基础资料页：页面可打开，能看到分类区、一级分类新增按钮、二级分类新增按钮、编辑按钮、删除按钮。
- Android 一级分类 CRUD：关闭模拟器 Gboard 手写笔教学拦截后，在 Android UI 中新增 `androidcatok0606c`，编辑为 `androidcatok0606cx`，再确认删除；数据库对应分类 `deleted_at` 写入 `1780678906`，页面不再显示该活动分类。
- Android 一级分类 CRUD 截图：`docs/test-records/artifacts/master-data-date-build-20260606/android-master-add-after-stylus-disabled.png`、`docs/test-records/artifacts/master-data-date-build-20260606/android-master-edit-dialog-typed.png`、`docs/test-records/artifacts/master-data-date-build-20260606/android-master-after-delete.png`。
- Android 二级分类 CRUD：在 `交通` 父分类下新增 `androidl20606`，编辑为 `androidl20606x`，再确认删除；数据库显示父分类为 `交通`，对应二级分类 `deleted_at` 写入 `1780679937`，页面不再显示该活动二级分类。
- Android 二级分类 CRUD 截图：`docs/test-records/artifacts/master-data-date-build-20260606/android-l2-category-add-dialog-typed.png`、`docs/test-records/artifacts/master-data-date-build-20260606/android-l2-category-edit-dialog-typed.png`、`docs/test-records/artifacts/master-data-date-build-20260606/android-l2-category-after-delete.png`。
- Android 使用人 CRUD：在 Android UI 中新增 `androidmember0606b`，编辑为 `androidmemxber0606b`，再确认删除；数据库对应使用人 `deleted_at` 写入 `1780679184`，页面不再显示该活动使用人。
- Android 使用人 CRUD 截图：`docs/test-records/artifacts/master-data-date-build-20260606/android-member-add-dialog-typed-fixed.png`、`docs/test-records/artifacts/master-data-date-build-20260606/android-member-edit-dialog-typed.png`、`docs/test-records/artifacts/master-data-date-build-20260606/android-member-after-delete.png`。
- Android 账户 CRUD：在 Android UI 中新增 `androidaccount0606`，编辑为 `androidaccount06x06`，再确认删除；数据库对应账户 `deleted_at` 写入 `1780679419`，页面不再显示该活动账户。
- Android 账户 CRUD 截图：`docs/test-records/artifacts/master-data-date-build-20260606/android-account-add-dialog-typed.png`、`docs/test-records/artifacts/master-data-date-build-20260606/android-account-edit-dialog-typed.png`、`docs/test-records/artifacts/master-data-date-build-20260606/android-account-after-delete.png`。
- Android 交易页：显示日期分界线 `2026-06-05`、起始/结束日期输入框、日期选择按钮、按日折叠按钮和缩略图交易项；点击 `折叠2026-06-05` 后切换为 `展开2026-06-05`，当天交易项不再出现在 UI 树中。截图：`docs/test-records/artifacts/master-data-date-build-20260606/android-transaction-collapsed.png`。
- Android 自动化环境修正：模拟器 Gboard 弹出 `Try out your stylus` 教学浮层时会抢走 adb 输入；通过 `settings put secure stylus_handwriting_enabled 0`、`stylus_handwriting_available 0`、`handwriting_enabled 0` 后，`adb shell input text` 可正常输入 Flutter TextField。

## 未覆盖项

- 未使用真实 Android 设备；本轮目标为本机 Android Emulator 闭环，已使用 `emulator-5554` 覆盖。
- 未重新做 Ubuntu 真实恢复演练；本轮未修改备份/恢复实现，Windows/Ubuntu 兼容性沿用 `full-functional-20260603.md` 中的备份 manifest、相对路径和 SQLite integrity 检查记录。

## 覆盖审计结论

- 当前新增/修改功能已完成本机闭环：服务端 API、Flutter Web、Android Emulator 均已验证。
- “所有已有功能正常使用”的当前证据由三部分组成：
  - `full-functional-20260603.md`：覆盖交易 CRUD、筛选、统计、附件上传/FFmpeg、backup/checkpoint、短信手动扫描导入、安全边界。
  - `sms-receiver-fix-20260603.md`：覆盖 Android SMS receiver 崩溃修复、在线短信入队、断网不自动处理、恢复后手动重扫。
  - 本记录：覆盖当前代码最终门禁、基础资料管理、日期分组折叠、日期过滤、服务地址显示、APK 构建超时修复、Android 基础资料/交易/设置入口。

## 已知提示

- Android 构建仍提示 `image_picker_android` 使用 Kotlin Gradle Plugin；当前构建通过，后续 Flutter 版本可能要求插件升级到 Built-in Kotlin。
