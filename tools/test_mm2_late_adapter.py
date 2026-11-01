#!/usr/bin/env python3
"""Actual fingerprint registration and Knife Stab migration/cleanup in the booted bundle.

The harness schedules the real fingerprint worker explicitly after mocked MM2
instances appear; it cannot reproduce Roblox's network or GUI timing.
"""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text()
anchor = 'game = {\n    PlaceId = 142823291,\n    GameId = 20260716,'
assert source.count(anchor) == 1
source = source.replace(anchor, 'game = {\n    PlaceId = 123456789,\n    GameId = 20260716,', 1)
for name in ('HarnessRoundStart', 'HarnessRoundEnd', 'HarnessRoleRemote'):
    old = f'{name}.Parent = gameplayFolder'
    assert source.count(old) == 1
    source = source.replace(old, f'{name}.Parent = nil', 1)
# Retain the production worker verbatim, but start it only when this test has
# inserted replicated objects, as would happen after the initial boot in game.
old = 'if PENDING_FINGERPRINT then\n    task.spawn(function(): ()\n        local attempts: number = 0'
new = 'if PENDING_FINGERPRINT then\n    GENV.__runLateFingerprint = function(): ()\n        local attempts: number = 0'
assert source.count(old) == 1
source = source.replace(old, new, 1)
old = '    end)\nend\n\nstate.boot = {'
assert source.count(old) == 1
source = source.replace(old, '    end\nend\n\nstate.boot = {', 1)
old = '''    states = { ["ClickGUI.Showdock"] = false },
    values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000 },
    ui = {},'''
new = '''    states = { ["ClickGUI.Showdock"] = false, ["MM2.Knife"] = true,
        ["MM2.Knife.KnifeAura"] = true },
    values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000,
        ["MM2.Knife.AuraRange"] = 22, ["Shortcut.MM2Knife"] = "G" },
    ui = { unboundKeyDefaultsVersion = 1 },'''
assert source.count(old) == 1
source = source.replace(old, new, 1)
source += r'''
local function byName(name)
 for _,feature in ipairs(ex.allFeatures) do if feature.name==name then return feature end end
end
assert(ex.state.activeGameName==nil and type(GENV.__runLateFingerprint)=='function')
local feature=byName('KillAura');local card=ex.state.framework:GetModule('KillAura')
local chams=ex.state.framework:GetModule('Chams');local items=ex.state.framework:GetModule('ItemESP')
local binding=ex.state.shortcutBindings['Universal.KillAura']
assert(feature and card and binding and feature.configKey=='Universal.KillAura')
assert(chams.Options['Show Perk'] and not chams.Options['Show Perk'].Object.Parent.Visible,
 'perk row must initially be hidden')
assert(not items.Options['Gun ESP'] and not items.Options['Trap ESP'], 'MM2 item providers must not exist yet')
assert(not card.Enabled and not feature.enabled and binding.key==Enum.KeyCode.Unknown)
local originalDescription=feature.description
-- Four production fingerprints appear only after boot.
local gameplay=ReplicatedStorage:FindFirstChild('Remotes'):FindFirstChild('Gameplay')
HarnessRoundStart.Parent=gameplay;HarnessRoundEnd.Parent=gameplay;HarnessRoleRemote.Parent=gameplay
local client=newInst('Folder');client.Name='ClientServices';client.Parent=ReplicatedStorage
local weapon=newInst('Folder');weapon.Name='WeaponService';weapon.Parent=client
local fired=newInst('RemoteEvent');fired.Name='GunFired';fired.Parent=weapon
local gui=newInst('Folder');gui.Name='MainGUI';gui.Parent=ReplicatedStorage
local gameFrame=newInst('Folder');gameFrame.Name='Game';gameFrame.Parent=gui
local timer=newInst('TextLabel');timer.Name='Timer';timer.Parent=gameFrame
local map=newInst('Model');map.Name='Map';map.Parent=workspace
local coins=newInst('Folder');coins.Name='CoinContainer';coins.Parent=map
GENV.__runLateFingerprint()
assert(ex.state.activeGameName=='MM2' and ex.state.mm2Core and ex.state.activeGameModule,
 'real fingerprint worker must register and initialize MM2')
assert(chams.Options['Show Perk'].Object.Parent.Visible and chams.Options['Murderer colour']
 and items.Options['Gun ESP'] and items.Options['Trap ESP'], 'late MM2 must publish role and item overlays')
assert(not byName('KillAura') and byName('Knife Stab')==feature and card==ex.state.mm2KnifeAuraModule)
assert(feature.registry['Knife Stab']==feature and not feature.registry.KillAura)
assert(feature.configKey=='Universal.KillAura' and feature.categoryName=='Exploits')
assert(ex.state.moduleSearch.Resolve('Knife Stab').entry.feature==feature)
assert(feature.row:GetAttribute('FeatureSortName')=='knife stab')
local title=feature.row:FindFirstChild('Title');local record=title and ex.state.bitmapText._live[title]
assert(record and record.request.segments[1].text=='Knife Stab')
assert(ex.configData.states['Universal.KillAura.KnifeAura']==true and card.Options['Knife Aura'].Value==true)
assert(ex.configData.values['Universal.KillAura.AuraRange']==22 and card.Options['Aura Range'].Value==22)
assert(ex.configData.values['Shortcut.UniversalKillAura']=='G' and binding.key==Enum.KeyCode.G,
 'the migrated key must already work in this session, not only after reinjection')
assert(card.Enabled and feature.enabled and ex.state.mm2KnifeRuntime.masterEnabled,
 'legacy enabled state, controller and actual UI must agree')
local rows={}
for _,row in ipairs(ex.state.clickGui.categories.Exploits.window.body:GetChildren()) do
 local name=row:GetAttribute('FeatureSortName');if type(name)=='string' then table.insert(rows,row) end
end
table.sort(rows,function(a,b) return a.LayoutOrder<b.LayoutOrder end)
for i=2,#rows do assert(rows[i-1]:GetAttribute('FeatureSortName')<=rows[i]:GetAttribute('FeatureSortName')) end
-- Exercise the migrated keyboard shortcut twice, not just its saved value.
local key={UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.G}
UserInputService.InputBegan:Fire(key,false)
assert(not card.Enabled and not feature.enabled and not ex.state.mm2KnifeRuntime.masterEnabled)
UserInputService.InputBegan:Fire(key,false)
assert(card.Enabled and feature.enabled and ex.state.mm2KnifeRuntime.masterEnabled)
-- Keep a provider option selected while its game unloads.
local gunOption=items.Options['Gun ESP']
local trapOption=items.Options['Trap ESP']
local gunControl=ex.state.toggleControls['Universal.ItemRender.GunESP']
gunControl.setChecked(true)
assert(items.Enabled and gunOption.Value and gunOption.Object.Parent.Visible)
-- Direct composite unload exercises the real game adapter, not a mock rename.
ex.state.activeGameModule.destroy()
assert(not card.Enabled and not feature.enabled and card.CombatAdapter==nil and ex.state.mm2KnifeAuraModule==nil)
assert(not chams.Options['Show Perk'].Object.Parent.Visible, 'MM2 perk row must hide when its provider unloads')
assert(not gunOption.Object.Parent.Visible and not trapOption.Object.Parent.Visible,
 'item-provider rows must hide when their providers unload')
local calls={}
local replacement={name='Gun ESP',tooltip='replacement',setEnabled=function(v) table.insert(calls,v) end}
local release=ex.state.moduleServices.itemEsp.register(replacement)
assert(release and items.Options['Gun ESP']==gunOption and gunOption.Object.Parent.Visible and calls[#calls]==true,
 'same-name replacement must reuse the row and honor its existing ON state')
gunControl.setChecked(false)
assert(calls[#calls]==false, 'the row must call the replacement, not the retired provider')
gunControl.setChecked(true)
assert(calls[#calls]==true)
release()
assert(not gunOption.Object.Parent.Visible and calls[#calls]==false,
 'removing an active replacement must stop it and hide its row')
assert(ex.configData.states['Universal.KillAura']==true, 'unload must not erase the saved enabled state')
assert(feature.name=='KillAura' and feature.description==originalDescription and feature.registry.KillAura==feature)
assert(record.request.segments[1].text=='KillAura' and ex.state.moduleSearch.Resolve('KillAura').entry.feature==feature)
assert(card.OptionFilter('Reach') and not card.OptionFilter('Kill All') and not card.OptionFilter('Knife Aura'),
 'detach must restore universal options and hide stale MM2 actions')
print('PASS actual late MM2 fingerprint: Knife Stab migration, keybind/UI and adapter cleanup')
'''
with tempfile.TemporaryDirectory(prefix='mm2-late-adapter-') as tmp:
    script = Path(tmp) / 'boot.luau'
    script.write_text(source)
    result = subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stdout[-5000:] + '\n' + result.stderr)
    assert 'PASS actual late MM2 fingerprint:' in result.stdout
    print('PASS actual late MM2 fingerprint: Knife Stab migration, keybind/UI and adapter cleanup')
    # A newer provider belongs to another module; MM2 must not remove it.
    ownership = audit_menu.build(debug=True).read_text() + r'''
local previous=ex.state.gameBridge.roleProvider
assert(previous and previous.Name=='MM2')
local other={Name='Other',Roles={'Other'},Get=function() return 'Other' end}
ex.state.registerRoleProvider(other)
ex.state.activeGameModule.destroy()
assert(ex.state.gameBridge.roleProvider==other, 'MM2 unload must preserve a newer role provider')
print('PASS MM2 role provider ownership')
'''
    script.write_text(ownership)
    result = subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stdout[-2500:] + '\n' + result.stderr)
    assert 'PASS MM2 role provider ownership' in result.stdout
    print('PASS MM2 role provider ownership: unload preserves a newer game provider')
