# 数据模型设计

## 基本原则

- SQLite 是中心数据源。
- 所有写操作必须在线提交到服务端。
- 金额使用整数分：`amount_cent INTEGER`，单位是 0.01 RMB。
- 展示时以 `amount_cent / 100` 转成人民币金额。
- `currency` 字段保留，默认 `CNY`，首版不做汇率和多币种统计。
- 删除使用软删除。
- 最后写入胜出。
- 数据库只保存相对路径，不保存平台绝对路径。
- 所有迁移脚本必须在事务中执行，并通过 `schema_migrations` 记录。

## 迁移表

### schema_migrations

```sql
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at INTEGER NOT NULL
);
```

首版数据库版本为 `1`，当前最新版本为 `2`。服务端启动时按版本顺序执行迁移，任一迁移失败必须停止启动。

## 核心表

### transactions

```sql
CREATE TABLE transactions (
  id TEXT PRIMARY KEY,
  amount_cent INTEGER NOT NULL,
  currency TEXT NOT NULL DEFAULT 'CNY',
  direction TEXT NOT NULL CHECK (direction IN ('income', 'expense', 'transfer')),
  transaction_time INTEGER NOT NULL,
  category_l1_id TEXT NOT NULL,
  category_l2_id TEXT,
  member_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  counterparty TEXT,
  description TEXT,
  source TEXT NOT NULL CHECK (source IN ('manual', 'sms', 'web')),
  source_ref TEXT,
  created_by_device_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1
);
```

说明：

- `amount_cent`：收入和支出均存正整数，方向由 `direction` 表示。
- `transaction_time`：交易发生时间，Unix timestamp。
- `category_l1_id` 和 `category_l2_id` 支持一级/二级分类。
- `source='sms'` 只可能来自 Android，`transaction_time` 使用收到短信时间。
- `deleted_at IS NOT NULL` 表示软删除。
- `version` 用于最后写入胜出下的覆盖记录和审计显示。
- `source_ref` 对短信导入保存 `sms_imports.id`，手动交易为空。

索引：

```sql
CREATE INDEX idx_transactions_time ON transactions(transaction_time DESC);
CREATE INDEX idx_transactions_member ON transactions(member_id);
CREATE INDEX idx_transactions_account ON transactions(account_id);
CREATE INDEX idx_transactions_category_l1 ON transactions(category_l1_id);
CREATE INDEX idx_transactions_category_l2 ON transactions(category_l2_id);
CREATE INDEX idx_transactions_deleted ON transactions(deleted_at);
CREATE INDEX idx_transactions_source_ref ON transactions(source, source_ref);
```

### categories

```sql
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('income', 'expense', 'transfer')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
```

一级分类 `parent_id` 为空，二级分类 `parent_id` 指向一级分类。

### members

```sql
CREATE TABLE members (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
```

### accounts

```sql
CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  masked_identifier TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
```

账户以银行名称和可选银行卡尾号组合展示。`name` 保存银行名称，例如 `工商银行`；`masked_identifier` 只保存可选尾号，例如 `0973`，不得保存完整卡号。旧的现金、微信零钱、支付宝等账户仍可保留为普通账户名称。

## 附件表

### attachments

```sql
CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL,
  original_file_name TEXT,
  stored_file_name TEXT NOT NULL,
  thumbnail_file_name TEXT,
  sha256 TEXT NOT NULL,
  mime_type TEXT NOT NULL DEFAULT 'image/jpeg',
  size_bytes INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  compression_status TEXT NOT NULL CHECK (compression_status IN ('pending', 'done', 'failed')),
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  FOREIGN KEY(transaction_id) REFERENCES transactions(id)
);
```

服务端接收上传后调用 FFmpeg 压缩为 JPG。数据库只保存文件元数据和相对文件名，不保存图片 BLOB。

## 短信导入表

### sms_imports

```sql
CREATE TABLE sms_imports (
  id TEXT PRIMARY KEY,
  sms_hash TEXT NOT NULL UNIQUE,
  sender_masked TEXT,
  sms_received_at_ms INTEGER NOT NULL DEFAULT 0,
  sms_time INTEGER NOT NULL,
  parsed_amount_cent INTEGER,
  parsed_direction TEXT,
  parsed_counterparty TEXT,
  parsed_account_hint TEXT,
  parsed_category_l1_id TEXT,
  parsed_category_l2_id TEXT,
  status TEXT NOT NULL CHECK (status IN ('candidate', 'confirmed', 'ignored')),
  transaction_id TEXT,
  device_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

短信原文不上传服务端。`sms_hash` 由 Android 本地根据短信发送方、就近秒归一化接收时间和规范化短信正文计算，用于去重；服务端只保存 hash、脱敏发送方和精确的 `sms_received_at_ms`，不保存短信正文。`sms_time` 表示收到短信时间的秒级值，`sms_received_at_ms` 表示 Android SMS provider 的原始接收时间。

## 设备与配对

### devices

```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'web')),
  token_hash TEXT NOT NULL UNIQUE,
  is_admin INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER,
  revoked_at INTEGER
);
```

### pairing_codes

```sql
CREATE TABLE pairing_codes (
  id TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at INTEGER NOT NULL,
  used_at INTEGER,
  created_at INTEGER NOT NULL
);
```

配对码明文不进入 SQLite。服务端进程内可短期缓存当前未过期明文配对码，用于未配对设备重复请求时重新在控制台打印；服务重启后该缓存丢失，可重新生成新的配对码。

## 审计与变更

### audit_logs

```sql
CREATE TABLE audit_logs (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  device_id TEXT NOT NULL,
  payload_json TEXT,
  created_at INTEGER NOT NULL
);
```

审计用于排查最后写入胜出的覆盖情况，不作为复杂冲突解决系统。

设置页只查询最近审计摘要，展示时间、动作、实体和设备名；接口不得返回 `payload_json`。当前设备改名会写入 `entity_type='device'`、`action='update_name'` 的审计记录，但不记录旧名或新名，避免日志中扩散可识别设备信息。

审计 payload 必须脱敏：

- 不写入 token、配对码、短信原文。
- 账户标识只允许写入 `masked_identifier`。
- 修改交易时只记录字段名和必要的旧值/新值摘要，避免日志无限膨胀。

## 统计模型

统计按服务端 SQL 聚合：

- 分类饼图：按一级分类聚合 `SUM(amount_cent)`。
- 时间折线图：按日、周或月聚合 `SUM(amount_cent)`。
- 过滤维度：方向、时间范围、成员、分类、账户或银行名称。
- 默认只统计 `deleted_at IS NULL` 的交易。

## 首版基础数据种子

迁移版本 `1` 会写入最小可测试基础数据：

- 成员：`本人`。
- 账户：`现金`。
- 支出一级分类：餐饮、交通、购物、居家、其他支出；餐饮包含正餐、饮品二级分类。
- 收入一级分类：工资、其他收入。
- 转账一级分类：账户转账。

种子数据只用于首版开箱读写闭环，后续基础数据维护功能可以在不改变交易表结构的情况下扩展。
