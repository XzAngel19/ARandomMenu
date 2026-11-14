const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const read = p => fs.readFileSync(p, 'utf8');
const file = read(path.join(root, 'Angel-Hub-MM2-Integracion-parcial.txt'));
const readTest = p => read(path.join(__dirname, p));
(async () => {
  const prefix = process.env.LUAU_TEST_PREFIX || '/tmp/angel-test-deps';
  const modulePath = path.join(prefix, 'node_modules/@luau-rs/luau/dist/direct-api.js');
  const { Lua } = await import(pathToFileURL(modulePath).href);
  const lua = await Lua.create({ sandbox: true });
  lua.compile(file);
  const start = file.indexOf('local function installGameplay(screenGui)');
  const end = file.indexOf('\nlocal function initializeScript()', start);
  if (start < 0 || end < 0) throw new Error('Gameplay source boundaries not found');
  lua.execute(readTest('gameplay-mock.luau') + '\n' + file.slice(start, end) + '\n' + readTest('gameplay-checks.luau'));
  const guiLua = await Lua.create({ sandbox: true });
  guiLua.execute(readTest('gui-mock.luau') + '\n' + file + `
assert(shared.AngelHub and shared.AngelHub.actions, "GUI failed to initialize")
local hub = shared.AngelHub
assert(hub.values["Auto Farm"] == false and hub.values["Gun ESP"] == false and hub.values["Anti AFK"] == false)
assert(hub.setters["Auto Farm"](true) == false and hub.values["Auto Farm"] == false)
hub.setters["Enable Gravity"](true)
hub.setters["Gravity Value"](123)
services.RunService.Heartbeat:Fire(0.1)
assert(workspace.Gravity == 123)
hub.setters["Enable Gravity"](false)
assert(workspace.Gravity == 196.2)
shared.AngelHubGui:Destroy()
assert(not hub.actions)
`);
  console.log('PASS compile, isolated gameplay, GUI boot and unload (mocks only)');
})().catch(err => { console.error(err); process.exitCode = 1; });
