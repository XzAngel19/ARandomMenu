#!/usr/bin/env python3
"""The manifest, the fallback and the files on disk must describe one menu.

A module that compiles and travels inside bundle.lua but is not registered is
dead weight (WallHop, LagSwitch, RemoteLogger used to be). The fallback
manifest in Wurst.lua used to list a different set than Manifest.lua, so a
failed fetch booted a menu nobody had tested. Both are checked here.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest_text = (ROOT / 'src/libraries/Manifest.lua').read_text()
wurst = (ROOT / 'src/Wurst.lua').read_text()

ENTRY = re.compile(
    r'path = "([^"]+)"\s*,\s*name = "([^"]+)"\s*,\s*category = "([^"]+)"',
)


def entries(text: str):
    return [tuple(m.groups()) for m in ENTRY.finditer(text)]


manifest = entries(manifest_text[manifest_text.index('modules = {'):])
assert manifest, 'the manifest lists no modules'

# 1) Every registered path exists and is unique.
paths = [path for path, _, _ in manifest]
assert len(paths) == len(set(paths)), 'duplicate module path in the manifest'
for path in paths:
    assert (ROOT / path).is_file(), f'manifest points at a missing file: {path}'

# 2) Every universal module on disk is registered. Orphans are dead code.
disk = {
    p.relative_to(ROOT).as_posix()
    for p in (ROOT / 'src/games/universal').rglob('*.lua')
}
orphans = sorted(disk - set(paths))
assert not orphans, f'unregistered universal modules: {orphans}'

# 3) v138.9: there is ONE catalog. The old fallbackManifest in Wurst.lua was a
# second copy that silently booted a different menu when the fetch failed.
assert 'fallbackManifest' not in wurst, (
    'Wurst.lua still carries a fallbackManifest: the catalog must live only in '
    'Manifest.lua (tools/card.py edits it)'
)
assert 'manifest = fallbackManifest' not in wurst

# 3b) Wurst.lua owns no category tables either: it reads them from the catalog.
assert 'local FEATURE_CATEGORIES: {[string]: string} = {}' in wurst, (
    'Wurst.lua must start with an empty FEATURE_CATEGORIES and fill it from '
    'Manifest.lua (categories/cards)'
)
assert '= "Utilities",\n    ["KillAura"]' not in wurst, 'the old card map is back'

# 4) The MM2 load list covers every MM2 file, and points at real files.
game_block = manifest_text[manifest_text.index('gameModules = {'):]
mm2_paths = re.findall(
    r'"(src/games/MM2/[^"]+)"', game_block[game_block.index('MM2 = {'):game_block.index('VD = {')]
)
mm2_disk = {
    p.relative_to(ROOT).as_posix() for p in (ROOT / 'src/games/MM2').rglob('*.lua')
}
assert set(mm2_paths) == mm2_disk, (
    'MM2 load list does not match the folder:\n'
    f' missing from the list: {sorted(mm2_disk - set(mm2_paths))}\n'
    f' listed but absent: {sorted(set(mm2_paths) - mm2_disk)}'
)
assert len(mm2_paths) == len(set(mm2_paths)), 'duplicate MM2 module path'

# 4b) Every card a module creates must be in the catalog's window map, otherwise
# it silently lands in Utilities and stops being findable.
order = re.findall(r'^\s{12}"([^"]+)",\s*$', manifest_text[
    manifest_text.index('categories = {'):manifest_text.index('cards = {')
], re.M)
aliases = dict(re.findall(r'\["([^"]+)"\] = "([^"]+)",', manifest_text[
    manifest_text.index('aliases = {'):manifest_text.index('default = "Utilities"')
]))
cards = dict(re.findall(r'\["([^"]+)"\] = "([^"]+)",', manifest_text[
    manifest_text.index('cards = {'):manifest_text.index('gamePlaces = {')
]))
for window in cards.values():
    assert window in order or window in aliases, f'card window {window} is unknown'
assert len(cards) >= 70, f'the card map lost entries: {len(cards)}'

missing_cards = []
for source in (ROOT / 'src/games').rglob('*.lua'):
    text = source.read_text()
    for match in re.finditer(r'createUniversalFeature\(\s*\n?\s*"([^"]+)"', text):
        name = match.group(1)
        window = text[match.start():match.start() + 3000]
        if name not in cards and 'categoryName' not in window:
            missing_cards.append(f'{name} ({source.relative_to(ROOT)})')
assert not missing_cards, 'cards without a catalog window: ' + ', '.join(sorted(set(missing_cards)))

# 5) The gameplay modules the loader maps are not legacy monoliths.
for name in ('MM2', 'TRS', 'VD', 'BedFight'):
    assert (ROOT / 'src/games' / name / 'base.lua').is_file(), name
    assert not (ROOT / 'src/games' / f'{name}.luau').exists(), (
        f'src/games/{name}.luau is a dead monolith; the loader uses {name}/base.lua'
    )

print(
    f'PASS manifests: {len(manifest)} modules registered, no orphans, '
    f'single catalog, {len(cards)} card windows, {len(mm2_paths)} MM2 files listed'
)
