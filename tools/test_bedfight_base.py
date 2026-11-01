#!/usr/bin/env python3
"""Exercise BedFight's real base-module ESP and Anti Void lifecycles."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/BedFight/base.lua').read_text()
script=PRELUDE+r'''
local paramsCount=0
local RaycastParams={new=function() paramsCount+=1;return {} end}
local Color3={fromRGB=function(...) return {...} end}
local Vector2={new=function(...) return {...} end}
local UDim2={new=function(...) return {...} end,fromOffset=function(...) return {...} end,fromScale=function(...) return {...} end}
local UDim={new=function(...) return {...} end}
Enum.TextXAlignment={Center='Center'}
local anchor={Position=Vector3.new(3,100,0),IsA=function(_,kind) return kind=='BasePart' end}
local bed={Parent=true,IsA=function(_,kind) return kind=='Model' end,
    FindFirstChild=function(_,name) if name=='BedHitbox' then return anchor end end}
local beds={GetChildren=function() return {bed} end}
local ground={Parent=true,IsDescendantOf=function(self) return self.Parent~=nil end}
local groundHit=true
local lastParams
local workspace={CurrentCamera={},FindFirstChild=function(_,name) if name=='BedsContainer' then return beds end end,
    GetChildren=function() return {} end,Raycast=function(_,_,_,params)
        lastParams=params;assert(params.FilterDescendantsInstances[1]~=nil)
        if groundHit then return {Instance=ground} end
    end}
local floor={Value=0,IsA=function(_,kind) return kind=='NumberValue' end}
local barrier={FindFirstChild=function(_,name) if name=='MaxHeight' then return floor end end}
local info={FindFirstChild=function(_,name) if name=='DeathBarrierInfo' then return barrier end end}
local game={GetService=function(_,name)
    if name=='ReplicatedStorage' then return {FindFirstChild=function(_,child) if child=='GameInfo' then return info end end} end
end}
local function makeRoot(y)
    return {Position=Vector3.new(0,y,0),AssemblyLinearVelocity=Vector3.zero,CFrame={marker='original'}}
end
local function makeCharacter(root)
    local hum={HipHeight=2,MoveDirection=Vector3.zero}
    return {FindFirstChild=function(_,name) if name=='HumanoidRootPart' then return root end end,
        FindFirstChildOfClass=function(_,class) if class=='Humanoid' then return hum end end}
end
local root=makeRoot(100)
local player={Character=makeCharacter(root)}
local pool={};local layer={Visible=false}
local render={Layer=function() return layer end,Project=function() return {X=1,Y=2} end,
    Set=function(_,_,key) pool[key]=true;return {Show=function() end,Label=function() end} end,
    Release=function(_,_,key) pool[key]=nil end,ReleaseAll=function() table.clear(pool) end}
local features,providers={},{}
local env={state={bedFightScroll={},bedFightFeatures={},renderLibrary=render},LocalPlayer=player,ScreenGui={},featureConnections={}}
function env.createUniversalFeature(name,_,_,fn)
    local feature={};function feature:Toggle(v) fn(v) end;features[name]=feature;return feature
end
function env.addToggleOption() end
function env.addNumberOption() end
function env.addTextOption() end
function env.addActionOption() end
function env.addInformationOption() end
function env.registerEspExtra(p) providers[p.Name]=p end
function env.create(class,properties)
    local object={ClassName=class,Parent=properties.Parent}
    function object:Destroy() self.Parent=nil;self.destroyed=true end
    return object
end
function env.makeTextLabel() return {} end
function env.disconnectFeatureConnection(name)
    local c=env.featureConnections[name];if c then c:Disconnect();env.featureConnections[name]=nil end
end
env.TaskManager={Connect=function(_,fn) return {callback=fn,active=true,Disconnect=function(self) self.active=false end} end}
local function getfenv() return env end
'''+ '\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
local function frame(name) local c=env.featureConnections[name];assert(c and c.active);c.callback(1/60) end
now=0;Module.init({Services={protectedTargets={isProtected=function() return false end}}})
providers.Beds.Toggle(true);frame('BedFightBeds');assert(pool[bed] and layer.Visible)
providers.Beds.Toggle(false);assert(not pool[bed] and not layer.Visible)
providers.Beds.Toggle(true);frame('BedFightBeds');assert(pool[bed])
env.state.renderLibrary=nil -- the framework may unload first
Module.destroy();assert(not pool[bed] and not layer.Visible, 'unload releases BedFight bed drawings')
env.state.renderLibrary=render
-- A safe position must not leak through a new activation or a new character.
Module.init({Services={protectedTargets={isProtected=function() return false end}}})
features['Anti Void']:Toggle(true);groundHit=true;frame('BedFightVoid')
for _=1,120 do frame('BedFightVoid') end
assert(paramsCount==1, 'Anti Void reuses its raycast parameters')
root.Position=Vector3.new(0,10,0);groundHit=false;frame('BedFightVoid')
assert(root.CFrame.Position.Y==104, 'valid current-session ground still rescues')
root.Position=Vector3.new(0,100,0);groundHit=true;frame('BedFightVoid')
ground.Parent=nil;root.Position=Vector3.new(0,10,0);groundHit=false;local stale=root.CFrame;frame('BedFightVoid')
assert(root.CFrame==stale, 'removed ground cannot be a rescue destination')
ground.Parent=true;features['Anti Void']:Toggle(false);root.Position=Vector3.new(0,10,0);groundHit=false
features['Anti Void']:Toggle(true);local unchanged=root.CFrame;frame('BedFightVoid')
assert(root.CFrame==unchanged, 'OFF/ON must not rescue to the previous activation position')
features['Anti Void']:Toggle(false)
root=makeRoot(100);player.Character=makeCharacter(root);groundHit=true
features['Anti Void']:Toggle(true);frame('BedFightVoid')
root=makeRoot(10);player.Character=makeCharacter(root);groundHit=false;unchanged=root.CFrame;frame('BedFightVoid')
assert(root.CFrame==unchanged and lastParams.FilterDescendantsInstances[1]==player.Character,
    'respawn must not reuse the old character rescue point or raycast filter')
features['Anti Void']:Toggle(false)
-- Both scaffold variants must keep immediate edge detection without allocating filters each frame.
for _,case in ipairs({{'Scaffold','BedFightScaffold'},{'Server Scaffold','BedFightServerScaffold'}}) do
    paramsCount=0;groundHit=true;root=makeRoot(100);player.Character=makeCharacter(root)
    features[case[1]]:Toggle(true)
    for _=1,120 do frame(case[2]) end
    assert(paramsCount==1, case[1]..' must reuse raycast parameters')
    player.Character=makeCharacter(root);frame(case[2])
    assert(lastParams.FilterDescendantsInstances[1]==player.Character, case[1]..' respawn filter')
    features[case[1]]:Toggle(false)
end
Module.destroy()
assert(next(env.featureConnections)==nil, 'base-module connections cleaned')
print('PASS BedFight base: bed-drawing unload, Anti Void session/respawn isolation, scaffold raycast reuse')
'''
with tempfile.TemporaryDirectory(prefix='bedfight-base-') as tmp:
    path=Path(tmp)/'bedfight.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
