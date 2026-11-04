#!/usr/bin/env python3
"""KONG 中心房间目录服务（P2 · 方案A：独立 HTTP/JSON 服务）。

职责：登记房间地址、分配随机短码、查询 / 心跳 / 回收。**不接触牌局数据**。
房间地址 = HTTP 请求方的公网源 IP（宿主无需自探测公网 IP）+ 其上报端口。

运行：
    python3 directory.py --port 8080
接口（POST，JSON）：
    /create_room  {port, mode, max_players} -> {code, expires_in}
    /join_room    {code}                    -> {host, port, mode} | {error}
    /heartbeat    {code}                    -> {ok}
    /close_room   {code}                    -> {ok}
    GET /health                             -> {ok, rooms}
错误码：ROOM_NOT_FOUND / RATE_LIMITED / BAD_REQUEST
"""
import argparse
import json
import random
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Crockford base32：去易混字符 I/L/O/U
ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
CODE_LEN = 6
IDLE = "idle"               # 池实例：可被分配，不可加入
RESERVED = "reserved"       # 已被某次创建占用，等玩家连入
IN_USE = "in_use"           # 正常房间
RESERVE_TIMEOUT = 30        # 预约超时（秒）：超时无人连入则回 idle（码不变）
DEFAULT_TTL = 1800          # 码 TTL（秒）= 30min：仅限制"用码加入"，与房间存活/重连无关
DEFAULT_HB_TIMEOUT = 30     # 心跳超时（秒）：宿主停跳即视为失效
DEFAULT_RATE = 10           # 每 IP 窗口内允许的请求数
RATE_WINDOW = 60            # 限速窗口（秒）


class DirectoryStore:
    """内存房间目录（纯逻辑，可注入 now 便于单测；线程安全）。"""

    def __init__(self, ttl=DEFAULT_TTL, hb_timeout=DEFAULT_HB_TIMEOUT, reserve_timeout=RESERVE_TIMEOUT):
        self.ttl = ttl
        self.hb_timeout = hb_timeout
        self.reserve_timeout = reserve_timeout
        self._rooms = {}  # code -> {host, port, mode, max_players, created, last_seen}
        self._lock = threading.Lock()

    def _new_code(self):
        while True:
            code = "".join(random.choice(ALPHABET) for _ in range(CODE_LEN))
            if code not in self._rooms:
                return code

    def sweep(self, now=None):
        """回收：心跳超时 或 码 TTL 过期。返回被移除的码列表。"""
        now = time.time() if now is None else now
        removed = []
        for code, r in list(self._rooms.items()):
            if now - r["last_seen"] > self.hb_timeout or now - r["created"] > self.ttl:
                del self._rooms[code]
                removed.append(code)
                continue
            if r["state"] == RESERVED and now - r["reserved_at"] > self.reserve_timeout:
                r["state"] = IDLE
                r["reserved_at"] = 0
        return removed

    def create(self, host, port, mode, max_players, now=None, code=None, state=IN_USE):
        now = time.time() if now is None else now
        with self._lock:
            self.sweep(now)
            if code:
                c = str(code).strip().upper()
                if not self._valid_code(c):
                    return None  # 自定义码非法
                code = c
                # 固定码：同码重登记视为"接管"（宿主重启后沿用同码）
            else:
                code = self._new_code()
            self._rooms[code] = {
                "host": host,
                "port": int(port),
                "mode": str(mode),
                "max_players": int(max_players),
                "state": state if state in (IDLE, RESERVED, IN_USE) else IN_USE,
                "created": now,
                "last_seen": now,
                "reserved_at": 0,
                "last_alloc": 0,
            }
            return code

    def allocate(self, now=None):
        """池分配：选最久未分配的 idle → 置 reserved。无可用房 → None。"""
        now = time.time() if now is None else now
        with self._lock:
            self.sweep(now)
            idle = [c for c, r in self._rooms.items() if r["state"] == IDLE]
            if not idle:
                return None
            idle.sort(key=lambda c: self._rooms[c]["last_alloc"])
            code = idle[0]
            r = self._rooms[code]
            r["state"] = RESERVED
            r["reserved_at"] = now
            r["last_alloc"] = now
            return {"code": code, "host": r["host"], "port": r["port"]}

    def stats(self):
        with self._lock:
            idle = sum(1 for r in self._rooms.values() if r["state"] == IDLE)
            busy = sum(1 for r in self._rooms.values() if r["state"] != IDLE)
            return {"rooms": len(self._rooms), "idle": idle, "busy": busy}

    @staticmethod
    def _valid_code(code):
        # 自定义/固定码：允许完整 A-Z0-9（长度 3..16）。join 时会统一大写。
        if not (3 <= len(code) <= 16):
            return False
        return all(ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" for ch in code)

    def join(self, code, now=None):
        now = time.time() if now is None else now
        with self._lock:
            self.sweep(now)
            r = self._rooms.get(str(code).strip().upper())
            if r is None or r["state"] == IDLE:
                return None
            r["state"] = IN_USE
            r["reserved_at"] = 0
            return {"host": r["host"], "port": r["port"], "mode": r["mode"]}

    def heartbeat(self, code, now=None):
        now = time.time() if now is None else now
        with self._lock:
            self.sweep(now)
            r = self._rooms.get(str(code).strip().upper())
            if r is None:
                return False
            r["last_seen"] = now
            r["created"] = now  # 心跳续期：只要宿主活着，码就不因 TTL 过期
            return True

    def close(self, code):
        with self._lock:
            return self._rooms.pop(str(code).strip().upper(), None) is not None

    def count(self):
        return len(self._rooms)


class RateLimiter:
    """按来源 IP 的滑动窗口限速（防码枚举）。"""

    def __init__(self, limit=DEFAULT_RATE, window=RATE_WINDOW):
        self.limit = limit
        self.window = window
        self._hits = {}
        self._lock = threading.Lock()

    def allow(self, ip, now=None):
        now = time.time() if now is None else now
        with self._lock:
            q = [t for t in self._hits.get(ip, []) if now - t < self.window]
            if len(q) >= self.limit:
                self._hits[ip] = q
                return False
            q.append(now)
            self._hits[ip] = q
            return True


class Handler(BaseHTTPRequestHandler):
    store = None
    limiter = None

    def log_message(self, *args):  # 静音默认访问日志
        pass

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        if n <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8") or "{}")
        except ValueError:
            return None

    def do_GET(self):
        if self.path.rstrip("/") == "/health":
            st = self.store.stats()
            self._json({"ok": True, "rooms": st["rooms"], "idle": st["idle"], "busy": st["busy"]})
        else:
            self._json({"error": "BAD_REQUEST"}, 404)

    @staticmethod
    def _should_limit(ip):
        """回环（同机池心跳）不限速；外部请求仍按 IP 限速。"""
        return str(ip) not in ("127.0.0.1", "::1", "localhost")

    def do_POST(self):
        ip = self.client_address[0]
        if self._should_limit(ip) and not self.limiter.allow(ip):
            self._json({"error": "RATE_LIMITED"}, 429)
            return
        data = self._read_json()
        if data is None:
            self._json({"error": "BAD_REQUEST"}, 400)
            return
        path = self.path.rstrip("/")
        if path == "/create_room":
            port = data.get("port")
            if not isinstance(port, int):
                self._json({"error": "BAD_REQUEST"}, 400)
                return
            # 房间地址：优先请求显式 host（如专用服务器的公网 IP）；否则用源 IP；
            # 若源 IP 是回环（同机部署）且配了 advertise_host，则用 advertise_host。
            host = str(data.get("host", "") or "").strip()
            if not host:
                host = ip
            if host in ("127.0.0.1", "::1", "localhost") and getattr(self, "advertise_host", ""):
                host = self.advertise_host
            code = self.store.create(
                host, port, data.get("mode", "dedicated"), data.get("max_players", 4),
                code=data.get("code"), state=data.get("state", IN_USE))
            if code is None:
                self._json({"error": "BAD_CODE"}, 400)
                return
            self._json({"code": code, "expires_in": self.store.ttl})
        elif path == "/allocate_room":
            r = self.store.allocate()
            self._json(r if r is not None else {"error": "NO_ROOM"})
        elif path == "/join_room":
            r = self.store.join(str(data.get("code", "")))
            self._json(r if r is not None else {"error": "ROOM_NOT_FOUND"})
        elif path == "/heartbeat":
            ok = self.store.heartbeat(str(data.get("code", "")))
            self._json({"ok": ok, "error": None if ok else "ROOM_NOT_FOUND"})
        elif path == "/close_room":
            self._json({"ok": self.store.close(str(data.get("code", "")))})
        else:
            self._json({"error": "BAD_REQUEST"}, 404)


def main():
    ap = argparse.ArgumentParser(description="KONG room directory service")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--ttl", type=int, default=DEFAULT_TTL)
    ap.add_argument("--heartbeat-timeout", type=int, default=DEFAULT_HB_TIMEOUT)
    ap.add_argument("--rate", type=int, default=DEFAULT_RATE)
    ap.add_argument("--reserve-timeout", type=int, default=RESERVE_TIMEOUT)
    ap.add_argument("--advertise-host", default="", help="同机部署时对外广播的公网 IP（源 IP 为回环时使用）")
    args = ap.parse_args()

    Handler.store = DirectoryStore(ttl=args.ttl, hb_timeout=args.heartbeat_timeout,
                                   reserve_timeout=args.reserve_timeout)
    Handler.limiter = RateLimiter(limit=args.rate)
    Handler.advertise_host = args.advertise_host
    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print("[KONG] directory listening on TCP %d (ttl=%ds hb=%ds rate=%d/%ds)"
          % (args.port, args.ttl, args.heartbeat_timeout, args.rate, RATE_WINDOW))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
