# KONG 账号服务（Account）

P3a：给玩家**持久账号**（跨会话/跨房间）——设备匿名注册、昵称、持久战绩。**方案 A：独立 HTTP/JSON 服务**，只存"身份+战绩"，**不接触牌局牌面**。

## 运行
```bash
python3 account.py --port 8090 --data accounts.json
```
零依赖（Python 3 标准库）。参数：
- `--port`（默认 8090）
- `--data`（账号数据文件，默认 `accounts.json`；原子写）
- `--rate`（每 IP 每 60s 请求上限，默认 30）

## 接口（POST，JSON）
| 路径 | 请求 | 响应 |
| --- | --- | --- |
| `/register_device` | `{"name"?: "小明"}` | `{"account_id":"acc_...","secret":"..."}` |
| `/login` | `{"account_id":"acc_...","secret":"..."}` | `{"account_id","name","stats"}` 或 `{"error":"AUTH_FAILED"}` |
| `/set_name` | `{"account_id","secret","name"}` | `{"ok":true}` |
| `/get_profile` | `{"account_id"}` | `{"account_id","name","stats"}` |
| `/steam_auth` | `{"account_id","secret","ticket"}` | `{"ok":true,"steam_id","owner"}` 或 `{"error":"STEAM_AUTH_FAILED"}` |
| `GET /health` | — | `{"ok":true,"accounts":N}` |

**Steam 校验（P3b，桩先行）**：`--steam-webapi-key <KEY> --steam-appid <ID>` 有 key → 真校验（调 Steam Web API `AuthenticateUserTicket`）；无 → `MockVerifier`（`ticket="mock:<steamid>"` 通过）。Client sends its Steam auth ticket; server binds `account↔steam_id`.

- `account_id`/`secret` 由服务端签发；客户端存 `user://account.cfg`，之后 `login`。
- 错误：`AUTH_FAILED` / `RATE_LIMITED`(429) / `BAD_REQUEST`。

## 测试
```bash
python3 test_account.py    # 注册/登录/昵称/战绩/持久化/限速
```

## 部署（VPS）
1. 放行 **TCP 8090**（云安全组 + `sudo ufw allow 8090/tcp`）。
2. systemd 常驻：见 `kong-account.service`（改路径/用户/端口）。
3. 客户端设置"账号地址" = `http://<VPS公网IP>:8090`。

> 参数待填：实例架构/OS/公网 IP/域名（可选）/SSH。持久数据建议放稳定路径（如 `/var/lib/kong/accounts.json`）。
