# 服务端附件模块

## 模块目标

服务端接收 Android/Web 上传的照片，调用 FFmpeg 适度压缩为 JPG，保存压缩文件和缩略图，并记录附件元数据。

## API

- `POST /api/attachments`
- `GET /api/transactions/{id}/attachments`
- `GET /api/attachments/{id}`
- `GET /api/attachments/{id}/thumbnail`
- `DELETE /api/attachments/{id}`

## 上传流程

1. 校验设备 token。
2. 接收 multipart 文件。
3. 保存到 `tmp/`。
4. 校验文件类型。
5. 获取存储锁，避免和备份同时操作最终图片目录。
6. 调用 FFmpeg 压缩为 JPG。
7. 生成缩略图。
8. 计算压缩后文件 sha256。
9. 写入 `attachments` 表。
10. 删除临时文件。

上传请求字段：

- `transaction_id`：已存在且未软删除的交易 ID。
- `file`：图片文件，首版限制 20 MB。

返回附件元数据，不返回本地绝对路径。客户端读取图片时必须带设备 token 请求图片 bytes，避免把 token 放入 URL。

## 删除流程

`DELETE /api/attachments/{id}` 只做软删除：

1. 校验设备 token。
2. 校验附件存在且未删除。
3. 设置 `attachments.deleted_at`。
4. 写入附件删除审计。
5. 不立即删除 `photos/` 或 `thumbnails/` 中的物理文件，物理清理作为后续维护任务执行。

## FFmpeg 参数

默认压缩目标：

- 输出格式：JPG。
- 最大尺寸：1600x1600。
- JPG 质量：可配置，默认保留票据和文字细节，当前 `-q:v 18`。
- 去除元数据。

示例命令形态：

```text
ffmpeg -y -i input -vf scale=w='min(1600,iw)':h='min(1600,ih)':force_original_aspect_ratio=decrease -q:v 18 -map_metadata -1 output.jpg
```

实际命令需要处理竖图、横图和尺寸不超过上限的图片。

缩略图命令形态：

```text
ffmpeg -y -i output.jpg -vf scale=w='min(480,iw)':h='min(480,ih)':force_original_aspect_ratio=decrease -q:v 24 -map_metadata -1 thumb.jpg
```

压缩任务默认串行执行，且和备份目录复制互斥，避免小 CPU 被多个 FFmpeg 进程打满，也避免备份到半成品 JPG。

## Windows 与 Ubuntu Linux 配置

Windows：

- `ffmpeg.path = "C:\\tools\\ffmpeg\\bin\\ffmpeg.exe"`
- 启动时执行 `ffmpeg -version` 健康检查。

Ubuntu Linux：

- `ffmpeg.path = "/usr/bin/ffmpeg"` 或 `ffmpeg`
- 启动时执行 `ffmpeg -version` 健康检查。

如果 FFmpeg 不可用：

- 附件上传前的 `ffmpeg -version` 检查失败。
- 附件上传返回 `ffmpeg_unavailable`。
- 不保存未压缩原图为正式附件。

## 文件命名

压缩图：

```text
data/photos/{attachment_id}.jpg
```

缩略图：

```text
data/thumbnails/{attachment_id}.jpg
```

数据库保存相对文件名，不保存绝对路径。

## 清理策略

- 上传失败删除临时文件。
- 软删除附件时设置 `deleted_at`。
- 物理清理作为后续维护任务执行。

## 验收标准

- Android 和 Web 上传后都得到 JPG。
- 服务端压缩职责明确。
- Windows 和 Ubuntu Linux 都能配置 FFmpeg。
- 数据库不保存图片 BLOB。
- 上传失败不会留下正式附件记录。
- 压缩图和缩略图路径都是相对路径。
- Web 与 Android 列表默认加载缩略图，不加载原图。
- Web 与 Android 可从交易详情中软删除已上传照片。
