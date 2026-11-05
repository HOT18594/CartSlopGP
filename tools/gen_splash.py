"""Generates assets/ui/boot_splash.png (launch splash) and a small cart icon."""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 720
OUT = os.path.join("assets", "ui", "boot_splash.png")
ICON = os.path.join("assets", "ui", "cart_icon.png")

SKY_TOP = (47, 159, 232)
SKY_BOTTOM = (191, 233, 255)
INK = (30, 27, 58)
CREAM = (255, 246, 227)
PINK = (242, 108, 167)
YELLOW = (255, 210, 46)
RED = (242, 84, 91)


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def draw_cart(draw: ImageDraw.ImageDraw, x: float, y: float, scale: float) -> None:
    """Side-view shopping cart, matching the menu style."""
    s = scale
    basket = [
        (x - 52 * s, y - 62 * s),
        (x + 52 * s, y - 62 * s),
        (x + 38 * s, y - 10 * s),
        (x - 38 * s, y - 10 * s),
    ]
    draw.polygon(basket, fill=(232, 236, 245), outline=INK, width=max(2, int(3 * s)))
    for step in range(1, 4):
        t = step / 4
        x0 = basket[0][0] + (basket[1][0] - basket[0][0]) * t
        x1 = basket[3][0] + (basket[2][0] - basket[3][0]) * t
        draw.line((x0, basket[0][1], x1, basket[3][1]), fill=INK, width=max(1, int(2 * s)))
    for step in range(1, 3):
        t = step / 3
        y0 = basket[0][1] + (basket[3][1] - basket[0][1]) * t
        y1 = basket[1][1] + (basket[2][1] - basket[1][1]) * t
        draw.line((basket[0][0], y0, basket[1][0], y1), fill=INK, width=max(1, int(2 * s)))
    draw.line((x - 50 * s, y - 60 * s, x - 50 * s, y - 76 * s), fill=RED, width=max(3, int(10 * s)))
    for wx in (-34, 34):
        draw.line((x + wx * s, y - 10 * s, x + wx * s, y + 20 * s), fill=INK, width=max(2, int(4 * s)))
        draw.ellipse((x + wx * s - 9 * s, y + 18 * s, x + wx * s + 9 * s, y + 36 * s), fill=INK)
        draw.ellipse((x + wx * s - 3.5 * s, y + 24 * s, x + wx * s + 3.5 * s, y + 31 * s),
                     fill=(180, 184, 198))


def make_splash() -> None:
    image = Image.new("RGB", (W, H), SKY_TOP)
    draw = ImageDraw.Draw(image)
    for y in range(H):
        t = y / H
        draw.line((0, y, W, y), fill=tuple(int(a + (b - a) * t) for a, b in zip(SKY_TOP, SKY_BOTTOM)))

    # clouds
    for cx, cy, r in ((180, 120, 46), (420, 80, 34), (980, 110, 52), (1160, 220, 30)):
        for dx, dy, rr in ((-1.1, 0.15, 0.7), (1.05, 0.2, 0.65), (0, 0, 1), (-0.5, -0.4, 0.6)):
            draw.ellipse((cx + dx * r - rr * r, cy + dy * r - rr * r,
                          cx + dx * r + rr * r, cy + dy * r + rr * r), fill=(255, 255, 255))

    # ground + lot
    horizon = 470
    draw.rectangle((0, horizon, W, H), fill=(203, 191, 206))
    for i in range(-5, 6):
        bottom_x = W / 2 + i * 230
        draw.line((W / 2 + i * 10, horizon, bottom_x, H), fill=(255, 255, 255), width=4)

    # title
    display = font("assets/ui/fonts/LuckiestGuy-Regular.ttf", 150)
    body = font("assets/ui/fonts/Fredoka-Bold.ttf", 30)
    title = "CART SLOP GP"
    tw = draw.textlength(title, font=display)
    tx = (W - tw) / 2
    draw.text((tx, 70), title, font=display, fill=CREAM,
              stroke_width=18, stroke_fill=INK)
    sub = "SLOPMART PARKING LOT"
    sw = draw.textlength(sub, font=body)
    draw.text(((W - sw) / 2, 268), sub, font=body, fill=INK)

    draw_cart(draw, W / 2, 585, 2.1)
    image.save(OUT)
    print("wrote", OUT)

    # small transparent cart for UI use
    icon = Image.new("RGBA", (160, 140), (0, 0, 0, 0))
    idraw = ImageDraw.Draw(icon)
    draw_cart(idraw, 80, 95, 0.9)
    icon.save(ICON)
    print("wrote", ICON)


if __name__ == "__main__":
    make_splash()
