#!/usr/bin/env python3
"""MM2 keybind state, actual card skins and slow profile writes (simulated)."""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
probe = r'''
assert(game.PlaceId==142823291 and ex.state.activeGameName=='MM2')
local f=assert(ex.state.mm2GunAuraFeature, 'real MM2 Gun Aura card')
local binding=assert(ex.state.shortcutBindings[f.configKey])
local key={KeyCode=Enum.KeyCode.K,UserInputType=Enum.UserInputType.Keyboard}
local function same(a,b) return a.R==b.R and a.G==b.G and a.B==b.B end
local function check(on)
    assert(f.enabled==on and (ex.state.mm2GunAuraEnabled==true)==on,'MM2 runtime and feature state')
    assert(same(f.row.BackgroundColor3,ex.Theme.enabled)==on,'MM2 card must match its state')
    ex.state.hudList.refresh()
    assert((ex.state.hudList.frame:FindFirstChild('Gun Aura')~=nil)==on,'MM2 hacklist must match its state')
end
ex.state.animationsEnabled=false
ex.state.hudList.SetVisible(true)
if f.enabled then f.activationTarget.MouseButton1Click:Fire() end
binding.assign(Enum.KeyCode.K)
assert(f.bindSquare and f.bindSquare.Text~='', 'the assigned key must remain visible')
assert(not same(f.bindSquare.BackgroundColor3,ex.Theme.enabled),
    'an assigned key must not make a disabled MM2 module look enabled')
check(false)
UserInputService.InputBegan:Fire(key,false)
check(true)
assert(same(f.bindSquare.BackgroundColor3,ex.Theme.enabled), 'bound square follows ON')
UserInputService.InputBegan:Fire(key,false)
check(false)
assert(not same(f.bindSquare.BackgroundColor3,ex.Theme.enabled), 'bound square follows OFF')
f.activationTarget.MouseButton1Click:Fire();check(true)
f.activationTarget.MouseButton1Click:Fire();check(false)

-- Executors may yield while writing a profile. A key must update the actual
-- card immediately, not only the feature/HackList before the write finishes.
local oldSpawn, oldWrite = task.spawn, writefile
local spawned={}
task.spawn=function(fn,...)
    local co=coroutine.create(fn);table.insert(spawned,co)
    local ok,err=coroutine.resume(co,...);assert(ok,err)
    return co
end
writefile=function(_path,_body) coroutine.yield('slow write') end
UserInputService.InputBegan:Fire(key,false)
assert(#spawned>0 and coroutine.status(spawned[#spawned])=='suspended', 'profile write must be paused')
check(true)
assert(same(f.bindSquare.BackgroundColor3,ex.Theme.enabled), 'key ON is painted before storage finishes')
local first=spawned[#spawned]
-- Toggle OFF before the ON write resumes, then complete them out of order.
UserInputService.InputBegan:Fire(key,false)
local second=spawned[#spawned]
assert(second~=first and coroutine.status(second)=='suspended')
check(false)
assert(not same(f.bindSquare.BackgroundColor3,ex.Theme.enabled), 'key OFF is painted before storage finishes')
local function finish(co)
    local guard=0
    while coroutine.status(co)~='dead' do
        guard+=1;assert(guard<10,'a stalled write must not spawn an infinite loop')
        local ok,err=coroutine.resume(co);assert(ok,err)
    end
end
finish(second);check(false);finish(first);check(false)
task.spawn,writefile=oldSpawn,oldWrite

-- A feature callback may itself yield (independent of file I/O). A later OFF
-- must stay OFF when a slow earlier ON eventually finishes.
local oldToggle=f.onToggle;local handlers={}
f.onToggle=function(value)
    oldToggle(value)
    if value then coroutine.yield('slow feature setup') end
end
task.spawn=function(fn,...)
    local co=coroutine.create(fn);table.insert(handlers,co)
    local ok,err=coroutine.resume(co,...);assert(ok,err)
    return co
end
UserInputService.InputBegan:Fire(key,false)
assert(coroutine.status(handlers[1])=='suspended');check(true)
UserInputService.InputBegan:Fire(key,false);check(false)
finish(handlers[1]);check(false)
assert(ex.configData.states[f.configKey]==false,'a late ON handler must not save over the newer OFF')
f.onToggle=oldToggle;task.spawn=oldSpawn
-- A failing activation must undo the optimistic paint and call cleanup.
f.onToggle=function(value)
    if value then error('mock activation failure') end
    oldToggle(false)
end
UserInputService.InputBegan:Fire(key,false);check(false)
assert(not same(f.bindSquare.BackgroundColor3,ex.Theme.enabled),'failed activation restores OFF indicator')
f.onToggle=oldToggle
-- A separate UI painting fault must not swallow the module toggle itself.
local oldSkin=ex.state.applyCardSkin
ex.state.applyCardSkin=function() error('mock paint failure') end
UserInputService.InputBegan:Fire(key,false)
assert(f.enabled and ex.state.mm2GunAuraEnabled, 'paint failure must not block the feature callback')
ex.state.applyCardSkin=oldSkin;oldSkin(f,false);f.syncBindSquare();check(true)
UserInputService.InputBegan:Fire(key,false);check(false)

-- A second, unrelated card must follow the same rule: an assigned key on a
-- disabled module may never paint its square as enabled. Anti AFK replaces the
-- removed Shaders card as the control here.
local af
for _,candidate in ipairs(ex.allFeatures) do
    if candidate.name=='Anti AFK' then af=candidate;break end
end
assert(af,'Anti AFK feature must exist')
local afBinding=assert(ex.state.shortcutBindings[af.configKey])
if af.enabled then af.activationTarget.MouseButton1Click:Fire() end
afBinding.assign(Enum.KeyCode.F)
assert(not af.enabled and not same(af.bindSquare.BackgroundColor3,ex.Theme.enabled))
local afKey={KeyCode=Enum.KeyCode.F,UserInputType=Enum.UserInputType.Keyboard}
UserInputService.InputBegan:Fire(afKey,false)
assert(af.enabled and same(af.row.BackgroundColor3,ex.Theme.enabled)
    and same(af.bindSquare.BackgroundColor3,ex.Theme.enabled),'Anti AFK key ON')
UserInputService.InputBegan:Fire(afKey,false)
assert(not af.enabled and not same(af.row.BackgroundColor3,ex.Theme.enabled)
    and not same(af.bindSquare.BackgroundColor3,ex.Theme.enabled),'Anti AFK key OFF')
-- Duplicate bindings still use the warning colour, irrespective of ON/OFF.
afBinding.assign(Enum.KeyCode.K)
assert(same(af.bindSquare.BackgroundColor3,ex.Theme.negative)
    and same(f.bindSquare.BackgroundColor3,ex.Theme.negative),'both conflicting keys repaint immediately')
afBinding.assign(Enum.KeyCode.K)
assert(not same(af.bindSquare.BackgroundColor3,ex.Theme.negative)
    and not same(f.bindSquare.BackgroundColor3,ex.Theme.negative),'clearing the conflict repaints both keys')
-- Leave the control card bound to its own key so the rest of the probe keeps
-- exercising Gun Aura alone.
afBinding.assign(Enum.KeyCode.F)
-- Gun Aimbot deliberately uses its key for a manual shot, not a module toggle.
local gun=assert(ex.state.mm2SilentAimFeature)
local gunBinding=assert(ex.state.shortcutBindings[gun.configKey]);assert(not gun.enabled)
gunBinding.assign(Enum.KeyCode.G)
local originalPress=gunBinding.onPress;local gunCalls=0
assert(type(originalPress)=='function')
gunBinding.onPress=function() gunCalls+=1;originalPress() end
UserInputService.InputBegan:Fire({KeyCode=Enum.KeyCode.G,UserInputType=Enum.UserInputType.Keyboard},false)
assert(gunCalls==1 and not gun.enabled and not same(gun.row.BackgroundColor3,ex.Theme.enabled),
    'manual Gun Aimbot key must not toggle its module')
print('PASS MM2 keybinds: Gun Aura, Anti AFK, manual Gun key, click and slow writes')
'''
with tempfile.TemporaryDirectory(prefix='mm2-ui-keybinds-') as tmp:
    path = Path(tmp) / 'mm2.luau'
    path.write_text(source + probe, encoding='utf-8')
    result = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout[-2500:] + '\n' + result.stderr)
    assert 'PASS MM2 keybinds:' in result.stdout
    print('PASS MM2 keybinds: Gun Aura, Anti AFK, manual Gun key, click and slow writes')
