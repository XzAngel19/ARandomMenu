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
assert(h.values['Gun Aimbot']==false and h.values['Gun Aura']==false)
assert(h.values['Auto Pickup Gun Key Value']=='H' and h.values['Auto Get Gun']==false)
local foundPickup=false;for _,c in ipairs(h.searchables)do if c.Name=='Auto Pickup Gun' then foundPickup=true end end;assert(foundPickup)
-- Exercise the actual GUI Activated dispatch, not just direct action calls.
for _,name in ipairs({'Kill All','Kill Selected','Fling','Get Gun'})do
 local calls=0;local previous=h.actions[name];h.actions[name]=function()calls+=1 end
 local card;for _,c in ipairs(h.searchables)do if c.Name==name then card=c end end
 assert(card and card:FindFirstChildOfClass('TextButton'))
 card:FindFirstChildOfClass('TextButton').Activated:Fire();assert(calls==1);h.actions[name]=previous
end
uis.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='H'}},false)
assert(h.values['Auto Get Gun']);uis.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='H'}},false);assert(not h.values['Auto Get Gun'])

assert(h.values['WallCheck']==true and h.values['Macro']==false and h.values['Aim Method']=='Normal')
assert(h.values['Speed Mode']=='Velocity' and h.values['Gravity Method']=='Workspace')
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
 function services.HttpService:JSONDecode()return {Autoload=true,['Auto Farm']=true,['Auto Win']=true,['Auto Unbox']=true,['Auto Fling Selected Target']=true}end\n`+file+`\n
 local v=shared.AngelHub.values;assert(not v['Auto Farm'] and not v['Auto Win'] and not v['Auto Unbox'] and not v['Auto Fling Selected Target'])
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
 console.log('PASS: lists, Fling, Auto Win Sheriff, safe autoload, visual and prior GUI regressions (PC/mobile mocks only)');
})().catch(err=>{console.error(err);process.exit(1)});
