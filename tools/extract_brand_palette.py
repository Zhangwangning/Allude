#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
码夹 CodeClip · 品牌调色板提取器
==================================

从各品牌的官方图标里提取主色，生成 `CodeClipShared/BrandPalette.swift`，
供详情页做「跟着品牌走的磨砂玻璃卡片」。

为什么提取而不是手填
--------------------
详情页卡片底要「按品牌重构」——淘宝是橙玻璃、星巴克是绿玻璃、抖音是黑玻璃。
手填一套品牌色固然可行，但图标一换就失真；从图标本身提取，永远与图标一致，
而且能拿到**多色**（底色 + 点缀色），做渐变比单色有层次。

提取方式
--------
**从 Asset Catalog 里已处理好的成品图提取**（`Assets.xcassets/Brands/*.imageset/*.png`），
而不是 `brand-source/` 里的原始图。两个理由：
  · 成品图已经把「圆底图标」外扩成满底方图，原始图带 alpha，
    直接 `convert("RGB")` 会让透明区变**黑**，黑色会被当成品牌色混进调色板；
  · 提取的对象与用户实际看到的那张图**完全同一张**，不存在两处口径。

缩到 64×64 后走 PIL 的中位切分量化（MEDIANCUT），取占比最高的 3 色。

🔴 **近白永远沉底，不参与「主色」竞争**（2026-09-21 修订）
------------------------------------------------------
早先的口径是「白底图标就该得到浅色玻璃」（顺丰 / EMS / 丰巢），靠给近白按
0.25 折算面积来让彩底浮上来。**这个口径是错的**：白底图标的识别色是**那个
彩色的 LOGO**，不是纸白本身 —— 优速的白玻璃跟没上色一样，白瞎了品牌身份。
现在改成：**排序时近白一律排到所有非白之后**（只在近白内部再按面积排）。
顺丰 / EMS / 百世 / 优速 / 宅急送 这 5 个白底图标因此拿到各自的颜色，
其余 41 个品牌的首色**一个都没变**。

⚠️ **近黑（≤ 30）不适用该规则**：抖音、得物、安能的主色就是黑，黑是它们的
品牌色，不能被当成"没识别度"处理。

灰度兜底：若沉底后浮上来的首色**仍是灰的**（饱和度 < 0.15 且非近黑），
说明量化把彩色 LOGO 和底色混成了灰 —— 此时从候选中另挑第一个
「非近黑且饱和度 ≥ 0.20」的色顶到最前（宅急送的绿猴就靠这一步拿到绿）。

对比度交给 UI 侧控制（渐变色一律压到低透明度），不靠这里筛色。

用法
----
    PY=/Users/zhangwangning/.workbuddy/binaries/python/envs/default/bin/python
    $PY tools/extract_brand_palette.py             # 提取并写入工程
    $PY tools/extract_brand_palette.py --dry-run   # 只打印，不写文件
"""

from __future__ import annotations

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SOURCE_DIR = os.path.join(ROOT, "CodeClip", "CodeClipShared", "Assets.xcassets", "Brands")
OUT = os.path.join(ROOT, "CodeClip", "CodeClipShared", "BrandPalette.swift")

TOP_N = 3          # 每张图取几个色
SAMPLES = 64       # 量化前先缩到多少像素
MIN_SHARE = 0.02   # 占比低于此的碎色丢弃
DISTINCT = 40      # 与已选色差异小于此的视为重复色，丢弃

NEAR_WHITE = 232   # 三通道都不低于此值 → 视为「近白」，排序时一律沉底
NEAR_BLACK = 30    # 三通道都不高于此值 → 视为「近黑」，黑是它的品牌色，不受上述规则影响
GRAY_SAT = 0.15    # 饱和度低于此视为「灰」（没有识别度）→ 触发灰度兜底
PREFER_SAT = 0.20  # 灰度兜底时，替补色至少要有的饱和度


def _is_near_white(rgb: tuple[int, int, int]) -> bool:
    return min(rgb) >= NEAR_WHITE


def _is_near_black(rgb: tuple[int, int, int]) -> bool:
    return max(rgb) <= NEAR_BLACK


def _saturation(rgb: tuple[int, int, int]) -> float:
    """HSV 里的 S。近黑的分母极小会让 S 虚高，所以调用前先用 _is_near_black 挡掉。"""
    high, low = max(rgb), min(rgb)
    return 0.0 if high == 0 else (high - low) / high


def _diff(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def dominant_colors(path: str, n: int = TOP_N) -> list[tuple[int, tuple[int, int, int]]]:
    """返回 [(像素数, (r,g,b)), ...]，按「代表色」降序。

    排序规则见模块文档：**近白永远沉底**（非白内部按面积降序），
    近黑不受影响；若浮上来的首色仍是灰的，再走一次灰度兜底。
    """
    im = Image.open(path).convert("RGB").resize((SAMPLES, SAMPLES), Image.LANCZOS)
    # 多切几档再筛，避免「只有 3 档时把某个真实色切没」
    quantized = im.quantize(colors=8, method=Image.Quantize.MEDIANCUT)

    palette = quantized.getpalette() or []
    counts = quantized.getcolors() or []          # [(count, palette_index), ...]

    total = SAMPLES * SAMPLES
    candidates: list[tuple[int, tuple[int, int, int]]] = []
    for count, index in counts:
        if count / total < MIN_SHARE:
            continue
        rgb = tuple(palette[index * 3: index * 3 + 3])
        if len(rgb) == 3:
            candidates.append((count, rgb))       # type: ignore[arg-type]

    # 近白沉底；同一档内面积大的在前
    candidates.sort(key=lambda item: (_is_near_white(item[1]), -item[0]))

    out: list[tuple[int, tuple[int, int, int]]] = []
    for count, rgb in candidates:
        if any(_diff(rgb, kept) < DISTINCT for _, kept in out):
            continue
        out.append((count, rgb))
        if len(out) >= n:
            break

    # 灰度兜底：首色是灰（且不是"黑就是品牌色"那种黑）→ 换一个够饱和的顶上
    if out and not _is_near_black(out[0][1]) and _saturation(out[0][1]) < GRAY_SAT:
        swap = next((i for i, (_, rgb) in enumerate(out)
                     if not _is_near_black(rgb) and _saturation(rgb) >= PREFER_SAT), None)
        if swap is not None:
            out.insert(0, out.pop(swap))

    return out


def to_hex(rgb: tuple[int, int, int]) -> str:
    return "0x%02X%02X%02X" % rgb


def main() -> int:
    dry_run = "--dry-run" in sys.argv

    if not os.path.isdir(SOURCE_DIR):
        print(f"✗ 找不到品牌图标目录：{SOURCE_DIR}", file=sys.stderr)
        print("  先跑 tools/import_brand_logos.py 导入品牌图标。", file=sys.stderr)
        return 1

    sets = sorted(d for d in os.listdir(SOURCE_DIR) if d.endswith(".imageset"))
    if not sets:
        print(f"✗ {SOURCE_DIR} 里没有 .imageset", file=sys.stderr)
        return 1

    entries: list[tuple[str, list[str], list[tuple[int, tuple[int, int, int]]]]] = []
    for folder in sets:
        asset = folder[: -len(".imageset")]
        png = os.path.join(SOURCE_DIR, folder, asset + ".png")
        if not os.path.exists(png):
            print(f"⚠ {asset} 缺少 {asset}.png，跳过", file=sys.stderr)
            continue
        colors = dominant_colors(png)
        if not colors:
            print(f"⚠ {asset} 提取不到颜色，跳过", file=sys.stderr)
            continue
        entries.append((asset, [to_hex(rgb) for _, rgb in colors], colors))

    width = max(len(a) for a, _, _ in entries) + 4
    print(f"{'资源名':<{width}} {'调色板（按占比降序）'}")
    print("-" * (width + 46))
    for asset, hexes, colors in entries:
        shares = "  ".join(f"{c / (SAMPLES * SAMPLES):>5.1%} {h}"
                           for (c, _), h in zip(colors, hexes))
        print(f"{asset:<{width}} {shares}")

    if dry_run:
        print("\n（--dry-run，未写入）")
        return 0

    lines = [
        "import Foundation",
        "",
        "// 本文件由 tools/extract_brand_palette.py 从各品牌官方图标提取，请勿手改。",
        "// 换图标后重跑脚本即可刷新。",
        "",
        "/// 各品牌官方图标的主色调色板。",
        "///",
        "/// 用途：详情页卡片的「品牌色磨砂玻璃」底 —— 淘宝橙、星巴克绿、抖音黑，",
        "/// 一律跟着各自的官方图标走，而不是另配一套颜色。",
        "enum BrandPalette {",
        "",
        "    /// 键 = Asset 资源名，值 = 主色（按占比降序，最多 3 个）",
        "    static let table: [String: [UInt32]] = [",
    ]
    for asset, hexes, _ in entries:
        lines.append(f'        "{asset}": [{", ".join(hexes)}],')
    lines += [
        "    ]",
        "",
        "    /// 取某个品牌图标的调色板；未收录返回 nil，由调用方回落到品牌主色。",
        "    static func colors(forAsset asset: String?) -> [UInt32]? {",
        "        guard let asset, let value = table[asset], !value.isEmpty else { return nil }",
        "        return value",
        "    }",
        "}",
        "",
    ]

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"\n已写入 {OUT}（{len(entries)} 个品牌）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
