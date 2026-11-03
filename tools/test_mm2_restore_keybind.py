#!/usr/bin/env python3
"""Saved ON restore can overlap a keypress; a late restore must not undo OFF."""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
saved = 'states = { ["ClickGUI.Showdock"] = false },'
assert source.count(saved) == 1
source = source.replace(saved, 'states = { ["ClickGUI.Showdock"] = false, ["MM2.GunAura"] = true },', 1)
setup = '''
PAUSED_RESTORE = {}
task.defer = function(fn,...)
    local co=coroutine.create(fn)
    local ok,err=coroutine.resume(co,...);assert(ok,err)
    if coroutine.status(co)=='suspended' then table.insert(PAUSED_RESTORE,co) end
    return co
end
GENV.PAUSE_GUN_AURA = true
'''
assert source.count('SOURCES = {\n') == 1
source = source.replace('SOURCES = {\n', setup + '\nSOURCES = {\n', 1)
anchor = '        gunAuraTick()\n    end\n\n    GunAuraFeature = createUniversalFeature('
assert source.count(anchor) == 1
source = source.replace(anchor, '        gunAuraTick()\n        if GENV.PAUSE_GUN_AURA then coroutine.yield("restoring Gun Aura") end\n    end\n\n    GunAuraFeature = createUniversalFeature(', 1)
probe = r'''
local f=assert(ex.state.mm2GunAuraFeature);assert(ex.configData.states[f.configKey])
assert(#PAUSED_RESTORE==1 and coroutine.status(PAUSED_RESTORE[1])=='suspended')
assert(ex.state.mm2GunAuraEnabled and f.enabled, 'saved restore should publish its in-progress ON state')
GENV.PAUSE_GUN_AURA=false
local binding=assert(ex.state.shortcutBindings[f.configKey]);binding.assign(Enum.KeyCode.K)
UserInputService.InputBegan:Fire({KeyCode=Enum.KeyCode.K,UserInputType=Enum.UserInputType.Keyboard},false)
assert(not f.enabled and not ex.state.mm2GunAuraEnabled, 'keypress must turn the restoring feature OFF')
local ok,err=coroutine.resume(PAUSED_RESTORE[1]);assert(ok,err)
assert(not f.enabled and not ex.state.mm2GunAuraEnabled and ex.configData.states[f.configKey]==false,
    'finishing an older restore must not overwrite the newer OFF')
print('PASS MM2 saved state: a late restore does not override a newer keypress')
'''
with tempfile.TemporaryDirectory(prefix='mm2-restore-key-') as tmp:
    path = Path(tmp) / 'restore.luau'
    path.write_text(source + probe, encoding='utf-8')
    result = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout[-1800:] + '\n' + result.stderr)
    assert 'PASS MM2 saved state:' in result.stdout
    print('PASS MM2 saved state: a late restore does not override a newer keypress')
