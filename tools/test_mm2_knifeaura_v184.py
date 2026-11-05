#!/usr/bin/env python3
"""Real MM2 Knife Stab loop: retries, delayed OFF races, distance and touch fallback."""
import os
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'src/games/MM2/Blatant/KnifeAura.lua').read_text()
segment=s[s.index('    local function getEquippedWeapon('):s.index('    local function toggleKnifeAura(')]
script=r'''
local now=1
local os={clock=function() return now end}
local mt
mt={__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end,
    __index=function(v,k) if k=='Magnitude' then return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end end}
local function pos(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local tasks={}
local task={delay=function(_,fn) table.insert(tasks,fn) end}
local function flush() local copy=tasks;tasks={};for _,f in ipairs(copy) do f() end end
local myRoot={Position=pos(0,0,0)}
local targetRoot={Position=pos(10,0,0)}
local humanoid={Health=100}
local targetCharacter={FindFirstChild=function(_,name) if name=='HumanoidRootPart' then return targetRoot end end}
local target={Name='Target',Character=targetCharacter}
local character={FindFirstChild=function(_,name) if name=='HumanoidRootPart' then return myRoot end end,
    FindFirstChildOfClass=function() return humanoid end}
local LocalPlayer={Character=character}
local Players={GetPlayers=function() return {LocalPlayer,target} end}
local sent,activated=0,0
local activateFails,remoteFails,disabled,held,disableOnActivate=false,false,false,true,false
local handle={IsA=function(_,kind) return kind=='BasePart' end}
local remote={IsA=function(_,kind) return kind=='RemoteEvent' end,
    FireServer=function(_,part) if remoteFails then error('remote disappeared') end
        assert(part==targetRoot);sent+=1 end}
local events={FindFirstChild=function(_,name) if name=='HandleTouched' then return remote end end}
local knife
knife={GetAttribute=function(_,name) return name=='Disabled' and disabled end,
    FindFirstChild=function(_,name) if name=='Handle' then return handle elseif name=='Events' then return events end end,
    Activate=function() if activateFails then error('equip race') end activated+=1
        if disableOnActivate then knife.Enabled=false end end}
local function getPlayerWeapon(_,name,equipped) assert(name=='Knife' and equipped);return held and knife or nil end
local function getPlayerRole(player) return player==LocalPlayer and 'Murderer' or 'Innocent' end
local protected=false
local function isProtectedTarget() return protected end
local function isPlayerAlive() return true end
local knifeSettings={aura=true,auraRange=14}
local touchPhases={}
local state={mm2KnifeRuntime={masterEnabled=true,lastAuraSwing=-math.huge},
    fireTouchInterest=function(_,_,phase) table.insert(touchPhases,phase) end}
local notes=0
local trajectoryCalibration={noteAuthoredShot=function() notes+=1 end}
local function getEffectiveRange() return knifeSettings.auraRange end
local featureConnections={}
local function disconnectFeatureConnection(key) featureConnections[key]=nil end
local TaskManager={Connect=function(_,fn) return {fn=fn,Disconnect=function() end} end}
''' + segment + r'''
activateFails=true;processKnifeAura()
assert(state.mm2KnifeRuntime.lastAuraSwing==-math.huge and #tasks==0,
    'failed activation cannot consume the next swing')
activateFails=false;processKnifeAura();assert(activated==1 and #tasks==1)
state.mm2KnifeRuntime.masterEnabled=false;refreshKnifeController();flush()
assert(sent==0 and notes==0, 'a delayed contact must not fire after master OFF')
state.mm2KnifeRuntime.masterEnabled=true;refreshKnifeController()
now+=1;processKnifeAura();assert(#tasks==1)
state.mm2KnifeRuntime.masterEnabled=false;refreshKnifeController()
state.mm2KnifeRuntime.masterEnabled=true;refreshKnifeController();flush()
assert(sent==0, 'old delayed contact must not revive on rapid OFF/ON')
now+=1;processKnifeAura();flush();assert(sent==1 and notes==1)
now+=1;processKnifeAura();targetRoot.Position=pos(100,0,0);flush()
assert(sent==1, 'target outside range after delay must not be hit')
targetRoot.Position=pos(10,0,0);remoteFails=true;now+=1;processKnifeAura();flush()
assert(sent==1 and #touchPhases==2 and touchPhases[1]==0 and touchPhases[2]==1,
    'failed remote falls back to begin/end touch')
-- A normal swing may disable the Tool for its own cooldown. The contact
-- belongs to the successful activation and must not be cancelled by that.
remoteFails=false;disableOnActivate=true;now+=1;processKnifeAura();flush()
assert(sent==2 and knife.Enabled==false, 'cooldown after activation does not cancel contact')
disableOnActivate=false;knife.Enabled=true
held=false;now+=1;processKnifeAura();assert(#tasks==0, 'knife must be equipped')
held=true;knife.Enabled=false;now+=1;processKnifeAura();assert(#tasks==0, 'disabled Tool cannot start an activation')
knife.Enabled=true;disabled=true;now+=1;processKnifeAura();assert(#tasks==0, 'Disabled attribute is respected')
disabled=false;protected=true;now+=1;processKnifeAura();assert(#tasks==0, 'protected targets are skipped')
print('PASS MM2 Knife Stab: failed activation retry, OFF/ON cancellation, live range, remote fallback and protection')
'''
with tempfile.TemporaryDirectory(prefix='mm2-knifeaura-') as tmp:
    p=Path(tmp)/'test.luau';p.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
