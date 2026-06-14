# 客户端短信模块设计

## 范围

短信模块仅存在于 Android Flutter App。Web 不实现、不展示、不路由到短信扫描能力。

Android App 私有安装包分发，不上架 Google Play。应用可以申请短信相关权限，但仍需在 UI 中解释权限用途。

实现方式：

- Flutter 层定义 `SmsPlatformAdapter`。
- Android 原生层通过 platform channel 暴露权限申请、历史扫描、广播接收初始化。
- Web adapter 返回 `unsupported`，路由和导航不注册短信入口。
- 不默认引入第三方短信读取插件，避免包体积和权限行为不可控。
- Android 本地使用 `crypto` 计算 `sms_hash`；hash 输入为发送方、就近秒归一化接收时间和规范化短信正文，服务端请求体只包含结构化字段。
- Android 本地保存短信提取模板 JSON，服务端不保存模板、不接收模板样本原文。

## 行为决策

- 支持 Android `SMS_RECEIVED` 广播监听；候选只保存在进程内队列，不做本地持久化。
- 断网时收到消费短信，App 不做任何处理。
- 恢复网络后，用户可以手动触发重新扫描短信。
- 短信原文只在 Android 本地解析，并可在短信导入候选和确认页展示，帮助用户核对模板提取结果。
- 服务端只接收用户确认后的结构化交易，不接收短信原文。
- 用户授权短信权限后不自动读取历史短信，必须点击“重新扫描”。
- 一个发送号码和一个本地账户可以学习出多个模板；只有用户启用的模板参与提取，未启用模板或未命中启用模板的短信直接忽略。
- Android 本地记录已成功导入或已被服务端判定重复的 `sms_hash`，后续手动重扫或广播轮询不再展示这些短信。

## 权限

Android 需要按目标系统版本申请：

- `READ_SMS`：历史短信扫描。
- `RECEIVE_SMS`：后台监听新短信。
- `ACCESS_NETWORK_STATE`：广播接收时判断当前是否在线；无法确认在线时按断网处理，不解析、不入队。

权限解释必须说明：

- 只读取金融交易相关短信。
- 短信正文不会上传服务器。
- 用户确认后才创建交易。

## 数据流

```text
SMS received or manual scan
  -> Android SMS adapter reads local message
  -> local enabled template match
  -> local parser extracts amount/template time placeholder/counterparty/account hint/balance
  -> transaction time is set to the SMS provider received time
  -> server category suggestion from structured fields, with local category fallback
  -> candidate confirmation UI
  -> user confirms/edits one candidate or multi-selects candidates for one-click import
  -> POST /api/sms/imports
  -> server creates transaction with source='sms'
```

## 后台监听

在线时：

- 收到短信后，如果进程可用，原生 receiver 将短信放入内存队列。
- 短信页定时拉取内存队列并在本地解析候选交易。
- 用户确认后提交服务端。

断网时：

- 不解析。
- 不保存后台待处理队列。
- 不弹确认。
- 用户稍后在短信模块手动点击“重新扫描”。

这条规则优先于自动化体验：断网短信不做任何后台持久化，避免引入离线队列和隐私风险。

## 手动重新扫描

手动扫描步骤：

1. 用户点击“重新扫描短信”。
2. App 检查网络和短信权限。
3. 扫描指定时间范围内短信。
4. 只保留匹配已启用本地模板的短信。
5. 本地按 `sender + received_at_second + normalized_body` 计算 `sms_hash` 去重。
6. 过滤本机已成功导入或已处理重复的 `sms_hash`。
7. 用候选结构化字段请求服务端分类建议，不上传短信原文。
8. 展示候选交易和本地短信原文。
9. 用户单条确认编辑后提交服务端，或进入多选模式批量导入选中候选。

当前默认扫描范围为近 7 天，UI 暂不提供范围调整。

## 解析与分类

当前采用本地模板、服务端历史交易分类建议和本地规则组合：

- 设置页 Android-only 提供“短信模板”入口。
- 用户选择账户、输入发送号码和日期范围后点击“学习模板”。
- 学习过程只在 Android 本地读取短信正文，按脱敏骨架聚类生成模板。
- 新模板默认禁用；用户可启用、停用或删除单个模板。
- 模板作用域为 `sender_normalized + account_id`。
- 模板 JSON 只保存脱敏骨架、槽位、样本数和启用状态，不保存短信原文。

模板槽位包括：

- 金额。
- 余额。
- 收入/支出方向。
- 短信明文时间占位 `{date_time}`。
- 交易对象。
- 账户提示。
- 分类猜测。

`{date_time}` 仍用于模板匹配短信中的时间片段，但不作为交易时间提交。交易时间统一采用 Android SMS provider 返回的收到短信时间。

未匹配已启用模板的短信不生成候选，也不使用规则兜底。

分类猜测优先级：

1. 服务端基于历史交易训练的 Multinomial Naive Bayes 分类建议。
2. 置信度不足、样本不足或网络失败时保留 Android 本地关键词规则结果。
3. 用户在确认页手动修改分类。

服务端分类建议 API 只接收方向、金额、交易时间、账户、交易对象和描述等结构化字段；短信导入候选的交易时间为收到短信时间，不得从短信原文提取。请求不得接收短信原文。Android 只有在 `confidence >= 0.65` 且 top1-top2 差值 `>= 0.15` 时自动采用服务端建议。

## 提交接口

`POST /api/sms/imports` 请求包含：

- `sms_hash`
- `sender_masked`
- `sms_received_at_ms`
- `sms_time`
- `amount_cent`
- `direction`
- `counterparty`
- `account_hint`
- `account_id`
- `category_l1_id`
- `category_l2_id`
- `member_id`
- `description`

不得包含短信原文。

`description` 只能来自用户确认或本地规则生成的摘要，不能复制完整短信正文。

本地解析出的余额只用于模板匹配和候选辅助展示，当前不提交服务端。

`sms_received_at_ms` 是 Android SMS provider 的原始接收时间，单位毫秒；`sms_time` 是同一收到短信时间的秒级值，并作为短信导入创建交易时的 `transaction_time`。

多选批量导入使用本地解析出的默认金额、方向、账户、分类、使用人、交易对象和描述，不进入逐条编辑页。重复短信按已处理移除候选，不新增交易。

## 验收标准

- Web 不包含任何短信模块 UI。
- Android 断网收到短信不会产生导入候选。
- Android 可手动重扫短信。
- Android 短信页支持多选、全选/取消全选和批量导入选中候选。
- Android 设置页可学习并启用多个本地短信模板；只启用部分模板时，未启用模板对应短信不会出现在候选列表。
- 服务端日志和请求体中不出现短信原文。
- Android 模拟器或真机测试记录包含权限申请、在线导入、断网不处理、手动重扫。
