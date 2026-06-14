# Release 打包与 Ubuntu 脚本记录

## 功能切片

- 清理本地生成产物。
- 清空本机 dev 数据库、附件目录和 dev server secret。
- 构建 release 服务端、Flutter Web、Android APK。
- 生成 Ubuntu 可运行安装、迁入、迁出、启动、关闭脚本。
- 生成 Ubuntu release 包。

## 清理与数据库状态

已停止 `127.0.0.1:8080` 上的本机 `go run` 服务。

已删除并重建：

- `var/dev`
- `dist`
- `client/build`

清理后确认：

```text
var/dev/data/app.db 不存在
```

## 新增脚本

源码位置：

- `scripts/ubuntu/install.sh`
- `scripts/ubuntu/start.sh`
- `scripts/ubuntu/stop.sh`
- `scripts/ubuntu/db-export.sh`
- `scripts/ubuntu/db-import.sh`

发布包内位置：

```text
dist/release/ledger-node-ubuntu-amd64/scripts/ubuntu/
```

脚本默认安装目录：

```text
/opt/ledger-node
```

## 构建命令

Go 测试：

```powershell
go test ./...
```

Windows 服务端：

```powershell
go build -trimpath -ldflags="-s -w" -o dist\release\windows-amd64\ledger-server.exe .\server\cmd\ledger-server
```

Ubuntu amd64 服务端：

```powershell
$env:GOOS='linux'; $env:GOARCH='amd64'; $env:CGO_ENABLED='0'
go build -trimpath -ldflags="-s -w" -o dist\release\ubuntu-amd64\ledger-server .\server\cmd\ledger-server
```

Flutter Web：

```powershell
cd client
flutter pub get
flutter build web --release --no-wasm-dry-run
```

Android release APK：

```powershell
cd client
flutter build apk --release --no-pub
```

## 产物

```text
dist/release/windows-amd64/ledger-server.exe
dist/release/ubuntu-amd64/ledger-server
dist/release/web/
dist/release/android/app-release.apk
dist/release/ledger-node-ubuntu-amd64/
dist/release/ledger-node-ubuntu-amd64.tar.gz
dist/release/ledger-node-ubuntu-amd64.zip
```

产物大小：

```text
ledger-server.exe: 10,998,272 bytes
ledger-server: 10,666,146 bytes
app-release.apk: 54,345,764 bytes
ledger-node-ubuntu-amd64.tar.gz: 43,831,303 bytes
ledger-node-ubuntu-amd64.zip: 44,942,190 bytes
```

## 验证

- `go test ./...` 通过。
- Flutter Web release 构建成功。
- Android release APK 构建成功。
- 使用隔离临时目录启动 `dist/release/windows-amd64/ledger-server.exe`，`GET /api/health` 返回 `status=ok`、`journal_mode=wal`。

未完成：

- 本机未安装可用 WSL Linux 发行版，`bash -n scripts/ubuntu/*.sh` 无法执行；Ubuntu 脚本未在真实 Ubuntu 环境运行。
- 未执行 release APK 真机安装；本次只构建 release APK。

## 文档同步

- `agents.md` 已说明 `scripts/ubuntu/` 脚本属于发布运维接口，后续更新应尽可能保持文件名、参数和环境变量兼容。
- `docs/architecture/deployment-backup-migration.md` 已记录 Ubuntu 脚本用途和环境变量。
- `MIGRATION.md` 已补充 Ubuntu 发布脚本迁移流程。
