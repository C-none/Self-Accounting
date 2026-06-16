# API 与安全设计

## 安全模型

系统不设计账号密码。访问控制基于：

- HTTPS。
- 一次性配对码。
- 设备 token。
- 服务端存储 token hash。
- 设备可撤销。

测试阶段可以在局域网使用 HTTP。生产公网阶段必须使用 HTTPS。

hash 与随机值规则：

- 配对码明文只返回给已配对设备一次；未配对设备请求生成时只触发服务端控制台打印，HTTP 响应不得包含配对码。
- 服务端数据库只保存 `HMAC-SHA256(server_secret, pairing_code)`；进程内可短期缓存当前未过期明文码，用于重复请求时重新打印。
- 设备 token 明文只返回一次，服务端保存 `HMAC-SHA256(server_secret, device_token)`。
- token 校验使用常量时间比较。
- 常规请求日志、审计和错误响应不得输出配对码、token、短信原文、完整银行卡号或完整账户敏感标识；唯一例外是用户主动请求生成配对码时，服务端交互式控制台输出当前配对码。

## 配对流程

1. 未配对设备在配对页点击“请求生成配对码”，服务端生成短期一次性配对码并打印到命令行，HTTP 响应不包含明文配对码。
2. 如果已有未过期、未使用的当前配对码，服务端重新打印同一个配对码。
3. 已配对设备可在设置页生成配对码，此时 HTTP 响应返回明文配对码。
4. 新设备输入配对码并调用 `POST /api/pair/confirm`。
5. 服务端校验配对码，生成设备 token。
6. 客户端保存 token，后续请求使用 `Authorization: Bearer <token>`。
7. 服务端只保存 token hash。

首台设备规则：

- 如果数据库中没有任何 active admin 设备，首台设备仍不能直接从 HTTP 响应获得配对码，只能通过服务端控制台读取配对码。
- 首台设备配对成功后自动设为 admin。
- 后续已配对设备可在账户内部调用 `POST /api/pair/start` 获取新设备配对码；未配对设备调用只会触发服务端控制台打印。

## API 列表

### Pairing

- `POST /api/pair/start`
  - 生成一次性配对码。
  - 未携带有效 token：返回 `expires_at` 和 `delivery=server_console`，不返回 `pairing_code`。
  - 携带有效 token：返回 `pairing_code`、`expires_at` 和 `delivery=response`。

- `POST /api/pair/confirm`
  - 请求：`pairing_code`、`device_name`、`platform`。
  - `platform` 只允许 `android` 或 `web`。
  - 返回：`device_id`、`device_token`、`is_admin`、`server_time`。

### Bootstrap

- `GET /api/bootstrap`
  - 返回成员、账户、分类、服务端配置、当前设备信息和平台功能开关。
  - Web 返回中 `features.sms=false`。

### Devices

- `PATCH /api/devices/current`
  - 需要设备 token。
  - 请求：`name`，服务端裁剪空白后保存为当前设备名。
  - 返回更新后的当前设备信息。
  - 写入 `audit_logs(entity_type='device', action='update_name')`，审计 payload 不记录旧名、新名、token 或配对码。

### Master Data

- `POST /api/categories` / `PATCH /api/categories/{id}` / `DELETE /api/categories/{id}`
  - 管理一级和二级分类。
  - 分类方向只允许 `income`、`expense`、`transfer`。
  - 删除为软删除；已有交易引用的分类不能删除，避免历史交易丢失显示名称。
  - `POST /api/categories/reorder` 按方向和父级调整同一作用域内分类显示顺序；请求包含 `type`、`parent_id` 和完整 `ordered_ids`，服务端校验无重复、无缺失后写入 `sort_order`。

- `POST /api/members` / `PATCH /api/members/{id}` / `DELETE /api/members/{id}`
  - 管理使用人。
  - 删除为软删除；已有交易引用的使用人不能删除。
  - `POST /api/members/reorder` 按完整 `ordered_ids` 调整使用人显示顺序。

- `POST /api/accounts` / `PATCH /api/accounts/{id}` / `DELETE /api/accounts/{id}`
  - 管理账户。
  - 账户标识必须由客户端传入脱敏值，服务端不得记录完整敏感账户标识。
  - 删除为软删除；已有交易引用的账户不能删除。
  - `POST /api/accounts/reorder` 按完整 `ordered_ids` 调整账户显示顺序。

### Transactions

- `GET /api/transactions`
  - 支持时间范围、分类、成员、账户、方向、关键词、分页。
  - 默认 `include_deleted=false`。
  - 默认 `page_size=50`，最大 `page_size=200`。

- `POST /api/transactions`
  - Android 和 Web 都可调用。
  - 请求金额字段为 `amount_cent`。
  - 手动新增时 `source` 由服务端根据平台设为 `manual` 或 `web`，客户端不得伪造 `source='sms'`。

- `GET /api/transactions/{id}`
  - 获取详情。

- `PATCH /api/transactions/{id}`
  - 编辑已有交易。
  - 最后写入胜出，服务端更新时间和版本。

- `DELETE /api/transactions/{id}`
  - 软删除，设置 `deleted_at`。

### SMS

- `POST /api/category-suggestions`
  - 需要设备 token。
  - 用于短信导入候选的分类建议，也可被 Android 或 Web 安全调用，但首个接入入口仅为 Android 短信导入。
  - 请求：`items` 数组，每项包含 `client_ref`、`direction`、`amount_cent`、`transaction_time`、`account_id`、`counterparty`、`description`。
  - 返回：每项包含 `client_ref`、`category_l1_id`、`category_l2_id`、`confidence`、`method` 和最多 3 个 `alternatives`。
  - 服务端基于未软删除历史交易即时训练轻量 Multinomial Naive Bayes 模型，不保存请求、不写审计日志。
  - 请求体不得包含 `raw_body`、`sms_body`、`body`、`message`、`content` 或 `text` 等疑似短信正文的字段。

- `POST /api/sms/imports`
  - 仅 Android 调用。
  - 提交用户确认后的短信结构化结果。
  - Android 可在本地候选和确认页展示短信原文；请求体不提交短信原文。
  - 服务端拒绝包含 `raw_body`、`sms_body`、`message` 等疑似短信正文的字段。
  - `sms_hash` 由 Android 本地按发送方、就近秒归一化接收时间和规范化正文生成，服务端不接收正文。
  - `sms_received_at_ms` 必填，用于审计和后续筛选；`sms_hash` 唯一，重复导入返回 `duplicate_sms_import`。
  - `sms_time` 使用收到短信时间的秒级值，短信明文中的时间不作为交易时间。
  - 服务端创建 `source='sms'` 的交易，并把 `sms_imports.transaction_id` 指向该交易。

### Attachments

- `POST /api/attachments`
  - 上传照片。
  - 服务端保存临时文件后用 FFmpeg 压缩为 JPG。
  - multipart 字段包含 `transaction_id` 和 `file`。
  - 单文件大小上限由 `/api/bootstrap` 返回，首版默认 20 MB。

- `GET /api/transactions/{id}/attachments`
  - 获取某笔交易未删除附件的元数据。

- `GET /api/attachments/{id}` / `GET /api/attachments/{id}/thumbnail`
  - 需要设备 token。
  - 返回服务端压缩后的 JPG 或缩略图。
  - 客户端不得通过 URL query 传 token，Web 端用带认证头的 HTTP 请求拉取 bytes 后显示。

- `DELETE /api/attachments/{id}`
  - 需要设备 token。
  - 软删除附件元数据，设置 `deleted_at`。
  - 不在业务请求中物理删除压缩图或缩略图文件。

### Statistics

- `GET /api/stats/category`
  - 饼图数据。
  - 支持 `direction`、`from`、`to`、`member_id`、`category_l1_id`、`category_l2_id`、`account_id`、`bank_name`、`level`、`compare_by` 查询参数。
  - `compare_by` 支持 `category_l1`、`category_l2`、`member`、`bank`；传入后不能再使用同一属性过滤，例如 `compare_by=category_l1` 不能同时传 `category_l1_id` 或 `category_l2_id`。

- `GET /api/stats/timeline`
  - 折线图数据。
  - 支持 `bucket=day|week|month`，以及和分类统计相同的过滤参数。
  - 传入 `compare_by` 时返回 `series` 多序列折线数据，同时保留合计 `points`。

### Admin

- `GET /api/admin/audit-logs`
  - 查询最近审计日志，仅 admin 设备可调用。
  - 支持 `limit`，默认 50，最大 100。
  - 返回字段只包含 `id`、`entity_type`、`entity_id`、`action`、`device_id`、`device_name`、`created_at`，不返回 `payload_json`。
  - 用于设置页的精简日志查询，不作为完整调试日志或敏感数据导出接口。

- `POST /api/admin/backup`
  - 生成跨平台备份包。
  - 仅 admin 设备可调用；和附件压缩共用存储锁。

- `POST /api/admin/checkpoint`
  - 执行 SQLite checkpoint，用于迁移前。
  - 仅 admin 设备可调用。

## 最后写入胜出

服务端接收 `PATCH` 时不做复杂合并：

- 以服务端接收时间为准。
- 当前写入覆盖已有值。
- `version = version + 1`。
- 写入 `audit_logs`，记录覆盖前后的关键字段。

客户端如果显示的是旧数据，提交后仍以本次提交为最终状态。

## 错误规范

所有 API 错误返回 JSON：

```json
{
  "error": {
    "code": "unauthorized",
    "message": "device token is invalid"
  }
}
```

常用错误码：

- `unauthorized`
- `forbidden`
- `not_found`
- `validation_error`
- `network_required`
- `ffmpeg_unavailable`
- `backup_in_progress`
- `duplicate_sms_import`
- `payload_too_large`
- `internal_error`

## 公网要求

生产公网环境必须满足：

- HTTPS 可用。
- token 不通过 URL query 传递。
- 配对码短期有效，使用后作废。
- 支持撤销设备。
- 常规日志不记录 token、短信原文和完整银行卡标识；配对码只允许在用户主动请求生成时输出到服务端控制台。
