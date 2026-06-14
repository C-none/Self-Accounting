# 性能与体积预算

## 优先级

在功能等价的前提下，优先级固定为：

1. 数据正确、安全边界和迁移可靠。
2. App 启动速度、网页打开速度和小 CPU 服务器响应速度。
3. Android 包体积、Flutter Web 下载体积、服务端二进制体积。
4. UI 可用性和信息密度。

不为了视觉美观引入装饰资源、复杂动效、重型图表库、字体包、背景图或营销页。

## 依赖准入

新增第三方依赖必须同时满足：

- 当前功能不用它会明显更复杂或不可验证。
- Android、Web、Windows、Ubuntu Linux 目标都不被破坏。
- 不显著增加启动时间、构建产物体积或小 CPU 压力。
- 在对应 `docs/` 文件和最终汇报中说明用途。

首版默认允许：

- Go 后端：`modernc.org/sqlite`，用于纯 Go SQLite 驱动。
- Flutter：必要平台插件按功能切片引入，图表和短信不默认引入插件。

首版默认禁止：

- 大型 UI 套件、动画库、图表库、图标包、自定义字体包。
- 客户端本地数据库和离线同步队列。
- 服务端 ORM、后台任务框架、外部缓存、消息队列。

## 构建产物记录

每个客户端或发布相关切片完成后记录：

```powershell
go build -trimpath -ldflags="-s -w" -o dist/ledger-server.exe ./server/cmd/ledger-server
flutter build web --release --analyze-size
flutter build apk --release --analyze-size
```

记录项：

- `ledger-server.exe` 大小。
- Flutter Web `build/web` 总大小、首屏关键文件大小。
- Android release APK 大小。
- 对比上一次同类切片是否增长超过 10%。

超过 10% 必须说明原因；如果增长来自非必要资源或依赖，必须回退或替换。

## 运行性能检查

每个闭环测试记录至少包含：

- 服务端启动耗时是否异常。
- `/api/health`、交易列表、交易新增、统计接口是否在本机小数据量下快速响应。
- Web 首屏是否能直接进入配对页或交易列表，不等待非首屏资源。
- Android 冷启动后是否能直接进入配对页或交易列表。
- 图片上传时 FFmpeg 只压缩当前任务，不并行打满 CPU。

## UI 约束

- 页面以表单、列表、过滤器、统计图为主，不设计 landing page。
- 不使用全屏背景图、插画、装饰渐变、复杂阴影和大面积动效。
- 图表只表达金额比例和时间趋势，不追求视觉特效。
- 列表和表单优先信息密度，避免卡片套卡片和大留白。
