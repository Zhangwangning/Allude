#!/usr/bin/env python3
"""对比「预填地址」与「人工地址」，产出地址准确率与差异清单。

用法：
    python3 tools/annotation/address-report.py 标注模板_合并.tsv

读取规则：
    · 只统计「人工地址」列非空、且「预填」为 pickup 的行；
    · 两列去空白后完全相同 → 判为正确，否则记为差异；
    · 输出到 地址差异.md（含按类型分组的前若干条）。
"""
import csv
import re
import sys
from collections import Counter

path = sys.argv[1] if len(sys.argv) > 1 else "标注模板_合并.tsv"

def rows_of(p):
    raw = open(p, encoding="utf-8-sig").read().splitlines()
    return [r.split("\t") for r in raw if r.strip()]

rows = rows_of(path)[1:]
def norm(s): return re.sub(r"\s+", "", s or "")

ok, bad = [], []
for r in rows:
    if len(r) < 13: continue
    if r[1].strip() != "pickup": continue
    human = r[12].strip()
    if not human: continue
    if norm(r[6]) == norm(human):
        ok.append(r)
    else:
        bad.append(r)

total = len(ok) + len(bad)
print(f"已核对地址：{total} 条 —— 正确 {len(ok)}，不一致 {len(bad)}")
if total:
    print(f"地址准确率：{len(ok)/total*100:.1f}%")

def kind(pre, hum):
    if not pre.strip(): return "A 未抓到地址（人工补全）"
    if norm(hum).startswith(norm(pre)) or norm(pre).startswith(norm(hum)): return "B 截断/多余"
    if "市" not in pre and "市" in hum: return "C 缺行政区"
    return "D 完全不同"

groups = Counter(kind(r[6], r[12]) for r in bad)
if groups:
    print("\n差异类型：")
    for k, v in groups.most_common():
        print(f"  {k}: {v}")

with open("地址差异.md", "w", encoding="utf-8") as f:
    f.write("# 地址差异清单\n\n")
    f.write(f"已核对 {total} 条：正确 {len(ok)}，不一致 {len(bad)}\n\n")
    for k, v in groups.most_common():
        f.write(f"- {k}: {v}\n")
    f.write("\n## 明细\n\n")
    for r in bad:
        f.write(f"### 序号 {r[0]}（{kind(r[6], r[12])}）\n")
        f.write(f"- 原文：{r[9].strip()}\n")
        f.write(f"- 预填地址：`{r[6].strip() or '（空）'}`\n")
        f.write(f"- 人工地址：`{r[12].strip()}`\n\n")
print("\n明细已写入 地址差异.md")
