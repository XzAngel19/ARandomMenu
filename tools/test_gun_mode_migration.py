#!/usr/bin/env python3
"""Boot real MM2 controls with old and new Gun Aimbot mode/profile names."""
from pathlib import Path
import os
import subprocess
import tempfile
import gen_full_boot_harness

ROOT = Path(__file__).resolve().parents[1]
gen_full_boot_harness.main()
source = (ROOT / 'build/full_boot.luau').read_text()
marker = '-- harness epilogue: inspect what the boot built'
assert source.count(marker) == 1
source = source.split(marker, 1)[0]
old = '''    states = { ["ClickGUI.Showdock"] = false },
    values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000 },'''
assert source.count(old) == 1
cases = [
    ('Aimmethod', 'Bullet', 'Normal(Bullet)', False, False, True),
    ('Aimmethod', 'CFrame', 'Silent(Cframe)', True, False, False),
    ('Mode', 'CFrame', 'Silent(Cframe)', True, False, False),
    ('Aimmethod', 'Normal(Bullet)', 'Normal(Bullet)', False, False, True),
    ('Aimmethod', 'Silent(Cframe)', 'Silent(Cframe)', True, False, False),
    ('Aimmethod', 'Experimental', 'Experimental', False, True, False),
]
with tempfile.TemporaryDirectory(prefix='gun-mode-migration-') as tmp:
    script = Path(tmp) / 'boot.luau'
    for field, saved, display, silent, experimental, wall in cases:
        initial = f'''    states = {{ ["ClickGUI.Showdock"] = false,
        ["MM2.Shoot.Bullet.WallCheck"] = true, ["MM2.Shoot.CFrame.WallCheck"] = false,
        ["MM2.Shoot.Experimental.WallCheck"] = false }},
    values = {{ ["ClickGUI.Arrows"] = {{255, 255, 255}}, ["Universal.Speed.Speed"] = 5000,
        ["MM2.Shoot.{field}"] = "{saved}", ["MM2.Shoot.CFrame.Target"] = "Custom",
        ["MM2.Shoot.CFrame.TargetPlayer"] = "OldPlayer" }},'''
        test = f'''
local ex=GENV.__expose
local cfg, mm=ex.configData, ex.state.mm2Core.mm2Settings
assert(cfg.values["MM2.Shoot.Aimmethod"] == "{display}", 'wrong migrated display')
assert((mm.silentAim == true) == {str(silent).lower()}, 'wrong Silent state')
assert((mm.experimentalAim == true) == {str(experimental).lower()}, 'wrong Experimental state')
assert(mm.shootWallCheck == {str(wall).lower()}, 'wrong saved mode WallCheck')
local aim=ex.state.valueControls["MM2.Shoot.Aimmethod"]
aim.apply("Silent(Cframe)")
assert(mm.silentAim and not mm.shootWallCheck and mm.shootMode=="Custom" and mm.shootTarget=="OldPlayer",
    'legacy CFrame per-mode settings must survive the label rename')
aim.apply("Normal(Bullet)")
assert(not mm.silentAim and not mm.experimentalAim and mm.shootWallCheck,
    'Bullet settings must remain independent')
aim.apply("Experimental")
assert(mm.experimentalAim and not mm.shootWallCheck, 'Experimental remains available')
print('PASS migrated mode: {field} {saved}')
'''
        script.write_text(source.replace(old, initial, 1) + test)
        result = subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(f'{field} {saved}:\n{result.stdout[-4000:]}\n{result.stderr}')
        assert f'PASS migrated mode: {field} {saved}' in result.stdout
print('PASS Gun Aimbot: legacy/current labels, mode settings and Experimental survive real bundle boot')
