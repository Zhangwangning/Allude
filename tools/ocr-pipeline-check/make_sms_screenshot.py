#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成一张「模拟 iPhone 短信截图」，用于验证 OCR → 解析引擎 的端到端链路。

刻意放了**两条**短信：
  1) 快递短信（应被解析 → 取件码 C-4082 + 地址）
  2) 银行消费短信（含「尾号」，但必须被关键词闸门 + 尾号排除词拦下）
这样一次跑完既验证「能识别对的」，也验证「能挡掉错的」。

用法：
    /Users/zhangwangning/.workbuddy/binaries/python/envs/default/bin/python \\
        tools/ocr-pipeline-check/make_sms_screenshot.py
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent / "sms-sample.png"

W, H = 1170, 1180
MARGIN = 34
BUBBLE_PAD_X = 26
BUBBLE_PAD_Y = 20
BUBBLE_RADIUS = 26
FONT_SIZE = 42
LINE_GAP = 16

BACKGROUND = (255, 255, 255)
STATUS_BAR = (17, 17, 17)
BUBBLE = (233, 233, 235)
TEXT = (8, 8, 8)

FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/Library/Fonts/Arial Unicode.ttf",
]

MESSAGES = [
    "【兔喜生活】您有包裹已到达恒大御府店，取件码为C-4082，"
    "地址：舜耕中路2号院御府南门西侧3栋104号惠鲜果蔬店",
    "【中国银行】您尾号6688的储蓄卡 9月20日 消费人民币58.00元。",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    raise SystemExit("找不到可用中文字体，请检查 FONT_CANDIDATES")


def wrap(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> list[str]:
    """按像素宽度折行 —— 中文逐字折行即可，与短信界面表现一致。"""
    lines, current = [], ""
    for ch in text:
        probe = current + ch
        if draw.textlength(probe, font=font) <= max_width or not current:
            current = probe
        else:
            lines.append(current)
            current = ch
    if current:
        lines.append(current)
    return lines


def main() -> None:
    font = load_font(FONT_SIZE)
    small = load_font(30)

    img = Image.new("RGB", (W, H), BACKGROUND)
    draw = ImageDraw.Draw(img)

    # 顶部：状态栏 + 联系人
    draw.text((60, 42), "9:41", font=small, fill=STATUS_BAR)
    draw.text((W - 190, 42), "5G  ▮▮▮", font=small, fill=STATUS_BAR)

    contact = "10086"
    cw = draw.textlength(contact, font=small)
    draw.text(((W - cw) / 2, 108), contact, font=small, fill=STATUS_BAR)

    # 消息气泡（左对齐，自上而下排布）
    max_text_w = W - MARGIN * 2 - BUBBLE_PAD_X * 2 - 90
    y = 190

    for message in MESSAGES:
        lines = wrap(draw, message, font, max_text_w)
        line_h = FONT_SIZE + LINE_GAP
        bubble_w = max(draw.textlength(ln, font=font) for ln in lines) + BUBBLE_PAD_X * 2
        bubble_h = len(lines) * line_h - LINE_GAP + BUBBLE_PAD_Y * 2

        draw.rounded_rectangle(
            [MARGIN, y, MARGIN + bubble_w, y + bubble_h],
            radius=BUBBLE_RADIUS,
            fill=BUBBLE,
        )

        ty = y + BUBBLE_PAD_Y
        for line in lines:
            draw.text((MARGIN + BUBBLE_PAD_X, ty), line, font=font, fill=TEXT)
            ty += line_h

        y += bubble_h + 34

    img.save(OUT)
    print(f"已生成：{OUT}  ({img.width}x{img.height})")
    for i, m in enumerate(MESSAGES, 1):
        print(f"  短信 {i}: {m}")


if __name__ == "__main__":
    main()
