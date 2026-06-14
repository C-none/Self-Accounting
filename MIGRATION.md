# 服务器迁移流程

本文件是实际迁移操作手册，适用于 Windows 和 Ubuntu Linux 之间迁移家庭记账服务器。

核心原则：不要只复制 `app.db`。交易记录在 SQLite 中，附件图片和缩略图在文件系统中；数据库只保存相对文件名和 hash，不保存图片 BLOB。迁移时必须同时带走数据库、`photos/`、`thumbnails/`，否则交易记录仍在，但图片和缩略图会无法打开。

## 必须迁移的内容

按配置文件中的实际路径为准，默认生产节点可按下列结构理解：

```text
ledger-node/
  ledger-server.exe 或 ledger-server
  config.json
  server-secret.key              # security.secret_path 指向的文件
  web/                           # Flutter Web 产物，若由本目录托管
  data/
    app.db
    app.db-wal                   # 停服或 checkpoint 后通常不存在
    app.db-shm                   # 停服或 checkpoint 后通常不存在
    photos/                      # 原图/压缩后大图，必须迁移
    thumbnails/                  # 缩略图，必须迁移
  backups/
  tmp/
```

必须确认：

- `database.path` 指向的 SQLite 数据库已迁移。
- `storage.photos_dir` 整个目录已迁移。
- `storage.thumbnails_dir` 整个目录已迁移。
- `security.secret_path` 指向的 `server-secret.key` 已迁移，除非明确接受所有已配对设备 token 失效。
- `config.json` 已按目标机器调整端口、域名、路径和 FFmpeg 路径。
- 目标平台使用对应二进制：Windows 用 `ledger-server.exe`，Ubuntu Linux 用 `ledger-server`。

`POST /api/admin/backup` 生成的备份包包含 `app.db`、`photos/`、`thumbnails/`、`manifest.json`、`config.export.json`，但不会导出 `server-secret.key`。如果这是迁移而不是普通数据备份，需要单独安全复制 `server-secret.key`，否则已有 Web/Android 设备 token 无法继续验证。

## 推荐方案：备份包迁移

这是跨平台迁移的默认方案。它通过 SQLite `VACUUM INTO` 生成一致数据库，并在备份期间锁住附件存储，避免打包到半写入图片。

### 1. 在旧服务器生成备份

使用一个管理员设备 token 调用接口：

```powershell
$base = "http://127.0.0.1:8080"
$token = "<admin-device-token>"
$headers = @{ Authorization = "Bearer $token" }

Invoke-RestMethod -Method Post -Uri "$base/api/admin/checkpoint" -Headers $headers
$backup = Invoke-RestMethod -Method Post -Uri "$base/api/admin/backup" -Headers $headers
$backup.file_name
```

备份文件会写入 `backup.dir` 指定目录，例如：

```text
backups/ledger-backup-YYYYMMDD-HHMMSS.zip
```

同时复制 `security.secret_path` 指向的 secret 文件：

```powershell
Copy-Item .\server-secret.key .\backups\server-secret.key
```

如果 secret 在其他位置，以 `config.json` 的 `security.secret_path` 为准。

### 2. 传输到目标机器

下面示例把单独复制的 secret 放在目标机器的 `incoming/server-secret.key`，用来强调它不在备份 zip 内。

需要传输：

```text
ledger-backup-YYYYMMDD-HHMMSS.zip
incoming/server-secret.key
目标平台 ledger-server 可执行文件
Flutter Web 产物 web/ 或已配置的 web_dir
config.json
```

公网传输时，备份包和 `server-secret.key` 都应按敏感数据处理。`server-secret.key` 能影响配对码和设备 token 校验，不要放进公开目录或普通日志。

### 3. 在目标机器恢复

先停止目标服务，并保存现有数据副本。

Windows 示例：

```powershell
Stop-Process -Name ledger-server -ErrorAction SilentlyContinue
Copy-Item .\data .\data.before-migration -Recurse -Force

Expand-Archive .\ledger-backup-YYYYMMDD-HHMMSS.zip .\restore -Force

Remove-Item .\data\photos -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item .\data\thumbnails -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item .\data\app.db-wal -Force -ErrorAction SilentlyContinue
Remove-Item .\data\app.db-shm -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force .\data | Out-Null

Copy-Item .\restore\app.db .\data\app.db -Force
Copy-Item .\restore\photos .\data\photos -Recurse -Force
Copy-Item .\restore\thumbnails .\data\thumbnails -Recurse -Force
Copy-Item .\incoming\server-secret.key .\server-secret.key -Force
```

Ubuntu Linux 示例：

```bash
sudo systemctl stop ledger-server
cp -a data data.before-migration

rm -rf restore
unzip ledger-backup-YYYYMMDD-HHMMSS.zip -d restore

rm -rf data/photos data/thumbnails
rm -f data/app.db-wal data/app.db-shm
mkdir -p data

cp restore/app.db data/app.db
cp -a restore/photos data/photos
cp -a restore/thumbnails data/thumbnails
cp incoming/server-secret.key ./server-secret.key
chmod 600 ./server-secret.key
```

然后检查并修改 `config.json`：

```json
{
  "database": {
    "path": "./data/app.db"
  },
  "storage": {
    "photos_dir": "./data/photos",
    "thumbnails_dir": "./data/thumbnails",
    "tmp_dir": "./tmp"
  },
  "security": {
    "secret_path": "./server-secret.key"
  },
  "ffmpeg": {
    "path": "ffmpeg"
  }
}
```

Windows 上 `ffmpeg.path` 可以是 `C:\\tools\\ffmpeg\\bin\\ffmpeg.exe`；Ubuntu Linux 上可以是 `/usr/bin/ffmpeg` 或 PATH 中的 `ffmpeg`。

### 4. 启动目标服务

Windows：

```powershell
.\ledger-server.exe --config .\config.json
```

Ubuntu Linux：

```bash
./ledger-server --config ./config.json
```

如果使用 systemd，确认 service 文件中的工作目录、二进制路径和 `--config` 路径指向新目录。

## 备选方案：整节点打包迁移

如果目标机器只是接管同一个节点，且希望最大程度保留运行目录，可在 checkpoint 后停服并打包整个 `ledger-node/`。这种方式必须包含 `server-secret.key`，也必须包含 `data/photos/` 和 `data/thumbnails/`。

## Ubuntu 发布脚本迁移

Ubuntu release 包内提供 `scripts/ubuntu/` 运维脚本，可用于标准安装、启停和停服迁移：

```bash
bash scripts/ubuntu/install.sh
/opt/ledger-node/scripts/start.sh
/opt/ledger-node/scripts/stop.sh
/opt/ledger-node/scripts/db-export.sh
/opt/ledger-node/scripts/db-import.sh /path/to/ledger-db-export-YYYYMMDD-HHMMSS.tar.gz
```

默认安装目录是 `/opt/ledger-node`，可用 `LEDGER_APP_DIR` 调整。`db-export.sh` 会先停服，再导出 `app.db`、`photos/`、`thumbnails/`、`config.json` 和 `server-secret.key`；`db-import.sh` 会先停服并保存当前数据快照，再恢复数据库和附件目录。该脚本流程仍遵守本手册的核心原则：迁移时不能只复制 `app.db`。

Windows 打包：

```powershell
$base = "http://127.0.0.1:8080"
$token = "<admin-device-token>"
Invoke-RestMethod -Method Post -Uri "$base/api/admin/checkpoint" -Headers @{ Authorization = "Bearer $token" }

Stop-Process -Name ledger-server -ErrorAction SilentlyContinue
Compress-Archive -Path .\ledger-node\* -DestinationPath .\ledger-node-migration.zip -Force
```

Ubuntu Linux 打包：

```bash
curl -X POST \
  -H "Authorization: Bearer <admin-device-token>" \
  http://127.0.0.1:8080/api/admin/checkpoint

sudo systemctl stop ledger-server
cd /opt
zip -r ledger-node-migration.zip ledger-node
```

目标机器解压后需要：

- 替换为目标平台二进制。
- 修改 `config.json` 中的平台路径、监听地址、`public_base_url` 和 `ffmpeg.path`。
- 确认 `security.secret_path` 指向的 secret 文件实际存在。
- 确认服务进程对 `data/`、`photos/`、`thumbnails/`、`backups/`、`tmp/` 有读写权限。

## 恢复后验证清单

迁移完成后必须验证：

```bash
sqlite3 data/app.db "PRAGMA integrity_check;"
```

返回应为：

```text
ok
```

再按顺序检查：

1. `GET /api/health` 正常。
2. Web 页面能打开，并能用迁移前已配对设备继续访问。
3. 交易列表总数和迁移前一致。
4. 打开一条带附件的交易，缩略图能显示。
5. 点击或打开附件原图，图片能加载。
6. 统计页面能显示迁移后数据。
7. 新增一条带图片附件的交易，服务端能通过 FFmpeg 生成大图和缩略图。
8. 再次调用 `POST /api/admin/checkpoint` 成功。
9. 再次调用 `POST /api/admin/backup`，新备份包仍包含 `photos/` 和 `thumbnails/`。

如果第 4 或第 5 项失败，优先检查 `storage.photos_dir`、`storage.thumbnails_dir` 是否指向恢复后的目录，以及这两个目录是否完整复制。

## 常见问题

### 迁移后交易在，但图片不显示

原因通常是只迁移了 `app.db`，没有迁移 `photos/` 和 `thumbnails/`，或者 `config.json` 的目录指向错误。重新从备份包恢复这两个目录，并确认目录权限。

### 迁移后所有设备都需要重新配对

通常是 `server-secret.key` 没有复制，或者 `security.secret_path` 指到了新生成的 secret。常规迁移应保留旧 secret。若 secret 已丢失，不要继续覆盖数据；先保留现场，再按恢复预案处理设备表或重新初始化配对。

### 复制了 app.db，但数据不完整

SQLite WAL 模式下运行中可能存在 `app.db-wal`。迁移前应调用 `POST /api/admin/checkpoint` 并停服，或使用 `/api/admin/backup` 生成一致备份包。不要在服务运行中手工复制单个 `app.db`。

### 新上传图片失败

旧图片能显示但新图片失败时，通常是目标机器 `ffmpeg.path` 配置不对，或服务进程没有写入 `photos/`、`thumbnails/`、`tmp/` 的权限。

### Windows 与 Ubuntu 路径差异

数据库中的附件文件名必须是相对文件名，不应出现 `C:\`、盘符或 Linux 绝对路径。迁移后只在 `config.json` 中使用目标平台路径。
