# 本机闭环测试方案

## 当前本机环境

2026-06-01 已确认：

- Go：`go1.26.3 windows/amd64`
- Flutter：`3.44.0 stable`
- Dart：`3.12.0`
- SQLite CLI：`3.51.2`
- FFmpeg：`8.1.1`
- ADB：`37.0.0`
- Chrome：可用于 Flutter Web
- Android AVD：`Pixel_9_Pro`

注意：

- 当前目录不是 Git 仓库，无法用 `git status` 追踪改动。
- `emulator` 未直接加入 PATH，可用绝对路径启动：

```powershell
C:\Users\huzhi\scoop\apps\android-clt\current\emulator\emulator.exe -avd Pixel_9_Pro
```

## 每个功能切片的固定流程

1. 更新对应 `docs/` 设计或 TODO。
2. 实现一个最小可测功能切片。
3. 启动本机 Go 服务端。
4. 执行服务端 API 测试。
5. 执行 Flutter Web 闭环测试。
6. 如涉及客户端关键功能或平台差异，执行 Android 模拟器测试。
7. 如涉及照片，验证 FFmpeg 压缩结果和文件可访问。
8. 如涉及备份，验证 checkpoint 和备份包 manifest。
9. 记录测试结果、未测项和原因。

禁止在一个未通过闭环的切片上继续叠加新功能。

## 本机服务端

默认地址：

```text
http://127.0.0.1:8080
```

Android 模拟器访问同一服务：

```text
http://10.0.2.2:8080
```

启动命令形态：

```powershell
go run ./server/cmd/ledger-server --config ./config.dev.json
```

服务端基础验收：

- `/api/health` 返回 OK。
- SQLite 数据库创建在 `./var/dev/data/app.db`。
- `PRAGMA journal_mode` 为 WAL。
- FFmpeg 启动检查通过。
- 常规请求日志和测试记录不包含 token、配对码、短信原文；用户主动请求生成配对码时，服务端控制台会临时输出配对码用于完成配对。

## Web 闭环

开发期可用：

```powershell
flutter run -d chrome --dart-define=LEDGER_API_BASE=http://127.0.0.1:8080
```

发布构建闭环必须验证 Go 托管的 Flutter Web：

```powershell
flutter build web --release --analyze-size
go run ./server/cmd/ledger-server --config ./config.dev.json
```

Web 验收路径：

- 输入配对码完成配对或使用已有 token。
- 新增交易。
- 列表读取与过滤。
- 编辑交易。
- 软删除交易。
- 上传照片并查看服务端压缩 JPG。
- 查看分类饼图和时间折线图。
- 页面不展示短信扫描入口。
- 首屏不加载非必要装饰资源。

## Android 模拟器闭环

启动模拟器：

```powershell
C:\Users\huzhi\scoop\apps\android-clt\current\emulator\emulator.exe -avd Pixel_9_Pro
adb devices
```

运行 App：

```powershell
flutter run -d emulator-5554 --dart-define=LEDGER_API_BASE=http://10.0.2.2:8080
```

Android 基础验收路径：

- 输入配对码完成配对或使用已有 token。
- 新增交易。
- 列表读取与过滤。
- 编辑交易。
- 软删除交易。
- 上传照片并查看服务端压缩 JPG。
- 查看分类饼图和时间折线图。
- Android 专属短信入口存在。

短信切片额外验收：

- 权限申请流程可见。
- 模拟短信或历史短信扫描能产生候选。
- 断网时收到短信不解析、不入队、不弹候选。
- 联网后用户手动触发重新扫描。
- 提交服务端的请求体不包含短信原文。

## 测试记录模板

每个切片完成后记录：

```text
功能切片：
服务端启动命令：
服务端访问地址：
Web 测试结果：
Android 模拟器测试结果：
性能/体积记录：
未测试项及原因：
发现并修复的问题：
```

## 已完成记录

- Phase 0/1 闭环记录：[`../test-records/phase0-phase1.md`](../test-records/phase0-phase1.md)。
