const fs=require('node:fs'), path=require('node:path'), assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'), read=p=>fs.readFileSync(p,'utf8');
const file=read(path.join(root,'Angel-Hub-GUI-Main-Movement.txt'));
const fixtures=path.join(root,'tools/angel_hub_partial_tests');
(async()=>{
 const prefix=process.env.LUAU_TEST_PREFIX||path.join(root,'tools/luau');
 const {Lua}=await import(pathToFileURL(path.join(prefix,'node_modules/@luau-rs/luau/dist/direct-api.js')).href);
 const compile=await Lua.create({sandbox:true});compile.compile(file);
 assert(!file.includes('addSection(visualsRight, "Notifications")'));
 assert(file.includes('addCycle(mainLeft, "Aim Method", { "Normal", "Instakill" })'));
 const gui=await Lua.create({sandbox:true});
 gui.execute(read(path.join(fixtures,'gui-mock.luau'))+'\nfunction players:GetPlayers()return {player} end\n'+file+`\n
assert(shared.AngelHub and shared.AngelHubGui)
local h=shared.AngelHub
assert(h.values['Gun Aimbot']==false and h.values['Gun Aura']==false)
assert(h.values['WallCheck']==true and h.values['Macro']==false and h.values['Aim Method']=='Normal')
assert(h.values['Speed Mode']=='Velocity' and h.values['Gravity Method']=='Workspace')
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
 const instrumented=src.replace('    screenGui.Destroying:Connect(function()','    AngelHub._testPrediction={prediction=prediction,queue=queueShot,observe=observeEcho}\n    screenGui.Destroying:Connect(function()');
 const predictor=await Lua.create({sandbox:true});
 predictor.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+instrumented+'\n'+read(path.join(__dirname,'prediction-checks.luau')));
 const outside=await Lua.create({sandbox:true});
 outside.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'outside-checks.luau')));
 const role=await Lua.create({sandbox:true});
 role.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'role-checks.luau')));
 for(const mobile of [false,true]) {
  const extra=await Lua.create({sandbox:true});
  extra.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'main-checks.luau')));
 }
 const movementStart=file.indexOf('local function installMovementFeatures(screenGui)');
 const movementEnd=file.indexOf('\nlocal function initializeScript()',movementStart);
 assert(movementStart>=0 && movementEnd>movementStart);
 const movement=file.slice(movementStart,movementEnd);
 for(const mobile of [false,true]) {
  const test=await Lua.create({sandbox:true});
  test.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(__dirname,'movement-setup.luau'))+'\n'+movement+'\n'+read(path.join(__dirname,'movement-checks.luau')));
  const respawn=await Lua.create({sandbox:true});
  respawn.execute(read(path.join(fixtures,'gameplay-mock.luau'))+`\nlocal mobile=${mobile};local fakeNow=100;local os={clock=function()return fakeNow end}\n`+read(path.join(__dirname,'movement-setup.luau'))+'\n'+movement+'\n'+read(path.join(__dirname,'respawn-checks.luau')));
 }
 const universal=await Lua.create({sandbox:true});
 universal.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=true;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'movement-setup.luau'))+'\ngame.PlaceId=1\n'+movement+'\n'+read(path.join(__dirname,'movement-checks.luau')));
 const hook=await Lua.create({sandbox:true});
 hook.execute(read(path.join(fixtures,'gameplay-mock.luau'))+'\nlocal mobile=false;local fakeNow=100;local os={clock=function()return fakeNow end}\n'+read(path.join(__dirname,'mock-setup.luau'))+'\n'+src+'\n'+read(path.join(__dirname,'hook-checks.luau')));
 console.log('PASS: GUI, gun/knife regressions and PC/mobile Fly, Speed and Gravity (mocks only)');
})().catch(err=>{console.error(err);process.exit(1)});
