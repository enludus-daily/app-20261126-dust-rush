#!/usr/bin/env python3
"""すいこみロボのアイコン（1024x1024、透過なし）。真上から見た明るいフローリングに、ロボが通ったぴかぴかの筋。
白い丸いロボ（ミントに光る輪とサイドブラシ）と、目のあるほこりが 2 つ。
使い方: python3 scripts/make-icon-robo.py"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")


def hx(v):
    return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))


img = Image.new("RGB", (S, S), hx("E4D3B8"))
d = ImageDraw.Draw(img)
# 板目
for i, y in enumerate(range(0, S, 128)):
    d.line([(0, y), (S, y)], fill=hx("D3BE9E"), width=6)
    off = (i * 290) % 420
    for x in range(off, S, 420):
        d.line([(x, y), (x, y + 128)], fill=hx("D3BE9E"), width=6)
# 掃除した筋（明るく光る帯）
streak = Image.new("L", (S, S), 0)
sd = ImageDraw.Draw(streak)
sd.line([(-40, 900), (430, 560), (560, 520)], fill=255, width=270, joint="curve")
streak = streak.filter(ImageFilter.GaussianBlur(18))
shine = Image.new("RGB", (S, S), hx("FBF4E8"))
img = Image.composite(shine, img, streak)
d = ImageDraw.Draw(img)
# ほこり 2 つ（目あり）
for cx, cy, r in [(800, 250, 70), (300, 260, 52)]:
    for dx, dy, k in [(-0.45, 0.1, 0.75), (0.45, 0.05, 0.7), (0.0, -0.35, 0.8), (0, 0.15, 1.0)]:
        rr = r * k
        d.ellipse([cx + dx * r - rr, cy + dy * r - rr, cx + dx * r + rr, cy + dy * r + rr], fill=hx("B3ABA1"))
    for s in (-1, 1):
        ex, ey = cx + s * r * 0.36, cy - r * 0.05
        d.ellipse([ex - r * 0.18, ey - r * 0.24, ex + r * 0.18, ey + r * 0.24], fill=hx("FFFFFF"))
        d.ellipse([ex - r * 0.09, ey - r * 0.11, ex + r * 0.09, ey + r * 0.11], fill=hx("3B3650"))
# ロボ
cx, cy, R = 560, 560, 250
shadow = Image.new("L", (S, S), 0)
ImageDraw.Draw(shadow).ellipse([cx - R, cy - R + 30, cx + R, cy + R + 30], fill=90)
shadow = shadow.filter(ImageFilter.GaussianBlur(22))
img = Image.composite(Image.new("RGB", (S, S), hx("8E7F6E")), img, shadow)
d = ImageDraw.Draw(img)
# サイドブラシ
for s in (-1, 1):
    bx, by = cx + s * R * 0.62, cy - R * 0.72
    for k in range(3):
        a = s * 0.6 + k * 2.094
        d.line([(bx, by), (bx + math.cos(a) * 105, by + math.sin(a) * 105)], fill=hx("8B8399"), width=14)
d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=hx("FFFFFF"), outline=hx("CFC7D8"), width=10)
d.arc([cx - R * 0.88, cy - R * 0.88, cx + R * 0.88, cy + R * 0.88], start=210, end=330, fill=hx("BDB4C9"), width=26)
# 光る輪
glow = Image.new("L", (S, S), 0)
gr = R * 0.55
ImageDraw.Draw(glow).ellipse([cx - gr, cy - gr, cx + gr, cy + gr], outline=255, width=46)
glow = glow.filter(ImageFilter.GaussianBlur(14))
img = Image.composite(Image.new("RGB", (S, S), hx("5FCFAE")), img, glow)
d = ImageDraw.Draw(img)
d.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], outline=hx("3FB894"), width=22)
d.ellipse([cx - R * 0.2, cy - R * 0.2, cx + R * 0.2, cy + R * 0.2], fill=hx("EDE8F2"))
img.save(OUT)
print("saved", OUT)
