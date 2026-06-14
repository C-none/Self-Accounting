# 小小记账启动说明

本项目由 Go + SQLite 服务端和 Flutter 客户端组成。Flutter 同一套代码覆盖 Web 和 Android，Web 由 Go 服务端托管，Android 可连接本机服务端或公网服务端。

## 1. 项目边界

- 服务端：Go 单二进制 + SQLite。
- 客户端：Flutter Web + Flutter Android。
- Web 支持交易、照片、统计、基础资料管理，不支持短信扫描。
- Android 支持 Web 的全部业务功能，并额外支持短信扫描导入。
- 不支持离线新增或离线编辑。
- 金额持久化使用 `amount_cent INTEGER`，单位为分。
- 图片最终压缩由服务端 FFmpeg 完成。
- 删除采用软删除。
- 默认不依赖 Docker、Nginx、PostgreSQL、Redis。

## 2. 前置环境

在项目根目录执行：

```powershell
go version
flutter --version
ffmpeg -version
adb version
```

如果 Android 模拟器要参与验证，还需要 Android Studio 或 Android command line tools，并确认存在可用 AVD，例如 `Pixel_9_Pro`。

## 3. 本机 Web 启动步骤

以下命令默认从项目根目录 `d:\file\prog\accounting` 执行。

### 先说明启动顺序

`flutter build web` 与 `go run` 本质上是独立流程，顺序不影响程序运行成功。区别在于：

1. `flutter build web` 只负责产出静态前端文件（`client/build/web`），不依赖服务端。
2. `go run ...` 负责启动 API 并托管上一步生成的静态目录。
3. 只要 `client/build/web` 已存在，服务端启动后即可访问这些页面；反过来也一样，服务端可先起起来，再按需重构建前端。

推荐实践：

- 开发联调：先起 `go run`，再在前端改动后按需重建 Web 或使用热重载。
- 发布验证：先构建 Web，确认产物后再启动服务端，便于固定使用同一份构建产物。

### Step 1: 构建 Flutter Web

```powershell
cd client
flutter pub get
flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:8080
cd ..
```

构建结果会生成到：

```text
client/build/web
```

`config.dev.json` 已配置 Go 服务端托管这个目录。

### Step 2: 启动 Go 服务端

```powershell
go run .\server\cmd\ledger-server --config .\config.dev.json
```

成功后控制台会显示监听地址：

```text
ledger server listening on 127.0.0.1:8080
ledger web/API URL: http://127.0.0.1:8080
```

### Step 3: 打开 Web 页面

浏览器打开：

```text
http://127.0.0.1:8080
```

### Step 4: 首次配对

首次设备不会直接在页面获得配对码。

1. 在 Web 配对页点击“请求生成配对码”。
2. 回到运行服务端的命令行窗口。
3. 查看服务端打印的 `PAIRING CODE`。
4. 将该配对码输入 Web 页面。
5. 点击“完成配对”。

如果已经存在未过期、未使用的配对码，再次点击“请求生成配对码”时，服务端会重新打印同一个配对码。

### Step 5: 后续配对新设备

已配对设备进入：

```text
设置 -> 生成新设备配对码
```

此时配对码会直接显示在已配对设备页面内，也会由服务端管理当前有效配对码。

## 4. Android 模拟器启动步骤

Android 模拟器访问宿主机服务端时，API 地址必须使用：

```text
http://10.0.2.2:8080
```

### Step 1: 启动服务端

先确保服务端已按 Web 步骤启动：

```powershell
go run .\server\cmd\ledger-server --config .\config.dev.json
```

### Step 2: 启动模拟器

如果 `emulator` 已在 PATH：

```powershell
emulator -avd Pixel_9_Pro
```

如果不在 PATH，可使用本机 Android SDK 的绝对路径，例如：

```powershell
C:\Users\huzhi\scoop\apps\android-clt\current\emulator\emulator.exe -avd Pixel_9_Pro
```

确认设备在线：

```powershell
adb devices
```

应看到类似：

```text
emulator-5554    device
```

### Step 3: 构建 Android APK

```powershell
cd client
flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:8080
cd ..
```

APK 路径：

```text
client/build/app/outputs/flutter-apk/app-debug.apk
```

### Step 4: 安装并启动 APK

```powershell
adb -s emulator-5554 install -r .\client\build\app\outputs\flutter-apk\app-debug.apk
adb -s emulator-5554 shell am start -n com.example.ledger_client/.MainActivity
```

### Step 5: Android 首次配对

1. Android 配对页点击“请求生成配对码”。
2. 回到服务端命令行窗口查看 `PAIRING CODE`。
3. 在 Android 页面输入配对码。
4. 点击“完成配对”。

配对后 Android 底部导航会包含：

```text
交易 / 统计 / 短信 / 设置
```

## 5. Android 热运行方式

如果需要 Flutter 热更新调试：

```powershell
cd client
flutter run -d emulator-5554 --dart-define=LEDGER_API_BASE=http://10.0.2.2:8080
```

真机调试时，将 `10.0.2.2` 换成电脑在局域网中的 IP，例如：

```text
http://192.168.x.x:8080
```

## 6. 闭环测试环境

本项目还有一套专门用于本地闭环验证的配置：

```text
config.visual-test.json
```

它使用端口：

```text
127.0.0.1:18080
```

对应构建命令如下。

Web：

```powershell
cd client
flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:18080
cd ..
go run .\server\cmd\ledger-server --config .\config.visual-test.json
```

Android：

```powershell
cd client
flutter build apk --debug --no-pub --dart-define=LEDGER_API_BASE=http://10.0.2.2:18080
cd ..
adb -s emulator-5554 install -r .\client\build\app\outputs\flutter-apk\app-debug.apk
adb -s emulator-5554 shell am start -n com.example.ledger_client/.MainActivity
```

## 7. 常用验证命令

服务端健康检查：

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8080/api/health
```

Go 测试：

```powershell
go test ./...
```

Flutter 静态分析：

```powershell
cd client
flutter analyze
```

Flutter 单元测试：

```powershell
cd client
flutter test
```

## 8. 生产构建

Windows 服务端二进制：

```powershell
go build -trimpath -ldflags="-s -w" -o dist\ledger-server.exe .\server\cmd\ledger-server
```

Linux 服务端二进制：

```bash
go build -trimpath -ldflags="-s -w" -o dist/ledger-server ./server/cmd/ledger-server
```

Web release：

```powershell
cd client
flutter build web --release --dart-define=LEDGER_API_BASE=https://your-domain.example
```

Android release：

```powershell
cd client
flutter build apk --release --dart-define=LEDGER_API_BASE=https://your-domain.example
```

发布 APK 按 ABI 分开打包：

```powershell
flutter build apk --release --split-per-abi --dart-define=LEDGER_API_BASE=https://your-domain.example
```

产物会生成到 `client/build/app/outputs/flutter-apk/`，release 目录归档为：

```text
dist/release/android/app-armeabi-v7a-release.apk
dist/release/android/app-arm64-v8a-release.apk
dist/release/android/app-x86_64-release.apk
```

生产公网环境必须使用 HTTPS，并在配置中设置：

```json
{
  "server": {
    "require_https": true,
    "public_base_url": "https://your-domain.example"
  }
}
```

Ubuntu 发布包或已提交的 `dist/release/` 产物安装时使用 release 安装入口：

```bash
LEDGER_PUBLIC_BASE_URL=https://your-domain.example \
LEDGER_REQUIRE_HTTPS=true \
LEDGER_LISTEN_ADDR=0.0.0.0:8080 \
bash scripts/ubuntu/install-release.sh
```

兼容入口 `scripts/ubuntu/install.sh` 等同于 `install-release.sh`。开发机临时安装才使用 `install-dev.sh`，它默认读取 `dist/dev/ubuntu-amd64/ledger-server` 和 `client/build/web`，这些 dev 构建产物继续被 git 忽略。

## 9. 关键配置说明

默认开发配置文件：

```text
config.dev.json
```

关键字段：

```json
{
  "server": {
    "listen_addr": "127.0.0.1:8080",
    "public_base_url": "http://127.0.0.1:8080",
    "web_dir": "./client/build/web"
  },
  "database": {
    "path": "./var/dev/data/app.db"
  },
  "ffmpeg": {
    "path": "ffmpeg",
    "jpg_quality": 18,
    "max_width": 1600,
    "max_height": 1600
  }
}
```

## 10. 常见问题

### Web 打开 404

先执行：

```powershell
cd client
flutter build web --release --dart-define=LEDGER_API_BASE=http://127.0.0.1:8080
```

再启动服务端。

### Android 访问不了服务端

模拟器必须使用：

```text
http://10.0.2.2:8080
```

不能使用：

```text
http://127.0.0.1:8080
```

因为 Android 模拟器内的 `127.0.0.1` 指向模拟器自己。

### 页面没有直接显示配对码

这是预期行为。

未配对设备不能直接获得配对码。点击“请求生成配对码”后，请在服务端命令行窗口查看 `PAIRING CODE`。

### 图片上传或缩略图失败

检查 FFmpeg：

```powershell
ffmpeg -version
```

并确认 `config.dev.json` 中：

```json
{
  "ffmpeg": {
    "path": "ffmpeg"
  }
}
```

### 端口被占用

查看 `8080` 监听进程：

```powershell
Get-NetTCPConnection -LocalPort 8080 -State Listen
```

如果只想临时避开端口冲突，可使用 `config.visual-test.json` 的 `18080`。

## 11. 备份与迁移

不要只复制 `app.db`。

完整迁移操作手册见根目录：

```text
MIGRATION.md
```

推荐流程：

1. 在服务端执行 checkpoint 或停服。
2. 使用 `/api/admin/backup` 生成备份包。
3. 备份包应包含 `manifest.json`、`app.db`、`photos/`、`thumbnails/` 和配置导出。
4. 如果要保留已配对设备 token，单独安全迁移 `server-secret.key`。
5. 在目标 Windows 或 Ubuntu 机器恢复数据库、附件图片和缩略图目录。
6. 使用目标机器配置启动 `ledger-server`。
7. 完成 Web 和 Android 读写闭环验证，至少打开一条带附件交易确认缩略图和原图可访问。
