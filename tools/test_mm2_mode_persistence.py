#!/usr/bin/env python3
"""Boot the real bundle with conflicting legacy/per-mode saved options."""
import os
import subprocess
import tempfile
from pathlib import Path
import gen_full_boot_harness

ROOT = Path(__file__).resolve().parents[1]
gen_full_boot_harness.main()
source = (ROOT / 'build/full_boot.luau').read_text()
old = '''    states = { ["ClickGUI.Showdock"] = false },
    values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000 },'''
new = '''    states = { ["ClickGUI.Showdock"] = false,
        ["MM2.Shoot.WallCheck"] = true, ["MM2.Shoot.Experimental.WallCheck"] = false,
        ["MM2.Shoot.Bullet.WallCheck"] = true,
        ["MM2.AutoShoot.WallCheck"] = true, ["MM2.AutoShoot.CFrame.WallCheck"] = false,
        ["MM2.AutoShoot.CFrame.Proximity"] = true },
    values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000,
        ["MM2.Shoot.Aimmethod"] = "Experimental", ["MM2.Shoot.Experimental.Target"] = "Custom",
        ["MM2.Shoot.Experimental.TargetPlayer"] = "SavedPlayer",
        ["MM2.AutoShoot.Mode"] = "CFrame", ["MM2.AutoShoot.CFrame.Aura"] = 88 },'''
assert source.count(old) == 1
source = source.replace(old, new, 1)
marker = '-- harness epilogue: inspect what the boot built'
assert source.count(marker) == 1
checks = r'''
do
    local ex = GENV.__expose
    local cfg, mm = ex.configData, ex.state.mm2Core.mm2Settings
    assert(mm.experimentalAim == true and mm.shootWallCheck == false
        and mm.shootMode == 'Custom' and mm.shootTarget == 'SavedPlayer',
        'Gun Experimental settings were overwritten during startup')
    assert(cfg.states['MM2.Shoot.Experimental.WallCheck'] == false,
        'Gun per-mode persisted setting changed during startup')
    assert(cfg.states['MM2.AutoShoot.CFrame.WallCheck'] == false
        and cfg.states['MM2.AutoShoot.WallCheck'] == false
        and cfg.states['MM2.AutoShoot.Proximity'] == true
        and cfg.values['MM2.AutoShoot.Aura'] == 88,
        'Auto Shoot CFrame settings were overwritten during startup')
    local aim = ex.state.valueControls['MM2.Shoot.Aimmethod']
    aim.apply('Bullet')
    assert(mm.shootWallCheck == true and mm.shootMode == 'Murder', 'saved Bullet state was lost')
    aim.apply('Experimental')
    assert(mm.shootWallCheck == false and mm.shootTarget == 'SavedPlayer', 'Experimental restore failed')
    local mode = ex.state.valueControls['MM2.AutoShoot.Mode']
    mode.apply('Bullet')
    assert(cfg.states['MM2.AutoShoot.WallCheck'] == true, 'Bullet default did not restore')
    mode.apply('CFrame')
    assert(cfg.states['MM2.AutoShoot.WallCheck'] == false and cfg.values['MM2.AutoShoot.Aura'] == 88,
        'saved CFrame options did not restore')
    -- Let the ordinary harness run with the defaults it expects.
    ex.state.toggleControls['MM2.Shoot.WallCheck'].setChecked(true)
    ex.state.valueControls['MM2.Shoot.Target'].apply('Murder')
    aim.apply('Bullet')
    ex.state.toggleControls['MM2.AutoShoot.WallCheck'].setChecked(true)
    ex.state.toggleControls['MM2.AutoShoot.Proximity'].setChecked(false)
    ex.state.valueControls['MM2.AutoShoot.Aura'].apply(25)
    mode.apply('Bullet')
    print('PASS saved per-mode MM2 options survive boot and switches')
end
'''
source = source.replace(marker, checks + '\n' + marker, 1)
with tempfile.TemporaryDirectory(prefix='mm2-mode-persist-') as directory:
    script = Path(directory) / 'boot.luau'
    script.write_text(source)
    result = subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stdout[-5000:] + result.stderr)
    assert 'PASS saved per-mode MM2 options survive boot and switches' in result.stdout
    print('PASS saved per-mode MM2 options survive boot and switches')
