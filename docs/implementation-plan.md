# 可执行实施计划

## 总原则

- 每次只实现一个最小可测切片。
- 每个切片先更新对应设计文档，再实现，再执行本机闭环测试。
- 本机服务端固定作为中心服务器，Web 使用 Flutter Web，Android 使用 `Pixel_9_Pro` 模拟器。
- Web 支持手动新增交易，不支持短信扫描。
- 同等功能下优先体积小、启动快、打开快，不做与功能无关的视觉设计。

## Phase 0：工程骨架与闭环环境

目标：让服务端、Flutter Web、Flutter Android 都能在本机跑通空壳。

实现：

- 创建 Go 服务端目录、`config.dev.json`、健康检查 API、SQLite 初始化。
- 创建 Flutter 项目，启用 Android 和 Web。
- Go 服务端托管 Flutter Web release 产物。
- 写最小自动化脚本或命令记录，用于启动服务端、运行 Web、运行 Android。

验收：

- `go test ./...` 通过。
- `go run ./server/cmd/ledger-server --config ./config.dev.json` 启动。
- `GET http://127.0.0.1:8080/api/health` 成功。
- `flutter run -d chrome` 能打开空壳页。
- `flutter run -d emulator-5554` 能打开空壳页。

## Phase 1：在线记账核心

目标：完成设备配对、基础数据、交易 CRUD、统计 API 和 Web/Android 共享 UI。

切片顺序：

1. SQLite schema 与迁移。
2. 设备配对 API。
3. Flutter 配对页和 token 保存。
4. Bootstrap API 与基础数据种子。
5. 交易新增 API。
6. Flutter 交易表单新增。
7. 交易列表和过滤。
8. 交易编辑。
9. 交易软删除。
10. 统计 API。
11. Flutter 自绘饼图和折线图。

每个交易切片都要验证：

- 服务端 API。
- Flutter Web 真实读写。
- Android 模拟器真实读写。
- `amount_cent INTEGER` 写入正确。
- 无网络时不产生本地待同步队列。
- 统计接口只聚合未软删除交易，客户端图表数据来自服务端。

## Phase 2：照片、公网安全与迁移

目标：完成照片上传压缩、备份和 checkpoint。

切片顺序：

1. 附件上传 API。
2. FFmpeg JPG 压缩和缩略图。
3. Web/Android 照片上传与查看。
4. Admin checkpoint API。
5. Admin backup API。
6. Windows 与 Ubuntu Linux 恢复流程文档化；本机先做备份包完整性和相对路径恢复检查，具备 Ubuntu 环境时补真实跨系统恢复。

每个切片都要记录构建体积；照片切片还要记录 FFmpeg 命令、输出文件大小和 CPU 风险。备份切片必须避免和附件压缩并发复制同一存储目录。

## Phase 3：Android 短信导入

目标：Android 私有安装包支持短信扫描与用户确认导入，Web 无短信入口。

切片顺序：

1. Flutter `SmsPlatformAdapter` 和 Web unsupported adapter。
2. Android 权限申请。
3. Android 历史短信手动扫描。
4. Android 在线短信广播监听，候选只保存在进程内队列。
5. 本地短信解析和分类猜测。
6. 候选确认 UI。
7. `POST /api/sms/imports` 和去重。
8. 断网不处理、联网后手动重扫验收；申请权限后不得自动扫描历史短信。

安全验收：

- 请求体不包含短信原文。
- 服务端日志不包含短信原文。
- `sms_hash` 去重生效。
- Web 构建不展示短信路由和入口。

## 发布前检查

- `docs/TODO.md` 对应任务状态已更新。
- `external/current/manifest-current.json` 包含本阶段使用过的网络资料。
- Go、Flutter Web、Flutter Android release 构建成功。
- Web 和 Android 闭环测试记录完整。
- 备份包包含 manifest，恢复流程不依赖平台绝对路径。
