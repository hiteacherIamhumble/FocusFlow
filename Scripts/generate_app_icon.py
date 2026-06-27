#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "Resources" / "AppIcon.iconset"
ICONSET.mkdir(parents=True, exist_ok=True)

SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

def lerp(a, b, t):
    return int(a + (b - a) * t)

def make_icon(size: int) -> Image.Image:
    scale = size / 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Warm canvas rounded square.
    radius = int(220 * scale)
    for y in range(size):
        t = y / max(1, size - 1)
        color = (
            lerp(247, 238, t),
            lerp(244, 248, t),
            lerp(237, 255, t),
            255,
        )
        draw.line([(0, y), (size, y)], fill=color)
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.putalpha(mask)

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([int(246*scale), int(250*scale), int(806*scale), int(810*scale)], fill=(47, 52, 64, 45))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(34 * scale)))
    img = Image.alpha_composite(img, shadow)

    draw = ImageDraw.Draw(img)
    # Focus blue ring, intentionally open to suggest returning.
    bbox = [int(238*scale), int(220*scale), int(786*scale), int(768*scale)]
    width = max(3, int(76 * scale))
    draw.arc(bbox, start=34, end=324, fill=(91, 124, 250, 255), width=width)

    # Mint progress leaf/check shape.
    draw.rounded_rectangle(
        [int(420*scale), int(478*scale), int(688*scale), int(574*scale)],
        radius=int(48*scale),
        fill=(123, 201, 154, 255),
    )
    draw.rounded_rectangle(
        [int(360*scale), int(390*scale), int(474*scale), int(662*scale)],
        radius=int(56*scale),
        fill=(123, 201, 154, 255),
    )

    # Peach start point.
    draw.ellipse(
        [int(318*scale), int(284*scale), int(450*scale), int(416*scale)],
        fill=(255, 184, 107, 255),
    )

    # Inner calm dot.
    draw.ellipse(
        [int(478*scale), int(412*scale), int(590*scale), int(524*scale)],
        fill=(255, 255, 255, 230),
    )

    return img

for name, size in SIZES.items():
    make_icon(size).save(ICONSET / name)

print(ICONSET)
