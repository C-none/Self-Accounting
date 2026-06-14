# 客户端照片模块设计

## 范围

Android 和 Web 都支持为交易添加照片。客户端负责选择或拍摄照片并上传；最终压缩由服务端 FFmpeg 完成。

## 平台能力

Android：

- 调用摄像头拍照。
- 从相册选择。
- 上传文件到服务端。

Web：

- 使用浏览器文件选择。
- 上传文件到服务端。

## 上传流程

```text
User selects photo
  -> Flutter validates size/type
  -> POST /api/attachments multipart
  -> server stores temp file
  -> server FFmpeg compresses to JPG
  -> server creates attachment record
  -> client receives attachment metadata
  -> client loads thumbnail through authenticated image API
```

## 客户端校验

客户端只做轻量校验：

- 文件必须是图片。
- 单文件大小超过配置上限时提示用户。
- 网络不可用时禁止上传。

客户端不负责最终高压缩参数，避免 Android/Web 压缩结果不一致。

性能要求：

- 交易列表只显示服务端缩略图。
- 交易详情页用户点击附件后才加载压缩大图。
- 客户端不在启动时预取附件。
- Web 不引入额外图片处理库。
- Android 拍照/选图只作为上传来源，最终压缩结果以服务端 JPG 为准。
- 客户端不把 device token 放进图片 URL，图片和缩略图通过 bearer token 请求后以内存字节展示。

## 附件状态

客户端展示状态：

- `uploading`
- `done`
- `failed`

当前服务端同步压缩并返回 `done` 或错误；客户端显示上传进度和失败提示。后续如果改为异步压缩，再增加 `processing` 状态轮询。

## 交易表单集成

新增交易时：

- 可以先创建交易，再上传附件并绑定交易。
- 或表单提交时带本地照片，服务端先创建交易再处理附件。

编辑交易时：

- 可以追加或删除附件。
- 删除附件为软删除。

当前实现支持新增交易时暂存照片并随保存上传；编辑已有交易时选择图片会立即上传。已上传附件可以在交易详情页软删除。

## 验收标准

- Android 和 Web 都能上传照片。
- 压缩职责只在服务端 FFmpeg。
- 客户端展示的是服务端压缩后的 JPG。
- 无网络时不进入上传队列。
- 上传照片后可在 Web 和 Android 查看同一个服务端缩略图。
- 已上传照片可从交易详情页删除，删除后交易附件列表不再返回该照片。
