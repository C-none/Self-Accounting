# 图片压缩、银行尾号账户与短信导入过滤闭环记录

日期：2026-06-06

## 功能切片

- 降低服务端照片压缩损耗，提升含文字图片细节可读性。
- 账户按“银行名称 + 可选银行卡尾号”展示和匹配。
- Android 短信导入前增加交易日期范围与导入银行过滤。
- 短信解析支持银行名、尾号、短信正文交易时间、复杂商户名和带逗号余额字段。

## 本机服务端

- 启动方式：`go run ./server/cmd/ledger-server --config ./config.visual-test.json`
- 访问地址：`http://127.0.0.1:18080`
- Android 访问地址：`http://10.0.2.2:18080`
- 状态：已启动并保留运行。

## Web 测试结果

- Flutter Web release 已构建并由本机服务端提供访问。
- 交易页可读取服务端数据。
- 已验证上传图片后的交易行在金额左侧显示缩略图。
- 已验证账户展示为银行名加尾号，例如“工商银行 尾号0973”。
- 已验证 Web 端没有短信扫描入口。
- 截图：`docs/test-records/artifacts/feature-bank-sms-photo-20260606/web-transaction-bank-thumbnail.png`

## Android 模拟器测试结果

- 模拟器：`emulator-5554`。
- APK：`client/build/app/outputs/flutter-apk/app-debug.apk`。
- 已安装并启动当前 APK。
- 已完成设备配对并连接本机服务端。
- 交易页可读取服务端数据。
- 已验证图片交易行显示右侧缩略图，且账户展示“工商银行 尾号0973”。
- 已验证 Android 端存在“短信”入口，Web 端无该入口。
- 短信导入页已验证：
  - 起始日期过滤。
  - 结束日期过滤。
  - 导入银行过滤，银行列表来自已创建账户名称。
  - 选择“工商银行”后重新扫描模拟短信。
  - 候选结果匹配尾号 `0973`、银行 `工商银行`、交易时间 `2026-06-06 10:31`、金额 `¥37.00`。
  - 余额字段未被误识别为交易金额。
- Android 应用和模拟器已保留运行，当前停在短信导入页。
- 截图：
  - `docs/test-records/artifacts/feature-bank-sms-photo-20260606/android-transaction-bank-thumbnail.png`
  - `docs/test-records/artifacts/feature-bank-sms-photo-20260606/android-sms-filters.png`
  - `docs/test-records/artifacts/feature-bank-sms-photo-20260606/android-sms-bank-filter-open.png`
  - `docs/test-records/artifacts/feature-bank-sms-photo-20260606/android-sms-icbc-candidate-final.png`

## 服务端与单元测试

- `go test ./...` 通过。
- `flutter analyze` 通过。
- `flutter test` 通过。
- `flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18080` 通过。
- `flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080` 通过。

## 数据与安全检查

- 金额仍使用 `amount_cent` 写入，测试金额 `37.00` 对应 `3700`。
- 短信导入服务端只接收结构化交易字段，不上传短信原文。
- 账户尾号按最多 4 位数字保存，不记录完整银行卡号。
- 本次测试记录不包含设备 token、配对码或短信原文。

## 未重复覆盖项

- 备份/checkpoint、统计图表细节、交易编辑和软删除未在本切片中重复执行完整回归；本次闭环聚焦图片压缩、交易页缩略图、账户银行尾号匹配和短信导入过滤。

## 发现并修复的问题

- 图片压缩默认质量过低，已改为更保守的服务端压缩参数，并提高缩略图尺寸。
- 账户创建过度依赖显式账户类型，已允许账户表单默认创建银行账户。
- 银行卡尾号未标准化，已统一提取最多 4 位数字。
- 短信解析会被余额金额干扰，已跳过余额、剩余、可用余额等上下文金额。
- 短信导入缺少导入前过滤，已增加日期范围和银行过滤。
