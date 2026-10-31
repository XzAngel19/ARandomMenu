#!/usr/bin/env python3
"""Run the real AirWalk source with native-style PC/touch signals and lifecycle mocks."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Movement/AirWalk.lua").read_text()

script = r'''
local Vector3 = {}
function Vector3.new(x,y,z) return {X=x,Y=y,Z=z} end
local CFrame = {new = function(x,y,z) return {Position=Vector3.new(x,y,z)} end}
local UDim2 = {new=function(...) return {...} end,
    fromScale=function(...) return {...} end, fromOffset=function(...) return {...} end}
local Color3 = {new=function(...) return {...} end, fromRGB=function(...) return {...} end}
local Enum = {UserInputType={Keyboard="Keyboard",Touch="Touch",MouseButton1="MouseButton1"},
    KeyCode={Space="Space",LeftShift="LeftShift",RightShift="RightShift"}, Font={Code="Code"}}
local function signal()
    local callbacks = {}
    local event = {}
    function event:Connect(callback)
        local connection = {}
        callbacks[connection] = callback
        function connection:Disconnect() callbacks[self] = nil end
        return connection
    end
    function event:Fire(...)
        local items = {}
        for _, callback in pairs(callbacks) do table.insert(items, callback) end
        for _, callback in ipairs(items) do callback(...) end
    end
    function event:Count() local n=0; for _ in pairs(callbacks) do n+=1 end; return n end
    return event
end
local world = {Name="Workspace"}
local objects = {}
local Instance = {new=function(class)
    local part = {ClassName=class, Parent=nil, destroyed=false}
    function part:Destroy() self.destroyed=true; self.Parent=nil end
    table.insert(objects, part)
    return part
end}
local function create(class, props)
    local object = props or {}
    object.ClassName = class
    object.children = {}
    object.InputBegan, object.InputEnded = signal(), signal()
    function object:Destroy()
        self.destroyed=true; self.Parent=nil
        for _, child in ipairs(self.children) do child:Destroy() end
    end
    if object.Parent then table.insert(object.Parent.children, object) end
    return object
end
local gui = {children={}}
local input = {TouchEnabled=true, InputBegan=signal(), InputEnded=signal(),
    WindowFocusReleased=signal(), TextBoxFocused=signal(), keys={}}
function input:GetFocusedTextBox() return self.focused end
function input:IsKeyDown(key) return self.keys[key] == true end
local heartbeat=signal()
local run={Heartbeat=heartbeat}
local h={Health=100,HipHeight=2}
local root={Size=Vector3.new(2,2,1),Position=Vector3.new(0,100,0),
    AssemblyLinearVelocity=Vector3.new(3,0,4)}
local char={FindFirstChildOfClass=function(_,name) if name=="Humanoid" then return h end end,
    FindFirstChild=function(_,name) if name=="HumanoidRootPart" then return root end end}
local player={Character=char}
local host={LocalPlayer=player,UserInputService=input,RunService=run,workspace=world,ScreenGui=gui,create=create}
local card
local framework={Categories={Exploits={CreateModule=function(_,def)
    card={Enabled=false,cleanup={}}
    function card:SetStatus(value) self.status=value end
    function card:Clean(item) table.insert(self.cleanup,item) end
    function card:Toggle(value)
        if self.Enabled==value then return end
        self.Enabled=value
        if not value then
            for i=#self.cleanup,1,-1 do
                local item=self.cleanup[i]
                if type(item)=="function" then item() else item:Disconnect() end
            end
            table.clear(self.cleanup)
        end
        def.Function(value)
    end
    return card
end}}}
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." != "..tostring(b)) end
'''+"\nlocal Module=(function()\n"+SOURCE+"\nend)()\n"+r'''
Module.init({host=host,framework=framework})
assert(not card.Enabled and heartbeat:Count()==0 and #objects==0 and #gui.children==0,
    "injecting AirWalk OFF creates no platform or controls")
card:Toggle(true)
assert(heartbeat:Count()==1 and card.status=="Active")
heartbeat:Fire(1/60)
local part=objects[#objects]
assert(part and part.CanCollide and part.Anchored and part.CanTouch==false and part.Parent==world)
near(part.CFrame.Position.Y,96.5)
root.Position=Vector3.new(0,105,0); heartbeat:Fire(1/60); near(part.CFrame.Position.Y,101.5)
root.Position=Vector3.new(0,100,0); heartbeat:Fire(1/60)
near(part.CFrame.Position.Y,101.5)
assert(part.CanCollide, "the platform holds the highest jump height")
part.CanCollide=false; heartbeat:Fire(1/60)
assert(part.CanCollide, "the local platform remains collidable")
local key={UserInputType="Keyboard",KeyCode="Space"}
local beforeSpike=part.CFrame.Position.Y
input.InputBegan:Fire(key,false); heartbeat:Fire(1)
near(part.CFrame.Position.Y, beforeSpike + 22/60)
heartbeat:Fire(.1)
assert(root.AssemblyLinearVelocity.Y==22, "Space rises and a large dt cannot cause a huge jump")
input.InputEnded:Fire(key)
root.AssemblyLinearVelocity=Vector3.new(3,0,4)
local shift={UserInputType="Keyboard",KeyCode="LeftShift"}
input.InputBegan:Fire(shift,false); heartbeat:Fire(.1)
assert(root.AssemblyLinearVelocity.Y==-22, "Shift descends")
input.WindowFocusReleased:Fire()
root.AssemblyLinearVelocity=Vector3.new(3,0,4); heartbeat:Fire(.1)
assert(root.AssemblyLinearVelocity.Y==0, "lost focus releases held controls")
input.focused=true; input.InputBegan:Fire(key,false); heartbeat:Fire(.1)
assert(root.AssemblyLinearVelocity.Y==0, "typing does not move the player")
input.focused=false
input.keys.Space=true; heartbeat:Fire(.1)
assert(root.AssemblyLinearVelocity.Y==22, "physical key state is also honoured")
input.keys.Space=false; root.AssemblyLinearVelocity=Vector3.new(3,0,4)
local frame=gui.children[#gui.children]
local up,down=frame.children[1],frame.children[2]
assert(up.Name=="Up" and down.Name=="Down")
local finger={UserInputType="Touch"}
up.InputBegan:Fire(finger); heartbeat:Fire(.1)
assert(root.AssemblyLinearVelocity.Y==22, "touch Up rises")
input.InputEnded:Fire(finger)
root.AssemblyLinearVelocity=Vector3.new(3,0,4)
down.InputBegan:Fire(finger); heartbeat:Fire(.1)
assert(root.AssemblyLinearVelocity.Y==-22, "touch Down descends")
down.InputEnded:Fire(finger)
root.AssemblyLinearVelocity=Vector3.new(3,0,4)
h.Health=0; heartbeat:Fire(.1); assert(part.destroyed, "death removes the platform")
h.Health=100; heartbeat:Fire(.1); part=objects[#objects]
assert(not part.destroyed and part.Parent==world, "a valid character recreates the platform")
Module.destroy()
assert(not card.Enabled and heartbeat:Count()==0 and input.InputBegan:Count()==0
    and input.InputEnded:Count()==0 and part.destroyed and frame.destroyed,
    "unload removes platform, mobile controls and connections")
print("PASS AirWalk: inert injection, height, PC/touch input, focus, death/respawn and complete cleanup")
'''

with tempfile.TemporaryDirectory(prefix="airwalk-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
