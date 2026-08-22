# NOTICE

This client is an unofficial Roblox port of the Wurst Client.

It is not affiliated with, endorsed by, or supported by Wurst-Imperium.
Wurst7 remains © 2014-2026 Wurst-Imperium and contributors, licensed under
the GNU General Public License version 3. This port is released under the
same licence; the full text is in `LICENSE`.

Source: https://github.com/Wurst-Imperium/Wurst7

Pinned upstream commit:

    4a22e53d774b9a28e395874834f099e779685998
    2026-08-10  "Update Fabric API"

Every file under `assets/wurst/` (except the checksum manifest) is listed
below. The gate fails if a file is present and missing from this list.

## Vendored files

All of these were copied from `src/main/resources/assets/wurst/` at the
pinned commit, by `tools/fetch_wurst_assets.py`. Copyright (c) 2014-2026
Wurst-Imperium and contributors.

| Local path | Upstream path |
|---|---|
| `assets/wurst/wurst_128.png` | `src/main/resources/assets/wurst/wurst_128.png` |
| `assets/wurst/icon.png` | `src/main/resources/assets/wurst/icon.png` |
| `assets/wurst/colorpalette.png` | `src/main/resources/assets/wurst/colorpalette.png` |
| `assets/wurst/dancingtaco1.png` | `src/main/resources/assets/wurst/dancingtaco1.png` |
| `assets/wurst/dancingtaco2.png` | `src/main/resources/assets/wurst/dancingtaco2.png` |
| `assets/wurst/dancingtaco3.png` | `src/main/resources/assets/wurst/dancingtaco3.png` |
| `assets/wurst/dancingtaco4.png` | `src/main/resources/assets/wurst/dancingtaco4.png` |
| `assets/wurst/translations/en_us.json` | `src/main/resources/assets/wurst/translations/en_us.json` |

## Font fallback (not Minecraft)

`src/gui/Current/Assets/Typography/Monocraft.otf` and the raster
`assets/font/monocraft-16.png` are **Monocraft**, © 2022 Idrees Hassan,
SIL Open Font License 1.1. The OFL text is
`src/gui/Current/Assets/Typography/Monocraft-OFL.txt`. They are the
CI / no-network stand-in behind `state.bitmapText`. They are not
Mojangles, not `ascii.png`, and not an official Minecraft asset.

Minecraft 1.18.1 font sheets (`ascii.png`, `accented.png`,
`unicode_page_*.png`, `glyph_sizes.bin`, `client.jar`) are Mojang /
Microsoft and must not be added to this tree. Pins and the
redistribution reading live in `docs/minecraft-1.18.1-font.md`.
