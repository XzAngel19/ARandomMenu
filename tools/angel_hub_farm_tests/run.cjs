const fs=require('node:fs'),path=require('node:path'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),read=p=>fs.readFileSync(p,'utf8');
const fixture=path.join(root,'tools/angel_hub_partial_tests');
const file=read(path.join(root,'Angel-Hub-GUI-Continuacion.txt'));
const farm=file.slice(file.indexOf('local function installMM2Farm(screenGui)'),file.indexOf('\nlocal function initializeScript()'));
const setup=`
game.PlaceId=142823291;Vector3.zero=Vector3.new(0,0,0)
AngelHub.connections={}
run.PreSimulation=event()
AngelHub.setters["Coins Aura"]=function(v)V["Coins Aura"]=v end
local function connectInput(signal,callback)local c=signal:Connect(callback);table.insert(AngelHub.connections,c);return c end
AngelHub.findMM2Map=function()
 local fallback
 for _,model in ipairs(workspace:GetChildren())do
  if model:IsA('Model') and not string.find(string.lower(model.Name),'lobby',1,true) then
   if model:FindFirstChild('CoinContainer') or model:FindFirstChild('CoinAreas') or model:FindFirstChild('Coins') then return model end
   if not fallback and model:FindFirstChild('Spawns')then fallback=model end
  end
 end
 return fallback
end
`;
(async()=>{
 const prefix=process.env.LUAU_TEST_PREFIX||path.join(root,'tools/luau');
 const {Lua}=await import(pathToFileURL(path.join(prefix,'node_modules/@luau-rs/luau/dist/direct-api.js')).href);
 for(const name of ['farm-counter-checks.luau','farm-reset-checks.luau','../angel_hub_farm_tests/below-checks.luau','../angel_hub_farm_tests/coins-aura-checks.luau','../angel_hub_farm_tests/full-grab-checks.luau']){
  let test=read(path.join(fixture,name)).replaceAll('installGameplay(screenGui)','installMM2Farm(screenGui)');

  const lua=await Lua.create({sandbox:true});
  try{lua.execute(read(path.join(fixture,'gameplay-mock.luau'))+'\nlocal fakeNow=100;local os={clock=function()return fakeNow end}\n'+setup+'\n'+farm+'\n'+test)}
  catch(e){console.error(name);throw e}
 }
 console.log('PASS: Farm Below, Coins Aura, full-bag grab, counters, reset, safe zone, conflict and void checks (mocks only)');
})().catch(e=>{console.error(e);process.exit(1)});
