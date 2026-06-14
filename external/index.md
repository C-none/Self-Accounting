# External Reference Index

## 当前主路线

本项目主路线固定为：

- 客户端：Flutter 单代码库，覆盖 Android 和 Web。
- 服务端：Go 单二进制。
- 数据库：SQLite。
- 图片压缩：服务端 FFmpeg。
- 测试：本机 Go 服务端 + Flutter Web + Android Emulator。

所有当前会用于实现和验证的网络资料已下载到 [current/](current/)，机器可读清单为 [current/manifest-current.json](current/manifest-current.json)。

抓取时间：`2026-06-01`。

## 当前资料：Flutter

| 本地文件 | 用途 | 来源 |
| --- | --- | --- |
| [app_architecture.html](current/flutter/app_architecture.html) | Flutter 分层和共享客户端架构 | [source](https://docs.flutter.dev/app-architecture/guide) |
| [web_building.html](current/flutter/web_building.html) | Flutter Web release、WASM 构建选择 | [source](https://docs.flutter.dev/platform-integration/web/building) |
| [web_deployment.html](current/flutter/web_deployment.html) | Flutter Web 部署和 base href | [source](https://docs.flutter.dev/deployment/web) |
| [android_deployment.html](current/flutter/android_deployment.html) | Android release 构建 | [source](https://docs.flutter.dev/deployment/android) |
| [app_size.html](current/flutter/app_size.html) | `--analyze-size` 和包体积分析 | [source](https://docs.flutter.dev/perf/app-size) |
| [performance_best_practices.html](current/flutter/performance_best_practices.html) | Flutter 性能实践 | [source](https://docs.flutter.dev/perf/best-practices) |
| [platform_channels.html](current/flutter/platform_channels.html) | Android 短信 platform channel | [source](https://docs.flutter.dev/platform-integration/platform-channels) |
| [integration_tests.html](current/flutter/integration_tests.html) | Flutter 集成测试 | [source](https://docs.flutter.dev/testing/integration-tests) |

## 当前资料：Go 与 SQLite

| 本地文件 | 用途 | 来源 |
| --- | --- | --- |
| [net_http.html](current/backend/go/net_http.html) | Go HTTP API 和静态资源托管 | [source](https://pkg.go.dev/net/http) |
| [embed.html](current/backend/go/embed.html) | 内嵌 Flutter Web 静态资源 | [source](https://pkg.go.dev/embed) |
| [cmd_go.html](current/backend/go/cmd_go.html) | Go 构建和交叉编译 | [source](https://pkg.go.dev/cmd/go) |
| [database_sql.html](current/backend/go/database_sql.html) | Go 数据库访问抽象 | [source](https://pkg.go.dev/database/sql) |
| [wal.html](current/backend/sqlite/wal.html) | SQLite WAL 与 checkpoint | [source](https://www.sqlite.org/wal.html) |
| [backup.html](current/backend/sqlite/backup.html) | SQLite 一致性备份 | [source](https://www.sqlite.org/backup.html) |
| [transactions.html](current/backend/sqlite/transactions.html) | SQLite 事务边界 | [source](https://www.sqlite.org/lang_transaction.html) |
| [pragma.html](current/backend/sqlite/pragma.html) | SQLite PRAGMA 配置 | [source](https://www.sqlite.org/pragma.html) |

## 当前资料：Android SMS

| 本地文件 | 用途 | 来源 |
| --- | --- | --- |
| [sms_intents.html](current/android/sms_intents.html) | 新短信广播 | [source](https://developer.android.com/reference/android/provider/Telephony.Sms.Intents) |
| [sms_inbox.html](current/android/sms_inbox.html) | 历史短信扫描字段参考 | [source](https://developer.android.com/reference/android/provider/Telephony.Sms.Inbox) |
| [manifest_permission.html](current/android/manifest_permission.html) | `READ_SMS` / `RECEIVE_SMS` 权限 | [source](https://developer.android.com/reference/android/Manifest.permission) |
| [default_handlers.html](current/android/default_handlers.html) | Android 敏感权限和默认处理器说明 | [source](https://developer.android.com/guide/topics/permissions/default-handlers) |
| [play_sms_policy.html](current/android/play_sms_policy.html) | Google Play SMS 政策；本项目私有 APK，不上架 Play | [source](https://support.google.com/googleplay/android-developer/answer/10208820?hl=en) |

## 当前资料：媒体与测试

| 本地文件 | 用途 | 来源 |
| --- | --- | --- |
| [ffmpeg.html](current/media/ffmpeg.html) | FFmpeg CLI 压缩图片 | [source](https://ffmpeg.org/ffmpeg.html) |
| [ffmpeg_filters.html](current/media/ffmpeg_filters.html) | FFmpeg scale filter | [source](https://ffmpeg.org/ffmpeg-filters.html) |
| [playwright_intro.html](current/testing/playwright_intro.html) | Web 闭环测试 | [source](https://playwright.dev/docs/intro) |
| [playwright_test_assertions.html](current/testing/playwright_test_assertions.html) | Web 测试断言 | [source](https://playwright.dev/docs/test-assertions) |
