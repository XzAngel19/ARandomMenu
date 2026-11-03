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
function vectorMeta.__mul(a, b)
    if type(a)=="number" then a,b=b,a end
    return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
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
    ParticleOrientation={VelocityParallel=item("VelocityParallel"),VelocityPerpendicular=item("VelocityPerpendicular"),FacingCamera=item("FacingCamera")},
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
local treeReads=0
local function container(name,class)
    local obj={Name=name, ClassName=class, children={}, ChildAdded=signal(), ChildRemoved=signal()}
    function obj:GetChildren() treeReads+=1; return table.clone(self.children) end
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
world.DescendantAdded,world.DescendantRemoving=signal(),signal()
local roof={Transparency=0,IsA=function(_,name) return name=="BasePart" end}
local rayCount,groundRayCount,isCovered,roofHeight,groundHit,groundFail=0,0,false,nil,nil,false
local roofRadius,splashGround=nil,nil
function world:Raycast(origin,direction,params)
    assert(params.FilterType==Enum.RaycastFilterType.Exclude and #params.FilterDescendantsInstances>=1)
    if direction.Y<0 then
        groundRayCount+=1
        if groundFail then error("ground ray denied") end
        if direction.Y==-100 and splashGround then
            return {Instance=splashGround,Position=Vector3.new(origin.X,0,origin.Z),Normal=Vector3.new(0,1,0)}
        end
        return if groundHit then {Instance=groundHit} else nil
    end
    rayCount+=1
    local center=camera.CFrame.Position
    if isCovered or (roofRadius and math.abs(origin.X-center.X)<=roofRadius and math.abs(origin.Z-center.Z)<=roofRadius)
        or (roofHeight and origin.Y<=roofHeight and origin.Y+direction.Y>=roofHeight) then return {Instance=roof} end
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
    function obj:Emit(n) self.Emitted=(self.Emitted or 0)+n end
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
local reflectionStarts,reflectionStops,reflectionObservations=0,0,{}
local reflectionLibrary={fail=false}
function reflectionLibrary:Start(report)
    if self.fail then return nil,"simulated unavailable" end
    reflectionStarts+=1
    local active=true
    return {Observe=function(_,part) reflectionObservations[part]=true end, Stop=function()
        if active then active=false;reflectionStops+=1 end
    end}
end
local libraries={shaderreflection=reflectionLibrary}
local card=Shaders.init({framework=framework,host=host,libraries=libraries})
assert(card==framework.Modules.Shaders)
assert(not card.Options.Look and not card.Options.Weather and not card.Options.Advanced,
    "no old look or mode selector remains")
local names={"Floor reflections","Surface textures","Glass reflections","Fog","Rain","Snow","Falling leaves","Dust motes","Wet surfaces","Water reflections"}
assert(#card.OptionMetadata==#names)
for i,name in ipairs(names) do assert(card.OptionMetadata[i].label==name and card.OptionMetadata[i].type=="toggle") end
assert(card.Options["Floor reflections"].Value and card.Options["Surface textures"].Value and card.Options["Glass reflections"].Value)
for _,name in ipairs({"Fog","Rain","Snow","Falling leaves","Dust motes","Wet surfaces","Water reflections"}) do
    assert(not card.Options[name].Value)
end
pass("simple individual toggles, no Look/preset/weather selector")

local gameEffect=Instance.new("ColorCorrectionEffect"); gameEffect.Name="GameOwned"; gameEffect.Brightness=-0.2; gameEffect.Parent=lighting
local cameraEffect=Instance.new("ColorCorrectionEffect"); cameraEffect.Parent=camera
local floor=part("Floor",Enum.Material.Plastic,Vector3.new(30,1,30))
floor.Color=Color3.fromRGB(40,32,24)
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
assert(color.Brightness==0.01 and color.Contrast==0.14 and color.Saturation==0.10
    and color.TintColor==Color3.fromRGB(255,244,232))
assert(bloom.Intensity==0.36 and bloom.Size==30 and bloom.Threshold==1.05 and rays.Intensity==0.18 and rays.Spread==0.85)
local dof=byName(lighting,"ARMShaderDOF"); local blur=byName(lighting,"ARMShaderBlur")
assert(dof and dof.Enabled and dof.FarIntensity==0.12 and blur and blur.Enabled and blur.Size==2)
assert(lighting.EnvironmentDiffuseScale==0.55 and lighting.EnvironmentSpecularScale==0.82
    and lighting.ShadowSoftness==0.20 and lighting.GlobalShadows and lighting.ExposureCompensation==0.10 and lighting.Brightness==2.2,
    "realistic baseline: stronger specular/diffuse and cinematic exposure")
assert(not byName(world,"ARMShaderWeather") and activeHandles("Shaders weather")==0)
assert(activeHandles("Shaders surfaces")==1 and #spawned==0,"surface art is lazy, not downloaded at boot")
assert(reflectionStarts==1 and reflectionStops==0)
card.Options["Floor reflections"].Metadata.callback(false)
assert(reflectionStops==1 and card.Enabled and renderable(color) and activeHandles("Shaders surfaces")==1)
reflectionLibrary.fail=true
card.Options["Floor reflections"].Metadata.callback(true)
assert(reflectionStarts==1 and card.Enabled and renderable(color)
    and notifications[#notifications]:find("Floor reflection unavailable",1,true))
card.Options["Floor reflections"].Metadata.callback(false)
reflectionLibrary.fail=false
card.Options["Floor reflections"].Metadata.callback(true)
assert(reflectionStarts==2 and reflectionStops==1)
pass("warm baseline, floor reflection lifecycle and independent failure isolation")

frames(25)
assert(reflectionObservations[floor] and reflectionObservations[wood],
    "the world traversal must feed eligible map surfaces to the mirror library")
assert(glass.Reflectance==0.38 and window.Reflectance==0.38)
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
assert(textureOf(floor).Face==Enum.NormalId.Top and textureOf(floor).Transparency==0.55
    and textureOf(floor).Color3==floor.Color, "dark floors must not be tinted towards white")
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
assert(glass.Reflectance==0.38 and floor.Reflectance==0.30)
card.Options["Wet surfaces"].Metadata.callback(false)
assert(floor.Reflectance==0 and glass.Reflectance==0.38 and textureOf(floor)==originalFloorTexture)
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
assert(not textureOf(delayed) and activeHandles("Shaders surfaces")==1,
    "floor mirrors alone still need the incremental map walk")
card.Options["Floor reflections"].Metadata.callback(false)
assert(activeHandles("Shaders surfaces")==0)
local noScan=treeReads; frames(100)
assert(treeReads==noScan,"no hierarchy traversal when all surface and floor options are off")
pass("delayed assets do not revive disabled surfaces and idle costs no scan")

-- Isolate one real map part so we can distinguish the two async generations.
local detached={}
for _,obj in ipairs(world:GetChildren()) do
    if obj~=delayed and obj:IsA("BasePart") then
        obj.Parent=nil;table.insert(detached,obj)
    end
end
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
for _,obj in ipairs(detached) do obj.Parent=world end
pass("texture generations stay isolated while glass remains enabled")

-- A ray prioritizes the current floor, but the incremental hierarchy walk must
-- still discover the map if that ray fails or RaycastParams are unavailable.
groundHit=delayed
host.state.resolveAsset=function(name) return "custom://"..name end
local initialGroundRays=groundRayCount
card.Options["Surface textures"].Metadata.callback(true)
frames(5);assert(textureOf(delayed) and #spawned>=1)
runAllSpawned();frames(60)
assert(textureOf(delayed).ColorMapContent.Uri=="custom://shaderConcreteTexture")
groundFail=true
frames(60)
assert(textureOf(delayed), "failed floor ray must not stop the world traversal")
local noticeCount=#notifications;frames(60)
assert(#notifications==noticeCount and groundRayCount-initialGroundRays<=8,
    "floor rays remain limited to scan cadence")
groundFail=false
card.Options["Surface textures"].Metadata.callback(false)
local rayConstructor=RaycastParams.new
RaycastParams.new=function() error("RaycastParams unavailable") end
card.Options["Surface textures"].Metadata.callback(true)
frames(80)
assert(textureOf(delayed), "map traversal works without ray parameters")
card.Options["Surface textures"].Metadata.callback(false)
runAllSpawned()
RaycastParams.new=rayConstructor;groundHit=nil
assert(queryCount==0, "surface coverage must not be restricted to a nearby radius query")
pass("floor ray prioritization and whole-map traversal survive ray failures")

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

-- Unlike the old 120-stud query, map traversal reaches distant parts and
-- retains earlier changes when the camera moves. Four surface jobs per tick.
local manyFloors,manyGlass={},{}
for i=1,140 do
    local p=part("Floor"..i,Enum.Material.Plastic,Vector3.new(20,1,20))
    p.Position=Vector3.new(i*100,0,0);table.insert(manyFloors,p)
end
for i=1,140 do
    local p=part("Glass"..i,Enum.Material.Glass,Vector3.new(8,10,1));p.Transparency=0.5
    p.Position=Vector3.new(i*100,0,20);table.insert(manyGlass,p)
end
card.Options["Surface textures"].Metadata.callback(true)
card.Options["Glass reflections"].Metadata.callback(true)
frames(100,1/60);runAllSpawned();frames(300,1/60)
local countTex,countGlass=0,0
for _,p in ipairs(manyFloors) do if textureOf(p) then countTex+=1 end end
for _,p in ipairs(manyGlass) do if p.Reflectance>0 then countGlass+=1 end end
assert(countTex==140 and countGlass==140,"eligible remote map surfaces should all be reached")
assert(queryCount==0,"surface coverage does not depend on a radius query")
camera.CFrame={Position=Vector3.new(5000,12,0)};frames(180,1/60)
assert(textureOf(manyFloors[1]) and textureOf(manyFloors[140]), "moving the camera must not evict earlier floors")
local stream=part("StreamedWindow",Enum.Material.Glass,Vector3.new(10,10,1));stream.Transparency=0.5
world.DescendantAdded:Fire(stream);frames(1)
assert(stream.Reflectance==0.38,"streamed-in parts enter the bounded priority queue")
world.DescendantRemoving:Fire(stream);stream.Parent=nil
assert(stream.Reflectance==0,"streamed-out parts restore their own value")
card.Options["Surface textures"].Metadata.callback(false)
card.Options["Glass reflections"].Metadata.callback(false)
for _,p in ipairs(manyFloors) do assert(not textureOf(p));p.Parent=nil end
for _,p in ipairs(manyGlass) do assert(p.Reflectance==0);p.Parent=nil end
camera.CFrame={Position=Vector3.new(0,12,0)}
pass("distant map surfaces, streaming, no camera eviction and incremental work")

-- Explicit limits prevent huge worlds from creating an unbounded number of
-- textures/reflectance records; exceeding a limit is reported to the user.
local stress={}
for i=1,610 do table.insert(stress,part("StressFloor"..i,Enum.Material.Concrete,Vector3.new(20,1,20))) end
for i=1,1210 do
    local p=part("StressGlass"..i,Enum.Material.Glass,Vector3.new(10,10,1));p.Transparency=0.5
    table.insert(stress,p)
end
local noticesBefore=#notifications
card.Options["Surface textures"].Metadata.callback(true)
card.Options["Glass reflections"].Metadata.callback(true)
frames(700,1/60);runAllSpawned();frames(700,1/60)
local allTextures,allGlass=0,0
for _,p in ipairs(world:GetChildren()) do
    if p:IsA("BasePart") then
        for _,texture in ipairs(children(p,"Texture")) do
            if texture.Name=="ARMShaderTexture" then allTextures+=1 end
        end
        if p.Reflectance==0.38 then allGlass+=1 end -- includes transparent plastic windows
    end
end
assert(allTextures==600 and allGlass==1200,"hard map budgets are enforced: "..allTextures.."/"..allGlass)
assert(#notifications==noticesBefore+1 and notifications[#notifications]:find("Surface limit",1,true))
card.Options["Surface textures"].Metadata.callback(false)
card.Options["Glass reflections"].Metadata.callback(false)
for _,p in ipairs(stress) do assert(not textureOf(p) and p.Reflectance==0);p.Parent=nil end
pass("large maps have bounded retained objects and a visible limit warning")

-- Fog: use the game's atmosphere instead of creating a competing duplicate.
card.Options.Fog.Metadata.callback(true)
local ownFog=byName(lighting,"Atmosphere")
assert(ownFog and ownFog.Density==0.38 and #children(lighting,"Atmosphere")==1)
local fogFolder=byName(world,"ARMShaderWeather")
local fogCell=byName(fogFolder,"FogCell");local mist=byName(fogCell,"Fog mist")
assert(mist and mist.Rate==4 and mist.Transparency.Value==0.86 and activeHandles("Shaders weather")==1)
local beforeFogRays=rayCount;frames(5)
assert(mist.Enabled and rayCount==beforeFogRays,"fog particles work independently without roof scans")
local incoming=Instance.new("Atmosphere"); incoming.Name="GameAtmosphere"; incoming.Density=0.16; incoming.Parent=lighting
flushDeferred()
assert(ownFog.destroyed and incoming.Density==0.38 and #children(lighting,"Atmosphere")==1)
incoming.Density=0.77
card.Options.Fog.Metadata.callback(false);flushDeferred()
assert(fogFolder.destroyed and not byName(world,"ARMShaderWeather"),"fog particles clean up on OFF")
assert(incoming.Density==0.77 and incoming.Haze==0.5 and not incoming.destroyed)
card.Options.Fog.Metadata.callback(true)
incoming:Destroy()
local replacement=Instance.new("Atmosphere");replacement.Density=0.23;replacement.Parent=lighting
flushDeferred();assert(replacement.Density==0.38)
card.Options.Fog.Metadata.callback(false);flushDeferred()
assert(replacement.Density==0.23 and not replacement.destroyed)
runAllSpawned()
pass("fog uses atmosphere plus independent particles and restores dynamic replacements")

card.Options["Water reflections"].Metadata.callback(true)
assert(terrain.WaterReflectance==0.55)
card.Options["Water reflections"].Metadata.callback(false)
assert(terrain.WaterReflectance==0.12)
card.Options["Water reflections"].Metadata.callback(true)
terrain.WaterReflectance=0.8
card.Options["Water reflections"].Metadata.callback(false)
assert(terrain.WaterReflectance==0.8,"later game water change wins")
pass("optional water reflection restores conditionally")

-- Nine independent cells sample the sky. Outer cells can remain rainy when
-- the camera is under a small roof, as in the Rain plugin reference.
local function weatherCells(folder)
    local out={}
    for _,p in ipairs(children(folder,"Part")) do if p.Name=="WeatherCell" then table.insert(out,p) end end
    return out
end
card.Options.Rain.Metadata.callback(true)
local rain=byName(world,"ARMShaderWeather")
assert(rain and #weatherCells(rain)==9 and #children(rain,"Part")==10 and activeHandles("Shaders weather")==1)
local rainEmitters={}
for _,p in ipairs(weatherCells(rain)) do
    assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery)
    local e=byName(p,"Rain");assert(e.Rate==12);table.insert(rainEmitters,e)
end
local splash=byName(byName(rain,"RainSplashCell"),"Rain splashes")
splashGround=floor
rayCount=0;frames(40)
assert(rayCount<=15 and splash.Emitted>0,"outdoor rain samples can create limited local splashes")
for _,e in ipairs(rainEmitters) do assert(e.Enabled) end
isCovered=true;frames(40)
for _,e in ipairs(rainEmitters) do assert(not e.Enabled) end
roof.Transparency=1;frames(40)
for _,e in ipairs(rainEmitters) do assert(e.Enabled) end
roof.Transparency=0;isCovered=false;roofHeight=camera.CFrame.Position.Y+5;frames(40)
for _,e in ipairs(rainEmitters) do assert(not e.Enabled,"low ceiling blocks rain") end
roofHeight=nil;roofRadius=10;frames(40)
assert(not rainEmitters[1].Enabled,"the centre cell is sheltered")
for i=2,#rainEmitters do assert(rainEmitters[i].Enabled,"outdoor cells stay visible beyond a roof") end
roofRadius=nil;splashGround=nil;frames(40)
local beforeJumps=rayCount
for i=1,120 do camera.CFrame={Position=Vector3.new(if i%6<3 then 100 else 0,12,0)};frames(1,1/60) end
assert(rayCount-beforeJumps<=15,"rapid camera jumps cannot bypass ray limit")
camera.CFrame={Position=Vector3.new(0,12,0)}
card.Options.Snow.Metadata.callback(true)
local combined=byName(world,"ARMShaderWeather")
assert(rain.destroyed and #weatherCells(combined)==9)
for _,p in ipairs(weatherCells(combined)) do
    assert(#children(p,"ParticleEmitter")==2 and byName(p,"Rain").Rate==12 and byName(p,"Snow").Rate==5)
end
runAllSpawned();frames(35)
assert(byName(weatherCells(combined)[1],"Snow").Texture=="custom://shaderSnowTexture")
card.Options["Falling leaves"].Metadata.callback(true)
card.Options["Dust motes"].Metadata.callback(true)
local all=byName(world,"ARMShaderWeather")
assert(#weatherCells(all)==9 and #children(all,"Part")==11 and #children(byName(all,"DustCell"),"ParticleEmitter")==1)
local totalRate=0
for _,p in ipairs(children(all,"Part")) do for _,e in ipairs(children(p,"ParticleEmitter")) do totalRate+=e.Rate end end
assert(totalRate==183,"108 rain + 45 snow + 18 leaves + 12 dust particles/s, plus manual splashes")
runAllSpawned();frames(35)
local dust=byName(byName(all,"DustCell"),"Dust motes")
assert(dust.Enabled and dust.Texture=="custom://shaderSnowTexture" and dust.Rate==12 and dust.Size.Value==0.35)
card.Options.Fog.Metadata.callback(true)
local withFog=byName(world,"ARMShaderWeather")
assert(byName(byName(withFog,"FogCell"),"Fog mist") and byName(weatherCells(withFog)[1],"Rain"))
frames(35)
assert(byName(byName(withFog,"FogCell"),"Fog mist").Enabled)
card.Options.Fog.Metadata.callback(false)
all=byName(world,"ARMShaderWeather");dust=byName(byName(all,"DustCell"),"Dust motes")
frames(35)
assert(not byName(all,"FogCell") and dust.Enabled and byName(weatherCells(all)[1],"Rain").Enabled,
    "switching fog off must leave rain and dust active")
runAllSpawned()
isCovered=true;frames(35)
assert(dust.Enabled and not byName(weatherCells(all)[1],"Rain").Enabled,
    "dust stays active indoors while rain respects the roof")
isCovered=false
world.CurrentCamera=nil;frames(2)
assert(not dust.Enabled)
world.CurrentCamera=camera;frames(35);assert(dust.Enabled)
card.Options.Rain.Metadata.callback(false)
local snowLeaves=byName(world,"ARMShaderWeather")
assert(not byName(weatherCells(snowLeaves)[1],"Rain") and byName(weatherCells(snowLeaves)[1],"Snow")
    and not byName(snowLeaves,"RainSplashCell"))
card.Options.Snow.Metadata.callback(false)
card.Options["Falling leaves"].Metadata.callback(false)
local dustOnly=byName(world,"ARMShaderWeather")
assert(#children(dustOnly,"Part")==1)
local dustRays=rayCount;frames(50);assert(rayCount==dustRays,"dust alone needs no roof raycasts")
card.Options["Dust motes"].Metadata.callback(false)
assert(not byName(world,"ARMShaderWeather") and activeHandles("Shaders weather")==0)
runAllSpawned() -- all cancelled completions must stay dead
pass("independent rain/snow/leaves/dust, outdoor cells, splashes and camera recovery")

host.state.resolveAsset=function() return nil,"not available" end
card.Options.Rain.Metadata.callback(true)
local fallback=byName(world,"ARMShaderWeather")
local fallbackEmitter=byName(weatherCells(fallback)[1],"Rain")
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
assert(lighting.ExposureCompensation==2.2,"the baseline leaves the game's exposure alone")
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
    callback(if name=="Fog" then true elseif name=="Surface textures" or name=="Floor reflections" then false else default)
    return {callback=callback}
end
local fallbackFramework=Framework.init(fallbackHost)
local saved=Shaders.init({framework=fallbackFramework,host=fallbackHost,libraries=libraries})
assert(saved.Options.Fog.Value and not saved.Options["Surface textures"].Value
    and not saved.Options["Floor reflections"].Value and not saved.Options.Look)
local startsBeforeRestore=reflectionStarts
features.Shaders.toggle(true)
assert(replacement.Density==0.38 and reflectionStarts==startsBeforeRestore,
    "a saved OFF floor reflection must not start on module enable")
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
