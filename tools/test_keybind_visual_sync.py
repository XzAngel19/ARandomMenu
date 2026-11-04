#!/usr/bin/env python3
"""Boot real cards and exercise keyboard, menu and navigator state together.

The harness models UI properties and input signals, not physical input on a
Roblox client. It must catch stale navigator tiles as well as stale card skins.
"""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
probe = r'''
local speed=ex.state.framework:GetModule('Speed Hack')
local feature=speed.Feature
assert(speed.Options.Mode.Value==EXPECTED_MODE, 'Velocity is the default, but a saved mode must win')
assert(not speed.Enabled and not feature.enabled)
local binding=ex.state.shortcutBindings[feature.configKey]
assert(binding and type(binding.onPress)=='function')
binding.key=Enum.KeyCode.K
local nav=ex.state.navigator;assert(nav)
nav.Open()
ex.state.animationsEnabled=false
ex.state.hudList.SetVisible(true)
local function deep(parent,name)
    if parent.Name==name then return parent end
    for _,child in ipairs(parent:GetChildren()) do
        local found=deep(child,name);if found then return found end
    end
end
local tile=deep(nav.root,'Nav_SpeedHack');assert(tile,'Speed Hack navigator tile missing')
local floating=ex.state.floatingUi;assert(floating);floating.toggleFavorite(feature)
local function favoriteStatus() return floating.favoriteRows[1]:FindFirstChild('Status') end
local function same(a,b) return a.R==b.R and a.G==b.G and a.B==b.B end
local key={KeyCode=Enum.KeyCode.K,UserInputType=Enum.UserInputType.Keyboard}
UserInputService.InputBegan:Fire(key,false)
assert(feature.enabled and speed.Enabled and ex.configData.states[feature.configKey]==true)
assert(same(feature.row.BackgroundColor3,ex.Theme.enabled),'key ON must repaint the menu card')
assert(same(tile.BackgroundColor3,ex.Theme.enabled),'key ON must repaint the open navigator tile')
assert(favoriteStatus().BackgroundTransparency==0,'key ON must repaint the favorite')
ex.state.hudList.refresh();assert(ex.state.hudList.frame:FindFirstChild('Speed Hack'), 'hacklist must show Speed')
UserInputService.InputEnded:Fire(key,false)
UserInputService.InputBegan:Fire(key,false)
assert(not feature.enabled and not speed.Enabled and ex.configData.states[feature.configKey]==false)
assert(not same(feature.row.BackgroundColor3,ex.Theme.enabled),'key OFF must repaint the menu card')
assert(not same(tile.BackgroundColor3,ex.Theme.enabled),'key OFF must repaint the open navigator tile')
assert(favoriteStatus().BackgroundTransparency==0.58,'key OFF must repaint the favorite')
ex.state.hudList.refresh();assert(not ex.state.hudList.frame:FindFirstChild('Speed Hack'), 'hacklist must hide Speed')
feature.activationTarget.MouseButton1Click:Fire()
assert(feature.enabled and same(feature.row.BackgroundColor3,ex.Theme.enabled)
    and same(tile.BackgroundColor3,ex.Theme.enabled),'mouse card activation matches keybind')
feature.activationTarget.MouseButton1Click:Fire();assert(not feature.enabled and not speed.Enabled)
tile.MouseButton1Click:Fire();assert(feature.enabled and same(feature.row.BackgroundColor3,ex.Theme.enabled))
tile.MouseButton1Click:Fire();assert(not feature.enabled and not speed.Enabled)
local bright=assert(ex.state.framework:GetModule('Fullbright'));local bf=bright.Feature
local brightTile=assert(deep(nav.root,'Nav_Fullbright'))
ex.state.shortcutBindings[bf.configKey].key=Enum.KeyCode.J
local key2={KeyCode=Enum.KeyCode.J,UserInputType=Enum.UserInputType.Keyboard}
UserInputService.InputBegan:Fire(key2,false)
assert(bright.Enabled and bf.enabled and same(bf.row.BackgroundColor3,ex.Theme.enabled)
    and same(brightTile.BackgroundColor3,ex.Theme.enabled),'second module key ON')
UserInputService.InputBegan:Fire(key2,false)
assert(not bright.Enabled and not bf.enabled and not same(bf.row.BackgroundColor3,ex.Theme.enabled)
    and not same(brightTile.BackgroundColor3,ex.Theme.enabled),'second module key OFF')
print('PASS keybind UI: keyboard, card, favorite, open navigator and stored state stay synchronized')
'''
saved_anchor = '["Universal.Speed.Speed"] = 5000'
assert source.count(saved_anchor) == 1
with tempfile.TemporaryDirectory(prefix='keybind-visual-') as tmp:
    for mode in ('Velocity', 'WalkSpeed'):
        case = source
        if mode == 'WalkSpeed':
            case = case.replace(saved_anchor, saved_anchor + ', ["Universal.Speed.Mode"] = "WalkSpeed"', 1)
        path = Path(tmp) / f'keybind_{mode}.luau'
        path.write_text(case + f'\nEXPECTED_MODE="{mode}"\n' + probe, encoding='utf-8')
        proc = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], capture_output=True, text=True)
        if proc.returncode:
            raise SystemExit(mode + ':\n' + proc.stdout[-1200:] + '\n' + proc.stderr)
        assert 'PASS keybind UI:' in proc.stdout
        print(f'PASS keybind UI: two modules, keyboard/click/hacklist/favorites/navigator; Speed mode {mode}')
