# 统计过滤与日周月折线闭环记录

日期：2026-06-06

## 功能切片

- 统计页增加过滤器：统计方向、使用人、分类、银行、起始日期、结束日期。
- 折线图增加粒度选择：按日、按周、按月。
- 服务端统计接口增加 `bucket=week`。
- 服务端统计接口增加 `bank_name` 过滤，用账户银行名称匹配。

## 本机服务端

- 启动方式：`go run ./server/cmd/ledger-server --config ./config.visual-test.json`
- Web 访问地址：`http://127.0.0.1:18080`
- Android 访问地址：`http://10.0.2.2:18080`
- 状态：已启动并保留运行。

## 服务端/API 验证

- `GET /api/stats/timeline?direction=expense&bucket=week&bank_name=工商银行&category_l1_id=expense_food&member_id=member_self` 返回：
  - `bucket=week`
  - 时间桶 `2026-06-01`
  - 聚合金额 `7400`
- `GET /api/stats/category?direction=expense&bank_name=工商银行&category_l1_id=expense_food&member_id=member_self` 返回：
  - 分类 `餐饮`
  - 聚合金额 `7400`
  - 占比 `100%`

## Web 测试结果

- Web release 构建通过并由本机服务端提供访问。
- Web 统计页显示新增过滤器：
  - 统计方向
  - 折线粒度
  - 使用人
  - 分类
  - 银行
  - 起始日期
  - 结束日期
- 已验证折线粒度下拉包含 `按日`、`按周`、`按月`。
- 已验证银行下拉来自账户名称，包含 `现金` 和 `工商银行`。
- 已选择 `按周 + 工商银行`，页面显示：
  - `时间趋势（按周）`
  - `餐饮 100.0% ¥74.00`
  - 周桶横轴 `2026-06-01`
- Web 已保留打开在统计页。
- 截图：
  - `docs/test-records/artifacts/stats-filter-20260606/web-stats-default.png`
  - `docs/test-records/artifacts/stats-filter-20260606/web-bucket-open.png`
  - `docs/test-records/artifacts/stats-filter-20260606/web-bank-open.png`
  - `docs/test-records/artifacts/stats-filter-20260606/web-stats-week-icbc.png`

## Android 模拟器测试结果

- 模拟器：`emulator-5554`。
- APK：`client/build/app/outputs/flutter-apk/app-debug.apk`。
- 已安装并启动当前 APK。
- 已完成统计页验证：
  - 统计方向：支出。
  - 折线粒度：可从 `按日` 切换到 `按周`。
  - 使用人：全部使用人。
  - 分类：全部分类。
  - 银行：可选择 `工商银行`。
  - 日期过滤控件存在。
- 已选择 `按周 + 工商银行`，页面显示：
  - `餐饮 100.0% ¥74.00`
  - `时间趋势（按周）`
- Android 模拟器和 App 已保留运行。
- 截图：
  - `docs/test-records/artifacts/stats-filter-20260606/android-stats-filter-icbc-top.png`
  - `docs/test-records/artifacts/stats-filter-20260606/android-stats-filter-icbc-timeline.png`
  - `docs/test-records/artifacts/stats-filter-20260606/android-stats-filter-icbc-final.png`

## 构建与自动化验证

- `go test ./...` 通过。
- `flutter analyze` 通过。
- `flutter test` 通过。
- `flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18080` 通过。
- `flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080` 通过。

## 未测试项及原因

- 未实现多条折线同时对比多个使用人、分类或银行；本切片实现的是通过过滤器切换单条聚合折线。TODO 已记录后续多序列对比。
- 备份/checkpoint、交易编辑、软删除和照片上传未在本切片重复完整回归；本次闭环聚焦统计过滤和折线粒度。

## 发现并修复的问题

- 服务端折线统计原先只支持 `day/month`，已增加 `week`。
- 客户端统计页原先只透传 `direction`，已透传成员、分类、银行、日期范围和粒度。
- 统计页原先没有过滤 UI，已在 Android 和 Web 共用页面补齐。
