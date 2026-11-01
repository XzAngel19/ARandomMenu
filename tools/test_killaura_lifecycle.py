#!/usr/bin/env python3
"""Execute KillAura's real toggle/respawn/unload lifecycle without sending attacks."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/universal/Combat/KillAura.lua').read_text()
script=r'''
local function signal()
    local listeners={};local event={}
    function event:Connect(fn)
        local connection={};listeners[connection]=fn
        function connection:Disconnect() listeners[self]=nil end
        return connection
    end
    function event:Fire(...) for _,fn in pairs(listeners) do fn(...) end end
    function event:Count() local n=0;for _ in pairs(listeners) do n+=1 end;return n end
    return event
end
local delayed={}
local task={defer=function(fn) table.insert(delayed,fn) end}
local function flush() while #delayed>0 do table.remove(delayed,1)() end end
local tool={Name='Knife',Activated=signal(),IsA=function(_,kind) return kind=='Tool' end}
local character={GetChildren=function() return {tool} end}
local backpack={ChildAdded=signal(),GetChildren=function() return {} end}
local player={Character=character,CharacterAdded=signal(),FindFirstChild=function(_,name) if name=='Backpack' then return backpack end end}
local Enum={KeyCode={Unknown='Unknown'}}
local Color3={fromRGB=function(...) return {...} end}
local frameConnection
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
    function card:SetStatus(value) self.status=value end
    function card:Notify() end
    function card:Clean(item) table.insert(self.cleanups,item) end
    function card:Event(event,fn) self:Clean(event:Connect(fn)) end
    function card:Loop(fn)
        frameConnection={callback=fn,active=true,Disconnect=function(self) self.active=false end}
        self:Clean(frameConnection)
    end
    function card:Toggle(on)
        if self.Enabled==on then return end
        self.Enabled=on
        if not on then
            for i=#self.cleanups,1,-1 do
                local item=self.cleanups[i]
                if type(item)=='function' then item() else item:Disconnect() end
            end
            table.clear(self.cleanups)
        end
        definition.Function(on)
    end
    return card
end}}}
local host={LocalPlayer=player,UserInputService={},workspace={},state={teamCheck={}}}
'''+ '\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({host=host,framework=framework,entity={}})
assert(not card.Enabled and tool.Activated:Count()==0 and player.CharacterAdded:Count()==0, 'OFF at injection')
card:Toggle(true)
assert(card.Enabled and frameConnection.active and tool.Activated:Count()==1 and player.CharacterAdded:Count()==1)
player.CharacterAdded:Fire();assert(#delayed==1)
card:Toggle(false)
assert(not frameConnection.active and tool.Activated:Count()==0 and player.CharacterAdded:Count()==0)
flush();assert(tool.Activated:Count()==0, 'deferred respawn must not reattach listeners after OFF')
card:Toggle(true);assert(tool.Activated:Count()==1)
local currentFrame=frameConnection
Module.destroy()
assert(not card.Enabled and not currentFrame.active and tool.Activated:Count()==0 and player.CharacterAdded:Count()==0,
    'unload while ON must turn off the real local card and remove all watchers')
Module.init({host=host,framework=framework,entity={}})
local adapterEvents={}
card.CombatAdapter=function(value) table.insert(adapterEvents,value) end
card:Toggle(true);Module.destroy()
assert(#adapterEvents==2 and adapterEvents[1]==true and adapterEvents[2]==false,
    'an installed game-specific adapter receives OFF on unload')
print('PASS KillAura lifecycle: inert injection, deferred OFF, real card/adapter unload, watcher cleanup')
'''
with tempfile.TemporaryDirectory(prefix='killaura-lifecycle-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
