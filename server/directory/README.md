# KONG 中心房间目录服务（Directory）

P2 阶段：把"输 IP:端口"变成"**建房拿码、输码加入**"。本服务是方案 A——**独立 HTTP/JSON 服务**，只管"短码 ↔ 房间地址"的登记与查询，**不接触牌局数据**。

## 运行
```bash
python3 directory.py --port 8080
```
零依赖（Python 3 标准库）。可选参数：
- `--port`（默认 8080）
- `--ttl`（码有效期秒数，默认 1800 = 30min；仅限制"用码加入"，与房间存活/断线重连无关）
- `--heartbeat-timeout`（心跳超时秒数，默认 30；宿主停跳即回收码）
- `--rate`（每 IP 每 60s 允许的请求数，默认 10；防码枚举）

## 接口（POST，JSON）
| 路径 | 请求 | 响应 |
| --- | --- | --- |
| `/create_room` | `{"port":7007,"mode":"dedicated","max_players":4}` | `{"code":"K7X2Q9","expires_in":1800}` |
| `/join_room` | `{"code":"K7X2Q9"}` | `{"host":"1.2.3.4","port":7007,"mode":"dedicated"}` 或 `{"error":"ROOM_NOT_FOUND"}` |
| `/heartbeat` | `{"code":"K7X2Q9"}` | `{"ok":true}` |
| `/close_room` | `{"code":"K7X2Q9"}` | `{"ok":true}` |
| `GET /health` | — | `{"ok":true,"rooms":N}` |

- **房间地址 = 请求方的公网源 IP**（`client_address[0]`）+ 上报的 `port`；宿主无需自探测公网 IP。
- 错误：`ROOM_NOT_FOUND` / `RATE_LIMITED`(HTTP 429) / `BAD_REQUEST`。

## 测试
```bash
python3 test_directory.py     # 纯逻辑单测（码/join/close/心跳/TTL/限速）
```

## 部署（VPS）
1. 放行 **TCP 8080**（Oracle 云 Security List/NSG + 系统 `sudo ufw allow 8080/tcp`）。
2. systemd 常驻：见 `kong-directory.service`（按需改路径/端口/用户）。
   ```bash
   sudo cp kong-directory.service /etc/systemd/system/
   sudo systemctl enable --now kong-directory
   ```
3. 客户端游戏内设置"目录地址" = `http://<VPS公网IP>:8080`。

> 参数待填：实例架构（x86_64/ARM）、OS 版本、公网 IP、域名（可选）、SSH 方式。
> 安全：目录会暴露房间的 `host:port`（玩家/服务器 IP）；如需隐藏 IP 需中继（非本期）。
