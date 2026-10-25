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

# 3) The fallback manifest is exactly the manifest: no second menu to test.
fallback_at = wurst.index('local fallbackManifest')
fallback_block = wurst[fallback_at:wurst.index('local bundleAt:', fallback_at)]
fallback = entries(fallback_block)
assert fallback == manifest, (
    'fallbackManifest drifted from Manifest.lua:\n'
    f' only in manifest: {sorted(set(manifest) - set(fallback))}\n'
    f' only in fallback: {sorted(set(fallback) - set(manifest))}'
)

# 4) The MM2 load list covers every MM2 file, and points at real files.
mm2_start = wurst.index('MM2 = {')
mm2_block = wurst[mm2_start:wurst.index('VD = {', mm2_start)]
mm2_paths = re.findall(r'"(src/games/MM2/[^"]+)"', mm2_block)
mm2_disk = {
    p.relative_to(ROOT).as_posix() for p in (ROOT / 'src/games/MM2').rglob('*.lua')
}
assert set(mm2_paths) == mm2_disk, (
    'MM2 load list does not match the folder:\n'
    f' missing from the list: {sorted(mm2_disk - set(mm2_paths))}\n'
    f' listed but absent: {sorted(set(mm2_paths) - mm2_disk)}'
)
assert len(mm2_paths) == len(set(mm2_paths)), 'duplicate MM2 module path'

# 5) The gameplay modules the loader maps are not legacy monoliths.
for name in ('MM2', 'TRS', 'VD', 'BedFight'):
    assert (ROOT / 'src/games' / name / 'base.lua').is_file(), name
    assert not (ROOT / 'src/games' / f'{name}.luau').exists(), (
        f'src/games/{name}.luau is a dead monolith; the loader uses {name}/base.lua'
    )

print(
    f'PASS manifests: {len(manifest)} modules registered, no orphans, '
    f'fallback identical, {len(mm2_paths)} MM2 files listed'
)
