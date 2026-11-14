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
  const farmLua = await Lua.create({ sandbox: true });
  farmLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('farm-combat-checks.luau'));
  const farmCounterLua = await Lua.create({ sandbox: true });
  farmCounterLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('farm-counter-checks.luau'));
  const farmProgressLua = await Lua.create({ sandbox: true });
  farmProgressLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('farm-progress-checks.luau'));
  const shootLua = await Lua.create({ sandbox: true });
  shootLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('shoot-checks.luau'));
  const shootRoleLua = await Lua.create({ sandbox: true });
  shootRoleLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('shoot-role-checks.luau'));
  const winCounterLua = await Lua.create({ sandbox: true });
  winCounterLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('win-counter-checks.luau'));
  const winSheriffLua = await Lua.create({ sandbox: true });
  winSheriffLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('win-sheriff-checks.luau'));
  const unboxLua = await Lua.create({ sandbox: true });
  unboxLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}; local require = function(module) return module.data end\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('unbox-checks.luau'));
  const unboxYieldLua = await Lua.create({ sandbox: true });
  unboxYieldLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}; local require = function(module) if module.yieldNow then coroutine.yield("require") end return module.data end\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('unbox-yield-checks.luau'));
  const emotesLua = await Lua.create({ sandbox: true });
  emotesLua.execute(readTest('gameplay-mock.luau') + '\nlocal require = function(module) return module.data end\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('emotes-checks.luau'));
  const gunAssistLua = await Lua.create({ sandbox: true });
  gunAssistLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('gun-assist-checks.luau'));
  const voteLua = await Lua.create({ sandbox: true });
  voteLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('vote-checks.luau'));
  const guiLua = await Lua.create({ sandbox: true });
  guiLua.execute(readTest('gui-mock.luau') + '\n' + file + `
assert(shared.AngelHub and shared.AngelHub.actions, "GUI failed to initialize")
local hub = shared.AngelHub
assert(hub.values["Auto Farm"] == false and hub.values["Auto Win"] == false and hub.values["Gun ESP"] == false and hub.values["Anti AFK"] == false)
assert(hub.setters["Auto Farm"](true) == false and hub.values["Auto Farm"] == false)
assert(hub.values["Select Map"] == "Waiting for maps")
assert(hub.values["Box To Open"] == "Waiting for boxes" and hub.values["Reveal Animation"] == "Off")
for _,card in ipairs(hub.searchables) do
 if card.Name == "Insta Kill As Sheriff" or card.Name == "Win Sheriff WallCheck" then assert(card:GetAttribute("GroupHidden")) end
end
hub.cycleOptions["Select Map"]({"Hospital", "Factory"})
assert(hub.values["Select Map"] == "Hospital")
hub.setters["Select Map"]("Factory");assert(hub.values["Select Map"] == "Factory")
hub.cycleOptions["Select Map"]({"Bank", "Factory"});assert(hub.values["Select Map"] == "Factory")
assert(hub.values["Farm Mode"] == "Walk")
hub.setters["Farm Mode"]("Under"); assert(hub.values["Farm Mode"] == "Walk")
hub.setters["Farm Mode"]("Below"); assert(hub.values["Farm Mode"] == "Below")
assert(hub.values["Stay Under When Round Starts"] == nil)
assert(hub.values["Shoot Mode"] == "Bullet")
hub.setters["Shoot Mode"]("Experimental"); assert(hub.values["Shoot Mode"] == "Bullet")
hub.setters["Shoot Mode"]("CFrame"); assert(hub.values["Shoot Mode"] == "CFrame")
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
  const winGui = await Lua.create({ sandbox: true });
  winGui.execute(readTest('gui-mock.luau') + `
local storage=Instance.new('Folder');services.ReplicatedStorage=storage
local remotes=Instance.new('Folder');remotes.Name='Remotes';remotes.Parent=storage
local gameplay=Instance.new('Folder');gameplay.Name='Gameplay';gameplay.Parent=remotes
for _,name in ipairs({'VictoryScreen','RoundEndFade','RoundStart'})do
 local remote=Instance.new('RemoteEvent');remote.Name=name;remote.OnClientEvent=event();remote.Parent=gameplay
end
` + file + `
local h=shared.AngelHub
local cards={};for _,card in ipairs(h.searchables)do cards[card.Name]=card end
assert(not cards['Insta Kill As Sheriff'].Visible and not cards['Win Sheriff WallCheck'].Visible)
h.setters['Auto Win'](true)
assert(h.values['Auto Win'] and cards['Insta Kill As Sheriff'].Visible and not cards['Win Sheriff WallCheck'].Visible)
h.setters['Insta Kill As Sheriff'](true);assert(cards['Win Sheriff WallCheck'].Visible)
h.setters['Auto Win'](false)
assert(not cards['Insta Kill As Sheriff'].Visible and not cards['Win Sheriff WallCheck'].Visible and cards['Sheriff Wins'].Visible ~= false)
shared.AngelHubGui:Destroy()
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
shared.AngelHub.setters["Shoot Mode"]("Experimental")
assert(shared.AngelHub.values["Shoot Mode"] == "Experimental")
assert(shared.AngelHub.setters["Auto Shoot"](true) == false)
assert(shared.AngelHub.values["Remove Textures"] == false)
assert(shared.AngelHub.setters["Remove Textures"](true) == false)
shared.AngelHubGui:Destroy()
`);
  console.log('PASS compile, gameplay, PC/mobile MM2/non-MM2 GUI and unload (mocks only)');
})().catch(err => { console.error(err); process.exitCode = 1; });
