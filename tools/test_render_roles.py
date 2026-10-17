#!/usr/bin/env python3
"""Execute GameRoles, Render, Chams, Nametags and HP together with deterministic Instances."""
import os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
script=r'''
local function V(x,y,z) return {X=x or 0,Y=y or 0,Z=z or 0} end
local vmt={}
local Vector2,Vector3={},{}
function Vector2.new(x,y) return setmetatable(V(x,y),vmt) end
function Vector3.new(x,y,z) return setmetatable(V(x,y,z),vmt) end
vmt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vmt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vmt.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
vmt.__index=function(a,k)
 if k=='Magnitude' then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
 if k=='Unit' then return a*(1/a.Magnitude) end
end
Vector3.zero=Vector3.new(0,0,0)
local CFrame={new=function(pos) return setmetatable({Position=pos},{__mul=function(a,b) return a.Position+b end}) end}
local Color3={};Color3.__index=Color3
function Color3.new(r,g,b) return setmetatable({R=r or 0,G=g or 0,B=b or 0},Color3) end
function Color3.fromRGB(r,g,b) return Color3.new(r/255,g/255,b/255) end
function Color3:Lerp(b,t) return Color3.new(self.R+(b.R-self.R)*t,self.G+(b.G-self.G)*t,self.B+(b.B-self.B)*t) end
local function typeof(v) return getmetatable(v)==Color3 and 'Color3' or type(v) end
local Enum=setmetatable({}, {__index=function(t,k) local e=setmetatable({}, {__index=function(s,n) rawset(s,n,n);return n end});t[k]=e;return e end})
local UDim={new=function(s,o) return {Scale=s,Offset=o} end}
local UDim2={new=function(xs,xo,ys,yo) return {X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}} end}
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
local objects={}
local methods={}
local Instance={}
function Instance.new(class)
 local obj=setmetatable({props={Name=class,ClassName=class},children={}}, {
  __index=function(o,k) return methods[k] or o.props[k] end,
  __newindex=function(o,k,v)
   if k=='Parent' then
    local prev=o.props.Parent;if prev then local i=table.find(prev.children,o);if i then table.remove(prev.children,i) end end
    if v then table.insert(v.children,o) end
   end
   o.props[k]=v
  end})
 table.insert(objects,obj);return obj
end
function methods:IsA(class) return self.ClassName==class or class=='BasePart' and self.ClassName=='Part' end
function methods:FindFirstChild(name) for _,c in ipairs(self.children) do if c.Name==name then return c end end end
function methods:FindFirstChildOfClass(class) for _,c in ipairs(self.children) do if c:IsA(class) then return c end end end
function methods:GetChildren() return table.clone(self.children) end
function methods:Destroy() for _,c in ipairs(self:GetChildren()) do c:Destroy() end;self.Parent=nil;self.destroyed=true end
local function create(class,props) local o=Instance.new(class);for k,v in pairs(props) do o[k]=v end;return o end
local screen=Instance.new('ScreenGui');local workspace=Instance.new('Workspace')
local now=1;local os={clock=function() return now end}
local measureCalls=0
local game={GetService=function(_,n) assert(n=='TextService');return {GetTextSize=function(_,text,size) measureCalls+=1;return Vector2.new(utf8.len(text)*size*.6,size) end} end}
local function makePlayer(name)
 local p={Name=name,DisplayName='Ángel <b>',Character=Instance.new('Model')}
 local char=p.Character;char.Parent=workspace
 local hum=create('Humanoid',{Name='Humanoid',Health=100,MaxHealth=100,HipHeight=2,Parent=char})
 local root=create('Part',{Name='HumanoidRootPart',Size=Vector3.new(2,2,1),Position=Vector3.new(0,0,10),CFrame=CFrame.new(Vector3.new(0,0,10)),Parent=char})
 local head=create('Part',{Name='Head',Size=Vector3.new(2,2,2),Position=Vector3.new(0,2,10),Parent=char})
 return p,{Player=p,Character=char,Humanoid=hum,Health=100,MaxHealth=100,Head=head,RootPart=root,Distance=12,IsFriendly=false}
end
local player,target=makePlayer('Example')
local localPlayer,self=makePlayer('Local')
local targets={target}
local entity={Refresh=function(self) self.List=targets;return targets end,VisibleFrom=function() return true end}
local camera={ViewportSize=Vector2.new(360,640),WorldToViewportPoint=function(_,p) return Vector3.new(180+p.X*10,320-p.Y*10,p.Z),true end}
workspace.CurrentCamera=camera
local listeners,provider={},nil
local bridge={onEvent=function(fn) table.insert(listeners,fn);if provider then fn('roles',provider) end;return function() local i=table.find(listeners,fn);if i then table.remove(listeners,i) end end end}
local function emit(kind,p) for _,fn in ipairs(table.clone(listeners)) do fn(kind,p) end end
bridge.registerRoles=function(p) provider=p;emit('roles',p) end
bridge.unregisterRoles=function(p) if provider==p then provider=nil;emit('roles',nil) end end
bridge.playerRole=function(p) return provider and provider.Get(p) end
local host={Players={GetPlayers=function() return {localPlayer,player} end,PlayerRemoving={Connect=function() return {Disconnect=function() end} end}},create=create,ScreenGui=screen,workspace=workspace,LocalPlayer=localPlayer,state={activeGameName='MM2'},
 configData={states={},values={}},services={gameBridge=bridge}}
local framework={Modules={},Categories={Visuals={}}}
function framework.Categories.Visuals:CreateModule(def)
 local card={Name=def.Name,Options={},Enabled=false,cleanups={}}
 framework.Modules[def.Name]=card
 function card:RefreshVisibility()
  for name,o in pairs(self.Options) do
   o.Visible=not self.OptionFilter or self.OptionFilter(name)
   if o.Show then local s=self.Options[o.Show.Option];o.Visible=o.Visible and s~=nil and (not o.Show.Values and s.Value==true or o.Show.Values and table.find(o.Show.Values,s.Value)~=nil) end
  end
 end
 function card:CreateToggle(d) local o={Value=d.Default,Show=d.Show};function o:SetVisible(v) self.Visible=v end;self.Options[d.Name]=o;return o end
 card.CreateColor=card.CreateToggle;card.CreateSlider=card.CreateToggle
 function card:CreateDropdown(d) d.Default=d.List[d.Index];return self:CreateToggle(d) end
 function card:Event(signal,fn) local c=signal:Connect(fn);self:Clean(function() c:Disconnect() end) end
 function card:Clean(fn) table.insert(self.cleanups,fn) end
 function card:Render(fn) self.render=fn end
 function card:SetStatus(s) self.status=s end
 function card:Toggle(v)
  self.Enabled=v;def.Function(v)
  if not v then self.render=nil;for _,fn in ipairs(self.cleanups) do fn() end;table.clear(self.cleanups) end
 end
 return card
end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a)..' != '..tostring(b)) end
'''
for name,path in [('Roles','src/libraries/GameRoles.lua'),('Render','src/libraries/Render.lua'),('ESP','src/games/universal/Render/PlayerESP.lua'),('Chams','src/games/universal/Render/Chams.lua'),('Names','src/games/universal/Render/Nametags.lua'),('HP','src/games/universal/Render/HP.lua')]:
 script+='\nlocal '+name+'=(function()\n'+(ROOT/path).read_text()+'\nend)()\n'
script+=r'''
local roles=Roles.init(host)
local render=Render.init(host)
local context={host=host,render=render,entity=entity,framework=framework,services={gameRoles=roles,gameBridge=bridge,protectedTargets={isProtected=function() return false end}}}
local chams=Chams.init(context);local names=Names.init(context);local hp=HP.init(context)
local esp=ESP.init(context)
assert(not esp.Options['Name tags'] and not esp.Options['Health bar'] and not esp.Options['Health text'])
emit('extra',{Name='Future extra',Default=false})
assert(esp.Options['Future extra'],'generic ESP extras still register')
assert(not chams.Options.Nametags and not chams.Options['Nametag distance'])
assert(not chams.Options['Murderer colour'],'universal has no MM2 rows without a provider')
local red,green=Color3.fromRGB(255,20,40),Color3.fromRGB(20,255,40)
local role='Murderer'
local mm2={Name='MM2',DeadRoles={'Dead'},ReplacesTeams=true,Roles={'Murderer','Sheriff','Hero','Innocent','Dead'},Colors={Murderer=red},Get=function() return role end}
local unregister=roles:Register(mm2)
assert(not chams.Options.Teammates.Visible and not hp.Options.Teammates.Visible and not names.Options.Teammates.Visible)
assert(not hp.Options['Role colours'],'HP colour is health, not role')
for _,name in ipairs(mm2.Roles) do assert(chams.Options[name..' colour'] and chams.Options[name..' ESP']) end
chams.Options['Murderer colour'].Value=green
assert(names.Options['Murderer colour'].Value==red and mm2.Colors.Murderer==red,'palettes must be independent')
chams:Toggle(true);chams.render()
local highlight
for _,o in ipairs(workspace.children) do if o:IsA('Highlight') then highlight=o end end
assert(highlight and highlight.FillColor==green and highlight.Adornee==target.Character)
chams.Options['Murderer ESP'].Value=false;now+=1;chams.render();assert(highlight.destroyed)
chams.Options['Murderer ESP'].Value=true
-- Dead role includes an existing corpse; disabling it releases the highlight.
role='Dead';target.Humanoid.Health=0;targets={};now+=1;chams.render()
local corpse
for _,o in ipairs(workspace.children) do if o:IsA('Highlight') then corpse=o end end
assert(corpse and corpse.Adornee==target.Character)
chams.Options['Dead ESP'].Value=false;now+=1;chams.render();assert(corpse.destroyed)
role='Murderer';target.Humanoid.Health=100;targets={target}
esp:Toggle(true);esp.render();assert(screen:FindFirstChild('PlayerEspLayer').Visible)
workspace.CurrentCamera=nil;esp.render();assert(not screen:FindFirstChild('PlayerEspLayer').Visible)
workspace.CurrentCamera=camera;esp.render();assert(screen:FindFirstChild('PlayerEspLayer').Visible)
names:Toggle(true);names.render()
local nameLayer=screen:FindFirstChild('NametagsLayer')
local drawingRoot=nameLayer.children[1];local nameLabel=drawingRoot:FindFirstChild('Name')
assert(nameLabel and nameLabel.Text=='Ángel <b>' and nameLabel.RichText==false)
local width=nameLabel.Size.X.Offset;assert(width>0 and width<=336)
local m=measureCalls
for _=1,30 do names.render();assert(nameLabel.Size.X.Offset==width) end
assert(measureCalls==m,'cache text bounds; keep explicit width on later frames')
assert(nameLabel.Font=='Arial' and nameLabel.TextStrokeTransparency==1 and nameLabel.BackgroundTransparency==.5)
assert(not names.Options.Distance.Value and not names.Options['Show role'].Value)
assert(not nameLabel:FindFirstChildOfClass('UICorner') and not nameLabel:FindFirstChildOfClass('UIStroke'))
names.Options.Distance.Value=true;names.render();assert(string.sub(nameLabel.Text,1,1)=='[' and not string.find(nameLabel.Text,'studs'))
names.Options.Distance.Value=false;names.render()
local project=camera.WorldToViewportPoint
camera.WorldToViewportPoint=function() return Vector3.new(-100,200,10),false end
names.render();assert(#nameLayer.children==0,'offscreen tags do not get pinned to screen edges')
camera.WorldToViewportPoint=project
workspace.CurrentCamera=nil;names.render();assert(#nameLayer.children==0)
workspace.CurrentCamera=camera;names.render();assert(#nameLayer.children==1)
-- Future game / removal / ownership: no MM2-specific role names required.
local future={Name='Future',Roles={'Medic','Guard'},Colors={Medic=green},Get=function() return 'Medic' end}
local releaseFuture=roles:Register(future)
unregister();assert(provider==future,'stale cleanup must not remove new provider')
assert(chams.Options['Medic colour'] and chams.Options['Medic ESP'])
future.Get=function() return 'Murderer' end
for _,binding in ipairs(roles.bindings) do
 local colour,unknown=binding:Resolve(player,red)
 assert(unknown==nil and colour==red,'undeclared role never reuses a hidden old palette')
end
future.Get=function() return 'Medic' end
assert(not chams.Options['Murderer colour'].Visible and chams.Options.Teammates.Visible)
releaseFuture();assert(provider==nil and not chams.Options['Medic colour'].Visible)
-- HP can show only self, independently of Chams/Nametags/ESP.
chams:Toggle(false);names:Toggle(false);hp:Toggle(true)
hp.Options.Players.Value=false;hp.Options['Self HP'].Value=true;hp.render(1/60)
local hud=screen:FindFirstChild('SelfHP');assert(hud.Visible and hud:FindFirstChild('Heart').Text=='❤️')
assert(hud:FindFirstChild('Value').Text=='100 / 100')
self.Humanoid.Health=23;hp.render(.1)
assert(hud:FindFirstChild('Value').Text=='23 / 100')
local track=hud:FindFirstChild('Track');near(track:FindFirstChild('Fill').Size.X.Scale,.23)
assert(track:FindFirstChild('Damage').Size.X.Scale>.23)
localPlayer.Character=nil;hp.render(.1)
assert(hud:FindFirstChild('State')==nil and hud.Size.X.Offset==156);near(track:FindFirstChild('Fill').Size.X.Scale,0)
localPlayer,self=makePlayer('Respawn');host.LocalPlayer=localPlayer;self.Humanoid.MaxHealth=200;self.Humanoid.Health=150
hp.render(.1);near(track:FindFirstChild('Fill').Size.X.Scale,.75);near(track:FindFirstChild('Damage').Size.X.Scale,.75)
self.Humanoid.Health=0/0;self.Humanoid.MaxHealth=0;hp.render(.1);near(track:FindFirstChild('Fill').Size.X.Scale,0)
hp.Options.Players.Value=true;hp.render(.1)
local hpLayer=screen:FindFirstChild('HPLayer');assert(#hpLayer.children==1)
-- Real Render box/outline segments, mode switches, and lazy fill.
local layer=render:Layer('Geometry');local set=render:Set(layer,'test')
local rect={left=10,right=70,top=10,bottom=110,width=60,height=100}
set:Fill(nil,red,.8);assert(set.fill==nil,'OFF fill must not allocate an instance')
set:Box(rect,'Corner',1,red)
assert(#set.lines.Box==8 and #set.lines.BoxOutline==8)
assert(set.lines.Box[1].ZIndex>set.lines.BoxOutline[1].ZIndex)
assert(set.lines.BoxOutline[1].Size.Y.Offset==3)
local n=#objects
for _=1,30 do set:Box(rect,'Corner',1,red) end;assert(#objects==n,'pooled geometry, no per-frame instances')
set:Box(rect,'Full',1,red);assert(not set.lines.Box[8].Visible and not set.lines.BoxOutline[8].Visible)
set:Box(rect,'Off',1,red);assert(not set.lines.Box[1].Visible and not set.lines.BoxOutline[1].Visible)
rect.width=1;rect.right=11;rect.height=1;rect.bottom=11;set:Box(rect,'Corner',1,red)
assert(set.lines.Box[1].Size.X.Offset<=1,'tiny brackets never extend outside box')
-- Distance/removal releases all targets, OFF clears self and others.
targets={};hp.render(.1);assert(#hpLayer.children==0)
hp:Toggle(false);assert(not hud.Visible)
HP.destroy();Names.destroy();Chams.destroy();ESP.destroy();assert(not esp.Enabled);Roles.destroy();Render.destroy()
assert(hud.destroyed and #listeners==0,'unload releases every role listener and GUI')
print('PASS render roles: real Chams/HP/Nametags/GameRoles/Render, local palettes, future providers, Unicode/cache, health/respawn, outlined pooled boxes and complete cleanup')
'''
with tempfile.TemporaryDirectory() as t:
 p=Path(t)/'test.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
