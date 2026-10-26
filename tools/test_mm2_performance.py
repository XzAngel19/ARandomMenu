#!/usr/bin/env python3
"""Deterministic performance/lifecycle regressions against the real MM2 source.

These count simulated instance lookups and callbacks, NOT Roblox CPU usage.
"""
from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()
FARM = (ROOT / 'src/games/MM2/Other/AutoFarm.lua').read_text()
WIN = (ROOT / 'src/games/MM2/Other/AutoWin.lua').read_text()
PRED = (ROOT / 'src/games/MM2/Prediction.lua').read_text()
SILENT = (ROOT / 'src/games/MM2/Combat/SilentAim.lua').read_text()
KNIFE = (ROOT / 'src/games/MM2/Combat/KnifeThrow.lua').read_text()

# Guard the actual no-target branch as well as executing the real scan below.
no_target = FARM.split('if not nearest or not nearestPosition then', 1)[1].split(
    'if nearestPosition then', 1)[0]
assert not re.search(r'\bscanAt\s*=', no_target), 'an empty scan must not move its deadline backwards'
assert 'core.findLobbyReferencePart' in FARM and 'core.findLobbyReferencePart' in WIN
for key in ('MM2LobbyAdded', 'MM2LobbyRemoved', 'MM2LobbyDescendantAdded',
            'MM2LobbyDescendantRemoving'):
    assert f'"{key}"' in BASE, f'{key} must be disconnected on unload'

PRED_SETUP = r'''
do
    local workspace={Gravity=196.2}
    local LocalPlayer={Character={}}
    local counts={}
    local function rig(withUpper)
        local char={parts={}}
        local humanoid={Health=100,Parent=char,GetState=function() return "Running" end}
        local root={Name="HumanoidRootPart",Parent=char,Position=Vector3.new(10,0,0),AssemblyLinearVelocity=Vector3.zero,IsA=function() return true end}
        local function part(name,y)
            return {Name=name,Parent=char,Position=Vector3.new(10,y,0),IsA=function() return true end}
        end
        char.parts.HumanoidRootPart=root
        char.parts.Torso=part("Torso",3)
        if withUpper then char.parts.UpperTorso=part("UpperTorso",1) end
        function char:FindFirstChild(name)
            counts[name]=(counts[name] or 0)+1
            return self.parts[name]
        end
        function char:FindFirstChildOfClass(name)
            counts.Humanoid=(counts.Humanoid or 0)+1
            return self.humanoid
        end
        char.humanoid=humanoid
        return char,root,humanoid,part
    end
    local char,root,humanoid,part=rig(true)
    local target={Character=char}
    local Players={GetPlayers=function() return {LocalPlayer,target} end}
    local state={mm2Core={predictionMath=predictionMath,getEstimatedLatency=function() return 0.12 end}}
    local featureConnections={}
    local sampleTick=nil
    local function disconnectFeatureConnection(key)
        if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
    end
    local TaskManager={Connect=function(_,callback)
        sampleTick=callback
        return {Disconnect=function() sampleTick=nil end}
    end}
    local function loadPrediction()
'''
PRED_TEST = r'''
    end
    local Module=loadPrediction()
    Module.init({})
    now=0
    for i=1,60 do
        now=i/60
        sampleTick(1/60)
    end
    local pred=state.mm2Prediction
    local history=pred.getHistory(target,0.6)
    assert(history and #history>=35, '60 Hz passive samples/history must remain intact')
    assert(counts.Humanoid==1 and counts.HumanoidRootPart==1 and counts.UpperTorso==1,
        'unchanged R15 rig should need only one search per stable part')
    local _,shot=pred.knifeAim(target,Vector3.zero,96)
    near(shot.capturedPosition.Y,1)
    -- Replacing the preferred torso immediately falls back; adding it back
    -- immediately beats Head on the very next sample.
    char.parts.UpperTorso.Parent=nil
    char.parts.UpperTorso=nil
    now+=1/60; sampleTick(1/60)
    local _,headShot=pred.knifeAim(target,Vector3.zero,96)
    near(headShot.capturedPosition.Y,3)
    char.parts.UpperTorso=part('UpperTorso',2)
    now+=1/60; sampleTick(1/60)
    local _,newShot=pred.knifeAim(target,Vector3.zero,96)
    near(newShot.capturedPosition.Y,2)
    -- Replaced root and humanoid, death, and a new character all invalidate.
    root.Parent=nil
    root={Name='HumanoidRootPart',Parent=char,Position=Vector3.new(50,0,0),AssemblyLinearVelocity=Vector3.zero,IsA=function() return true end}
    char.parts.HumanoidRootPart=root
    now+=1/60; sampleTick(1/60)
    assert(pred.getMotion(target).samples==1,'teleport/replaced root must clear stale fit')
    humanoid.Parent=nil
    humanoid={Parent=char,Health=100,GetState=function() return 'Jumping' end}
    char.humanoid=humanoid
    now+=1/60; sampleTick(1/60)
    assert(pred.getHistory(target,0.6)[2].state=='Jumping','replacement humanoid state must be read')
    humanoid.Health=0
    now+=1/60; sampleTick(1/60)
    assert(pred.getMotion(target)==nil,'dead rigs are dropped')
    local newChar=rig(true)
    target.Character=newChar
    now+=1/60; sampleTick(1/60)
    assert(pred.getMotion(target).samples==1,'respawn starts a fresh track')
    Module.destroy()
    assert(sampleTick==nil and state.mm2Prediction==nil)
    print('PASS MM2 sampler: 60 Hz maintained; cached lookup counts; torso/root/humanoid/respawn invalidation')
end
'''

LOBBY_SETUP = r'''
do
    local realTypeof=typeof
    local function typeof(v)
        if getmetatable(v)==mt then return 'Vector3' end
        return realTypeof(v)
    end
    local function signal()
        local s={listeners={}}
        function s:Connect(fn)
            local c={Connected=true,fn=fn};function c:Disconnect() self.Connected=false end
            table.insert(self.listeners,c);return c
        end
        function s:Fire(...)
            for _,c in ipairs(self.listeners) do if c.Connected then c.fn(...) end end
        end
        return s
    end
    local reads,deep=0,0
    local function node(name,class)
        local n={Name=name,ClassName=class or 'Model',children={}}
        function n:IsA(className) return self.ClassName==className or (className=='BasePart' and self.ClassName=='Part') end
        function n:IsDescendantOf(parent)
            local p=self.Parent;while p do if p==parent then return true end;p=p.Parent end;return false
        end
        function n:FindFirstChild(name,recursive)
            if recursive then deep+=1 end
            for _,c in ipairs(self.children) do if c.Name==name then return c end end
            if recursive then for _,c in ipairs(self.children) do local x=c:FindFirstChild(name,true);if x then return x end end end
            return nil
        end
        function n:FindFirstChildWhichIsA(className,recursive)
            if recursive then deep+=1 end
            for _,c in ipairs(self.children) do if c:IsA(className) then return c end end
            if recursive then for _,c in ipairs(self.children) do local x=c:FindFirstChildWhichIsA(className,true);if x then return x end end end
            return nil
        end
        return n
    end
    local workspace=node('Workspace','Workspace')
    workspace.ChildAdded=signal();workspace.ChildRemoved=signal()
    workspace.DescendantAdded=signal();workspace.DescendantRemoving=signal()
    function workspace:GetChildren() reads+=1;return table.clone(self.children) end
    local function add(parent,child)
        child.Parent=parent;table.insert(parent.children,child)
        if parent==workspace then workspace.ChildAdded:Fire(child) end
        workspace.DescendantAdded:Fire(child)
        return child
    end
    local function remove(child)
        workspace.DescendantRemoving:Fire(child)
        local p=child.Parent;table.remove(p.children,table.find(p.children,child));child.Parent=nil
        if p==workspace then workspace.ChildRemoved:Fire(child) end
    end
    local featureConnections={}
'''
LOBBY_TEST = r'''
    now=0
    for _=1,120 do assert(findLobbyModel()==nil);assert(findLobbyReferencePart()==nil) end
    assert(reads==2,'empty lobby misses should be cached across 120 calls')
    local map=add(workspace,node('Map'))
    local mapSpawns=add(map,node('Spawns'))
    local mapPart=add(mapSpawns,node('MapSpawn','Part'));mapPart.Position=Vector3.new(1800,0,0)
    for _=1,120 do assert(findLobbyModel()==nil);assert(findLobbyReferencePart()==nil) end
    local deepAfterMiss=deep
    for _=1,120 do findLobbyReferencePart() end
    assert(deep==deepAfterMiss,'no repeated recursive walks on a miss')
    local lobby=add(workspace,node('MainLobby'))
    local spawnFolder=add(lobby,node('Spawns'))
    local spawn=add(spawnFolder,node('Spawn','Part'));spawn.Position=Vector3.zero
    assert(findLobbyModel()==lobby and findLobbyReferencePart()==spawn,'new lobby is visible immediately')
    local before=deep
    for _=1,120 do
        assert(findLobbyModel()==lobby and findLobbyReferencePart()==spawn)
        assert(isRootNearLobby({Position=Vector3.new(100,0,0)},lobby))
        assert(not isRootNearLobby({Position=Vector3.new(1800,0,0)},lobby))
    end
    assert(deep==before,'stable lobby reference must not trigger recursive scans')
    local pads=add(lobby,node('VotePads'))
    assert(findLobbyReferencePart()==spawn,'fallback while pads have no part')
    local pad=add(pads,node('Pad','Part'));pad.Position=Vector3.new(5,0,0)
    assert(findLobbyReferencePart()==pad,'a streamed-in vote pad must replace the lower-priority spawn immediately')
    remove(pad)
    assert(findLobbyReferencePart()==spawn,'removed cached part must be re-resolved')

    -- Both features must reject the lobby yet detect the map before roles or
    -- coins appear, during the pre-round countdown.
    local findMM2Map=function() return map end
    local role='None'
    local getPlayerRole=function() return role end
    local isRoundLifecycleActive=function() return false end
    local LocalPlayer={}
    local safeZonePlatform=nil
'''
LOBBY_AFTER_GUARDS = r'''
    local root={Position=Vector3.zero}
    assert(not isCharacterInActiveRound(root) and not isCharacterOnMap(root),'lobby must remain safe')
    root.Position=Vector3.new(1800,0,0)
    assert(isCharacterInActiveRound(root) and isCharacterOnMap(root),'pre-round map must be detected without coins')
    role='Dead';assert(not isCharacterInActiveRound(root),'dead player must not farm')
    role='None'
    remove(lobby)
    local folder=add(workspace,node('SeasonalFolder'))
    local inner=add(folder,node('Interior'))
    local nestedPads=add(inner,node('VotePads'))
    local nestedPad=add(nestedPads,node('NestedPad','Part'));nestedPad.Position=Vector3.zero
    assert(findLobbyModel()==nil,'core round classifier must not treat arbitrary nested folders as direct lobbies')
    assert(findLobbyReferencePart()==nestedPad,'farm/win retain nested seasonal lobby fallback')
    remove(nestedPads)
    assert(findLobbyReferencePart()==nil,'removed seasonal lobby marker must invalidate fallback')
    print('PASS MM2 lobby: cached hits/misses, streaming, removal, countdown map and lobby safety')
end
'''

COIN_SETUP = r'''
do
    local state={}
    local fullScans=0
    local fallbackCoin={Name='Coin_Server',Parent=true,Position=Vector3.new(20,0,0)}
    function fallbackCoin:IsA(class) return class=='BasePart' end
    function fallbackCoin:GetAttribute() return nil end
    local workspace={GetDescendants=function() fullScans+=1;return {fallbackCoin} end}
    local tagged={}
    local game={GetService=function() return {GetTagged=function() return tagged end} end}
'''
COIN_SCAN_SETUP = r'''
    local scanAt=0
    local scanCache={}
    local blacklist={}
    local stillCollectable=function(p) return not p.collected end
    local coinPositionOf=function(p) return p.Position end
    local function scan(root)
'''
COIN_TEST = r'''
        return nearest,nearestPosition
    end
    local providerCalls=0
    local list={}
    state.mm2CoinPickups=function() providerCalls+=1;return list end
    local root={Position=Vector3.zero}
    now=0
    for i=1,120 do now=i/60;assert(scan(root)==nil) end
    assert(providerCalls>=15 and providerCalls<=21,'empty scans should run ~10 Hz, not every frame: '..providerCalls)
    list={fallbackCoin}
    local detectedAt=nil
    for _=1,7 do now+=1/60;if scan(root) then detectedAt=now;break end end
    assert(detectedAt and detectedAt<=2+0.12,'new coin must be detected within the 0.1 s empty-scan window')
    fallbackCoin.collected=true
    assert(scan(root)==nil,'a collected coin stops being targeted immediately')
    fallbackCoin.collected=false
    state.mm2CoinPickups=nil
    scanAt=0;scanCache={};now=3
    assert(scan(root)==fallbackCoin and fullScans==1,'fallback world scan still finds Coin_Server')
    tagged={fallbackCoin};scanAt=0;scanCache={};now=4
    assert(scan(root)==fallbackCoin and fullScans==1,'tagged pickup avoids world walk')
    print('PASS MM2 coins: ~10 Hz empty scans, timely appearance, collected skip, tags and fallback')
end
'''


def run(code: str) -> None:
    with tempfile.TemporaryDirectory(prefix='mm2-perf-') as td:
        path = Path(td) / 'test.luau'
        path.write_text(code)
        subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], cwd=ROOT, check=True)


def main() -> None:
    pred_math = section(BASE, 'local predictionMath = {}', 'local lastLatencyReadAt')
    run(PRELUDE + pred_math + PRED_SETUP + PRED + PRED_TEST)
    lobby_names = section(BASE, 'local LOBBY_MODEL_NAMES:', 'local function isMM2MapModel')
    lobby_cache = section(BASE, 'local lobbyCache:', 'local function detectRoundPhase')
    farm_guard = section(FARM, 'local function isCharacterInActiveRound', 'local function restoreCharacter')
    win_guard = section(WIN, 'local function isCharacterOnMap', 'local function restoreVictims')
    run(PRELUDE + LOBBY_SETUP + lobby_names + lobby_cache + LOBBY_TEST + farm_guard + win_guard + LOBBY_AFTER_GUARDS)
    pickup = section(FARM, 'local function coinPickups()', '-- Live ping')
    scan = section(FARM, '-- Nearest pickup, from Coin ESP', 'if not nearest or not nearestPosition then')
    run(PRELUDE + COIN_SETUP + pickup + COIN_SCAN_SETUP + scan + COIN_TEST)


if __name__ == '__main__':
    main()
