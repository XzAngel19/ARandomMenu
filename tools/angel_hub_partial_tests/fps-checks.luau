Enum.RenderFidelity={Performance='performance'};Enum.QualityLevel={Level01='lowest'}
Enum.CoreGuiType={PlayerList='players',Backpack='backpack',Chat='chat',EmotesMenu='emotes'}
local names={'Remove Textures','Disable Particles','Disable Shadows','Simple Materials','Lowest Render Quality',
 'Low Detail Meshes','Hide Distant Scenery','Simplify Terrain','Disable Post Effects','Simple Lighting',
 'Disable Local Lights','Simplify Game UI','Hide World UI','Hide Game UI','Hide Roblox Panels'}
for _,n in ipairs(names)do V[n]=false;AngelHub.setters[n]=function(v)V[n]=v end end
local function node(class,name,parent)
 local obj={class=class,Name=name,Parent=parent}
 function obj:IsA(c)return self.class==c or (c=='BasePart' and (self.class=='Part' or self.class=='MeshPart'))
  or (c=='PostEffect' and self.class=='BloomEffect') or (c=='Light' and self.class=='PointLight')end
 function obj:FindFirstChildOfClass()return nil end
 return obj
end
local decal=node('Decal','Decal',workspace);decal.Transparency=.2
local particle=node('ParticleEmitter','Particle',workspace);particle.Enabled=true
local mesh=node('MeshPart','Mesh',workspace);mesh.TextureID='asset';mesh.Material='wood';mesh.Reflectance=.5;mesh.CastShadow=true
mesh.RenderFidelity='automatic';mesh.Anchored=true;mesh.CanCollide=true;mesh.Position=Vector3.new(500,0,0);mesh.LocalTransparencyModifier=.1
local terrain=node('Terrain','Terrain',workspace);terrain.Decoration=true;terrain.WaterWaveSize=2;terrain.WaterWaveSpeed=3;terrain.WaterReflectance=.6
local light=node('PointLight','Light',workspace);light.Enabled=true
local bloom=node('BloomEffect','Bloom',lighting);bloom.Enabled=true
lighting.GlobalShadows=true;lighting.EnvironmentDiffuseScale=1;lighting.EnvironmentSpecularScale=1
function lighting:GetDescendants()return {bloom}end
lighting.DescendantAdded=event()
playerGui.Name='PlayerGui';playerGui.Parent=localPlayer;playerGui.DescendantAdded=event()
local gameGui=node('ScreenGui','GameHud',playerGui);gameGui.Enabled=true
local worldGui=node('BillboardGui','WorldHud',workspace);worldGui.Enabled=true
local stroke=node('UIStroke','Stroke',gameGui);stroke.Enabled=true
local touch=node('ScreenGui','TouchGui',playerGui);touch.Enabled=true
local touchStroke=node('UIStroke','TouchStroke',touch);touchStroke.Enabled=true
function playerGui:GetDescendants()return {gameGui,stroke,touch,touchStroke}end
for _,o in ipairs({decal,particle,mesh,terrain,light,worldGui})do table.insert(workspace.objects,o)end
local starter={values={players=true,backpack=true,chat=false,emotes=true}}
function starter:GetCoreGuiEnabled(kind)return self.values[kind]end
function starter:SetCoreGuiEnabled(kind,value)self.values[kind]=value end
services.StarterGui=starter
installGameplay(screenGui)
for _,n in ipairs(names)do assert(AngelHub.setters[n](true)~=false,n)end
heartbeat:Fire(.1);heartbeat:Fire(.1);heartbeat:Fire(.1)
assert(decal.Transparency==1 and not particle.Enabled and mesh.TextureID=='')
assert(not mesh.CastShadow and mesh.Material=='plastic' and mesh.Reflectance==0 and mesh.RenderFidelity=='performance')
assert(mesh.LocalTransparencyModifier==1 and not terrain.Decoration and terrain.WaterWaveSize==0)
assert(not light.Enabled and not bloom.Enabled and not lighting.GlobalShadows and lighting.EnvironmentDiffuseScale==0)
assert(not gameGui.Enabled and not worldGui.Enabled and not stroke.Enabled and touch.Enabled and touchStroke.Enabled)
assert(rendering.QualityLevel=='lowest' and not starter.values.players and not starter.values.backpack)
local newParticle=node('ParticleEmitter','New',workspace);newParticle.Enabled=true;workspace.DescendantAdded:Fire(newParticle);assert(not newParticle.Enabled)
-- External writes that do not equal our applied value survive disable.
decal.Transparency=.33;AngelHub.setters['Remove Textures'](false);assert(decal.Transparency==.33 and mesh.TextureID=='asset')
mesh.Position=Vector3.new(20,0,0);heartbeat:Fire(1);heartbeat:Fire(.1);assert(mesh.LocalTransparencyModifier==.1)
starter.values.players=true
screenGui.Destroying:Fire()
assert(particle.Enabled and newParticle.Enabled and mesh.CastShadow and mesh.Material=='wood' and mesh.Reflectance==.5)
assert(mesh.RenderFidelity=='automatic' and terrain.Decoration and terrain.WaterWaveSize==2 and light.Enabled and bloom.Enabled)
assert(lighting.GlobalShadows and lighting.EnvironmentDiffuseScale==1 and gameGui.Enabled and worldGui.Enabled and stroke.Enabled)
assert(rendering.QualityLevel=='auto' and starter.values.players and starter.values.backpack and not starter.values.chat)
