#!/usr/bin/env python3
"""把标注好的 xlsx 转回 TSV，供 retrain.swift 读取。

用法：python3 tools/annotation/xlsx2tsv.py 标注模板.xlsx > 标注模板.tsv
"""
import sys
from openpyxl import load_workbook

path = sys.argv[1] if len(sys.argv) > 1 else "标注模板.xlsx"
ws = load_workbook(path, data_only=True).active
for row in ws.iter_rows(values_only=True):
    cells = ["" if v is None else str(v).replace("\t", " ").replace("\n", " ")
             for v in row]
    if any(c.strip() for c in cells):
        print("\t".join(cells))
