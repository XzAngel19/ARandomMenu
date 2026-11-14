const fs = require('node:fs');
const assert = require('node:assert/strict');
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
  // Count the actual module switches in the menu, including Auto Win sub-switches.
  const moduleNames = [...file.matchAll(/\baddModule\([^\n]*?,\s*"([^"]+)"/g)].map(match => match[1]);
  const supportBlock = file.slice(file.indexOf('local supportedModules ='), file.indexOf('    local function message(text)', file.indexOf('local supportedModules =')));
  const supported = new Set([...supportBlock.matchAll(/\["([^"]+)"\]\s*=\s*true/g)].map(match => match[1]));
  const pending = moduleNames.filter(name => !supported.has(name));
  const expectedPending = ['Gun Aimbot', 'Auto Knife Throw', 'Auto Fling Selected Target', 'Player Shield', 'Impact Shield',
    'Fling Sheriff And Get Gun', 'Fling Murder If Dead', 'Auto Blurt', 'Wall Crawl State', 'Air Swim', 'Player ESP', 'Disguise Character', 'FreeCam'];
  assert.equal(moduleNames.length, 49); assert.equal(new Set(moduleNames).size, 49);
  assert.equal(moduleNames.filter(name => supported.has(name)).length, 36);
  assert.deepEqual(pending, expectedPending);
  assert.equal([...supported].filter(name => !moduleNames.includes(name)).length, 0);
  const buttons = [...file.matchAll(/addButton\([^\n]+?,\s*"([^"]+)"/g)].map(match => match[1]);
  const pendingButtons = ['Kill All', 'Fling Murderer', 'Fling Sheriff', 'Fling All Innocents', 'Fling', 'Blurt Roles', 'Start Calibration', 'Open Calibration'];
  assert.equal(buttons.length, 28); assert.equal(pendingButtons.filter(name => buttons.includes(name)).length, 8);
  const boundActions = new Set([...file.matchAll(/AngelHub\.actions\["([^"]+)"\]\s*=/g)].map(match => match[1]));
  for (const name of ['High Jump', 'Long Jump', 'Create', 'Load', 'Save', 'Rejoin Server', 'Reset Settings', 'Unload']) boundActions.add(name);
  for (const name of buttons) assert.equal(boundActions.has(name), !pendingButtons.includes(name), `Action status: ${name}`);
  const blockedBlock = file.slice(file.indexOf('local UNIMPLEMENTED_TOGGLES ='), file.indexOf('local function addToggle('));
  const blockedOptions = [...blockedBlock.matchAll(/\["([^"]+)"\]\s*=\s*true/g)].map(match => match[1]);
  assert.equal(blockedOptions.length, 24);
  assert.ok(file.includes('{"Zoom Through Walls", "Speed Auto Jump", "Jump Auto Jump"}'));
  console.log(`Inventory: ${moduleNames.length} module switches, 36 connected, ${pending.length} blocked; 28 buttons, 20 connected, 8 pending; 27 explicitly blocked options`);
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
  const winMurderLua = await Lua.create({ sandbox: true });
  winMurderLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('win-murder-checks.luau'));
  const unboxLua = await Lua.create({ sandbox: true });
  unboxLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}; local require = function(module) return module.data end\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('unbox-checks.luau'));
  const unboxYieldLua = await Lua.create({ sandbox: true });
  unboxYieldLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}; local require = function(module) if module.yieldNow then coroutine.yield("require") end return module.data end\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('unbox-yield-checks.luau'));
  const emotesLua = await Lua.create({ sandbox: true });
  emotesLua.execute(readTest('gameplay-mock.luau') + '\nlocal require = function(module) return module.data end\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('emotes-checks.luau'));
  const gunAssistLua = await Lua.create({ sandbox: true });
  gunAssistLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('gun-assist-checks.luau'));
  const coinEspLua = await Lua.create({ sandbox: true });
  coinEspLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('coin-esp-checks.luau'));
  const notificationLua = await Lua.create({ sandbox: true });
  notificationLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('notifications-checks.luau'));
  const airWalkLua = await Lua.create({ sandbox: true });
  airWalkLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('airwalk-checks.luau'));
  const chamsLua = await Lua.create({ sandbox: true });
  chamsLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('chams-checks.luau'));
  const nametagsLua = await Lua.create({ sandbox: true });
  nametagsLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('nametags-checks.luau'));
  const hpLua = await Lua.create({ sandbox: true });
  hpLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('hp-checks.luau'));
  const notificationYieldLua = await Lua.create({ sandbox: true });
  notificationYieldLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('notifications-yield-checks.luau'));
  const markersLua = await Lua.create({ sandbox: true });
  markersLua.execute(readTest('gameplay-mock.luau') + '\nlocal fakeNow = 100; local os = {clock = function() return fakeNow end}\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('markers-checks.luau'));
  const teleportSearchLua = await Lua.create({ sandbox: true });
  teleportSearchLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('teleport-search-checks.luau'));
  const teleportGlideLua = await Lua.create({ sandbox: true });
  teleportGlideLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('teleport-glide-checks.luau'));
  const flyLua = await Lua.create({ sandbox: true });
  flyLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('fly-checks.luau'));
  const walkFlingLua = await Lua.create({ sandbox: true });
  walkFlingLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('walkfling-checks.luau'));
  const pointersLua = await Lua.create({ sandbox: true });
  pointersLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('pointers-checks.luau'));
  const pointerRolesLua = await Lua.create({ sandbox: true });
  pointerRolesLua.execute(readTest('gameplay-mock.luau') + '\n' + toggles + '\n' + file.slice(start, end) + '\n' + readTest('pointers-role-checks.luau'));
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
assert(hub.values["Marker Point"] == nil and hub.values["Teleport Point"] == nil)
hub.listOptions["Marker Point"]({"Home", "Roof"});assert(hub.values["Marker Point"] == "Home")
hub.setters["Marker Point"]("Roof");assert(hub.values["Marker Point"] == "Roof")
hub.listOptions["Marker Point"]({"Roof", "Hill"});assert(hub.values["Marker Point"] == "Roof")
hub.listOptions["Marker Point"]({});assert(hub.values["Marker Point"] == nil)
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
assert(not cards['Insta Kill As Sheriff'].Visible and not cards['Insta Kill As Murder'].Visible and not cards['Win Sheriff WallCheck'].Visible)
h.setters['Auto Win'](true)
assert(cards['Insta Kill As Murder'].Visible)
h.setters['Insta Kill As Murder'](true);assert(h.values['Insta Kill As Murder'])
assert(h.values['Auto Win'] and cards['Insta Kill As Sheriff'].Visible and not cards['Win Sheriff WallCheck'].Visible)
h.setters['Insta Kill As Sheriff'](true);assert(cards['Win Sheriff WallCheck'].Visible)
h.setters['Auto Win'](false)
assert(not cards['Insta Kill As Sheriff'].Visible and not cards['Win Sheriff WallCheck'].Visible and cards['Sheriff Wins'].Visible ~= false)
shared.AngelHubGui:Destroy()
`);
  const safeConfigLua = await Lua.create({ sandbox: true });
  safeConfigLua.execute(readTest('gui-mock.luau') + `
run.RenderStepped=event();run.Stepped=event()
isfile=function()return true end;readfile=function()return "saved" end
function services.HttpService:JSONDecode()return {Autoload=true,["Walk Fling"]=true}end
` + file + `
assert(shared.AngelHub.values["Autoload"]==true and shared.AngelHub.values["Walk Fling"]==false)
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
