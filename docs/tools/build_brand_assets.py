#!/usr/bin/env python3
"""Build the Cart Slop GP website brand assets from the official game art.

Single source of truth
----------------------
* ``godot_project/assets/ui/cart_icon.png``  512x512 squircle app icon — the logo.
* ``godot_project/assets/ui/boot_splash.png`` 1280x720 launch art — hero/OG backplate.
* ``godot_project/assets/ui/fonts/``          official game fonts (OFL/licensed).

Nothing is invented and nothing is downloaded: every pixel below is a resize,
crop or composite of those files. The script is deterministic (fixed-resample,
no timestamps in the output), needs only Pillow, and writes a manifest with the
source and output hashes so `--check` can prove the checked-in derivatives still
belong to the current official art.

Usage (from the folder that contains website/):
    python website/tools/build_brand_assets.py          # (re)generate
    python website/tools/build_brand_assets.py --check  # verify only, no writes

Outputs under website/assets/:
    brand/logo.png  brand/logo-192.png  brand/logo-64.png
    favicon-16x16.png  favicon-32x32.png  favicon-48x48.png  favicon.ico
    apple-touch-icon.png  icon-192.png  icon-512.png  icon-512-maskable.png
    og-image.png  hero.webp  hero.jpg
    fonts/Fredoka-Medium.ttf  fonts/LuckiestGuy-Regular.ttf  (+ licenses)
    brand-manifest.json  favicon-32-data-uri.txt
"""
from __future__ import annotations

import hashlib
import io
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
WEBSITE = os.path.dirname(HERE)
WORKSPACE = os.path.dirname(WEBSITE)
GAME_UI = os.path.join(WORKSPACE, "godot_project", "assets", "ui")
if not os.path.isdir(GAME_UI):
    # website/ lives inside the game repository in the GitHub layout.
    GAME_UI = os.path.join(WORKSPACE, "assets", "ui")
ICON_SRC = os.path.join(GAME_UI, "cart_icon.png")
SPLASH_SRC = os.path.join(GAME_UI, "boot_splash.png")
FONT_DIR = os.path.join(GAME_UI, "fonts")
DIST = os.path.join(WEBSITE, "assets")
BRAND = os.path.join(DIST, "brand")
FONTS_OUT = os.path.join(DIST, "fonts")
MANIFEST = os.path.join(DIST, "brand-manifest.json")

FONT_DISPLAY = "LuckiestGuy-Regular.ttf"
FONT_BODY = "Fredoka-Medium.ttf"
FONT_LICENSE_FILES = ("OFL-Fredoka.txt", "LICENSE-LuckiestGuy.txt")

# Brand palette lifted from the game's UI (scripts/ui/ui_palette.gd) and the
# app icon: near-black navy shells, cyan glass rims, yellow and red accents.
BG = (10, 13, 26, 255)          # #0a0d1a page backplate
SURFACE = (14, 18, 38, 255)     # #0e1226
CYAN = (69, 182, 240, 255)      # #45b6f0
YELLOW = (255, 210, 46, 255)    # #ffd22e
CREAM = (255, 246, 227, 255)    # #fff6e3
RED = (242, 84, 91, 255)        # #f2545b


def rel(path: str) -> str:
    return os.path.relpath(path, WEBSITE).replace("\\", "/")


def rel_to_workspace(path: str) -> str:
    return os.path.relpath(path, WORKSPACE).replace("\\", "/")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_sources() -> tuple[Image.Image, Image.Image]:
    for path in (ICON_SRC, SPLASH_SRC):
        if not os.path.isfile(path):
            raise SystemExit("missing official brand source: " + path)
    icon = Image.open(ICON_SRC).convert("RGBA")
    splash = Image.open(SPLASH_SRC).convert("RGB")
    if icon.size != (512, 512):
        raise SystemExit("unexpected cart_icon.png size %r (expected 512x512)"
                         % (icon.size,))
    if splash.size != (1280, 720):
        raise SystemExit("unexpected boot_splash.png size %r (expected 1280x720)"
                         % (splash.size,))
    return icon, splash


def resize(icon: Image.Image, size: int) -> Image.Image:
    return icon.resize((size, size), Image.Resampling.LANCZOS)


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def write_bytes(path: str, payload: bytes) -> dict:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(payload)
    return {"path": rel(path), "bytes": len(payload),
            "sha256": sha256_bytes(payload)}


def make_icon_with_background(icon: Image.Image, size: int,
                              scale: float) -> Image.Image:
    """Square brand plate: dark navy background + centred official logo."""
    canvas = Image.new("RGBA", (size, size), BG)
    inner = max(1, int(size * scale))
    mark = resize(icon, inner)
    offset = (size - inner) // 2
    canvas.alpha_composite(mark, (offset, offset))
    return canvas


def load_font(name: str, size: int) -> ImageFont.FreeTypeFont:
    path = os.path.join(FONT_DIR, name)
    if not os.path.isfile(path):
        raise SystemExit("missing official font: " + path)
    return ImageFont.truetype(path, size)


def draw_slanted_bar(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                     skew: int, fill: tuple[int, int, int, int]) -> None:
    """A brand parallelogram (the game UI's black-slanted motif)."""
    left, top, right, bottom = box
    draw.polygon(
        [(left + skew, top), (right, top), (right - skew, bottom), (left, bottom)],
        fill=fill)


def cover_crop(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize + centre-crop, the CSS `background-size: cover` equivalent."""
    target_w, target_h = size
    source_w, source_h = image.size
    scale = max(target_w / source_w, target_h / source_h)
    scaled = image.resize(
        (max(1, round(source_w * scale)), max(1, round(source_h * scale))),
        Image.Resampling.LANCZOS)
    left = (scaled.width - target_w) // 2
    top = (scaled.height - target_h) // 2
    return scaled.crop((left, top, left + target_w, top + target_h))


def fit_font(name: str, text: str, max_width: int, start: int,
             minimum: int = 12) -> ImageFont.FreeTypeFont:
    """Largest official-font size at which `text` fits `max_width`."""
    size = start
    while size > minimum:
        font = load_font(name, size)
        box = font.getbbox(text)
        if box[2] - box[0] <= max_width:
            return font
        size -= 2
    return load_font(name, minimum)


def build_og_image(icon: Image.Image, splash: Image.Image) -> Image.Image:
    """1200x630 OpenGraph/Twitter card: official art + official fonts.

    Layout mirrors the black-slanted UI: a dark plate with a skewed right edge
    over the official boot-splash artwork, the official app icon as the logo,
    the display font for the title and the body font for the taglines.
    """
    width, height = 1200, 630
    canvas = cover_crop(splash, (width, height)).convert("RGBA")

    # Black slanted plate over the left 55 % with a skewed edge.
    edge_top, edge_bottom = 612, 724
    plate = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    plate_draw = ImageDraw.Draw(plate)
    plate_draw.polygon([(0, 0), (edge_top, 0), (edge_bottom, height), (0, height)],
                       fill=(8, 10, 22, 236))
    # Soft fade into the artwork so the skew edge is not a hard poster cut.
    for step in range(1, 9):
        alpha = int(120 * (1.0 - step / 9.0))
        plate_draw.polygon(
            [(edge_top - 16 * step, 0),
             (edge_top - 16 * (step - 1), 0),
             (edge_bottom - 16 * (step - 1), height),
             (edge_bottom - 16 * step, height)],
            fill=(8, 10, 22, alpha))
    canvas.alpha_composite(plate)
    draw = ImageDraw.Draw(canvas)

    # Brand slanted rails on the plate edge (cyan + yellow, the UI accents).
    draw.polygon([(edge_top - 18, 0), (edge_top - 8, 0),
                  (edge_bottom - 8, height), (edge_bottom - 18, height)],
                 fill=CYAN)
    draw.polygon([(edge_top - 4, 0), (edge_top + 2, 0),
                  (edge_bottom + 2, height), (edge_bottom - 4, height)],
                 fill=YELLOW)
    # Left edge accent bar: a thin vertical brand stripe with the same skew.
    draw_slanted_bar(draw, (0, 0, 10, height), 0, CYAN)
    draw_slanted_bar(draw, (14, 0, 18, height), 0, YELLOW)

    # Logo (official app icon, resampled only).
    logo = resize(icon, 116)
    canvas.alpha_composite(logo, (56, 48))
    wordmark_font = load_font(FONT_BODY, 22)
    draw.text((186, 76), "CART SLOP GP", font=wordmark_font,
              fill=(185, 200, 225, 255))

    # Title, auto-fitted to the plate width.
    title = "CART SLOP GP"
    title_font = fit_font(FONT_DISPLAY, title, 520, 92)
    title_box = title_font.getbbox(title)
    draw.text((56, 178), title, font=title_font, fill=CREAM)
    title_bottom = 178 + (title_box[3] - title_box[1])

    # Version chip: slanted yellow plate with dark ink (skew echoes the UI).
    chip_text = "V0.8.7"
    chip_font = load_font(FONT_DISPLAY, 30)
    chip_box = chip_font.getbbox(chip_text)
    chip_w = (chip_box[2] - chip_box[0]) + 44
    chip_h = 44
    chip_top = title_bottom + 6
    draw.polygon([(56, chip_top), (56 + chip_w, chip_top),
                  (56 + chip_w - 12, chip_top + chip_h),
                  (44, chip_top + chip_h)], fill=YELLOW)
    draw.text((62, chip_top + 4), chip_text, font=chip_font, fill=BG)

    # Taglines in the official body font.
    tag_font = load_font(FONT_BODY, 30)
    small_font = load_font(FONT_BODY, 24)
    draw.text((56, chip_top + chip_h + 24), "ARCADE KART RACING",
              font=tag_font, fill=CREAM)
    draw.text((56, chip_top + chip_h + 62), "& 8-PLAYER PARTY MAYHEM",
              font=tag_font, fill=CREAM)

    # Platform footer with a cyan hairline.
    draw.line([(56, 528), (edge_top - 60, 528)], fill=(69, 182, 240, 170),
              width=2)
    draw.text((56, 548), "WINDOWS   •   MACOS   •   LINUX   •   WEB",
              font=small_font, fill=(185, 200, 225, 255))
    return canvas.convert("RGB")


def build_all() -> dict:
    icon, splash = load_sources()
    outputs: list[dict] = []

    def emit_png(path: str, image: Image.Image) -> None:
        outputs.append(write_bytes(path, png_bytes(image)))

    # --- Logo set (exact official art, only resampled) ---
    emit_png(os.path.join(BRAND, "logo.png"), resize(icon, 512))
    emit_png(os.path.join(BRAND, "logo-192.png"), resize(icon, 192))
    emit_png(os.path.join(BRAND, "logo-64.png"), resize(icon, 64))

    # --- Favicons ---
    emit_png(os.path.join(DIST, "favicon-16x16.png"), resize(icon, 16))
    emit_png(os.path.join(DIST, "favicon-32x32.png"), resize(icon, 32))
    emit_png(os.path.join(DIST, "favicon-48x48.png"), resize(icon, 48))
    # Inline copy for the Pi's server-rendered pages (/play, /login, console):
    # a 32 px palette-quantised PNG is ~1/3 the bytes of the full-colour one at
    # the same look at that size, which matters when it is embedded three times.
    embed_icon = resize(icon, 32).quantize(
        colors=96, method=Image.Quantize.FASTOCTREE,
        dither=Image.Dither.NONE)
    embed_buffer = io.BytesIO()
    embed_icon.save(embed_buffer, format="PNG", optimize=True)
    outputs.append(write_bytes(os.path.join(DIST, "favicon-embed.png"),
                               embed_buffer.getvalue()))
    ico_buffer = io.BytesIO()
    resize(icon, 48).save(ico_buffer, format="ICO",
                          sizes=[(16, 16), (32, 32), (48, 48)])
    outputs.append(write_bytes(os.path.join(DIST, "favicon.ico"),
                               ico_buffer.getvalue()))
    emit_png(os.path.join(DIST, "apple-touch-icon.png"),
             make_icon_with_background(icon, 180, 0.84))
    emit_png(os.path.join(DIST, "icon-192.png"),
             make_icon_with_background(icon, 192, 0.88))
    emit_png(os.path.join(DIST, "icon-512.png"),
             make_icon_with_background(icon, 512, 0.88))
    # Android maskable icons must keep the logo inside the 80 % safe circle.
    emit_png(os.path.join(DIST, "icon-512-maskable.png"),
             make_icon_with_background(icon, 512, 0.68))

    # --- Social preview ---
    emit_png(os.path.join(DIST, "og-image.png"), build_og_image(icon, splash))

    # --- Hero backplate: official launch art, compressed for the web ---
    hero = cover_crop(splash, (1280, 720))
    webp_buffer = io.BytesIO()
    hero.save(webp_buffer, format="WEBP", quality=86, method=6)
    outputs.append(write_bytes(os.path.join(DIST, "hero.webp"),
                               webp_buffer.getvalue()))
    jpg_buffer = io.BytesIO()
    hero.save(jpg_buffer, format="JPEG", quality=84, optimize=True,
              progressive=True)
    outputs.append(write_bytes(os.path.join(DIST, "hero.jpg"),
                               jpg_buffer.getvalue()))

    # --- Official fonts (game UI typefaces; licenses travel with them) ---
    os.makedirs(FONTS_OUT, exist_ok=True)
    for name in (FONT_DISPLAY, FONT_BODY):
        source = os.path.join(FONT_DIR, name)
        if not os.path.isfile(source):
            raise SystemExit("missing official font: " + source)
        destination = os.path.join(FONTS_OUT, name)
        shutil.copyfile(source, destination)
        outputs.append({"path": rel(destination),
                        "bytes": os.path.getsize(destination),
                        "sha256": sha256_file(destination)})
    for name in FONT_LICENSE_FILES:
        source = os.path.join(FONT_DIR, name)
        if os.path.isfile(source):
            destination = os.path.join(FONTS_OUT, name)
            shutil.copyfile(source, destination)
            outputs.append({"path": rel(destination),
                            "bytes": os.path.getsize(destination),
                            "sha256": sha256_file(destination)})

    # --- Data URI for the server-rendered pages (/play, /login, console) ---
    favicon_embed = read_bytes(os.path.join(DIST, "favicon-embed.png"))
    import base64
    data_uri = "data:image/png;base64," + base64.b64encode(
        favicon_embed).decode("ascii")
    uri_path = os.path.join(DIST, "favicon-32-data-uri.txt")
    outputs.append(write_bytes(uri_path, (data_uri + "\n").encode("ascii")))

    manifest = {
        "generator": "website/tools/build_brand_assets.py",
        "format": 1,
        "palette": {
            "bg": "#0a0d1a", "surface": "#0e1226", "cyan": "#45b6f0",
            "yellow": "#ffd22e", "cream": "#fff6e3", "red": "#f2545b",
        },
        "sources": [
            {"path": rel_to_workspace(ICON_SRC),
             "bytes": os.path.getsize(ICON_SRC),
             "sha256": sha256_file(ICON_SRC), "role": "logo"},
            {"path": rel_to_workspace(SPLASH_SRC),
             "bytes": os.path.getsize(SPLASH_SRC),
             "sha256": sha256_file(SPLASH_SRC), "role": "hero/og art"},
        ],
        # The data URI itself is a generated output file; keep its hash and
        # length in the manifest instead of duplicating ~2 KB of base64.
        "favicon_data_uri_32_sha256": sha256_bytes(data_uri.encode("ascii")),
        "favicon_data_uri_32_bytes": len(data_uri),
        "outputs": sorted(outputs, key=lambda item: item["path"]),
    }
    payload = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    write_bytes(MANIFEST, payload.encode("utf-8"))
    return manifest


def read_bytes(path: str) -> bytes:
    with open(path, "rb") as handle:
        return handle.read()


def check(manifest: dict) -> int:
    problems: list[str] = []
    for source in manifest["sources"]:
        path = os.path.join(WORKSPACE, source["path"])
        if not os.path.isfile(path):
            problems.append("missing source " + source["path"])
        elif sha256_file(path) != source["sha256"]:
            problems.append("source changed since assets were built: "
                            + source["path"])
    for output in manifest["outputs"]:
        path = os.path.join(WEBSITE, output["path"])
        if not os.path.isfile(path):
            problems.append("missing output " + output["path"])
            continue
        actual = os.path.getsize(path)
        if actual != output["bytes"]:
            problems.append("%s is %d bytes, manifest says %d"
                            % (output["path"], actual, output["bytes"]))
        if sha256_file(path) != output["sha256"]:
            problems.append("%s does not match its recorded hash"
                            % output["path"])
    uri_path = os.path.join(DIST, "favicon-32-data-uri.txt")
    if os.path.isfile(uri_path):
        uri = read_bytes(uri_path).decode("ascii").strip()
        if sha256_bytes(uri.encode("ascii")) != \
                manifest.get("favicon_data_uri_32_sha256"):
            problems.append("favicon-32-data-uri.txt does not match the "
                            "manifest")
    else:
        problems.append("missing favicon-32-data-uri.txt")
    if problems:
        for problem in problems:
            print("BRAND CHECK FAILED: " + problem, file=sys.stderr)
        return 1
    print("BRAND CHECK OK: %d generated assets from %d official sources"
          % (len(manifest["outputs"]), len(manifest["sources"])))
    return 0


def main(argv: list[str]) -> int:
    check_only = "--check" in argv
    if check_only:
        if not os.path.isfile(MANIFEST):
            print("BRAND CHECK FAILED: no " + MANIFEST, file=sys.stderr)
            return 1
        with open(MANIFEST, "r", encoding="utf-8") as handle:
            return check(json.load(handle))
    manifest = build_all()
    total = sum(item["bytes"] for item in manifest["outputs"])
    print("BRAND BUILD OK: %d files, %.1f KB" % (len(manifest["outputs"]),
                                                total / 1024.0))
    for item in manifest["outputs"]:
        print("  %-42s %8d bytes" % (item["path"], item["bytes"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
