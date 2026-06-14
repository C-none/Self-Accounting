# 部署、备份与迁移设计

实际迁移操作手册见根目录 `MIGRATION.md`。该手册明确要求迁移 SQLite 数据库时同时迁移附件图片目录 `photos/` 和缩略图目录 `thumbnails/`，并说明保留已配对设备时需要同步迁移 `server-secret.key`。

## 部署目标

服务端必须能在 Windows 和 Ubuntu Linux 上运行，并支持频繁迁移服务和数据。推荐发布两个平台的 Go 二进制：

- Windows：`ledger-server.exe`
- Ubuntu Linux：`ledger-server`

Flutter Web 生产产物嵌入 Go 二进制或作为同目录静态资源由 Go 托管。生产运行不依赖 Flutter SDK、Node.js、Nginx 或 Docker。

## Ubuntu 发布脚本

Ubuntu release 包应包含 `scripts/ubuntu/` 下的固定运维脚本：

- `install.sh`：兼容入口，等同于 `install-release.sh`。
- `install-release.sh`：从发布包根目录或 `dist/release/` 安装 `ledger-server`、`web/`、运维脚本和可选 APK 到目标目录。
- `install-dev.sh`：从 dev 构建路径安装，默认读取 `dist/dev/ubuntu-amd64/ledger-server` 和 `client/build/web`，仅用于有构建环境的开发机或临时测试机。
- `install-common.sh`：安装公共实现，被 dev/release 安装脚本调用，不作为用户直接入口。
- `start.sh`：用 `nohup` 启动服务，写入 `run/ledger-server.pid` 和 `logs/ledger-server.log`。
- `stop.sh`：按 pid 文件停止服务。
- `db-export.sh`：停服后导出 `app.db`、`photos/`、`thumbnails/`、`config.json` 和 `server-secret.key` 到 `exports/ledger-db-export-*.tar.gz`。
- `db-import.sh`：停服后从 `ledger-db-export-*.tar.gz` 或服务端备份 zip 恢复数据库、图片目录和可选 `server-secret.key`。

这些脚本是发布运维接口，后续更新应尽可能保持文件名、参数和环境变量兼容。默认安装目录是：

```text
/opt/ledger-node
```

可通过环境变量调整：

```bash
LEDGER_APP_DIR=/opt/ledger-node
LEDGER_RUN_USER=ledger
LEDGER_LISTEN_ADDR=0.0.0.0:8080
LEDGER_PUBLIC_BASE_URL=https://ledger.example.com
LEDGER_REQUIRE_HTTPS=true
```

dev 安装默认安装到 `/opt/ledger-node-dev`，可通过相同的 `LEDGER_APP_DIR` 覆盖；release 安装默认安装到 `/opt/ledger-node`。dev 产物路径属于本地构建输出，应继续被 git 忽略；release 产物放在 `dist/release/`，需要随仓库发布。

脚本不依赖 Docker、Nginx 或 systemd。生产公网 HTTPS 可由云厂商负载均衡或外部反向代理提供，但本系统本地运行不强制依赖它们。

## 运行目录

```text
ledger-node/
  ledger-server.exe          # Windows 可执行文件
  ledger-server              # Ubuntu Linux 可执行文件
  config.json
  server-secret.key          # security.secret_path 指向的文件，用于保留已配对设备 token
  data/
    app.db
    app.db-wal               # WAL 模式运行中可能存在
    app.db-shm               # WAL 模式运行中可能存在
    photos/
    thumbnails/
  backups/
  logs/
  tmp/
```

## 配置文件

`config.json` 至少包含：

```json
{
  "server": {
    "listen_addr": "0.0.0.0:8080",
    "public_base_url": "https://ledger.example.com",
    "require_https": true
  },
  "database": {
    "path": "./data/app.db",
    "busy_timeout_ms": 5000,
    "synchronous": "NORMAL"
  },
  "storage": {
    "photos_dir": "./data/photos",
    "thumbnails_dir": "./data/thumbnails",
    "tmp_dir": "./tmp"
  },
  "ffmpeg": {
    "path": "ffmpeg",
    "jpg_quality": 18,
    "max_width": 1600,
    "max_height": 1600
  },
  "backup": {
    "dir": "./backups"
  }
}
```

Windows 下可以把 `ffmpeg.path` 配置为 `C:\\tools\\ffmpeg\\bin\\ffmpeg.exe`。Ubuntu Linux 下可以使用 `/usr/bin/ffmpeg` 或 PATH 中的 `ffmpeg`。

## SQLite WAL 与迁移规则

SQLite 使用 WAL 后，运行中可能存在 `app.db-wal` 和 `app.db-shm`。这些文件关系到已提交事务和共享内存索引。迁移时不能只复制 `app.db`。

推荐迁移方式：

1. 在旧服务器调用 `POST /api/admin/checkpoint`。
2. 停止旧服务。
3. 调用或手动创建备份包。
4. 将备份包复制到目标 Windows 或 Ubuntu Linux 机器。
5. 在新机器恢复备份包并启动对应平台二进制。

最低限度的手动目录复制方式：

1. 停止旧服务。
2. 确认没有服务进程持有数据库。
3. 复制整个 `ledger-node/` 目录，而不是只复制 `data/app.db`。
4. 在目标机器启动服务。

## 备份包格式

备份包使用 zip：

```text
ledger-backup-YYYYMMDD-HHMMSS.zip
  manifest.json
  app.db
  photos/
  thumbnails/
  config.export.json
```

备份 API 生成的 zip 不包含 `server-secret.key`。用于迁移时，必须把 `security.secret_path` 指向的 secret 文件作为敏感文件单独迁移；否则旧设备 token 无法继续校验。

`manifest.json` 示例：

```json
{
  "format_version": 1,
  "created_at": "2026-05-31T12:00:00Z",
  "source_os": "windows|linux",
  "app_version": "0.1.0",
  "database_file": "app.db",
  "photos_dir": "photos",
  "thumbnails_dir": "thumbnails",
  "currency": "CNY",
  "amount_unit": "cent",
  "config_file": "config.export.json"
}
```

## 备份流程

服务端 `POST /api/admin/backup` 执行：

1. 拒绝并发备份任务。
2. 获取存储锁，和附件 FFmpeg 压缩/落库互斥。
3. 执行 SQLite checkpoint，并用 `VACUUM INTO` 生成一致性 `app.db`。
4. 扫描 `photos/` 和 `thumbnails/`。
5. 写入 `manifest.json` 与 `config.export.json`。
6. 生成 zip 到 `backups/`。
7. 返回备份文件名、大小和创建时间。

## 恢复流程

恢复由管理员在停服状态执行：

1. 停止服务。
2. 备份当前 `data/` 到安全目录。
3. 解压备份包。
4. 校验 `manifest.json`。
5. 替换 `data/app.db`、`photos/`、`thumbnails/`。
6. 如需保留已配对设备，恢复 `security.secret_path` 指向的 `server-secret.key`。
7. 按目标平台修改 `config.json` 中路径和 FFmpeg 配置。
8. 启动 Windows 或 Ubuntu Linux 对应二进制。
9. 执行 `sqlite3 data/app.db "PRAGMA integrity_check;"`，确认返回 `ok`。

## 跨平台注意事项

- 数据库、照片和备份文件路径必须使用应用内部相对路径保存。
- 数据库不保存 Windows 绝对路径或 Linux 绝对路径。
- 附件记录保存文件 hash 和相对文件名。
- FFmpeg 路径是平台相关配置，备份恢复后允许重新配置。
- 生产公网域名变化时，客户端需要重新设置服务器地址；设备 token 可保留，前提是数据库和 `server-secret.key` 都来自同一源服务器。

## 构建与体积要求

每次发布必须记录构建产物大小：

```powershell
go build -trimpath -ldflags="-s -w" -o dist/ledger-server.exe ./server/cmd/ledger-server
flutter build web --release --analyze-size
flutter build apk --release --analyze-size
```

Flutter Web 需同时试构建 `flutter build web --release --wasm`。首版以真实本机测试结果选择默认发布产物：若 `--wasm` 的首屏加载和兼容性在 Chrome 测试中优于普通 release，则采用 `--wasm`；否则采用普通 release。选择结果必须记录在本文件或测试记录中。
