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
  const toggles = file.slice(file.indexOf('local UNIMPLEMENTED_TOGGLES ='), file.indexOf('local function addToggle('));
  lua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('gameplay-checks.luau'));
  const guiLua = await Lua.create({ sandbox: true });
  guiLua.execute(readTest('gui-mock.luau') + '\n' + file + `
assert(shared.AngelHub and shared.AngelHub.actions, "GUI failed to initialize")
local hub = shared.AngelHub
assert(hub.values["Auto Farm"] == false and hub.values["Gun ESP"] == false and hub.values["Anti AFK"] == false)
assert(hub.setters["Auto Farm"](true) == false and hub.values["Auto Farm"] == false)
assert(hub.values["Speed Mode"] == "Velocity")
hub.setters["Speed Value"](-12);assert(hub.values["Speed Value"] == -12)
hub.setters["Speed Value"](0);assert(hub.values["Speed Value"] == 0)
hub.setters["Enable Gravity"](true)
hub.setters["Gravity Value"](123)
services.RunService.Heartbeat:Fire(0.1)
assert(workspace.Gravity == 123)
hub.setters["Enable Gravity"](false)
assert(workspace.Gravity == 196.2)
shared.AngelHubGui:Destroy()
assert(not hub.actions)
`);
  const outside = await Lua.create({ sandbox: true });
  outside.execute(readTest('gui-mock.luau') + '\ngame.PlaceId = 1\n' + file + `
assert(shared.AngelHub and shared.AngelHub.actions, "GUI failed outside MM2")
assert(shared.AngelHub.values["Auto Farm"] == nil and shared.AngelHub.values["Gun ESP"] == nil)
assert(shared.AngelHub.values["Noclip"] == false and shared.AngelHub.values["X-Ray"] == false)
shared.AngelHubGui:Destroy()
`);
  const mobile = await Lua.create({ sandbox: true });
  mobile.execute(readTest('gui-mock.luau') + '\nuis.TouchEnabled=true;uis.KeyboardEnabled=false\n' + file + `
assert(shared.AngelHub and shared.AngelHub.actions, "GUI failed on mobile")
assert(shared.AngelHub.values["Aimbot Keybind Value"] == nil)
assert(shared.AngelHub.values["Fly Up Key Value"] == nil)
assert(shared.AngelHub.values["Remove Textures"] == false)
assert(shared.AngelHub.setters["Remove Textures"](true) == false)
shared.AngelHubGui:Destroy()
`);
  console.log('PASS compile, gameplay, PC/mobile MM2/non-MM2 GUI and unload (mocks only)');
})().catch(err => { console.error(err); process.exitCode = 1; });
