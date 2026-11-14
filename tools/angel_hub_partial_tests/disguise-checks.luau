AngelHub.moduleNames['Disguise Character']=true;V['Disguise Character']=false;AngelHub.setters['Disguise Character']=function(v)V['Disguise Character']=v end
for name,value in pairs({['Disguise Target ID']='123',['Disguise Mode']='Character',['Use Target Movement Animations']=true,
 ['Disguise Animation Speed']=1,['Show Target Emotes']=false})do V[name]=value;AngelHub.setters[name]=function(v)V[name]=v end end
local methods={};local nodeMeta={}
nodeMeta.__index=function(t,k)return methods[k] or t.props[k]end
nodeMeta.__tostring=function(t)return t.props.Name end
nodeMeta.__newindex=function(t,k,v)
 if k=='Parent'then
  local old=t.props.Parent;if old and old.children then for i,x in ipairs(old.children)do if x==t then table.remove(old.children,i);break end end end
  if v and v.children then table.insert(v.children,t)end
 end
 t.props[k]=v
end
local function node(class,name)local x=setmetatable({class=class,props={Name=name},children={}},nodeMeta);return x end
function methods:IsA(c)return self.class==c or (c=='BasePart' and self.class=='Part')end
function methods:GetChildren()return table.clone(self.children)end
function methods:GetDescendants()local out={};local function walk(x)for _,v in ipairs(x.children)do table.insert(out,v);walk(v)end end;walk(self);return out end
function methods:FindFirstChild(n)for _,v in ipairs(self.children)do if v.Name==n then return v end end end
function methods:FindFirstChildOfClass(n)for _,v in ipairs(self.children)do if v:IsA(n)then return v end end end
function methods:Destroy()self.destroyed=true;self.Parent=nil end
function methods:Clone()local x=node(self.class,self.Name);x.AnimationId=self.AnimationId;return x end
local owner=node('Model','Character');owner.Parent=workspace
local human=node('Humanoid','Humanoid');human.Parent=owner;human.Health=100;human.MaxHealth=100;human.RigType='R15';human.WalkSpeed=16;human.JumpPower=50;human.MoveDirection=Vector3.new(0,0,0)
function methods:AddAccessory(x)x.Parent=self.Parent end
local ownRoot=node('Part','HumanoidRootPart');ownRoot.Parent=owner;ownRoot.Position=Vector3.new(0,0,0);ownRoot.AssemblyLinearVelocity=Vector3.new(0,0,0);ownRoot.Anchored=false
local ownHead=node('Part','Head');ownHead.Parent=owner
local shirt=node('Shirt','MyShirt');shirt.Parent=owner
local accessory=node('Accessory','MyHat');accessory.Parent=owner
local face=node('Decal','face');face.Parent=ownHead
local animate=node('LocalScript','Animate');animate.Parent=owner
local walk=node('Folder','walk');walk.Parent=animate
local anim=node('Animation','WalkAnim');anim.AnimationId='rbxassetid://old';anim.Parent=walk
local track={Speed=.8};function track:AdjustSpeed(v)self.Speed=v end
local animator=node('Animator','Animator');animator.Parent=human
function methods:GetPlayingAnimationTracks()return {track}end
localPlayer.Character=owner
local descriptions={}
function playersService:GetHumanoidDescriptionFromUserId(id)
 local desc={WalkAnimation=456};function desc:Destroy()self.destroyed=true end;table.insert(descriptions,desc);return desc
end
local models={}
function playersService:CreateHumanoidModelFromDescription(desc,rig)
 assert(desc and rig=='R15');local model=node('Model','Staged');table.insert(models,model)
 local s=node('Shirt','NewShirt');s.Parent=model;local hat=node('Accessory','NewHat');hat.Parent=model
 local head=node('Part','Head');head.Parent=model;local newface=node('Decal','face');newface.Parent=head
 return model
end
installGameplay(screenGui);heartbeat:Fire(.21);assert(shirt.Parent==owner and anim.AnimationId=='rbxassetid://old')
assert(AngelHub.setters['Show Target Emotes'](true)==false and not V['Show Target Emotes'])
AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21)
assert(shirt.Parent==nil and accessory.Parent==nil and face.Parent==nil)
assert(owner:FindFirstChild('NewShirt') and owner:FindFirstChild('NewHat') and ownHead:FindFirstChild('face'))
assert(anim.AnimationId=='rbxassetid://456' and descriptions[1].destroyed and models[1].destroyed and track.Speed==.8)
V['Disguise Animation Speed']=1.5;heartbeat:Fire(.21);assert(track.Speed==1.5)
V['Disguise Animation Speed']=1;heartbeat:Fire(.21);assert(track.Speed==.8)
-- Never overwrite an external animation edit; never remove an externally added appearance item.
anim.AnimationId='rbxassetid://external';local external=node('Shirt','External');external.Parent=owner
AngelHub.setters['Disguise Character'](false)
assert(shirt.Parent==owner and accessory.Parent==owner and face.Parent==ownHead and external.Parent==owner)
assert(not owner:FindFirstChild('NewShirt') and anim.AnimationId=='rbxassetid://external')
-- Animation mode changes only slots, not appearance, and restores on disable.
V['Disguise Mode']='Animation';AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21)
assert(shirt.Parent==owner and owner:FindFirstChild('NewShirt')==nil and anim.AnimationId=='rbxassetid://456')
V['Disguise Animation Speed']=1.5;heartbeat:Fire(.21);assert(track.Speed==1.5)
track.Speed=1.2;AngelHub.setters['Disguise Character'](false);assert(anim.AnimationId=='rbxassetid://external' and track.Speed==1.2)
-- Numeric animation asset overrides work independently of target-animation cloning.
V['Disguise Mode']='Character';V['Use Target Movement Animations']=false;V['Walk Bundle ID']='789'
AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21);assert(anim.AnimationId=='rbxassetid://789')
V['Walk Bundle ID']='987';heartbeat:Fire(.21);assert(anim.AnimationId=='rbxassetid://external')
fakeNow+=.8;heartbeat:Fire(.21);assert(anim.AnimationId=='rbxassetid://987')
AngelHub.setters['Disguise Character'](false);assert(anim.AnimationId=='rbxassetid://external')
V['Walk Bundle ID']='';V['Use Target Movement Animations']=true
-- A target change is debounced and the old appearance is restored immediately.
V['Disguise Mode']='Character';AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21);assert(shirt.Parent==nil)
V['Disguise Target ID']='999';heartbeat:Fire(.21);assert(shirt.Parent==owner)
fakeNow+=.8;heartbeat:Fire(.21);assert(shirt.Parent==nil)
-- Respawn with the same model name still invalidates/restores the old character.
local oldOwner,oldHead=owner,ownHead;oldOwner.Parent=nil
owner=node('Model','Character');owner.Parent=workspace
human=node('Humanoid','Humanoid');human.Parent=owner;human.Health=100;human.MaxHealth=100;human.RigType='R15';human.MoveDirection=Vector3.new(0,0,0)
ownRoot=node('Part','HumanoidRootPart');ownRoot.Parent=owner;ownRoot.Position=Vector3.new(0,0,0);ownRoot.AssemblyLinearVelocity=Vector3.new(0,0,0)
ownHead=node('Part','Head');ownHead.Parent=owner;local secondShirt=node('Shirt','Second');secondShirt.Parent=owner
localPlayer.Character=owner;heartbeat:Fire(.21);assert(shirt.Parent==oldOwner and face.Parent==oldHead)
fakeNow+=.8;heartbeat:Fire(.21);assert(secondShirt.Parent==nil)
screenGui.Destroying:Fire();assert(secondShirt.Parent==owner)
