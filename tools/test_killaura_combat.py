#!/usr/bin/env python3
"""Run the real universal KillAura target/swing loop with behavioral mocks."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'src/games/universal/Combat/KillAura.lua').read_text()
script = r'''
local now=1
local os={clock=function() return now end}
local task={defer=function(fn) fn() end}
local function signal()
    return {Connect=function(_,fn) return {Disconnect=function() end} end}
end
local handle={Name='Handle',IsA=function(_,kind) return kind=='BasePart' end}
local swings=0
local activateFails=false
local tool={Name='Sword',Enabled=true,Activated=signal(),IsA=function(_,kind) return kind=='Tool' end,
    FindFirstChild=function(_,name) if name=='Handle' then return handle end end,
    GetDescendants=function() return {handle} end,
    Activate=function() if activateFails then error('temporary activation error') end swings+=1 end}
local character={GetChildren=function() return {tool} end}
local backpack={ChildAdded=signal(),GetChildren=function() return {} end}
local localPlayer={Character=character,CharacterAdded=signal(),
    FindFirstChild=function(_,name) if name=='Backpack' then return backpack end end}
local function target(name,id)
    local part={name=name}
    local model={part=part}
    local player={Name=name,DisplayName=name,UserId=id}
    local root={Position={},CFrame={target=part}}
    return {Player=player,Character=model,RootPart=root,Health=100}
end
local ignored=target('Ignored',1)
local ally=target('Ally',2)
local enemy=target('Enemy',3)
local candidates={ignored,enemy}
local entity={LocalEntity={RootPart=nil},IsAlive=function() return true end,Refresh=function() end,
    InRange=function(_,query)
        local result=table.clone(candidates)
        while query.Limit and #result>query.Limit do table.remove(result) end
        return result
    end,
    VisibleFrom=function() return true end}
local contacts={}
firetouchinterest=function(_,part,phase) table.insert(contacts,{part=part,phase=phase}) end
local workspace={GetPartBoundsInBox=function(_,frame) return {frame.target} end}
local OverlapParams={new=function() return {} end}
local Vector3={new=function(x,y,z) return {X=x,Y=y,Z=z} end}
local Enum={KeyCode={Unknown='Unknown'},RaycastFilterType={Include='Include'}}
local Color3={fromRGB=function(...) return {...} end}
local selectedCandidate={label='backup'}
local backupActivations=0
local weapons={Find=function() return nil end,Best=function() return selectedCandidate end,
    Activate=function(_,candidate,target)
        assert(candidate==selectedCandidate and target==enemy)
        backupActivations+=1;return true
    end,Labels=function() return {} end,SetAllowEquip=function() end}
local card
local framework={Categories={Exploits={CreateModule=function(_,definition)
    card={Enabled=false,Options={},cleanups={}}
    local function option(self,d)
        local value={Value=d.List and d.List[d.Index or 1] or d.Default,Selected={}}
        self.Options[d.Name]=value;return value
    end
    card.CreateDropdown=option;card.CreateBind=option;card.CreateSlider=option;card.CreateList=option
    card.CreateTextBox=option;card.CreateButton=option;card.CreateToggle=option;card.CreateColor=option
    function card:CreateNote() end
    function card:SetStatus(text) self.status=text end
    function card:Notify() end
    function card:Clean(item) table.insert(self.cleanups,item) end
    function card:Event(event,fn) self:Clean(event:Connect(fn)) end
    function card:Loop(fn) self.tick=fn;self:Clean({Disconnect=function() self.tick=nil end}) end
    function card:Toggle(on)
        if self.Enabled==on then return end
        self.Enabled=on
        if not on then
            for i=#self.cleanups,1,-1 do
                local x=self.cleanups[i];if type(x)=='function' then x() else x:Disconnect() end
            end
            table.clear(self.cleanups)
        end
        definition.Function(on)
    end
    return card
end}}}
local host={LocalPlayer=localPlayer,UserInputService={},workspace=workspace,
    state={teamCheck={isSameTeam=function(player) return player==ally.Player end}}}
''' + '\nlocal Module=(function()\n' + source + '\nend)()\n' + r'''
Module.init({host=host,framework=framework,entity=entity,weapons=weapons})
card.Options['Rotation'].Value='Off'
card.Options['Max targets'].Value=1
card.Options['Ignore players'].Value='Ignored'
card:Toggle(true);card.tick()
assert(swings==1 and #contacts==2 and contacts[1].part==enemy.Character.part,
    'ignored nearest player must not consume the only valid target slot')
assert(contacts[1].phase==0 and contacts[2].phase==1, 'touch begins before it ends')
candidates={ally,enemy};card.Options['Ignore players'].Value=''
contacts={};now+=1;card.tick()
assert(swings==2 and contacts[1].part==enemy.Character.part,
    'post-filtered ally must not consume the only valid target slot')
candidates={enemy};tool.Enabled=false;now+=1;card.tick()
assert(backupActivations==1, 'disabled equipped tool must allow a real alternate weapon')
tool.Enabled=true;activateFails=true;now+=1;card.tick()
assert(backupActivations==2, 'failed Activate must allow alternate weapon and not stop the loop')
card:Toggle(false);assert(card.tick==nil)
Module.destroy()
print('PASS KillAura combat: post-filter target limits, correct touch order, disabled/failed tool fallback and OFF')
'''
with tempfile.TemporaryDirectory(prefix='killaura-combat-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
