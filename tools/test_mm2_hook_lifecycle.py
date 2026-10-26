#!/usr/bin/env python3
"""Exercise the real Silent AIM / Knife Throw hooks with deterministic mocks.

Counts and toggle behavior are simulated, not an executor or live Roblox test.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
SILENT = (ROOT / 'src/games/MM2/Combat/SilentAim.lua').read_text()
KNIFE = (ROOT / 'src/games/MM2/Combat/KnifeThrow.lua').read_text()

SETUP = r'''
do
    local cfmt={}
    CFrame.new=function(p) return setmetatable({Position=p},cfmt) end
    CFrame.lookAt=function(p,q) return setmetatable({Position=p,Endpoint=q},cfmt) end
    local realTypeof=typeof
    local function typeof(v)
        if getmetatable(v)==mt then return 'Vector3' end
        if getmetatable(v)==cfmt then return 'CFrame' end
        if type(v)=='table' and v.ClassName then return 'Instance' end
        return realTypeof(v)
    end
    local function signal()
        local s={listeners={}}
        function s:Connect(fn)
            local c={Connected=true,fn=fn};function c:Disconnect() self.Connected=false end
            table.insert(self.listeners,c);return c
        end
        return s
    end
    local deferred={}
    local task={defer=function(fn) table.insert(deferred,fn) end,
        delay=function(_,fn) table.insert(deferred,fn) end,
        wait=function() end}
    local function flush()
        local q=deferred;deferred={};for _,f in ipairs(q) do f() end
    end
    local role='Murderer'
    local localChar={ClassName='Model',ChildAdded=signal()}
    local targetChar={ClassName='Model'}
    local localRoot={ClassName='Part',Name='HumanoidRootPart',Position=Vector3.zero,
        AssemblyLinearVelocity=Vector3.zero,CFrame=CFrame.new(Vector3.zero),IsA=function(_,n) return n=='BasePart' end}
    local targetRoot={ClassName='Part',Name='HumanoidRootPart',Position=Vector3.new(25,0,0),
        AssemblyLinearVelocity=Vector3.zero,CFrame=CFrame.new(Vector3.new(25,0,0)),IsA=function(_,n) return n=='BasePart' end}
    local humanoid={ClassName='Humanoid',Health=100}
    local targetHumanoid={ClassName='Humanoid',Health=100}
    local gun={ClassName='Tool',Name='Gun',Activated=signal()}
    local knife={ClassName='Tool',Name='Knife',Activated=signal()}
    local remote={ClassName='RemoteEvent',Name='Shoot',Parent=gun}
    local handle={ClassName='Part',Name='Handle',CFrame=CFrame.new(Vector3.zero),IsA=function(_,n) return n=='BasePart' end}
    function gun:IsA(n) return n=='Tool' end
    function gun:FindFirstChild(n) if n=='Shoot' then return remote end return nil end
    function knife:IsA(n) return n=='Tool' end
    function knife:FindFirstChild(n) if n=='Handle' then return handle end return nil end
    function knife:GetAttribute() return nil end
    function localChar:FindFirstChild(n)
        if n=='HumanoidRootPart' then return localRoot end
        if n=='Gun' and gun.Parent==self then return gun end
        if n=='Knife' and knife.Parent==self then return knife end
        return nil
    end
    function localChar:FindFirstChildOfClass(n) if n=='Humanoid' then return humanoid end end
    function localChar:GetChildren()
        local a={localRoot};if gun.Parent==self then table.insert(a,gun) end
        if knife.Parent==self then table.insert(a,knife) end;return a
    end
    function targetChar:FindFirstChild(n) if n=='HumanoidRootPart' then return targetRoot end end
    function targetChar:FindFirstChildOfClass(n) if n=='Humanoid' then return targetHumanoid end end
    local LocalPlayer={Character=localChar,CharacterAdded=signal()}
    function LocalPlayer:FindFirstChildOfClass() return nil end
    local target={Character=targetChar,Name='Target'}
    local Players={GetPlayers=function() return {LocalPlayer,target} end}
    local function equip(tool)
        gun.Parent=nil;knife.Parent=nil;tool.Parent=localChar
    end
    local nativePC=CFrame.new(Vector3.new(-90,0,0))
    local nativeMobile=CFrame.new(Vector3.new(-91,0,0))
    local nativePCFn=function() return nativePC end
    local nativeMobileFn=function() return nativeMobile end
    local ws={GetMouseTargetCFrame=nativePCFn,GetTargetPosition=nativeMobileFn}
    local wsModule={ClassName='ModuleScript'}
    local rs={FindFirstChild=function(_,n)
        if n=='ClientServices' then return {FindFirstChild=function(_,m) if m=='WeaponService' then return wsModule end end} end
    end}
    local game={GetService=function(_,n) if n=='ReplicatedStorage' then return rs end;return nil end}
    local function require(obj) assert(obj==wsModule);return ws end
    local originals={}
    local function original(self,...)
        originals[#originals+1]={self=self,args={...}}
        return 'native',...
    end
    local currentHook=original
    local hookCalls=0
    local methodCalls=0
    local method='FireServer'
    local function hookmm(_,kind,hook)
        assert(kind=='__namecall');hookCalls+=1
        local prev=currentHook;currentHook=hook;return prev
    end
    local function getMethod() methodCalls+=1;return method end
    local genv={}
    local function getgenv() return genv end
    local featureConnections={}
    local function disconnectFeatureConnection(key)
        if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
    end
    local TaskManager={Connect=function(_,fn)
        local c={Connected=true,fn=fn};function c:Disconnect() self.Connected=false end;return c
    end}
    local core={
        findMurderer=function() if role=='Murderer' then return target end end,
        getPlayerRole=function(p) if p==target then return role end return 'Sheriff' end,
        getPlayerWeapon=function(p,n)
            if p==LocalPlayer and n=='Gun' and gun.Parent==localChar then return gun end
            if p==LocalPlayer and n=='Knife' and knife.Parent==localChar then return knife end
        end,
        isPlayerAlive=function() return true end,isProtectedTarget=function() return false end,
        isWeaponPathClear=function() return true end,
        getGunOriginCFrame=function() return CFrame.new(Vector3.zero) end,
        getWeaponServiceModule=function() return ws end,
    }
    local state={mm2Core=core,mm2Prediction={knifeAim=function() return Vector3.new(30,2,3) end},
        hookMetamethod=hookmm,getNamecallMethod=getMethod,
        mm2PlanGunEndpoint=function() return {endpoint=Vector3.new(40,3,2)} end}
    local configData={states={},values={}}
    local cards={}
    local MM2Scroll={}
    local mm2Features={}
    local function createUniversalFeature(name,_,__,callback,config)
        local card={enabled=false,onToggle=callback}
        function card:SetStatus(v) self.status=v end
        function card:SetEnabled(v) self.enabled=v;self.onToggle(v) end
        cards[name]=card
        if config and config.configKey and configData.states[config.configKey] then
            task.defer(function() card:SetEnabled(true) end)
        end
        return card
    end
    local function addCycleOption(_,_,values,index,callback) callback(values[index]) end
    local function addToggleOption(_,_,value,callback) callback(value) end
    local function addTextOption(_,_,value,callback) callback(value);return {Parent={}} end
    local function addNumberOption(_,_,value,_,__,callback) callback(value) end
    local function addInformationOption() end
    local function setOptionVisible() end
    local function resolveTargetPlayer() return target end
    local function loadSilent()
'''
MIDDLE = r'''
    end
    local function loadKnife()
'''
TEST = r'''
    end
    equip(gun)
    local Silent=loadSilent();Silent.init({})
    local silent=cards['Silent AIM']
    assert(hookCalls==0 and currentHook==original, 'OFF must not install a global namecall hook')
    assert(ws.GetMouseTargetCFrame==nativePCFn and ws.GetTargetPosition==nativeMobileFn,
        'OFF must not wrap WeaponService')
    silent:SetEnabled(true)
    assert(hookCalls==1 and currentHook~=original, 'ON installs exactly one hook')
    near(ws:GetMouseTargetCFrame().Position.X,40)
    near(ws:GetTargetPosition(10,20).Position.X,40)
    local kind,a,b=currentHook(remote,'a','b')
    assert(kind=='native' and typeof(a)=='CFrame' and typeof(b)=='CFrame','Gun.Shoot must be rewritten')
    near(b.Position.X,40)
    local getBefore=methodCalls
    local other={ClassName='RemoteEvent',Name='Unrelated'}
    local _,x,y=currentHook(other,'x','y')
    assert(x=='x' and y=='y' and methodCalls==getBefore,'unrelated calls must pass untouched cheaply')
    method='InvokeServer';local _,untouched=currentHook(remote,'unchanged');assert(untouched=='unchanged');method='FireServer'
    silent:SetEnabled(false)
    assert(currentHook==original and ws.GetMouseTargetCFrame==nativePCFn and ws.GetTargetPosition==nativeMobileFn,
        'OFF restores unwrapped hooks')
    for _=1,4 do silent:SetEnabled(true);silent:SetEnabled(false);assert(currentHook==original) end

    -- A foreign wrapper installed after ours cannot be displaced; the old
    -- bridge becomes inert and a reinjection reuses it rather than stacking.
    silent:SetEnabled(true)
    local own=currentHook
    local foreign=function(self,...) return own(self,...) end
    hookmm(game,'__namecall',foreign)
    silent:SetEnabled(false)
    assert(currentHook==foreign,'OFF must preserve the foreign hook')
    local bridge=genv.__WURST_MM2_SILENT_NAMECALL_V1
    assert(bridge.installed and bridge.dispatch==nil and bridge.owner==nil,'nested bridge must be inert')
    local _,unchanged=foreign(remote,'unchanged');assert(unchanged=='unchanged')
    Silent.destroy()
    local before=hookCalls
    Silent=loadSilent();Silent.init({});silent=cards['Silent AIM']
    assert(hookCalls==before,'reinjection with OFF must not stack hooks')
    silent:SetEnabled(true)
    assert(hookCalls==before and currentHook==foreign,'ON must reuse the nested bridge')
    local _,_,rewritten=foreign(remote,'a','b');near(rewritten.Position.X,40)
    hookmm(game,'__namecall',own) -- foreign script unhooks itself
    silent:SetEnabled(false)
    assert(currentHook==original and bridge.installed==false,'direct hook removed once foreign owner releases it')

    local Knife=loadKnife();Knife.init({})
    local knifeCard=cards['Knife Throw']
    -- Silent first, Knife second; then turn Silent off first.
    role='Murderer';equip(gun);silent:SetEnabled(true);knifeCard:SetEnabled(true)
    near(ws:GetMouseTargetCFrame().Position.X,40)
    silent:SetEnabled(false)
    role='Innocent';equip(knife)
    near(ws:GetMouseTargetCFrame().Position.X,30)
    near(ws:GetTargetPosition(1,2).Position.X,30)
    knifeCard:SetEnabled(false)
    assert(ws.GetMouseTargetCFrame==nativePCFn and ws.GetTargetPosition==nativeMobileFn,
        'both OFF must unwind inactive inner wrappers')
    -- Reverse installation and shutdown order.
    knifeCard:SetEnabled(true);silent:SetEnabled(true)
    knifeCard:SetEnabled(false)
    role='Murderer';equip(gun)
    near(ws:GetMouseTargetCFrame().Position.X,40)
    near(ws:GetTargetPosition(1,2).Position.X,40)
    silent:SetEnabled(false)
    assert(ws.GetMouseTargetCFrame==nativePCFn and ws.GetTargetPosition==nativeMobileFn,
        'reverse toggle order must also restore both methods')
    -- A third party WeaponService wrapper stays in place and can still call
    -- the disabled original wrapper without referencing cleared locals.
    silent:SetEnabled(true)
    local previous=ws.GetMouseTargetCFrame
    local foreignPC=function(...) return previous(...) end
    ws.GetMouseTargetCFrame=foreignPC
    silent:SetEnabled(false)
    assert(ws.GetMouseTargetCFrame==foreignPC and ws:GetMouseTargetCFrame()==nativePC)
    ws.GetMouseTargetCFrame=nativePCFn
    Knife.destroy();Silent.destroy()

    -- Executors without hookmetamethod still use the PC/mobile WeaponService
    -- route, and a restored ON config installs the hook only when enabled.
    state.hookMetamethod=nil
    local missing=loadSilent();missing.init({});local card=cards['Silent AIM']
    local calls=hookCalls;card:SetEnabled(true)
    assert(hookCalls==calls and currentHook==original)
    near(ws:GetMouseTargetCFrame().Position.X,40);near(ws:GetTargetPosition(1,2).Position.X,40)
    card:SetEnabled(false);missing.destroy()
    state.hookMetamethod=hookmm
    genv=setmetatable({}, {__newindex=function() error('read-only environment') end})
    local restricted=loadSilent();restricted.init({});local restrictedCard=cards['Silent AIM']
    restrictedCard:SetEnabled(true)
    assert(currentHook~=original,'read-only getgenv should fall back to a private bridge')
    near(ws:GetTargetPosition(1,2).Position.X,40)
    restrictedCard:SetEnabled(false);restricted.destroy()
    assert(currentHook==original)
    genv={}
    calls=hookCalls
    configData.states['MM2.SilentAIM']=true
    local restored=loadSilent();restored.init({});local restoredCard=cards['Silent AIM']
    assert(hookCalls==calls,'saved ON is enabled by deferred restoration, not by initialization itself')
    flush()
    assert(restoredCard.enabled and hookCalls==calls+1 and currentHook~=original)
    restored.destroy()
    assert(currentHook==original and ws.GetMouseTargetCFrame==nativePCFn)
    print('PASS MM2 hook lifecycle: OFF/ON/restored, PC/mobile, foreign hooks, reinjection and Knife toggle orders')
end
'''


def main() -> None:
    code = PRELUDE + SETUP + SILENT + MIDDLE + KNIFE + TEST
    with tempfile.TemporaryDirectory(prefix='mm2-hook-') as td:
        path = Path(td) / 'test.luau'
        path.write_text(code)
        subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
