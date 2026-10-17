#!/usr/bin/env python3
"""Execute MM2 destinations and the universal dispatcher against mock services."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section
ROOT = Path(__file__).resolve().parents[1]
MM2 = (ROOT / 'src/games/MM2/Movement/Teleport.lua').read_text()
UNIVERSAL = (ROOT / 'src/games/universal/Movement/ClickTeleport.lua').read_text()
script = PRELUDE + r'''
Enum.KeyCode={Unknown='Unknown',J='J'};Enum.UserInputType={Keyboard='Keyboard'}
local cf={__add=function(a,b) return CFrame.new(a.Position+b) end}
CFrame.new=function(p) return setmetatable({Position=p},cf) end
local initial=CFrame.new(Vector3.zero)
local pivots={}
local character={Parent=true,GetPivot=function() return initial end,
 PivotTo=function(_,p) table.insert(pivots,p.Position) end,FindFirstChild=function() end}
local LocalPlayer={Character=character,FindFirstChildOfClass=function() end}
local root={CFrame=CFrame.new(Vector3.new(30,0,0))}
local target={Name='TargetGuy',Character={FindFirstChild=function() return root end}}
local Players={GetPlayers=function() return {LocalPlayer,target} end}
local mapSpawn={CFrame=CFrame.new(Vector3.new(10,0,0)),IsA=function(_,c) return c=='BasePart' end}
local lobbySpawn={CFrame=CFrame.new(Vector3.new(20,0,0))}
local drop={GetPivot=function() return CFrame.new(Vector3.new(40,0,0)) end}
local workspace={FindFirstChild=function(_,name)
 if name=='Lobby' then return {FindFirstChild=function() return {FindFirstChildWhichIsA=function() return lobbySpawn end} end} end
end}
local notices={}
local function notify(message) table.insert(notices,message) end
local callbacks={}
local featureConnections={}
local TaskManager={Connect=function(_,fn) callbacks.auto=fn;return {Disconnect=function() callbacks.auto=nil end} end}
local function disconnectFeatureConnection(key)
 if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
end
local task={spawn=function(fn) fn() end,wait=function() end}
local keyHandler
local UserInputService={GetFocusedTextBox=function() end,InputBegan={Connect=function(_,fn)
 keyHandler=fn;return {Disconnect=function() keyHandler=nil end}
end}}
local configData={values={['MM2.Teleport.GetGunkey']='J',['MM2.Teleport.Gunpickupdelay']=.2},states={}}
local tp={Options={Destination={Value='MM2 Map'}},Notify=function(_,m) notify(m) end}
local defs={}
local function option(_,d)
 local id=d.Name:gsub('%W','')
 local value=configData.values['Universal.ClickTeleport.'..id]
 if value==nil then value=d.List and d.List[d.Index] or d.Default end
 local o={Value=value};tp.Options[d.Name]=o;defs[d.Name]=d
 if d.Function then d.Function(value) end
 return o
end
tp.CreateDropdown=option;tp.CreateTextBox=option;tp.CreateBind=option;tp.CreateToggle=option;tp.CreateSlider=option
local settings={getGunKey='Unknown',autoGetGunDelay=.1}
local state={framework={GetModule=function(_,name) assert(name=='Teleport');return tp end},mm2Core={
 findDroppedGun=function() return drop end,
 findMM2Map=function() return {FindFirstChild=function() return {GetChildren=function() return {mapSpawn} end} end} end,
 mm2Settings=settings}}
'''+ '\nlocal MM2=(function()\n'+MM2+'\nend)()\n'+r'''
MM2.init({})
assert(settings.getGunKey=='J' and settings.autoGetGunDelay==.2,'preserve old custom binding and delay')
assert(not tp.Options['MM2 target'])
state.mm2TeleportRun();near(pivots[#pivots].X,10);near(pivots[#pivots].Y,3)
tp.Options.Destination.Value='MM2 Lobby';state.mm2TeleportRun();near(pivots[#pivots].X,20)
defs['Player name'].Function('target');tp.Options.Destination.Value='MM2 Player'
state.mm2TeleportRun();near(pivots[#pivots].X,30)
tp.Options.Destination.Value='MM2 Gun';local before=#pivots;state.mm2TeleportRun()
assert(#pivots==before+2);near(pivots[before+1].X,40);near(pivots[before+1].Y,2);near(pivots[#pivots].X,0)
defs['Auto Get Gun'].Function(true);assert(callbacks.auto)
callbacks.auto(.5);near(pivots[#pivots-1].X,40)
defs['Auto Get Gun'].Function(false);assert(not callbacks.auto)
local function characterRoot() error('MM2 route must not run the universal travel setup') end
local Module={}
'''+section(UNIVERSAL,'function Module.run(', 'function Module.destroy(')+r'''
local context={host={state=state}}
local previous=#pivots;Module.run(context,tp,{})
assert(#pivots==previous+2,'universal action dispatches to the selected MM2 destination')
MM2.destroy();assert(not state.mm2TeleportRun and not keyHandler and not callbacks.auto)
Module.run(context,tp,{});assert(notices[#notices]=='MM2 destinations are not ready')
print('PASS Teleport: one dispatcher; Map/Lobby/Player/Gun, auto pickup, custom key/delay migration, unload')
'''
with tempfile.TemporaryDirectory(prefix='teleport-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
