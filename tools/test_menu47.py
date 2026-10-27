#!/usr/bin/env python3
"""Actual merged controllers / saved markers. Deterministic mocks, not a live game."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
def source(path): return '(function()\n'+(ROOT/path).read_text()+'\nend)()'
script=PRELUDE+r'''
local Color3={fromRGB=function(r,g,b) return {r,g,b} end}
local Vector2={new=function(x,y) return {X=x,Y=y} end}
local game={PlaceId=123}
Enum.KeyCode={Escape='Escape'};Enum.UserInputType={MouseButton1='MouseButton1',Touch='Touch'}
local RaycastParams={new=function() return {} end}
local inputCallback
local input={InputBegan={Connect=function(_,fn) inputCallback=fn;return {Disconnect=function() inputCallback=nil end} end},GetFocusedTextBox=function() return nil end}

local cards={}
local function option(self,d)
 local o={Value=d.Default,definition=d}
 function o:Set(v) self.Value=v;if d.Function then d.Function(v) end end
 self.Options[d.Name]=o;return o
end
local function makeCard(d)
 local c={Options={},cleanups={},Enabled=false,notifications={}}
 c.CreateToggle=option;c.CreateSlider=option;c.CreateTextBox=option;c.CreateColor=option;c.CreateButton=option
 function c:CreateList(d)
  local o={selected={},definition=d}
  for _,name in ipairs(d.Default or {}) do o.selected[name]=true end
  function o:Refresh() self.names=d.Items() end
  function o:Set(name,on) self.selected[name]=on end
  function o:IsSelected(name) return self.selected[name]==true end
  o:Refresh();self.Options[d.Name]=o;return o
 end
 function c:Clean(item) table.insert(self.cleanups,item) end
 function c:Render(fn) self.frame=fn end
 function c:Loop(fn) self.loop=fn end
 function c:SetStatus(text) self.status=text end
 function c:Notify(text) table.insert(self.notifications,text) end
 function c:Toggle(v)
  self.Enabled=v
  if not v then for _,fn in ipairs(self.cleanups) do fn() end;table.clear(self.cleanups);self.frame=nil;self.loop=nil end
  d.Function(v)
 end
 cards[d.Name]=c;return c
end
local framework={Categories={Render={CreateModule=function(_,d) return makeCard(d) end}}}
local render={}
function render:Layer() return {items={},Visible=false} end
function render:ReleaseAll(layer) table.clear(layer.items) end
function render:Release(layer,name) layer.items[name]=nil end
function render:Project(_,p) return p.Z>0 and p or nil end
function render:Set(layer,name)
 local drawing=layer.items[name] or {}
 function drawing:Show() end
 function drawing:Label(_,text) self.text=text end
 layer.items[name]=drawing;return drawing
end
local root={Position=Vector3.new(10,20,30)}
local player={Character={FindFirstChild=function() return root end}}
local config={values={}}
local saves=0
local world={CurrentCamera={ViewportSize={X=1000,Y=1000},CFrame={Position=Vector3.zero}}}
local host={UserInputService=input,LocalPlayer=player,workspace=world,configData=config,queueConfigSave=function() saves+=1 end}
local menuVisible=true
local menu={isVisible=function() return menuVisible end,setVisible=function(v) menuVisible=v end}
local context={host=host,framework=framework,render=render,services={menu=menu}}
'''+ '\nlocal Markers='+source('src/games/universal/Render/Markers.lua')+r'''
local markers=Markers.init(context)
local function press(card,name) card.Options[name].definition.Function() end
press(markers,'Save here');assert(#markers.notifications==0)
markers.Options.Name:Set('Home');press(markers,'Save here');assert(saves==2 and markers.Options.Point:IsSelected('Home'))
local data=config.values['Universal.Markers.Places.123'];assert(data['Home'][1]==10 and data['Home'][2]==20 and data['Home'][3]==30)
markers:Toggle(true);markers.frame();assert(markers.Options.Point.names[1]=='Home')
markers.Options['Manual coordinates']:Set(true);markers.Options.Coordinates:Set('1, 2, 3');markers.Options.Name:Set('Exit');press(markers,'Save coordinates');assert(data['Exit'][3]==3)
markers.Options.Coordinates:Set('NaN, 1, 2');press(markers,'Save coordinates');assert(data['Exit'][1]==1 and #markers.notifications==1)
local raycasts=0
world.CurrentCamera.ScreenPointToRay=function(_,x,y) return {Origin=Vector3.zero,Direction=Vector3.new(0,0,1)} end
world.Raycast=function(_,origin,delta,params) raycasts+=1;assert(params.RespectCanCollide);return {Position=Vector3.new(7,8,9)} end
markers.Options.Name:Set('Touch spot');press(markers,'Touch');assert(not menuVisible)
inputCallback({UserInputType='MouseButton1',Position=Vector3.new(30,40,0)},true);assert(raycasts==0,'UI input must not place a marker')
inputCallback({UserInputType='Touch',Position=Vector3.new(30,40,0)},false);assert(data['Touch spot #1'][3]==9 and menuVisible)
press(markers,'Touch');inputCallback({UserInputType='MouseButton1',Position=Vector3.zero},false)
assert(data['Touch spot #2'] and data['Touch spot #1'])
markers.Options.Name:Set('');press(markers,'Touch');inputCallback({UserInputType='Touch',Position=Vector3.zero},false)
press(markers,'Touch');inputCallback({UserInputType='Touch',Position=Vector3.zero},false)
assert(data['Point 1'] and data['Point 2'] and markers.Options.Name.Value=='')
press(markers,'Touch');inputCallback({KeyCode='Escape'},false);assert(raycasts==4 and menuVisible)
-- Starting while already hidden must not reopen the menu.
menuVisible=false;press(markers,'Touch');inputCallback({KeyCode='Escape'},false);assert(not menuVisible)
menuVisible=true
markers:Toggle(false);Markers.destroy()
markers=Markers.init(context);assert(markers.Options.Point:IsSelected('Home'),'points/selection survive reload')
markers.Options.Point.definition.OnRemove('Home');data=config.values['Universal.Markers.Places.123'];assert(not data['Home'] and data['Exit'])
Markers.destroy();game.PlaceId=456;markers=Markers.init(context);assert(#markers.Options.Point.names==0,'no cross-game coordinate leakage');Markers.destroy()
config.values['Universal.Markers.Places.456']='bad data';markers=Markers.init(context);assert(#markers.Options.Point.names==0);Markers.destroy()
pass('Markers: save by name/current position, optional parsed coordinates, invalid inputs, persistence, remove, per-place separation and malformed config')
local lighting={Brightness=2,ClockTime=7,GlobalShadows=true,FogEnd=900,Ambient='original',OutdoorAmbient='outside'}
host.Lighting=lighting
'''+ '\nlocal Fullbright='+source('src/games/universal/Render/Fullbright.lua')+r'''
local bright=Fullbright.init(context);bright:Toggle(true)
assert(lighting.Brightness==3 and lighting.ClockTime==7,'brightness alone must not change time')
bright.Options['Time Changer']:Set(true);bright.loop(0);assert(lighting.ClockTime==14)
bright.Options['Fast time']:Set(true);bright.loop(2);near(lighting.ClockTime,12)
bright.Options['Time Changer']:Set(false);assert(lighting.ClockTime==7)
bright.Options['Fast time']:Set(false);bright.Options['Time Changer']:Set(true);bright.loop(0)
lighting.ClockTime=18;bright.loop(0);assert(lighting.ClockTime==14)
lighting.Brightness=4;bright:Toggle(false)
assert(lighting.ClockTime==18 and lighting.Brightness==4 and lighting.GlobalShadows and lighting.Ambient=='original' and lighting.FogEnd==900)
Fullbright.destroy();pass('Fullbright: optional time, fast cycle, immediate suboption restoration, external updates and owned-only cleanup')
'''
# Exercise the actual notification helper, not a copy of the filter.
disguise=(ROOT/'src/games/universal/Other/Disguise.lua').read_text()
a=disguise.index('    local function status(message:');b=disguise.index('    local function isAppearanceItem',a)
script+='\nlocal activeCard={count=0,SetStatus=function(self,s) self.status=s end,Notify=function(self,s) self.count+=1 end}\n'+disguise[a:b]+r'''
status('Ready');assert(activeCard.count==0 and activeCard.status=='Ready')
notify('Could not load avatar');assert(activeCard.count==1)
pass('Disguise: routine readiness is status; actual failures remain notifications')
'''
manifest=(ROOT/'src/libraries/Manifest.lua').read_text()
assert 'universal/Blatant/Fling.lua' not in manifest and 'TimeChanger.lua' not in manifest
assert 'universal/Movement/AntiFling.lua' in manifest, 'Anti Fling is its own card since v138.2'
assert 'universal/Blatant/WalkFling.lua' in manifest, 'Walk Fling is its own card since v138.2'
cards_source=(ROOT/'src/guis/Wurst/Code/Cards.lua').read_text()
assert 'notify(name .. " ran")' not in cards_source and 'notify(name .. (requestedState' not in cards_source
assert 'notify("Could not toggle "' in cards_source and 'notify("Could not run "' in cards_source
assert 'Spiderman' not in (ROOT/'src/games/universal/Blatant/Spider.lua').read_text()
with tempfile.TemporaryDirectory() as t:
 p=Path(t)/'menu.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
