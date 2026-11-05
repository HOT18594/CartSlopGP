"""Generate the tileable ground textures used by the Meadow Loop minigame.

Outputs (256 x 256, seamless, no external sources):
  assets/textures/grass_field.png   - mottled meadow grass
  assets/textures/dirt_track.png    - packed-dirt race surface

The algorithm tiles a small random lattice, upscales it, and crops the centre
so opposite edges wrap. Fine speckle is added with a wrap-safe blur. Both
textures are original CC0 work produced for this project.

Run:  python tools/gen_track_textures.py
"""

from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageFilter

SIZE = 256
OUT_DIR = os.path.join("assets", "textures")
SEED = 20261105


def _tile_noise(rng: np.random.Generator, cells: int) -> np.ndarray:
    """Upscale a 3x3 tiling of a small lattice, then crop the seamless centre."""
    lattice = rng.random((cells, cells)).astype(np.float32) * 255.0
    small = Image.fromarray(lattice.astype(np.uint8), mode="L")
    big = Image.new("L", (cells * 3 * 32, cells * 3 * 32))
    tile = small.resize((32, 32), Image.BICUBIC)
    for y in range(cells * 3):
        for x in range(cells * 3):
            big.paste(tile, (x * 32, y * 32))
    big = big.resize((SIZE * 3, SIZE * 3), Image.BICUBIC)
    big = big.filter(ImageFilter.GaussianBlur(6))
    return np.asarray(big, dtype=np.float32)[SIZE:SIZE * 2, SIZE:SIZE * 2] / 255.0


def _speckle(rng: np.random.Generator, amount: float) -> np.ndarray:
    noise = rng.random((SIZE, SIZE)).astype(np.float32) - 0.5
    tile = Image.fromarray(((noise + 0.5) * 255).astype(np.uint8), mode="L")
    # 3x3 blur then centre crop keeps the speckle seamlessly tileable.
    big = Image.new("L", (SIZE * 3, SIZE * 3))
    for y in range(3):
        for x in range(3):
            big.paste(tile, (x * SIZE, y * SIZE))
    big = big.filter(ImageFilter.GaussianBlur(0.7))
    blurred = np.asarray(big, dtype=np.float32)[SIZE:SIZE * 2, SIZE:SIZE * 2] / 255.0 - 0.5
    return noise * (1.0 - amount) + blurred * amount * 2.0


def grass() -> Image.Image:
    rng = np.random.default_rng(SEED)
    broad = _tile_noise(rng, 7)
    fine = _speckle(rng, 0.35)
    # Short vertical-ish blades, tiled by wrapping the y index.
    blades = np.zeros((SIZE, SIZE), dtype=np.float32)
    for _ in range(2600):
        x = int(rng.integers(0, SIZE))
        y = int(rng.integers(0, SIZE))
        length = int(rng.integers(2, 6))
        shade = float(rng.uniform(0.05, 0.22))
        for step in range(length):
            blades[(y - step) % SIZE, x] += shade
            if x + 1 < SIZE:
                blades[(y - step) % SIZE, x + 1] += shade * 0.3

    h = broad * 0.55 + fine * 0.45 + blades * 0.5
    # Two green tones, from shaded teal-green to sunlit yellow-green.
    dark = np.array([0.235, 0.435, 0.180], dtype=np.float32)
    light = np.array([0.470, 0.690, 0.270], dtype=np.float32)
    t = np.clip(h * 0.85 + 0.18, 0.0, 1.0)[..., None]
    rgb = dark + (light - dark) * t
    rgb += fine[..., None] * 0.055
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), mode="RGB")


def dirt() -> Image.Image:
    rng = np.random.default_rng(SEED + 1)
    broad = _tile_noise(rng, 9)
    fine = _speckle(rng, 0.55)
    # Faint tyre-worn streaks running along V (track direction).
    streak = np.zeros((SIZE, SIZE), dtype=np.float32)
    for _ in range(150):
        x = int(rng.integers(0, SIZE))
        width = int(rng.integers(1, 3))
        shade = float(rng.uniform(-0.07, 0.07))
        for dx in range(width):
            streak[:, (x + dx) % SIZE] += shade
        streak[:, x % SIZE] = np.convolve(
            streak[:, x % SIZE], np.ones(9) / 9.0, mode="same")

    h = broad * 0.5 + fine * 0.6 + streak
    dark = np.array([0.400, 0.310, 0.220], dtype=np.float32)
    light = np.array([0.690, 0.570, 0.410], dtype=np.float32)
    t = np.clip(h * 0.8 + 0.38, 0.0, 1.0)[..., None]
    rgb = dark + (light - dark) * t
    # A few small pale gravel chips.
    for _ in range(220):
        x, y = int(rng.integers(0, SIZE)), int(rng.integers(0, SIZE))
        rgb[y, x] = np.clip(rgb[y, x] + rng.uniform(0.06, 0.16), 0, 1)
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), mode="RGB")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, image in (("grass_field.png", grass()), ("dirt_track.png", dirt())):
        path = os.path.join(OUT_DIR, name)
        image.save(path)
        print("wrote", path, image.size)


if __name__ == "__main__":
    main()
