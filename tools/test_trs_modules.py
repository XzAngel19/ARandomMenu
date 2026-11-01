#!/usr/bin/env python3
"""Execute the real TRS module's queued actions and hook lifecycle with mocks."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/TRS/base.lua').read_text()
script=PRELUDE+r'''
Enum.KeyCode={Unknown='Unknown'};Enum.UserInputType={Keyboard='Keyboard'}
local BrickColor={new=function(n) return n end}
local RaycastParams={new=function() return {} end}
local Color3={fromRGB=function(...) return {...} end}
local function signal()
    local listeners={};local event={}
    function event:Connect(fn) local c={};listeners[c]=fn;function c:Disconnect() listeners[self]=nil end;return c end
    function event:Fire(...) for _,fn in pairs(listeners) do fn(...) end end
    function event:Count() local n=0;for _ in pairs(listeners) do n+=1 end;return n end
    return event
end
local delayed,deferred={},{}
local task={delay=function(_,fn) table.insert(delayed,fn) end,defer=function(fn) table.insert(deferred,fn) end,
    spawn=function(fn) fn() end}
local function flushDelayed() while #delayed>0 do table.remove(delayed,1)() end end
local function flushDeferred() while #deferred>0 do table.remove(deferred,1)() end end
local function valueContainer(children) return {FindFirstChild=function(_,name) return children[name] end} end
local bools=valueContainer({})
local root={Position=Vector3.zero,AssemblyLinearVelocity=Vector3.zero,CFrame={LookVector=Vector3.new(1,0,0),
    PointToObjectSpace=function(_,p) return p end}}
local humanoid={Health=100}
local character={FindFirstChild=function(_,name) if name=='Bools' then return bools elseif name=='HumanoidRootPart' then return root end end,
    FindFirstChildOfClass=function(_,name) if name=='Humanoid' then return humanoid end end}
local targetRoot={Position=Vector3.new(4,0,0),AssemblyLinearVelocity=Vector3.zero}
local targetCharacter={FindFirstChild=function(_,name) if name=='HumanoidRootPart' then return targetRoot end end,
    FindFirstChildOfClass=function(_,name) if name=='Humanoid' then return humanoid end end}
local target={Character=targetCharacter,TeamColor=141,IsA=function(_,kind) return kind=='Player' end}
local owner=nil
local ball={Position=Vector3.new(3,0,0),Size=Vector3.new(2,2,2),IsA=function(_,kind) return kind=='BasePart' end}
function ball:FindFirstChild(name)
    if name=='playerWeld' and owner then return {} end
    if name=='creator' and owner then return {Value=owner,IsA=function(_,kind) return kind=='ObjectValue' end} end
end
local goal={Name='HomeGoalDetector',Position=Vector3.new(30,0,0),IsA=function(_,kind) return kind=='BasePart' end}
goal.CFrame={RightVector=Vector3.new(0,0,1),PointToObjectSpace=function(_,p) return p-goal.Position end}
local ownGoal={Name='AwayGoalDetector',Position=Vector3.new(-150,0,0),IsA=function(_,kind) return kind=='BasePart' end}
local workspace={Gravity=196,FindFirstChild=function(_,name)
    if name=='ball' then return ball elseif name=='Bools' then return bools elseif name=='HomeGoalDetector' then return goal
    elseif name=='AwayGoalDetector' then return ownGoal end
end,Raycast=function() return nil end}
local playerGui=nil
local LocalPlayer={Character=character,TeamColor=23,IsA=function(_,kind) return kind=='Player' end,
    FindFirstChild=function() return nil end,FindFirstChildOfClass=function(_,kind) if kind=='PlayerGui' then return playerGui end end}
local actions,disarms,pickups={},0,0
local action={IsA=function(_,kind) return kind=='RemoteEvent' end,FireServer=function(_,a) table.insert(actions,a) end}
local disarm={IsA=function(_,kind) return kind=='RemoteEvent' end,FireServer=function() disarms+=1 end}
local pickup={Parent=true,IsA=function(_,kind) return kind=='RemoteEvent' end,
    GetAttribute=function(_,name) if name=='Attribute' then return true end end,
    FireServer=function() pickups+=1 end}
local shoot={}
local remotes={FindFirstChild=function(_,name)
    if name=='Action' then return action elseif name=='SoftDisPlayer' then return disarm
    elseif name=='ShootTheBall' then return shoot end
end,GetChildren=function() return {pickup} end}
local replicated={FindFirstChild=function(_,name) if name=='Remotes' then return remotes end end}
local game={GetService=function(_,name)
    if name=='ReplicatedStorage' then return replicated elseif name=='Debris' then return {AddItem=function() end} end
end}
local instances={}
local Instance={new=function(class)
    local o={ClassName=class};function o:Destroy() self.destroyed=true;self.Parent=nil end
    table.insert(instances,o);return o
end}
local UserInputService={InputBegan=signal(),GetFocusedTextBox=function() return nil end}
local Players={GetPlayers=function() return {LocalPlayer,target} end}
local state={trsScroll={},trsFeatures={}}
local featureConnections={}
local function disconnectFeatureConnection(name)
    local c=featureConnections[name];if c then c:Disconnect();featureConnections[name]=nil end
end
local TaskManager={Connect=function(_,fn) return {callback=fn,active=true,Disconnect=function(self) self.active=false end} end}
local features={}
local function createUniversalFeature(name,_,_,fn)
    local f={options={},row={}};function f:Toggle(v) fn(v) end;features[name]=f;return f
end
local function addNumberOption(f,name,_,_,_,fn) f.options[name]=fn;return {} end
local function addToggleOption(f,name,_,fn) f.options[name]=fn;return {} end
local function addCycleOption(f,name,_,_,fn) f.options[name]=fn;return {} end
local function addKeyOption(f,name,_,fn) f.options[name]=fn;return {} end
local function addInformationOption() end
local function getCharacterParts() return character,humanoid,root end
local function notify() end
local sent
local originalCall=function(_,...) sent={...};return 'sent' end
local callChain=originalCall
local function hookmetamethod(_,_,fn) local previous=callChain;callChain=fn;return previous end
local function getnamecallmethod() return 'FireServer' end
local firesignal
'''+ '\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({Menu={},TaskManager=TaskManager,Services={protectedTargets={isProtected=function() return false end}}})
local function frame(name) local c=featureConnections[name];assert(c and c.active);c.callback(1/60) end
-- A pickup's delayed Deke must not survive an OFF/ON cycle.
now=1;owner=nil;features['Auto Pickup']:Toggle(true);frame('TRSPickupLoop');assert(pickups==1 and #delayed==1)
features['Auto Pickup']:Toggle(false);features['Auto Pickup']:Toggle(true);owner=LocalPlayer;flushDelayed()
assert(#actions==0, 'old pickup must not Deke in a new activation')
owner=nil;now=2;frame('TRSPickupLoop');owner=LocalPlayer;flushDelayed()
assert(actions[#actions]=='Deke', 'current pickup still performs its delayed Deke')
features['Auto Pickup']:Toggle(false);table.clear(actions)
-- A tackle's two delayed steals must not survive OFF/ON either.
features['Auto Tackle'].options['Show carrier'](false);features['Auto Tackle'].options.Aimlock(false)
now=3;owner=target;features['Auto Tackle']:Toggle(true);frame('TRSAutoTackle')
assert(actions[#actions]=='TackIe' and #delayed==2)
features['Auto Tackle']:Toggle(false);features['Auto Tackle']:Toggle(true);flushDelayed()
assert(disarms==0, 'old tackle must not steal in a new activation')
now=4;frame('TRSAutoTackle');flushDelayed();assert(disarms==2, 'current tackle still retries twice')
features['Auto Tackle']:Toggle(false)
-- A failed shot with no mobile button should not leave an idle namecall hook.
now=5;owner=LocalPlayer;features['Shoot Assist'].options['Shot key']('G');features['Shoot Assist']:Toggle(true)
UserInputService.InputBegan:Fire({UserInputType='Keyboard',KeyCode='G'},false)
assert(callChain==originalCall, 'failed shot must release the temporary hook')
-- Missing executor signal support is another failed-shot path.
local ups=0
local button={Parent=true,MouseButton1Down=function()
    callChain(shoot,Vector3.new(1,0,0),'arg2',0,Vector3.new(0,0,2),'arg5','arg6','oldcurve','arg8',false,'oldside')
end,MouseButton1Up=function() ups+=1 end}
local header={MouseButton1Click=function() end}
function button:FindFirstChild(name) if name=='Header' then return header end end
local controlFrame=valueContainer({JumpButton=button});local mobile=valueContainer({TouchControlFrame=controlFrame})
playerGui=valueContainer({MobileCTRL=mobile});now=6
UserInputService.InputBegan:Fire({UserInputType='Keyboard',KeyCode='G'},false)
assert(callChain==originalCall, 'unsupported signal must release the hook')
-- When supported, the game's native shot is still redirected and the release is sent.
firesignal=function(callback) callback() end;now=7
UserInputService.InputBegan:Fire({UserInputType='Keyboard',KeyCode='G'},false)
assert(sent and sent[1].X>0 and sent[7]=='Right' and sent[10]=='Right', 'native shot was redirected')
flushDeferred();assert(callChain==originalCall, 'consumed shot releases idle hook after dispatch')
flushDelayed();assert(ups==1, 'native button release still fires')
-- The button can fire without the game sending a remote: the pending hook must time out.
button.MouseButton1Down=function() end
now=8;UserInputService.InputBegan:Fire({UserInputType='Keyboard',KeyCode='G'},false)
assert(callChain~=originalCall and #delayed==2)
flushDelayed();assert(callChain==originalCall and ups==2, 'missing remote releases the hook after timeout')
-- An older timeout must not cancel a newer pending context.
now=9;UserInputService.InputBegan:Fire({UserInputType='Keyboard',KeyCode='G'},false)
now=10;UserInputService.InputBegan:Fire({UserInputType='Keyboard',KeyCode='G'},false)
assert(#delayed==4)
table.remove(delayed,1)();table.remove(delayed,1)()
assert(callChain~=originalCall, 'old timeout must leave newer shot pending')
sent=nil;callChain(shoot,Vector3.new(1,0,0),'arg2',0,Vector3.new(0,0,2),'arg5','arg6','oldcurve','arg8',false,'oldside')
assert(sent and sent[7]=='Right' and sent[10]=='Right', 'newer context still redirects')
flushDeferred();flushDelayed();assert(callChain==originalCall)
-- Header uses the same timed hook and must also release it if no remote arrives.
owner=nil;ball.Position=Vector3.new(3,2,0);now=11
features['Auto Header']:Toggle(true);frame('TRSAutoHeader')
assert(callChain~=originalCall and #delayed==1, 'header should have a pending native context')
flushDelayed();assert(callChain==originalCall, 'header timeout releases the idle hook')
features['Auto Header']:Toggle(false);owner=LocalPlayer;ball.Position=Vector3.new(3,0,0)
-- Maximum power deliberately retains the hook until the option is disabled.
features['Pass Assist'].options['Maximum power'](true);assert(callChain~=originalCall)
now=12;UserInputService.InputBegan:Fire({UserInputType='Keyboard',KeyCode='G'},false);flushDeferred()
assert(callChain~=originalCall, 'maximum power keeps its active hook')
flushDelayed();features['Pass Assist'].options['Maximum power'](false);assert(callChain==originalCall)
-- A different script may have installed its own hook on top. Keep that hook and
-- make our now-idle wrapper forward unchanged; do not replace the other script.
features['Pass Assist'].options['Maximum power'](true)
local prior=callChain
local external=function(self,...) return prior(self,...) end
callChain=external
features['Pass Assist'].options['Maximum power'](false)
assert(callChain==external, 'disabling must preserve an external later hook')
sent=nil;callChain(shoot,'external',2,3,4,5,6,7,8,9,10)
assert(sent[1]=='external' and sent[3]==3, 'retained wrapper must be inert')
features['Shoot Assist']:Toggle(false)
Module.destroy();flushDelayed();flushDeferred()
assert(callChain==external and UserInputService.InputBegan:Count()==0, 'unload must keep the external hook and disconnect actions')
sent=nil;callChain(shoot,'after-unload');assert(sent[1]=='after-unload')
print('PASS TRS: queued cancellation, native shot/charge, overlapping timeouts, header timeout, external hooks and unload')
'''
with tempfile.TemporaryDirectory(prefix='trs-modules-') as tmp:
    path=Path(tmp)/'trs.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
