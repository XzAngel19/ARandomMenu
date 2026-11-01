#!/usr/bin/env python3
"""Exercise NPCESP's real name-entry, scanning and cleanup using mock Instances.

The mocks do not simulate Roblox rendering or streaming timing.
"""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
import audit_menu

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Render/NPCESP.lua').read_text()
script = PRELUDE + r'''
local Vector2={new=function(x,y) return {X=x,Y=y} end}
local Color3={fromRGB=function() return {} end}
local function typeof(v) return type(v)=='table' and v.ClassName and 'Instance' or type(v) end
local function signal()
 local listeners={};local s={}
 function s:Connect(fn)
  local c={Connected=true};listeners[c]=fn
  function c:Disconnect() self.Connected=false;listeners[self]=nil end
  return c
 end
 function s:Fire(...) for c,fn in pairs(table.clone(listeners)) do if c.Connected then fn(...) end end end
 function s:Count() local n=0;for _ in pairs(listeners) do n+=1 end;return n end
 return s
end
local world={DescendantAdded=signal(),DescendantRemoving=signal(),CurrentCamera={CFrame={Position=Vector3.zero}}}
function world:IsA(class) return class=='Workspace' end
function world:FindFirstAncestorOfClass() return nil end
local model={Name='CreatorStatue',Parent=world}
local root={Name='HumanoidRootPart',Parent=model,Position=Vector3.new(10,0,0)}
function root:IsA(class) return class=='BasePart' end
function model:IsA(class) return class=='Model' end
function model:GetAttribute() return nil end
function model:GetChildren() return {root} end
function model:FindFirstChild(name) if name=='HumanoidRootPart' then return root end end
function model:FindFirstChildOfClass() return nil end
function model:FindFirstChildWhichIsA(class) if class=='BasePart' then return root end end
function model:IsDescendantOf(other) return other==world end
function world:GetDescendants() return {model} end
local active={};local layer={Visible=false}
local drawing={Box=function() end,Label=function() end,Highlight=function() end,
 HideLabel=function() end,Show=function() end}
local render={}
function render:Layer() return layer end
function render:Set(_,target) active[target]=true;return drawing end
function render:Release(_,target) active[target]=nil end
function render:ReleaseAll() table.clear(active) end
function render:ModelRect() return {centreX=10,top=10} end
local players={GetPlayerFromCharacter=function() return nil end,GetPlayers=function() return {} end}
local host={Players=players,LocalPlayer={Character=nil},workspace=world}
local savedText='LegacyName' -- callback runs before CreateTextBox returns
local card
local function option(self,def)
 local o={Value=def.Default}
 self.Options[def.Name]=o
 return o
end
local framework={Categories={Visuals={CreateModule=function(_,def)
 card={Options={},Enabled=false,cleanups={}}
 card.CreateToggle=option;card.CreateColor=option;card.CreateSlider=option
 function card:CreateTextBox(d)
  local box={ClassName='TextBox',Text=savedText,FocusLost=signal()}
  function box:IsA(class) return class=='TextBox' end
  local o={Object=box,Value=savedText,callback=d.Function}
  function o:Set(value) self.Value=value;self.Object.Text=value;self.callback(value) end
  d.Function(savedText) -- Widgets invokes the callback during construction
  self.Options[d.Name]=o
  return o
 end
 function card:CreateButton(d) local o={click=d.Function};self.Options[d.Name]=o;return o end
 function card:Event(sig,fn) self:Clean(sig:Connect(fn)) end
 function card:Clean(item) table.insert(self.cleanups,item) end
 function card:Render(fn) self.render=fn end
 function card:SetStatus(s) self.Status=s end
 function card:Toggle(v)
  self.Enabled=v
  if not v then
   for _,item in ipairs(self.cleanups) do if type(item)=='function' then item() else item:Disconnect() end end
   table.clear(self.cleanups);self.render=nil
  end
  def.Function(v)
 end
 return card
end}}}
''' + '\nlocal Module=(function()\n' + SOURCE + '\nend)()\n' + r'''
Module.init({host=host,framework=framework,render=render})
local input=card.Options['Force by name']
assert(input and card.Options['Clear forced names'], 'saved text must not abort module construction')
card:Toggle(true);card.render();assert(not active[model], 'an unrelated saved name must not match the statue')
-- Typing is not submission: do not add the first character or clear the box.
for _,value in ipairs({'C','Cr','CreatorStatue'}) do
 input.Object.Text=value;input.callback(value)
 assert(input.Object.Text==value, 'typing must not clear the text box')
 card.render();assert(not active[model], 'partial input must not become a forced name')
end
input.Object.FocusLost:Fire(true);card.render()
assert(input.Object.Text=='' and active[model], 'Enter must submit the whole name')
card.Options['Clear forced names'].click();card.render()
assert(not active[model], 'clearing names must remove drawings from a prior scan')
-- Mobile may submit without a keyboard/Enter.
input.Object.Text='statue';input.callback('statue')
card.Options['Add forced name'].click();card.render()
assert(input.Object.Text=='' and active[model], 'the add button submits the whole name')
local focus=input.Object.FocusLost
assert(focus:Count()==1)
Module.destroy()
assert(not card.Enabled and not layer.Visible and not active[model] and focus:Count()==0,
 'unload must release drawings, workspace listeners and input connection')
print('PASS NPCESP: saved text, full-name Enter/mobile submission, clear/rescan, and cleanup')
'''

with tempfile.TemporaryDirectory(prefix='npc-esp-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)

    # Also boot the real Framework/Widgets/bundle with a previously saved
    # nonempty input; that builder invokes callbacks before returning controls.
    boot = audit_menu.build(debug=True).read_text()
    original = 'values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000 },'
    replacement = 'values = { ["ClickGUI.Arrows"] = {255, 255, 255}, ["Universal.Speed.Speed"] = 5000, ["Universal.NPCESP.Forcebyname"] = "LegacyName" },'
    assert boot.count(original) == 1
    boot = boot.replace(original, replacement, 1) + r'''
local npc=ex.state.framework:GetModule('NPCESP')
local input=npc and npc.Options['Force by name']
assert(input and npc.Options['Add forced name'] and npc.Options['Clear forced names'],
 'saved nonempty input must not stop NPCESP boot')
input.Object.Text='CreatorStatue'
input.Object:GetPropertyChangedSignal('Text'):Fire()
assert(input.Value=='CreatorStatue' and input.Object.Text=='CreatorStatue')
input.Object.FocusLost:Fire(true)
assert(input.Value=='' and input.Object.Text=='', 'Enter submits and clears the full value')
print('PASS NPCESP real Framework/Widgets saved input and Enter')
'''
    path.write_text(boot)
    result = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], text=True, capture_output=True)
    if result.returncode or 'Load complete · failures=0' not in result.stdout:
        raise SystemExit(result.stdout[-5000:] + '\n' + result.stderr)
    assert 'PASS NPCESP real Framework/Widgets saved input and Enter' in result.stdout
    print('PASS NPCESP real Framework/Widgets: saved input and Enter')
