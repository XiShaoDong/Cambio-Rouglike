#!/usr/bin/env python3
"""Steam 票据校验（P3b，桩先行）。

- `MockVerifier`：开发/测试用——`ticket = "mock:<steamid>"` 即视为通过（无需 Steam）。
- `SteamWebApiVerifier`：生产用——调 Steam Web API `ISteamUserAuth/AuthenticateUserTicket/v1/`
  （需你的 **Web API Key** + App ID）。**无资源时用 Mock，上层逻辑不变。**
"""
import json
import urllib.parse
import urllib.request


class SteamVerifier:
    def verify(self, ticket):
        raise NotImplementedError


class MockVerifier(SteamVerifier):
    """ticket 形如 'mock:<steamid>' 视为通过。"""

    def verify(self, ticket):
        if isinstance(ticket, str) and ticket.startswith("mock:"):
            sid = ticket[5:].strip()
            if sid:
                return {"steamid": sid, "owner": True}
        return None


class SteamWebApiVerifier(SteamVerifier):
    URL = "https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/"

    def __init__(self, web_api_key, app_id):
        self.web_api_key = web_api_key
        self.app_id = app_id

    def verify(self, ticket):
        if not ticket:
            return None
        params = urllib.parse.urlencode({"key": self.web_api_key, "appid": self.app_id, "ticket": ticket})
        url = "%s?%s" % (self.URL, params)
        try:
            with urllib.request.urlopen(url, timeout=6) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except Exception:
            return None
        p = ((data.get("response", {}) or {}).get("params", {})) or {}
        if p.get("result") != "OK":
            return None
        steamid = str(p.get("steamid", ""))
        if not steamid:
            return None
        owner_raw = p.get("owner")
        owner = owner_raw is True or str(owner_raw) == "1"
        return {"steamid": steamid, "owner": owner}
