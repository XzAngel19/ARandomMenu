#!/usr/bin/env python3
"""Run the real consented MM2 recorder with client-visible manual/menu knives.

Mocks prove accounting, archives and lifecycle, not Roblox/server observation.
"""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
setup = r'''
local TELEMETRY='Wurst/Telemetry/MM2_Trajectory_Calibration.json'
local FILES,ENCODED,WRITES={},{},{}
local failArchive,failArchiveExists,corruptArchiveRead=false,false,false
local archiveHook=nil
local originalOs=os
local fakeClock=originalOs.clock()
os={clock=function() return fakeClock end,time=originalOs.time,date=originalOs.date}
local DELAYED_3,DELAYED_10={},{}
local delay0=task.delay
function task.delay(t,fn,...)
 if t==3 then table.insert(DELAYED_3,fn);return end
 if t==10 then table.insert(DELAYED_10,fn);return end
 return delay0(t,fn,...)
end
function isfolder(_) return true end
function makefolder(_) end
function isfile(path)
 if failArchiveExists and tostring(path):find('_part_',1,true) then error('exists denied') end
 return FILES[path]~=nil or tostring(path):find('Game_20260716',1,true)~=nil
end
function readfile(path)
 if corruptArchiveRead and tostring(path):find('_part_',1,true) then return 'corrupt' end
 if FILES[path]~=nil then return FILES[path] end
 if tostring(path):find('Game_20260716',1,true) then return HarnessSavedConfig end
 error('missing')
end
function writefile(path,bytes)
 local isArchive=tostring(path):find('_part_',1,true)~=nil
 if failArchive and isArchive then FILES[path]='partial-write';error('archive denied') end
 FILES[path]=bytes
 if tostring(path):find('/Telemetry/',1,true) then table.insert(WRITES,{path,bytes}) end
 if isArchive and archiveHook then local fn=archiveHook;archiveHook=nil;fn() end
end
DateTime={now=function() return {ToIsoDate=function() return 'now' end} end}
workspace.Gravity=196.2
function workspace:GetServerTimeNow() return 100 end
function LocalPlayer:GetMouse() return {Hit=CFrame.new(Vector3.new(10,2,3))} end
function LocalPlayer.Character:GetPivot() return CFrame.new(Vector3.zero) end
function PlayersService:GetPlayerFromCharacter(char)
 if char==LocalPlayer.Character then return LocalPlayer end
 if char==HarnessHeroGuy.Character then return HarnessHeroGuy end
end
local heroRoot=HarnessHeroGuy.Character:FindFirstChild('HumanoidRootPart')
heroRoot.Size=Vector3.new(2,2,1)
local heroHum=HarnessHeroGuy.Character:FindFirstChildOfClass('Humanoid')
heroHum.MoveDirection=Vector3.zero
local function clone(value,seen)
 if type(value)~='table' then return value end
 seen=seen or {};if seen[value] then return seen[value] end
 local out={};seen[value]=out
 for k,v in pairs(value) do out[clone(k,seen)]=clone(v,seen) end
 return out
end
function HttpService:JSONEncode(value)
 local id='json-'..tostring(#ENCODED+1)
 ENCODED[#ENCODED+1]=clone(value)
 return id
end
local function decoded(path)
 local n=tonumber(tostring(FILES[path]):match('json%-(%d+)'))
 return n and ENCODED[n] or nil
end
local projectileSignal,nativeThrow=signal(),signal()
local baseAdded=CollectionService.GetInstanceAddedSignal
function CollectionService:GetInstanceAddedSignal(tag)
 if tag=='ThrowingKnife' then return projectileSignal end
 return baseAdded(self,tag)
end
local clientServices=newInst('Folder');clientServices.Name='ClientServices';clientServices.Parent=ReplicatedStorage
local weaponModule=newInst('ModuleScript');weaponModule.Name='WeaponService';weaponModule.Parent=clientServices
local weaponService={KnifeThrown={Event=nativeThrow},GunFired={OnClientEvent=signal()}}
local knife=newInst('Tool');knife.Name='Knife';knife.Parent=LocalPlayer.Character
local handle=newInst('Part');handle.Name='Handle';handle.Position=Vector3.new(1,2,3);handle.CFrame=CFrame.new(handle.Position);handle.Parent=knife
local function makeProjectile(withLink,rawSpeed)
 local p=newInst('Folder');p.Name='ThrownKnife';p.Parent=workspace
 p:SetAttribute('Direction',Vector3.new(1,0,0))
 if rawSpeed~=nil then p:SetAttribute('ThrowSpeed',rawSpeed) end
 local blade=newInst('Part');blade.Name='BladePosition';blade.Position=Vector3.new(2,2,3);blade.Parent=p
 if withLink then
  local link=newInst('ObjectValue');link.Name='HandleLink';link.Value=handle;link.Parent=p
 end
 return p
end
local function flush10()
 local jobs=table.clone(DELAYED_10);table.clear(DELAYED_10)
 for _,fn in ipairs(jobs) do fn() end
end
'''
assert source.count('SOURCES = {\n') == 1
source = source.replace('SOURCES = {\n', setup + '\nSOURCES = {\n', 1)
common = r'''
local c=assert(ex.state.mm2TrajectoryCalibration)
ex.state.requireModule=function(module)
 if module==weaponModule then return weaponService end
 error('unknown module')
end
local function events()
 local snapshot=assert(decoded(TELEMETRY),'snapshot was encoded')
 return snapshot.session.events,snapshot
end
local function matching(list,phase,source)
 for _,ev in ipairs(list) do
  if ev.kind=='knife' and ev.phase==phase and (not source or ev.source==source) then return ev end
 end
end
'''
capture = common + r'''
-- Until Yes even visible projectiles and native signals are not observed.
local unseen=makeProjectile(false,96);projectileSignal:Fire(unseen);nativeThrow:Fire()
assert(#WRITES==0 and not c:save('before-consent'))
assert(c:setConsent(true),'Yes starts recorder')
assert(#nativeThrow.connections>0,'real WeaponService native throw signal was connected')
-- Tool.Activated may also happen around a manual throw: it must not create a
-- second counted attempt when the actual KnifeThrown event was observed.
local function step(label,fn)
 local ok,err=xpcall(fn,debug.traceback)
 assert(ok,label..': '..tostring(err))
end
step('activation',function() knife.Activated:Fire() end)
step('native',function() nativeThrow:Fire() end)
local manual=makeProjectile(true,96)
step('manual spawn',function() projectileSignal:Fire(manual) end)
local function sampleKnife(projectile)
 fakeClock+=0.1
 projectile:FindFirstChild('BladePosition').Position=Vector3.new(6,2,3)
 for _,scheduled in ipairs(ex.TaskManager.tasks) do
  if scheduled.label=='MM2 knife sampler' then scheduled.callback(0.1);return end
 end
 error('knife sampler missing')
end
step('manual sample',function() sampleKnife(manual) end)
step('manual finish',function() manual.Destroying:Fire() end)
-- A menu-authored throw follows a separate direct remote path.
c:noteAuthoredShot({kind='knife',tool=knife,originPos=Vector3.new(1,2,3),
 aimPos=Vector3.new(50,2,3),target=HarnessHeroGuy,
 source='menu-auto-throw',settings={mode='Auto Knife Throw'}})
local automatic=makeProjectile(true,96);projectileSignal:Fire(automatic)
heroHum.HealthChanged:Fire(50)
step('auto sample',function() sampleKnife(automatic) end)
automatic.Destroying:Fire()
-- An unannounced own blade cannot reuse the stale Activated record from the
-- first manual throw or manufacture another counted activation.
local unannounced=makeProjectile(true,96);projectileSignal:Fire(unannounced);unannounced.Destroying:Fire()
-- A client-visible blade without a HandleLink or speed still gets recorded.
local unknown=makeProjectile(false,nil);projectileSignal:Fire(unknown);unknown.Destroying:Fire()
assert(c:save('probe'))
local list,snapshot=events()
local manualEvent=assert(matching(list,'authored','native-throw-event'),'native intent recorded')
local autoEvent=assert(matching(list,'authored','menu-auto-throw'),'menu throw recorded')
assert(autoEvent.origin[1]==1 and autoEvent.endpoint[1]==50,'menu origin and endpoint saved')
local spawned,finished,linked,unknownFinished=0,0,0,false
local ids={};local autoResult=nil
for _,ev in ipairs(list) do
 if ev.kind=='knife' and ev.phase=='projectile-spawn' then spawned+=1;ids[ev.projectileId]=true end
 if ev.kind=='knife' and ev.phase=='projectile-linked' then
  linked+=1;assert(ids[ev.projectileId],'link associates its spawn')
 end
 if ev.kind=='knife' and ev.phase=='projectile-observed' then
  finished+=1
  assert(ids[ev.projectileId] and #ev.projectileTrajectory>=1,'blade path is retained')
  if ev.speed==nil then unknownFinished=true end
  if ev.shotId==autoEvent.shotId then autoResult=ev end
 end
end
assert(spawned==4 and linked==3 and finished==4 and unknownFinished,
 'every visible tag is retained, including missing link/speed')
assert(snapshot.session.knifeObserved==4 and snapshot.session.knifeAttempts==2
 and snapshot.session.knifeConfirmed==3,'activation and actual throw are not counted twice')
assert(autoResult and #autoResult.projectileTrajectory>=2 and #autoResult.targetTrajectory>=2
 and autoResult.targetHealthAtAim==100 and autoResult.targetHealthAfter==50,
 'actual sampler saves blade/target paths and client-observed health')
assert(not ex.featureConnections.MM2KnifeSampler,'sampler disconnects after the final projectile')
assert(manualEvent.shotId~=autoEvent.shotId)
local before=#WRITES;c:setConsent(false)
local after=makeProjectile(true,96);projectileSignal:Fire(after);nativeThrow:Fire()
flush10();assert(#WRITES==before and FILES[TELEMETRY]~=nil,'No disconnects observation and preserves old files')
print('PASS calibration capture: consent, native and menu attempts, linked/unlinked projectiles, no duplicate counts, No cleanup')
'''
archive = common + r'''
assert(c:setConsent(true))
-- A batch larger than the former 2,400-record limit is archived, not evicted.
for i=1,2410 do c:noteAuthoredShot({kind='knife',source='batch-test'}) end
failArchive=true;flush10()
local current,snapshot=events()
assert(#current==2410 and snapshot.session.evictedEvents==0,'failed archive keeps every event in snapshot')
local orphan='Wurst/Telemetry/MM2_Trajectory_'..snapshot.sessionId..'_part_1.json'
assert(FILES[orphan]=='partial-write','a failed writer may leave partial bytes')
failArchive=false
c:noteAuthoredShot({kind='knife',source='batch-test'});flush10()
current,snapshot=events()
assert(snapshot.session.archivedEvents==2411 and #snapshot.session.archiveFiles==1)
local archived=assert(decoded(snapshot.session.archiveFiles[1]))
assert(archived.kind=='mm2-trajectory-event-archive' and #archived.events==2411 and #current==0,
 'verified segment contains the complete batch')
assert(FILES[orphan]=='partial-write' and snapshot.session.archiveFiles[1]~=orphan,
 'retry uses a fresh name without overwriting partial bytes')
assert(snapshot.session.evictedEvents==0,'archive never silently evicts knife records')
print('PASS calibration archive: no eviction, failed IO retains events, verified segment and index')
'''
archive_races = common + r'''
assert(c:setConsent(true))
for i=1,2401 do c:noteAuthoredShot({kind='knife',source='race-test'}) end
failArchiveExists=true;flush10()
local current,snapshot=events()
assert(#current==2401 and snapshot.session.evictedEvents==0,'failed isfile must keep snapshot')
failArchiveExists=false;corruptArchiveRead=true
c:noteAuthoredShot({kind='knife',source='race-test'});flush10()
current,snapshot=events()
assert(#current==2402 and #snapshot.session.archiveFiles==0,'bad readback cannot clear buffer')
corruptArchiveRead=false
c:noteAuthoredShot({kind='knife',source='race-test'})
archiveHook=function() c:noteAuthoredShot({kind='knife',source='during-write'}) end
flush10()
current,snapshot=events()
assert(snapshot.session.archivedEvents==2403 and #current==1 and current[1].source=='during-write',
 'an event recorded during a yielding archive survives in the new snapshot')
assert(#decoded(snapshot.session.archiveFiles[1]).events==2403)
print('PASS calibration archive races: isfile/read errors retain data and concurrent event survives')
'''
archive_revoke = common + r'''
assert(c:setConsent(true))
for i=1,2401 do c:noteAuthoredShot({kind='knife',source='revoke-test'}) end
archiveHook=function() c:setConsent(false) end
flush10()
local current,snapshot=events()
assert(c:getConsent()==false and #current==2401 and snapshot.session.evictedEvents==0,
 'No during write retains the pre-archive snapshot and cannot discard events')
local before=#WRITES;flush10();assert(#WRITES==before,'revoked consent schedules no new writes')
assert(c:setConsent(true),'later explicit Yes may resume')
current,snapshot=events()
assert(#current==2401 and #snapshot.session.archiveFiles==0,'resuming retains the unarchived batch')
print('PASS calibration archive revoke: No during a write preserves data and prevents later writes')
'''
with tempfile.TemporaryDirectory(prefix='calibration-capture-') as tmp:
    for name,case in [('capture',capture),('archive',archive),('archive-races',archive_races),('archive-revoke',archive_revoke)]:
        path=Path(tmp)/(name+'.luau');path.write_text(source+case,encoding='utf-8')
        result=subprocess.run([os.environ.get('LUAU','luau'),str(path)],capture_output=True,text=True)
        if result.returncode: raise SystemExit(name+' failed:\n'+result.stdout[-4000:]+'\n'+result.stderr)
        assert 'PASS calibration' in result.stdout
        print(result.stdout[result.stdout.rfind('PASS calibration'):].strip())
