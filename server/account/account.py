#!/usr/bin/env python3
"""KONG 账号服务（P3a · 方案A：独立 HTTP/JSON 服务）。

职责：设备匿名账号（注册/登录/昵称/持久战绩）+ 落盘持久化。**不接触牌局牌面**。
运行：
    python3 account.py --port 8090 --data accounts.json
接口（POST，JSON）：
    /register_device {name?}              -> {account_id, secret}
    /login           {account_id,secret}  -> {account_id,name,stats} | {error:"AUTH_FAILED"}
    /set_name        {account_id,secret,name} -> {ok}
    /get_profile     {account_id}         -> {account_id,name,stats}
    GET /health                           -> {ok, accounts}
"""
import argparse
import json
import os
import random
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from steam import MockVerifier, SteamWebApiVerifier

DEFAULT_RATE = 30
RATE_WINDOW = 60


def _rand_hex(n):
    return "".join(random.choice("0123456789abcdef") for _ in range(n))


class AccountStore:
    """账号存储（内存 + JSON 落盘；纯逻辑，可单测；线程安全）。"""

    def __init__(self, path=None):
        self.path = path
        self._accounts = {}  # account_id -> {name, secret, stats, created}
        self._lock = threading.Lock()
        self._load()

    def _load(self):
        if self.path and os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    self._accounts = json.load(f)
            except (ValueError, OSError):
                self._accounts = {}

    def _save(self):
        if not self.path:
            return
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self._accounts, f, ensure_ascii=False)
        os.replace(tmp, self.path)

    def register(self, name=None, now=None):
        now = time.time() if now is None else now
        with self._lock:
            aid = "acc_" + _rand_hex(16)
            secret = _rand_hex(32)
            clean = (name or "").strip()[:16] or "玩家"
            self._accounts[aid] = {"name": clean, "secret": secret,
                                   "stats": {"wins": 0, "matches": 0}, "created": now}
            self._save()
            return {"account_id": aid, "secret": secret}

    def login(self, aid, secret):
        a = self._accounts.get(aid)
        if a is None or a.get("secret") != secret:
            return None
        return self._profile(aid, a)

    def set_name(self, aid, secret, name):
        with self._lock:
            a = self._accounts.get(aid)
            if a is None or a.get("secret") != secret:
                return False
            clean = (name or "").strip()[:16]
            if clean:
                a["name"] = clean
            self._save()
            return True

    def get_profile(self, aid):
        a = self._accounts.get(aid)
        return self._profile(aid, a) if a else None

    def add_stats(self, aid, deltas):
        """供服务器端累加战绩（未来 P4 MMR）。deltas: {key: int}。"""
        with self._lock:
            a = self._accounts.get(aid)
            if a is None:
                return False
            for k, v in deltas.items():
                a["stats"][k] = int(a["stats"].get(k, 0)) + int(v)
            self._save()
            return True

    def bind_steam(self, aid, secret, steam_id):
        """把 account 绑定到 steam_id（P3b）。校验 secret。"""
        with self._lock:
            a = self._accounts.get(aid)
            if a is None or a.get("secret") != secret or not steam_id:
                return False
            a["steam_id"] = str(steam_id)
            self._save()
            return True

    def count(self):
        return len(self._accounts)

    def _profile(self, aid, a):
        return {"account_id": aid, "name": a["name"], "stats": a.get("stats", {}),
                "steam_id": str(a.get("steam_id", ""))}


class RateLimiter:
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
    verifier = None

    def log_message(self, *args):
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
            self._json({"ok": True, "accounts": self.store.count()})
        else:
            self._json({"error": "BAD_REQUEST"}, 404)

    def do_POST(self):
        ip = self.client_address[0]
        if not self.limiter.allow(ip):
            self._json({"error": "RATE_LIMITED"}, 429)
            return
        data = self._read_json()
        if data is None:
            self._json({"error": "BAD_REQUEST"}, 400)
            return
        path = self.path.rstrip("/")
        if path == "/register_device":
            self._json(self.store.register(data.get("name")))
        elif path == "/login":
            prof = self.store.login(str(data.get("account_id", "")), str(data.get("secret", "")))
            if prof is None:
                self._json({"error": "AUTH_FAILED"})
            else:
                self._json(prof)
        elif path == "/set_name":
            ok = self.store.set_name(str(data.get("account_id", "")), str(data.get("secret", "")), data.get("name", ""))
            self._json({"ok": ok, "error": None if ok else "AUTH_FAILED"})
        elif path == "/get_profile":
            prof = self.store.get_profile(str(data.get("account_id", "")))
            self._json(prof if prof is not None else {"error": "AUTH_FAILED"})
        elif path == "/steam_auth":
            aid = str(data.get("account_id", ""))
            sec = str(data.get("secret", ""))
            if self.store.login(aid, sec) is None:
                self._json({"error": "AUTH_FAILED"})
                return
            res = self.verifier.verify(str(data.get("ticket", ""))) if self.verifier is not None else None
            if res is None:
                self._json({"error": "STEAM_AUTH_FAILED"})
                return
            self.store.bind_steam(aid, sec, res["steamid"])
            self._json({"ok": True, "steam_id": res["steamid"], "owner": bool(res.get("owner"))})
        else:
            self._json({"error": "BAD_REQUEST"}, 404)


def main():
    ap = argparse.ArgumentParser(description="KONG account service")
    ap.add_argument("--port", type=int, default=8090)
    ap.add_argument("--data", default="accounts.json")
    ap.add_argument("--rate", type=int, default=DEFAULT_RATE)
    ap.add_argument("--steam-webapi-key", default="", help="有则启用真实 Steam 校验；否则用 MockVerifier")
    ap.add_argument("--steam-appid", type=int, default=480)
    args = ap.parse_args()

    Handler.store = AccountStore(path=args.data)
    Handler.limiter = RateLimiter(limit=args.rate)
    if args.steam_webapi_key:
        Handler.verifier = SteamWebApiVerifier(args.steam_webapi_key, args.steam_appid)
        steam_mode = "steam-webapi"
    else:
        Handler.verifier = MockVerifier()
        steam_mode = "mock"
    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print("[KONG] account service listening on TCP %d (data=%s, steam=%s)" % (args.port, args.data, steam_mode))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
