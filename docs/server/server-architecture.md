# 服务端总体架构

## 技术路线

服务端采用 Go 单二进制：

- Go `net/http` 提供 REST API。
- SQLite 作为中心数据库。
- Flutter Web 生产产物由 Go 托管，当前首版以 `client/build/web` 作为随二进制发布的静态目录。
- FFmpeg 作为外部可执行依赖，用于照片压缩。

不引入 Docker、Nginx、PostgreSQL、Redis 作为必需组件。生产公网可使用外层反向代理或云平台 HTTPS，但应用部署本身不依赖它们。

默认依赖策略：

- 优先使用 Go 标准库，减少二进制体积、交叉构建复杂度和安全维护面。
- 配置文件使用 JSON：`config.json`，避免 TOML/YAML 解析依赖。
- token hash、配对码 hash、随机 ID、日志、zip 备份、静态资源托管均使用标准库完成。
- SQLite 驱动默认使用 `modernc.org/sqlite`，这是为跨 Windows/Ubuntu 构建接受的后端第三方依赖。
- 不引入 ORM；SQL 语句集中在 repository 层，避免反射和额外运行时开销。

## 进程职责

Go 服务端负责：

- 设备配对与 token 校验。
- 交易 CRUD。
- 短信导入结构化结果接收。
- 附件上传和 FFmpeg 压缩。
- 统计聚合。
- 备份和 checkpoint。
- 静态 Flutter Web 托管。

## 并发模型

家庭用户数小于 5，系统以简单可靠为主：

- HTTP 请求并发由 Go 标准库处理。
- SQLite 写事务保持短小。
- 附件压缩任务限制并发，默认一次只处理 1 个压缩任务，避免小 CPU 被 FFmpeg 打满。
- 备份任务与压缩任务互斥或限流。
- 后台任务不做常驻复杂调度。首版只保留附件压缩锁、备份锁和必要的启动检查。

## SQLite 配置

启动时执行：

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA synchronous = NORMAL;
```

如果用户更重视断电安全，可以在配置中切换 `synchronous = FULL`。

## 静态资源托管

生产构建时：

1. 构建 Flutter Web。
2. 首版将产物作为 `client/build/web` 随二进制发布；后续可再改为 `embed`。
3. Go 服务端托管 Web 入口。
4. 非 API 路由回退到 Flutter Web `index.html`。

API 路由统一以 `/api/` 开头，避免和前端路由冲突。

静态资源响应要求：

- Flutter Web 产物使用强缓存文件名资源，`index.html` 不长缓存。
- 服务端启用 gzip 预压缩或运行时 gzip 时，必须先测量 CPU 影响；小 CPU 上优先使用构建期预压缩文件。
- 不为 Web 首屏引入额外字体、图片背景、营销页或装饰资源。

## 配置与启动检查

启动时检查：

- 数据目录可读写。
- SQLite 可打开并迁移 schema。
- FFmpeg 可执行文件可用。
- HTTPS 配置在生产模式下有效。
- 备份目录可写。

本机开发默认配置：

```json
{
  "server": {
    "listen_addr": "127.0.0.1:8080",
    "public_base_url": "http://127.0.0.1:8080",
    "require_https": false,
    "web_dir": "./client/build/web"
  },
  "database": {
    "path": "./var/dev/data/app.db",
    "busy_timeout_ms": 5000,
    "synchronous": "NORMAL"
  },
  "storage": {
    "photos_dir": "./var/dev/data/photos",
    "thumbnails_dir": "./var/dev/data/thumbnails",
    "tmp_dir": "./var/dev/tmp"
  },
  "ffmpeg": {
    "path": "ffmpeg",
    "jpg_quality": 18,
    "max_width": 1600,
    "max_height": 1600
  },
  "backup": {
    "dir": "./var/dev/backups"
  },
  "security": {
    "secret_path": "./var/dev/server-secret.key"
  }
}
```

`security.secret_path` 保存服务端 HMAC secret。该文件用于 hash 配对码和设备 token，不应写入常规日志。未配对设备请求配对码时，服务端只在交互式控制台打印配对码，不通过 HTTP 响应返回；已配对设备在设置页生成配对码时可在响应中返回明文码。

服务端启动时在控制台输出监听地址和可访问 Web/API URL，便于部署时确认 IP 与端口。

## 日志原则

日志记录：

- 请求路径、状态码、耗时。
- 设备 ID。
- 错误码。

日志不得记录：

- 设备 token。
- 配对码。
- 短信原文。
- 完整银行卡号。
