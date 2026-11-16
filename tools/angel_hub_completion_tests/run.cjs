const fs=require('node:fs'), path=require('node:path'), assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'), read=p=>fs.readFileSync(p,'utf8');
const file=read(path.join(root,'Angel-Hub-GUI-Continuacion.txt'));
const fixtures=path.join(root,'tools/angel_hub_partial_tests');
(async()=>{
 const prefix=process.env.LUAU_TEST_PREFIX||path.join(root,'tools/luau');
 const {Lua}=await import(pathToFileURL(path.join(prefix,'node_modules/@luau-rs/luau/dist/direct-api.js')).href);
 const compile=await Lua.create({sandbox:true});compile.compile(file);
 assert(!file.includes('addSection(visualsRight, "Notifications")'));
 assert(!file.includes('Require Sprint Key') && file.includes('["MM2 Sprint Tail Box"]=true'));
 for (const name of ['Farm Mode','ESP Max Distance','Item Max Distance','Nametag Max Distance','HP Max Distance']) assert(!file.includes('"'+name+'"'));
 assert(file.includes('addCycle(mainLeft, "Aim Method", { "Normal", "Instakill" })'));
 const gui=await Lua.create({sandbox:true});
 gui.execute(read(path.join(fixtures,'gui-mock.luau'))+'\nplayer.Name="Me";firetouchinterest=function()end;local roster={player};function players:GetPlayers()return roster end\n'+file+`\n
assert(shared.AngelHub and shared.AngelHubGui)
local h=shared.AngelHub
local alice={Name='Alice'};local bob={Name='Bob'};table.insert(roster,bob);table.insert(roster,alice)
run.Heartbeat:Fire(1.1);assert(h.values['Kill Player']=='Alice' and h.values['Fling Target']=='Alice')
h.setters['Kill Player']('Bob');h.setters['Fling Target']('Bob');assert(h.values['Kill Player']=='Bob' and h.values['Fling Target']=='Bob')
table.remove(roster,2);run.Heartbeat:Fire(1.1);assert(h.values['Kill Player']=='Alice' and h.values['Fling Target']=='Alice')
h.setters['Kill Player']('Nobody');assert(h.values['Kill Player']=='Alice')
table.remove(roster,2);run.Heartbeat:Fire(1.1);assert(h.values['Kill Player']==nil and h.values['Fling Target']==nil)
for _,name in ipairs({'Stay Under When Round Starts','Fling Murder After Full Bag','Fling Sheriff After Full Bag','Auto Kill All When Full Bag'})do
 assert(h.values[name]==false);h.setters[name](true);assert(h.values[name]==true);h.setters[name](false)
end
assert(h.values['Gun Aimbot']==false and h.values['Gun Aura']==false)
assert(h.values['Auto Pickup Gun Key Value']=='H' and h.values['Auto Get Gun']==false)
local foundPickup=false;for _,c in ipairs(h.searchables)do if c.Name=='Auto Pickup Gun' then foundPickup=true end end;assert(foundPickup)
-- Exercise the actual GUI Activated dispatch, not just direct action calls.
for _,name in ipairs({'Kill All','Kill Selected','Fling','Get Gun','Play Emote'})do
 local calls=0;local previous=h.actions[name];h.actions[name]=function()calls+=1 end
 local card;for _,c in ipairs(h.searchables)do if c.Name==name then card=c end end
 assert(card and card:FindFirstChildOfClass('TextButton'))
 card:FindFirstChildOfClass('TextButton').Activated:Fire();assert(calls==1);h.actions[name]=previous
end
uis.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='H'}},false)
assert(h.values['Auto Get Gun']);uis.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='H'}},false);assert(not h.values['Auto Get Gun'])

assert(h.values['WallCheck']==true and h.values['Macro']==false and h.values['Aim Method']=='Normal')
assert(h.values['Speed Mode']=='Velocity' and h.values['Gravity Method']=='Workspace')
h.setters['Farm Speed'](0);assert(h.values['Farm Speed']==1)
h.setters['Farm Speed'](60);assert(h.values['Farm Speed']==28)
h.setters['Farm Speed'](24);assert(h.values['Farm Speed']==24)
assert(h.values['Win Time']~=nil and h.setters['Win Time']~=nil)
h.setters['Auto Farm'](true);h.setters['Walk Fling'](true);assert(not h.values['Auto Farm'] and not h.values['Walk Fling'])
local numeric
for _,c in ipairs(h.searchables)do if c.Name=='Speed Value' then numeric=c:FindFirstChildOfClass('TextBox')end end
assert(numeric);numeric.Text='-8';numeric.FocusLost:Fire();assert(h.values['Speed Value']==-8)
numeric.Text='0';numeric.FocusLost:Fire();assert(h.values['Speed Value']==0)
numeric.Text='bad';numeric.FocusLost:Fire();assert(h.values['Speed Value']==0 and numeric.Text=='0')

local auraSlider
for _,card in ipairs(h.searchables)do if card.Name=='Shoot Proximity Aura' then auraSlider=card end end
assert(auraSlider and auraSlider.Visible==false)
h.setters['Shoot Proximity'](true);assert(auraSlider.Visible==true)
h.setters['Shoot Proximity'](false);assert(auraSlider.Visible==false)

for _,c in ipairs(h.searchables)do assert(c.Name~='Gun Notification' and c.Name~='Instant Roles')end
local window=h.pages.Main.Parent.Parent
local before=window.Visible
services.UserInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.RightShift},true)
assert(window.Visible~=before)
shared.AngelHubGui:Destroy()
`);
 const autoload=await Lua.create({sandbox:true});
 autoload.execute(read(path.join(fixtures,'gui-mock.luau'))+`\nfunction players:GetPlayers()return {player}end
 isfile=function()return true end;readfile=function()return '{}' end
 function services.HttpService:JSONDecode()return {Autoload=true,['Auto Farm']=true,['Auto Win']=true,['Auto Unbox']=true,['Auto Fling Selected Target']=true,['Walk Fling']=true,['FreeCam']=true,['Air Walk']=true}end\n`+file+`\n
 local v=shared.AngelHub.values;assert(not v['Auto Farm'] and not v['Auto Win'] and not v['Auto Unbox'] and not v['Auto Fling Selected Target'] and not v['Walk Fling'] and not v['FreeCam'] and not v['Air Walk'])
 shared.AngelHubGui:Destroy()\n`);
 const otherGui=await Lua.create({sandbox:true});
 otherGui.execute(read(path.join(fixtures,'gui-mock.luau'))+'\nfunction players:GetPlayers()return {player} end;game.PlaceId=1\n'+file+`\n
local hidden=0
for _,box in ipairs(shared.AngelHub.boxes)do
 if box:GetAttribute('MM2Hidden') then assert(box.Visible==false);hidden+=1 end
end
assert(hidden>=15)
shared.AngelHubGui:Destroy()
`);
 const start=file.indexOf('local function installGunFeatures(screenGui)');
 const end=file.indexOf('\nlocal function initializeScript()',start);
 assert(start>=0&&end>start);
 const src=file.slice(start,end);
 for(const mobile of [false,true]){
  const lua=await Lua.create({sandbox:true});
  lua.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'gun-checks.luau')));
 }
 const instrumented=src.replace('    local function cleanupMainFeatures()','    AngelHub._testPrediction={prediction=prediction,queue=queueShot,observe=observeEcho}\n    local function cleanupMainFeatures()');
 const predictor=await Lua.create({sandbox:true});
 predictor.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+instrumented+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','prediction-checks.luau')));
 const outside=await Lua.create({sandbox:true});
 outside.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','outside-checks.luau')));
 const role=await Lua.create({sandbox:true});
 role.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','role-checks.luau')));
 for(const mobile of [false,true]) {
  const extra=await Lua.create({sandbox:true});
  extra.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'main-checks.luau')));
 }
 for(const mobile of [false,true]){
  const stab=await Lua.create({sandbox:true});
  stab.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'kill-all-checks.luau')));
 }
 const movementStart=file.indexOf('local function installMovementFeatures(screenGui)');
 const movementEnd=file.indexOf('\nlocal function initializeScript()',movementStart);
 assert(movementStart>=0 && movementEnd>movementStart);
 const movement=file.slice(movementStart,movementEnd);
 for(const mobile of [false,true]) {
  const test=await Lua.create({sandbox:true});
  test.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+movement+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-checks.luau')));
  const sprint=await Lua.create({sandbox:true});
  sprint.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+movement+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','sprint-checks.luau')));
  const respawn=await Lua.create({sandbox:true});
  respawn.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+movement+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','respawn-checks.luau')));
 }
 const universal=await Lua.create({sandbox:true});
 universal.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=true;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\ngame.PlaceId=1\n'+movement+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-checks.luau')));
 const noSprint=await Lua.create({sandbox:true});
 noSprint.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=true;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\ngame.PlaceId=1\n'+movement+`\ninstallMovementFeatures(screenGui);uis.InputBegan:Fire(shift,false);heartbeat:Fire(.1);assert(humanoid.WalkSpeed==16);for _,x in ipairs(created) do assert(x.Name~='AngelHubSprintButton' and x.Name~='AngelSprintTail') end`);
 for(const mobile of [false,true]) {
  const knife=await Lua.create({sandbox:true});
  knife.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(__dirname,'mock-setup.luau'))+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','knife-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','knife-checks.luau')));
 }
 for(const mobile of [false,true]) {
  const late=await Lua.create({sandbox:true});
  late.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(__dirname,'mock-setup.luau'))+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','knife-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'knife-late-checks.luau')));
 }
 const invalid=await Lua.create({sandbox:true});
 const knifeDebug=src.replace('    -- v139.2: this loop used to run every frame','    AngelHub._knifeTest={resolve=resolveKnifeAim,prediction=prediction}\n    -- v139.2: this loop used to run every frame');
 invalid.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','knife-setup.luau'))+'\n'+knifeDebug+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','knife-invalid.luau')));
 const shield=await Lua.create({sandbox:true});
 shield.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','shield-checks.luau')));
 for (const mobile of [false,true]) {
  const visuals=await Lua.create({sandbox:true});
  visuals.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'visual-checks.luau')));
 }
 const visualRoles=await Lua.create({sandbox:true});
 visualRoles.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','role-visual-checks.luau')));
 const coin=await Lua.create({sandbox:true});
 coin.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','coin-checks.luau')));
 const coinModelAndParent=await Lua.create({sandbox:true});
 coinModelAndParent.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+src+`
AngelHub.moduleNames['Coin ESP']=true;V['Coin ESP']=false;AngelHub.setters['Coin ESP']=function(v)V['Coin ESP']=v end
V['Coin Colour']={r=1};V['Coin Transparency']=0;V['Coin In Use']='All'
services.Players={LocalPlayer=localPlayer}
local coinMesh={Name='Mesh',Size=Vector3.new(2,2,2),attributes={}}
function coinMesh:IsA(c)return c=='BasePart'end
function coinMesh:GetAttribute(n)return self.attributes[n]end
function coinMesh:GetDescendants()return {}end
function coinMesh:FindFirstChildOfClass()return nil end
local modelVisual={Name='CoinVisual',Parent=map,PrimaryPart=coinMesh,attributes={}}
coinMesh.Parent=modelVisual
function modelVisual:IsA(c)return c=='Model'end
function modelVisual:GetAttribute(n)return self.attributes[n]end
function modelVisual:FindFirstChildOfClass()return nil end
function modelVisual:FindFirstChildWhichIsA(c)if c=='BasePart'then return coinMesh end end
function modelVisual:GetDescendants()return {coinMesh}end
function modelVisual:IsDescendantOf(o)return o==map or o==workspace end
function coinMesh:IsDescendantOf(o)return o==map or o==workspace end
local bareServer={Name='Coin_Server',Parent=map,Size=Vector3.new(1,1,1),attributes={}}
function bareServer:IsA(c)return c=='BasePart'end
function bareServer:GetAttribute(n)return self.attributes[n]end
function bareServer:FindFirstChild()return nil end
function bareServer:FindFirstChildOfClass()return nil end
function bareServer:GetDescendants()return {}end
function bareServer:IsDescendantOf(o)return o==map or o==workspace end
map.descendants={modelVisual,coinMesh,bareServer}
services.CollectionService={GetTagged=function(_,tag)if tag=='CoinVisual'then return {modelVisual}end return {}end}
installCoinESP(screenGui)
AngelHub.setters['Coin ESP'](true);heartbeat:Fire(1)
local foundModel,foundBare=false,false
for _,b in ipairs(created)do
 if b.class=='BoxHandleAdornment' and not b.destroyed then
  assert(b.Parent==playerGui)
  if b.Adornee==coinMesh then foundModel=true end
  if b.Adornee==bareServer then foundBare=true end
 end
end
assert(foundModel and foundBare)
modelVisual.attributes.Collected=true;heartbeat:Fire(1)
for _,b in ipairs(created)do
 if b.class=='BoxHandleAdornment' and b.Adornee==coinMesh then assert(b.destroyed) end
end
screenGui.Destroying:Fire()
`);
 const util=await Lua.create({sandbox:true});
 util.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','utility-checks.luau')));
 const vote=await Lua.create({sandbox:true});
 vote.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','vote-checks.luau')));
 const items=await Lua.create({sandbox:true});
 items.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'item-checks.luau')));
 const actions=await Lua.create({sandbox:true});
 actions.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(root,'tools/angel_hub_visual_tests','movement-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'actions-checks.luau')));
 const fling=await Lua.create({sandbox:true});
 fling.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'fling-checks.luau')));
 const sheriff=await Lua.create({sandbox:true});
 sheriff.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_farm_tests','sheriff-checks.luau')));
 const farmShoot=await Lua.create({sandbox:true});
 farmShoot.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_farm_tests','farm-shoot-checks.luau')));
 const hook=await Lua.create({sandbox:true});
 hook.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','hook-checks.luau')));
 const knifeFallback=await Lua.create({sandbox:true});
 knifeFallback.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+read(path.join(root,'tools/angel_hub_visual_tests','knife-setup.luau'))+'\n'+knifeDebug+`
installGunFeatures(screenGui)
AngelHub.setters['Knife Throw'](true);AngelHub.setters['Throw WallCheck'](true)
local enemy2={Name='Bob',DisplayName='Bob',UserId=3,Character={Parent=workspace}}
local er2={Position=Vector3.new(45,0,0),CFrame=CFrame.new(Vector3.new(45,0,0)),AssemblyLinearVelocity=Vector3.new(0,0,16),Parent=enemy2.Character}
function er2:IsA(c)return c=='BasePart'end;function er2:IsDescendantOf(m)return m==enemy2.Character end
local eh2={Health=100,FloorMaterial=Enum.Material.Ground,MoveDirection=Vector3.zero}
function eh2:IsA(c)return c=='Humanoid'end;function eh2:GetState()return {Name='Running'}end;function eh2:GetAttribute()return nil end
function enemy2.Character:FindFirstChildOfClass(n)if n=='Humanoid'then return eh2 end end
function enemy2.Character:FindFirstChild(n)if n=='HumanoidRootPart' or n=='Head' then return er2 end end
function enemy2.Character:GetDescendants()return {er2,eh2} end
function enemy2.Character:GetAttribute()return nil end
function enemy2:FindFirstChildOfClass()return nil end
function playersService:GetPlayers()return {localPlayer,other,enemy2}end
-- Closest target (X=20) blocked by wall; second-best visible target (X=45) is chosen.
local oldRay=workspace.Raycast
function workspace:Raycast(origin,dir,params)
 local target=origin+dir
 if math.abs(target.X-20)<10 then return {Instance=wall} end
 local ignore=false
 if params and params.FilterDescendantsInstances then
  for _,x in ipairs(params.FilterDescendantsInstances) do if x==enemy2.Character then ignore=true end end
 end
 if not ignore and math.abs(target.X-45)<10 then return {Instance=er2} end
 return nil
end
fakeNow+=0.2;heartbeat:Fire(0.1)
local cf=ws:GetMouseTargetCFrame()
assert(typeof(cf)=='CFrame' and cf.Position.X>35)
workspace.Raycast=oldRay
-- Verify knifeAim caps non-input-history quadratic acceleration overshoot over long flights.
local pred=AngelHub._knifeTest.prediction
er2.Position=Vector3.new(120,0,0);er2.CFrame=CFrame.new(er2.Position);er2.AssemblyLinearVelocity=Vector3.new(0,0,16)
fakeNow+=0.05;heartbeat:Fire(0.05)
er2.Position=Vector3.new(120,0,1.0);er2.CFrame=CFrame.new(er2.Position);er2.AssemblyLinearVelocity=Vector3.new(0,0,22)
fakeNow+=0.05;heartbeat:Fire(0.05)
er2.Position=Vector3.new(120,0,2.5);er2.CFrame=CFrame.new(er2.Position);er2.AssemblyLinearVelocity=Vector3.new(0,0,30)
fakeNow+=0.05;heartbeat:Fire(0.05)
local aimPt=pred.knifeAim(enemy2,Vector3.new(0,0,0),96)
assert(aimPt~=nil and aimPt.Z<45)
screenGui.Destroying:Fire()
`);
 const farmFullGui=await Lua.create({sandbox:true});
 farmFullGui.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+`
local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
run.Stepped=event()
for _,n in ipairs({'Auto Farm','Coins Aura','Farm Safe Zone','Auto Grab Gun And Shoot','Reset When Full Coin Bag',
 'Stay Under When Round Starts','Auto Kill All When Full Bag','Fling Murder After Full Bag','Fling Sheriff After Full Bag',
 'Auto Fling Selected Target','Enable Speed','Enable Fly','Noclip','Auto Vote'})do setting(n,false)end
setting('Farm Speed',22);setting('Coins Collected',0);setting('Farm Time',0);V['Fling Retries']=0
local fmt={};fmt.__index=fmt;fmt.__mul=function(a,b)return setmetatable({Position=a.Position+b.Position},fmt)end
function fmt:ToObjectSpace(b)return CFrame.new(b.Position-self.Position)end
function CFrame.new(x,y,z)local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0);return setmetatable({Position=p},fmt)end
function CFrame.Angles()return CFrame.new(0,0,0)end
Enum.HumanoidStateType={Seated='seated',GettingUp='gettingup'};humanoid.FloorMaterial=Enum.Material.Ground;humanoid.seated=true
function humanoid:GetStateEnabled()return self.seated end;function humanoid:SetStateEnabled(_,v)self.seated=v end;function humanoid:ChangeState()end
character.Parent=workspace;root.Parent=character;root.Position=Vector3.zero;root.CFrame=CFrame.new(root.Position)
root.AssemblyAngularVelocity=Vector3.zero;root.AssemblyLinearVelocity=Vector3.zero;root.Velocity=Vector3.zero;root.RotVelocity=Vector3.zero
function character:GetPivot()return root.CFrame end
function character:PivotTo(cf)self.lastPivot=cf;root.CFrame=cf;root.Position=cf.Position end
local murd={Name='Murd',UserId=2,Character={Parent=workspace}}
local mr={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.zero};function mr:IsA(c)return c=='BasePart'end
local mh={Health=100,Sit=false,MoveDirection=Vector3.zero};mr.Parent=murd.Character
function murd.Character:FindFirstChildOfClass(n)if n=='Humanoid'then return mh end end
function murd.Character:FindFirstChild(n)if n=='HumanoidRootPart'then return mr end end
local sher={Name='Sher',UserId=3,Character={Parent=workspace}}
local sr={Position=Vector3.new(30,0,0),AssemblyLinearVelocity=Vector3.zero};function sr:IsA(c)return c=='BasePart'end
local sh={Health=100,Sit=false,MoveDirection=Vector3.zero};sr.Parent=sher.Character
function sher.Character:FindFirstChildOfClass(n)if n=='Humanoid'then return sh end end
function sher.Character:FindFirstChild(n)if n=='HumanoidRootPart'then return sr end end
function playersService:GetPlayers()return {localPlayer,murd,sher} end
local coinLbl={Text='40/40'};function coinLbl:IsA(c)return c=='TextLabel'end
local coinBag={};function coinBag:FindFirstChild(n)if n=='Coins'then return coinLbl end end
function coinBag:GetDescendants()return {coinLbl} end
local gameGui={};function gameGui:FindFirstChild(n)if n=='CoinBag'then return coinBag end end
local mainGui={};function mainGui:FindFirstChild(n)if n=='Game' or n=='CoinBag' then return n=='Game' and gameGui or coinBag end end
function playerGui:FindFirstChild(n)if n=='MainGUI'then return mainGui end end
local oldLpClass=localPlayer.FindFirstChildOfClass
function localPlayer:FindFirstChildOfClass(n)if n=='PlayerGui'then return playerGui end return oldLpClass(self,n) end
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local coinsStarted={OnClientEvent=event()};function coinsStarted:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended,RoundStart=started,CoinsStarted=coinsStarted})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end;services.ReplicatedStorage=storage
AngelHub.getMM2Role=function(p)if p==murd then return 'Murderer' elseif p==sher then return 'Sheriff' end end
AngelHub.findMM2Map=function()return map.Parent and map end
AngelHub.refreshMM2Roles=function()end;AngelHub.releaseMM2Roles=function()end
local drop={Position=Vector3.new(45,0,0),CFrame=CFrame.new(Vector3.new(45,0,0))};function drop:IsA(c)return c=='BasePart'end;function drop:IsDescendantOf(w)return w==workspace end
local curDrop=drop;local shots=0;local hasGun=false;local gunTouches=0
local oldCharFind=character.FindFirstChild
function character:FindFirstChild(n) if n=='Gun' and hasGun then return drop end return oldCharFind(self,n) end
AngelHub.findMM2DroppedGun=function()return curDrop end
AngelHub.actions={['Get Gun']=function() gunTouches+=1; return true end}
AngelHub.farmGrabShoot=function()shots+=1 end
installMM2Fling(screenGui);installMM2Farm(screenGui)
-- Simulate prior round end followed by RoundStart(nil) / CoinsStarted: must NOT leave roundEnded=true
ended.OnClientEvent:Fire();started.OnClientEvent:Fire();coinsStarted.OnClientEvent:Fire()
-- Step 1: Before full coin bag (0/40), Auto Grab Gun uses firetouchinterest (NO PivotTo teleport!), and does NOT shoot!
coinLbl.Text='0/40'
AngelHub.setters['Auto Grab Gun And Shoot'](true);AngelHub.setters['Auto Farm'](true)
heartbeat:Fire(.2)
assert(gunTouches==1 and character.lastPivot==nil and shots==0,'FAIL_PRE_FULL_GUN_TOUCH')
hasGun=true;fakeNow+=0.3;heartbeat:Fire(.2);assert(shots==0,'FAIL_NO_SHOOT_BEFORE_FULL')
-- Step 2: Reach full bag via GUI '40/40': rests on map 1.5s and touches ground before flinging!
hasGun=false;curDrop=nil;character.lastPivot=nil;root.Position=Vector3.zero;root.CFrame=CFrame.new(root.Position)
humanoid.FloorMaterial=Enum.Material.Air;coinLbl.Text='40/40'
AngelHub.setters['Fling Murder After Full Bag'](true);AngelHub.setters['Fling Sheriff After Full Bag'](true)
heartbeat:Fire(.2);assert(not AngelHub.mm2FlingBusy,'FAIL_MUST_REST_FIRST')
fakeNow+=1.6;heartbeat:Fire(.2);assert(not AngelHub.mm2FlingBusy,'FAIL_WAIT_GROUND')
humanoid.FloorMaterial=Enum.Material.Ground;heartbeat:Fire(.2)
local pin1=created[#created];assert(pin1 and pin1.class=='BodyVelocity' and AngelHub.mm2FlingOwner=='farm','FAIL_PIN1')
-- After 2.2s burst + 1.0s rest, Murd is STILL alive (mh.Health==100) -> must fling Murd AGAIN!
fakeNow+=2.2;heartbeat:Fire(.2);fakeNow+=0.2;heartbeat:Fire(.2);assert(not AngelHub.mm2FlingBusy,'FAIL_RETRY_REST')
fakeNow+=1.0;heartbeat:Fire(.2)
local pin1b=created[#created];assert(pin1b~=pin1 and pin1b.class=='BodyVelocity' and AngelHub.mm2FlingOwner=='farm','FAIL_MURD_RETRY')
-- Now Murd dies (mh.Health=0) -> transitions to Sheriff fling!
mh.Health=0;fakeNow+=0.2;heartbeat:Fire(.2);fakeNow+=1.1;heartbeat:Fire(.2)
local pin2=created[#created];assert(pin2~=pin1b and pin2.class=='BodyVelocity' and AngelHub.mm2FlingOwner=='farm','FAIL_PIN2')
-- After 2.2s burst + 1.0s rest, Sher is STILL alive (sh.Health==100) -> must fling Sher AGAIN!
fakeNow+=2.2;heartbeat:Fire(.2);fakeNow+=1.2;heartbeat:Fire(.2)
local pin2b=created[#created];assert(pin2b~=pin2 and pin2.class=='BodyVelocity' and AngelHub.mm2FlingOwner=='farm','FAIL_SHER_RETRY')
-- Now Sher dies (sh.Health=0) and GunDrop appears -> Auto Grab Gun uses firetouchinterest (no teleport to GunDrop!) and shoots!
sh.Health=0;curDrop=drop;local beforeTouches=gunTouches
fakeNow+=0.2;heartbeat:Fire(.2);fakeNow+=0.3;heartbeat:Fire(.2);fakeNow+=0.3;heartbeat:Fire(.2)
assert(gunTouches>beforeTouches and (not character.lastPivot or character.lastPivot.Position.X~=45),'FAIL_TOUCH_NO_TELEPORT')
hasGun=true;fakeNow+=0.3;heartbeat:Fire(.2);assert(shots>=1,'FAIL_SHOOT_AT_FULL')
screenGui.Destroying:Fire()
`);
 assert(file.includes('addSection(extraLeft, "Disguise")')&&file.includes('addModule(extraLeft, "Disguise", nil, false)')&&file.includes('addText(extraLeft, "UserID"')&&file.includes('installDisguise(screenGui)'));
 const disguiseTest=await Lua.create({sandbox:true});
 disguiseTest.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+`
local function makeDesc(props)
 local d={
  HeightScale=props.HeightScale or 1, WidthScale=props.WidthScale or 1, DepthScale=props.DepthScale or 1,
  HeadScale=props.HeadScale or 1, BodyTypeScale=props.BodyTypeScale or 0, ProportionScale=props.ProportionScale or 0,
  WalkAnimation=props.WalkAnimation or 0, IdleAnimation=props.IdleAnimation or 0,
  emotes=props.emotes or {}, equipped=props.equipped or {}, destroyed=false,
 }
 function d:GetEmotes()
  local out={}; for k,v in pairs(self.emotes) do out[k]={table.unpack(v)} end; return out
 end
 function d:GetEquippedEmotes()
  local out={}; for i,v in ipairs(self.equipped) do out[i]=v end; return out
 end
 function d:SetEmotes(e) self.emotes={}; for k,v in pairs(e) do self.emotes[k]={table.unpack(v)} end end
 function d:SetEquippedEmotes(eq) self.equipped={}; for i,v in ipairs(eq) do self.equipped[i]=v end end
 function d:Destroy() self.destroyed=true end
 return d
end
local function makeObj(className, name, parent, extra)
 local raw=extra or {}
 raw.ClassName=className; raw.Name=name; raw.children=raw.children or {}; raw.destroyed=false
 local o={}
 function o:IsA(c) return self.ClassName==c or (c=='Instance') end
 function o:GetChildren() local out={}; for _,v in ipairs(self.children) do if not v.destroyed then table.insert(out,v) end end; return out end
 function o:GetDescendants()
  local out={}
  local function walk(n) for _,c in ipairs(n:GetChildren()) do table.insert(out,c); walk(c) end end
  walk(self); return out
 end
 function o:FindFirstChild(n, rec)
  for _,c in ipairs(self:GetChildren()) do if c.Name==n then return c end if rec then local f=c:FindFirstChild(n,true) if f then return f end end end
 end
 function o:FindFirstChildOfClass(c)
  for _,v in ipairs(self:GetChildren()) do if not v.destroyed and v:IsA(c) then return v end end
 end
 function o:IsDescendantOf(anc)
  local cur=self.Parent; while cur do if cur==anc then return true end; cur=cur.Parent end; return false
 end
 function o:Clone()
  local copy=makeObj(self.ClassName, self.Name, nil, {})
  for k,v in pairs(raw) do
   if k~='Parent' and k~='children' and type(v)~='function' and type(v)~='table' then copy[k]=v end
  end
  for _,c in ipairs(self:GetChildren()) do
   local cc=c:Clone(); cc.Parent=copy
  end
  if copy.ClassName=='Accessory' then
   for _,d in ipairs(copy:GetDescendants()) do
    if d.ClassName=='Weld' and raw._targetPartName then d.Part1={Name=raw._targetPartName, ClassName='BasePart', IsA=function(_,c) return c=='BasePart' end} end
   end
  end
  return copy
 end
 function o:Destroy()
  raw.destroyed=true; o.Parent=nil
 end
 local proxy=setmetatable(o, {
  __index=raw,
  __newindex=function(t,k,v)
   if k=='Parent' then
    local old=raw.Parent
    if old and old.children then
     for i,x in ipairs(old.children) do if x==t then table.remove(old.children, i); break end end
    end
    raw.Parent=v
    if v and v.children then
     local found=false; for _,x in ipairs(v.children) do if x==t then found=true; break end end
     if not found then table.insert(v.children, t) end
     if v==character and character.DescendantAdded then character.DescendantAdded:Fire(t) end
    end
    return
   end
   raw[k]=v
  end
 })
 proxy.Parent=parent
 return proxy
end
character.children={}; character.DescendantAdded=event(); character.Archivable=true
local origFindChild=character.FindFirstChild
function character:IsA(c) return c=='Model' end
function character:FindFirstChild(n, rec)
 for _,c in ipairs(self.children) do
  if not c.destroyed and c.Name==n then return c end
  if rec and c.FindFirstChild then local f=c:FindFirstChild(n,true) if f then return f end end
 end
end
function character:FindFirstChildOfClass(c)
 if c=='Humanoid' then return humanoid end
 for _,v in ipairs(self.children) do if not v.destroyed and v:IsA(c) then return v end end
end
function character:GetChildren() local out={}; for _,v in ipairs(self.children) do if not v.destroyed then table.insert(out,v) end end; return out end
function character:GetDescendants()
 local out={}
 local function walk(n) for _,c in ipairs(n:GetChildren()) do table.insert(out,c); walk(c) end end
 walk(self); return out
end
function character:Clone()
 local copy=makeObj('Model', self.Name, nil, {children={}})
 local chHum=makeObj('Humanoid', 'Humanoid', copy, {})
 function chHum:ApplyDescriptionResetAsync(desc)
  for _,c in ipairs(copy:GetChildren()) do if c.ClassName=='Shirt' or c.ClassName=='Accessory' then c:Destroy() end end
  makeObj('Shirt', 'TargetShirt', copy, {ShirtTemplate='rbxassetid://999'})
  local acc=makeObj('Accessory', 'TargetHat', copy, {_targetPartName='Head'})
  local h=makeObj('BasePart', 'Handle', acc, {})
  makeObj('Weld', 'AccessoryWeld', h, {Part1={Name='Head'}})
  local targetHead=copy:FindFirstChild('Head')
  if targetHead then makeObj('Decal', 'face', targetHead, {Texture='rbxassetid://888'}) end
 end
 makeObj('BasePart', 'Head', copy, {})
 return copy
end
local liveHead=makeObj('BasePart', 'Head', character, {})
makeObj('Decal', 'face', liveHead, {Texture='rbxassetid://111'})
makeObj('Shirt', 'OrigShirt', character, {ShirtTemplate='rbxassetid://222'})
makeObj('Accessory', 'OrigHat', character, {})
local animate=makeObj('LocalScript', 'Animate', character, {})
local walkFolder=makeObj('StringValue', 'walk', animate, {})
local walkAnim=makeObj('Animation', 'WalkAnim', walkFolder, {AnimationId='rbxassetid://12345'})
local localDesc=makeDesc({HeightScale=1.15, WalkAnimation=12345, emotes={Wave={101}}, equipped={{Name='Wave',Slot=1}}})
function humanoid:FindFirstChildOfClass(c) if c=='HumanoidDescription' then return localDesc end end
local targetDesc=makeDesc({HeightScale=1.8, WalkAnimation=77777, IdleAnimation=88888, emotes={Dance={202},Cheer={303}}, equipped={{Name='Dance',Slot=1},{Name='Cheer',Slot=2}}})
function services.Players:GetPlayers() return {{Name='TargetUser',DisplayName='TargetDisplay',UserId=999111}} end
function services.Players:GetHumanoidDescriptionFromUserIdAsync(uid)
 assert(uid==999111 or uid==78492, 'bad uid '..tostring(uid))
 return makeDesc({HeightScale=targetDesc.HeightScale, WalkAnimation=targetDesc.WalkAnimation, IdleAnimation=targetDesc.IdleAnimation, emotes=targetDesc.emotes, equipped=targetDesc.equipped})
end
AngelHub.values['Disguise']=false; AngelHub.setters['Disguise']=function(v) AngelHub.values['Disguise']=v end
AngelHub.values['UserID']='TargetUser'; AngelHub.setters['UserID']=function(v) AngelHub.values['UserID']=tostring(v) end
installDisguise(screenGui)
AngelHub.setters['Disguise'](true)
drain()
assert(character:FindFirstChild('TargetShirt')~=nil, 'TargetShirt missing')
assert(character:FindFirstChild('OrigShirt')==nil, 'OrigShirt still present')
local hat=character:FindFirstChild('TargetHat'); assert(hat~=nil, 'TargetHat missing')
local weld=hat:FindFirstChild('AccessoryWeld', true); assert(weld and weld.Part1==liveHead, 'Accessory weld not rebound')
local face=liveHead:FindFirstChild('face'); assert(face and face.Texture=='rbxassetid://888', 'Target face missing')
assert(localDesc:GetEmotes().Dance~=nil and localDesc:GetEmotes().Wave==nil, 'Target emotes not applied')
assert(localDesc:GetEquippedEmotes()[1].Name=='Dance', 'Target equipped emotes not applied')
assert(walkAnim.AnimationId=='rbxassetid://12345' and localDesc.WalkAnimation==12345, 'Movement animation must NOT be modified')
-- Stray server accessory added while disguised is filtered out cleanly
local stray=makeObj('Accessory', 'StrayHat', character, {})
assert(stray.destroyed==true, 'Stray appearance item should be destroyed')
-- Disabling Disguise restores original avatar items and original emotes
AngelHub.setters['Disguise'](false)
assert(character:FindFirstChild('OrigShirt')~=nil and character:FindFirstChild('TargetShirt')==nil, 'Original shirt not restored')
assert(character:FindFirstChild('OrigHat')~=nil and character:FindFirstChild('TargetHat')==nil, 'Original hat not restored')
local restoredFace=liveHead:FindFirstChild('face'); assert(restoredFace and restoredFace.Texture=='rbxassetid://111', 'Original face not restored')
assert(localDesc:GetEmotes().Wave~=nil and localDesc:GetEmotes().Dance==nil, 'Original emotes not restored')
assert(walkAnim.AnimationId=='rbxassetid://12345', 'Movement animation changed on restore')
-- Re-enable with numeric UserID and verify screenGui.Destroying restores cleanly
AngelHub.setters['UserID']('78492'); AngelHub.setters['Disguise'](true)
drain()
assert(character:FindFirstChild('TargetShirt')~=nil, 'Numeric UserID disguise failed')
screenGui.Destroying:Fire()
assert(character:FindFirstChild('OrigShirt')~=nil and localDesc:GetEmotes().Wave~=nil, 'Destroying did not restore')
`);
 console.log('PASS: lists, Fling, Auto Win Sheriff, safe autoload, visual and prior GUI regressions (PC/mobile mocks only)');
})().catch(err=>{console.error(err);process.exit(1)});
