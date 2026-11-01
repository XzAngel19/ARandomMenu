#!/usr/bin/env python3
"""Real MM2 boots preserve legacy and explicit KillAura states, settings and keys."""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text()
old = '''    states = { ["ClickGUI.Showdock"] = false },
    values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000 },
    ui = {},'''
assert source.count(old) == 1
cases = [
    # Explicit new settings win over old ones. Missing new settings migrate.
    ('legacy', '', '', 'true', 'G', 'true', '22'),
    ('explicit_off', '["Universal.KillAura"] = false, ["Universal.KillAura.KnifeAura"] = false,',
     '["Shortcut.UniversalKillAura"] = "H", ["Universal.KillAura.AuraRange"] = 10,',
     'false', 'H', 'false', '10'),
    ('explicit_on', '["Universal.KillAura"] = true, ["Universal.KillAura.KnifeAura"] = false,',
     '["Shortcut.UniversalKillAura"] = "H", ["Universal.KillAura.AuraRange"] = 10,',
     'true', 'H', 'false', '10'),
]
with tempfile.TemporaryDirectory(prefix='knife-migration-') as tmp:
    path = Path(tmp) / 'boot.luau'
    for name, states, values, enabled, key, aura, reach in cases:
        saved = f'''    states = {{ ["ClickGUI.Showdock"] = false, {states}
        ["MM2.Knife"] = true, ["MM2.Knife.KnifeAura"] = true }},
    values = {{ ["ClickGUI.Arrows"] = {{255, 255, 255}}, ["Universal.Speed.Speed"] = 5000,
        {values} ["MM2.Knife.AuraRange"] = 22, ["Shortcut.MM2Knife"] = "G" }},
    ui = {{ unboundKeyDefaultsVersion = 1 }},'''
        probe = f'''
local card=ex.state.mm2KnifeAuraModule;local feature=ex.state.mm2KnifeFeature
local binding=ex.state.shortcutBindings['Universal.KillAura']
assert(card and feature and feature.name=='Knife Stab' and feature.configKey=='Universal.KillAura')
assert(card.Enabled=={enabled} and feature.enabled=={enabled} and ex.state.mm2KnifeRuntime.masterEnabled=={enabled}, 'state/UI mismatch: {name}')
assert(ex.configData.states['Universal.KillAura']=={enabled}, 'wrong persisted state: {name}')
assert(card.Options['Knife Aura'].Value=={aura} and card.Options['Aura Range'].Value=={reach}, 'wrong saved options: {name}')
assert(binding and binding.key==Enum.KeyCode.{key} and ex.configData.values['Shortcut.UniversalKillAura']=='{key}', 'wrong saved shortcut: {name}')
local input={{UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.{key}}}
UserInputService.InputBegan:Fire(input,false)
assert(card.Enabled~={enabled} and feature.enabled~={enabled}, 'shortcut must toggle migrated controller: {name}')
UserInputService.InputBegan:Fire(input,false)
assert(card.Enabled=={enabled} and feature.enabled=={enabled}, 'shortcut must restore controller: {name}')
ex.state.activeGameModule.destroy()
assert(not card.Enabled and not feature.enabled and ex.configData.states['Universal.KillAura']=={enabled}, 'cleanup/state persistence: {name}')
print('PASS knife migration: {name}')
'''
        path.write_text(source.replace(old, saved, 1) + probe)
        result = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(f'{name}:\n{result.stdout[-2500:]}\n{result.stderr}')
        assert f'PASS knife migration: {name}' in result.stdout
print('PASS MM2 Knife Stab: legacy/current states, options and shortcuts across actual bundle boots')
