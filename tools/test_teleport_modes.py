#!/usr/bin/env python3
"""Execute MM2 destinations and immediate gun pickup against mock services."""
import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
MM2 = (ROOT / "src/games/MM2/Movement/Teleport.lua").read_text()
UNIVERSAL = (ROOT / "src/games/universal/Movement/ClickTeleport.lua").read_text()

assert "Gun pickup delay" not in MM2
assert "Gun pickup delay" not in UNIVERSAL
assert "autoGetGunDelay" not in MM2
assert "task.wait" not in MM2
grab = section(MM2, "    local function grabDroppedGun()", "    local teleport =")
assert "PivotTo" not in grab and "touchDroppedGun(gunDrop)" in grab

script = PRELUDE + r'''
Enum.KeyCode={Unknown='Unknown',J='J'};Enum.UserInputType={Keyboard='Keyboard'}
local cf={__add=function(a,b) return CFrame.new(a.Position+b) end}
CFrame.new=function(p) return setmetatable({Position=p},cf) end
local initial=CFrame.new(Vector3.zero)
local pivots={}
local touches=0
local hasGun=false
local rootPart={Name='HumanoidRootPart',IsA=function(_,class) return class=='BasePart' end}
local gunTool={Name='Gun'}
local character={Parent=true,GetPivot=function() return initial end,
 PivotTo=function(_,p) table.insert(pivots,p.Position) end}
function character:FindFirstChild(name)
 if name=='HumanoidRootPart' then return rootPart end
 if name=='Gun' and hasGun then return gunTool end
 return nil
end
local LocalPlayer={Character=character,FindFirstChildOfClass=function() end}
local root={CFrame=CFrame.new(Vector3.new(30,0,0))}
local target={Name='TargetGuy',Character={FindFirstChild=function() return root end}}
local Players={GetPlayers=function() return {LocalPlayer,target} end}
local function node(name,class,children)
 local object={Name=name,ClassName=class,children=children or {}}
 function object:IsA(wanted)
  return self.ClassName==wanted or (wanted=='BasePart' and (self.ClassName=='Part' or self.ClassName=='SpawnLocation'))
 end
 function object:GetChildren() return self.children end
 function object:FindFirstChild(wanted,recursive)
  for _,child in ipairs(self.children) do if child.Name==wanted then return child end end
  if recursive then for _,child in ipairs(self.children) do local found=child:FindFirstChild(wanted,true);if found then return found end end end
 end
 function object:FindFirstChildWhichIsA(wanted,recursive)
  for _,child in ipairs(self.children) do if child:IsA(wanted) then return child end end
  if recursive then for _,child in ipairs(self.children) do local found=child:FindFirstChildWhichIsA(wanted,true);if found then return found end end end
 end
 return object
end
local mapSpawn=node('Spawn','Part');mapSpawn.CFrame=CFrame.new(Vector3.new(10,0,0))
local lobbySpawn=node('Spawn','SpawnLocation');lobbySpawn.CFrame=CFrame.new(Vector3.new(20,0,0))
local spawns=node('Spawns','Folder',{mapSpawn})
local map=node('Map','Model',{spawns})
local lobby=node('Lobby','Model',{node('Spawns','Folder',{lobbySpawn})})
local workspace=node('Workspace','Workspace',{lobby})
local drop={IsA=function(_,className) return className=='BasePart' end,
 GetPivot=function() error('instant gun pickup must not read a teleport destination') end}
local notices={}
local function notify(message) table.insert(notices,message) end
local callbacks={}
local featureConnections={}
local TaskManager={Connect=function(_,fn) callbacks.auto=fn;return {Disconnect=function() callbacks.auto=nil end} end}
local function disconnectFeatureConnection(key)
 if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
end
local task={spawn=function(fn) fn() end,wait=function() error('gun pickup must never wait') end}
local keyHandler
local UserInputService={GetFocusedTextBox=function() end,InputBegan={Connect=function(_,fn)
 keyHandler=fn;return {Disconnect=function() keyHandler=nil end}
end}}
-- Old configs may still contain the removed delay. It must simply be ignored.
local configData={values={['MM2.Teleport.GetGunkey']='J',['MM2.Teleport.Gunpickupdelay']=.2},states={}}
local tp={Options={Destination={Value='MM2'}},Notify=function(_,m) notify(m) end}
local defs={}
local function option(_,d)
 local id=d.Name:gsub('%W','')
 local value=configData.values['Universal.ClickTeleport.'..id]
 if value==nil then value=d.List and d.List[d.Index] or d.Default end
 local o={Value=value};tp.Options[d.Name]=o;defs[d.Name]=d
 if d.Function then d.Function(value) end
 return o
end
tp.CreateButton=function(_,d) defs[d.Name]=d;tp.Options[d.Name]={Value=nil} end
tp.CreateDropdown=option;tp.CreateTextBox=option;tp.CreateBind=option;tp.CreateToggle=option;tp.CreateSlider=option
local settings={getGunKey='Unknown'}
local role='Innocent'
local roundActive=true
local activeMap=map
local state={fireTouchInterest=function(first,second,toggle)
 assert(first==rootPart and second==drop)
 touches+=1
 if toggle==1 then hasGun=true end
end,
 framework={GetModule=function(_,name) assert(name=='Teleport');return tp end},mm2Core={
 findDroppedGun=function() return drop end,
 getPlayerRole=function() return role end,
 isRoundLifecycleActive=function() return roundActive end,
 findMM2Map=function() return activeMap end,
 mm2Settings=settings}}
''' + "\nlocal MM2=(function()\n" + MM2 + "\nend)()\n" + r'''
MM2.init({})
assert(settings.getGunKey=='J','preserve the old custom binding')
assert(defs['Gun pickup delay']==nil and tp.Options['Gun pickup delay']==nil,
 'the pickup delay control and its persisted option are gone')
assert(not tp.Options['MM2 target'])
assert(not state.mm2TeleportRun, 'no second MM2 dispatcher')
defs['Teleport to Map'].Function();near(pivots[#pivots].X,10);near(pivots[#pivots].Y,3)
defs['Teleport to Lobby'].Function();near(pivots[#pivots].X,20)
defs['Player name'].Function('target');defs['Teleport to Player'].Function();near(pivots[#pivots].X,30)
local nested=node('NestedSpawn','Part');nested.CFrame=CFrame.new(Vector3.new(11,0,0))
spawns.children={node('Container','Model',{nested})}
defs['Teleport to Map'].Function();near(pivots[#pivots].X,11)
local mapFallback=node('Fallback','Part');mapFallback.CFrame=CFrame.new(Vector3.new(12,0,0))
spawns.children={};map.children={spawns,mapFallback}
defs['Teleport to Map'].Function();near(pivots[#pivots].X,12)
map.children={spawns}
local count=#pivots;defs['Teleport to Map'].Function()
assert(#pivots==count and notices[#notices]=='No active MM2 map spawn was found.')
activeMap=nil;defs['Teleport to Map'].Function()
assert(#pivots==count and notices[#notices]=='No active MM2 map was found.')
activeMap=map;spawns.children={mapSpawn}
local pad=node('Pad','Part');pad.CFrame=CFrame.new(Vector3.new(21,0,0))
workspace.children={node('Area','Model',{node('VotePads','Folder',{pad})})}
defs['Teleport to Lobby'].Function();near(pivots[#pivots].X,21)
local worldSpawn=node('Spawn','SpawnLocation');worldSpawn.CFrame=CFrame.new(Vector3.new(22,0,0))
workspace.children={node('Spawns','Folder',{worldSpawn})}
defs['Teleport to Lobby'].Function();near(pivots[#pivots].X,22)
workspace.children={};count=#pivots;defs['Teleport to Lobby'].Function()
assert(#pivots==count and notices[#notices]=='The MM2 lobby spawn was not found.')
workspace.children={lobby}

local before=#pivots
hasGun=false;touches=0
defs['Get Gun'].Function()
assert(touches==2 and hasGun,'manual Get Gun pulses touch and confirms immediately')
assert(#pivots==before,'manual Get Gun never teleports away or back')
pass('MM2 Get Gun: immediate touch pickup, no delay and no travel')

for name,d in pairs(defs) do assert(d.Show.Option=='Destination' and #d.Show.Values==1 and d.Show.Values[1]=='MM2',name..' is grouped under the sole MM2 entry') end
hasGun=false;touches=0;before=#pivots
defs['Auto Get Gun'].Function(true)
assert(callbacks.auto and touches==2 and hasGun,'enabling Auto Get Gun picks up in the same frame')
assert(#pivots==before,'Auto Get Gun never pivots the character')
callbacks.auto(.5)
assert(touches==2,'an owned gun is not touched again')
hasGun=false
callbacks.auto(.5)
assert(touches==4 and hasGun,'a later Heartbeat retries without a delay')
assert(#pivots==before)
hasGun=false
for _, blockedRole in ipairs({'Murderer','Sheriff','Unknown'}) do
 role=blockedRole; callbacks.auto(.5)
 assert(touches==4,'Auto Get Gun must not touch for role '..blockedRole)
end
role='Innocent';roundActive=false;callbacks.auto(.5)
assert(touches==4,'Auto Get Gun must not run outside the round')
roundActive=true
local savedMap=activeMap;activeMap=nil;callbacks.auto(.5)
assert(touches==4,'Auto Get Gun must not run in the lobby without a map')
activeMap=savedMap
callbacks.auto(.5);assert(touches==6 and hasGun,'pickup resumes when role, round and map are valid')
defs['Auto Get Gun'].Function(false);assert(not callbacks.auto)
pass('MM2 Auto Get Gun: immediate retry, role/round/lobby gates and no teleport')

local function characterRoot() error('MM2 route must not run the universal travel setup') end
local Module={}
''' + section(UNIVERSAL, "function Module.run(", "function Module.destroy(") + r'''
local context={host={state=state}}
local previous=#pivots;Module.run(context,tp,{})
assert(#pivots==previous and notices[#notices]=='Choose a MM2 teleport button below','MM2 actions belong together, not in another selector')
MM2.destroy();assert(not state.mm2TeleportRun and not keyHandler and not callbacks.auto)
Module.run(context,tp,{});assert(notices[#notices]=='Choose a MM2 teleport button below')
print('PASS Teleport: destinations, instant manual/auto gun pickup, no delay option, unload')
'''

with tempfile.TemporaryDirectory(prefix="teleport-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
