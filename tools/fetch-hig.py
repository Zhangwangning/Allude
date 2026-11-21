#!/usr/bin/env python3
"""把 Apple HIG 主题页抓成 Markdown，落到 skills/apple-hig/references/。

为什么不用 HTML / .webarchive：Apple 文档站是 SPA，页面正文由 JS 渲染，
`curl` 或 Safari 存档拿到的 HTML 里只有导航壳（正文一个字都没有）。
正文在文档 JSON 里：

    https://developer.apple.com/tutorials/data/cn/design/human-interface-guidelines/<slug>.json

用法：
    python3 tools/fetch-hig.py layout typography widgets     # 指定主题
    python3 tools/fetch-hig.py --missing                     # 只补还没入库的
    python3 tools/fetch-hig.py --all                         # 全部重抓

注意：
- 必须走 `curl` 子进程；本机 python 的 urllib 会撞代理 MITM，
  报 CERTIFICATE_VERIFY_FAILED: self-signed certificate in certificate chain。
- 原文逐字保留，只加文件头（来源 / 抓取日期）；要更新就整体重抓，不要手改。
"""
import datetime
import json
import os
import subprocess
import sys

REFMAP = {}

BASE = "https://developer.apple.com/tutorials/data/cn/design/human-interface-guidelines"
PAGE = "https://developer.apple.com/cn/design/human-interface-guidelines"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "skills/apple-hig/references")


def fetch(slug):
    tmp = f"/tmp/hig-{slug}.json"
    # 索引本身没有同名子路径，URL 是 .../human-interface-guidelines.json
    url = f"{BASE}.json" if slug == "human-interface-guidelines" else f"{BASE}/{slug}.json"
    subprocess.run(["curl", "-sSL", "-A", "Mozilla/5.0", url, "-o", tmp], check=True)
    with open(tmp) as f:
        return json.load(f)


def inline(items):
    """把 inlineContent 拼成一行文字。"""
    out = []
    for it in items or []:
        if isinstance(it, str):
            out.append(it)
            continue
        t = it.get("type")
        if t in ("text", "codeVoice"):
            out.append(it.get("text", ""))
        elif t == "reference":
            out.append(it.get("title") or it.get("identifier", "").split("/")[-1])
        elif t in ("emphasis", "strong"):
            out.append(inline(it.get("inlineContent")))
        elif t == "image":
            out.append("")
        else:
            out.append(it.get("text", "") or inline(it.get("inlineContent")))
    return "".join(out)


def render_blocks(blocks, depth=0):
    out = []
    for b in blocks or []:
        t = b.get("type")
        if t == "heading":
            level = min(6, max(2, b.get("level", 2)))
            out.append("\n" + "#" * level + " " + b.get("text", "").strip() + "\n")
        elif t == "paragraph":
            text = inline(b.get("inlineContent")).strip()
            if text:
                out.append(text + "\n")
        elif t == "codeListing":
            code = b.get("code") or []
            out.append("```" + (b.get("syntax") or "") + "\n" + "\n".join(code) + "\n```\n")
        elif t in ("unorderedList", "orderedList"):
            for i, item in enumerate(b.get("items") or []):
                marker = "-" if t == "unorderedList" else f"{i + 1}."
                first = True
                for c in item.get("content") or []:
                    if c.get("type") == "paragraph":
                        lead = f"{marker} " if first else "  "
                        out.append(lead + inline(c.get("inlineContent")).strip())
                        first = False
                    else:
                        sub = render_blocks([c], depth + 1).strip()
                        if sub:
                            out.append(("  " if first else "  ") + sub.replace("\n", "\n  "))
                            first = False
                out.append("")
        elif t == "table":
            rows = b.get("rows") or []
            for r in rows:
                cells = []
                for cell in r:
                    parts = []
                    for c in cell:
                        if c.get("type") == "paragraph":
                            parts.append(inline(c.get("inlineContent")).strip())
                        else:
                            parts.append(render_blocks([c], depth + 1).strip())
                    cells.append(" ".join(p for p in parts if p).replace("|", "\\|"))
                out.append("| " + " | ".join(cells) + " |")
            out.append("")
        elif t == "aside":
            body = render_blocks(b.get("content"), depth + 1).strip()
            if body:
                out.append("> " + body.replace("\n", "\n> ") + "\n")
        elif t == "links":
            for it in b.get("items") or []:
                if isinstance(it, str):
                    ref = REFMAP.get(it)
                    if ref:
                        title = (ref.get("title") or "").strip()
                        slug = (ref.get("url") or "").split("/")[-1].split("#")[0]
                        brief = inline(ref.get("abstract")).strip()
                        line = f"- **{title}**"
                        if slug:
                            line += f"（`references/{slug}.md`）"
                        if brief:
                            line += f" —— {brief}"
                        out.append(line)
                    else:
                        out.append(f"- {it}")
                else:
                    out.append(f"- {inline([it])}")
            out.append("")
    return "\n".join(out)


def to_markdown(slug, data):
    global REFMAP
    REFMAP = data.get("references") or {}
    title = (data.get("metadata") or {}).get("title") or slug
    parts = [
        f"# {title}",
        "",
        f"- 来源：{PAGE}/{slug}",
        f"- 抓取：{datetime.date.today().isoformat()}，正文取自 Apple 文档 JSON（同上路径 + `.json`）",
        "- 说明：官方原文，除本头注未改写。",
        "",
        "---",
        "",
    ]
    abstract = inline((data.get("abstract") or []))
    if abstract.strip():
        parts += [abstract.strip(), ""]
    for sec in data.get("primaryContentSections") or []:
        if sec.get("kind") == "content":
            parts.append(render_blocks(sec.get("content")))
        elif sec.get("kind") == "hero":
            pass
    text = "\n".join(parts)
    while "\n\n\n" in text:
        text = text.replace("\n\n\n", "\n\n")
    return text


def all_slugs():
    """从索引与各分区把全部主题 slug 摸出来。"""
    def refs_of(slug):
        try:
            return fetch(slug)
        except Exception:
            return {}
    seen = set()
    todo = ["human-interface-guidelines"]
    found = set()
    while todo:
        cur = todo.pop()
        if cur in seen:
            continue
        seen.add(cur)
        data = refs_of(cur)
        for _, ref in (data.get("references") or {}).items():
            url = ref.get("url", "")
            if "/design/human-interface-guidelines/" not in url:
                continue
            s = url.split("/")[-1].split("#")[0]
            if not s or s in found:
                continue
            found.add(s)
            if ref.get("kind") in ("article", "collectionGroup", "symbol"):
                todo.append(s)
    return sorted(found)


def main():
    os.makedirs(OUT, exist_ok=True)
    args = sys.argv[1:]
    have = {f[:-3] for f in os.listdir(OUT) if f.endswith(".md")}
    if not args or args[0] == "--all":
        slugs = all_slugs()
    elif args[0] == "--missing":
        slugs = [s for s in all_slugs() if s not in have]
    else:
        slugs = args
    if not slugs:
        print(f"没有要抓的。已入库 {len(have)} 篇，索引里没有更多。")
        return
    for slug in slugs:
        try:
            data = fetch(slug)
        except Exception as e:
            print(f"✗ {slug}: {e}")
            continue
        md = to_markdown(slug, data)
        if len(md) < 350:
            # 目录页 / 空壳，不要用空文件覆盖已有正文
            print(f"-- {slug}: 正文只有 {len(md)} 字节（目录页？），跳过")
            continue
        path = os.path.join(OUT, f"{slug}.md")
        with open(path, "w") as f:
            f.write(md)
        print(f"✓ {slug}: {len(md)} 字节")


if __name__ == "__main__":
    main()
