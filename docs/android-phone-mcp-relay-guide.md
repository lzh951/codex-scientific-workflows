# Android 手机 MCP 中继/断线重连说明（公开版）

> 这是一份可公开发布的说明。已移除所有敏感信息（Owner Token、实际设备 ID、真实公网 URL）。

## 1. 结论先说

1. `trycloudflare` 这类临时隧道的 MCP URL 不是稳定地址，进程/网络/重启会变。
2. 如果 ChatGPT 里看到 `Phone is not connected`、`502`、`401 Unauthorized`，多数不是“手机坏了”，而是：
   - 链接未更新
   - 令牌/授权不同步
   - 连接器未重新绑定
3. 你在手机界面看到的按钮文案可能不同，最终判断要看状态字段，不看按钮文字。

## 2. MCP 链路组件（公开版）

- 手机 MCP App 本地服务：`<手机 IP>:7676`（通常通过手机 `localhost` 暴露）
- 公网中继（可选）：`https://<随机>.trycloudflare.com/d/<device-id>/mcp`
- ChatGPT 自定义应用（App）：`Android Phone Files MCP`（名字你可按你当前命名）

## 3. 什么时候会变化

`trycloudflare` 为 quick tunnel，官方说明是随机子域名，主要用于测试，不是生产：
- 重启 cloudflared 后可能换域名
- App/进程重连后可能换域名
- 电脑重启、服务重装、参数变更也可能换域名
- 网络环境抖动导致隧道会话重建也可能换域名

官方文档：
- Quick tunnel（随机 `*.trycloudflare.com`）：`https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/`
- 建生产隧道（固定 hostname）：`https://developers.cloudflare.com/tunnel/setup/`

## 4. 你应该优先使用的判断顺序

### 4.1 手机端检查
1. App 是否在前台/运行，端口服务是否起
2. 中继状态是否显示 `connected`（或等效中文状态）
3. 允许目录是否为 `/storage/emulated/0`（或你确认的范围）
4. 复制并保存“当前的公共 MCP URL”

### 4.2 ChatGPT 端检查
1. 打开 Apps/自定义应用页确认：
   - 应用已连接
   - URL 是否与你刚复制的一致
2. 用测试问题快速验证：
   - `列出 /storage/emulated/0/Download`
3. 如果报 401：先看是不是 token/授权过期，必要时重授权

## 5. 30 秒自检（适配“你手机 UI 与我这边有差异”）

只看状态字段，不看按钮名字：

1. 看“服务状态”：出现 `running on port 7676`（或等价运行状态）就算服务已起
2. 看“Relay status / 中继状态”：出现 `connected` 就算连上中继
3. 看“Phone-direct public MCP URL”：复制完整地址
4. 回 ChatGPT 执行一条目录测试

## 6. 链路变更/重建策略

### 6.1 仅地址变了
- 手机端重新复制新 URL
- 更新 ChatGPT 中的自定义应用 URL（官方现状下通常更稳妥是新建应用）
- 用新应用做一次目录验证

### 6.2 报 401
- 检查 owner token 是否过期或授权失效
- 按流程重走授权
- 不要在公开场合发布真实 token

### 6.3 频繁断线
- 让 App 保持后台运行（忽略电池优化、允许自启动）
- 避免频繁关闭/清理应用
- 不依赖本机 USB 线维持长期连接

## 7. 公开可操作的目录建议（去隐私版）

常见可处理范围（示例）：
- `Download`
- `Documents`
- `DCIM`
- `Pictures`
- `Movies`
- `Music`
- `Movies`
- `Documents` 内子目录

常见建议不直接动的范围（除非确认）：
- App 私有目录（如 `/Android/*`）
- 关键系统配置目录
- 隐藏配置目录（以 `.` 开头）

## 8. 推荐的稳定方案（简版）

若你希望“尽量少改 URL”：
1. 用正式 Cloudflare Tunnel（固定 hostname）替代随机 quick tunnel
2. 统一中继地址策略，尽量避免中间层变更

## 9. 常用故障快速清单

| 现象 | 最可能原因 | 处理 |
|---|---|---|
| ChatGPT 显示 `Phone is not connected` | 地址旧了/连接器未更新 | 重新复制公共 URL 并更新连接器 |
| 返回 `502` | 隧道会话不可达/公网隧道异常 | 手机端检查 relay，必要时重启隧道 |
| 返回 `401` | token / 授权未对齐 | 重新授权（不公开 token） |
| 手机端显示 running 但无法访问 | App URL 未更新到 ChatGPT | 逐步同步手机 URL 与 ChatGPT 配置 |

## 10. 敏感信息清理规则（上传前）

- 不发布：
  - owner token
  - 真实 `/d/<device-id>/mcp` 中的 `device-id`
  - 真实公共 `trycloudflare` 完整地址
- 可发布：
  - 流程步骤
  - 报错码和对应处理逻辑
  - 目录策略和安全边界说明

