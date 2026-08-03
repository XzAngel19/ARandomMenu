from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


RAW_BASE = "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/src/gui/Current/"


def luminance_alpha(source: Image.Image, contrast: float = 1.7) -> Image.Image:
    rgba = source.convert("RGBA")
    gray = rgba.convert("L")
    alpha = gray.point(lambda value: max(0, min(255, int((value - 14) * contrast))))
    white = Image.new("RGBA", rgba.size, (232, 234, 240, 0))
    white.putalpha(alpha)
    return white


def trim(image: Image.Image, padding: int = 8) -> Image.Image:
    alpha = image.getchannel("A")
    box = alpha.getbbox()
    if box is None:
        return image
    left, top, right, bottom = box
    return image.crop((max(0, left - padding), max(0, top - padding), min(image.width, right + padding), min(image.height, bottom + padding)))


def save_asset(root: Path, relative: str, image: Image.Image, kind: str, usage: str, entries: dict[str, dict[str, object]], key: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    entries[key] = {
        "category": Path(relative).parts[1],
        "path": relative.replace("\\", "/"),
        "localPath": relative.replace("/", "\\"),
        "url": RAW_BASE + relative.replace("\\", "/"),
        "version": 1,
        "type": kind,
        "dimensions": [image.width, image.height],
        "usage": usage,
    }


def make_title() -> Image.Image:
    canvas = Image.new("RGBA", (900, 120), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    font_paths = [Path("C:/Windows/Fonts/georgiab.ttf"), Path("C:/Windows/Fonts/GOTHICB.TTF")]
    font_path = next((path for path in font_paths if path.exists()), font_paths[-1])
    font = ImageFont.truetype(str(font_path), 48)
    text = "A random Testing Menu #0001"
    box = draw.textbbox((0, 0), text, font=font, stroke_width=1)
    x = (canvas.width - (box[2] - box[0])) // 2
    y = (canvas.height - (box[3] - box[1])) // 2 - box[1]
    draw.text((x + 1, y + 2), text, font=font, fill=(15, 15, 18, 150), stroke_width=2, stroke_fill=(0, 0, 0, 140))
    draw.text((x, y), text, font=font, fill=(239, 239, 242, 255), stroke_width=1, stroke_fill=(168, 168, 176, 210))
    random.seed(10001)
    alpha = canvas.getchannel("A")
    alpha_draw = ImageDraw.Draw(alpha)
    for _ in range(120):
        px = random.randrange(max(1, x), min(canvas.width, x + box[2] - box[0]))
        py = random.randrange(max(1, y), min(canvas.height, y + box[3] - box[1]))
        if alpha.getpixel((px, py)) > 80:
            alpha_draw.ellipse((px, py, px + random.randrange(1, 4), py + random.randrange(1, 3)), fill=random.randrange(20, 110))
    canvas.putalpha(alpha)
    return trim(canvas, 5)


def particle_dot() -> Image.Image:
    image = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((7, 8, 24, 23), fill=(242, 243, 246, 210))
    return image.filter(ImageFilter.GaussianBlur(2.2))


def particle_star() -> Image.Image:
    image = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.polygon([(24, 2), (27, 20), (46, 24), (27, 27), (24, 46), (21, 27), (2, 24), (21, 20)], fill=(245, 245, 248, 235))
    draw.ellipse((21, 21, 27, 27), fill=(255, 255, 255, 255))
    return image.filter(ImageFilter.GaussianBlur(0.5))


def ash_fragment() -> Image.Image:
    image = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    ImageDraw.Draw(image).polygon([(8, 7), (27, 13), (22, 29), (14, 24)], fill=(205, 207, 214, 205))
    return image.filter(ImageFilter.GaussianBlur(0.7))


def black_petal() -> Image.Image:
    image = Image.new("RGBA", (42, 54), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((8, 3, 34, 47), fill=(15, 15, 19, 230), outline=(158, 160, 169, 220), width=2)
    draw.line((22, 13, 20, 47), fill=(120, 122, 130, 170), width=1)
    return image


def cross_small() -> Image.Image:
    image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.polygon([(28, 4), (36, 4), (35, 26), (56, 25), (56, 34), (35, 35), (36, 60), (27, 60), (29, 35), (8, 36), (8, 27), (29, 27)], fill=(224, 225, 230, 215))
    return image


def halftone() -> Image.Image:
    image = Image.new("RGBA", (512, 160), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for y in range(8, 160, 12):
        for x in range(8, 512, 12):
            fade = 1.0 - x / 512
            radius = max(1, int(3.5 * fade))
            alpha = int(115 * fade)
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(230, 230, 234, alpha))
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--anime", type=Path, required=True)
    parser.add_argument("--blossoms", type=Path, required=True)
    parser.add_argument("--assets-root", type=Path, required=True)
    args = parser.parse_args()

    root = args.assets_root.parent
    assets = args.assets_root
    reference = Image.open(args.reference).convert("RGB")
    entries: dict[str, dict[str, object]] = {}

    source_path = assets / "Source" / "darkcore-asset-sheet.png"
    source_path.parent.mkdir(parents=True, exist_ok=True)
    reference.save(source_path, optimize=True)

    anime = Image.open(args.anime).convert("RGB")
    anime_path = assets / "Header" / "anime-header.jpg"
    anime_path.parent.mkdir(parents=True, exist_ok=True)
    anime.save(anime_path, quality=94, optimize=True)
    entries["anime_header"] = {"category": "Header", "path": "Assets/Header/anime-header.jpg", "localPath": "Assets\\Header\\anime-header.jpg", "url": RAW_BASE + "Assets/Header/anime-header.jpg", "version": 1, "type": "image/jpeg", "dimensions": [anime.width, anime.height], "usage": "Exclusive cropped image for AnimeHeader"}

    blossoms = Image.open(args.blossoms).convert("RGBA")
    save_asset(root, "Assets/Animations/blossoms-spritesheet.png", blossoms, "image/png", "25-frame 5x5 animated content background", entries, "blossoms_spritesheet")
    save_asset(root, "Assets/Typography/title-logo.png", make_title(), "image/png", "Gothic distressed header title", entries, "title_logo")
    save_asset(root, "Assets/Particles/snow-dot.png", particle_dot(), "image/png", "Soft white atmosphere particle", entries, "particle_snow_dot")
    save_asset(root, "Assets/Particles/emo-star.png", particle_star(), "image/png", "Four-point atmosphere star", entries, "particle_emo_star")
    save_asset(root, "Assets/Particles/ash-fragment.png", ash_fragment(), "image/png", "Slow falling ash fragment", entries, "particle_ash_fragment")
    save_asset(root, "Assets/Particles/black-petal.png", black_petal(), "image/png", "Dark falling petal", entries, "particle_black_petal")
    save_asset(root, "Assets/Decorations/cross-small.png", cross_small(), "image/png", "Small non-interactive darkcore cross", entries, "decor_cross_small")
    save_asset(root, "Assets/Decorations/halftone-fade.png", halftone(), "image/png", "Manga halftone edge fade", entries, "decor_halftone_fade")

    crop_specs = {
        "decor_spike_corner_left": ("Assets/Decorations/spike-corner-left.png", (18, 0, 225, 168), "Lower-left angular spikes"),
        "decor_spike_corner_right": ("Assets/Decorations/spike-corner-right.png", (799, 0, 1015, 168), "Lower-right angular spikes"),
        "decor_chain_divider": ("Assets/Decorations/chain-divider.png", (24, 758, 508, 820), "Thin chain section divider"),
        "decor_ink_scratch": ("Assets/Decorations/ink-scratch.png", (24, 830, 998, 954), "Ink scratch accent"),
    }
    for key, (relative, box, usage) in crop_specs.items():
        cropped = trim(luminance_alpha(reference.crop(box), 2.0), 4)
        if key.endswith("right"):
            cropped = cropped.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        save_asset(root, relative, cropped, "image/png", usage, entries, key)

    manifest_path = assets / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["schemaVersion"] = 3
    manifest["rawBaseUrl"] = RAW_BASE
    for key, entry in manifest.get("assets", {}).items():
        entry.setdefault("localPath", str(entry.get("path", "")).replace("/", "\\"))
        entry.setdefault("url", RAW_BASE + str(entry.get("path", "")))
        entry.setdefault("version", 1)
        entry.setdefault("type", "image/png")
    manifest["assets"].update(entries)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
