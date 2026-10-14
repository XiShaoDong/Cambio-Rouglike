#!/usr/bin/env python3
"""账号服务纯逻辑单测：python3 test_account.py（无需网络/依赖）。"""
import os
import tempfile
from account import AccountStore, RateLimiter
from steam import MockVerifier

_fail = 0
_checks = 0


def _ok(name, cond):
    global _fail, _checks
    _checks += 1
    if cond:
        print("[PASS] " + name)
    else:
        _fail += 1
        print("[FAIL] " + name)
    return cond


def test_register_login():
    s = AccountStore()
    r = s.register("小明")
    aid, secret = r["account_id"], r["secret"]
    _ok("register 返回非空 id/secret", bool(aid) and bool(secret))
    _ok("id 前缀 acc_", aid.startswith("acc_"))
    prof = s.login(aid, secret)
    _ok("login 命中返回 profile", prof is not None and prof["name"] == "小明")
    _ok("login 错误 secret → None", s.login(aid, "bad") is None)
    _ok("login 未知 id → None", s.login("acc_nope", secret) is None)
    _ok("register 唯一", s.register()["account_id"] != aid)


def test_set_name():
    s = AccountStore()
    r = s.register("A")
    _ok("set_name 成功", s.set_name(r["account_id"], r["secret"], "新名"))
    _ok("改后生效", s.get_profile(r["account_id"])["name"] == "新名")
    _ok("set_name 错误 secret → False", not s.set_name(r["account_id"], "bad", "X"))
    _ok("未知 id → None profile", s.get_profile("acc_nope") is None)


def test_stats():
    s = AccountStore()
    r = s.register()
    aid = r["account_id"]
    s.add_stats(aid, {"wins": 2, "matches": 3})
    s.add_stats(aid, {"wins": 1})
    p = s.get_profile(aid)
    _ok("战绩累加", p["stats"]["wins"] == 3 and p["stats"]["matches"] == 3)


def test_persistence():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "accounts.json")
        s1 = AccountStore(path=path)
        r = s1.register("持久")
        aid, secret = r["account_id"], r["secret"]
        s1.add_stats(aid, {"wins": 5})
        # 新实例从同一文件加载
        s2 = AccountStore(path=path)
        p = s2.login(aid, secret)
        _ok("持久化：跨实例可登录", p is not None and p["name"] == "持久")
        _ok("持久化：战绩保留", p["stats"]["wins"] == 5)


def test_steam():
    mv = MockVerifier()
    r = mv.verify("mock:76561198000000000")
    _ok("Mock 通过 mock: 票据", r is not None and r["steamid"] == "76561198000000000")
    _ok("Mock 拒绝非 mock 票据", mv.verify("garbage") is None and mv.verify("") is None)
    s = AccountStore()
    reg = s.register("S")
    aid, sec = reg["account_id"], reg["secret"]
    _ok("bind_steam 成功", s.bind_steam(aid, sec, "76561198000000000"))
    _ok("profile 含 steam_id", s.get_profile(aid)["steam_id"] == "76561198000000000")
    _ok("bind_steam 错误 secret → False", not s.bind_steam(aid, "bad", "1"))


def test_rate_limit():
    rl = RateLimiter(limit=2, window=60)
    _ok("限速前 2 次放行", rl.allow("1.1.1.1", now=0) and rl.allow("1.1.1.1", now=1))
    _ok("第 3 次拒绝", not rl.allow("1.1.1.1", now=2))
    _ok("窗口过后放行", rl.allow("1.1.1.1", now=61))


def main():
    test_register_login()
    test_set_name()
    test_stats()
    test_persistence()
    test_steam()
    test_rate_limit()
    passed = _checks - _fail
    print("=== ACCOUNT RESULT: %d/%d passed%s ===" % (passed, _checks, " (FAILURES!)" if _fail else ""))
    return 1 if _fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
