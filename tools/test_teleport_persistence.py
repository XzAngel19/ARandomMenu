#!/usr/bin/env python3
"""Exercise the real boot/teleport source in simulated executor environments.

The filesystem and queue here are mocks shared between fresh getgenv tables.
These tests do not establish how Roblox or a particular executor behaves.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path
import gen_full_boot_harness as harness

ROOT = harness.ROOT
wurst = (ROOT / 'src/Wurst.lua').read_text()
bundle = (ROOT / 'src/libraries/bundle.lua').read_text()
assert '__expose' not in wurst, 'test-only runtime exposure leaked into production'
anchor = 'state.frameworkEnvironment = createGameModuleEnvironment(diagnostics)'
assert wurst.count(anchor) == 1
expose = '''do local g = getgenv() if type(g) == "table" then
    g.__expose = {state=state, configData=configData,
        queueConfigSave=queueConfigSave, flushConfigSave=flushConfigSave}
end end
'''
instrumented = wurst.replace(anchor, expose + anchor, 1)

SETUP = r'''
FILES={}; QUEUED={}; CLOSES={}; DELAYED={}
function isfolder() return true end
function makefolder() end
function isfile(path)
    return FILES[path]~=nil or tostring(path):find('Game_20260716',1,true)~=nil
end
function writefile(path,content) FILES[path]=content end
function readfile(path)
    if FILES[path]~=nil then return FILES[path] end
    if tostring(path):find('Game_20260716',1,true) then return HarnessSavedConfig end
    error('file not found: '..tostring(path))
end
function delfile(path) FILES[path]=nil end
function queue_on_teleport(src) table.insert(QUEUED,src) end
function game:BindToClose(fn) table.insert(CLOSES,fn) end
DateTime={now=function() return {ToIsoDate=function() return '2026-10-31' end} end}
task.delay=function(seconds,fn,...)
    table.insert(DELAYED,{seconds=seconds,fn=fn,args={...}})
end

local function boot()
    GENV.__expose=nil
    local run,err=loadstring(WURST_SOURCE,'@Wurst');assert(run,err)
    local ok,failure=pcall(run);assert(ok,tostring(failure))
    local ex=GENV.__expose
    assert(ex and ex.state and type(ex.state.destruct)=='function', 'boot did not finish')
    return ex
end
local function fire(status)
    LocalPlayer.OnTeleport:Fire(Enum.TeleportState[status])
end
local function listeners()
    local count=0
    for _,c in ipairs(LocalPlayer.OnTeleport.connections) do
        if c.Connected then count+=1 end
    end
    return count
end
local function runAtDestination(source, options)
    options=options or {}
    local origin=GENV
    local oldHttp,oldWait=game.HttpGet,task.wait
    local oldIsLoaded,oldLoaded=game.IsLoaded,game.Loaded
    local oldGameId,oldPlaceId=game.GameId,game.PlaceId
    local destination={};GENV=destination
    game.GameId=options.gameId or oldGameId
    game.PlaceId=options.placeId or oldPlaceId
    if options.loadGameId then
        game.GameId=0
        game.IsLoaded=function() return false end
        game.Loaded={Wait=function() game.GameId=options.loadGameId end}
    end
    local fetches=0
    local function runOrigin(fn)
        local current=GENV;GENV=origin;fn();GENV=current
    end
    task.wait=function(seconds)
        if seconds==1 and options.onWait then
            runOrigin(options.onWait)
        end
    end
    game.HttpGet=function()
        fetches+=1
        if options.onFetch then runOrigin(options.onFetch) end
        return 'getgenv().AUTO_RAN = (getgenv().AUTO_RAN or 0) + 1'
    end
    local fn,err=loadstring(source);assert(fn,err)
    local ok,failure=pcall(fn)
    GENV=origin;game.HttpGet=oldHttp;task.wait=oldWait
    game.IsLoaded=oldIsLoaded;game.Loaded=oldLoaded
    game.GameId=oldGameId;game.PlaceId=oldPlaceId
    assert(ok,tostring(failure))
    return destination.AUTO_RAN or 0,fetches
end
local function expectRun(source, expected, options)
    local count,fetches=runAtDestination(source,options)
    assert(count==expected, 'unexpected destination reload: '..tostring(count)..' wanted '..tostring(expected))
    return fetches
end
'''

TELEPORT = r'''
local a=boot()
local persist=a.state.teleportPersist
assert(persist.enabled and persist.supported)
assert(#QUEUED==0, 'do not queue eagerly at boot')
assert(listeners()==1, 'one active teleport listener')
fire('RequestedFromServer');assert(#QUEUED==0)
fire('Started');assert(#QUEUED==1)
fire('Started');fire('WaitingForServer');fire('InProgress')
assert(#QUEUED==1, 'repeated status events must not queue duplicates')
local first=QUEUED[1]
assert(expectRun(first,1,{placeId=9999})==1, 'same universe must follow')
assert(expectRun(first,1,{loadGameId=20260716})==1, 'wait for GameId on early destination injection')
assert(expectRun(first,0,{gameId=987654})==0, 'different universe must not follow')
assert(expectRun(first,0,{loadGameId=987654})==0, 'check universe after load before fetching')
local savedReadfile=readfile;readfile=nil
assert(expectRun(first,0)==0, 'guarded queue must fail closed without destination readfile')
readfile=savedReadfile

-- Use the real UI option callback, not just the controller API.
local keep=a.state.toggleControls['ClickGUI.Keepafterteleport']
assert(keep and type(keep.setChecked)=='function', 'Keep toggle was not registered')
keep.setChecked(false)
assert(not persist.enabled and a.configData.states['ClickGUI.Keepafterteleport']==false)
assert(listeners()==0, 'Keep OFF must disconnect its listener')
assert(expectRun(first,0)==0, 'Keep OFF must invalidate a queue already submitted')
fire('Started');assert(#QUEUED==1)
keep.setChecked(true)
assert(persist.enabled and listeners()==1)
assert(expectRun(first,0)==0, 're-enabling Keep must not resurrect an old token')
fire('Started');assert(#QUEUED==2)
local second=QUEUED[2]
assert(expectRun(second,1)==1)
fire('Failed')
assert(expectRun(second,0)==0, 'failed teleport must retire its old queue')
fire('Started');assert(#QUEUED==3)
local third=QUEUED[3]
assert(expectRun(third,1)==1)

-- Ordinary GUI teardown during an actual transition must preserve its token.
local gui=CoreGui:FindFirstChild('Wurst');assert(gui)
gui.AncestryChanged:Fire(gui,nil)
assert(listeners()==0)
assert(expectRun(third,1)==1, 'teleport teardown must preserve the submitted queue')
a.state.destruct()
assert(GENV.WURST_STOPPED==true)
assert(expectRun(third,0)==0, 'Destruct after teardown must revoke the queue')
fire('Started');assert(#QUEUED==3)

-- A manual boot after Destruct is allowed, but cannot reauthorize older queues.
local b=boot()
assert(b.state.teleportPersist.enabled and GENV.WURST_STOPPED==false)
assert(expectRun(third,0)==0)
fire('Started');assert(#QUEUED==4)
assert(expectRun(QUEUED[4],1)==1)
b.state.destruct()
assert(expectRun(QUEUED[4],0)==0, 'Destruct must block fresh getgenv after queueing')
fire('Started');assert(#QUEUED==4 and listeners()==0)
print('PASS teleport authorization, Keep UI, cancellation, failure, teardown and manual reload')
'''

ROUND_TRIP = r'''
-- Execute the actual queued loader and boot the actual Wurst source, twice,
-- with a fresh getgenv each hop and shared executor files.
local current=boot()
local oldHttp=game.HttpGet
local bootFetches=0
game.HttpGet=function(self,url,...)
    if tostring(url):find('src/Wurst.lua',1,true) then
        bootFetches+=1
        return WURST_SOURCE
    end
    return oldHttp(self,url,...)
end
for hop=1,2 do
    fire('Started')
    assert(#QUEUED==hop, 'one source should be queued per hop')
    local queued=QUEUED[hop]
    local gui=CoreGui:FindFirstChild('Wurst');assert(gui)
    gui.AncestryChanged:Fire(gui,nil) -- expected old-place UI teardown
    assert(listeners()==0)
    GENV={}
    local load,err=loadstring(queued);assert(load,err);load()
    assert(bootFetches==hop and GENV.__expose and GENV.__expose.state.destruct,
        'queued source did not boot Wurst at the destination')
    current=GENV.__expose
    assert(current.state.teleportPersist.enabled and listeners()==1)
    load() -- a consumed token must not boot a second copy after the new claim
    assert(bootFetches==hop, 'the old queue reloaded a second time')
end
current.state.destruct()
game.HttpGet=oldHttp
print('PASS real queued loader boots Wurst across two fresh-environment hops')
'''

PERSIST_OFF = r'''
local a=boot()
a.state.toggleControls['ClickGUI.Keepafterteleport'].setChecked(false)
a.state.destruct()
local b=boot()
assert(not b.state.teleportPersist.enabled and listeners()==0)
assert(b.configData.states['ClickGUI.Keepafterteleport']==false, 'Keep OFF was not restored')
fire('Started');assert(#QUEUED==0)
b.state.toggleControls['ClickGUI.Keepafterteleport'].setChecked(true)
fire('Started');assert(#QUEUED==1 and expectRun(QUEUED[1],1)==1)
b.state.destruct()
print('PASS Keep OFF survives reload and can be enabled manually')
'''

RACES = r'''
local a=boot();fire('Started');local first=QUEUED[#QUEUED]
assert(expectRun(first,0,{onWait=function() a.state.destruct() end})==0,
    'Destruct during destination wait must prevent fetch')
local b=boot();fire('Started');local second=QUEUED[#QUEUED]
assert(expectRun(second,0,{onFetch=function() b.state.destruct() end})==1,
    'Destruct during HttpGet must prevent executing the fetched source')
print('PASS revocation is checked after wait and after the fetch')
'''

HANDOFF = r'''
local a=boot()
local oldGui=CoreGui:FindFirstChild('Wurst')
assert(listeners()==1 and #CLOSES==2, 'config and MM2 callbacks expected')
-- Capture an actual queued debounce callback with unsaved changes.
a.flushConfigSave()
a.configData.values.HandoffMarker='latest-before-reinject'
a.queueConfigSave()
local pending=DELAYED[#DELAYED]
assert(pending and pending.seconds==0.35)
local b=boot() -- real new boot must synchronously retire a before reading config
assert(a.state.teleportPersist.closed and listeners()==1)
assert(b.configData.values.HandoffMarker=='latest-before-reinject', 'previous config was not flushed before reload')
assert(oldGui.destroyed and #CLOSES==4)
local newGui=CoreGui:FindFirstChild('Wurst');assert(newGui and newGui~=oldGui)
-- An old Destruct or deferred ancestry signal cannot remove the new GUI.
a.state.destruct();oldGui.AncestryChanged:Fire(oldGui,nil)
assert(newGui.destroyed~=true and newGui.Parent~=nil and GENV.WURST_STOPPED==false)
b.configData.values.HandoffMarker='new-runtime'
CLOSES[3]()
local profile='Wurst/Profiles/Game_20260716.lua'
local saved=FILES[profile];assert(saved and saved:find('new%-runtime'))
CLOSES[1]();pending.fn(table.unpack(pending.args))
assert(FILES[profile]==saved, 'retired callbacks must not overwrite the new config')
local telemetry='Wurst/Telemetry/MM2_Trajectory_Calibration.json'
FILES[telemetry]='prior'
CLOSES[4]();assert(FILES[telemetry]=='{}', 'active MM2 close must still save')
FILES[telemetry]='newer-runtime'
CLOSES[2]()
assert(FILES[telemetry]=='newer-runtime', 'retired MM2 close overwrote newer calibration')

-- Even if getgenv changes, old cleanup must not revoke the new owner's token,
-- reset its kill switch, or destroy its GUI.
local priorEnv=GENV
GENV={}
local c=boot()
local cGui=CoreGui:FindFirstChild('Wurst');assert(cGui and cGui~=newGui)
c.configData.values.HandoffMarker='fresh-env-runtime'
CLOSES[5]()
local freshProfile=FILES[profile]
FILES[telemetry]='fresh-env-calibration'
-- The old MM2 callback can run even before its delayed GUI teardown.
CLOSES[4]()
assert(FILES[telemetry]=='fresh-env-calibration', 'older active callback overwrote fresh-env calibration')
b.state.destruct()
assert(FILES[profile]==freshProfile, 'older cleanup overwrote fresh-env profile')
assert(cGui.destroyed~=true and cGui.Parent~=nil and GENV.WURST_STOPPED==false)
fire('Started')
assert(expectRun(QUEUED[#QUEUED],1)==1, 'old teardown revoked a newer runtime')
c.state.destruct()
print('PASS reinjection handoff, stale config callbacks and runtime ownership')
'''

FALLBACK = r'''
-- Without durable file APIs, delaying submission until teleport still protects
-- Destruct before it starts, but a submitted queue cannot be revoked reliably
-- across a fresh getgenv. This asserts/document the fallback, not Delta support.
readfile=nil;writefile=nil;isfile=nil;delfile=nil
local warnings={};warn=function(message) table.insert(warnings,tostring(message)) end
local a=boot();assert(a.state.teleportPersist.enabled and #QUEUED==0)
assert(#warnings>0 and warnings[1]:find('storage unavailable',1,true),
    'release console must disclose the unguarded fallback')
a.state.destruct();fire('Started');assert(#QUEUED==0)
local b=boot();fire('Started');assert(#QUEUED==1)
local stale=QUEUED[1];b.state.destruct()
assert(expectRun(stale,1)==1, 'unguarded queue limitation changed; revisit the documentation')
print('PASS no-file fallback defers queuing; post-submission revocation is not guaranteed')
'''

ALIASES = r'''
queue_on_teleport=nil
queueonteleport=function(src) table.insert(QUEUED,src) end
local a=boot();assert(a.state.teleportPersist.supported)
fire('Started');assert(#QUEUED==1);a.state.destruct()
queueonteleport=nil
syn={queue_on_teleport=function(src) table.insert(QUEUED,src) end}
local b=boot();assert(b.state.teleportPersist.supported)
fire('Started');assert(#QUEUED==2);b.state.destruct()
syn=nil
fluxus={queue_on_teleport=function(src) table.insert(QUEUED,src) end}
local c=boot();assert(c.state.teleportPersist.supported)
fire('Started');assert(#QUEUED==3);c.state.destruct()
print('PASS queueonteleport, syn and fluxus provider aliases')
'''

QUEUE_RETRY = r'''
local attempts=0
queue_on_teleport=function(src)
    attempts+=1
    if attempts==1 then return false end
    table.insert(QUEUED,src)
end
local a=boot()
fire('Started');assert(attempts==1 and #QUEUED==0 and not a.state.teleportPersist.queued)
fire('InProgress');assert(attempts==2 and #QUEUED==1 and a.state.teleportPersist.queued)
fire('Started');assert(attempts==2, 'successful queue must be deduplicated')
a.state.destruct()
print('PASS a rejected queue is retried, then deduplicated')
'''

LOST_STORAGE = r'''
local warnings={};warn=function(message) table.insert(warnings,tostring(message)) end
local a=boot();fire('Started')
local originalWrite=writefile
writefile=function(path,content)
    if path:find('/Teleport_',1,true) then error('storage lost') end
    return originalWrite(path,content)
end
fire('Failed');fire('Started')
local found=false
for _,message in ipairs(warnings) do
    if message:find('storage unavailable',1,true) then found=true end
end
assert(found, 'storage lost after a failed teleport must be reported before retry')
a.state.destruct()
print('PASS storage loss on a teleport retry is disclosed')
'''

LEGACY = r'''
-- A source already submitted by v167 does not read the new authorization.
local oldSnippet=[[
    local genv=(type(getgenv)=='function' and getgenv()) or {}
    genv.WURST_TP_QUEUED=false
    if genv.WURST_STOPPED==true then return end
    if game.GameId~=20260716 then return end
    genv.WURST_BRANCH='arena/9492e6b6-arandommenu'
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(1)
    local ok,err=pcall(function() loadstring(game:HttpGet('old-loader'))() end)
    if not ok then warn(tostring(err)) end
]]
local a=boot();a.state.destruct()
assert(expectRun(oldSnippet,1)==1, 'legacy queue limitation changed; revisit documentation')
print('PASS documents that pre-v168 queues cannot be generically revoked')
'''

WRITE_FAILURE = r'''
local a=boot();fire('Started');local source=QUEUED[1]
local originalWrite=writefile
writefile=function(path,content)
    if path:find('/Teleport_',1,true) then error('mock write failure') end
    return originalWrite(path,content)
end
a.state.destruct()
assert(expectRun(source,0)==0, 'delete fallback must revoke a token when overwrite fails')
print('PASS failed token overwrite falls back to deleting the owned token')
'''

READ_FAILURE = r'''
local warnings={};warn=function(message) table.insert(warnings,tostring(message)) end
local a=boot();fire('Started');local source=QUEUED[1]
local originalRead=readfile
readfile=function(path)
    if path:find('/Teleport_',1,true) then error('read blocked') end
    return originalRead(path)
end
a.state.destruct()
readfile=originalRead
local found=false
for _,message in ipairs(warnings) do
    if message:find('revocation is unverified',1,true) then found=true end
end
assert(found, 'unverifiable token revocation must be reported')
assert(expectRun(source,1)==1, 'read failure limitation changed; revisit documentation')
print('PASS inability to read a token during Destruct is disclosed')
'''

PRODUCTION = r'''
local run,err=loadstring(WURST_SOURCE,'@Wurst');assert(run,err);run()
assert(GENV.__expose==nil, 'release boot leaked its internal state')
assert(type(GENV.WURST_RUNTIME)=='table' and type(GENV.WURST_RUNTIME.Destruct)=='function')
GENV.WURST_RUNTIME.Destruct()
print('PASS production boot has no test-only state exposure')
'''


def run_case(name: str, case: str, real_source: bool = False) -> None:
    source = wurst if real_source else instrumented
    script = ''.join([
        harness.PRELUDE,
        '\nSOURCES={ ["src/libraries/bundle.lua"]=', harness.long_bracket(bundle), ' }\n',
        'WURST_SOURCE=', harness.long_bracket(source), '\n',
        SETUP,
        case,
    ])
    with tempfile.TemporaryDirectory(prefix='teleport-persistence-') as tmp:
        path = Path(tmp) / f'{name}.luau'
        path.write_text(script)
        result = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], text=True, capture_output=True)
    if result.returncode:
        failed = ROOT / 'build' / f'teleport_{name}_failed.luau'
        failed.parent.mkdir(parents=True, exist_ok=True)
        failed.write_text(script)
        raise SystemExit(f'{name} ({failed}):\n{result.stdout[-3500:]}\n{result.stderr}')
    lines = [line for line in result.stdout.splitlines() if line.startswith('PASS ')]
    assert lines, f'{name}: no PASS marker'
    print('\n'.join(lines))


for name, script, real in [
    ('teleport', TELEPORT, False),
    ('round-trip', ROUND_TRIP, False),
    ('persist-off', PERSIST_OFF, False),
    ('races', RACES, False),
    ('handoff', HANDOFF, False),
    ('fallback', FALLBACK, False),
    ('aliases', ALIASES, False),
    ('queue-retry', QUEUE_RETRY, False),
    ('lost-storage', LOST_STORAGE, False),
    ('legacy', LEGACY, False),
    ('write-failure', WRITE_FAILURE, False),
    ('read-failure', READ_FAILURE, False),
    ('production', PRODUCTION, True),
]:
    run_case(name, script, real)
