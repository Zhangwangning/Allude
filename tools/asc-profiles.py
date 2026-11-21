#!/usr/bin/env python3
"""列出团队里所有分发 profile，并把指定的几个下载到本地。

复用 tools/testflight-publish.py 里的 JWT 与 api 实现（本机没有 PyJWT，
那边是用 openssl 手搓 ES256 的）。
"""
import base64
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tfp", os.path.join(HERE, "testflight-publish.py"))
tfp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tfp)

DIAG = "--list" in sys.argv

r = tfp.api("GET", "/v1/profiles", query={
    "limit": "200",
    "include": "certificates",
    "fields[profiles]": "name,profileType,profileState,uuid,expirationDate,certificates",
})
if "data" not in r:
    print("API 失败:", json.dumps(r, ensure_ascii=False)[:400])
    sys.exit(1)

inc = {}
for item in r.get("included", []):
    if item["type"] == "certificates":
        inc[item["id"]] = item["attributes"]

rows = []
for p in r["data"]:
    a = p["attributes"]
    certs = []
    for ref in (p["relationships"].get("certificates", {}) or {}).get("data", []) or []:
        c = inc.get(ref["id"], {})
        certs.append(c.get("displayName") or c.get("name") or ref["id"])
    rows.append({
        "id": p["id"],
        "name": a.get("name"),
        "type": a.get("profileType"),
        "state": a.get("profileState"),
        "expires": (a.get("expirationDate") or "")[:10],
        "certs": certs,
    })

rows.sort(key=lambda x: (x["type"] or "", x["name"] or ""))
for x in rows:
    print(f"{x['id']:12} {x['type']:18} {x['state']:10} {x['expires']}  {x['name']}")
    for c in x["certs"]:
        print(f"             ↳ {c}")

if "--download" in sys.argv:
    want = {"7H29P7MJ8Q": "app", "4F62FDJ8K2": "widget"}
    for pid, tag in want.items():
        d = tfp.api("GET", f"/v1/profiles/{pid}")
        if "data" not in d:
            print(f"下载 {pid} 失败: {json.dumps(d, ensure_ascii=False)[:300]}")
            continue
        content = d["data"]["attributes"].get("profileContent")
        if not content:
            print(f"{pid} 没有 profileContent")
            continue
        out = f"/tmp/store_{tag}.mobileprovision"
        open(out, "wb").write(base64.b64decode(content))
        print(f"已写入 {out}  ({d['data']['attributes'].get('name')})")
