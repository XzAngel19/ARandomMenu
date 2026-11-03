#!/usr/bin/env python3
"""Exercise real Shaders + Framework with a simulated Roblox client.

The mocks model ownership, asynchronous downloads, streaming and bounded work;
they do not render pixels, measure GPU/FPS, or prove Delta asset compatibility.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHADERS = (ROOT / "src/games/universal/Render/Shaders.lua").read_text()
FRAMEWORK = (ROOT / "src/libraries/Framework.lua").read_text()

PRELUDE = r'''
Color3 = {}
local colorMeta = {__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end}
function Color3.new(r, g, b) return setmetatable({R=r or 0, G=g or 0, B=b or 0}, colorMeta) end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
function colorMeta.__index(_, key)
    if key == "Lerp" then
        return function(a, b, t) return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t) end
    end
end
local vectorMeta = {}
function vectorMeta.__index(v, key)
    if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
end
function vectorMeta.__add(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
function vectorMeta.__sub(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
Vector3 = {new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end}
Vector2 = {new=function(x,y) return {X=x,Y=y} end}
NumberSequence = {new=function(v) return {Value=v} end}
NumberRange = {new=function(a,b) return {Min=a,Max=b or a} end}
ColorSequence = {new=function(v) return {Value=v} end}
Content = {fromUri=function(uri) return {Uri=uri} end}
RaycastParams = {new=function() return {} end}
OverlapParams = {new=function() return {} end}
-- NormalIds are EnumItems, not strings: table.concat on them would fail in Roblox.
local function item(name) return setmetatable({}, {__tostring=function() return name end}) end
Enum = {
    ParticleEmitterShape={Box=item("Box")}, ParticleEmitterShapeStyle={Volume=item("Volume")},
    NormalId={Bottom=item("Bottom"),Top=item("Top"),Front=item("Front"),Back=item("Back"),
        Left=item("Left"),Right=item("Right")},
    ParticleOrientation={VelocityParallel=item("VelocityParallel"),FacingCamera=item("FacingCamera")},
    RaycastFilterType={Exclude=item("Exclude")}, PartType={Block=item("Block"), Ball=item("Ball")},
    Material={},
}
for _, name in ipairs({"Plastic","SmoothPlastic","Concrete","Asphalt","Pavement","Wood",
    "WoodPlanks","Brick","Grass","Marble","Glass","Metal"}) do Enum.Material[name] = item(name) end

local deferred, spawned = {}, {}
task = {
    defer=function(fn) table.insert(deferred,fn) end,
    spawn=function(fn) table.insert(spawned,fn) end,
}
local function flushDeferred()
    local n=0
    while #deferred>0 do
        n+=1; assert(n<100,"deferred events must settle")
        table.remove(deferred,1)()
    end
end
local function runSpawned()
    assert(#spawned>0,"asset job expected")
    table.remove(spawned,1)()
end
local function runAllSpawned()
    local n=0
    while #spawned>0 do n+=1; assert(n<100,"jobs must settle"); runSpawned() end
end
local function signal()
    local callbacks={}
    return {
        Connect=function(_,fn)
            table.insert(callbacks,fn)
            return {Disconnect=function()
                for i,cb in ipairs(callbacks) do if cb==fn then table.remove(callbacks,i); break end end
            end}
        end,
        Fire=function(_,...) for _,fn in ipairs(table.clone(callbacks)) do fn(...) end end,
        Count=function() return #callbacks end,
    }
end
local function container(name,class)
    local obj={Name=name, ClassName=class, children={}, ChildAdded=signal(), ChildRemoved=signal()}
    function obj:GetChildren() return table.clone(self.children) end
    function obj:FindFirstChildOfClass(wanted)
        for _, child in ipairs(self.children) do if child:IsA(wanted) and not child.destroyed then return child end end
    end
    function obj:IsA(wanted)
        return self.ClassName==wanted or (wanted=="BasePart" and (self.ClassName=="Part" or self.ClassName=="MeshPart"))
            or (wanted=="Decal" and self.ClassName=="Texture")
    end
    return obj
end
local lighting=container("Lighting","Lighting")
lighting.EnvironmentDiffuseScale=0.2; lighting.EnvironmentSpecularScale=0.1
lighting.ShadowSoftness=0.1; lighting.GlobalShadows=false; lighting.ExposureCompensation=0
local camera=container("Camera","Camera")
camera.CFrame={Position=Vector3.new(0,12,0)}
local world=container("Workspace","Workspace")
world.CurrentCamera=camera
local roof={Transparency=0,IsA=function(_,name) return name=="BasePart" end}
local rayCount,groundRayCount,isCovered,roofHeight,groundHit=0,0,false,nil,nil
function world:Raycast(origin,direction,params)
    assert(params.FilterType==Enum.RaycastFilterType.Exclude and #params.FilterDescendantsInstances>=1)
    if direction.Y<0 then
        groundRayCount+=1
        return if groundHit then {Instance=groundHit} else nil
    end
    rayCount+=1
    if isCovered or (roofHeight and origin.Y<=roofHeight and origin.Y+direction.Y>=roofHeight) then return {Instance=roof} end
    return nil
end
local queryParts,queryCount,queryFail = {},0,false
function world:GetPartBoundsInRadius(position,radius,params)
    queryCount+=1
    assert(radius==120 and params.MaxParts==240 and params.FilterType==Enum.RaycastFilterType.Exclude)
    if queryFail then error("radius query denied") end
    return table.clone(queryParts)
end
local function children(parent,class)
    local found={}
    for _, obj in ipairs(parent.children) do
        if not obj.destroyed and (not class or obj.ClassName==class) then table.insert(found,obj) end
    end
    return found
end
local created={}
Instance={fail={},failAt={}}
function Instance.new(class)
    if Instance.fail[class] or Instance.failAt[class]==(created[class] or 0)+1 then
        error("creation denied for "..class)
    end
    created[class]=(created[class] or 0)+1
    local obj=container(class,class)
    obj.destroyed=false
    local store={Enabled=true,Brightness=0,Contrast=0,Saturation=0,TintColor=Color3.new(1,1,1),
        Density=0.2,Offset=0,Haze=0.5,Glare=0,Color=Color3.new(1,1,1),Decay=Color3.new(0.5,0.5,0.5),
        Anchored=false,CanCollide=true,CanQuery=true,CanTouch=true,Transparency=0,Reflectance=0,
        Material=Enum.Material.Plastic,MaterialVariant="",Shape=Enum.PartType.Block,
        Size=Vector3.new(4,1,4),CFrame={UpVector=Vector3.new(0,1,0)},WaterReflectance=0.12}
    function obj:Destroy()
        self.Parent=nil; self.destroyed=true
        for _, child in ipairs(table.clone(self.children)) do child:Destroy() end
    end
    setmetatable(obj,{
        __index=function(_,key) return store[key] end,
        __newindex=function(_,key,value)
            if key=="Parent" then
                local old=store.Parent
                if old then for i,child in ipairs(old.children) do if child==obj then table.remove(old.children,i);break end end end
                store.Parent=value
                if old and old.ChildRemoved then old.ChildRemoved:Fire(obj) end
                if value then table.insert(value.children,obj); if value.ChildAdded then value.ChildAdded:Fire(obj) end end
            else store[key]=value end
        end,
    })
    return obj
end
local terrain=Instance.new("Terrain"); terrain.Name="Terrain"; terrain.Parent=world
local localCharacter=Instance.new("Model"); localCharacter.Name="LocalCharacter"; localCharacter.Parent=world
local humanoid=Instance.new("Humanoid"); humanoid.Parent=localCharacter

game={GetService=function(_,name) if name=="Lighting" then return lighting end end}
local warnings={}
warn=function(text) table.insert(warnings,tostring(text)) end
local notifications,features,handles={},{},{}
local manager={}
function manager:Connect(callback,_,label)
    local h={Connected=true,callback=callback,label=label}
    function h:Disconnect() self.Connected=false end
    table.insert(handles,h); return h
end
local function activeHandles(label)
    local n=0
    for _,h in ipairs(handles) do if h.Connected and (not label or h.label==label) then n+=1 end end
    return n
end
local function frames(count,dt)
    for _=1,count do
        local before=created.Texture or 0
        for _,h in ipairs(table.clone(handles)) do if h.Connected then h.callback(dt or 0.05) end end
        assert((created.Texture or 0)-before<=8,"at most four candidates/two faces each per frame")
        flushDeferred()
    end
end
local host={Lighting=lighting,workspace=world,TaskManager=manager,LocalPlayer={Character=localCharacter},state={},
    notify=function(text) table.insert(notifications,text) end}
function host.createUniversalFeature(name,_,_,toggle,options)
    local feature={name=name,configKey=options.configKey,toggle=toggle}
    function feature:SetStatus(status) self.status=status end
    features[name]=feature; return feature
end
function host.addCycleOption(_,_,_,_,callback) return {callback=callback} end
function host.addToggleOption(_,_,_,callback) return {callback=callback} end
function host.addNumberOption(_,_,_,_,_,callback) return {callback=callback} end
function host.addColorOption(_,_,_,callback) return {callback=callback} end
function host.addActionOption(_,_,callback) return {callback=callback} end
function host.addInformationOption() end
function host.setOptionVisible(_,row,visible) row.visible=visible end
local assetRequests={}
host.state.resolveAsset=function(name) table.insert(assetRequests,name); return "custom://"..name end
local function byName(parent,name)
    for _,obj in ipairs(parent.children) do if obj.Name==name and not obj.destroyed then return obj end end
end
local function renderable(effect) return effect and not effect.destroyed and effect.Enabled
    and (effect.Parent==lighting or effect.Parent==camera) end
local function part(name,material,size,parent)
    local p=Instance.new("Part"); p.Name=name; p.Material=material; p.Size=size; p.Anchored=true; p.Parent=parent or world
    return p
end
local function textureOf(p) return byName(p,"ARMShaderTexture") end
local function pass(name) print("PASS\tshaders: "..name) end
'''

BODY = r'''
local Framework=assert(loadstring(FRAMEWORK_SOURCE))()
local framework=Framework.init(host)
local Shaders=assert(loadstring(SHADERS_SOURCE))()
local card=Shaders.init({framework=framework,host=host})
assert(card==framework.Modules.Shaders)
assert(not card.Options.Look and not card.Options.Weather and not card.Options.Advanced,
    "no old look or mode selector remains")
local names={"Surface textures","Glass reflections","Fog","Rain","Snow","Falling leaves","Dust motes","Wet surfaces","Water reflections"}
assert(#card.OptionMetadata==#names)
for i,name in ipairs(names) do assert(card.OptionMetadata[i].label==name and card.OptionMetadata[i].type=="toggle") end
assert(card.Options["Surface textures"].Value and card.Options["Glass reflections"].Value)
for _,name in ipairs({"Fog","Rain","Snow","Falling leaves","Dust motes","Wet surfaces","Water reflections"}) do
    assert(not card.Options[name].Value)
end
pass("simple individual toggles, no Look/preset/weather selector")

local gameEffect=Instance.new("ColorCorrectionEffect"); gameEffect.Name="GameOwned"; gameEffect.Brightness=-0.2; gameEffect.Parent=lighting
local cameraEffect=Instance.new("ColorCorrectionEffect"); cameraEffect.Parent=camera
local floor=part("Floor",Enum.Material.Plastic,Vector3.new(30,1,30))
local wood=part("WoodFloor",Enum.Material.WoodPlanks,Vector3.new(20,1,20))
local wall=part("BrickWall",Enum.Material.Brick,Vector3.new(25,12,2))
local grass=part("Lawn",Enum.Material.Grass,Vector3.new(20,1,20))
local marble=part("MarbleFloor",Enum.Material.Marble,Vector3.new(20,1,20))
local glass=part("Glass",Enum.Material.Glass,Vector3.new(8,10,0.5)); glass.Transparency=0.4; glass.Reflectance=0.03
local window=part("Window",Enum.Material.Plastic,Vector3.new(8,10,0.5)); window.Transparency=0.5; window.Reflectance=0.05
local avatarFloor=part("Floor",Enum.Material.Plastic,Vector3.new(30,1,30),localCharacter)
local npc=Instance.new("Model"); npc.Parent=world; local npcHum=Instance.new("Humanoid"); npcHum.Parent=npc
local npcFloor=part("Floor",Enum.Material.Plastic,Vector3.new(30,1,30),npc)
local tool=Instance.new("Tool"); tool.Parent=world; local toolFloor=part("Floor",Enum.Material.Plastic,Vector3.new(30,1,30),tool)
local moving=part("Moving",Enum.Material.Plastic,Vector3.new(30,1,30)); moving.Anchored=false
local mesh=Instance.new("MeshPart"); mesh.Anchored=true; mesh.Size=Vector3.new(30,1,30); mesh.Parent=world
local decorated=part("Decorated",Enum.Material.Concrete,Vector3.new(30,1,30))
local existingDecal=Instance.new("Decal"); existingDecal.Parent=decorated
local variant=part("Custom",Enum.Material.Concrete,Vector3.new(30,1,30)); variant.MaterialVariant="GameVariant"
local sloped=part("Sloped",Enum.Material.Concrete,Vector3.new(30,1,30)); sloped.CFrame={UpVector=Vector3.new(0,0.5,0)}
queryParts={floor,wood,wall,grass,marble,glass,window,avatarFloor,npcFloor,toolFloor,moving,mesh,decorated,variant,sloped}
features.Shaders.toggle(true)
local color,bloom,rays=byName(lighting,"ARMShaderColor"),byName(lighting,"ARMShaderBloom"),byName(lighting,"ARMShaderRays")
assert(card.Enabled and renderable(color) and renderable(bloom) and renderable(rays))
assert(color.Brightness==0.04 and color.Contrast==0.12 and color.Saturation==0.08)
assert(bloom.Intensity==0.35 and rays.Intensity==0.1)
assert(lighting.EnvironmentDiffuseScale==0.65 and lighting.EnvironmentSpecularScale==0.9
    and lighting.ShadowSoftness==0.35 and lighting.GlobalShadows and lighting.ExposureCompensation==0.12)
assert(not byName(world,"ARMShaderWeather") and activeHandles("Shaders weather")==0)
assert(activeHandles("Shaders surfaces")==1 and #spawned==0,"surface art is lazy, not downloaded at boot")
pass("enabling immediately applies native lighting and starts only a bounded surface scan")

frames(25)
assert(glass.Reflectance==0.22 and window.Reflectance==0.22)
assert(#assetRequests==0 and #spawned==5,"only five detected materials request art asynchronously")
assert(textureOf(floor).ColorMapContent.Uri=="rbxassetid://9920484153"
    and textureOf(wood).ColorMapContent.Uri=="rbxassetid://9920626778"
    and textureOf(grass).ColorMapContent.Uri=="rbxassetid://9920551868"
    and textureOf(marble).ColorMapContent.Uri=="rbxassetid://9439430596",
    "documented Roblox colour maps can be tried immediately while local images load")
assert(children(wall,"Texture")[1].ColorMapContent.Uri=="rbxassetid://9920482813")
runAllSpawned()
frames(60)
assert(#assetRequests==5)
assert(textureOf(floor).ColorMapContent.Uri=="custom://shaderConcreteTexture")
assert(textureOf(wood).ColorMapContent.Uri=="custom://shaderWoodTexture")
assert(textureOf(grass).ColorMapContent.Uri=="custom://shaderGrassTexture")
assert(textureOf(marble).ColorMapContent.Uri=="custom://shaderMarbleTexture")
local brickTextures=children(wall,"Texture")
assert(#brickTextures==2 and brickTextures[1].ColorMapContent.Uri=="custom://shaderBrickTexture")
assert(brickTextures[1].Face==Enum.NormalId.Front and brickTextures[2].Face==Enum.NormalId.Back)
assert(textureOf(floor).Face==Enum.NormalId.Top and textureOf(floor).Transparency==0.3)
assert(not textureOf(avatarFloor) and not textureOf(npcFloor) and not textureOf(toolFloor)
    and not textureOf(moving) and not textureOf(mesh) and not textureOf(decorated)
    and not textureOf(variant) and not textureOf(sloped),"exclude characters, tools, meshes, decals, variants and slopes")
assert(floor.Material==Enum.Material.Plastic and floor.CanCollide and floor.Anchored and floor.Size.Y==1,
    "surface art does not modify materials, collisions or geometry")
pass("actual colour textures and glass reflection affect eligible parts, not avatars or physics")

local originalFloorTexture=textureOf(floor)
card.Options["Glass reflections"].Metadata.callback(false)
assert(glass.Reflectance==0.03 and window.Reflectance==0.05)
assert(textureOf(floor)==originalFloorTexture and not originalFloorTexture.destroyed,
    "turning glass off leaves texture option intact")
card.Options["Glass reflections"].Metadata.callback(true)
card.Options["Wet surfaces"].Metadata.callback(true)
frames(80)
assert(glass.Reflectance==0.22 and floor.Reflectance==0.16)
card.Options["Wet surfaces"].Metadata.callback(false)
assert(floor.Reflectance==0 and glass.Reflectance==0.22 and textureOf(floor)==originalFloorTexture)
glass.Reflectance=0.66 -- the game changes this while the option is active
card.Options["Glass reflections"].Metadata.callback(false)
assert(glass.Reflectance==0.66 and window.Reflectance==0.05,"never overwrite a newer game value")
pass("independent glass/wet toggles restore only values still owned by the module")

local addedDecal=Instance.new("Decal"); addedDecal.Parent=floor
frames(60)
assert(originalFloorTexture.destroyed and not textureOf(floor) and not addedDecal.destroyed,
    "new game decals take precedence on the next scan")
local oldWood=textureOf(wood)
wood.Parent=nil
local arriving=part("NewMapFloor",Enum.Material.Wood,Vector3.new(20,1,20))
queryParts={arriving, glass}
frames(90)
assert(oldWood.destroyed and textureOf(arriving),"streamed-out surfaces clean up and new map parts are enhanced")
arriving.Anchored=false
frames(60)
assert(not textureOf(arriving),"a formerly static object is released if it becomes dynamic")
pass("streaming, map changes, new decals and changed physics are reconciled")

-- A pending download cannot recreate textures after the option is switched off.
card.Options["Surface textures"].Metadata.callback(false)
local delayed=part("Late",Enum.Material.Concrete,Vector3.new(20,1,20))
queryParts={delayed}
card.Options["Surface textures"].Metadata.callback(true)
frames(5)
assert(#spawned>0 and textureOf(delayed).ColorMapContent.Uri=="rbxassetid://9920484153")
card.Options["Surface textures"].Metadata.callback(false)
runAllSpawned(); frames(60)
assert(not textureOf(delayed) and activeHandles("Shaders surfaces")==0)
local noScan=queryCount; frames(100)
assert(queryCount==noScan,"no world query when all surface options are off")
pass("delayed assets do not revive disabled surfaces and idle costs no scan")

-- Toggling textures while glass keeps the scanner alive still invalidates old jobs.
local generationCalls=0
host.state.resolveAsset=function()
    generationCalls+=1
    return "custom://generation"..generationCalls
end
card.Options["Glass reflections"].Metadata.callback(true)
card.Options["Surface textures"].Metadata.callback(true)
frames(5)
assert(#spawned==1)
card.Options["Surface textures"].Metadata.callback(false)
card.Options["Surface textures"].Metadata.callback(true)
frames(60)
assert(#spawned==2)
runSpawned();frames(60)
assert(textureOf(delayed).ColorMapContent.Uri=="rbxassetid://9920484153",
    "an old completion cannot replace the current fallback")
runSpawned();frames(60)
assert(textureOf(delayed).ColorMapContent.Uri=="custom://generation2",
    "the current download replaces the fallback on a later scan")
card.Options["Surface textures"].Metadata.callback(false)
card.Options["Glass reflections"].Metadata.callback(false)
pass("texture generations stay isolated while glass remains enabled")

-- Even if the bounded radius query misses the floor (or fails), the downward
-- ray can prioritize it without searching all descendants or running each frame.
queryParts={}
groundHit=delayed
host.state.resolveAsset=function(name) return "custom://"..name end
local initialGroundRays=groundRayCount
card.Options["Surface textures"].Metadata.callback(true)
frames(5);assert(textureOf(delayed) and #spawned==1)
runAllSpawned();frames(60)
assert(textureOf(delayed).ColorMapContent.Uri=="custom://shaderConcreteTexture")
queryFail=true
frames(60)
assert(textureOf(delayed) and notifications[#notifications]:find("Nearby scan unavailable",1,true))
local noticeCount=#notifications;frames(60)
assert(#notifications==noticeCount and groundRayCount-initialGroundRays<=6,
    "query failure warns once and ground rays remain limited to scan cadence")
queryFail=false
card.Options["Surface textures"].Metadata.callback(false)
local overlapConstructor=OverlapParams.new
OverlapParams.new=function() error("OverlapParams unavailable") end
card.Options["Surface textures"].Metadata.callback(true)
frames(5)
assert(textureOf(delayed) and notifications[#notifications]:find("Nearby scan unavailable",1,true),
    "missing overlap parameters still permit the floor ray")
card.Options["Surface textures"].Metadata.callback(false)
runAllSpawned()
OverlapParams.new=overlapConstructor;groundHit=nil
queryParts={delayed}
pass("floor ray is prioritized and remains useful if the nearby scan fails")

local brokenFloor=part("BrokenFloor",Enum.Material.Concrete,Vector3.new(20,1,20))
brokenFloor.GetChildren=function() error("unreadable surface") end
queryParts={brokenFloor,delayed}
local warnCount=#warnings
card.Options["Surface textures"].Metadata.callback(true)
frames(5);runAllSpawned();frames(100)
assert(textureOf(delayed) and #warnings==warnCount+1 and warnings[#warnings]:find("unreadable surface",1,true),
    "one bad surface is diagnosed without stopping the scanner")
frames(100)
assert(#warnings==warnCount+1,"repeated processing errors are not logged every scan")
card.Options["Surface textures"].Metadata.callback(false)
queryParts={delayed}
pass("bad surfaces are reported once and do not block other parts")

host.state.resolveAsset=function() return nil,"missing getcustomasset" end
card.Options["Surface textures"].Metadata.callback(true)
frames(5); runAllSpawned(); frames(100)
assert(card.Enabled and textureOf(delayed).ColorMapContent.Uri=="rbxassetid://9920484153" and renderable(color))
assert(notifications[#notifications]:find("trying Roblox material images",1,true))
local warned=#notifications; frames(100)
assert(#notifications==warned and #spawned==0,"failed art is reported once, without a download loop")
card.Options["Surface textures"].Metadata.callback(false)
host.state.resolveAsset=function(name) table.insert(assetRequests,name);return "custom://"..name end
pass("missing custom assets are reported while trying the Roblox fallback")

local modernContent=Content
Content=nil -- older clients do not expose Content.fromUri
card.Options["Surface textures"].Metadata.callback(true)
frames(5);runAllSpawned();frames(70)
assert(textureOf(delayed) and textureOf(delayed).Texture=="custom://shaderConcreteTexture",
    "legacy Texture property remains a fallback when ColorMapContent is unavailable")
card.Options["Surface textures"].Metadata.callback(false)
Content=modernContent
pass("canonical ColorMapContent with legacy Texture fallback")

-- A failure halfway through a two-face wall must not leave a partial overlay.
queryParts={wall}
card.Options["Surface textures"].Metadata.callback(true)
frames(5);runAllSpawned()
Instance.failAt.Texture=(created.Texture or 0)+2
frames(70)
assert(#children(wall,"Texture")==0,"failed second face rolls back the first face")
Instance.failAt.Texture=nil
frames(70)
assert(#children(wall,"Texture")==2,"a later scan can retry the complete pair")
card.Options["Surface textures"].Metadata.callback(false)
pass("partial wall-texture creation is atomic and can be retried")

-- At most 240 queried parts, 80 texture instances and 100 reflected parts.
local manyFloors,manyGlass={},{}
queryParts={}
for i=1,140 do
    local p=part("Floor"..i,Enum.Material.Plastic,Vector3.new(20,1,20))
    table.insert(manyFloors,p);table.insert(queryParts,p)
end
for i=1,140 do
    local p=part("Glass"..i,Enum.Material.Glass,Vector3.new(8,10,1));p.Transparency=0.5
    table.insert(manyGlass,p);table.insert(queryParts,p)
end
card.Options["Surface textures"].Metadata.callback(true)
card.Options["Glass reflections"].Metadata.callback(true)
local startQueries=queryCount
frames(70,1/60);runAllSpawned();frames(250,1/60)
local countTex,countGlass=0,0
for _,p in ipairs(manyFloors) do if textureOf(p) then countTex+=1 end end
for _,p in ipairs(manyGlass) do if p.Reflectance>0 then countGlass+=1 end end
assert(countTex==80 and countGlass==100,"hard limits plus 240-part clipped query: "..countTex.."/"..countGlass)
assert(queryCount-startQueries<=4,"world queries at most every two seconds")
card.Options["Surface textures"].Metadata.callback(false)
card.Options["Glass reflections"].Metadata.callback(false)
for _,p in ipairs(manyFloors) do assert(not textureOf(p)) end
for _,p in ipairs(manyGlass) do assert(p.Reflectance==0) end
queryParts={}
pass("surface scanning, instance counts and reflection changes have fixed budgets")

-- Fog: use the game's atmosphere instead of creating a competing duplicate.
card.Options.Fog.Metadata.callback(true)
local ownFog=byName(lighting,"Atmosphere")
assert(ownFog and ownFog.Density==0.38 and #children(lighting,"Atmosphere")==1)
local incoming=Instance.new("Atmosphere"); incoming.Name="GameAtmosphere"; incoming.Density=0.16; incoming.Parent=lighting
flushDeferred()
assert(ownFog.destroyed and incoming.Density==0.38 and #children(lighting,"Atmosphere")==1)
incoming.Density=0.77
card.Options.Fog.Metadata.callback(false);flushDeferred()
assert(incoming.Density==0.77 and incoming.Haze==0.5 and not incoming.destroyed)
card.Options.Fog.Metadata.callback(true)
incoming:Destroy()
local replacement=Instance.new("Atmosphere");replacement.Density=0.23;replacement.Parent=lighting
flushDeferred();assert(replacement.Density==0.38)
card.Options.Fog.Metadata.callback(false);flushDeferred()
assert(replacement.Density==0.23 and not replacement.destroyed)
pass("fog owns or borrows atmosphere and handles dynamic replacements")

card.Options["Water reflections"].Metadata.callback(true)
assert(terrain.WaterReflectance==0.55)
card.Options["Water reflections"].Metadata.callback(false)
assert(terrain.WaterReflectance==0.12)
card.Options["Water reflections"].Metadata.callback(true)
terrain.WaterReflectance=0.8
card.Options["Water reflections"].Metadata.callback(false)
assert(terrain.WaterReflectance==0.8,"later game water change wins")
pass("optional water reflection restores conditionally")

-- Multiple independent weather toggles share four roof checks, not four grids.
card.Options.Rain.Metadata.callback(true)
local rain=byName(world,"ARMShaderWeather")
assert(rain and #children(rain,"Part")==4 and activeHandles("Shaders weather")==1)
local rainEmitters={}
for _,p in ipairs(children(rain,"Part")) do
    assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery)
    local e=children(p,"ParticleEmitter")[1];assert(e.Rate==15);table.insert(rainEmitters,e)
end
rayCount=0;frames(20)
assert(rayCount<=8)
for _,e in ipairs(rainEmitters) do assert(e.Enabled) end
isCovered=true;frames(20)
for _,e in ipairs(rainEmitters) do assert(not e.Enabled) end
roof.Transparency=1;frames(20)
for _,e in ipairs(rainEmitters) do assert(e.Enabled) end
roof.Transparency=0;isCovered=false;roofHeight=camera.CFrame.Position.Y+5;frames(50)
for _,e in ipairs(rainEmitters) do assert(not e.Enabled,"low ceiling blocks rain") end
roofHeight=nil;frames(50)
local beforeJumps=rayCount
for i=1,120 do camera.CFrame={Position=Vector3.new(if i%6<3 then 100 else 0,12,0)};frames(1,1/60) end
assert(rayCount-beforeJumps<=15,"rapid camera jumps cannot bypass ray limit")
camera.CFrame={Position=Vector3.new(0,12,0)}
card.Options.Snow.Metadata.callback(true)
local combined=byName(world,"ARMShaderWeather")
assert(rain.destroyed and #children(combined,"Part")==4)
for _,p in ipairs(children(combined,"Part")) do
    assert(#children(p,"ParticleEmitter")==2 and byName(p,"Rain").Rate==15 and byName(p,"Snow").Rate==7)
end
runAllSpawned();frames(25)
assert(byName(children(combined,"Part")[1],"Snow").Texture=="custom://shaderSnowTexture")
card.Options["Falling leaves"].Metadata.callback(true)
card.Options["Dust motes"].Metadata.callback(true)
local all=byName(world,"ARMShaderWeather")
assert(#children(all,"Part")==5 and #children(byName(all,"DustCell"),"ParticleEmitter")==1)
local totalRate=0
for _,p in ipairs(children(all,"Part")) do for _,e in ipairs(children(p,"ParticleEmitter")) do totalRate+=e.Rate end end
assert(totalRate==107,"60 rain + 28 snow + 12 leaves + 7 dust particles/s")
runAllSpawned();frames(30)
local dust=byName(byName(all,"DustCell"),"Dust motes")
assert(dust.Enabled and dust.Texture=="custom://shaderSnowTexture")
world.CurrentCamera=nil;frames(2)
assert(not dust.Enabled)
world.CurrentCamera=camera;frames(30);assert(dust.Enabled)
card.Options.Rain.Metadata.callback(false)
local snowLeaves=byName(world,"ARMShaderWeather")
assert(not byName(children(snowLeaves,"Part")[1],"Rain") and byName(children(snowLeaves,"Part")[1],"Snow"))
card.Options.Snow.Metadata.callback(false)
card.Options["Falling leaves"].Metadata.callback(false)
local dustOnly=byName(world,"ARMShaderWeather")
assert(#children(dustOnly,"Part")==1)
local dustRays=rayCount;frames(50);assert(rayCount==dustRays,"dust alone needs no roof raycasts")
card.Options["Dust motes"].Metadata.callback(false)
assert(not byName(world,"ARMShaderWeather") and activeHandles("Shaders weather")==0)
runAllSpawned() -- all cancelled completions must stay dead
pass("independent rain/snow/leaves/dust, shared roof budget and camera recovery")

host.state.resolveAsset=function() return nil,"not available" end
card.Options.Rain.Metadata.callback(true)
local fallback=byName(world,"ARMShaderWeather")
local fallbackEmitter=byName(children(fallback,"Part")[1],"Rain")
runAllSpawned()
assert(fallbackEmitter.Texture=="rbxasset://textures/particles/SquareParticle.png")
Instance.fail.ParticleEmitter=true
card.Options.Snow.Metadata.callback(true)
assert(card.Enabled and renderable(color) and not byName(world,"ARMShaderWeather"))
assert(notifications[#notifications]:find("Weather unavailable",1,true))
Instance.fail.ParticleEmitter=nil
card.Options.Snow.Metadata.callback(false)
local pending=byName(world,"ARMShaderWeather")
lighting.ExposureCompensation=0.77 -- game change survives cleanup
features.Shaders.toggle(false)
runAllSpawned();flushDeferred()
assert(pending.destroyed and not card.Enabled and activeHandles()==0)
assert(color.destroyed and bloom.destroyed and rays.destroyed and not gameEffect.destroyed and cameraEffect.Parent==camera)
assert(lighting.EnvironmentDiffuseScale==0.2 and lighting.EnvironmentSpecularScale==0.1
    and lighting.ShadowSoftness==0.1 and lighting.GlobalShadows==false and lighting.ExposureCompensation==0.77)
pass("fallback, partial failures, delayed jobs and complete conditional cleanup")
lighting.ExposureCompensation=2.2
features.Shaders.toggle(true)
assert(lighting.ExposureCompensation>2.2,"a bright scene must not be clamped down and darkened")
features.Shaders.toggle(false);runAllSpawned()
assert(lighting.ExposureCompensation==2.2)
lighting.ExposureCompensation=4.5
features.Shaders.toggle(true)
assert(lighting.ExposureCompensation==4.5,"original exposure above 3 must not be clamped down")
features.Shaders.toggle(false);runAllSpawned()
assert(lighting.ExposureCompensation==4.5)
pass("high original exposure is never reduced by the baseline")

Instance.fail.BloomEffect=true
local ok=pcall(features.Shaders.toggle,true)
assert(not ok and not card.Enabled and not byName(lighting,"ARMShaderColor"),"partial construction is cleaned")
Instance.fail.BloomEffect=nil
features.Shaders.toggle(true)
assert(renderable(byName(lighting,"ARMShaderColor")))
Shaders.destroy()
assert(not card.Enabled and activeHandles()==0 and not byName(lighting,"ARMShaderColor"))
pass("partial construction, re-enable and module destroy")

-- Saved toggle values may be delivered synchronously while the UI is built.
local fallbackHost=table.clone(host);fallbackHost.state={}
function fallbackHost.addToggleOption(_,name,default,callback)
    callback(if name=="Fog" then true elseif name=="Surface textures" then false else default)
    return {callback=callback}
end
local fallbackFramework=Framework.init(fallbackHost)
local saved=Shaders.init({framework=fallbackFramework,host=fallbackHost})
assert(saved.Options.Fog.Value and not saved.Options["Surface textures"].Value and not saved.Options.Look)
features.Shaders.toggle(true)
assert(replacement.Density==0.38)
Shaders.destroy();flushDeferred();assert(replacement.Density==0.23)
pass("synchronous saved-toggle restoration is safe and cannot restore removed looks")
'''


def lua_quote(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


script_text = (PRELUDE + "\nlocal FRAMEWORK_SOURCE = " + lua_quote(FRAMEWORK)
               + "\nlocal SHADERS_SOURCE = " + lua_quote(SHADERS) + "\n" + BODY)
with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "shaders.luau"
    script.write_text(script_text, encoding="utf-8")
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
