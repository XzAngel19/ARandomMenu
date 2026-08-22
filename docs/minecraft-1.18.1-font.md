# Minecraft 1.18.1 font authority

Wurst 7.19 draws every label with `WurstClient.MC.font`
(`net.minecraft.client.gui.Font`). That object is **Minecraft 1.18.1's
default font**, not a face Wurst ships. This file is the pin so A and
the gate stop treating the font as "`ascii.png`, advance 6".

This is a technical reading of public launcher metadata, the 1.18.1
`default.json` provider stack, and the Java renderer. It is **not**
legal advice and it is **not** a licence to copy Mojang files.

## For A — do this, do not do that

Do:

- Keep Monocraft (`assets/font/monocraft-16.png`, OFL) as the CI /
  no-network fallback. Label it Monocraft.
- If you implement exact Mojang glyphs: download the official
  `client.jar` in an explicit update mode, verify
  SHA1 `7e46fb47609401970e2818989fa584fd467cd036`, extract, generate a
  **local** atlas, do not commit the jar, the PNGs, `glyph_sizes.bin`,
  or the derived atlas.
- Measure width from per-glyph advances (scanned last opaque column
  + 1). Space is the empty `U+0020` cell in `ascii.png`, not 6.
- Logical line is 9. Shadow is the same glyphs at `+1,+1` with RGB
  quartered. Missing characters are the tofu rectangle, not a skip.

Do not:

- Vendor `ascii.png`, `accented.png`, `nonlatin_european.png`,
  `unicode_page_*.png`, `glyph_sizes.bin`, `default.json`, or
  `client.jar`.
- Call `monocraft-16.png` "Minecraft exact", `MC.font`, or Mojangles.
- Assume a single advance of 6 (old spec) or 11 (Monocraft cell).
- Assume 1.20+ providers (`space`, `unihex`, `reference`, `include`).
  1.18.1 does not have them.

Machine-readable pin: `assets/font/minecraft-1.18.1.manifest.json`.

## Official pins

| What | Value |
|---|---|
| Version id | `1.18.1` |
| Type | release |
| Release date | 2021-12-10 |
| Protocol | 757 |
| Data version | 2865 |
| Resource / data pack format | 8 |
| Minimum Java | 17 |
| Version manifest v2 | https://piston-meta.mojang.com/mc/game/version_manifest_v2.json |
| Version JSON | https://piston-meta.mojang.com/v1/packages/b0bdc637e4c4cbf0501500cbaad5a757b04848ed/1.18.1.json |
| Version JSON SHA1 | `b0bdc637e4c4cbf0501500cbaad5a757b04848ed` |
| Client JAR | https://piston-data.mojang.com/v1/objects/7e46fb47609401970e2818989fa584fd467cd036/client.jar |
| Client JAR SHA1 | `7e46fb47609401970e2818989fa584fd467cd036` |
| Server JAR SHA1 | `125e5adf40c659fd3bce3e66e67a16bb49ecc1b9` |
| Wiki | https://minecraft.wiki/w/Java_Edition_1.18.1 |
| Font providers (wiki) | https://minecraft.wiki/w/Font |

The SHA1 of the version JSON *is* the path segment after `/packages/`.
A downloader must fetch the manifest, select `id == "1.18.1"`, then
verify that JSON against `b0bdc637…` before trusting the client URL.

The asset index lives inside that version JSON. Font JSON and the
bitmap sheets used by `default` / `alt` / `illageralt` / `uniform`
ship **inside the client JAR** at:

- `assets/minecraft/font/*.json`
- `assets/minecraft/font/glyph_sizes.bin`
- `assets/minecraft/textures/font/*.png`

That is the one file to download. Do not scrape third-party mirrors
for pixels.

## What 1.18.1 actually loads

Four named fonts exist. Wurst's ClickGUI / HackList / Navigator use
the **default** one (`minecraft:default`).

| Font | File | Used for |
|---|---|---|
| default | `assets/minecraft/font/default.json` | Almost all in-game text. Wurst. |
| uniform | `uniform.json` | Force-Unicode / "Unicode font" option. |
| alt | `alt.json` | Enchanting-table SGA. |
| illageralt | `illageralt.json` | Unused unless a command formats with it. |

### `default.json` provider stack (first match wins)

There is **no** `space` provider, **no** `ttf`, **no** `unihex`,
**no** `reference`, **no** `include`. Those arrived in later
versions (unihex / include around 23w17a / 1.20). Copying a 1.20+
`default.json` is the wrong game.

| # | type | file | height | ascent | Coverage |
|---|---|---|---|---|---|
| 0 | `bitmap` | `minecraft:font/nonlatin_european.png` | default **8** | **7** | 67×16 = 1072 extra European / phonetic / symbols |
| 1 | `bitmap` | `minecraft:font/accented.png` | **12** | **10** | 75×16 = 1200 accented Latin, taller cells |
| 2 | `bitmap` | `minecraft:font/ascii.png` | default **8** | **7** | 16×16 = 256 cells. Rows 2–7 are `U+0020`–`U+007E`. Other rows are CP437-like extras (`£`, box drawing, `±`, `²`…). Empty cells are `U+0000`. |
| 3 | `legacy_unicode` | `minecraft:font/unicode_page_%s.png` + `glyph_sizes.bin` | 16-px cells | — | Everything else in the BMP. 1.18.1 ships 222 `unicode_page_XX.png` sheets. |

`file` on a bitmap provider is a resource location **under
`assets/<namespace>/textures/`**. So `minecraft:font/ascii.png` is
`assets/minecraft/textures/font/ascii.png`, not the JSON folder.

`uniform.json` is *only* the `legacy_unicode` provider. `alt.json`
is `ascii_sga.png` (Standard Galactic Alphabet). Neither is what
Wurst draws.

### Advances, height, ascent

Bitmap provider, 1.18.1 Java:

- Omitted `height` means **8**. That is the rendered glyph height
  in GUI-scale-1 pixels, not the PNG pixel size (the sheet is
  scaled so each cell is `height` tall).
- `ascent` is how far the glyph extends above the baseline.
  ascii / nonlatin: 7. accented: 10 (because those cells are 12
  tall).
- Glyph **advance is not a constant**. The renderer scans the
  cell for the last column that has a non-transparent pixel and
  uses `last + 1`. An empty cell (space, `U+0000`) therefore has
  a small baked width — space is **not** 6.
- `Font.lineHeight` is **9**. That is why HackList does
  `posY += 9`. It is `height` of the default line + 1 px of
  leading, not a guess.

Typical Latin widths (GUI-scale-1, observed from the ascii sheet,
not a contract to hard-code): `i`/`l`/`.` ≈ 2–3, most lowercase
5–6, `m`/`w` 6–7, digits 6, space 4. Saying "advance 6" was an
average, and it is **wrong as a gate**.

`legacy_unicode` widths come from `glyph_sizes.bin`: 65536 bytes,
one byte per BMP codepoint. High nibble = start column, low nibble
= end column inside a 16-wide cell.

### Shadow, fallback, colour

- `Font.drawShadow` / `draw(..., dropShadow=true)` draws the string
  a second time at **(+1, +1)** with RGB multiplied by ¼
  (`(color & 0xFCFCFC) >> 2`) and the original alpha kept, then
  draws the real glyphs on top. Wurst's HackList shadow is this,
  not a CSS drop-shadow.
- Bold is a second blit one pixel to the right, plus one extra
  pixel of advance. Wurst chrome is not bold.
- Italic is a shear. Wurst chrome is not italic.
- A codepoint no provider owns becomes the **missing-glyph tofu**
  (the white rectangle), not a hole and not a Monocraft substitute.
- Formatting codes (`§`) are Minecraft's, not Roblox
  `RichText`. Colour segments in the port have to be explicit
  runs, not `§`.

### What changed after 1.18.1 (so we do not "upgrade" by accident)

- 1.20 / 23w17a: `legacy_unicode` + `unicode_page_XX.png` replaced
  by GNU Unifont `.hex` (`unihex` provider, `unifont.zip`).
- `space` provider (explicit advances, including `U+0020 = 4`) is
  **not** in 1.18.1.
- `include` / `reference` providers are later.

A generator that reads a 1.21 jar is generating the wrong font.

## Who owns which file

| File | Owner | In this repo? |
|---|---|---|
| `client.jar`, `ascii.png`, `accented.png`, `nonlatin_european.png`, `ascii_sga.png`, `asciillager.png`, `unicode_page_*.png`, `glyph_sizes.bin`, `default.json` / `alt.json` / `uniform.json` / `illageralt.json` | Mojang / Microsoft | **No. Never.** |
| Wurst Java, `wurst_128.png`, taco frames, `en_us.json` | Wurst-Imperium, GPL-3.0, pinned `4a22e53` | Yes, under `assets/wurst/` + NOTICE |
| `Monocraft.otf`, `Monocraft-OFL.txt` | Idrees Hassan, SIL OFL 1.1 | Yes, `src/gui/Current/Assets/Typography/` |
| `assets/font/monocraft-16.png` + `.json` | Generated here from Monocraft (OFL) | Yes. **Not** Minecraft. |
| This document, `minecraft-1.18.1.manifest.json` | This port (facts + hashes) | Yes |

CandyFruits / ValveBD are leftover product faces. They are not
MC.font and they are not the fallback.

## Redistribution — known conditions, not a warranty

We are not lawyers. The notes below are the conservative reading
this repository will follow. They are **not** a legal opinion.

- Minecraft game assets are copyright Mojang / Microsoft. The
  Minecraft EULA does not grant a right to redistribute the client,
  its textures, or its font sheets.
- Pinning official URLs and SHA1s, and describing the JSON
  *structure* (provider types, file names, ascent/height, the
  ascii grid layout) is documentation of public launcher metadata.
- Copying the PNG bytes, `glyph_sizes.bin`, or the full
  `default.json` into git **is** redistributing a Mojang asset.
- A PNG we generate from those bytes is a derivative work of the
  Mojang sheets. Same rule: generate locally, do not version it.
- GNU Unifont (used by later Minecraft versions, and historically
  the source of the unicode pages) has its own GPL/OFL terms. That
  does not make Mojang's packaged `unicode_page_XX.png` free to
  ship.
- Monocraft is OFL 1.1: use, study, modify, redistribute, as long
  as the font is not sold by itself and the OFL text travels with
  it. We already ship `Monocraft-OFL.txt`.
- Wurst is GPL-3.0. It ships **no** font. There is nothing to
  vendor from Wurst for this.

What we will **not** claim:

- that we have a licence from Mojang to ship Mojangles
- that Monocraft is pixel-identical to 1.18.1 `ascii.png`
- that "advance 6" is the official width
- that a third-party asset dump (mcasset.cloud,
  InventivetalentDev/minecraft-assets) is an official distribution
  channel — those trees were used only to *read* `default.json`
  when the Mojang CDN was unreachable from this environment. The
  pin remains the official `client.jar` SHA1.

## Conservative technical strategy

In preference order. C will gate this; A implements the renderer.

1. **Do not vendor Mojang pixels.** The gate fails any
   `ascii.png` / `unicode_page_` / `glyph_sizes.bin` / `client.jar`
   added under `assets/` or `src/`.
2. **Downloader, official only, explicit update.** A tool
   (`tools/fetch_minecraft_font.py`, C2) reads the pinned
   manifest, downloads `client.jar` from piston-data, checks SHA1,
   extracts the font paths into `cache/minecraft-1.18.1/`
   (gitignored). Normal `validate.sh` does **not** hit the
   network.
3. **Generate locally, do not version.** A tool builds
   `assets/font/minecraft-atlas.png` + advances JSON from the
   extract. Both are gitignored. Runtime may load them when
   present.
4. **Fallback Monocraft.** If the extract / atlas is missing
   (CI, a fresh clone, no `--update`), `state.bitmapText` keeps
   using `monocraft-16.png`. Metrics stay 11×17 / advance 11.
   Surfaces must tolerate both atlases.
5. **Labels.** `monocraft-16.json` already says "Monocraft (OFL)".
   A Minecraft atlas JSON must say `Minecraft 1.18.1 default` and
   must not reuse the Monocraft filename.

Until step 3 exists, the honest statement is: **the port renders
Monocraft behind the bitmap contract**. That is an OFL stand-in,
not MC.font.

## What the old spec got wrong

| Old claim | 1.18.1 fact |
|---|---|
| Glyphs come from `ascii.png` only | Four-provider stack; ascii is third |
| Typical advance 6 | Variable; scanned per glyph |
| "Minecraft default bitmap" as if one sheet | default + uniform + alt + illageralt |
| Closest vendored = good enough to call exact | Monocraft is OFL imitation, different metrics (11 vs ~5–6, cell 17 vs 8) |

`Font.lineHeight = 9` and "Wurst ships no font" were already
correct. Those stay.
