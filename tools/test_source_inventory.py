#!/usr/bin/env python3
"""Keep the runtime source/bundle inventory aligned with its one manifest.

Wurst and the generated bundle are loader entry points; the manifest itself is
also bundled. Assets are fetched separately from the bundle at runtime.
"""
import re
from pathlib import Path
import build_bundle

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src'
MANIFEST = 'src/libraries/Manifest.lua'
LOADER = 'src/Wurst.lua'
BUNDLE = 'src/libraries/bundle.lua'
manifest = (ROOT / MANIFEST).read_text(encoding='utf-8')
wurst = (ROOT / LOADER).read_text(encoding='utf-8')

# The manifest is the only catalog for widgets, core, libraries and both
# universal/game modules. An extra shipped Lua file must be registered there,
# or the inventory and build need to explicitly document its special loading.
references = set(re.findall(r'"(src/[^"\n]+\.lua)"', manifest))
assert references, 'the runtime manifest contains no sources'
expected_bundle = references | {MANIFEST}
disk_sources = {
    p.relative_to(ROOT).as_posix()
    for p in SRC.rglob('*')
    if p.is_file() and p.suffix.lower() in ('.lua', '.luau')
}
expected_sources = expected_bundle | {LOADER, BUNDLE}
missing = sorted(expected_sources - disk_sources)
orphans = sorted(disk_sources - expected_sources)
assert not missing and not orphans, f'runtime sources missing={missing}; unregistered={orphans}'

stamp = re.search(r'local SOURCE_STAMP: string = "([^"]+)"', wurst).group(1)
bundle_stamp, bundled = build_bundle.parse_bundle((ROOT / BUNDLE).read_text(encoding='utf-8'))
assert bundle_stamp == stamp, 'loader and bundle stamps differ'
assert set(bundled) == expected_bundle, (
    f'bundle mismatch: missing={sorted(expected_bundle - set(bundled))}, '
    f'unregistered={sorted(set(bundled) - expected_bundle)}'
)

# These files are not in the Lua bundle: Wurst fetches each by URL. Check the
# actual disk contents as well as path membership, so a missing font/image
# cannot slip through a successful module compilation.
asset_paths = set(re.findall(r'"(src/guis/Wurst/Assets/[^"\n]+)"', wurst))
assert asset_paths, 'no runtime assets found in the loader'
other_files = {
    p.relative_to(ROOT).as_posix()
    for p in SRC.rglob('*')
    if p.is_file() and p.relative_to(ROOT).as_posix() not in disk_sources
}
assert other_files == asset_paths, (
    f'assets missing={sorted(asset_paths - other_files)}; '
    f'unreferenced={sorted(other_files - asset_paths)}'
)
for asset in sorted(asset_paths):
    contents = (ROOT / asset).read_bytes()
    assert len(contents) >= 64, f'empty or truncated asset: {asset}'
    if asset.endswith('.png'):
        assert contents.startswith(b'\x89PNG\r\n\x1a\n'), f'invalid PNG: {asset}'
    elif asset.endswith(('.jpg', '.jpeg')):
        assert contents.startswith(b'\xff\xd8\xff'), f'invalid JPEG: {asset}'
    elif asset.endswith(('.otf', '.ttf')):
        assert contents[:4] in (b'OTTO', b'\x00\x01\x00\x00'), f'invalid font: {asset}'
    else:
        raise AssertionError(f'add a signature check for new asset type: {asset}')

print(f'PASS source inventory: {len(expected_bundle)} bundled sources, '
      f'{len(asset_paths)} separately fetched assets, no unregistered files')
