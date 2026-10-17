#!/usr/bin/env python3
"""Execute actual Aim Assist: turn-rate, strength, frame-rate and camera-owner checks."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
script = PRELUDE + r'''
local function frame(position,look)
 local right=Vector3.new(-look.Z,0,look.X)
 if right.Magnitude<1e-6 then right=Vector3.new(1,0,0) end
 return {Position=position,LookVector=look.Unit,RightVector=right.Unit}
end
CFrame.lookAt=function(p,q) return frame(p,(q-p).Unit) end
local camera={CFrame=frame(Vector3.new(3,4,5),Vector3.new(0,0,-1))}
local selected={position=Vector3.new(103,4,5),distance=100,entity={Name='Target'},character={Name='Target'}}
local visible,capturing,focused,free,spectating,adapter=false,false,false,false,false,false
local received
local targeting={List=function(_,_,options) received=options;return {selected} end}
local card
local function option(self,d)
 local o={Value=d.Default,definition=d};if d.List then o.Value=d.List[d.Index or 1] end
 self.Options[d.Name]=o;return o
end
local framework={Categories={Combat={CreateModule=function(_,d)
 card={Options={},cleanups={}}
 card.CreateSlider=option;card.CreateDropdown=option;card.CreateToggle=option
 function card:CreateNote() end
 function card:SetStatus(s) self.status=s end
 function card:Render(fn) self.frame=fn end
 function card:Clean(fn) table.insert(self.cleanups,fn) end
 function card:Toggle(on)
  self.Enabled=on
  if not on then for _,fn in ipairs(self.cleanups) do fn() end;table.clear(self.cleanups);self.frame=nil end
  d.Function(on)
 end
 return card
end}}}
local services={menu={isVisible=function() return visible end,isCapturingInput=function() return capturing end},
 activity={isActive=function() return adapter end},freeCam={IsActive=function() return free end},spectate={IsActive=function() return spectating end}}
local host={workspace={CurrentCamera=camera},UserInputService={GetFocusedTextBox=function() return focused end}}
''' + '\nlocal Module=(function()\n' + (ROOT/'src/games/universal/Combat/AimAssist.lua').read_text() + '\nend)()\n' + r'''
local aim=Module.init({host=host,services=services,libraries={targeting=targeting},framework=framework,entity={}})
assert(not aim.Options.Smoothing and aim.Options.Speed and aim.Options.Strength)
aim:Toggle(true)
local initial=camera.CFrame
local function reset() camera.CFrame=initial end
local function turned() return math.acos(math.clamp(initial.LookVector:Dot(camera.CFrame.LookVector),-1,1)) end
aim.Options.Speed.Value=10;aim.Options.Strength.Value=1000;aim.frame(1)
near(turned(),math.rad(10));near((camera.CFrame.Position-initial.Position).Magnitude,0)
assert(received.VisibilityCheck and received.TeamCheck and received.FOV==180)
reset();aim.Options.Speed.Value=0;aim.frame(.02);assert(camera.CFrame==initial)
aim.Options.Speed.Value=180;aim.Options.Strength.Value=0;aim.frame(.02);assert(camera.CFrame==initial)
aim.Options.Strength.Value=100;aim.frame(.05);local strong=turned()
reset();aim.Options.Strength.Value=10;aim.frame(.05);assert(turned()<strong)
-- Exact time-based pull when the speed cap is not binding.
local expected=math.pi/2*(1-math.exp(-5))
for _,fps in ipairs({30,60,144}) do
 reset();aim.Options.Speed.Value=5000;aim.Options.Strength.Value=50
 for _=1,fps do aim.frame(1/fps) end
 near(turned(),expected,1e-7)
end
reset();selected.position=initial.Position+Vector3.new(0,0,100)
aim.Options.Speed.Value=10;aim.Options.Strength.Value=1000;aim.frame(1)
near(turned(),math.rad(10)) -- opposite directions must not produce a zero vector
selected.position=Vector3.new(103,4,5)
aim.Options.Mode.Value='Aimbot';aim.Options.Speed.Value=0;aim.Options.Strength.Value=0
reset();aim.frame(.02);near(turned(),math.pi/2);assert(received.AllowOffscreen and received.FOV==nil)
aim.Options.Mode.Value='Aim Assist';aim.Options.Speed.Value=180;aim.Options.Strength.Value=75
for _,blocked in ipairs({'visible','capturing','focused','free','spectating','adapter'}) do
 reset();visible=blocked=='visible';capturing=blocked=='capturing';focused=blocked=='focused';free=blocked=='free';spectating=blocked=='spectating';adapter=blocked=='adapter'
 aim.frame(.1);assert(camera.CFrame==initial,blocked..' must pause the assist')
end
Module.destroy();assert(not aim.Enabled and aim.frame==nil)
pass('Aim Assist actual source: Speed cap, Strength, zero, 30/60/144 FPS, huge values, opposite vectors, Aimbot, targeting filters, camera/UI arbitration and cleanup')
'''
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp)/'aimassist.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
