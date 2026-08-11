# -*- coding: utf-8 -*-
"""Generate app icon: black background, deep green 'Reg' text with green glow."""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# Config
BG_COLOR = (0, 0, 0)
TEXT_COLOR = (0, 170, 68)
GLOW_COLOR = (0, 220, 100)
CORNER_RATIO = 0.16
TEXT = "Reg"
MASTER_SIZE = 1024

ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANDROID_RES = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res")
WINDOWS_RES = os.path.join(PROJECT_ROOT, "windows", "runner", "resources")


def create_icon(master_size):
    corner_radius = int(master_size * CORNER_RATIO)
    padding = int(master_size * 0.08)

    # Rounded black background
    icon = Image.new("RGBA", (master_size, master_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)
    draw.rounded_rectangle(
        [(0, 0), (master_size - 1, master_size - 1)],
        radius=corner_radius,
        fill=BG_COLOR,
    )

    # Find font
    font = None
    max_text_width = master_size - padding * 2
    max_text_height = master_size - padding * 2
    font_candidates = [
        "C:\\Windows\\Fonts\\arialbd.ttf",
        "C:\\Windows\\Fonts\\Arialbd.ttf",
        "C:\\Windows\\Fonts\\segoeuib.ttf",
        "C:\\Windows\\Fonts\\segoeui.ttf",
        "C:\\Windows\\Fonts\\arial.ttf",
    ]
    for fp in font_candidates:
        if os.path.exists(fp):
            for size_candidate in range(master_size // 2, master_size // 6, -4):
                try:
                    f = ImageFont.truetype(fp, size_candidate)
                    bbox = f.getbbox(TEXT)
                    if (bbox[2] - bbox[0]) <= max_text_width and (bbox[3] - bbox[1]) <= max_text_height:
                        font = f
                        break
                except Exception:
                    continue
            if font:
                break
    if font is None:
        font = ImageFont.load_default()

    # Text layer (white)
    text_layer = Image.new("RGBA", (master_size, master_size), (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_layer)
    bbox = font.getbbox(TEXT)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (master_size - tw) // 2 - bbox[0]
    ty = (master_size - th) // 2 - bbox[1]
    text_draw.text((tx, ty), TEXT, font=font, fill=(255, 255, 255, 255))

    # Glow layer
    glow_layer = text_layer.filter(ImageFilter.GaussianBlur(radius=master_size * 0.035))
    glow_pixels = glow_layer.load()
    for y in range(master_size):
        for x in range(master_size):
            a = glow_pixels[x, y][3]
            if a > 0:
                glow_pixels[x, y] = (*GLOW_COLOR, a)

    # Composite
    result = Image.new("RGBA", (master_size, master_size), BG_COLOR)
    result = Image.alpha_composite(result, icon)
    result = Image.alpha_composite(result, glow_layer)
    green_text = Image.new("RGBA", (master_size, master_size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(green_text)
    gd.text((tx, ty), TEXT, font=font, fill=(*TEXT_COLOR, 255))
    result = Image.alpha_composite(result, green_text)

    return result


def main():
    print("Creating master icon (1024x1024)...")
    master = create_icon(MASTER_SIZE)

    print("\nAndroid icons:")
    for dir_name, size in ANDROID_SIZES.items():
        resized = master.resize((size, size), Image.LANCZOS)
        rgb = Image.new("RGB", (size, size), BG_COLOR)
        if resized.mode == "RGBA":
            rgb.paste(resized, (0, 0), resized)
        else:
            rgb = resized.convert("RGB")
        path = os.path.join(ANDROID_RES, dir_name, "ic_launcher.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        rgb.save(path, "PNG")
        print("  [OK] " + path)

    print("\nWindows icon:")
    ico_path = os.path.join(WINDOWS_RES, "app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    ico_sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (256, 256)]
    master.save(ico_path, "ICO", sizes=ico_sizes)
    print("  [OK] " + ico_path)

    print("\nDone!")


if __name__ == "__main__":
    main()