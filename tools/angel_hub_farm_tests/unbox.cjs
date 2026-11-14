const fs=require('node:fs'),path=require('node:path'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),read=p=>fs.readFileSync(p,'utf8');
const fixture=path.join(root,'tools/angel_hub_partial_tests');
const file=read(path.join(root,'Angel-Hub-GUI-Continuacion.txt'));
const src=file.slice(file.indexOf('local function installMM2Unbox(screenGui)'),file.indexOf('\nlocal function initializeScript()'));
(async()=>{
 const prefix=process.env.LUAU_TEST_PREFIX||path.join(root,'tools/luau');const {Lua}=await import(pathToFileURL(path.join(prefix,'node_modules/@luau-rs/luau/dist/direct-api.js')).href);
 for(const name of ['unbox-checks.luau','unbox-yield-checks.luau']){
  const lua=await Lua.create({sandbox:true});const fn=name==='unbox-yield-checks.luau'?'if module.yieldNow then coroutine.yield("require") end;return module.data':'return module.data';
  const setup=`game.PlaceId=142823291;AngelHub.connections={};AngelHub.actions={};local function connectInput(s,f)local c=s:Connect(f);table.insert(AngelHub.connections,c);return c end;local require=function(module) ${fn} end`;
  let test=read(path.join(fixture,name)).replaceAll('installGameplay(screenGui)','installMM2Unbox(screenGui)');
  if(name==='unbox-yield-checks.luau')test=test.replace("AngelHub.setters['Auto Unbox'](true);allTasks();assert(calls==0 and #tasks==1)","AngelHub.setters['Auto Unbox'](true);heartbeat:Fire(.1);allTasks();assert(calls==0 and #tasks==1)");
  try{lua.execute(read(path.join(fixture,'gameplay-mock.luau'))+'\nlocal fakeNow=100;local os={clock=function()return fakeNow end}\n'+setup+'\n'+src+'\n'+test)}catch(e){console.error(name);throw e}
 }
 console.log('PASS: Auto Unbox live catalogue, balances, receipts and cancellation (mocks only)');
})().catch(e=>{console.error(e);process.exit(1)});
