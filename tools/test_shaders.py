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
NumberSequence = {new=function(v)
    if type(v)=="table" then return {Keypoints=v} end
    return {Value=v}
end}
NumberSequenceKeypoint = {new=function(t,v) return {Time=t,Value=v} end}
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
    AssetFetchStatus={Success=item("Success"),Failure=item("Failure"),TimedOut=item("TimedOut")},
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
local treeReads,rootReads=0,0
local function container(name,class)
    local obj={Name=name, ClassName=class, children={}, ChildAdded=signal(), ChildRemoved=signal()}
    function obj:GetChildren()
        treeReads+=1
        if self.ClassName=="Workspace" then rootReads+=1 end
        return table.clone(self.children)
    end
    function obj:FindFirstChild(wanted)
        for _, child in ipairs(self.children) do if child.Name==wanted and not child.destroyed then return child end end
    end
    function obj:FindFirstChildOfClass(wanted)
        for _, child in ipairs(self.children) do if child:IsA(wanted) and not child.destroyed then return child end end
    end
    function obj:IsA(wanted)
        return self.ClassName==wanted or (wanted=="BasePart" and
            (self.ClassName=="Part" or self.ClassName=="MeshPart" or self.ClassName=="UnionOperation"))
            or (wanted=="Decal" and self.ClassName=="Texture")
    end
    return obj
end
local lighting=container("Lighting","Lighting")
-- Lighting properties and Instance properties fire synchronous change signals;
-- the production code must also tolerate Roblox's deferred signal behavior.
local lightingValues,lightingSignals={},{}
local propertyEventsDeferred=false
local function fireProperty(signalObject)
    if propertyEventsDeferred then task.defer(function() signalObject:Fire() end)
    else signalObject:Fire() end
end
function lighting:GetPropertyChangedSignal(key)
    if not lightingSignals[key] then lightingSignals[key]=signal() end
    return lightingSignals[key]
end
setmetatable(lighting,{
    __index=function(_,key) return lightingValues[key] end,
    __newindex=function(_,key,value)
        local old=lightingValues[key];lightingValues[key]=value
        if old~=value and lightingSignals[key] then fireProperty(lightingSignals[key]) end
    end,
})
lighting.EnvironmentDiffuseScale=0.2; lighting.EnvironmentSpecularScale=0.1
lighting.ShadowSoftness=0.1; lighting.GlobalShadows=false; lighting.ExposureCompensation=0
lighting.FogStart=5;lighting.FogEnd=1000;lighting.FogColor=Color3.fromRGB(80,90,100)
local camera=container("Camera","Camera")
camera.CFrame={Position=Vector3.new(0,12,0)}
local world=container("Workspace","Workspace")
world.CurrentCamera=camera
world.DescendantAdded,world.DescendantRemoving=signal(),signal()
local roof={Transparency=0,IsA=function(_,name) return name=="BasePart" end}
local rayCount,groundRayCount,isCovered,roofHeight,groundHit,groundFail=0,0,false,nil,nil,false
local lastRayParams=nil
local cellEnabledWrites=0
local roofFail=false
local roofRadius,splashGround=nil,nil
function world:Raycast(origin,direction,params)
    assert(params.FilterType==Enum.RaycastFilterType.Exclude and #params.FilterDescendantsInstances>=1)
    lastRayParams=params
    if direction.Y<0 then
        groundRayCount+=1
        if groundFail then error("ground ray denied") end
        if direction.Y==-100 and splashGround then
            return {Instance=splashGround,Position=Vector3.new(origin.X,0,origin.Z),Normal=Vector3.new(0,1,0)}
        end
        return if groundHit then {Instance=groundHit} else nil
    end
    rayCount+=1
    if roofFail then error("sky ray denied") end
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
Instance={fail={},failAt={},failProperty={}}
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
    local propertySignals={}
    function obj:GetPropertyChangedSignal(key)
        if not propertySignals[key] then propertySignals[key]=signal() end
        return propertySignals[key]
    end
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
            else
                local fail=Instance.failProperty[class]
                if fail and fail[key] and (not fail.name or fail.name==obj.Name) then
                    error("property denied: "..class.."."..key)
                end
                local old=store[key];store[key]=value
                -- A write that does not change the value still restarts the
                -- emitter's internal budget in the real engine, so v176 must
                -- not rewrite Enabled on every poll.
                if class=="ParticleEmitter" and key=="Enabled" and store.Parent
                    and store.Parent.Name=="WeatherCell" then cellEnabledWrites+=1 end
                if old~=value and propertySignals[key] then fireProperty(propertySignals[key]) end
            end
        end,
    })
    return obj
end
local terrain=Instance.new("Terrain"); terrain.Name="Terrain"; terrain.Parent=world
local localCharacter=Instance.new("Model"); localCharacter.Name="LocalCharacter"; localCharacter.Parent=world
local humanoid=Instance.new("Humanoid"); humanoid.Parent=localCharacter

-- A successful HTTP/download and getcustomasset can still yield an asset that
-- ContentProvider cannot load. Success, failure, no callback and API errors
-- are separate modeled outcomes, none of which prove actual rendered pixels.
local preloadMode,preloaded="success",{}
local contentProvider={}
function contentProvider:PreloadAsync(instances,callback)
    assert(#instances==1 and instances[1].ClassName=="ImageLabel")
    local uri=instances[1].Image
    table.insert(preloaded,uri)
    if preloadMode=="throw" then error("preload denied") end
    if preloadMode=="success" then callback(uri,Enum.AssetFetchStatus.Success)
    elseif preloadMode=="failure" then callback(uri,Enum.AssetFetchStatus.Failure)
    elseif preloadMode=="timeout" then callback(uri,Enum.AssetFetchStatus.TimedOut) end
end
game={GetService=function(_,name)
    if name=="Lighting" then return lighting elseif name=="ContentProvider" then return contentProvider end
end}
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
local libraries={}
local card=Shaders.init({framework=framework,host=host,libraries=libraries})
assert(card==framework.Modules.Shaders)
assert(not card.Options.Look and not card.Options.Weather and not card.Options.Advanced,
    "no old look or mode selector remains")
local names={"Surface textures","Glass reflections","Fog","Rain","Snow","Falling leaves","Dust motes","Wet surfaces","Water reflections"}
-- v177: one action entry ("Diagnose") follows the toggles; no presets return.
assert(#card.OptionMetadata==#names+1)
for i,name in ipairs(names) do assert(card.OptionMetadata[i].label==name and card.OptionMetadata[i].type=="toggle") end
assert(card.OptionMetadata[#names+1].label=="Diagnose" and card.OptionMetadata[#names+1].type=="action")
assert(not card.Options["Floor reflections"] and card.Options["Surface textures"].Value and card.Options["Glass reflections"].Value)
for _,name in ipairs({"Fog","Rain","Snow","Falling leaves","Dust motes","Wet surfaces","Water reflections"}) do
    assert(not card.Options[name].Value)
end
pass("simple individual toggles, no Look/preset/weather selector")


-- v177: Diagnose prints the facts the module tracks, so a missing effect on a
-- specific map can be explained from the client instead of guessed.
local captured={}
local realPrint=print
print=function(text) table.insert(captured,tostring(text)) end
card.Options["Diagnose"].Metadata.callback()
print=realPrint
local joined=table.concat(captured,"\n")
for _,needle in ipairs({"stamp=","surfaces:","reflectance:","weather:","water:","camera="}) do
    assert(joined:find(needle,1,true),"diagnose must report "..needle)
end
assert(joined:find("emitters=",1,true) and joined:find("visits=",1,true))
pass("diagnose reports surfaces, weather, water and camera facts")

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
local anonymousPane=part("Part",Enum.Material.SmoothPlastic,Vector3.new(8,10,0.4)); anonymousPane.Transparency=0.4
local union=Instance.new("UnionOperation");union.Name="UnionFloor";union.Material=Enum.Material.Concrete
union.Size=Vector3.new(24,1,24);union.Anchored=true;union.Parent=world
local avatarFloor=part("Floor",Enum.Material.Plastic,Vector3.new(30,1,30),localCharacter)
local npc=Instance.new("Model"); npc.Parent=world; local npcHum=Instance.new("Humanoid"); npcHum.Parent=npc
local npcFloor=part("Floor",Enum.Material.Plastic,Vector3.new(30,1,30),npc)
local tool=Instance.new("Tool"); tool.Parent=world; local toolFloor=part("Floor",Enum.Material.Plastic,Vector3.new(30,1,30),tool)
local moving=part("Moving",Enum.Material.Plastic,Vector3.new(30,1,30)); moving.Anchored=false
local movingWindow=part("MovingWindow",Enum.Material.Glass,Vector3.new(1,8,8));movingWindow.Anchored=false
movingWindow.Transparency=0.4;movingWindow.Reflectance=0.04
local avatarGlass=part("Visor",Enum.Material.Glass,Vector3.new(1,8,8),localCharacter)
avatarGlass.Anchored=false;avatarGlass.Transparency=0.4
local mesh=Instance.new("MeshPart"); mesh.Anchored=true; mesh.Size=Vector3.new(30,1,30); mesh.Parent=world
local decorated=part("Decorated",Enum.Material.Concrete,Vector3.new(30,1,30))
local existingDecal=Instance.new("Decal"); existingDecal.Parent=decorated
local variant=part("Custom",Enum.Material.Concrete,Vector3.new(30,1,30)); variant.MaterialVariant="GameVariant"
local sloped=part("Sloped",Enum.Material.Concrete,Vector3.new(30,1,30)); sloped.CFrame={UpVector=Vector3.new(0,0.5,0)}
queryParts={floor,wood,wall,grass,marble,glass,window,avatarFloor,npcFloor,toolFloor,moving,mesh,decorated,variant,sloped}
features.Shaders.toggle(true)
local color,bloom,rays=byName(lighting,"ARMShaderColor"),byName(lighting,"ARMShaderBloom"),byName(lighting,"ARMShaderRays")
assert(card.Enabled and renderable(color) and renderable(bloom) and renderable(rays))
assert(color.Brightness==0 and color.Contrast==0.08 and color.Saturation==0.05
    and color.TintColor==Color3.fromRGB(255,247,236))
assert(bloom.Intensity==0.2 and bloom.Threshold==0.95 and rays.Intensity==0.1)
assert(lighting.EnvironmentDiffuseScale==0.2 and lighting.EnvironmentSpecularScale==0.65
    and lighting.ShadowSoftness==0.35 and not lighting.GlobalShadows and lighting.ExposureCompensation==0,
    "the baseline must not forcibly brighten the existing scene")
assert(not byName(world,"ARMShaderWeather") and activeHandles("Shaders weather")==0)
assert(activeHandles("Shaders surfaces")==1 and #spawned==0,"surface art is lazy, not downloaded at boot")
assert(not byName(world,"ARMShaderFloorReflection"), "no limited floor mirror is created")
pass("warm baseline preserves existing shadows and has no limited mirror")

-- v177: a toggle pressed while the Shaders card is off used to swap its box and
-- do nothing, which reads as a broken effect. It must say why instead.
local beforeNotify=#notifications
card.Enabled=false
card.Options["Falling leaves"].Value=true
card.Options["Falling leaves"].Metadata.callback(true)
card.Enabled=true
assert(#notifications==beforeNotify+1 and notifications[#notifications]:find("Shaders is off",1,true),
    "a child toggle while the card is off must explain itself")
card.Options["Falling leaves"].Value=false
pass("child toggle outside the enabled card reports instead of silently ignoring")

-- v177: the status line must mention non-weather subsystems too, capped so the
-- card header stays readable.
for _,name in ipairs({"Wet surfaces","Water reflections","Fog","Rain","Snow"}) do
    card.Options[name].Value=true
end
card.Options["Glass reflections"].Metadata.callback(true)
assert(features.Shaders.status=="Surfaces · Glass · Wet · Water · +3",
    "status must count every enabled kind and cap at four: "..tostring(features.Shaders.status))
for _,name in ipairs({"Wet surfaces","Water reflections","Fog","Rain","Snow"}) do
    card.Options[name].Value=false
end
card.Options["Glass reflections"].Metadata.callback(true)
assert(features.Shaders.status=="Surfaces · Glass",
    "disabling kinds must shrink the status line: "..tostring(features.Shaders.status))
pass("status names surface/glass/wet/water and caps with a remainder")

frames(25)
assert(glass.Reflectance==0.5 and window.Reflectance==0.5 and anonymousPane.Reflectance==0.5,
    "transparent thin panes need not be literally named Window")
assert(movingWindow.Reflectance==0.5 and not movingWindow.Anchored and movingWindow.CanCollide
    and avatarGlass.Reflectance==0,"moving map glass can be enhanced without touching physics or avatar glass")
assert(textureOf(union),"compatible CSG floors should use the same per-face texture API")
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
assert(textureOf(floor).Texture=="custom://shaderConcreteTexture")
assert(textureOf(wood).Texture=="custom://shaderWoodTexture")
assert(textureOf(grass).Texture=="custom://shaderGrassTexture")
assert(textureOf(marble).Texture=="custom://shaderMarbleTexture")
local brickTextures=children(wall,"Texture")
assert(#brickTextures==2 and brickTextures[1].Texture=="custom://shaderBrickTexture")
assert(brickTextures[1].Face==Enum.NormalId.Front and brickTextures[2].Face==Enum.NormalId.Back)
assert(textureOf(floor).Face==Enum.NormalId.Top and textureOf(floor).Transparency==0.42
    and textureOf(floor).Color3==floor.Color, "dark floors must not be tinted towards white")
assert(not textureOf(avatarFloor) and not textureOf(npcFloor) and not textureOf(toolFloor)
    and not textureOf(moving) and not textureOf(mesh) and not textureOf(decorated)
    and not textureOf(variant) and not textureOf(sloped),"exclude characters, tools, meshes, decals, variants and slopes")
assert(floor.Material==Enum.Material.Plastic and floor.CanCollide and floor.Anchored and floor.Size.Y==1,
    "surface art does not modify materials, collisions or geometry")
pass("actual colour textures and glass reflection affect eligible parts, not avatars or physics")

-- Respect a game decal only on its own face; a sign on one side of a wall
-- must not prevent material detail on the opposite side.
local gameFront=Instance.new("Decal");gameFront.Face=Enum.NormalId.Front;gameFront.Parent=wall
world.DescendantAdded:Fire(gameFront)
frames(80)
local wallTextures=children(wall,"Texture")
assert(#wallTextures==1 and wallTextures[1].Face==Enum.NormalId.Back and not gameFront.destroyed,
    "an occupied wall face must leave its free opposite side available")
world.DescendantRemoving:Fire(gameFront);gameFront:Destroy();frames(80)
assert(#children(wall,"Texture")==2,"freed faces are reconsidered on later scans")
pass("game-owned decals win per face without excluding unrelated surfaces")

local originalFloorTexture=textureOf(floor)
card.Options["Glass reflections"].Metadata.callback(false)
assert(glass.Reflectance==0.03 and window.Reflectance==0.05 and movingWindow.Reflectance==0.04)
assert(textureOf(floor)==originalFloorTexture and not originalFloorTexture.destroyed,
    "turning glass off leaves texture option intact")
card.Options["Glass reflections"].Metadata.callback(true)
card.Options["Wet surfaces"].Metadata.callback(true)
frames(80)
assert(glass.Reflectance==0.5 and floor.Reflectance==0.32)
card.Options["Wet surfaces"].Metadata.callback(false)
assert(floor.Reflectance==0 and glass.Reflectance==0.5 and textureOf(floor)==originalFloorTexture)
window.Reflectance=0.02 -- the game writes after we enabled the glass option
frames(80)
assert(window.Reflectance==0.5,"glass remains enhanced after a game-side rewrite")
glass.Reflectance=0.66 -- the game changes this while the option is active
card.Options["Glass reflections"].Metadata.callback(false)
assert(glass.Reflectance==0.66 and window.Reflectance==0.02 and anonymousPane.Reflectance==0,
    "restore each latest game value when disabling glass")
pass("independent glass/wet toggles restore only values still owned by the module")

local addedDecal=Instance.new("Decal"); addedDecal.Parent=floor
world.DescendantAdded:Fire(addedDecal)
frames(60)
assert(originalFloorTexture.destroyed and not textureOf(floor) and not addedDecal.destroyed,
    "new game decals take precedence on the next scan")
local oldWood=textureOf(wood)
world.DescendantRemoving:Fire(wood);wood.Parent=nil
local arriving=part("NewMapFloor",Enum.Material.Wood,Vector3.new(20,1,20))
world.DescendantAdded:Fire(arriving)
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
assert(not textureOf(delayed) and activeHandles("Shaders surfaces")==0,
    "the scanner stops when surface, wet and glass options are all disabled")
local noScan=treeReads; frames(100)
assert(treeReads==noScan,"no hierarchy traversal when all surface options are off")
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
assert(textureOf(delayed).Texture=="custom://generation2",
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
assert(textureOf(delayed).Texture=="custom://shaderConcreteTexture")
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

-- A syntactically valid local URI is not evidence that the renderer loaded it.
-- Failed, absent, or denied preload status must keep the known Roblox fallback.
for _,mode in ipairs({"failure","none","throw"}) do
    preloadMode=mode
    host.state.resolveAsset=function(name) return "custom://"..name end
    card.Options["Surface textures"].Metadata.callback(true)
    frames(10);runAllSpawned();frames(80)
    assert(textureOf(delayed).ColorMapContent.Uri=="rbxassetid://9920484153",
        "unconfirmed local colour map replaced fallback on "..mode)
    card.Options["Surface textures"].Metadata.callback(false)
end
preloadMode="success"
-- On Roblox, local ColorMapContent can be accepted yet fail to render; use
-- legacy Texture for local URIs, or the official fallback if it is unavailable.
Instance.failProperty.Texture={Texture=true}
card.Options["Surface textures"].Metadata.callback(true)
frames(10);runAllSpawned();frames(80)
assert(textureOf(delayed).ColorMapContent.Uri=="rbxassetid://9920484153",
    "unsupported legacy local-texture setter should retain the official fallback")
card.Options["Surface textures"].Metadata.callback(false)
Instance.failProperty.Texture=nil
pass("local art needs successful preload and the compatible legacy texture path")

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
frames(10)
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
assert(stream.Reflectance==0.5,"streamed-in parts enter the bounded priority queue")
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
        if p.Reflectance==0.5 then allGlass+=1 end -- includes transparent plastic windows
    end
end
assert(allTextures==600 and allGlass==1200,"hard map budgets are enforced: "..allTextures.."/"..allGlass)
assert(#notifications==noticesBefore+1 and notifications[#notifications]:find("Surface limit",1,true))
card.Options["Surface textures"].Metadata.callback(false)
card.Options["Glass reflections"].Metadata.callback(false)
for _,p in ipairs(stress) do assert(not textureOf(p) and p.Reflectance==0);p.Parent=nil end
pass("large maps have bounded retained objects and a visible limit warning")

-- FogEnd only draws while Lighting has no Atmosphere. Preserve the game's
-- latest values while keeping the requested fog after game-side rewrites.
local oldFogColor=lighting.FogColor
card.Options.Fog.Metadata.callback(true)
assert(#children(lighting,"Atmosphere")==0 and lighting.FogStart==5 and lighting.FogEnd==110,
    "legacy fog must use FogEnd instead of inserting a competing Atmosphere")
assert(lighting.FogColor==Color3.fromRGB(176,188,196),"legacy fog keeps a readable grey-blue tint")
local fogFolder=byName(world,"ARMShaderWeather")
local fogCell=byName(fogFolder,"FogCell");local mist=byName(fogCell,"Fog mist")
local fogParts=0
for _,p in ipairs(children(fogFolder,"Part")) do if p.Name=="FogCell" then fogParts+=1 end end
assert(fogParts==17 and mist and mist.Rate==2 and mist.Size.Value==18
    and mist.Transparency.Keypoints[2].Value==0.78 and mist.Lifetime.Max==5.5
    and activeHandles("Shaders weather")==1,"near and distant faded mist patches use a bounded budget")
local beforeFogRays=rayCount;frames(5)
assert(mist.Enabled and rayCount==beforeFogRays,"fog particles work independently without roof scans")
lighting.FogEnd=1400;flushDeferred()
assert(lighting.FogEnd==110,"a game rewrite must not silently erase active fog")
local incoming=Instance.new("Atmosphere"); incoming.Name="GameAtmosphere"; incoming.Density=0.16; incoming.Parent=lighting
flushDeferred()
assert(lighting.FogEnd==1400 and lighting.FogColor==oldFogColor and incoming.Density==0.58
    and incoming.Haze==4.5 and #children(lighting,"Atmosphere")==1,
    "switch to the game's real atmosphere, raise Density and Haze, restore FogEnd")
incoming.Density=0.05;flushDeferred()
assert(incoming.Density==0.58,"a game rewrite must be reconciled while Fog is active")
incoming.Density=0.77;flushDeferred()
assert(incoming.Density==0.77,"already denser game fog must never be weakened")
card.Options.Fog.Metadata.callback(false);flushDeferred()
assert(fogFolder.destroyed and not byName(world,"ARMShaderWeather"),"fog particles clean up on OFF")
assert(incoming.Density==0.77 and incoming.Haze==0.5 and not incoming.destroyed)
card.Options.Fog.Metadata.callback(true)
incoming:Destroy()
local replacement=Instance.new("Atmosphere");replacement.Density=0.23;replacement.Parent=lighting
flushDeferred();assert(replacement.Density==0.58)
replacement:Destroy();flushDeferred()
assert(lighting.FogEnd==110,"FogEnd resumes if the game removes its Atmosphere")
card.Options.Fog.Metadata.callback(false);flushDeferred()
assert(lighting.FogEnd==1400 and lighting.FogStart==5 and lighting.FogColor==oldFogColor)
runAllSpawned()
-- Roblox may defer property notifications until after our writes have returned.
propertyEventsDeferred=true
card.Options.Fog.Metadata.callback(true);flushDeferred()
lighting.FogEnd=800;flushDeferred()
assert(lighting.FogEnd==110,"deferred game writes are reasserted without a signal loop")
lighting.FogEnd=750
card.Options.Fog.Metadata.callback(false);flushDeferred()
assert(lighting.FogEnd==750,"disable preserves a newer write even if its signal is still queued")
propertyEventsDeferred=false
lighting.FogEnd=1400
pass("fog selects FogEnd or a game Atmosphere, reasserts and restores their latest values")

card.Options["Water reflections"].Metadata.callback(true)
assert(terrain.WaterReflectance==0.75,"v177: water sheen must be visible, not a 0.03 nudge")
card.Options["Water reflections"].Metadata.callback(false)
assert(terrain.WaterReflectance==0.12)
card.Options["Water reflections"].Metadata.callback(true)
terrain.WaterReflectance=0.8
card.Options["Water reflections"].Metadata.callback(false)
assert(terrain.WaterReflectance==0.8,"later game water change wins")
pass("optional water reflection restores conditionally")

-- A dense near grid and sparse outer ring extend the weather to ~336 studs,
-- but remain camera-centred and bounded. Every cell has an independent roof.
local function weatherCells(folder)
    local out={}
    for _,p in ipairs(children(folder,"Part")) do if p.Name=="WeatherCell" then table.insert(out,p) end end
    return out
end
local function emittersOf(part) return children(part,"ParticleEmitter") end
card.Options.Rain.Metadata.callback(true)
local rain=byName(world,"ARMShaderWeather")
assert(rain and #weatherCells(rain)==17 and #children(rain,"Part")==18 and activeHandles("Shaders weather")==1)
local rainEmitters={}
local rainRate,nearCount,farCount=0,0,0
for _,p in ipairs(weatherCells(rain)) do
    assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery)
    local streak=byName(p,"Rain");local close=byName(p,"Rain 2")
    assert(streak and streak.Lifetime.Min==0.85 and streak.Size.Value==1.15)
    assert(streak.Squash and streak.Squash.Value<0 and streak.Orientation==Enum.ParticleOrientation.VelocityParallel)
    assert(streak.Acceleration and streak.Acceleration.Y<0 and streak.Texture=="rbxassetid://1822883048")
    if p.Size.X==40 then
        nearCount+=1
        assert(streak.Rate==110 and close and close.Rate==40,"near rain remains layered")
        rainRate+=streak.Rate+close.Rate;table.insert(rainEmitters,close)
    else
        farCount+=1
        assert(p.Size.X==112 and streak.Rate==28 and not close,"outer rain uses one economical layer")
        rainRate+=streak.Rate
    end
    table.insert(rainEmitters,streak)
end
assert(nearCount==9 and farCount==8 and rainRate==1574 and rainRate<2160,
    "more coverage with a lower automatic rain rate than v177")
local splash=byName(byName(rain,"RainSplashCell"),"Rain splashes")
assert(splash.Texture=="rbxassetid://1822856633" and splash.Size.Value==2.2)
splashGround=floor
rayCount=0;frames(65)
assert(rayCount<=23 and splash.Emitted>0,"outdoor splashes and roof queries are bounded")
assert(lastRayParams.RespectCanCollide==true,"noncollidable decorations do not act as roofs")
for _,e in ipairs(rainEmitters) do assert(e.Enabled,"each cell eventually samples the open sky") end
local writesBefore=cellEnabledWrites
frames(65)
assert(cellEnabledWrites==writesBefore,"stable shelter must not rewrite Enabled")
local beforeSkyFailure=#notifications
roofFail=true;frames(65)
for _,e in ipairs(rainEmitters) do assert(e.Enabled,"a denied sky ray is not an invented roof") end
assert(#notifications==beforeSkyFailure+1 and notifications[#notifications]:find("shelter",1,true))
frames(65);assert(#notifications==beforeSkyFailure+1,"shelter failure is not spammed")
roofFail=false
isCovered=true;frames(65)
for _,e in ipairs(rainEmitters) do assert(not e.Enabled) end
roof.Transparency=1;frames(65)
for _,e in ipairs(rainEmitters) do assert(e.Enabled) end
roof.Transparency=0;isCovered=false;roofHeight=camera.CFrame.Position.Y+5;frames(65)
for _,e in ipairs(rainEmitters) do assert(not e.Enabled,"a low ceiling blocks rain") end
roofHeight=nil;roofRadius=10;frames(65)
for _,e in ipairs(emittersOf(weatherCells(rain)[1])) do assert(not e.Enabled,"centre cell is sheltered") end
for index=2,#weatherCells(rain) do
    for _,e in ipairs(emittersOf(weatherCells(rain)[index])) do assert(e.Enabled,"outdoor cells remain visible") end
end
roofRadius=nil;splashGround=nil;frames(65)
local beforeJumps=rayCount
for i=1,120 do camera.CFrame={Position=Vector3.new(if i%6<3 then 100 else 0,12,0)};frames(1,1/60) end
assert(rayCount-beforeJumps<=15,"camera jumps cannot bypass the ray limit")
for _,e in ipairs(rainEmitters) do assert(e.Enabled,"camera movement does not switch off rain") end
world.CurrentCamera=nil;frames(2)
for _,e in ipairs(rainEmitters) do assert(not e.Enabled) end
world.CurrentCamera=camera;frames(65)
for _,e in ipairs(rainEmitters) do assert(e.Enabled,"open cells recover after camera replacement") end
camera.CFrame={Position=Vector3.new(0,12,0)}
card.Options.Snow.Metadata.callback(true)
local combined=byName(world,"ARMShaderWeather")
assert(rain.destroyed and #weatherCells(combined)==17)
local snowRate=0
for _,p in ipairs(weatherCells(combined)) do
    local snow=byName(p,"Snow")
    assert(snow and snow.Size.Value==1.25 and snow.Lifetime.Min==5 and snow.LightEmission>=0.5)
    assert(snow.Transparency.Keypoints[1].Value==1 and snow.Transparency.Keypoints[4].Value==1,
        "snow fades rather than appearing and vanishing abruptly")
    assert(snow.SpreadAngle.X>=20 and snow.Acceleration and snow.Acceleration.X>0)
    if p.Size.X==40 then assert(snow.Rate==22 and #emittersOf(p)==3)
    else assert(snow.Rate==8 and #emittersOf(p)==2) end
    snowRate+=snow.Rate
end
assert(snowRate==262)
runAllSpawned();frames(65)
assert(byName(weatherCells(combined)[1],"Snow").Texture=="custom://shaderSnowTexture")
card.Options["Falling leaves"].Metadata.callback(true)
card.Options["Dust motes"].Metadata.callback(true)
local all=byName(world,"ARMShaderWeather")
assert(#weatherCells(all)==17 and #children(all,"Part")==19 and #children(byName(all,"DustCell"),"ParticleEmitter")==1)
local totalRate=0
for _,p in ipairs(children(all,"Part")) do for _,e in ipairs(children(p,"ParticleEmitter")) do totalRate+=e.Rate end end
assert(totalRate==1952,"near+far rain/snow/leaves and dust, excluding manual splashes")
runAllSpawned();frames(65)
local dust=byName(byName(all,"DustCell"),"Dust motes")
assert(dust.Enabled and dust.Texture=="custom://shaderSnowTexture" and dust.Rate==20 and dust.Size.Value==0.55
    and dust.Transparency.Keypoints[1].Value==1 and dust.Transparency.Keypoints[4].Value==1)
card.Options.Fog.Metadata.callback(true)
local withFog=byName(world,"ARMShaderWeather")
assert(byName(byName(withFog,"FogCell"),"Fog mist") and byName(weatherCells(withFog)[1],"Rain"))
totalRate=0
for _,p in ipairs(children(withFog,"Part")) do for _,e in ipairs(children(p,"ParticleEmitter")) do totalRate+=e.Rate end end
assert(totalRate==1978 and totalRate<=2000,"the shared desktop budget includes all mist emitters")
frames(65)
assert(byName(byName(withFog,"FogCell"),"Fog mist").Enabled)
card.Options.Fog.Metadata.callback(false)
all=byName(world,"ARMShaderWeather");dust=byName(byName(all,"DustCell"),"Dust motes")
frames(65)
assert(not byName(all,"FogCell") and dust.Enabled and byName(weatherCells(all)[1],"Rain").Enabled,
    "switching fog off leaves rain and dust active")
runAllSpawned()
isCovered=true;frames(65)
assert(dust.Enabled and not byName(weatherCells(all)[1],"Rain").Enabled,"dust stays active indoors")
isCovered=false
world.CurrentCamera=nil;frames(2);assert(not dust.Enabled)
world.CurrentCamera=camera;frames(65);assert(dust.Enabled)
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
runAllSpawned()
pass("near/far weather, bounded budget, shelter, splashes and camera recovery")

-- Mobile and touch+keyboard devices get the compact profile at creation.
for _,case in ipairs({"mobile","touch"}) do
    host.state.isMobile=case=="mobile"
    host.UserInputService={TouchEnabled=case=="touch"}
    card.Options.Rain.Metadata.callback(true)
    local mobileRain=byName(world,"ARMShaderWeather")
    frames(65)
    for _,p in ipairs(weatherCells(mobileRain)) do
        local list=emittersOf(p)
        assert(#list==1 and list[1].Rate==(if p.Size.X==40 then 64 else 14),
            "compact profile must scale near and far rain")
        assert(list[1].Rate<=100)
    end
    card.Options.Rain.Metadata.callback(false)
    runAllSpawned()
end
host.state.isMobile=true;host.UserInputService=nil
for _,name in ipairs({"Rain","Snow","Falling leaves","Dust motes","Fog"}) do
    card.Options[name].Metadata.callback(true)
end
local mobileAll=byName(world,"ARMShaderWeather")
local mobileTotal=0
for _,p in ipairs(children(mobileAll,"Part")) do
    for _,e in ipairs(children(p,"ParticleEmitter")) do
        assert(e.Rate<=100,"no compact emitter exceeds Roblox's mobile cap")
        mobileTotal+=e.Rate
    end
end
assert(mobileTotal==927 and mobileTotal<=1000,"all compact effects share one budget")
for _,name in ipairs({"Fog","Rain","Snow","Falling leaves","Dust motes"}) do
    card.Options[name].Metadata.callback(false)
end
host.state.isMobile=false;runAllSpawned()
pass("mobile and touch-plus-keyboard use a conservative emitter profile")

host.state.resolveAsset=function(name) return "custom://"..name end
preloadMode="failure"
card.Options.Rain.Metadata.callback(true)
local failedArt=byName(world,"ARMShaderWeather")
runAllSpawned();frames(35)
assert(byName(weatherCells(failedArt)[1],"Rain").Texture=="rbxassetid://1822883048",
    "an unloadable local particle image must not replace the fallback")
card.Options.Rain.Metadata.callback(false)
preloadMode="success"

-- Unsupported rain-specific properties cannot prevent independent snow.
Instance.failProperty.ParticleEmitter={Rate=true,name="Rain"}
card.Options.Rain.Metadata.callback(true)
card.Options.Snow.Metadata.callback(true)
local isolatedWeather=byName(world,"ARMShaderWeather")
frames(35)
assert(card.Enabled and isolatedWeather and byName(weatherCells(isolatedWeather)[1],"Snow").Enabled
    and not byName(weatherCells(isolatedWeather)[1],"Rain"),
    "one particle style failing cannot destroy another weather effect")
Instance.failProperty.ParticleEmitter=nil
card.Options.Rain.Metadata.callback(false)
card.Options.Snow.Metadata.callback(false)
runAllSpawned()
pass("weather art failures and an incompatible style keep unrelated effects alive")

-- A failing optional emitter is not allowed to take down precipitation.
for _,case in ipairs({
    {name="Fog mist",option="Fog",missing="FogCell"},
    {name="Dust motes",option="Dust motes",missing="DustCell"},
    {name="Rain splashes",option=nil,missing="RainSplashCell"},
}) do
    Instance.failProperty.ParticleEmitter={Speed=true,name=case.name}
    card.Options.Rain.Metadata.callback(true)
    if case.option then card.Options[case.option].Metadata.callback(true) end
    local surviving=byName(world,"ARMShaderWeather")
    frames(35)
    assert(surviving and not byName(surviving,case.missing)
        and byName(weatherCells(surviving)[1],"Rain").Enabled,
        "a failed "..case.name.." must not disable rain")
    if case.option=="Fog" then assert(lighting.FogEnd==110,"distance fog remains active without mist particles") end
    Instance.failProperty.ParticleEmitter=nil
    if case.option then card.Options[case.option].Metadata.callback(false) end
    card.Options.Rain.Metadata.callback(false)
    runAllSpawned()
end
pass("fog, dust and splash emitter failures do not disable rain")

local constructor=RaycastParams.new
RaycastParams.new=function() error("shelter parameters unavailable") end
local warningsBefore=#notifications
card.Options.Rain.Metadata.callback(true)
local noParameters=byName(world,"ARMShaderWeather")
frames(35)
assert(noParameters and byName(weatherCells(noParameters)[1],"Rain").Enabled
    and #notifications==warningsBefore+1 and notifications[#notifications]:find("shelter",1,true),
    "rain stays visible with a single warning when ray parameters are unavailable")
RaycastParams.new=constructor
card.Options.Rain.Metadata.callback(false);runAllSpawned()

host.state.resolveAsset=function() return nil,"not available" end
card.Options.Rain.Metadata.callback(true)
local fallback=byName(world,"ARMShaderWeather")
local fallbackEmitter=byName(weatherCells(fallback)[1],"Rain")
runAllSpawned()
assert(fallbackEmitter.Texture=="rbxassetid://1822883048","the streak fallback survives a missing local image")
Instance.fail.ParticleEmitter=true
card.Options.Snow.Metadata.callback(true)
assert(card.Enabled and renderable(color) and not byName(world,"ARMShaderWeather")
    and activeHandles("Shaders weather")==0,"no empty weather scheduler when all emitters fail")
assert(notifications[#notifications]:find("particles unavailable",1,true))
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

-- A single unsupported post effect used to cancel the entire Shaders card.
card.Options["Glass reflections"].Metadata.callback(true)
Instance.fail.BloomEffect=true
local ok=pcall(features.Shaders.toggle,true)
assert(ok and card.Enabled and renderable(byName(lighting,"ARMShaderColor"))
    and renderable(byName(lighting,"ARMShaderRays")),"a missing Bloom must not stop other post effects")
assert(not byName(lighting,"ARMShaderBloom") and activeHandles("Shaders surfaces")==1,
    "surface options must start even without Bloom")
card.Options.Rain.Metadata.callback(true);frames(35)
assert(byName(world,"ARMShaderWeather"),"weather must remain independent of post effects")
Instance.fail.BloomEffect=nil
features.Shaders.toggle(false);runAllSpawned()
features.Shaders.toggle(true)
assert(renderable(byName(lighting,"ARMShaderBloom")))
Shaders.destroy()
assert(not card.Enabled and activeHandles()==0 and not byName(lighting,"ARMShaderColor"))
pass("a missing post effect is isolated; re-enable and destroy cleanly")

-- Saved toggle values may be delivered synchronously while the UI is built.
local fallbackHost=table.clone(host);fallbackHost.state={}
function fallbackHost.addToggleOption(_,name,default,callback)
    callback(if name=="Fog" then true elseif name=="Surface textures" then false else default)
    return {callback=callback}
end
local savedAtmosphere=Instance.new("Atmosphere");savedAtmosphere.Density=0.23;savedAtmosphere.Parent=lighting
local fallbackFramework=Framework.init(fallbackHost)
local saved=Shaders.init({framework=fallbackFramework,host=fallbackHost,libraries=libraries})
assert(saved.Options.Fog.Value and not saved.Options["Surface textures"].Value
    and not saved.Options["Floor reflections"] and not saved.Options.Look)
local restoreNotifications=#notifications
features.Shaders.toggle(true)
assert(#notifications==restoreNotifications,
    "v177: replaying saved toggle values must not toast about a disabled card")
assert(savedAtmosphere.Density==0.58, "saved fog restores without a floor mirror")
Shaders.destroy();flushDeferred();assert(savedAtmosphere.Density==0.23)
pass("synchronous saved-toggle restoration is safe and cannot restore removed looks")
'''


def lua_quote(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def main() -> None:
    script_text = (PRELUDE + "\nlocal FRAMEWORK_SOURCE = " + lua_quote(FRAMEWORK)
                   + "\nlocal SHADERS_SOURCE = " + lua_quote(SHADERS) + "\n" + BODY)
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "shaders.luau"
        script.write_text(script_text, encoding="utf-8")
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
