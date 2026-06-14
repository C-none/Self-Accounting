# 系统总体架构

## 目标与边界

本系统是面向少于 5 人家庭使用的记账系统。中心服务器只有小型 CPU，需要能在 Windows 与 Ubuntu Linux 之间迁移服务和数据。客户端固定采用 Flutter 单代码库，覆盖 Android App 与 Web，两端尽量复用 UI、状态管理、领域模型和 API 客户端。

新的需求基线：

- Android 和 Web 都支持新增交易、编辑交易、列表过滤、统计查看。
- 只有 Android 支持短信扫描和短信交易导入。
- Web 不支持短信扫描。
- 系统不支持离线新增或离线编辑；写操作必须联网。
- 断网时 Android 收到消费短信不做任何动作，用户恢复网络后手动触发短信重新扫描。
- Android 私有安装包分发，不上架 Google Play。
- 测试阶段局域网访问，实用阶段使用公网服务器。
- 生产公网访问使用 HTTPS + 一次性配对码 + 设备 token，不设计密码登录。
- 交易金额使用整数分存储：`amount_cent = RMB * 100`。
- 照片由服务端调用 FFmpeg 适度压缩为 JPG 后保存，默认保留票据和文字细节。
- 在功能等价的前提下，优先减小 Android 包体积、Flutter Web 首屏下载体积、服务端二进制体积，并优先提升 App 启动速度和网页打开速度；不实现纯装饰性图片、动效、复杂视觉效果或会降低性能的 UI。

详细性能与体积约束见 [performance-size-budget.md](performance-size-budget.md)。

## 架构拓扑

```text
Flutter Android App                 Flutter Web App
  SMS scan adapter                     no SMS feature
  camera/file picker                   browser file picker
  shared UI/domain/state/API           shared UI/domain/state/API
          |                                      |
          | HTTPS REST + multipart upload        |
          v                                      v
  ----------------------------------------------------------------
  Go Ledger Server
    net/http REST API
    device pairing + token auth
    transaction/statistics APIs
    SMS import endpoint
    FFmpeg photo compression worker
    backup/checkpoint APIs
    embedded Flutter Web static assets
          |
          v
  SQLite app.db + photos/ + thumbnails/ + backups/
  ----------------------------------------------------------------
```

## 组件职责

### Flutter Client

Flutter 客户端是唯一前端技术栈。Android 和 Web 共用以下层：

- 领域模型：交易、分类、成员、账户、附件、统计结果。
- API client：配对、交易、附件、统计、备份入口。
- UI 组件：交易表单、交易列表、过滤器、详情页、统计图表。
- 状态管理：当前设备、当前用户、筛选条件、提交状态、错误状态。

平台差异通过 adapter 隔离：

- Android：短信权限、后台监听、历史短信扫描、摄像头、通知。
- Web：无短信模块，仅提供文件选择和普通表单能力。

客户端依赖准入原则：

- 不引入大型 UI 套件、动画库、状态管理框架组合或图表库，除非当前功能无法用 Flutter SDK 与少量自定义绘制完成。
- 统计饼图和折线图首版使用 `CustomPainter` 或轻量自绘组件，避免为两个简单图表引入重型图表依赖。
- Android 短信能力优先通过 Flutter platform channel 接入原生 Android API，避免引入功能不可控的短信插件。
- Web 和 Android 共用功能必须懒加载业务数据；启动阶段只做配置读取、认证状态判断和必要的 bootstrap。

### Go Ledger Server

服务端是单进程 Go 程序，承担：

- REST API。
- Flutter Web 静态产物托管。
- SQLite 读写。
- 设备配对与 token 校验。
- 照片压缩和附件文件管理。
- 备份、恢复辅助和 SQLite checkpoint。

服务端不依赖 Docker、Nginx、PostgreSQL、Redis 作为必需组件。公网生产环境可以在外层接入反向代理或云厂商 HTTPS，但应用自身仍按 HTTPS 入口设计。

服务端以 Go 标准库为主：

- HTTP 使用 `net/http`。
- 配置默认使用 `config.json`，由 Go 标准库解析，避免为 TOML/YAML 引入依赖。
- token 与配对码 hash 使用标准库 `crypto/hmac`、`crypto/sha256` 和常量时间比较。
- ID 使用 `crypto/rand` 生成，不引入 UUID 依赖。
- SQLite 驱动允许使用 `modernc.org/sqlite`，理由是纯 Go、便于 Windows 与 Ubuntu Linux 交叉构建；这是首版服务端唯一默认第三方后端库。

### SQLite Storage

SQLite 是中心数据源。写入量很小，适合家庭场景。数据库运行时使用 WAL 以提升读写并发，但迁移和备份必须通过 checkpoint 或一致性备份流程完成，不能只复制 `app.db`。

## 运行模式

### 测试阶段：局域网

- 服务端绑定局域网地址或 `0.0.0.0`。
- Android 和 Web 使用 `http://LAN_IP:PORT` 或本地 HTTPS 测试地址。
- 可以使用临时自签证书，但正式生产必须使用可信 HTTPS。

### 实用阶段：公网服务器

- 服务端部署到公网服务器，必须启用 HTTPS。
- 客户端首次使用一次性配对码换设备 token。
- 后续请求使用 `Authorization: Bearer <device_token>`。
- 不提供账号密码登录。

## 功能矩阵

| 功能 | Android Flutter | Flutter Web |
| --- | --- | --- |
| 设备配对 | 支持 | 支持 |
| 新增交易 | 支持 | 支持 |
| 编辑交易 | 支持 | 支持 |
| 删除交易 | 支持软删除 | 支持软删除 |
| 列表过滤 | 支持 | 支持 |
| 饼图/折线图统计 | 支持 | 支持 |
| 拍照/上传照片 | 支持 | 支持文件选择上传 |
| 短信后台监听 | 支持 | 不支持 |
| 手动扫描历史短信 | 支持 | 不支持 |
| 离线编辑 | 不支持 | 不支持 |

## 关键约束

- 金额严禁使用浮点数持久化，统一使用 `amount_cent INTEGER`。
- 照片压缩职责在服务端，Flutter 不承担最终压缩标准。
- 最后写入胜出，不做复杂冲突合并。
- 删除使用软删除，保留审计和恢复空间。
- 迁移备份必须同时覆盖 Windows 与 Ubuntu Linux。
- 每个最小功能切片完成后都必须执行本机闭环测试。测试流程见 [local-closed-loop-testing.md](local-closed-loop-testing.md)。
