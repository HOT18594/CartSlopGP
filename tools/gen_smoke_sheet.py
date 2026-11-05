"""Generates assets/textures/smoke_sheet.png: a 4x4, 16-frame soft smoke puff.

The previous sheet was 16 near-identical thin crescents, which read as
boomerangs in game. Each frame here is a cluster of overlapping soft blobs
growing outward, with a coherent noise field that makes the puff break up
over the animation instead of flickering from frame to frame.

Run:  python tools/gen_smoke_sheet.py
"""

from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageFilter

CELL: int = 128
GRID: int = 4
FRAMES: int = GRID * GRID
OUT_PATH: str = os.path.join("assets", "textures", "smoke_sheet.png")
PREVIEW_PATH: str = os.path.join("tools", "smoke_sheet_preview.png")

YY, XX = np.mgrid[0:CELL, 0:CELL].astype(np.float32)
CENTER: float = (CELL - 1) * 0.5
DIST_FROM_CENTER = np.sqrt((XX - CENTER) ** 2 + (YY - CENTER) ** 2)


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fractal_noise(rng: np.random.Generator, octaves: int = 4) -> np.ndarray:
    """Stacked bicubic-upsampled random grids, normalised to 0..1."""
    out = np.zeros((CELL, CELL), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for octave in range(octaves):
        cells = 2 ** (octave + 1)
        grid = rng.random((cells + 1, cells + 1)).astype(np.float32)
        img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
        img = img.resize((CELL, CELL), Image.BICUBIC)
        out += np.asarray(img, dtype=np.float32) / 255.0 * amp
        total += amp
        amp *= 0.55
    out /= total
    return (out - out.min()) / max(out.max() - out.min(), 1e-6)


NOISE_A = fractal_noise(np.random.default_rng(4242))
NOISE_B = fractal_noise(np.random.default_rng(911))
COARSE = fractal_noise(np.random.default_rng(1337), octaves=2)


def coherent_noise(t: float) -> np.ndarray:
    """Two noise fields drifting against each other, so wisps evolve smoothly."""
    shift = int(t * 9.0)
    first = np.roll(NOISE_A, shift, axis=0)
    second = np.roll(NOISE_B, -shift // 2, axis=1)
    return np.clip(first * (0.65 - 0.25 * t) + second * (0.35 + 0.25 * t), 0.0, 1.0)


def build_frame(index: int) -> np.ndarray:
    """Return one 128x128 alpha frame (0..1), 0 = first frame."""
    t = index / float(FRAMES - 1)

    # Union of a handful of soft blobs => lumpy puff silhouette.
    sdf = np.full((CELL, CELL), 1e3, dtype=np.float32)
    grow = 0.80 + 0.30 * t
    for i in range(6):
        phase = i * 2.399963 + 0.35 * t  # golden angle, slowly rotating
        offset = (2.5 + 16.0 * t) * (0.25 + 0.75 * ((i * 0.6180339) % 1.0))
        cx = CENTER + math.cos(phase) * offset
        cy = CENTER + math.sin(phase) * offset * 0.9
        radius = (18.0 + 9.0 * t) * (0.85 + 0.5 * ((i * 0.7548776) % 1.0)) * grow
        sdf = np.minimum(sdf, np.sqrt((XX - cx) ** 2 + (YY - cy) ** 2) - radius)

    noise = coherent_noise(t)
    displaced = sdf + (noise - 0.5) * 20.0

    core = 1.0 - smoothstep(-5.0, 13.0, displaced)
    halo = (1.0 - smoothstep(1.0, 34.0, displaced)) * 0.22
    body = np.maximum(core, halo) * (0.60 + 0.40 * COARSE)

    # Soft gaps open up as the puff ages.
    holes = smoothstep(0.66, 0.98, noise) * (0.05 + 0.35 * t)
    body *= 1.0 - holes

    # Transparent margin so atlas sampling never bleeds between cells.
    body *= 1.0 - smoothstep(48.0, 60.0, DIST_FROM_CENTER)

    body = np.clip(body, 0.0, 1.0) * 0.85
    blurred = Image.fromarray((body * 255.0).astype(np.uint8), mode="L")
    blurred = blurred.filter(ImageFilter.GaussianBlur(1.2))
    return np.asarray(blurred, dtype=np.float32) / 255.0


def main() -> None:
    sheet = np.zeros((CELL * GRID, CELL * GRID), dtype=np.float32)
    for index in range(FRAMES):
        row, col = divmod(index, GRID)
        sheet[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL] = build_frame(index)

    alpha = (np.clip(sheet, 0.0, 1.0) * 255.0).astype(np.uint8)
    tint = np.full(alpha.shape, 238, dtype=np.uint8)  # warm white; tinted at runtime
    image = Image.fromarray(np.dstack((tint, tint, np.full_like(tint, 234), alpha)), mode="RGBA")
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    image.save(OUT_PATH)

    preview = Image.new("RGBA", image.size, (28, 30, 34, 255))
    preview.alpha_composite(image)
    preview.convert("RGB").resize((768, 768), Image.LANCZOS).save(PREVIEW_PATH)
    print(f"wrote {OUT_PATH} ({image.size[0]}x{image.size[1]}) and {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
