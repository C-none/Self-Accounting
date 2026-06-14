# 服务端交易模块

## 功能范围

服务端提供 Android 和 Web 共用的交易 API：

- 新增交易。
- 编辑交易。
- 软删除交易。
- 查询详情。
- 列表过滤和分页。

## API

- `GET /api/transactions`
- `POST /api/transactions`
- `GET /api/transactions/{id}`
- `PATCH /api/transactions/{id}`
- `DELETE /api/transactions/{id}`

## 新增交易

请求必须包含：

- `amount_cent`
- `currency`，默认 `CNY`
- `direction`
- `transaction_time`
- `category_l1_id`
- `member_id`
- `account_id`

可选：

- `category_l2_id`
- `counterparty`
- `description`
- `source`

Web 和 Android 手动新增时 `source='manual'` 或 `source='web'`。短信导入创建的交易由短信模块提交。

服务端实际规则：

- `amount_cent` 必须是正整数。
- `direction` 决定收入、支出或转账，金额本身不存负数。
- `source` 不信任客户端自由传入；普通交易由认证设备平台推导，短信交易只能由短信导入接口创建。
- `category_l1_id`、`category_l2_id`、`member_id`、`account_id` 必须指向未删除且 active 的基础数据。
- 创建成功写入 `audit_logs(action='create')`。

响应返回完整交易对象，字段名与数据库保持一致，时间字段使用 Unix timestamp 秒。

## 编辑交易

`PATCH /api/transactions/{id}` 使用最后写入胜出：

- 校验 token。
- 校验交易存在且未软删除。
- 覆盖提交字段。
- 更新时间、递增 `version`。
- 写入审计日志。
- 返回最新交易。

## 软删除

`DELETE /api/transactions/{id}`：

- 设置 `deleted_at`。
- 递增 `version`。
- 写审计日志。
- 默认列表不返回软删除交易。

## 过滤和分页

支持：

- `from`
- `to`
- `direction`
- `category_l1_id`
- `category_l2_id`
- `member_id`
- `account_id`
- `keyword`
- `page`
- `page_size`

关键词搜索首版可使用 `LIKE` 匹配 `description` 和 `counterparty`。

分页规则：

- 默认 `page=1`。
- 默认 `page_size=50`。
- 最大 `page_size=200`。
- 响应包含 `items`、`page`、`page_size`、`total`。

默认排序：

```sql
ORDER BY transaction_time DESC, created_at DESC
```

## 金额规则

所有金额字段都是 `amount_cent INTEGER`：

- 请求不得提交浮点金额字段。
- 响应返回 `amount_cent`。
- 客户端负责展示转换。

## 验收标准

- Android 和 Web 使用同一套 API 新增交易。
- 删除是软删除。
- 并发编辑时最后一次服务端接收的请求获胜。
- 服务端不保存浮点金额。
- Web/API 闭环覆盖新增、读取、过滤、编辑、删除。
- Android 模拟器闭环覆盖同一条交易从新增到删除的完整路径。
