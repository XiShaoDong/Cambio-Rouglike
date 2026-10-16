#!/usr/bin/env python3
"""目录服务纯逻辑单测：python3 test_directory.py（无需网络/依赖）。"""
from directory import DirectoryStore, RateLimiter, ALPHABET, CODE_LEN

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


def test_code_gen():
    # 不触发回收，确保 500 次生成全唯一
    s = DirectoryStore(ttl=10**9, hb_timeout=10**9)
    codes = {s.create("1.2.3.4", 7007, "dedicated", 4, now=i) for i in range(500)}
    _ok("码长度=%d" % CODE_LEN, all(len(c) == CODE_LEN for c in codes))
    _ok("字符集合法", all(all(ch in ALPHABET for ch in c) for c in codes))
    _ok("500 次生成唯一", len(codes) == 500)


def test_create_join_close():
    s = DirectoryStore()
    c = s.create("9.9.9.9", 7007, "dedicated", 4, now=1000)
    _ok("join 命中返回地址", s.join(c, now=1001) == {"host": "9.9.9.9", "port": 7007, "mode": "dedicated"})
    _ok("close 后 join 失败", s.close(c) and s.join(c, now=1002) is None)
    _ok("join 未知码 → None", s.join("ZZZZZZ", now=1003) is None)


def test_heartbeat():
    s = DirectoryStore(hb_timeout=30)
    c = s.create("9.9.9.9", 7007, "dedicated", 4, now=1000)
    _ok("心跳续命", s.heartbeat(c, now=1020) and s.join(c, now=1030) is not None)
    _ok("心跳超时回收", s.join(c, now=1051) is None)  # last_seen=1020, +31 > 30


def test_ttl():
    s = DirectoryStore(ttl=100, hb_timeout=10**9)
    c = s.create("9.9.9.9", 7007, "dedicated", 4, now=1000)
    _ok("新建立即可 join", s.join(c, now=1000) is not None)
    s.heartbeat(c, now=1050)  # 心跳续期
    _ok("心跳续期：超过原 TTL 仍有效", s.join(c, now=1101) is not None)  # 1101-1050=51<100
    s.heartbeat(c, now=1140)
    _ok("持续心跳长期有效", s.join(c, now=1200) is not None)
    _ok("停止心跳后过期", s.join(c, now=1140 + 100 + 1) is None)  # 1241-1140>100
    _c = s.create("203.0.113.9", 7007, "dedicated", 4)
    _ok("显式 host 覆盖源 IP（专用服务器上报公网 IP）", s.join(_c)["host"] == "203.0.113.9")


def test_rate_limit():
    rl = RateLimiter(limit=3, window=60)
    _ok("前 3 次放行", rl.allow("1.1.1.1", now=0) and rl.allow("1.1.1.1", now=1) and rl.allow("1.1.1.1", now=2))
    _ok("第 4 次拒绝", not rl.allow("1.1.1.1", now=3))
    _ok("窗口过后放行", rl.allow("1.1.1.1", now=61))
    _ok("不同 IP 独立", rl.allow("2.2.2.2", now=3))


def test_fixed_code():
    s = DirectoryStore(ttl=100, hb_timeout=100)
    c = s.create("1.2.3.4", 7007, "dedicated", 4, code="kong")
    _ok("自定义码大写规范化", c == "KONG")
    _ok("小写 join 命中", s.join("kong", now=1000)["host"] == "1.2.3.4")
    _ok("同码重登记=接管", s.create("5.6.7.8", 7007, "dedicated", 4, code="KONG") == "KONG"
        and s.join("KONG", now=1000)["host"] == "5.6.7.8")
    _ok("非法码被拒", s.create("1.2.3.4", 7007, "dedicated", 4, code="ab") is None)


def main():
    test_code_gen()
    test_create_join_close()
    test_heartbeat()
    test_ttl()
    test_rate_limit()
    test_fixed_code()
    total = _checks
    passed = _checks - _fail
    print("=== DIRECTORY RESULT: %d/%d passed%s ===" % (passed, total, " (FAILURES!)" if _fail else ""))
    return 1 if _fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
