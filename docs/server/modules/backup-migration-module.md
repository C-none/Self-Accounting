# 服务端备份与迁移模块

## 模块目标

备份迁移是一等能力，必须同时支持 Windows 与 Ubuntu Linux。系统不能依赖用户手工判断 SQLite WAL 文件状态。

## API

- `POST /api/admin/backup`
- `POST /api/admin/checkpoint`

## Checkpoint

`POST /api/admin/checkpoint`：

- 校验设备 token 和管理权限。
- 执行 `PRAGMA wal_checkpoint(TRUNCATE)`。
- 返回 `busy`、`log_frames`、`checkpointed_frames`。

用于迁移前降低 `app.db-wal` 未合并风险。

## 备份

`POST /api/admin/backup`：

1. 获取备份锁。
2. 阻止并发备份。
3. 获取存储锁，和附件 FFmpeg 压缩/落库互斥。
4. 执行 SQLite checkpoint。
5. 创建临时备份目录。
6. 使用 SQLite `VACUUM INTO` 生成一致性 `app.db`。
7. 复制 `photos/` 和 `thumbnails/`。
8. 写 `manifest.json`。
9. 写 `config.export.json`，不导出 server secret。
10. 打包为 zip。
11. 返回备份元数据。

用于服务器迁移时，备份 zip 之外还要单独安全复制 `security.secret_path` 指向的 `server-secret.key`，否则已有设备 token 和配对码 hash 无法继续校验。

## 备份内容

```text
ledger-backup-YYYYMMDD-HHMMSS.zip
  manifest.json
  app.db
  photos/
  thumbnails/
  config.export.json
```

## 恢复

恢复流程在停服状态执行：

1. 停止当前服务。
2. 保存当前 `data/` 副本。
3. 解压备份包。
4. 校验 `manifest.json`。
5. 替换 `app.db`、`photos/`、`thumbnails/`。
6. 如需保留已配对设备，恢复 `server-secret.key` 并确认 `security.secret_path` 指向它。
7. 按当前平台配置 FFmpeg 路径。
8. 启动服务。

恢复后验证：

- `/api/health` 正常。
- `sqlite3 data/app.db "PRAGMA integrity_check;"` 返回 `ok`。
- 交易列表能读取迁移前样例交易。
- 至少一个附件缩略图和原图 URL 可访问。
- `POST /api/admin/checkpoint` 能成功执行。

## Windows 到 Ubuntu Linux

注意事项：

- 备份包中的文件名使用相对路径。
- 不保存 Windows 绝对路径。
- 恢复后将 `ffmpeg.path` 改为 Ubuntu 路径。
- 确认文件权限允许服务进程读写。

## Ubuntu Linux 到 Windows

注意事项：

- 恢复后将 `ffmpeg.path` 改为 Windows `.exe` 路径。
- 确认数据目录没有被杀毒软件锁定。
- 使用普通目录路径，避免受限系统目录。

## 验收标准

- 备份包能在 Windows 生成，并通过 `PRAGMA integrity_check` 校验。
- 具备 Ubuntu Linux 环境时，备份包需补做 Windows -> Ubuntu 和 Ubuntu -> Windows 真实恢复演练。
- 文档明确禁止只复制 `app.db` 作为迁移方案。
- 备份包含 SQLite 数据、照片、缩略图、配置导出和 manifest。
- 迁移手册明确要求附件图片、缩略图和保留配对所需的 server secret 一起迁移。
- 备份与附件压缩受同一存储锁保护，避免备份到半成品图片。
