#!/usr/bin/env python3
"""Execute the actual dock-placement controller: mouse/touch, clamping, save/cancel and cleanup."""
import os,subprocess,tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/guis/Wurst/Code/Furniture.lua').read_text()
a=SOURCE.index('    local moving = false')
b=SOURCE.index('    local function restyleMenuButton',a)
script=PRELUDE+r'''
local Vector2={new=function(x,y) return Vector3.new(x,y,0) end}
local UDim2={fromScale=function(x,y) return {X={Scale=x,Offset=0},Y={Scale=y,Offset=0}} end,
 new=function(xs,xo,ys,yo) return {X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}} end,
 fromOffset=function(x,y) return {X={Scale=0,Offset=x},Y={Scale=0,Offset=y}} end}
Enum.UserInputType={MouseButton1='MouseButton1',MouseMovement='MouseMovement',Touch='Touch'}
Enum.KeyCode={Escape='Escape',Return='Return'}
local function signal()
 local s={listeners={}}
 function s:Connect(fn) self.listeners[fn]=true;return {Disconnect=function() self.listeners[fn]=nil end} end
 function s:Fire(...) for fn in pairs(self.listeners) do fn(...) end end
 function s:Count() local n=0;for _ in pairs(self.listeners) do n+=1 end;return n end
 return s
end
local function create(class,properties)
 local o=properties or {};o.ClassName=class;o.children={};o.InputBegan=signal()
 function o:Destroy() self.Parent=nil;self.destroyed=true end
 function o:FindFirstChild(name) for _,c in ipairs(self.children) do if c.Name==name and c.Parent==self then return c end end end
 if o.Parent then table.insert(o.Parent.children,o) end
 return o
end
local function controller(saved)
 local task={defer=function(fn) fn() end}
 local ScreenGui={AbsoluteSize=Vector2.new(1000,700),children={}}
 local resized=signal();function ScreenGui:GetPropertyChangedSignal() return resized end
 local pillFrame=create('Frame',{Parent=ScreenGui,Position=UDim2.fromScale(.5,.9),AbsoluteSize=Vector2.new(300,42),AbsolutePosition=Vector2.new(350,600),Visible=false})
 local state={uiShowDock=false,dock={root=pillFrame},listeners={}}
 function state.addMenuVisibilityListener(fn) table.insert(state.listeners,fn) end
 local configData={ui={dockPosition=saved}}
 local savedCount=0
 local function queueConfigSave() savedCount+=1 end
 local function setDockVisible(v) pillFrame.Visible=v end
 local Furniture={connections={}}
 local UserInputService={InputBegan=signal(),InputChanged=signal(),InputEnded=signal(),WindowFocusReleased=signal()}
 local CONTROL_FONT='Code';local Theme={text='white',surface='black'}
 local pillWidth,PILL_BUTTON,PILL_PADDING_Y=300,32,5
'''+SOURCE[a:b]+r'''
 return state,UserInputService,pillFrame,configData,resized,ScreenGui,function()
  finishDockMove(false);for _,c in ipairs(Furniture.connections) do c:Disconnect() end
 end
end
local state,input,root,config,resized,screen,destroy=controller()
assert(not root.Visible)
state.dock.BeginMove();assert(root.Visible and root:FindFirstChild('DockMoveHandle'))
local press={UserInputType='MouseButton1',Position=Vector3.new(400,610,0)}
root:FindFirstChild('DockMoveHandle').InputBegan:Fire(press)
input.InputChanged:Fire({UserInputType='MouseMovement',Position=Vector3.new(600,510,0)})
near(root.Position.X.Scale,.7);near(root.Position.Y.Scale,542/700)
input.InputEnded:Fire(press)
near(config.ui.dockPosition.x,.7);assert(not root.Visible and not root:FindFirstChild('DockMoveHandle'))
for _,s in pairs(input) do assert(s:Count()==0,'no placement input listeners left after drop') end
local before=root.Position
state.dock.BeginMove();input.InputBegan:Fire({KeyCode='Escape'});assert(root.Position==before and not root.Visible)
state.dock.BeginMove();input.WindowFocusReleased:Fire();assert(not root:FindFirstChild('DockMoveHandle'))
state.dock.BeginMove();state.listeners[1](false);assert(not root:FindFirstChild('DockMoveHandle'))
state.dock.BeginMove();local finger={UserInputType='Touch',Position=Vector3.new(1,2,0)}
root:FindFirstChild('DockMoveHandle').InputBegan:Fire(finger)
finger.Position=Vector3.new(10000,10000,0);input.InputChanged:Fire(finger);input.InputEnded:Fire(finger)
near(root.Position.X.Scale,.85);near(root.Position.Y.Scale,1)
state.dock.BeginMove();input.InputBegan:Fire({KeyCode='Return'});assert(not root.Visible)
state.dock.BeginMove();destroy();for _,s in pairs(input) do assert(s:Count()==0) end;assert(resized:Count()==0)
local again,_,restored,cfg,resize,canvas,unload=controller({x=.3,y=.4})
near(restored.Position.X.Scale,.3);near(restored.Position.Y.Scale,.4)
canvas.AbsoluteSize=Vector2.new(500,350);resize:Fire();near(restored.Position.X.Scale,.3);near(restored.Position.Y.Scale,.4)
unload()
pass('Dock actual controller: mouse/touch drop, bounds, save/reload, resize, Escape, Enter, focus/menu cancellation, temporary visibility and cleanup')
'''
settings=(ROOT/'src/guis/Wurst/Code/SettingsPage.lua').read_text()
assert 'addToggleOption(uiPanel, "Show dock", false,' in settings
assert 'host.addActionOption(uiPanel, "Move dock"' in settings
with tempfile.TemporaryDirectory() as t:
 p=Path(t)/'dock.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
