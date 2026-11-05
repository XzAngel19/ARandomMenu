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
source = source.split(marker, 1)[0]
checks = r'''
do
    local ex = GENV.__expose
    local cfg, mm = ex.configData, ex.state.mm2Core.mm2Settings
    local mobile = __MOBILE__
    if mobile then
        assert(mm.experimentalAim == true and mm.shootWallCheck == false
            and mm.shootMode == 'Custom' and mm.shootTarget == 'SavedPlayer',
            'mobile Gun Experimental settings were overwritten during startup')
    else
        assert(mm.experimentalAim == false and mm.shootWallCheck == true
            and cfg.values['MM2.Shoot.Aimmethod'] == 'Bullet',
            'PC must migrate the removed Experimental selection to Bullet')
    end
    assert(cfg.states['MM2.Shoot.Experimental.WallCheck'] == false
        and cfg.values['MM2.Shoot.Experimental.TargetPlayer'] == 'SavedPlayer',
        'old Experimental per-mode data must not be destroyed')
    assert(cfg.states['MM2.AutoShoot.CFrame.WallCheck'] == false
        and cfg.states['MM2.AutoShoot.WallCheck'] == false
        and cfg.states['MM2.AutoShoot.Proximity'] == true
        and cfg.values['MM2.AutoShoot.Aura'] == 88,
        'Auto Shoot CFrame settings were overwritten during startup')
    local aim = ex.state.valueControls['MM2.Shoot.Aimmethod']
    aim.apply(mobile and 'Normal(Bullet)' or 'Bullet')
    assert(mm.shootWallCheck == true and mm.shootMode == 'Murder', 'saved Bullet state was lost')
    if mobile then
        aim.apply('Experimental')
        assert(mm.shootWallCheck == false and mm.shootTarget == 'SavedPlayer', 'mobile Experimental restore failed')
    else
        aim.apply('Silent(CFrame)')
        assert(mm.silentAim and not mm.experimentalAim,'PC Silent mode must remain available')
        aim.apply('Experimental')
        assert(not mm.experimentalAim,'PC must reject the removed mode')
    end
    local mode = ex.state.valueControls['MM2.AutoShoot.Mode']
    mode.apply('Bullet')
    assert(cfg.states['MM2.AutoShoot.WallCheck'] == true, 'Auto Shoot Bullet default did not restore')
    mode.apply('CFrame')
    assert(cfg.states['MM2.AutoShoot.WallCheck'] == false and cfg.values['MM2.AutoShoot.Aura'] == 88,
        'saved Auto Shoot CFrame options did not restore')
    print('PASS saved per-mode MM2 options')
end
'''
with tempfile.TemporaryDirectory(prefix='mm2-mode-persist-') as directory:
    script = Path(directory) / 'boot.luau'
    for mobile in (False, True):
        boot = source
        if mobile:
            boot = boot.replace('UserInputService.props.TouchEnabled = false',
                                'UserInputService.props.TouchEnabled = true', 1)
            boot = boot.replace('UserInputService.props.KeyboardEnabled = true',
                                'UserInputService.props.KeyboardEnabled = false', 1)
        script.write_text(boot + checks.replace('__MOBILE__', str(mobile).lower()))
        result = subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(f'{mobile=}:\n'+result.stdout[-5000:]+result.stderr)
        assert 'PASS saved per-mode MM2 options' in result.stdout
print('PASS saved MM2 options: PC two modes, mobile Experimental, Auto Shoot settings')
