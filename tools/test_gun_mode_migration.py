#!/usr/bin/env python3
"""Real boot: desktop two-mode migration and shared key; mobile's three modes remain."""
from pathlib import Path
import os
import subprocess
import tempfile
import gen_full_boot_harness

ROOT = Path(__file__).resolve().parents[1]
gen_full_boot_harness.main()
source = (ROOT / 'build/full_boot.luau').read_text().split(
    '-- harness epilogue: inspect what the boot built', 1)[0]
old = '''    states = { ["ClickGUI.Showdock"] = false },
    values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000 },'''
assert source.count(old) == 1
cases = [
    ('Aimmethod', 'Bullet', 'Bullet', 'Normal(Bullet)', False, False),
    ('Aimmethod', 'CFrame', 'Silent(CFrame)', 'Silent(Cframe)', True, False),
    ('Mode', 'CFrame', 'Silent(CFrame)', 'Silent(Cframe)', True, False),
    ('Aimmethod', 'Normal(Bullet)', 'Bullet', 'Normal(Bullet)', False, False),
    ('Aimmethod', 'Silent(Cframe)', 'Silent(CFrame)', 'Silent(Cframe)', True, False),
    ('Aimmethod', 'Silent(CFrame)', 'Silent(CFrame)', 'Silent(Cframe)', True, False),
    ('Aimmethod', 'Experimental', 'Bullet', 'Experimental', False, True),
]
with tempfile.TemporaryDirectory(prefix='gun-mode-migration-') as tmp:
    script = Path(tmp) / 'boot.luau'
    for mobile in (False, True):
        for field, saved, pc_display, mobile_display, silent, experimental in cases:
            initial = f'''    states = {{ ["ClickGUI.Showdock"] = false,
        ["MM2.Shoot.Bullet.WallCheck"] = true, ["MM2.Shoot.CFrame.WallCheck"] = false,
        ["MM2.Shoot.Experimental.WallCheck"] = false }},
    values = {{ ["ClickGUI.Arrows"] = {{255, 255, 255}}, ["Universal.Speed.Speed"] = 5000,
        ["MM2.Shoot.{field}"] = "{saved}", ["MM2.Shoot.CFrame.Target"] = "Custom",
        ["MM2.Shoot.CFrame.TargetPlayer"] = "OldPlayer", ["Shortcut.MM2Shoot"] = "G" }},'''
            display = mobile_display if mobile else pc_display
            exp = mobile and experimental
            wall = not silent and not exp
            silent_label = 'Silent(Cframe)' if mobile else 'Silent(CFrame)'
            bullet_label = 'Normal(Bullet)' if mobile else 'Bullet'
            test = f'''
local ex=GENV.__expose
local cfg, state, mm=ex.configData, ex.state, ex.state.mm2Core.mm2Settings
assert(cfg.values["MM2.Shoot.Aimmethod"] == "{display}", 'wrong migrated display: '..tostring(cfg.values["MM2.Shoot.Aimmethod"]))
assert((mm.silentAim == true) == {str(silent).lower()}, 'wrong Silent state')
assert((mm.experimentalAim == true) == {str(exp).lower()}, 'wrong Experimental state')
assert(mm.shootWallCheck == {str(wall).lower()}, 'wrong saved mode WallCheck')
local aim=state.valueControls["MM2.Shoot.Aimmethod"]
aim.apply("{silent_label}")
assert(mm.silentAim and not mm.shootWallCheck and mm.shootMode=="Custom" and mm.shootTarget=="OldPlayer",
    'legacy CFrame per-mode settings must survive the label rename')
aim.apply("{bullet_label}")
assert(not mm.silentAim and not mm.experimentalAim and mm.shootWallCheck,
    'Bullet settings must remain independent')
local shoot
for _,f in ipairs(ex.allFeatures) do if f.name=='Gun Aimbot' then shoot=f end end
assert(shoot and state.shortcutBindings['MM2.Shoot'].key==Enum.KeyCode.G,'old shortcut is preserved; got '..tostring(state.shortcutBindings['MM2.Shoot'].key and state.shortcutBindings['MM2.Shoot'].key.Name)..' cfg '..tostring(cfg.values['Shortcut.MM2Shoot']))
'''
            if mobile:
                test += '''
aim.apply('Experimental')
assert(mm.experimentalAim and not mm.shootWallCheck, 'mobile keeps Experimental')
assert(not shoot.options:FindFirstChild('Option_Keybind'),'mobile retains its previous controls')
'''
            else:
                test += '''
aim.apply('Experimental')
assert(not mm.experimentalAim,'Experimental is not available on PC')
local row=assert(shoot.options:FindFirstChild('Option_Keybind'))
local button=assert(row:FindFirstChildOfClass('TextButton'))
local binding=assert(state.shortcutBindings['MM2.Shoot'])
assert(button.Text=='G','the old shortcut is displayed in the one keybind box')
button.MouseButton1Click:Fire();assert(type(state.keyCaptureCallback)=='function')
UserInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.H},false)
assert(state.keyCaptureCallback==nil,'key capture completes through real input dispatcher')
assert(binding.key==Enum.KeyCode.H and button.Text=='H' and cfg.values['Shortcut.MM2Shoot']=='H',
    'the option changes the existing shared shortcut')
binding.assign(Enum.KeyCode.J)
assert(button.Text=='J','changes elsewhere refresh the same box')
binding.assign(Enum.KeyCode.J)
assert(binding.key==Enum.KeyCode.Unknown and button.Text=='','pressing the same key clears it')
-- Drive the real input dispatch and feature callback, not just the saved key.
local bag=LocalPlayer:FindFirstChildOfClass('Backpack')
local gun=newInst('Tool');gun.Name='Gun';gun.Parent=bag
local humanoid=LocalPlayer.Character:FindFirstChildOfClass('Humanoid')
local equips=0
humanoid.EquipTool=function(_,tool) equips+=1;tool.Parent=LocalPlayer.Character end
assert(not shoot.enabled,'Gun Aimbot starts OFF')
binding.assign(Enum.KeyCode.H)
UserInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.H},false)
assert(equips==1 and gun.Parent==LocalPlayer.Character,'Bullet shortcut equips the Gun while OFF')
gun.Parent=bag;aim.apply('Silent(CFrame)')
UserInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.H},true)
assert(equips==2 and gun.Parent==LocalPlayer.Character,'the same shortcut works in Silent, even if input is game-processed')
'''
            test += "print('PASS migrated mode')\n"
            boot = source.replace(old, initial, 1).replace('    ui = {},\n}]]', '    ui = {unboundKeyDefaultsVersion = 1},\n}]]', 1)
            if mobile:
                boot = boot.replace('UserInputService.props.TouchEnabled = false',
                                    'UserInputService.props.TouchEnabled = true', 1)
                boot = boot.replace('UserInputService.props.KeyboardEnabled = true',
                                    'UserInputService.props.KeyboardEnabled = false', 1)
            script.write_text(boot + test)
            result = subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], text=True, capture_output=True)
            if result.returncode:
                raise SystemExit(f'{mobile=} {field} {saved}:\n{result.stdout[-2000:]}\n{result.stderr}')
            assert 'PASS migrated mode' in result.stdout
print('PASS Gun Aimbot: PC two-mode migration and one shared key; mobile keeps its three modes')
