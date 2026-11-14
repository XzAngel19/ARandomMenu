const fs=require('node:fs'),path=require('node:path'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),read=p=>fs.readFileSync(p,'utf8');const fixture=path.join(root,'tools/angel_hub_partial_tests');
const file=read(path.join(root,'Angel-Hub-GUI-Continuacion.txt'));
const src=file.slice(file.indexOf('local function installMM2Win(screenGui)'),file.indexOf('\nlocal function initializeScript()'));
const setup=`
game.PlaceId=142823291;Vector3.zero=Vector3.new(0,0,0);AngelHub.connections={}
local function connectInput(s,f)local c=s:Connect(f);table.insert(AngelHub.connections,c);return c end
AngelHub.findMM2Map=function()return map.Parent and map end
AngelHub.setters['Auto Farm']=function(v)V['Auto Farm']=v end
AngelHub.setters['Insta Kill As Murder']=function(v)V['Insta Kill As Murder']=v end
AngelHub.setters['Insta Kill As Sheriff']=function(v)V['Insta Kill As Sheriff']=v end
`;
(async()=>{const prefix=process.env.LUAU_TEST_PREFIX||path.join(root,'tools/luau');const {Lua}=await import(pathToFileURL(path.join(prefix,'node_modules/@luau-rs/luau/dist/direct-api.js')).href);
 for(const name of ['win-counter-checks.luau','win-murder-checks.luau']){
  const lua=await Lua.create({sandbox:true});let test=read(path.join(fixture,name)).replaceAll('installGameplay(screenGui)','installMM2Win(screenGui)');
  if(name==='win-murder-checks.luau')test=test.replace("started.OnClientEvent:Fire(10);remote.shouldYield=false;targetRoot.Anchored=true;heartbeat:Fire(.11);runQueue();assert(remote.calls==3)","root.Position=Vector3.new(0,0,0);started.OnClientEvent:Fire(10);remote.shouldYield=false;targetRoot.Anchored=true;heartbeat:Fire(.11);root.Position=character.lastPivot.Position;heartbeat:Fire(.11);runQueue();assert(remote.calls==3)");
  try{lua.execute(read(path.join(fixture,'gameplay-mock.luau'))+'\nlocal fakeNow=100;local os={clock=function()return fakeNow end}\n'+setup+'\n'+src+'\n'+test)}catch(e){console.error(name);throw e}
 }
 const farm=file.slice(file.indexOf('local function installMM2Farm(screenGui)'),file.indexOf('local function installMM2Unbox(screenGui)'));
 const conflict=await Lua.create({sandbox:true});
 conflict.execute(read(path.join(fixture,'gameplay-mock.luau'))+'\nlocal fakeNow=100;local os={clock=function()return fakeNow end}\n'+setup+'\n'+farm+'\n'+src+'\n'+read(path.join(__dirname,'conflict-checks.luau')));
 console.log('PASS: Auto Win platform, counters, attacks, restoration and Farm conflicts (mocks only)');
})().catch(e=>{console.error(e);process.exit(1)});
