#!/usr/bin/env python3
"""Aim module in an FPS (shift-lock): camera ownership and the fire path.

Runs the real src/games/universal/Combat/AimAssist.lua against mocks and pins
the two reported bugs:

1. Frozen camera: the old code bound a one-shot RenderStep that captured a
   stale CFrame and tried to unbind itself from inside the render step. If
   that unbind failed, the binding re-wrote the stale CFrame every frame and
   the camera stayed glued to the last aim point (where the player clicked).
   The fix writes the camera only from the per-frame RenderStepped callback,
   so with no target nothing writes the camera and no binding ever leaks.
2. Bugged gun: the virtual click was sent at (0, 0) (screen corner) and the
   module called Tool:Activate() even while the real click was already held,
   and re-equipped the tool from the backpack (which can force the game's
   equip/ADS camera). The fix clicks at the real mouse position, never
   double-activates on a held click, and never equips.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

script = r'''
local Vector3 = {}
local mt = {}
function Vector3.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0,__kind='Vector3'},mt) end
Vector3.zero = Vector3.new(0,0,0)
mt.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__mul = function(a,b)
    if type(a) == "number" then a,b = b,a end
    return Vector3.new(a.X*b, a.Y*b, a.Z*b)
end
mt.__div = function(a,b) return a*(1/b) end
mt.__index = function(a,k)
    if k == "Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k == "Unit" then return a/a.Magnitude end
    if k == "Dot" then return function(x,y) return x.X*y.X+x.Y*y.Y+x.Z*y.Z end end
end
local nativeType, nativeTypeof = type, typeof
type = function(v)
    if nativeType(v) == "table" and rawget(v, "__kind") then return rawget(v, "__kind") end
    return nativeType(v)
end
typeof = function(v)
    if nativeTypeof(v) == "table" and rawget(v, "__kind") then return rawget(v, "__kind") end
    return nativeTypeof(v)
end
local Vector2 = {}
local v2mt = {__index = function(t,k)
    if k == "Magnitude" then return math.sqrt(t.X*t.X + t.Y*t.Y) end
    if k == "Unit" then local m = t.Magnitude; return Vector2.new(t.X/m, t.Y/m) end
end}
function Vector2.new(x,y) return setmetatable({X=x or 0, Y=y or 0, __kind='Vector2'}, v2mt) end
local function frame(position, look)
    local right = Vector3.new(-look.Z, 0, look.X)
    if right.Magnitude < 1e-6 then right = Vector3.new(1,0,0) end
    return {Position=position, LookVector=look.Unit, RightVector=right.Unit, __kind='CFrame'}
end
local CFrame = {lookAt = function(p,q) return frame(p, (q-p).Unit) end}
local Enum = {
    MouseBehavior = {Default='Default', LockCenter='LockCenter', LockCurrentPosition='LockCurrentPosition'},
    UserInputType = {MouseButton1='MouseButton1'},
    RenderPriority = {Camera={Value=200}},
}
local now = 0
local os = {clock = function() return now end}
local function near(a,b,epsilon) assert(math.abs(a-b) < (epsilon or 1e-7), tostring(a).." != "..tostring(b)) end
local passed = 0
local function pass(name) passed = passed + 1; print("PASS", name) end

-- mocks ------------------------------------------------------------------
local steps = {}          -- BindToRenderStep registry: must stay empty
local runService = {
    BindToRenderStep = function(_, name, prio, fn) steps[name] = {fn=fn, prio=prio} end,
    UnbindFromRenderStep = function(_, name) steps[name] = nil end,
}
local mousePos = Vector2.new(400, 336)
local lmbPressed = false
local mouseBehavior = Enum.MouseBehavior.Default
local userInput = {
    GetFocusedTextBox = function() return nil end,
    IsMouseButtonPressed = function(_, _) return lmbPressed end,
    GetMouseLocation = function() return mousePos end,
}
userInput.MouseBehavior = nil
Object = nil
local camera = {
    Parent = {},
    CFrame = frame(Vector3.new(3,4,5), Vector3.new(0,0,-1)),
    ViewportSize = Vector2.new(800, 600),
    WorldToScreenPoint = function(_, pos) return Vector3.new(500, 300, 0), true end,
}
local world = {CurrentCamera = camera}
local activateCalls, equipCalls = 0, 0
local heldTool = true
local tool = {
    Enabled = true,
    IsA = function(_, c) return c == "Tool" end,
    Activate = function() activateCalls = activateCalls + 1 end,
}
local backpackTool = {
    Enabled = true,
    IsA = function(_, c) return c == "Tool" end,
    Activate = function() activateCalls = activateCalls + 1 end,
}
local hum = {EquipTool = function() equipCalls = equipCalls + 1 end}
local head = {Position = Vector3.new(3,4,5)}
local character = {
    GetChildren = function() if heldTool then return {tool} end return {} end,
    FindFirstChild = function(_, n) if n == "Head" then return head end return nil end,
    FindFirstChildOfClass = function(_, c) if c == "Humanoid" then return hum end return nil end,
}
local backpack = {GetChildren = function() return {backpackTool} end}
local player = {
    Character = character,
    FindFirstChild = function(_, n) if n == "Backpack" then return backpack end return nil end,
}
-- MouseBehavior is read as a property, keep it in sync with the variable
local userInputProxy = setmetatable({}, {__index = function(_, k)
    if k == "MouseBehavior" then return mouseBehavior end
    return userInput[k]
end, __newindex = function(_, k, v) userInput[k] = v end})
local vimEvents = {}
local vim = {SendMouseButtonEvent = function(_, x, y, _, pressed, _, _)
    table.insert(vimEvents, {x=x, y=y, pressed=pressed})
end}
game = {GetService = function(_, name)
    if name == "VirtualInputManager" then return vim end
    if name == "GuiService" then return {GetGuiInset = function() return Vector2.new(0, 36) end} end
    error("no service " .. tostring(name))
end}
local mousemoveCalls = {}
function mousemoverel(dx, dy) table.insert(mousemoveCalls, {dx, dy}) end
local selected = {position=Vector3.new(103,4,5), distance=100, entity={Name='Target'}, character={Name='Target'}, player=nil}
local currentTargets = {selected}
local targeting = {List = function(_, _, _) return currentTargets end}
local services = {
    menu = {isVisible=function() return false end, isCapturingInput=function() return false end},
    activity = {isActive=function() return false end},
    freeCam = {IsActive=function() return false end},
    spectate = {IsActive=function() return false end},
}
local host = {
    workspace = world,
    UserInputService = userInputProxy,
    LocalPlayer = player,
    RunService = runService,
    services = {},
}
local card
local function option(self, d)
    local o = {Value = d.Default, definition = d}
    if d.List then o.Value = d.List[d.Index or 1] end
    self.Options[d.Name] = o
    return o
end
local framework = {Categories = {Exploits = {CreateModule = function(_, d)
    card = {Options = {}, cleanups = {}}
    card.CreateSlider = option
    card.CreateDropdown = option
    card.CreateToggle = option
    function card:CreateNote() end
    function card:SetStatus(s) self.status = s end
    function card:Render(fn) self.frame = fn end
    function card:Clean(fn) table.insert(self.cleanups, fn) end
    function card:Toggle(on)
        self.Enabled = on
        if not on then
            for _, fn in ipairs(self.cleanups) do fn() end
            table.clear(self.cleanups)
            self.frame = nil
        end
        d.Function(on)
    end
    return card
end}}}
''' + '\nlocal Module = (function()\n' + (ROOT/'src/games/universal/Combat/AimAssist.lua').read_text() + '\nend)()\n' + r'''
local aim = Module.init({host=host, services=services, libraries={targeting=targeting}, framework=framework, entity={}})

-- 1) FPS shift-lock, Aimbot snap: the camera is written toward the target
--    from the frame callback and NO render-step binding is ever created.
aim.Options.Mode.Value = 'Aimbot'
aim.Options.Camera.Value = 'Auto'
mouseBehavior = Enum.MouseBehavior.LockCenter
aim:Toggle(true)
local before = camera.CFrame
aim.frame(0.016)
assert(camera.CFrame ~= before, "locked FPS: the camera must turn toward the target")
near(camera.CFrame.LookVector.X, 1, 1e-6)
assert(#mousemoveCalls > 0, "hybrid FPS must also move the virtual mouse (Mouse Hit sync)")
assert(next(steps) == nil, "no BindToRenderStep binding may be left behind by the aim frame")
pass("FPS hybrid aims with mouse+CFrame and never leaks a render-step binding")

-- 2) The click killed the target: with no target the camera must stay
--    exactly where the game put it (old code let a stale binding rewrite it).
currentTargets = {}
local gameFrame = frame(Vector3.new(3,4,5), Vector3.new(0,1,0))
camera.CFrame = gameFrame
aim.frame(0.016)
assert(camera.CFrame == gameFrame, "no target: the camera must not be written anymore")
assert(next(steps) == nil, "still no binding after the target is gone")
pass("target lost after the click: camera ownership returns to the game, nothing rewrites it")

-- 3) Auto Fire Always with a held tool and no real click: one Activate per
--    CPS interval, throttled.
currentTargets = {selected}
aim.Options["Auto Fire"].Value = true
aim.Options["Auto Fire mode"].Value = 'Always'
aim.Options["Clicks Per Second"].Value = 12
now = 100
local a0 = activateCalls
aim.frame(0.016)
assert(activateCalls == a0 + 1, "Always mode must Activate the held tool once")
aim.frame(0.016)
assert(activateCalls == a0 + 1, "CPS throttle must block an immediate second shot")
now = now + 1/12 + 0.01
aim.frame(0.016)
assert(activateCalls == a0 + 2, "after the CPS interval it fires again")
pass("Auto Fire Always: tool Activate() is CPS-throttled")

-- 4) Hold mode while the real click is held: the game already fires on that
--    click, the module must NOT Activate() again (semi-auto double-fire).
aim.Options["Auto Fire mode"].Value = 'Hold'
lmbPressed = true
now = now + 1
local a1 = activateCalls
aim.frame(0.016)
assert(activateCalls == a1, "Hold + real click held: no extra Activate (the game fires on the click)")
pass("Hold mode with the real click held never double-fires the tool")

-- 5) No held tool: virtual click at the REAL mouse position (never 0,0) and
--    never an EquipTool from the backpack (which can force the game camera).
heldTool = false
lmbPressed = false
aim.Options["Auto Fire mode"].Value = 'Always'
now = now + 1
local v0, e0 = #vimEvents, equipCalls
aim.frame(0.016)
assert(#vimEvents == v0 + 2, "virtual click must press and release")
local ev = vimEvents[#vimEvents]
assert(ev.x == 400 and ev.y == 336, "virtual click at the real cursor, got " .. ev.x .. "," .. ev.y)
assert(not (ev.x == 0 and ev.y == 0), "virtual click must never be sent at the (0,0) corner")
assert(equipCalls == e0, "must never EquipTool from the backpack")
pass("no held tool: virtual click at the real mouse position, backpack equip removed")

aim:Toggle(false)
assert(aim.frame == nil and next(steps) == nil)
Module.destroy()
pass("disable: frame callback and bindings are cleaned up")
'''

with tempfile.TemporaryDirectory(prefix='aim-fps-camera-') as tmp:
    path = Path(tmp) / 'aim_fps.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
