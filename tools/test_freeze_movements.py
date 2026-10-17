#!/usr/bin/env python3
"""Run the real FreezeMovements module with strict, deterministic Luau mocks."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Movement/FreezeMovements.lua').read_text()
PRELUDE = r'''
local now = 0
local os = {clock=function() return now end}
local Vector3 = {zero={Magnitude=0}}
local Enum = {HumanoidStateType={Jumping='Jumping',Dead='Dead'},AnimationPriority={Core='Core',Movement='Movement',Action='Action',Idle='Idle'}}
local function typeof(v) return type(v)=='table' and v.instance and 'Instance' or type(v) end
local function signal()
    local s={listeners={}}
    function s:Connect(fn)
        local c={Connected=true,fn=fn}
        function c:Disconnect() self.Connected=false end
        table.insert(self.listeners,c)
        return c
    end
    function s:Fire(...)
        for _,c in ipairs(self.listeners) do if c.Connected then c.fn(...) end end
    end
    return s
end
local tracks={}
local resolvedDestroyed=0
local delayedJobs=nil
local task={spawn=function(fn) if delayedJobs then table.insert(delayedJobs,fn) else fn() end end}
local game={GetObjects=function(_,url)
    assert(url=='rbxassetid://12345')
    return {{AnimationId='rbxassetid://777777',IsA=function(_,class) return class=='Animation' end,
        GetDescendants=function() return {} end,Destroy=function() resolvedDestroyed+=1 end}}
end}
local animator={AnimationPlayed=signal(),GetPlayingAnimationTracks=function() return tracks end}
local root={Parent=true,Anchored=false,AssemblyLinearVelocity={Magnitude=0}}
local danceFolder={Name='dance2'}
local danceAnimation={instance=true,Name='Animation1',AnimationId='rbxassetid://182436842',Parent=danceFolder,IsA=function(_,class) return class=='Animation' end}
local animate={Name='Animate',GetDescendants=function() return {danceAnimation} end}
danceFolder.Parent=animate
local character={FindFirstChild=function(_,name) if name=='Animate' then return animate end end,FindFirstChildWhichIsA=function() return nil end}
local humanoid={EmoteTriggered=signal(),Parent=character,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,AutoRotate=true,
    FindFirstChildOfClass=function() return animator end,
    GetAppliedDescription=function() return {GetEmotes=function() return {Salute={12345}} end,Destroy=function() end} end}
local tick,mode,toggle,feature
local checkboxes={}
local motionHeading=nil
local connections={}
local stored={values={["Movement.FreezeMovements.Freezemode"]="Freeze Emotes"},states={}}
local localPlayer={CharacterAdded=signal(),CharacterRemoving=signal()}
local host={
    LocalPlayer=localPlayer,
    configData=stored,
    TaskManager={Connect=function(_,fn) tick=fn; return {Disconnect=function() tick=nil end} end},
    featureConnections=connections,
    disconnectFeatureConnection=function(key) if connections[key] then connections[key]:Disconnect(); connections[key]=nil end end,
    getCharacterParts=function() return nil,humanoid,root end,
    createUniversalFeature=function(_,_,_,fn)
        toggle=fn; feature={enabled=false,SetStatus=function(self,s) self.status=s end};return feature
    end,
    addCycleOption=function(_,_,values,_,fn) assert(#values==2 and values[1]=='Anchor' and values[2]=='Motion');mode=fn;fn(stored.values['Movement.FreezeMovements.Freezemode'] or 'Anchor') end,
    addToggleOption=function(_,name,default,fn) checkboxes[name]=fn;fn(default);return {Parent={Visible=true}} end,
    addSectionOption=function(_,name) assert(name=='Motion settings');motionHeading={Visible=true};return motionHeading end,
    addInformationOption=function() end,
}
local function track(name,id,priority)
    local t={Name=name,Animation={instance=true,Name=name,AnimationId='rbxassetid://'..id},
        Priority=priority,IsPlaying=true,Looped=true,plays=0,stops=0,TimePosition=1}
    function t:Play() self.plays+=1;self.IsPlaying=true;animator.AnimationPlayed:Fire(self) end
    function t:Stop() self.stops+=1;self.IsPlaying=false end
    function t:Destroy() self.destroyed=true end
    function t:AdjustSpeed(speed) self.Speed=speed end
    return t
end
local loaded={}
function animator:LoadAnimation(animation)
    local t=track(animation.Name,0,'Core')
    t.Animation=animation;t.IsPlaying=false
    table.insert(loaded,t)
    return t
end
'''
TESTS = r'''
Module.init({host=host})
assert(stored.values['Movement.FreezeMovements.Freezemode']=='Motion','legacy emote mode must not anchor the player on upgrade')
assert(stored.states['Movement.FreezeMovements.FreezeEmotes']==true)
mode('Anchor')
feature.enabled=true;toggle(true);tick()
assert(root.Anchored and humanoid.WalkSpeed==16 and humanoid.JumpHeight==7.2)
assert(not motionHeading.Visible)
mode('Motion')
assert(motionHeading.Visible)
assert(not root.Anchored and humanoid.WalkSpeed==16 and humanoid.JumpHeight==7.2)
tick() -- binds AnimationPlayed and reads avatar emotes
local custom=track('Salute',999,'Idle')
local attack=track('Stab',222,'Action')
local idOnly=track('Animation',12345,'Core')
root.AssemblyLinearVelocity={Magnitude=16}
tracks={}
animator.AnimationPlayed:Fire(custom);custom.IsPlaying=false;tick()
assert(#loaded==1 and loaded[1].IsPlaying)
animator.AnimationPlayed:Fire(attack);attack.IsPlaying=false;tick()
assert(#loaded==1,'attack must not replace the held emote')
animator.AnimationPlayed:Fire(idOnly);idOnly.IsPlaying=false;tick()
assert(#loaded==2 and loaded[1].destroyed and loaded[2].IsPlaying)
local dance=track('Animation1',182436842,'Core');dance.Looped=false
animator.AnimationPlayed:Fire(dance);dance.IsPlaying=false;tick()
assert(#loaded==3 and loaded[2].destroyed and loaded[3].IsPlaying)
assert(custom.plays==0 and idOnly.plays==0 and attack.plays==0 and dance.plays==0)
assert(loaded[3].Looped and loaded[3].Priority=='Action')
tracks=loaded;now=2;tick();tick()
assert(#loaded==3,'Animate cancellation must not recreate tracks or capture managed tracks')
humanoid.GetState=function() return 'Jumping' end
tick();assert(not loaded[3].destroyed and loaded[3].IsPlaying,'jump must retain the held emote')
humanoid.GetState=function() return 'Running' end
-- Disable must release revived tracks and the event connection.
feature.enabled=false;toggle(false)
assert(dance.stops==1 and attack.stops==0,'OFF stops original emote source but never an attack')
for _,t in ipairs(loaded) do assert(t.stops==1 and t.destroyed) end
for _,c in ipairs(animator.AnimationPlayed.listeners) do assert(not c.Connected) end
assert(not tick)
-- If OFF occurs before Animate cancelled the original, that source must
-- stop too; there may be no managed replacement at all.
local source=track('Dance2',182436842,'Core')
tracks={source};feature.enabled=true;toggle(true);tick()
local lateSource=track('Dance3',182436842,'Core')
tracks={source,lateSource,attack} -- recognized source arriving before the next sampler tick
feature.enabled=false;toggle(false)
assert(source.stops==1 and not source.IsPlaying,'OFF must stop an original still-playing dance')
assert(lateSource.stops==1 and attack.stops==0,'OFF must also scan the watched Animator')
-- Catalog item 12345 resolves to a different animation, 777777.
local catalog=track('Animation',777777,'Action')
tracks={catalog};feature.enabled=true;toggle(true);tick()
local before=#loaded
catalog.IsPlaying=false;tick()
assert(#loaded==before+1 and loaded[#loaded].IsPlaying,'resolved UGC animation must survive walking')
feature.enabled=false;toggle(false)
assert(catalog.stops==1 and loaded[#loaded].destroyed)
assert(resolvedDestroyed>0,'catalog inspection must destroy its temporary containers')
-- A new UGC emote not present in the initial description is identified by
-- the actual engine track, NOT its name/priority or catalog asset ID.
tracks={};feature.enabled=true;toggle(true);tick()
local ugc=track('Animation',888888,'Action')
local count=#loaded
humanoid.EmoteTriggered:Fire(true,ugc);ugc.IsPlaying=false;tick()
assert(#loaded==count+1 and loaded[#loaded].IsPlaying,'engine-reported UGC must be retained')
feature.enabled=false;toggle(false)
assert(ugc.stops==1 and loaded[#loaded].destroyed,'UGC OFF stops source and replacement')
for _,connection in ipairs(humanoid.EmoteTriggered.listeners) do assert(not connection.Connected) end
-- An engine-denied event must not break catalog resolution or cleanup.
local engineEvent=humanoid.EmoteTriggered;humanoid.EmoteTriggered=nil
local fallback=track('Animation',777777,'Action')
tracks={fallback};feature.enabled=true;toggle(true);tick()
feature.enabled=false;toggle(false);assert(fallback.stops==1)
humanoid.EmoteTriggered=engineEvent
delayedJobs={};tracks={};feature.enabled=true;toggle(true);tick()
assert(#delayedJobs==1)
feature.enabled=false;toggle(false)
local destroyedBefore=resolvedDestroyed
for _,job in ipairs(delayedJobs) do job() end
assert(resolvedDestroyed==destroyedBefore,'stale catalog job must not load assets after OFF')
delayedJobs=nil
-- The two Motion checkboxes are independent of movement physics.
mode('Motion');checkboxes['Freeze Emotes'](false);checkboxes['Freeze Animation'](true)
feature.enabled=true;toggle(true)
local walk=track('Walk',444,'Movement');walk.Speed=.8;walk.TimePosition=.7
local stab=track('Stab',222,'Action')
tracks={walk,stab};tick()
local held=loaded[#loaded]
assert(held.Animation==walk.Animation and held.Looped and held.Priority=='Action')
assert(held.Speed==.8 and held.TimePosition==.7 and held.IsPlaying)
local jump=track('Jump',555,'Core');walk.IsPlaying=false;tracks={jump,stab}
humanoid.GetState=function() return 'Jumping' end
tick();tick()
assert(loaded[#loaded]==held and held.IsPlaying,'walking clip must survive a jump without recapture')
assert(held.TimePosition==.7 and held.plays==1,'do not seek/reset Play every frame')
assert(not root.Anchored and humanoid.WalkSpeed==16 and humanoid.JumpHeight==7.2)
checkboxes['Freeze Animation'](false)
assert(held.destroyed and not held.IsPlaying and stab.stops==0 and jump.stops==0)
checkboxes['Freeze Animation'](true);tracks={walk};walk.IsPlaying=true;tick();held=loaded[#loaded]
mode('Anchor');tick()
assert(held.destroyed and root.Anchored and not motionHeading.Visible,'mode switch releases motion before anchoring')
mode('Motion');tick()
assert(not root.Anchored and motionHeading.Visible,'Motion must restore Anchor ownership')
local oldMotion=loaded[#loaded]
local oldRoot=root
root={Parent=true,Anchored=false,AssemblyLinearVelocity={Magnitude=0}}
local run=track('Run',666,'Movement');tracks={run};tick()
assert(oldMotion.destroyed and loaded[#loaded].Animation==run.Animation,'new root must release and recapture motion')
feature.enabled=false;toggle(false)
assert(not root.Anchored and not oldRoot.Anchored)
root.Anchored=true;mode('Anchor');feature.enabled=true;toggle(true);tick()
feature.enabled=false;toggle(false)
assert(root.Anchored,'pre-existing anchored state must be restored, not forced false')
root.Anchored=false
-- Real respawn: no character, different Humanoid AND Animator; keep ON.
mode('Motion');checkboxes['Freeze Emotes'](true);checkboxes['Freeze Animation'](true)
feature.enabled=true;toggle(true);tracks={run};tick()
local beforeDeath=loaded[#loaded]
local previousAnimator=animator
humanoid.GetState=function() return 'Dead' end
tick();assert(beforeDeath.destroyed,'death releases the held clip')
localPlayer.CharacterRemoving:Fire(character)
humanoid=nil;root=nil
for _=1,5 do now+=.04;tick() end
local animateAfterRespawn=animate;animate=nil
character={FindFirstChild=function(_,name) if name=='Animate' then return animate end end,FindFirstChildWhichIsA=function() return nil end}
local newAnimator={AnimationPlayed=signal(),GetPlayingAnimationTracks=function() return tracks end,LoadAnimation=previousAnimator.LoadAnimation}
local availableAnimator=nil
local described=false
humanoid={Parent=character,Health=100,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,AutoRotate=true,
    GetState=function() return 'Running' end,
    FindFirstChildOfClass=function() return availableAnimator end,
    GetAppliedDescription=function() return {GetEmotes=function() return described and {Salute={12345}} or {} end,Destroy=function() end} end}
root={Parent=true,Anchored=false,AssemblyLinearVelocity={Magnitude=16}}
tracks={};localPlayer.CharacterAdded:Fire(character);assert(tick,'respawn rearms scheduler without toggling checkbox')
tick() -- Animator/Animate may not exist at CharacterAdded
availableAnimator=newAnimator;animator=newAnimator
tick()
local newWalk=track('Walk',444,'Movement');tracks={newWalk};tick()
local newHeld=loaded[#loaded];assert(newHeld.Animation==newWalk.Animation and newHeld.IsPlaying)
-- Denied EmoteTriggered, late avatar description and immediately cancelled UGC.
now+=.3;described=true
local newEmote=track('Animation',777777,'Action')
newAnimator.AnimationPlayed:Fire(newEmote);newEmote:Stop();tracks={};tick()
local newEmoteHeld=loaded[#loaded]
assert(newEmoteHeld.Animation==newEmote.Animation and newEmoteHeld.IsPlaying,'new-character UGC must be recovered even when movement cancelled the original track')
local resolvedBefore=resolvedDestroyed
now+=3;tick();now+=3;tick()
assert(resolvedDestroyed==resolvedBefore,'periodic metadata retry must not download the same catalog asset repeatedly')
animate=animateAfterRespawn;tick();assert(newEmoteHeld.IsPlaying,'late Animate must not drop held tracks')
local liveAdded=0
for _,c in ipairs(localPlayer.CharacterAdded.listeners) do if c.Connected then liveAdded+=1 end end
assert(liveAdded==1,'rearm must not accumulate character listeners')
for _,c in ipairs(previousAnimator.AnimationPlayed.listeners) do assert(not c.Connected,'old Animator is detached') end
-- Animator replacement without a character event must also release/rebind.
availableAnimator=nil;tick()
assert(newHeld.destroyed and newEmoteHeld.destroyed)
local finalAnimator={AnimationPlayed=signal(),GetPlayingAnimationTracks=function() return tracks end,LoadAnimation=previousAnimator.LoadAnimation}
availableAnimator=finalAnimator;animator=finalAnimator
local finalWalk=track('Walk',444,'Movement');tracks={finalWalk};tick()
local finalHeld=loaded[#loaded];assert(finalHeld.Animation==finalWalk.Animation and finalHeld.IsPlaying)
feature.enabled=false;toggle(false)
assert(finalHeld.destroyed)
assert(newHeld.destroyed and newEmoteHeld.destroyed and not tick,'OFF releases all new-character ownership')
for _,c in ipairs(localPlayer.CharacterAdded.listeners) do assert(not c.Connected) end
Module.destroy();assert(humanoid.JumpHeight==7.2 and humanoid.WalkSpeed==16 and not tick)
print('PASS FreezeMovements: UGC engine tracks, catalog-to-animation resolution, denied-event fallback, mode restoration, avatar names/IDs, immediate tracks, attack exclusion, duplicate prevention, death/no-character/new Humanoid/new Animator/late Animate, cached catalog, disable cleanup, Anchor/Motion, independent checkboxes, locomotion lock through jump, JumpHeight, destroy')
'''


def main():
    with tempfile.TemporaryDirectory(prefix='freeze-regression-') as tmp:
        path = Path(tmp) / 'test.luau'
        path.write_text(PRELUDE + '\nlocal Module=(function()\n' + SOURCE + '\nend)()\n' + TESTS)
        subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)


if __name__ == '__main__':
    main()
