"""Pack Poly Haven CC0 diffuse+alpha pairs into RGBA PNG cards, and generate
the dust/leaf particle sprites used by the MEADOW LOOP effects layer.

Inputs:  assets/textures/polyhaven/*_diff.jpg + *_alpha.jpg (CC0, 1k)
Outputs: assets/textures/foliage/*.png (original CC0-derived works)

Run:  python tools/build_foliage_atlases.py
"""

from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageFilter

SRC = os.path.join("assets", "textures", "polyhaven")
OUT = os.path.join("assets", "textures", "foliage")

PAIRS = [
    ("leaf_broad_diff.jpg", "leaf_broad_alpha.jpg", "leaf_broad.png"),
    ("leaf_diff.jpg", "leaf_alpha.jpg", "leaf_frond.png"),
    ("grassblade_diff.jpg", "grassblade_alpha.jpg", "grass_card.png"),
    ("fern_diff.jpg", "fern_alpha.jpg", "fern_card.png"),
]


def _dilate(rgb: np.ndarray, alpha: np.ndarray, passes: int = 3) -> np.ndarray:
    """Push colour under the transparent pixels so mipmaps have no dark halo."""
    result = rgb.copy()
    mask = alpha < 0.08
    for _ in range(passes):
        padded = np.pad(result, ((1, 1), (1, 1), (0, 0)), mode="edge")
        neighbours = np.stack([
            padded[:-2, 1:-1], padded[2:, 1:-1],
            padded[1:-1, :-2], padded[1:-1, 2:],
            padded[:-2, :-2], padded[:-2, 2:],
            padded[2:, :-2], padded[2:, 2:],
        ])
        blurred = neighbours.mean(axis=0)
        result = np.where(mask[..., None], 0.55 * result + 0.45 * blurred, result)
    return result


def pack(diff_name: str, alpha_name: str, out_name: str) -> None:
    diffuse = Image.open(os.path.join(SRC, diff_name)).convert("RGB")
    alpha = Image.open(os.path.join(SRC, alpha_name)).convert("L")
    rgb = np.asarray(diffuse, dtype=np.float32) / 255.0
    a = np.asarray(alpha, dtype=np.float32) / 255.0
    # The Poly Haven alpha maps are near-black backgrounds with a little JPEG
    # noise; a hard shoulder removes the speckle without eating fine fronds.
    a = np.clip((a - 0.12) / 0.72, 0.0, 1.0)
    rgb = _dilate(rgb, a)
    rgba = np.concatenate([rgb, a[..., None]], axis=2)
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), mode="RGBA") \
        .save(os.path.join(OUT, out_name))
    print("wrote", os.path.join(OUT, out_name))


def dust_puff() -> None:
    """Soft warm-grey puff, used by the kart's dirt GPUParticles3D."""
    size = 128
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) / 2.0
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (size * 0.5)
    body = np.clip(1.0 - d, 0.0, 1.0) ** 1.7
    rng = np.random.default_rng(771)
    grain = rng.random((size, size)).astype(np.float32)
    body *= 0.82 + 0.18 * grain
    rgba = np.zeros((size, size, 4), dtype=np.float32)
    rgba[..., 0] = 0.86
    rgba[..., 1] = 0.79
    rgba[..., 2] = 0.66
    rgba[..., 3] = np.clip(body, 0, 1) * 0.9
    Image.fromarray((rgba * 255).astype(np.uint8), mode="RGBA") \
        .save(os.path.join(OUT, "dust_puff.png"))
    print("wrote", os.path.join(OUT, "dust_puff.png"))


def drifting_leaf() -> None:
    """Tiny single-leaf silhouette for the ambient floating-leaf particles."""
    size = 64
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    nx = (x - size / 2) / (size * 0.32)
    ny = (y - size / 2) / (size * 0.46)
    # Pointed oval: |x|^(1.4) + |y|^(1.4) < 1
    shape = np.abs(nx) ** 1.4 + np.abs(ny) ** 1.4
    mask = (shape < 1.0).astype(np.float32)
    vein = np.exp(-((nx * 6.0) ** 2)) * mask
    rgba = np.zeros((size, size, 4), dtype=np.float32)
    rgba[..., 0] = 0.42 + vein * 0.25
    rgba[..., 1] = 0.55 + vein * 0.28
    rgba[..., 2] = 0.22 + vein * 0.15
    rgba[..., 3] = mask * 0.95
    Image.fromarray((rgba * 255).astype(np.uint8), mode="RGBA") \
        .save(os.path.join(OUT, "drifting_leaf.png"))
    print("wrote", os.path.join(OUT, "drifting_leaf.png"))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for triple in PAIRS:
        pack(*triple)
    dust_puff()
    drifting_leaf()


if __name__ == "__main__":
    main()
