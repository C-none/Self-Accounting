# 统计比较属性与二级分类过滤闭环记录

## 功能切片

- 统计页增加二级分类过滤。
- 统计页增加比较属性：一级分类、二级分类、使用人、银行，默认一级分类。
- 饼图按比较属性显示占比。
- 折线图按比较属性绘制多条颜色序列。
- 比较属性与同属性过滤互斥：
  - 按一级分类比较时隐藏一级分类和二级分类过滤。
  - 按二级分类比较时保留一级分类过滤，隐藏二级分类过滤。
  - 按使用人比较时隐藏使用人过滤。
  - 按银行比较时隐藏银行过滤。

## 本机服务端

启动方式：

```powershell
go run .\server\cmd\ledger-server --config .\config.dev.json
```

访问地址：

```text
http://127.0.0.1:8080
```

测试数据通过正式 API 写入，统计趋势接口返回：

```text
compare_by=category_l1
bucket=day
series_count=3
```

## 自动化检查

```powershell
go test ./...
flutter analyze
flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:8080
```

结果：

- `go test ./...` 通过。
- `flutter analyze` 无问题。
- Web release 构建成功。

Android APK 构建命令：

```powershell
flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:8080
```

该命令两次未在工具超时前返回，但 `client/build/app/outputs/flutter-apk/app-debug.apk` 已更新，并成功安装到模拟器。

## Web 测试结果

测试方式：

- 使用本机 Chrome 打开 `http://127.0.0.1:8080`。
- 通过页面完成 Web 配对。
- 进入统计页。
- 验证默认比较属性为一级分类。
- 切换比较属性为二级分类。

验证结果：

- 默认 `compare_by=category_l1`，趋势接口返回 3 条序列。
- 切换后 `compare_by=category_l2`，趋势接口返回 5 条序列。
- Web 截图显示默认按一级分类绘制饼图和多折线。
- Web 截图显示按二级分类比较时，一级分类过滤保留，二级分类过滤隐藏。

截图：

- `docs/test-records/artifacts/stats-comparison-web-default.png`
- `docs/test-records/artifacts/stats-comparison-web-compare-menu.png`
- `docs/test-records/artifacts/stats-comparison-web-category-l2.png`

## Android 模拟器测试结果

模拟器：

```text
emulator-5554
```

安装与启动：

```powershell
adb -s emulator-5554 install -r .\client\build\app\outputs\flutter-apk\app-debug.apk
adb -s emulator-5554 shell am start -n com.example.ledger_client/.MainActivity
```

验证结果：

- Android 统计页可打开。
- 当前按使用人比较时，一级分类、二级分类和银行过滤可见，使用人过滤隐藏。
- 切换为一级分类比较后，一级分类和二级分类过滤隐藏，使用人和银行过滤保留。
- 切换为二级分类比较后，一级分类过滤保留，二级分类过滤隐藏，使用人和银行过滤保留。
- 饼图标题随比较属性更新为 `占比统计（一级分类）` / `占比统计（二级分类）`。

截图：

- `docs/test-records/artifacts/stats-comparison-android-filter-top.png`
- `docs/test-records/artifacts/stats-comparison-android-category-l1.png`
- `docs/test-records/artifacts/stats-comparison-android-category-l2.png`

## 未测试项及原因

- 未重复执行照片上传、FFmpeg 压缩、备份/checkpoint、短信导入完整闭环；本切片只改统计 API 与统计 UI。
- 未执行 Ubuntu Linux 恢复流程；本切片不涉及备份迁移和平台路径。

## 发现并处理的问题

- Web Flutter 页面没有暴露普通 DOM 控件，改用 Playwright + 本机 Chrome 坐标驱动并结合统计接口响应验证。
- Android 下拉项坐标受滚动状态影响，改为先用 UI tree 读取选项 bounds，再点击中心点。
- PowerShell 测试数据脚本首次使用了错误的时间转换写法，改为 `[DateTimeOffset]::Parse(...).ToUnixTimeSeconds()` 后重新写入数据。

## 折线点数值补充验证

后续补充需求：折线图上每个点直接保留金额数值。

实现结果：

- 共享 `TimelineLineChart` 在每个折线点旁绘制 `formatMoney(amount_cent)`。
- Web 与 Android 共用同一 `CustomPainter`，两端同时生效。
- 缺失时间桶补出的 0 点也显示 `¥0.00`，与当前图上实际绘制点保持一致。

补充验证：

```powershell
flutter analyze
flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:8080
flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:8080
adb -s emulator-5554 install -r .\client\build\app\outputs\flutter-apk\app-debug.apk
```

结果：

- `flutter analyze` 无问题。
- Web release 构建成功。
- Android debug APK 构建成功。
- Android 首次安装新 APK 时模拟器返回 `INSTALL_FAILED_INSUFFICIENT_STORAGE`，执行 `adb -s emulator-5554 shell pm trim-caches 2G` 后安装成功。
- Web 截图确认每个折线点旁显示金额。
- Android 截图确认每个折线点旁显示金额。

截图：

- `docs/test-records/artifacts/stats-point-values-web.png`
- `docs/test-records/artifacts/stats-point-values-android.png`
