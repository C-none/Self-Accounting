# 服务端统计模块

## 模块目标

服务端提供分类占比和时间趋势聚合 API。客户端只负责渲染。

## API

- `GET /api/stats/category`
- `GET /api/stats/timeline`

## 通用参数

- `from`
- `to`
- `direction`
- `member_id`
- `account_id`
- `bank_name`
- `category_l1_id`
- `category_l2_id`
- `compare_by`

默认排除软删除交易：

```sql
WHERE deleted_at IS NULL
```

## 分类占比

`GET /api/stats/category` 返回按比较属性聚合的数据。`compare_by` 支持：

- `category_l1`
- `category_l2`
- `member`
- `bank`

未传 `compare_by` 时保留旧行为：按 `level=l1|l2` 聚合，默认 `l1`。

```json
{
  "currency": "CNY",
  "compare_by": "category_l1",
  "items": [
    {
      "group_id": "food",
      "group_name": "餐饮",
      "category_id": "food",
      "category_name": "餐饮",
      "amount_cent": 123400,
      "percent": 42.5
    }
  ]
}
```

金额聚合基于整数：

```sql
SUM(amount_cent)
```

参数：

- `level=l1|l2`，默认 `l1`。
- `compare_by=category_l1|category_l2|member|bank`。
- `direction=income|expense|transfer`，默认 `expense`。
- `from`、`to` 使用 Unix timestamp 秒。

传入 `compare_by` 时，不能同时使用同一属性作为过滤条件：

- `compare_by=category_l1` 时不能传 `category_l1_id` 或 `category_l2_id`。
- `compare_by=category_l2` 时不能传 `category_l2_id`，但可以用 `category_l1_id` 限定一级分类。
- `compare_by=member` 时不能传 `member_id`。
- `compare_by=bank` 时不能传 `bank_name` 或 `account_id`。

`percent` 只作为展示值，由服务端按整数聚合结果计算，客户端不得把 `percent` 作为金额依据。

## 时间趋势

`GET /api/stats/timeline` 支持：

- `bucket=day`
- `bucket=week`
- `bucket=month`

默认 `bucket=day`，默认 `direction=expense`。

`bucket=week` 返回每周一作为时间桶日期，例如 `2026-06-01`。

未传 `compare_by` 时保留旧返回，`points` 为合计趋势：

```json
{
  "currency": "CNY",
  "bucket": "day",
  "points": [
    {
      "date": "2026-05-31",
      "amount_cent": 12345
    }
  ]
}
```

传入 `compare_by` 时额外返回多序列 `series`，用于客户端绘制多条折线；`points` 仍返回按时间桶合计，保持兼容：

```json
{
  "currency": "CNY",
  "bucket": "day",
  "compare_by": "category_l1",
  "points": [
    {
      "date": "2026-05-31",
      "amount_cent": 12345
    }
  ],
  "series": [
    {
      "group_id": "food",
      "group_name": "餐饮",
      "points": [
        {
          "date": "2026-05-31",
          "amount_cent": 12345
        }
      ]
    }
  ]
}
```

## 性能策略

家庭数据量小，首版直接 SQL 聚合即可：

- 按时间范围过滤。
- 使用 `transaction_time` 索引。
- 返回聚合结果，不返回全量明细。

## 验收标准

- 统计 API 不返回浮点金额作为权威数据。
- `percent` 只作为展示辅助。
- Android 和 Web 使用同一统计接口。
- 软删除交易不进入默认统计。
- 图表数据来自统计 API，不由客户端全量扫描交易列表计算。
