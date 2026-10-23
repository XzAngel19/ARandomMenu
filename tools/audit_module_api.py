#!/usr/bin/env python3
"""Static cross-module audit: every core.*/prediction.* call must exist.

The MM2 modules talk through two tables: state.mm2Core (base.lua) and
state.mm2Prediction (Prediction.lua). A rename in either side is silent at
load time and only fails when a feature is used, so this checks the call
sites against the exported keys.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def block_keys(text: str, start_marker: str) -> set[str]:
    start = text.index(start_marker)
    depth, i = 0, start
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                block = text[start:i]
                break
        i += 1
    else:
        raise SystemExit(f'unbalanced table after {start_marker}')
    keys = set(re.findall(r'^\s{4}([A-Za-z_][A-Za-z0-9_]*)\s*=', block, re.M))
    keys |= set(re.findall(r'^\s{4}([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function', block, re.M))
    return keys


def calls(text: str, owner: str) -> set[str]:
    """Names read from `owner.<name>`, ignoring `owner.<name> = ...` writes."""
    found: set[str] = set()
    pattern = re.compile(r'\b' + owner + r'\.([A-Za-z_][A-Za-z0-9_]*)')
    for match in pattern.finditer(text):
        tail = text[match.end():match.end() + 4]
        if re.match(r'\s*=(?!=)', tail):
            continue
        found.add(match.group(1))
    return found


base = (ROOT / 'src/games/MM2/base.lua').read_text(encoding='utf-8')
pred = (ROOT / 'src/games/MM2/Prediction.lua').read_text(encoding='utf-8')

core_keys = block_keys(base, 'state.mm2Core = {')
pred_keys = set(
    re.findall(r'^\s{8}([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[A-Za-z_]', pred, re.M)
)

problems = []
uses: dict[tuple[str, str], set[str]] = {}
for path in sorted((ROOT / 'src/games/MM2').rglob('*.lua')):
    text = path.read_text(encoding='utf-8')
    rel = path.relative_to(ROOT).as_posix()
    for name in calls(text, 'core'):
        uses.setdefault(('core', name), set()).add(rel)
    for name in calls(text, 'prediction'):
        uses.setdefault(('prediction', name), set()).add(rel)

for (owner, name), files in sorted(uses.items()):
    if owner == 'core' and name not in core_keys:
        problems.append(f'core.{name} is called but not exported: {sorted(files)}')
    if owner == 'prediction' and name not in pred_keys:
        problems.append(f'prediction.{name} is called but not exported: {sorted(files)}')

print(f'core exports: {len(core_keys)} | prediction exports: {len(pred_keys)}')
print(f'call sites checked: {sum(len(v) for v in uses.values())}')
if problems:
    print('\n'.join(problems))
    raise SystemExit(f'{len(problems)} unresolved cross-module call(s)')
print('PASS every core.* and prediction.* call resolves to an export')
