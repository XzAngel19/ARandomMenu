#!/usr/bin/env python3
"""Execute v16 visibility, migration, evidence and cosmetic code in mocked Luau.
LUAU=/path/to/luau python3 tools/test_mm2_v16.py
These are deterministic regression tests, not a Roblox runtime/physics test.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()
LEARNING = (ROOT / 'src/games/universal/Other/GameLearning.lua').read_text()
VISUALS = (ROOT / 'src/games/MM2/Render/WeaponVisuals.lua').read_text()


def build():
    chunks = [PRELUDE, section(BASE, 'local predictionMath = {}', 'type MotionSample')]
    chunks += [r'''
do
local localChar, target, tagged = {}, {}, {}
local LocalPlayer={Character=localChar}
local CollectionService={GetTagged=function(_,tag) assert(tag=="WeaponPassthrough"); return {tagged} end}
local RaycastParams={new=function() return {} end}
local layers,calls={},0
local workspace={Raycast=function(_,origin,direction,params)
    calls+=1
    assert(table.find(params.FilterDescendantsInstances,localChar))
    assert(table.find(params.FilterDescendantsInstances,tagged))
    for _,part in ipairs(layers) do
        if not table.find(params.FilterDescendantsInstances,part) then return {Instance=part} end
    end
    return nil
end}
local function part(transparency, owner)
    return {Transparency=transparency,IsA=function(_,t) return t=="BasePart" end,
        IsDescendantOf=function(_,p) return p==owner end}
end
''', section(BASE, 'local function isWeaponPathClear(', 'local function getWeaponFromContainer('), r'''
local a,b=Vector3.zero,Vector3.new(10,0,0)
assert(isWeaponPathClear(a,b,target))
layers={part(1),part(0,target)}; assert(isWeaponPathClear(a,b,target))
layers={part(1),part(0)}; assert(not isWeaponPathClear(a,b,target))
layers={part(0.99)}; assert(not isWeaponPathClear(a,b,target))
layers={}; for i=1,40 do table.insert(layers,part(1)) end
calls=0; assert(not isWeaponPathClear(a,b,target) and calls==32)
pass("native LOS filters: local/tagged excluded; transparent skipped; opaque blocked; bounded fail-closed")
end

do
local runtime={sessionId="new-session",sessionGunAttempts=0,events={},motionBuckets={},
    gunAcceptance={},knifeSpeed={},knifeSpawnDelay={}}
local source={session={gunAttempts=3.139e57,events={{kind="gun"}}},aggregate={
    gunAcceptanceMs={count=51,mean=150,m2=5,minimum=80,maximum=250},
    knifeSpeedStudsPerSecond={count=192,mean=96,m2=0,minimum=96,maximum=96},
    knifeSpawnDelayMs={count=1e57,mean=200,m2=0,minimum=200,maximum=200}}}
local files={out="original bytes"}
local failBackup=false
local environment={readfile=function(path) assert(files[path],"not found"); return files[path] end,
    isfile=function(path) return files[path]~=nil end,
    writefile=function(path,text) if failBackup then error("no space") end; files[path]=text end}
local HttpService={JSONDecode=function() return source end}
local OUTPUT_PATH,trajectoryLogPrefix="out","test"
local warn=function() end
''', section(BASE, '    local function applyStatsPayload(', '    local function restoreMotionBucket('),
              section(BASE, '    local function loadSavedHistory()', '    local function vectorArray('), r'''
loadSavedHistory()
assert(files[runtime.historyBackup]=="original bytes" and files.out=="original bytes")
assert(runtime.sessionGunAttempts==0 and #runtime.events==0 and next(runtime.motionBuckets)==nil)
assert(runtime.gunAcceptance.count==51 and runtime.knifeSpeed.mean==96)
assert(runtime.knifeSpawnDelay.count==nil,"corrupt stats imported")
runtime.persistenceBlocked=false; failBackup=true; loadSavedHistory()
assert(runtime.persistenceBlocked and files.out=="original bytes")
failBackup=false; environment.readfile=function() error("permission denied") end
runtime.persistenceBlocked=false; loadSavedHistory(); assert(runtime.persistenceBlocked)
files.out=nil; runtime.persistenceBlocked=false; loadSavedHistory(); assert(not runtime.persistenceBlocked)
pass("migration: byte-exact backup; poisoned totals/events quarantined; valid stats kept; failures protected")
end

do
local runtime={sessionId="GL-session",buildStamp="v16",shots={},spawnShots={},hits={},revision=0,aggregates={
    shots=0,unconfirmed=0,confirmations=0,targetHits=0,projectileObservations=0,deathAssociations=0,unattributedDeaths=0},shotCounter=0}
local timers={}
local task={delay=function(_,fn) table.insert(timers,fn) end}
local tuning={killWindowSeconds=4,maxEvents=300}
local function isMM2() return true end
local function clampTrim() end
local function vectorArray(v) return {v.X,v.Y,v.Z} end
local function getPingMilliseconds() return 180 end
local function buildScene() return {} end
local LocalPlayer={Character={FindFirstChild=function() return {Position=Vector3.zero} end}}
local mouse={Hit={Position=Vector3.new(10,0,0)}}
local typeof=function(v) if type(v)=="table" and v.X then return "Vector3" end; return type(v) end
local os={clock=function() return 10 end,time=function() return 123 end}
''', section(LEARNING, '        local function finalizeShot(', '        local function recordShot('),
              section(LEARNING, '        local function recordAuthoredShot(', '        local function watchPlayer('), r'''
recordAuthoredShot({kind="knifeActivation",shotId="activation"})
assert(runtime.aggregates.shots==0)
local function shoot(id,kind) recordAuthoredShot({kind=kind or "gun",shotId=id,targetName="Target",sessionId="core-session",buildStamp="v16",toolName="Gun",originPos=Vector3.zero,aimPos=Vector3.new(10,0,0)}) end
shoot("one"); shoot("one"); assert(runtime.aggregates.shots==1 and runtime.shots[1].target=="Target")
recordConfirmation({shotId="one",kind="gun",hitTarget=true,evidence="GunFired.hitPart"})
recordConfirmation({shotId="one",kind="gun",hitTarget=true})
timers[1]()
assert(runtime.aggregates.targetHits==1 and runtime.aggregates.confirmations==1)
assert(runtime.shots[1].outcome.verdict=="target-hit" and runtime.aggregates.unconfirmed==0)
shoot("two"); timers[2](); assert(runtime.shots[2].outcome.verdict=="unconfirmed")
recordConfirmation({shotId="two",kind="gun",hitTarget=true}); assert(runtime.aggregates.unconfirmed==0)
shoot("three","knife"); recordConfirmation({shotId="three",kind="knife",evidence="projectile-observed"})
assert(runtime.shots[3].outcome.verdict=="projectile-observed" and runtime.aggregates.targetHits==2)
recordDeath({Name="Bystander"}); assert(runtime.aggregates.unattributedDeaths==1)
recordDeath({Name="Target"}); assert(runtime.aggregates.deathAssociations==1)
assert(runtime.shots[3].outcome.verdict=="projectile-observed")
shoot("four"); runtime.sessionId="reset"; timers[4](); assert(runtime.aggregates.unconfirmed==0)
pass("evidence: no activation/author duplicate; targetName bridge; late hit replaces unknown; no invented miss/kill")
end
''']
    chunks += [r'''
do
-- Minimal Instance/signal/parenting model to run the WHOLE cosmetic module.
local function signal()
    local s={connections={}}
    function s:Connect(fn)
        local c={Connected=true,fn=fn}
        function c:Disconnect() self.Connected=false end
        table.insert(self.connections,c); return c
    end
    function s:Fire(...) for _,c in ipairs(self.connections) do if c.Connected then c.fn(...) end end end
    return s
end
local methods={}
local objects={}
local instanceMt={__index=function(o,k) return methods[k] or o.props[k] end,
    __newindex=function(o,k,v)
        if k=="Parent" then
            if o.props.Parent then local c=o.props.Parent.children; local i=table.find(c,o); if i then table.remove(c,i) end end
            if v then table.insert(v.children,o) end
        end
        o.props[k]=v
    end}
local cfMt={__mul=function(a,b) return CFrame.new(a.Position+b.Position) end}
cfMt.__index={ToObjectSpace=function(a,b) return CFrame.new(b.Position-a.Position) end}
CFrame.new=function(p) return setmetatable({Position=p or Vector3.zero},cfMt) end
local Instance={new=function(class)
    local o=setmetatable({props={ClassName=class,Name=class,Size=Vector3.new(1,2,1),CFrame=CFrame.new(),Transparency=0,Archivable=true,
        DescendantAdded=signal(),DescendantRemoving=signal()},children={},tags={},attributes={}},instanceMt)
    table.insert(objects,o); return o
end}
function methods:IsA(class)
    return self.ClassName==class or (class=="BasePart" and (self.ClassName=="Part" or self.ClassName=="MeshPart"))
        or (class=="DataModelMesh" and self.ClassName=="SpecialMesh")
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
    local list={}; for _,child in ipairs(self.children) do table.insert(list,child); for _,desc in ipairs(child:GetDescendants()) do table.insert(list,desc) end end; return list
end
function methods:FindFirstChild(name,recursive)
    for _,c in ipairs(recursive and self:GetDescendants() or self.children) do if c.Name==name then return c end end
end
function methods:FindFirstChildWhichIsA(class,recursive)
    for _,c in ipairs(recursive and self:GetDescendants() or self.children) do if c:IsA(class) then return c end end
end
function methods:Clone()
    if not self.Archivable then return nil end
    local c=Instance.new(self.ClassName)
    for k,v in pairs(self.props) do if k~="Parent" then c.props[k]=v end end
    c.tags=table.clone(self.tags); c.attributes=table.clone(self.attributes)
    for _,child in ipairs(self.children) do local cc=child:Clone(); if cc then cc.Parent=c end end
    return c
end
function methods:GetAttributes() return table.clone(self.attributes) end
function methods:SetAttribute(k,v) self.attributes[k]=v end
function methods:ClearAllChildren() for _,c in ipairs(self:GetChildren()) do c:Destroy() end end
function methods:Destroy() self:ClearAllChildren(); self.Parent=nil; self.destroyed=true end
local CollectionService={GetTags=function(_,o) return table.clone(o.tags) end,
    RemoveTag=function(_,o,tag) local i=table.find(o.tags,tag); if i then table.remove(o.tags,i) end end}
Vector3.xAxis=Vector3.new(1,0,0); Vector3.yAxis=Vector3.new(0,1,0); Vector3.zAxis=Vector3.new(0,0,1)
local Color3={fromRGB=function(...) return {...} end}
local ColorSequence={new=function(v) return v end}
local NumberSequence={new=function(v) return v end}
local workspace=Instance.new("Folder")
local LocalPlayer={CharacterAdded=signal(),CharacterRemoving=signal()}
local deferred={}
local task={defer=function(fn) table.insert(deferred,fn) end}
local function flush() local q=deferred; deferred={}; for _,fn in ipairs(q) do fn() end end
local tasks={}
local TaskManager={Connect=function(_,fn) local c={Connected=true,fn=fn}; function c:Disconnect() self.Connected=false end; table.insert(tasks,c); return c end}
local function taskCount() local n=0; for _,t in ipairs(tasks) do if t.Connected then n+=1 end end; return n end
local options,master={},nil
local createUniversalFeature=function(_,_,_,cb,config) assert(config.categoryName=="Render"); master=cb; return {} end
local function addToggleOption(_,name,default,cb) assert(default==false); options[name]=cb end
local function addColorOption(_,name,default,cb) options[name]=cb end
local function addNumberOption(_,name,default,low,high,cb) options[name]=cb end
local state={mm2Core={getPlayerWeapon=function(_,name) return LocalPlayer.Character:FindFirstChild(name) end}}
local MM2Scroll,mm2Features={},{}
local function child(parent,class,name)
    local c=Instance.new(class); c.Name=name or class; c.Parent=parent; return c
end
local function character(r15)
    local c=Instance.new("Model")
    child(c,"Part",r15 and "LeftHand" or "Left Arm")
    child(c,"Part",r15 and "RightHand" or "Right Arm")
    return c
end
LocalPlayer.Character=character(false)
local gun=child(LocalPlayer.Character,"Tool","Gun")
local handle=child(gun,"Part","Handle"); handle.tags={"Weapon_Gun"}; handle.attributes={Damage=100}; handle.Anchored=true
child(handle,"Script"); child(handle,"RemoteEvent"); child(handle,"WeldConstraint")
local mesh=child(handle,"SpecialMesh"); child(mesh,"Script")
local vh=child(gun,"Model","VH"); child(vh,"MeshPart","Blade")
''', VISUALS.removesuffix('return Module\n'), r'''
Module.init({})
assert(#workspace.children==0 and taskCount()==0,"default must be off")
options["Double Gun"](true); flush(); assert(#workspace.children==0)
master(true); flush()
local folder=workspace.children[1]; assert(folder and #folder.children==2)
for _,copy in ipairs(folder.children) do
    assert(copy:IsA("BasePart") and not copy.Anchored and copy.Massless and not copy.CanTouch and not copy.CanQuery and not copy.CanCollide)
    assert(#copy.tags==0 and next(copy.attributes)==nil)
    for _,desc in ipairs(copy:GetDescendants()) do assert(not desc:IsA("Script") and not desc:IsA("RemoteEvent")) end
end
assert(handle.Anchored and #handle.tags==1 and handle.attributes.Damage==100 and #handle.children==4)
assert(taskCount()==0,"Double cosmetics need no loop")
gun.Parent=nil; LocalPlayer.Character.DescendantRemoving:Fire(gun); flush()
assert(folder.destroyed and #workspace.children[1].children==0)
local newChar=character(true)
local knife=child(newChar,"Tool","Knife"); child(knife,"Part","Handle")
local newVh=child(knife,"Model","VH"); child(newVh,"MeshPart","Blade")
LocalPlayer.CharacterRemoving:Fire(); LocalPlayer.Character=newChar; LocalPlayer.CharacterAdded:Fire(newChar)
options["Double Knife"](true); options["Electric Knife"](true); flush()
assert(taskCount()==1 and #workspace.children[1].children==4,"R15 plus VH and two own carriers")
for _,t in ipairs(tasks) do if t.Connected then t.fn(0.125) end end
options["Electric Knife"](false); flush(); assert(taskCount()==0)
master(false); flush(); assert(#workspace.children==0 and taskCount()==0)
for _,sig in ipairs({newChar.DescendantAdded,newChar.DescendantRemoving,LocalPlayer.CharacterAdded,LocalPlayer.CharacterRemoving}) do
    for _,c in ipairs(sig.connections) do assert(not c.Connected) end
end
master(true); options["Electric Knife"](true); Module.destroy(); flush()
assert(#workspace.children==0 and taskCount()==0 and not Module.Initialized,"deferred rebuild after destroy")
pass("full Weapon Visuals lifecycle: OFF, R6/R15, nested VH, safe geometry, unequip, respawn, electric-only 8 Hz, destroy")
end
print("v16 regression groups passed:",passed)
''']
    return '\n'.join(chunks)


def main():
    assert 'FireServer' not in VISUALS and 'require(' not in VISUALS and 'loadstring' not in VISUALS
    assert 'Render/WeaponVisuals.lua' in (ROOT / 'src/Wurst.lua').read_text()
    with tempfile.TemporaryDirectory(prefix='mm2-v16-') as directory:
        script = Path(directory) / 'regressions.luau'
        script.write_text(build())
        subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], check=True)


if __name__ == '__main__':
    main()
