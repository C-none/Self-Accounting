# 服务端认证与配对模块

## 模块目标

系统不设计密码登录。认证只基于一次性配对码和设备 token。

## 配对码

`POST /api/pair/start`：

- 生成随机配对码。
- 配对码短期有效，推荐 10 分钟。
- 服务端只保存配对码 hash。
- 服务端进程内短期缓存当前明文配对码；如果请求时已有未过期、未使用的配对码，重新打印同一个配对码。
- 未配对设备调用时，HTTP 响应只返回 `delivery=server_console` 和 `expires_at`，配对码只打印到服务端命令行。
- 已配对设备调用时，HTTP 响应返回 `pairing_code`、`delivery=response` 和 `expires_at`。

`POST /api/pair/confirm`：

- 校验配对码。
- 创建设备记录。
- 生成设备 token。
- 标记配对码已使用。
- 返回 token，之后不再展示。
- 如果是首台设备，设置 `is_admin=1`。

## 设备 token

- token 明文只返回一次。
- 服务端保存 token hash。
- 客户端每次请求用 `Authorization: Bearer <token>`。
- token 可通过设备管理撤销。
- 当前设备可通过 `PATCH /api/devices/current` 修改设备名，服务端只更新当前 token 对应设备，并写入不含敏感字段的审计摘要。

hash 实现：

- 使用 `HMAC-SHA256(server_secret, value)`。
- `server_secret` 存在 `config.json` 或首次启动生成到本机配置中。
- 校验时使用常量时间比较。
- 日志只记录 `device_id`，不记录 token。

## 局域网测试

测试阶段可以：

- 使用 HTTP。
- 使用局域网 IP。
- 允许用户主动请求时在服务端控制台展示配对码。

## 公网生产

生产阶段必须：

- 使用 HTTPS。
- 配对码短期有效且一次性使用。
- 禁止在 URL 中传递 token。
- 支持撤销设备。
- 拒绝未携带 token 的业务 API。

## 验收标准

- 无密码字段和密码登录流程。
- token 明文不落库。
- 撤销设备后旧 token 立即失效。
- 生产模式未配置 HTTPS 时启动或健康检查失败。
- 首台设备不能直接从 HTTP 响应获得配对码，只能读取服务端控制台输出后完成配对并成为 admin。
- 已配对设备可在账户内部生成新设备配对码。
- 已配对设备可在设置页修改本机设备名；admin 设备可在设置页查看最近审计日志摘要。
