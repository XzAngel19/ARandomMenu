#!/usr/bin/env python3
"""Execute the actual PC namecall hook/shortcut lifecycle with mocked executor APIs.

The real shot constructor's geometry/wall behavior is exercised separately in
 test_gun_safety.py. This tests input routing and never claims server acceptance.
"""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import section

ROOT = Path(__file__).resolve().parents[1]
shoot = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()
infra = section(shoot, '    local observerGeneration: number = 0', '    local shotHookInstalled: boolean = false')
block = section(shoot, '    local shotHookInstalled: boolean = false', '    local lastAutoStatus:')
prelude = r'''
local function cf(name) return {type='CFrame', id=name} end
local function typeof(v) return type(v)=='table' and v.type or type(v) end
local Enum={KeyCode={Unknown={Name='Unknown'}}}
local target={Name='Murderer'}
local camera={CFrame=cf('camera')}
local character={}
local humanoid={}
local gun={Parent=character}
local gunRemote={id='gun'}
function gunRemote:IsA(c) return c=='RemoteEvent' end
local knifeRemote={id='knife'}
function gun:FindFirstChild(name) return name=='Shoot' and gunRemote or nil end
function humanoid:EquipTool(tool) tool.Parent=character end
local LocalPlayer={Character=character}
local weaponLookupThrows=false
local function getPlayerWeapon(_,name)
 if weaponLookupThrows then error('character streamed out') end
 if name=='Gun' then return gun end
end
local function getCharacterParts() return character,humanoid end
local function getSelectedShootTarget() return target end
local waits=0
local RunService={Heartbeat={Wait=function() waits+=1 end}}
local notifications={}
local function notify(message) table.insert(notifications,message) end
local delayed={}
local suspendedObservers={}
local task={delay=function(_,fn) table.insert(delayed,fn) end,
 spawn=function(fn)
  local co=coroutine.create(fn);local ok,err=coroutine.resume(co);assert(ok,tostring(err))
  if coroutine.status(co)=='suspended' then table.insert(suspendedObservers,co) end
 end}
local function flush() local jobs=delayed; delayed={}; for _,fn in ipairs(jobs) do fn() end end
local game={}
local sent={}
local function transport(remote,...)
 table.insert(sent,{remote=remote,args=table.pack(...)})
 return 'transport result'
end
local chain=transport
local method='FireServer'
local executorCaller=false
local hooks=0
local function hook(_,name,replacement)
 assert(name=='__namecall');hooks+=1
 local previous=chain;chain=replacement;return previous
end
local observerConnections=0
local function connectGunFiredSignal() observerConnections+=1;return true end
local disconnected=0
local function disconnectGunFiredObserver() disconnected+=1 end
local pauseObserver=false
local function getWeaponServiceModule()
 if pauseObserver then coroutine.yield() end
 return {}
end
-- v187: the engine entry for a fresh :FireServer call. A resend from inside
-- the hook re-enters as an executor-originated namecall; the mock must model
-- that dispatch or the re-entrant trampoline never runs.
function gunRemote:FireServer(...)
 local prevMethod, prevExecutor = method, executorCaller
 method='FireServer'; executorCaller=true
 local out=table.pack(chain(self,...))
 method, executorCaller = prevMethod, prevExecutor
 return table.unpack(out,1,out.n)
end
local state={isMobile=false,hookMetamethod=hook,getNamecallMethod=function() return method end,
 checkCaller=function() return executorCaller end,mm2ShotFeedback={hide=function() end}}
local shootFeatureActive=false
local shootOptionsReady=true
local autoShootActive=false
local autoShootWanted=false
local transientShotActive=false
local transientShotGeneration=0
local updateAutoShootConnection=nil
local aimMode='Bullet'
local solved=0
local blocked=false
local throws=false
local throwsAfterFrames=false
local lastRejectReason=''
local ShootFeature={SetStatus=function() error('status UI unavailable') end}
local keyShots=0
local function fireGunAtTarget(p,opts)
 assert(p==target)
 -- v187: the hook no longer pre-checks the weapon, so the solver itself is
 -- where a streamed-out weapon lookup surfaces (as in production).
 getPlayerWeapon(LocalPlayer,'Gun',true)
 solved+=1
 if throws then error('aim failure') end
 if blocked then return false end
 if opts.redirect then
  assert(opts.nativeRedirect==true and opts.nativeOrigin.id=='native-origin', 'native call options propagate')
  opts.redirect(cf(aimMode..'-origin'),cf(aimMode..'-end'))
  if throwsAfterFrames then error('post-solve observer failed') end
 else keyShots+=1 end
 return true
end
local function last() return sent[#sent] end
local function click(remote,a,b,...)
 local n=#sent
 local result=chain(remote,a,b,...)
 assert(result=='transport result' and #sent==n+1,'one and only one native transport')
 return last().args
end
'''
checks = r'''
local originalA,originalB=cf('native-origin'),cf('native-end')
local args=click(gunRemote,originalA,originalB,'tail',nil,'last')
assert(args[1]==originalA and args[2]==originalB and solved==0,'OFF leaves native shot unchanged')
-- An unavailable/yielding optional weapon observer cannot delay the PC hook;
-- a stale observer cannot attach after the user disables the module.
pauseObserver=true;local beforeConnections=observerConnections
toggleShootMurderer(true)
assert(shotHookInstalled and #suspendedObservers==1,'hook installs while observer discovery waits')
args=click(gunRemote,originalA,originalB);assert(args[1].id=='Bullet-origin')
toggleShootMurderer(false)
local co=table.remove(suspendedObservers);local ok,err=coroutine.resume(co);assert(ok,tostring(err))
assert(observerConnections==beforeConnections,'stale observer cannot reattach after OFF')
pauseObserver=false
toggleShootMurderer(true)
assert(shotHookInstalled and chain~=transport)
args=click(gunRemote,originalA,originalB,'tail',nil,'last')
assert(args[1].id=='Bullet-origin' and args[2].id=='Bullet-end' and args.n==5
 and args[3]=='tail' and args[4]==nil and args[5]=='last','Bullet redirects and preserves extra arguments')
aimMode='Silent(CFrame)'
args=click(gunRemote,originalA,originalB)
assert(args[1].id=='Silent(CFrame)-origin' and args[2].id=='Silent(CFrame)-end','Silent redirects the same click')
assert(camera.CFrame.id=='camera','no aim lock or camera rotation')
blocked=true;args=click(gunRemote,originalA,originalB)
assert(args[1]==originalA and args[2]==originalB,'WallCheck failure passes the original click')
blocked=false;throws=true;args=click(gunRemote,originalA,originalB)
assert(args[1]==originalA and args[2]==originalB,'failed solver preserves native click')
throws=false;throwsAfterFrames=true;args=click(gunRemote,originalA,originalB)
assert(args[1].id=='Silent(CFrame)-origin' and args[2].id=='Silent(CFrame)-end',
 'valid frames survive an optional error after construction')
throwsAfterFrames=false
local solvedBefore=solved
executorCaller=true;args=click(gunRemote,originalA,originalB)
assert(args[1]==originalA and solved==solvedBefore,'Auto Shoot/Farm/executor packets are not redirected')
executorCaller=false;args=click(knifeRemote,originalA,originalB)
assert(args[1]==originalA and solved==solvedBefore,'Knife and unrelated remotes untouched')
weaponLookupThrows=true;args=click(knifeRemote,originalA,originalB)
assert(args[1]==originalA and args[2]==originalB and solved==solvedBefore,
 'v187: unrelated remotes trampoline without a single method call first')
args=click(gunRemote,originalA,originalB)
assert(args[1]==originalA and args[2]==originalB and solved==solvedBefore,
 'streaming/weapon lookup errors cannot swallow the native click')
weaponLookupThrows=false
args=click(gunRemote,'unexpected-format',originalB)
assert(args[1]=='unexpected-format' and solved==solvedBefore,'unknown packet contracts pass through')
method='InvokeServer';args=click(gunRemote,originalA,originalB)
assert(args[1]==originalA and solved==solvedBefore,'only FireServer is modified')
method='FireServer'
toggleShootMurderer(false)
assert(chain==transport and not shotHookInstalled,'OFF restores our topmost hook')
args=click(gunRemote,originalA,originalB);assert(args[1]==originalA)
-- One key is allowed to equip/fire while the PC master is OFF.
gun.Parent={};triggerManualShot()
assert(gun.Parent==character and waits==1 and keyShots==1,'key equips then fires with master OFF')
assert(transientShotActive and state.mm2ShotFeedback.shootActive,'feedback remains active for echo')
flush();assert(not transientShotActive and not state.mm2ShotFeedback.shootActive,'temporary feedback retires')
-- A third-party hook installed later must not be destroyed on OFF.
toggleShootMurderer(true)
local wrapped=chain
local third=function(remote,...) return wrapped(remote,...) end
chain=third
toggleShootMurderer(false)
assert(chain==third and shotHookInstalled,'do not overwrite a newer external hook')
args=click(gunRemote,originalA,originalB);assert(args[1]==originalA,'our retained wrapper is inert while OFF')
toggleShootMurderer(true);args=click(gunRemote,originalA,originalB)
assert(args[1].id=='Silent(CFrame)-origin','retained wrapper works after re-enable')
toggleShootMurderer(false)
-- Missing APIs fail closed: no native blocking, key remains available.
chain=transport;shotHookInstalled=false;state.checkCaller=nil
local before=#notifications
toggleShootMurderer(true)
assert(chain==transport and #notifications==before+1,'unsupported executor is disclosed')
toggleShootMurderer(false);triggerManualShot();assert(keyShots==2)
flush()
-- Mobile keeps its pre-existing action contract; never installs this hook.
state.isMobile=true;state.checkCaller=function() return false end
before=keyShots;triggerManualShot();assert(keyShots==before,'mobile OFF behavior is unchanged')
local oldHooks=hooks;toggleShootMurderer(true)
assert(hooks==oldHooks,'desktop namecall hook never installs on mobile')
triggerManualShot();assert(keyShots==before+1,'mobile ON action still fires')
toggleShootMurderer(false)
print('PASS Gun PC native: Bullet/Silent, one transport, untouched camera/other remotes, WallCheck, off key, mobile, cleanup and third-party hooks')
'''
with tempfile.TemporaryDirectory(prefix='gun-native-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(prelude+infra+block+'\n'+checks)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
