# Flutter 客户端架构

## 技术路线

客户端强制使用 Flutter 单代码库，覆盖：

- Android App。
- Web App。

目标是最大化 Android 与 Web 的 UI、状态、领域模型和 API 复用，同时通过平台 adapter 隔离短信、摄像头、文件选择、后台监听等差异。

同等功能下优先目标：

- Android App 冷启动快。
- Flutter Web 首屏下载少、打开快。
- 依赖数量少、包体积小。
- UI 安静、密集、直接服务记账功能，不做装饰性视觉设计。

## 分层结构

```text
lib/
  app/
    routing/
    theme/
    shell/
  domain/
    models/
    value_objects/
    validators/
  data/
    api/
    dto/
    repositories/
  state/
    auth/
    transactions/
    statistics/
    settings/
  features/
    transactions/
    sms/
    photos/
    statistics/
    settings/
  platform/
    platform_adapter.dart
    android/
    web/
```

首版推荐状态管理保持简单：

- 使用 Flutter SDK 自带 `ChangeNotifier`、`ValueNotifier` 或轻量 repository stream。
- 不引入大型状态管理框架，除非后续复杂度证明需要。
- 所有页面按 feature 分包，但首屏只初始化 auth、server settings 和 bootstrap 必要数据。

当前 Phase 0-3 实现采用 `lib/src/` 下的轻量结构：`api_client.dart`、`app_controller.dart`、`models.dart`、`pages/`、`sms/` 和 `widgets/`。后续模块增多时再按上面的完整分层拆分。

## 复用策略

必须共享：

- 交易表单。
- 交易列表。
- 过滤器。
- 交易详情页。
- 统计图表页。
- API client。
- 领域模型和校验。
- 金额格式化：输入 RMB，提交 `amount_cent`；展示 `amount_cent / 100`。

平台差异只放在 `platform/`：

- Android 短信权限、短信后台监听、历史短信扫描。
- Android 摄像头能力。
- Web 文件选择能力。
- 通知和后台行为。

依赖准入：

- 图表首版自绘，不默认引入 `fl_chart`。
- 短信首版使用 platform channel 调 Android 原生 API，不默认引入短信读取插件。
- 图片选择使用 Flutter 官方维护的 `image_picker`，用于 Android 拍照/相册和 Web 文件选择。
- `crypto` 仅用于 Android 本地计算 `sms_hash`，服务端不接收短信原文。
- 不引入第三方图标包、字体包、动画包、营销页组件库。
- 当前依赖 `http` 用于 Android/Web 共用 REST API client；依赖 `flutter_secure_storage` 用于保存设备 token。Web 端安全存储只用于 localhost 或 HTTPS 环境。
- Android 短信模板也使用 `flutter_secure_storage` 保存脱敏 JSON；模板只保存在本机，不进入服务端或 Web。

## 在线写入原则

客户端不支持离线新增或离线编辑：

- 无网络时新增、编辑、删除、上传照片直接失败。
- UI 给出明确提示：当前无网络，请联网后重试。
- 客户端可缓存最近读取的数据用于显示，但缓存数据不可编辑提交。

## 配对与认证

Flutter 客户端启动后：

1. 读取本地保存的服务地址；没有保存值时使用编译期 `LEDGER_API_BASE`，Web 仍可回落到同源服务。
2. 检查本地是否有 `device_token`。
3. 没有 token 时进入配对页。
4. 配对页允许手动输入服务 IP/主机和端口，保存后再请求或确认配对码。
5. 用户可点击“请求生成配对码”，未配对客户端只收到 `delivery=server_console`，页面不展示配对码。
6. 用户从服务端命令行读取配对码并输入。
7. 调用 `POST /api/pair/confirm`。
8. 保存 `device_id` 和 `device_token`。
9. 后续 API 自动携带 bearer token。

已配对设备可在设置页生成新设备配对码；此时客户端携带 token，服务端可在响应中返回明文配对码。

Web 端 token 存储在浏览器本地安全存储策略中；Android 端存储在平台安全存储中。

Android Manifest 首版设置：

- `android.permission.INTERNET` 用于访问本机或公网服务端。
- `android.permission.CAMERA` 用于拍照上传附件。
- `android.permission.ACCESS_NETWORK_STATE` 用于短信广播接收时判断当前是否在线；该权限无运行时弹窗。
- `android.permission.READ_SMS` 和 `android.permission.RECEIVE_SMS` 仅用于 Android 私有包的短信导入。
- `android:usesCleartextTraffic="true"` 仅支持本机/局域网 HTTP 测试；生产公网仍必须走 HTTPS。
- `android:allowBackup="false"` 和 `android:fullBackupContent="false"`，避免系统备份复制本机 token。

## 页面导航

主要页面：

- 交易列表。
- 新增交易。
- 交易详情/编辑。
- 短信导入候选列表（Android only）。
- 统计。
- 设置。
- 基础资料管理页：从设置页进入，可新增、编辑、删除和调整分类、使用人、账户显示顺序；账户按银行名称和可选银行卡尾号维护；删除调用服务端软删除 API；顺序通过服务端 `sort_order` 持久化并在 Web/Android 一致生效。

设置页同时提供当前服务地址修改、当前设备名修改和最近审计日志查询。服务地址在卡片内按 IP/主机和端口输入并保存到本机安全存储，保存后后续请求使用新地址，不在编辑控件退出时触发 bootstrap 刷新；HTTPS 地址回填到编辑框时必须保留 `https://`，未显式填写 scheme 且端口为 443 时按 HTTPS 规范化，避免 Android 重启后把公网 HTTPS 服务误保存为 `http://host:443`；设备名修改调用当前设备接口并刷新 bootstrap；日志查询仅 admin 设备显示，列表默认展示时间、动作、实体和设备名，可展开单条日志查看日志 ID、实体 ID、设备 ID、原始动作和原始实体类型，不展示审计 payload、token、配对码或短信正文。

Android 设置页额外提供“短信模板”入口；Web 不展示。模板页按账户和发送号码手动维护本地短信模板，支持新增、编辑、启用、停用和删除。模板语法使用 `{amount}` 这类大括号字段标记需要提取的内容，页面展示规则、示例和可选字段词。

Web 构建产物由 Go 服务端托管。生产环境中 Flutter Web 不单独部署。

## 响应式布局

- Android 和窄屏 Web 保持底部 `NavigationBar`。
- 桌面 Web 使用左侧 `NavigationRail`，宽屏时展开文字标签。
- 桌面断点按逻辑像素设置，需兼容 Windows/浏览器缩放后 1440px 视口只剩约 720 逻辑像素的情况。
- 页面主体不直接铺满浏览器宽度；交易列表、统计页等使用居中最大宽度，表单使用较窄最大宽度。
- 表单在宽屏下使用两列字段栅格，在手机和窄屏下回落为单列。
- 不为响应式改造新增第三方 UI 包、字体或图标依赖。

## 平台功能开关

客户端启动时根据平台能力启用功能：

| 功能 | Android | Web |
| --- | --- | --- |
| 新增交易 | 启用 | 启用 |
| 编辑交易 | 启用 | 启用 |
| 照片上传 | 启用 | 启用 |
| 短信扫描 | 启用 | 禁用 |
| 后台监听短信 | 启用 | 禁用 |
| 手动重扫短信 | 启用 | 禁用 |

Web 页面不得展示短信扫描入口。

短信导入页面只在服务端 bootstrap 返回 `features.sms=true` 时进入导航。Web 设备的该开关固定为 false；Android 设备进入页面后仍需用户主动授权并点击“重新扫描”才会读取历史短信。导入前可按解析后的交易日期和银行名称过滤候选；银行名称来自已创建账户。Android 历史扫描查询本机 `content://sms`，以覆盖不同厂商对 inbox/all 视图的差异；后台广播只进入进程内候选队列，不写本地离线队列。页面提供“清除本机短信隐藏记录”操作，仅删除 Android 本机 `sms_imported_hashes_v1` 缓存，方便重新扫描此前被隐藏的候选；该操作不删除服务端交易、本机模板或设备 token。若扫描后没有候选，页面只显示读取行数、95588 行数、正文非空行数、模板匹配数、候选数和隐藏数等本机诊断计数，不显示、不上传短信正文。

Android 短信解析先按 `sender_normalized + account_id` 匹配本地已启用手动模板；一个号码和账户可维护多个模板。未匹配启用模板的短信直接忽略，不生成候选。匹配后客户端按模板大括号字段提取金额、余额、短信明文时间占位、商户、银行卡尾号、银行名和方向等结构化字段；其中 `{date_time}` 只用于模板匹配，交易时间统一使用 Android SMS provider 的收到短信时间。模板只保存在本机，不进入服务端或 Web。服务端 `POST /api/sms/imports` 接口保持只接收结构化结果。

## 构建与启动速度

Android release 构建：

```powershell
flutter build apk --release --analyze-size
```

多 ABI APK 无法直接执行 size analyze 时，使用：

```powershell
flutter build apk --release --target-platform android-arm64 --analyze-size
```

Web release 构建：

```powershell
flutter build web --release
flutter build web --release --wasm
```

当前 Flutter 3.44.0 的 `flutter build web` 不支持 `--analyze-size`，Web 体积用 `build/web` 目录和关键文件大小记录。

性能要求：

- App 启动后先显示配对页或交易列表骨架，再加载统计和附件缩略图。
- 交易列表分页加载，默认每页 50 条。
- 交易列表按日期分组展示，同一天交易可以通过日期分界线折叠。
- 交易列表记录内第一排显示分类，第二排显示交易对象、详细描述和账户信息，第三排显示使用人和不含日期的交易时间。
- 统计页进入时再请求统计 API，不在启动时预取。
- 附件缩略图懒加载，列表默认不加载原图。
- 不使用启动页动画、全屏背景图、自定义字体下载或复杂转场。
