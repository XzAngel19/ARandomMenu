from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageSequence


@dataclass(frozen=True)
class AssetRegion:
    name: str
    category: str
    box: tuple[int, int, int, int]
    usage: str


REGIONS: tuple[AssetRegion, ...] = (
    AssetRegion("header_eyes_frame", "Frames", (15, 23, 724, 230), "Header frame or featured card"),
    AssetRegion("eye_visuals", "Icons", (63, 45, 258, 214), "Visuals feature"),
    AssetRegion("blossom_branch_wide", "Blossoms", (762, 0, 1536, 207), "Header corner blossom ornament"),
    AssetRegion("progress_bar", "Status", (764, 204, 1513, 245), "Loading and progress status"),
    AssetRegion("arrow_right", "Arrows", (32, 258, 112, 320), "Forward navigation"),
    AssetRegion("arrow_left", "Arrows", (136, 264, 204, 309), "Back navigation"),
    AssetRegion("arrow_up", "Arrows", (225, 258, 300, 327), "Expand upward"),
    AssetRegion("arrow_down", "Arrows", (327, 260, 389, 326), "Collapse downward"),
    AssetRegion("chevrons_right", "Arrows", (418, 267, 523, 315), "Fast forward navigation"),
    AssetRegion("search", "Icons", (548, 258, 624, 327), "Search field"),
    AssetRegion("close", "Icons", (650, 264, 710, 323), "Close popup"),
    AssetRegion("plus", "Icons", (739, 264, 790, 315), "Add or expand"),
    AssetRegion("minus", "Icons", (816, 276, 868, 303), "Remove or collapse"),
    AssetRegion("menu", "Icons", (892, 264, 950, 318), "Menu options"),
    AssetRegion("ellipsis", "Icons", (965, 276, 1029, 307), "More actions"),
    AssetRegion("flame", "Icons", (35, 339, 105, 415), "Highlighted action"),
    AssetRegion("flame_halftone", "Icons", (122, 338, 199, 415), "Highlighted action alternate"),
    AssetRegion("user_small", "Icons", (217, 349, 270, 412), "Player feature"),
    AssetRegion("user_large", "Icons", (283, 348, 341, 412), "Player feature alternate"),
    AssetRegion("target_cross", "Icons", (359, 345, 427, 415), "Targeting feature"),
    AssetRegion("target_plus", "Icons", (432, 344, 501, 415), "Targeting feature alternate"),
    AssetRegion("target_open", "Icons", (509, 344, 575, 415), "Target selection"),
    AssetRegion("target_ring", "Icons", (585, 344, 666, 415), "Target lock"),
    AssetRegion("toggle_texture", "Status", (686, 359, 771, 407), "Toggle control decoration"),
    AssetRegion("status_success_circle", "Status", (790, 347, 855, 414), "Success state"),
    AssetRegion("status_error_circle", "Status", (873, 350, 934, 413), "Error state"),
    AssetRegion("send", "Icons", (958, 353, 1019, 411), "Submit action"),
    AssetRegion("home", "Icons", (36, 428, 104, 491), "Home or universal tab"),
    AssetRegion("settings", "Icons", (118, 424, 190, 497), "Settings and config"),
    AssetRegion("tools", "Icons", (207, 426, 276, 494), "Utility feature"),
    AssetRegion("star", "Icons", (294, 429, 351, 492), "Favorite feature"),
    AssetRegion("heart", "Icons", (367, 432, 416, 487), "Protection or favorite"),
    AssetRegion("button_main", "Status", (451, 434, 637, 487), "Main navigation button frame"),
    AssetRegion("button_visuals", "Status", (648, 436, 838, 489), "Visuals navigation button frame"),
    AssetRegion("button_enable", "Status", (844, 424, 1028, 488), "Enabled state frame"),
    AssetRegion("volume", "Icons", (37, 503, 101, 562), "Audio enabled"),
    AssetRegion("volume_muted", "Icons", (119, 504, 183, 562), "Audio muted"),
    AssetRegion("bell_active", "Icons", (204, 501, 267, 565), "Notifications enabled"),
    AssetRegion("bell", "Icons", (281, 502, 343, 564), "Notifications"),
    AssetRegion("shield", "Icons", (359, 499, 424, 567), "Protection feature"),
    AssetRegion("button_player", "Status", (449, 502, 636, 555), "Player navigation button frame"),
    AssetRegion("button_misc", "Status", (648, 504, 837, 556), "Misc navigation button frame"),
    AssetRegion("button_disable", "Status", (844, 491, 1027, 556), "Disabled state frame"),
    AssetRegion("spinner", "Status", (38, 572, 101, 637), "Loading indicator"),
    AssetRegion("list", "Icons", (115, 575, 184, 633), "List or modules"),
    AssetRegion("warning", "Icons", (207, 571, 271, 639), "Warning and error"),
    AssetRegion("key", "Icons", (294, 573, 339, 638), "Keybind setting"),
    AssetRegion("lock", "Icons", (363, 572, 419, 638), "Security or locked state"),
    AssetRegion("button_settings", "Status", (449, 571, 636, 624), "Settings navigation button frame"),
    AssetRegion("separator_slash", "Decorations", (647, 580, 837, 610), "Manga separator"),
    AssetRegion("button_loading", "Status", (844, 557, 1028, 621), "Loading state frame"),
    AssetRegion("discord", "Icons", (37, 639, 106, 707), "Community link"),
    AssetRegion("twitter", "Icons", (122, 640, 196, 706), "Social link"),
    AssetRegion("spotify", "Icons", (204, 638, 269, 707), "Audio link"),
    AssetRegion("swirl", "Icons", (285, 642, 347, 705), "Misc visual"),
    AssetRegion("masked_user", "Icons", (358, 638, 425, 709), "Player protection"),
    AssetRegion("manga_face", "Icons", (446, 636, 536, 711), "Manga profile decoration"),
    AssetRegion("chart", "Icons", (552, 640, 622, 705), "Performance statistics"),
    AssetRegion("separator_thin", "Decorations", (647, 638, 836, 669), "Thin manga separator"),
    AssetRegion("button_success", "Status", (844, 622, 1028, 685), "Success state frame"),
    AssetRegion("frame_ink_circle", "Frames", (33, 715, 113, 799), "Circular icon frame"),
    AssetRegion("frame_ink_square", "Frames", (115, 715, 190, 799), "Ink square frame"),
    AssetRegion("frame_corner_square", "Frames", (193, 715, 266, 799), "Corner square frame"),
    AssetRegion("frame_round_square", "Frames", (270, 715, 351, 799), "Rounded icon frame"),
    AssetRegion("frame_cut_square", "Frames", (363, 715, 443, 799), "Cut corner icon frame"),
    AssetRegion("frame_plain_square", "Frames", (454, 715, 535, 799), "Plain icon frame"),
    AssetRegion("frame_compact_square", "Frames", (546, 715, 632, 799), "Compact icon frame"),
    AssetRegion("separator_notched", "Decorations", (647, 685, 836, 720), "Notched manga separator"),
    AssetRegion("separator_short", "Decorations", (648, 728, 830, 765), "Short manga separator"),
    AssetRegion("page_indicators", "Status", (645, 775, 775, 817), "Carousel indicators"),
    AssetRegion("button_warning", "Status", (844, 685, 1028, 748), "Warning state frame"),
    AssetRegion("button_error", "Status", (844, 748, 1028, 810), "Error state frame"),
    AssetRegion("spinner_segmented", "Status", (736, 820, 797, 886), "Segmented loader"),
    AssetRegion("spinner_dotted", "Status", (800, 820, 860, 886), "Dotted loader"),
    AssetRegion("spinner_ring", "Status", (861, 819, 922, 886), "Ring loader"),
    AssetRegion("spinner_minimal", "Status", (922, 820, 980, 885), "Minimal loader"),
    AssetRegion("spinner_broken", "Status", (979, 815, 1031, 887), "Broken ink loader"),
    AssetRegion("blossom_scatter_left", "Blossoms", (35, 808, 457, 1024), "Panel blossom decoration"),
    AssetRegion("blossom_scatter_right", "Blossoms", (445, 807, 736, 1024), "Panel blossom decoration alternate"),
    AssetRegion("panel_top", "Frames", (1045, 250, 1520, 342), "Top feature panel"),
    AssetRegion("panel_profile", "Frames", (1043, 345, 1521, 425), "Profile panel"),
    AssetRegion("panel_cracked", "Frames", (1042, 426, 1521, 514), "Cracked highlight panel"),
    AssetRegion("panel_ink", "Frames", (1042, 513, 1521, 600), "Ink highlight panel"),
    AssetRegion("panel_dark", "Frames", (1042, 600, 1521, 681), "Dark highlight panel"),
    AssetRegion("panel_brush", "Frames", (1042, 682, 1521, 751), "Brush highlight panel"),
    AssetRegion("panel_slash", "Frames", (1042, 742, 1521, 806), "Slash separator panel"),
    AssetRegion("panel_notice", "Frames", (1043, 806, 1427, 889), "Notification frame"),
    AssetRegion("panel_notice_icon", "Frames", (1426, 806, 1521, 889), "Notification icon frame"),
    AssetRegion("popup_left", "Frames", (1043, 889, 1180, 1002), "Popup frame left"),
    AssetRegion("popup_center", "Frames", (1180, 889, 1314, 1002), "Popup frame center"),
    AssetRegion("popup_right", "Frames", (1308, 889, 1424, 1002), "Popup frame right"),
    AssetRegion("popup_tall", "Frames", (1425, 889, 1521, 1004), "Popup frame tall"),
)


def transparent_crop(source: Image.Image, box: tuple[int, int, int, int], margin: int) -> Image.Image:
    region = source.crop(box).convert("RGBA")
    pixels = np.asarray(region).copy()
    gray = np.max(pixels[:, :, :3], axis=2)
    visible = gray > 4
    if np.any(visible):
        ys, xs = np.where(visible)
        left = max(0, int(xs.min()) - margin)
        top = max(0, int(ys.min()) - margin)
        right = min(region.width, int(xs.max()) + margin + 1)
        bottom = min(region.height, int(ys.max()) + margin + 1)
        pixels = pixels[top:bottom, left:right]
        gray = gray[top:bottom, left:right]
    alpha = np.clip((gray.astype(np.float32) - 2.0) * 3.2, 0, 255).astype(np.uint8)
    pixels[:, :, 3] = alpha
    pixels[:, :, :3] = np.maximum(pixels[:, :, :3], alpha[:, :, None])
    return Image.fromarray(pixels, "RGBA")


def process_gif(gif_path: Path, assets_root: Path, manifest: dict[str, object]) -> None:
    frame_root = assets_root / "Blossoms" / "Frames"
    frame_root.mkdir(parents=True, exist_ok=True)
    with Image.open(gif_path) as gif:
        frames = [frame.convert("RGBA") for frame in ImageSequence.Iterator(gif)]
        durations = [int(frame.info.get("duration", gif.info.get("duration", 130))) for frame in ImageSequence.Iterator(gif)]
    if len(frames) != 25:
        raise ValueError(f"Expected 25 blossom frames, found {len(frames)}")
    columns = 5
    rows = 5
    frame_width, frame_height = frames[0].size
    sheet = Image.new("RGBA", (frame_width * columns, frame_height * rows), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        frame_name = f"frame_{index + 1:02d}.png"
        frame_path = frame_root / frame_name
        frame.save(frame_path, optimize=True)
        sheet.alpha_composite(frame, ((index % columns) * frame_width, (index // columns) * frame_height))
        manifest["assets"][f"blossom_frame_{index + 1:02d}"] = {
            "category": "Blossoms",
            "path": frame_path.relative_to(assets_root.parent).as_posix(),
            "dimensions": [frame_width, frame_height],
            "usage": "Animated panel background frame",
        }
    sheet_path = assets_root / "Blossoms" / "blossom-spritesheet.png"
    sheet.save(sheet_path, optimize=True)
    manifest["assets"]["blossom_spritesheet"] = {
        "category": "Blossoms",
        "path": sheet_path.relative_to(assets_root.parent).as_posix(),
        "dimensions": [sheet.width, sheet.height],
        "usage": "Animated panel background using ImageRectOffset and ImageRectSize",
        "frames": len(frames),
        "columns": columns,
        "rows": rows,
        "frameDurationMilliseconds": 130,
        "sourceDurationsMilliseconds": durations,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sheet", type=Path, required=True)
    parser.add_argument("--gif", type=Path, required=True)
    parser.add_argument("--header", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    assets_root = args.output.resolve()
    source_root = assets_root / "Source"
    source_root.mkdir(parents=True, exist_ok=True)
    for category in ("Icons", "Arrows", "Frames", "Decorations", "Status", "Blossoms"):
        (assets_root / category).mkdir(parents=True, exist_ok=True)
    source_sheet = source_root / "manga-asset-sheet.png"
    source_gif = source_root / "blossom-animation.gif"
    header_path = assets_root / "header-anime.png"
    shutil.copyfile(args.sheet, source_sheet)
    shutil.copyfile(args.gif, source_gif)
    shutil.copyfile(args.header, header_path)
    manifest: dict[str, object] = {
        "schemaVersion": 2,
        "rawBaseUrl": "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/src/gui/Current/",
        "assets": {},
    }
    with Image.open(args.sheet) as opened:
        sheet = opened.convert("RGBA")
    for region in REGIONS:
        output = transparent_crop(sheet, region.box, 5)
        path = assets_root / region.category / f"{region.name}.png"
        output.save(path, optimize=True)
        manifest["assets"][region.name] = {
            "category": region.category,
            "path": path.relative_to(assets_root.parent).as_posix(),
            "dimensions": [output.width, output.height],
            "usage": region.usage,
        }
    with Image.open(header_path) as header:
        manifest["assets"]["header_anime"] = {
            "category": "Header",
            "path": header_path.relative_to(assets_root.parent).as_posix(),
            "dimensions": [header.width, header.height],
            "usage": "Responsive cropped menu header focused on the eyes",
        }
    process_gif(args.gif, assets_root, manifest)
    manifest_path = assets_root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({"assetCount": len(manifest["assets"]), "manifest": str(manifest_path)}, indent=2))


if __name__ == "__main__":
    main()
