"""Generate 480x270 preview cards for the minigames grid.

Meadow Loop uses a real in-game screenshot if _shots/meadow_v2_drive.png exists;
the unreleased events get matching flat illustrations.

Run from godot_project/:  python tools/gen_minigame_previews.py
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFilter

W, H = 480, 270
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "ui", "minigames")
SHOT = os.path.join(ROOT, "..", "_shots", "meadow_v2_drive.png")

INK = (30, 27, 58)
SKY = (118, 196, 241)
GRASS = (96, 174, 82)
GRASS_DARK = (72, 146, 66)
DIRT = (198, 156, 103)
DIRT_DARK = (170, 128, 82)
YELLOW = (255, 210, 46)
RED = (242, 84, 91)
CYAN = (69, 182, 240)
PINK = (242, 108, 167)
CREAM = (253, 246, 227)


def base(draw: ImageDraw.ImageDraw, grass: bool = True) -> None:
    for y in range(H):
        t = y / H
        color = (
            int(SKY[0] * (1 - t) + 140 * t),
            int(SKY[1] * (1 - t) + 205 * t),
            int(SKY[2] * (1 - t) + 235 * t),
        )
        draw.line([(0, y), (W, y)], fill=color)
    draw.rectangle([0, 150, W, H], fill=GRASS if grass else DIRT)
    draw.ellipse([-60, 120, 150, 210], fill=GRASS_DARK)
    draw.ellipse([330, 130, 560, 220], fill=GRASS_DARK)


def cone(draw: ImageDraw.ImageDraw, x: int, y: int, scale: float = 1.0) -> None:
    w = int(26 * scale)
    h = int(38 * scale)
    draw.polygon([(x, y - h), (x + w // 2, y), (x - w // 2, y)], fill=(255, 122, 45), outline=INK)
    draw.rectangle([x - w // 2 - 2, y - 2, x + w // 2 + 2, y + 5], fill=(240, 240, 240), outline=INK)


def road(draw: ImageDraw.ImageDraw, points, width: int = 150) -> None:
    draw.line(points, fill=DIRT, width=width, joint="curve")
    draw.line(points, fill=CREAM, width=width + 14, joint="curve")
    draw.line(points, fill=DIRT, width=width, joint="curve")
    draw.line(points, fill=DIRT_DARK, width=width - 10, joint="curve")


def preview_meadow() -> Image.Image:
    if os.path.exists(SHOT):
        image = Image.open(SHOT).convert("RGB")
        image = image.resize((W, H), Image.LANCZOS)
        return image.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60))
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    base(draw)
    road(draw, [(-20, 230), (120, 190), (250, 150), (500, 120)], 120)
    return image


def preview_slalom() -> Image.Image:
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    base(draw)
    road(draw, [(-30, 250), (170, 150), (330, 130), (520, 240)], 150)
    for i in range(5):
        cone(draw, 150 + i * 44, 178 - i * 5, 1.15)
    return image


def preview_crates() -> Image.Image:
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    base(draw)
    road(draw, [(-20, 250), (200, 200), (520, 190)], 165)
    for row in range(3):
        for col in range(4 - row):
            x = 170 + col * 56 + row * 28
            y = 190 - row * 48
            draw.rectangle([x, y - 42, x + 48, y], fill=(196, 146, 86), outline=INK, width=3)
            draw.line([x + 4, y - 38, x + 44, y - 4], fill=(160, 112, 64), width=3)
            draw.line([x + 44, y - 38, x + 4, y - 4], fill=(160, 112, 64), width=3)
    return image


def preview_drift() -> Image.Image:
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    base(draw)
    draw.ellipse([70, 55, 420, 255], outline=DIRT_DARK, width=26)
    draw.ellipse([70, 55, 420, 255], outline=(70, 66, 72), width=12)
    draw.arc([110, 90, 380, 230], 20, 320, fill=(52, 49, 56), width=9)
    draw.arc([130, 105, 360, 218], 200, 500, fill=(52, 49, 56), width=7)
    # top-down cart
    draw.rounded_rectangle([210, 130, 280, 200], 12, fill=RED, outline=INK, width=4)
    draw.rectangle([222, 142, 268, 188], fill=(210, 210, 216), outline=INK, width=3)
    for x in (218, 272):
        draw.ellipse([x - 8, 190, x + 8, 210], fill=INK)
    return image


def preview_boost() -> Image.Image:
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    base(draw)
    road(draw, [(-30, 250), (240, 160), (520, 40)], 160)
    for i in range(3):
        x = 150 + i * 42
        y = 205 - i * 34
        draw.polygon([(x, y), (x + 54, y - 18), (x + 54, y + 10), (x, y + 28), (x + 16, y + 8)],
                     fill=YELLOW, outline=INK)
    draw.line([(330, 120), (455, 55)], fill=(255, 255, 255), width=5)
    return image


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    items = {
        "meadow_loop.png": preview_meadow(),
        "slalom.png": preview_slalom(),
        "crates.png": preview_crates(),
        "drift.png": preview_drift(),
        "boost.png": preview_boost(),
    }
    for name, image in items.items():
        path = os.path.join(OUT, name)
        image.save(path, optimize=True)
        print("wrote", os.path.relpath(path), os.path.getsize(path))


if __name__ == "__main__":
    main()
