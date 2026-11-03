#!/usr/bin/env python3
"""Run the reflection library with mathematical CFrame/Instance mocks.

Checks projection geometry, safe clones, work bounds and teardown. This does
not render pixels or measure Roblox/Delta compatibility or GPU performance.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/libraries/ShaderReflection.lua').read_text(encoding='utf-8')
SHADERS = (ROOT / 'src/games/universal/Render/Shaders.lua').read_text(encoding='utf-8')

PRELUDE = r'''
local vmeta = {}
Vector3 = {}
function Vector3.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vmeta) end
Vector3.zero=Vector3.new(0,0,0)
function Vector3.FromNormalId(id)
    assert(id=='Top'); return Vector3.new(0,1,0)
end
function vmeta.__index(v,k)
    if k=='Magnitude' then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    if k=='Unit' then local m=v.Magnitude;return if m==0 then Vector3.zero else v/m end
    if k=='Dot' then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
    if k=='Cross' then return function(a,b) return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end end
end
function vmeta.__add(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
function vmeta.__sub(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
function vmeta.__unm(a) return Vector3.new(-a.X,-a.Y,-a.Z) end
function vmeta.__mul(a,b)
    if type(a)=='number' then a,b=b,a end
    if type(b)=='number' then return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
    return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
function vmeta.__div(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end
function vmeta.__eq(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
Vector2={new=function(x,y) return {X=x,Y=y} end}
UDim2={fromScale=function(x,y) return {X={Scale=x},Y={Scale=y}} end}
Color3={fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}

local cfmeta={}
CFrame={}
local function cf(p,r,u,b) return setmetatable({p=p,r=r,u=u,b=b},cfmeta) end
local I=Vector3.new(1,0,0);local J=Vector3.new(0,1,0);local K=Vector3.new(0,0,1)
function CFrame.new(a,b,c,r00,r01,r02,r10,r11,r12,r20,r21,r22)
    if type(a)=='table' then return cf(a,I,J,K) end
    local p=Vector3.new(a or 0,b or 0,c or 0)
    if r00~=nil then return cf(p,Vector3.new(r00,r10,r20),Vector3.new(r01,r11,r21),Vector3.new(r02,r12,r22)) end
    return cf(p,I,J,K)
end
function CFrame.fromMatrix(p,r,u,b) return cf(p,r,u,b or r:Cross(u)) end
function CFrame.fromAxisAngle(a,angle)
    local x,y,z=a.X,a.Y,a.Z
    local c,s,t=math.cos(angle),math.sin(angle),1-math.cos(angle)
    return cf(Vector3.zero,Vector3.new(t*x*x+c,t*x*y+s*z,t*x*z-s*y),
        Vector3.new(t*x*y-s*z,t*y*y+c,t*y*z+s*x),
        Vector3.new(t*x*z+s*y,t*y*z-s*x,t*z*z+c))
end
function CFrame.Angles(x,y,z)
    return CFrame.fromAxisAngle(I,x)*CFrame.fromAxisAngle(J,y)*CFrame.fromAxisAngle(K,z)
end
function cfmeta.__index(a,k)
    if k=='Position' then return a.p end
    if k=='RightVector' then return a.r end
    if k=='UpVector' then return a.u end
    if k=='ZVector' then return a.b end
    if k=='LookVector' then return -a.b end
    if k=='Rotation' then return cf(Vector3.zero,a.r,a.u,a.b) end
    if k=='PointToWorldSpace' then return function(self,v) return self*v end end
    if k=='PointToObjectSpace' then return function(self,v)
        local d=v-self.p;return Vector3.new(d:Dot(self.r),d:Dot(self.u),d:Dot(self.b))
    end end
end
function cfmeta.__mul(a,b)
    if getmetatable(b)==vmeta then return a.p+a.r*b.X+a.u*b.Y+a.b*b.Z end
    local function rot(v) return a.r*v.X+a.u*v.Y+a.b*v.Z end
    return cf(a*b.p,rot(b.r),rot(b.u),rot(b.b))
end
function cfmeta.__add(a,b) return cf(a.p+b,a.r,a.u,a.b) end
Enum={NormalId={Top='Top'},RaycastFilterType={Exclude='Exclude'},
    SurfaceGuiSizingMode={FixedSize='FixedSize'},ZIndexBehavior={Sibling='Sibling'},
    HumanoidDisplayDistanceType={None='None'},HumanoidHealthDisplayType={AlwaysOff='AlwaysOff'}}
RaycastParams={new=function() return {} end}
OverlapParams={new=function() return {} end}
local warns={}
warn=function(s) table.insert(warns,tostring(s)) end

local all,created={},{}
local candidateChecks=0
local methods={}
function methods:IsA(name)
    if name=='BasePart' and tostring(self.Name):find('ProbeFloor',1,true) then candidateChecks+=1 end
    return self.ClassName==name or (name=='BasePart' and (self.ClassName=='Part' or self.ClassName=='MeshPart'))
        or (name=='Decal' and self.ClassName=='Texture')
        or (name=='DataModelMesh' and self.ClassName=='SpecialMesh')
        or (name=='Clothing' and (self.ClassName=='Shirt' or self.ClassName=='Pants'))
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
    local out={}
    local function walk(parent) for _,c in ipairs(parent.children) do table.insert(out,c);walk(c) end end
    walk(self);return out
end
function methods:FindFirstChild(name)
    for _,c in ipairs(self.children) do if c.Name==name and not c.destroyed then return c end end
end
function methods:FindFirstChildOfClass(class)
    for _,c in ipairs(self.children) do if c:IsA(class) and not c.destroyed then return c end end
end
function methods:Destroy()
    if self.destroyed then return end
    for _,c in ipairs(table.clone(self.children)) do c:Destroy() end
    self.Parent=nil;self.destroyed=true
end
function methods:ClearAllChildren() for _,c in ipairs(table.clone(self.children)) do c:Destroy() end end
local instanceMeta={}
function instanceMeta.__index(obj,k)
    if k=='Position' and obj.props.CFrame then return obj.props.CFrame.Position end
    return methods[k] or obj.props[k]
end
function instanceMeta.__newindex(obj,k,v)
    if k=='Parent' then
        local old=obj.props.Parent
        if old then for i,c in ipairs(old.children) do if c==obj then table.remove(old.children,i);break end end end
        obj.props.Parent=v
        if v then table.insert(v.children,obj) end
    elseif k=='Position' and obj.props.CFrame then
        local f=obj.props.CFrame;obj.props.CFrame=cf(v,f.r,f.u,f.b)
    else obj.props[k]=v end
end
Instance={failClass=nil}
function Instance.new(class)
    if Instance.failClass==class then error('cannot create '..class) end
    created[class]=(created[class] or 0)+1
    local obj=setmetatable({ClassName=class,children={},destroyed=false,props={Name=class,
        Archivable=true,Anchored=false,CanCollide=true,CanTouch=true,CanQuery=true,
        CastShadow=true,Transparency=0,Size=Vector3.new(2,2,2),CFrame=CFrame.new()}},instanceMeta)
    table.insert(all,obj);return obj
end
function methods:Clone()
    if not self.Archivable then return nil end
    local out=Instance.new(self.ClassName)
    for k,v in pairs(self.props) do if k~='Parent' then out.props[k]=v end end
    for _,c in ipairs(self.children) do local copy=c:Clone();if copy then copy.Parent=out end end
    return out
end
local function parent(class,name,p)
    local x=Instance.new(class);x.Name=name;x.Parent=p;return x
end
local world=Instance.new('Workspace');world.Name='Workspace'
local playerGui=Instance.new('PlayerGui');playerGui.Name='PlayerGui'
local character=parent('Model','LocalCharacter',world)
local root=parent('Part','HumanoidRootPart',character);root.Transparency=1;root.Position=Vector3.new(0,3,0)
local originalHumanoid=parent('Humanoid','Humanoid',character);originalHumanoid.RigType='R15'
local shirt=parent('Shirt','Shirt',character);shirt.ShirtTemplate='rbxassetid://123';parent('Script','shirtScript',shirt)
local pants=parent('Pants','Pants',character);pants.PantsTemplate='rbxassetid://456'
local body={}
for i=1,28 do
    local p=parent('Part','Local'..i,character);p.Position=Vector3.new(i/10,3+i/10,0)
    local decal=parent('Decal','Face',p);parent('Script','nested',decal)
    local mesh=parent('SpecialMesh','Shape',p);parent('LocalScript','nested',mesh)
    parent('Script','must-not-run',p);parent('Weld','joint',p)
    table.insert(body,p)
end
local otherCharacter=parent('Model','OtherCharacter',world)
local otherRoot=parent('Part','HumanoidRootPart',otherCharacter);otherRoot.Transparency=1;otherRoot.Position=Vector3.new(5,3,0)
for i=1,15 do local p=parent('MeshPart','Other'..i,otherCharacter);p.Position=Vector3.new(5,3+i/10,0) end
local player={Character=character}
local other={Character=otherCharacter}
local players={GetPlayers=function() return {player,other} end}
local floor=parent('Part','Floor',world);floor.Anchored=true;floor.Size=Vector3.new(60,1,60);floor.Position=Vector3.new(0,-0.5,0)
local hit={Instance=floor,Position=Vector3.new(0,0,0),Normal=Vector3.new(0,1,0)}
local hitEnabled=true
local rayCount,queryCount,lastQueryPosition,lastRayDepth=0,0,nil,nil
local rayObstacles={}
function methods:Raycast(origin,direction,params)
    assert(params.FilterType=='Exclude' and #params.FilterDescendantsInstances>=1
        and #params.FilterDescendantsInstances<=5)
    assert((direction.Y==-15 or direction.Y==-80) and params.IgnoreWater)
    lastRayDepth=-direction.Y;rayCount+=1
    for _, obstacle in ipairs(rayObstacles) do
        if not table.find(params.FilterDescendantsInstances,obstacle) then
            return {Instance=obstacle,Position=Vector3.new(0,1,0),Normal=Vector3.new(0,1,0)}
        end
    end
    return if hitEnabled and not table.find(params.FilterDescendantsInstances,hit.Instance) then hit else nil
end
local nearby={}
for i=1,130 do
    local p=parent('Part','Wall'..i,world);p.Anchored=true;p.Size=Vector3.new(2,10,10)
    p.Position=Vector3.new(i/3,5,8);table.insert(nearby,p)
end
local below=parent('Part','BelowMirror',world);below.Anchored=true;below.Size=Vector3.new(4,4,4)
below.Position=Vector3.new(0,-6,0);table.insert(nearby,1,below)
local npc=parent('Model','NPC',world);parent('Humanoid','Humanoid',npc)
local npcPart=parent('Part','NPCPart',npc);npcPart.Anchored=true;table.insert(nearby,1,npcPart)
local tool=parent('Tool','Tool',world);local toolPart=parent('Part','ToolPart',tool);toolPart.Anchored=true;table.insert(nearby,1,toolPart)
function methods:GetPartBoundsInRadius(position,radius,params)
    queryCount+=1;lastQueryPosition=position
    assert(radius==32 and params.MaxParts==100 and params.FilterType=='Exclude')
    return table.clone(nearby)
end
local camera=parent('Camera','Camera',world);camera.CFrame=CFrame.new(0,10,10);world.CurrentCamera=camera
local handles={};local manager={failRender=false}
function manager:Connect(fn,phase,label)
    if phase=='render' and self.failRender then error('render scheduler denied') end
    local h={callback=fn,phase=phase,label=label,Connected=true}
    function h:Disconnect() self.Connected=false end
    table.insert(handles,h);return h
end
local function liveHandles()
    local n=0;for _,h in ipairs(handles) do if h.Connected then n+=1 end end;return n
end
local function frames(n,dt)
    for _=1,n do
        local before=created.Part or 0
        for _,h in ipairs(table.clone(handles)) do if h.Connected and h.phase~='render' then h.callback(dt) end end
        local made=(created.Part or 0)-before
        assert(made<=3,'no more than three part copies per tick: '..made)
        for _,h in ipairs(table.clone(handles)) do if h.Connected and h.phase=='render' then h.callback(dt) end end
    end
end
local host={workspace=world,LocalPlayer=player,PlayerGui=playerGui,Players=players,TaskManager=manager}
local notices={}
local fatalNotices={}
local function report(s,fatal) table.insert(notices,s);table.insert(fatalNotices,fatal==true) end
local function find(parent,name) return parent:FindFirstChild(name) end
local function findDeep(parent,name)
    for _,child in ipairs(parent:GetDescendants()) do if child.Name==name then return child end end
end
local function countParts(parent)
    local n=0;for _,child in ipairs(parent:GetDescendants()) do if child:IsA('BasePart') then n+=1 end end;return n
end
local function near(a,b,eps) assert(math.abs(a-b)<(eps or 1e-6),tostring(a)..' != '..tostring(b)) end
local function vec(a,b) near(a.X,b.X);near(a.Y,b.Y);near(a.Z,b.Z) end
local function pass(s) print('PASS',s) end
'''

BODY = r'''
local Module=assert(loadstring(SOURCE))()
local api=Module.init(host)
local session=assert(api:Start(report));assert(liveHandles()==2)
local folder=find(world,'ARMShaderFloorReflection')
local plane=find(folder,'ReflectionSurface')
local gui=find(playerGui,'ARMShaderFloorReflection')
local viewport=find(gui,'Reflection');local viewCamera=viewport.CurrentCamera
local scene=find(viewport,'ReflectedScene')
assert(gui.Parent==playerGui and gui.Adornee==plane and gui.Face=='Top' and gui.ClipsDescendants)
assert(gui.SizingMode=='FixedSize' and not gui.AlwaysOnTop and gui.ResetOnSpawn==false)
assert(plane.Transparency==1 and plane.Anchored and not plane.CanCollide and not plane.CanQuery and not plane.CanTouch)
assert(viewport.BackgroundTransparency==1 and viewport.ImageTransparency==0.12)
frames(40,0.1)
assert(gui.Enabled and countParts(scene)==54,'24 local + 12 other + 18 static copies')
assert(queryCount<=3 and rayCount<=21,'bounded floor probes and scene queries')
assert(floor.Transparency==0 and floor.CanCollide and floor.Anchored and floor.Size.X==60)
near(plane.Size.X,59.96);near(plane.Size.Z,59.96)
near(plane.Position.Y,0.04)
local copy=findDeep(scene,'Local1');assert(copy)
local model=copy.Parent;local mirrorHumanoid=find(model,'Humanoid')
assert(model.Name=='ReflectedActor' and mirrorHumanoid and mirrorHumanoid.RigType=='R15'
    and not mirrorHumanoid.AutoRotate and mirrorHumanoid.PlatformStand
    and not mirrorHumanoid.RequiresNeck and not mirrorHumanoid.BreakJointsOnDeath
    and find(model,'HumanoidRootPart').Transparency==1)
assert(find(model,'Shirt').ShirtTemplate==shirt.ShirtTemplate and find(model,'Pants').PantsTemplate==pants.PantsTemplate)
assert(#find(model,'Shirt'):GetChildren()==0 and find(shirt,'shirtScript'),'clothes copied without scripts')
vec(copy.CFrame.Position,Vector3.new(0.1,-3.1,0))
vec(copy.CFrame.RightVector,Vector3.new(-1,0,0));vec(copy.CFrame.UpVector,Vector3.new(0,-1,0))
assert(copy.Anchored and not copy.CanCollide and not copy.CanTouch and not copy.CanQuery)
assert(#copy:GetChildren()==2 and find(copy,'Face') and find(copy,'Shape'))
assert(#find(copy,'Face'):GetChildren()==0 and #find(copy,'Shape'):GetChildren()==0)
assert(find(body[1],'must-not-run') and #find(body[1],'Face'):GetChildren()==1,'source hierarchy untouched')
assert(not findDeep(scene,'ToolPart') and not findDeep(scene,'NPCPart') and not findDeep(scene,'BelowMirror'))
local offset=10/59.96;local scale=1+2*offset
near(viewport.Position.X.Scale,0.5-offset);near(viewport.Position.Y.Scale,0.5)
near(viewport.Size.X.Scale,scale);near(viewport.Size.Y.Scale,scale)
assert(viewCamera.FieldOfView==120)
near(viewCamera.CFrame.RightVector.Magnitude,9.94*math.tan(math.rad(60))/29.98/scale)
assert(gui.CanvasSize.X<=1024 and gui.CanvasSize.Y<=1024
    and gui.CanvasSize.X*viewport.Size.X.Scale<=1024
    and gui.CanvasSize.Y*viewport.Size.Y.Scale<=1024,
    'off-axis viewport enlargement must stay within the effective pixel budget')
pass('stronger full-floor off-axis view, mirrored pose, bounded copies and original floor')

root.Position=Vector3.new(24,3,0);hit.Position=Vector3.new(24,0,0);frames(25,0.1)
near(plane.Position.X,0.02);near(lastQueryPosition.X,24)
root.Position=Vector3.new(0,3,0);hit.Position=Vector3.new(0,0,0);frames(3,0.1)
pass('scene scanning follows the avatar rather than the centre of a large floor')

body[1].CFrame=CFrame.new(2,6,3)*CFrame.Angles(0,math.pi/3,0)
frames(1,0.05)
vec(copy.CFrame.Position,Vector3.new(2,-6,3))
local right=body[1].CFrame.RightVector
vec(copy.CFrame.RightVector,Vector3.new(-right.X,right.Y,-right.Z))
assert(copy.CFrame.RightVector:Cross(copy.CFrame.UpVector):Dot(copy.CFrame.ZVector)>0.999)
pass('animated avatar positions and proper-handed orientation are updated')

camera.CFrame=CFrame.new(0,0.2,0);frames(1,0.05)
assert(gui.Enabled and viewCamera.FieldOfView==120 and viewCamera.CFrame.RightVector.Magnitude>0)
camera.CFrame=CFrame.new(0,-1,0);frames(1,0.05);assert(not gui.Enabled)
camera.CFrame=CFrame.new(0,200,0);frames(1,0.05);assert(not gui.Enabled)
camera.CFrame=CFrame.fromMatrix(Vector3.new(0,10,0),Vector3.new(1,0,0),Vector3.new(0,0,1),Vector3.new(0,-1,0))
frames(1,0.05);assert(not gui.Enabled,'do not render the patch behind an upward-looking camera')
camera.CFrame=CFrame.new(0,10,150);frames(1,0.05);assert(not gui.Enabled,'off-axis size stays bounded')
world.CurrentCamera=nil;frames(1,0.05);assert(not gui.Enabled)
world.CurrentCamera=camera;camera.CFrame=CFrame.new(0,10,10);frames(1,0.05);assert(gui.Enabled)
pass('near-plane FOV clamp, under-floor/far-camera culling and camera recovery')

-- Many maps place invisible collision proxies or small props above the visible
-- floor. The first ray hit must not permanently hide the real mirror surface.
local proxy=parent('Part','InvisibleCollider',world);proxy.Anchored=true;proxy.Transparency=1
proxy.Size=Vector3.new(40,1,40)
local small=parent('Part','SmallProp',world);small.Anchored=true;small.Size=Vector3.new(1,1,1)
rayObstacles={proxy,small};local raysBefore=rayCount
frames(8,0.1)
assert(gui.Enabled and countParts(scene)>0 and rayCount-raysBefore<=15,
    'skip a few invalid blockers without unbounded raycasting')
rayObstacles={};proxy:Destroy();small:Destroy()
-- Custom rigs can lack HumanoidRootPart entirely. Use the camera as a safe
-- fallback anchor rather than disabling all floor reflections.
root.Parent=nil;frames(10,0.1)
assert(gui.Enabled and countParts(scene)>0 and lastRayDepth==80,
    'camera anchor searches farther without a standard humanoid root')
root.Parent=character;frames(4,0.1)
player.Character=nil;frames(25,0.1)
assert(gui.Enabled and countParts(scene)>0,'spectator cameras can still reflect eligible nearby scene geometry')
player.Character=character;frames(25,0.1)
pass('transparent blockers and nonstandard character roots do not hide valid floors')

local previousCopy=copy
hitEnabled=false;frames(4,0.1)
assert(not gui.Enabled and countParts(scene)==0 and #scene:GetChildren()==0 and previousCopy.destroyed)
frames(75,0.1);assert(#notices==1 and notices[1]:find('flat solid floor',1,true))
frames(80,0.1);assert(#notices==1,'missing-floor warning is not spammed')
hitEnabled=true;frames(25,0.1);assert(gui.Enabled and countParts(scene)==54)
pass('no-floor culling, one warning, stale-copy release and recovery')

local oldFloor=floor
local nextFloor=parent('Part','NewFloor',world);nextFloor.Anchored=true;nextFloor.Size=Vector3.new(30,1,30)
nextFloor.Position=Vector3.new(0,1.5,0);hit={Instance=nextFloor,Position=Vector3.new(0,2,0),Normal=Vector3.new(0,1,0)}
root.Position=Vector3.new(0,5,0);frames(3,0.1)
near(plane.Position.Y,2.04)
local newCopy=findDeep(scene,'Local1');assert(newCopy);near(newCopy.Position.Y,-2)
assert(oldFloor.Transparency==0 and nextFloor.Transparency==0)
hit.Normal=Vector3.new(0,0.5,0);frames(3,0.1);assert(not gui.Enabled and countParts(scene)==0)
hit.Normal=Vector3.new(0,1,0);nextFloor.Anchored=false;frames(25,0.1);assert(gui.Enabled)
nextFloor.Position=Vector3.new(0,2.5,0);hit.Position=Vector3.new(0,3,0);frames(4,0.1)
near(plane.Position.Y,3.04);assert(not nextFloor.Anchored,'a moving floor is never anchored by the mirror')
nextFloor.Position=Vector3.new(0,1.5,0);hit.Position=Vector3.new(0,2,0)
nextFloor.Anchored=true;nextFloor.Size=Vector3.new(2,1,2);frames(3,0.1);assert(not gui.Enabled)
nextFloor.Size=Vector3.new(30,1,30);frames(25,0.1);assert(gui.Enabled and countParts(scene)==54)
pass('floor changes and moving platforms follow their plane without modifying physics')

nextFloor.CFrame=CFrame.new(0,1.5,0)*CFrame.Angles(0,0.4,0.1)
local point=nextFloor.CFrame:PointToWorldSpace(Vector3.new(0,0.5,0))
local normal=nextFloor.CFrame.UpVector
hit.Position=point;hit.Normal=normal;root.Position=point+Vector3.new(0,3,0)
frames(4,0.1);assert(gui.Enabled)
local reflected=findDeep(scene,'Local1').Position
local source=body[1].Position
vec(reflected,source-normal*(2*(source-point):Dot(normal)))
near((source-point):Dot(normal),-(reflected-point):Dot(normal))
nextFloor.CFrame=CFrame.new(0,1.5,0);hit.Position=Vector3.new(0,2,0);hit.Normal=Vector3.new(0,1,0)
root.Position=Vector3.new(0,5,0);frames(3,0.1)
pass('reflection plane follows rotated and mildly tilted floors')

local newCharacter=parent('Model','Respawn',world)
local newRoot=parent('Part','HumanoidRootPart',newCharacter);newRoot.Transparency=1;newRoot.Position=Vector3.new(0,5,0)
local newBody=parent('Part','NewBody',newCharacter);newBody.Position=Vector3.new(0,6,0)
player.Character=newCharacter;frames(25,0.1)
assert(findDeep(scene,'NewBody') and not findDeep(scene,'Local1') and countParts(scene)==32)
newBody:Destroy();frames(2,0.1);assert(not findDeep(scene,'NewBody'))
pass('respawn, streamed-out parts and cleanup of stale avatar copies')

session:Stop();session:Stop()
assert(liveHandles()==0 and folder.destroyed and plane.destroyed and gui.destroyed and scene.destroyed)
assert(not find(world,'ARMShaderFloorReflection') and not find(playerGui,'ARMShaderFloorReflection'))
assert(not oldFloor.destroyed and not nextFloor.destroyed and not character.destroyed)
pass('idempotent stop disconnects both callbacks and destroys only owned resources')

for _,class in ipairs({'Part','SurfaceGui','ViewportFrame','Camera','WorldModel'}) do
    Instance.failClass=class
    local failed=api:Start(report)
    assert(not failed and liveHandles()==0 and not find(world,'ARMShaderFloorReflection')
        and not find(playerGui,'ARMShaderFloorReflection'),'partial setup leak: '..class)
end
Instance.failClass=nil
manager.failRender=true
local failed,reason=api:Start(report)
assert(not failed and reason:find('render scheduler denied',1,true) and liveHandles()==0
    and not find(world,'ARMShaderFloorReflection') and not find(playerGui,'ARMShaderFloorReflection'))
manager.failRender=false
pass('setup and second-scheduler failures roll back every resource')

local replacementBody=parent('Part','ReplacementBody',newCharacter);replacementBody.Position=Vector3.new(0,6,0)
replacementBody.Archivable=false
local warningCount=#notices
local noAvatar=assert(api:Start(report));frames(30,0.1)
assert(#notices==warningCount+1 and notices[#notices]:find('Avatar parts could not be copied',1,true)
    and not fatalNotices[#fatalNotices])
noAvatar:Stop();replacementBody.Archivable=true
local projectionFailure=assert(api:Start(report));frames(4,0.1)
camera.CFrame={Position=Vector3.new(0,10,10)}
warningCount=#notices;frames(1,0.1)
assert(liveHandles()==0 and not find(world,'ARMShaderFloorReflection')
    and notices[#notices]:find('Floor projection unavailable',1,true) and #notices==warningCount+1
    and fatalNotices[#fatalNotices])
camera.CFrame=CFrame.new(0,10,10)
local externalRemoval=assert(api:Start(report));local removed=find(world,'ARMShaderFloorReflection')
removed:Destroy();warningCount=#notices;frames(1,0.1)
assert(liveHandles()==0 and not find(playerGui,'ARMShaderFloorReflection')
    and notices[#notices]:find('Floor reflection unavailable',1,true) and #notices==warningCount+1
    and fatalNotices[#fatalNotices])
pass('uncloneable avatars and runtime failures are reported without leaking callbacks')

local a=assert(api:Start(report));local b=assert(api:Start(report));assert(liveHandles()==4)
Module.destroy();assert(liveHandles()==0 and not find(world,'ARMShaderFloorReflection') and not find(playerGui,'ARMShaderFloorReflection'))
pass('library destruction stops every outstanding session')

-- The map walker reports other floors even when the avatar is not on them.
-- No more than two additional viewports may exist, each with at most 32
-- cloned parts; their planes and poses are tested, not rendered pixels.
local again=Module.init(host)
local multi=assert(again:Start(report))
local extra={}
for i,position in ipairs({Vector3.new(-28,1.5,-18),Vector3.new(28,1.5,-18),Vector3.new(0,1.5,-24)}) do
    local p=parent('Part','DistantFloor'..i,world);p.Anchored=true
    p.Size=Vector3.new(40,1,35);p.Position=position;table.insert(extra,p);multi:Observe(p)
end
multi:Observe(nextFloor) -- primary is never duplicated
frames(120,0.1)
local function remotes()
    local out={}
    for _,child in ipairs(playerGui:GetChildren()) do
        if child.Name=='ARMShaderFloorReflectionRemote' then table.insert(out,child) end
    end
    return out
end
local remote=remotes();assert(#remote==2,'two visible floors besides the main one should get viewports')
for _,g in ipairs(remote) do
    local frame=find(g,'Reflection');local mirrorScene=find(frame,'ReflectedScene')
    assert(g.Adornee and g.Adornee.Parent==find(world,'ARMShaderFloorReflection') and g.Enabled)
    assert(frame.ImageTransparency==0.12 and countParts(mirrorScene)>0 and countParts(mirrorScene)<=32)
    local mirroredBody=findDeep(mirrorScene,'ReplacementBody');assert(mirroredBody)
    near(mirroredBody.Position.Y,-2)
    assert(not findDeep(mirrorScene,'ToolPart') and not findDeep(mirrorScene,'NPCPart'))
end
local replaced=remote[1];local removedFloor
for _,f in ipairs(extra) do if math.abs(f.Position.X-replaced.Adornee.Position.X)<1 then removedFloor=f end end
assert(removedFloor);removedFloor.Parent=nil
frames(25,0.1)
assert(replaced.destroyed and #remotes()==2,'a streamed-out floor is replaced by another visible candidate')
multi:Stop()
assert(#remotes()==0 and liveHandles()==0 and not extra[2].destroyed and not extra[3].destroyed)
pass('map-observed floors get bounded independent mirrors and streaming cleanup')

-- v173 stretched the 1024-pixel primary canvas across as much as 256 studs.
-- Keep broad coverage, but allocate a denser local mirror for the avatar.
nextFloor.Size=Vector3.new(256,1,256)
local detailed=assert(again:Start(report));detailed:Observe(extra[3]);frames(120,0.1)
local mainGui=find(playerGui,'ARMShaderFloorReflection')
local mainPlane=mainGui.Adornee;local wideGui=nil;local neighbor=nil
for _,g in ipairs(remotes()) do
    if g.Adornee.Size.X>250 then wideGui=g else neighbor=g end
end
assert(mainPlane.Size.X<=64 and mainPlane.Size.Z<=64,'local mirror must retain avatar detail on very large floors')
assert(mainGui.CanvasSize.X/mainPlane.Size.X>8,'local floor pixel density must not collapse')
assert(wideGui and wideGui.Enabled and neighbor and #remotes()==2,
    'the broader floor and one other floor remain reflected within the same three-viewport cap')
assert(wideGui.Adornee.Position.Y < mainPlane.Position.Y, 'local detail lies above the wider surface')
local wideScene=find(find(wideGui,'Reflection'),'ReflectedScene')
assert(countParts(wideScene)>0 and countParts(wideScene)<=32)
newRoot.Position=Vector3.new(80,5,0);hit.Position=Vector3.new(80,2,0)
camera.CFrame=CFrame.new(80,10,10);frames(25,0.1)
near(mainPlane.Position.X,80);assert(wideGui.Enabled and wideGui.Adornee.Size.X>250)
-- On leaving the big floor its wide layer must not survive as a stale mirror.
hit={Instance=extra[3],Position=Vector3.new(0,2,-24),Normal=Vector3.new(0,1,0)}
newRoot.Position=Vector3.new(0,5,-24);camera.CFrame=CFrame.new(0,10,-14);frames(5,0.1)
assert(wideGui.destroyed and #remotes()<=2)
detailed:Stop();nextFloor.Size=Vector3.new(30,1,30)
hit={Instance=nextFloor,Position=Vector3.new(0,2,0),Normal=Vector3.new(0,1,0)}
newRoot.Position=Vector3.new(0,5,0);camera.CFrame=CFrame.new(0,10,10)
assert(#remotes()==0 and liveHandles()==0)
pass('large floor keeps a detailed local mirror plus bounded broad coverage')

-- The under-player probe accepts narrow solid floors; the broad layer must
-- not silently disappear just because the additional-floor filter is stricter.
nextFloor.Size=Vector3.new(256,1,4);camera.CFrame=CFrame.new(0,10,2)
local narrow=assert(again:Start(report));frames(80,0.1)
local narrowWide=nil
for _,g in ipairs(remotes()) do if g.Adornee.Size.X>250 then narrowWide=g end end
assert(narrowWide and narrowWide.Enabled,'large, narrow primary floor keeps broad coverage')
narrow:Stop();nextFloor.Size=Vector3.new(30,1,30);camera.CFrame=CFrame.new(0,10,10)
pass('primary wide layer uses the primary floor eligibility rules')

local isolated=assert(again:Start(report))
Instance.failClass='SurfaceGui'
isolated:Observe(extra[3]);local beforeFailure=#notices;frames(20,0.1)
assert(liveHandles()==2 and #remotes()==0 and #notices==beforeFailure+1
    and notices[#notices]:find('Additional floor reflections unavailable',1,true),
    'secondary allocation failure must not disable or leak the primary reflection')
Instance.failClass=nil;isolated:Stop();Module.destroy();assert(liveHandles()==0)
pass('secondary viewport setup failure is isolated and cleaned up')

nextFloor.Size=Vector3.new(256,1,256)
local fallback=assert(again:Start(report));Instance.failClass='SurfaceGui'
local failureNotices=#notices;frames(20,0.1)
local fallbackGui=find(playerGui,'ARMShaderFloorReflection')
assert(fallbackGui.Enabled and fallbackGui.Adornee.Size.X>250 and #remotes()==0,
    'failed wide-mirror allocation restores broad primary coverage')
assert(#notices==failureNotices+1 and liveHandles()==2)
Instance.failClass=nil;fallback:Stop();Module.destroy();nextFloor.Size=Vector3.new(30,1,30)
pass('large floor falls back to a broad primary mirror if allocation fails')

-- Integration: the real Shaders traversal must discover floors and feed the
-- real reflection library even when both texture and glass options are OFF.
Enum.Material={Plastic='Plastic',SmoothPlastic='SmoothPlastic',Glass='Glass',Concrete='Concrete',
    Asphalt='Asphalt',Pavement='Pavement',Wood='Wood',WoodPlanks='WoodPlanks',Brick='Brick',Grass='Grass',Marble='Marble'}
local originalRay=methods.Raycast
function methods:Raycast(origin,direction,params)
    if direction.Y==-80 then return {Instance=nextFloor} end
    return originalRay(self,origin,direction,params)
end
local lighting=Instance.new('Lighting')
lighting.EnvironmentSpecularScale=0.1;lighting.ShadowSoftness=0.1;lighting.GlobalShadows=false
host.Lighting=lighting;host.state={}
local shaderCard
local framework={Categories={Render={CreateModule=function(_,definition)
    shaderCard={Options={},Enabled=false,cleanups={}}
    function shaderCard:Clean(f) table.insert(self.cleanups,f) end
    function shaderCard:SetStatus(_) end
    function shaderCard:Notify(_) end
    function shaderCard:CreateNote(_) end
    function shaderCard:CreateToggle(option)
        self.Options[option.Name]={Value=option.Name=='Floor reflections'}
    end
    function shaderCard:Toggle(value)
        self.Enabled=value
        if not value then for _,f in ipairs(self.cleanups) do f() end;self.cleanups={} end
        definition.Function(value)
    end
    return shaderCard
end}}}
local reflectionApi=Module.init(host)
local shader=assert(loadstring(SHADERS_SOURCE))()
shader.init({host=host,framework=framework,libraries={shaderreflection=reflectionApi}})
shaderCard:Toggle(true)
assert(shaderCard.Options['Floor reflections'].Value and not shaderCard.Options['Surface textures'].Value
    and not shaderCard.Options['Glass reflections'].Value)
frames(180,0.05)
assert(#remotes()==2 and liveHandles()==3,
    'real floor-only scanner must discover two extra floors and retain bounded scheduler handles')
shader.destroy()
assert(#remotes()==0 and liveHandles()==0 and not find(world,'ARMShaderFloorReflection'))
Module.destroy();methods.Raycast=originalRay
pass('real Shaders traversal feeds the reflection library with other options off')

local boundedApi=Module.init(host);local bounded=assert(boundedApi:Start(report));local probes={}
for i=1,200 do
    local p=parent('Part','ProbeFloor'..i,world);p.Anchored=true;p.Size=Vector3.new(10,1,10)
    p.Position=Vector3.new(10000+i*20,1.5,-40);table.insert(probes,p);bounded:Observe(p)
end
candidateChecks=0;frames(1,0.05)
assert(candidateChecks<=32, 'large candidate selection is sliced across ticks')
frames(7,0.05);assert(candidateChecks==200, 'the bounded scan eventually inspects every candidate')
bounded:Stop();Module.destroy();for _,p in ipairs(probes) do p:Destroy() end
pass('additional-floor candidate selection is incrementally bounded')

host.state={isMobile=true};nextFloor.Size=Vector3.new(256,1,256)
local mobileApi=Module.init(host)
local mobile=assert(mobileApi:Start(report));mobile:Observe(extra[2]);mobile:Observe(extra[3])
frames(100,0.1)
local mobileGui=find(playerGui,'ARMShaderFloorReflection')
assert(mobileGui.CanvasSize.X<=768 and mobileGui.CanvasSize.Y<=768
    and mobileGui.Adornee.Size.X<=64 and mobileGui.CanvasSize.X/mobileGui.Adornee.Size.X>5)
local mobileWide=false
for _,g in ipairs(remotes()) do
    assert(g.CanvasSize.X<=384 and g.CanvasSize.Y<=384)
    if g.Adornee.Size.X>250 then mobileWide=true end
end
assert(mobileWide and #remotes()<=2,'mobile keeps broad coverage in the same viewport budget')
mobile:Stop();Module.destroy();host.state={};nextFloor.Size=Vector3.new(30,1,30)
assert(liveHandles()==0 and #remotes()==0)
pass('mobile viewport resolution and large-floor detail are bounded separately from desktop')
'''


def quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'shader_reflection.luau'
    path.write_text(PRELUDE + '\nlocal SOURCE=' + quote(SOURCE) + '\nlocal SHADERS_SOURCE=' + quote(SHADERS) + '\n' + BODY, encoding='utf-8')
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
