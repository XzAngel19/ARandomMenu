#!/usr/bin/env python3
"""Auto Shoot: shared-path refusal cannot trigger a second, unsafe transport.

Exercises the real Bullet/CFrame functions with deterministic remote mocks.
An exception cannot prove whether a real packet reached the server.
"""
from pathlib import Path
import os
import subprocess
import tempfile
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
AUTO = (ROOT / 'src/games/MM2/Combat/AutoShoot.lua').read_text()
code = PRELUDE + r'''
local calls=0
local raiseRemote=false
local remote={IsA=function(_,name) return name=='RemoteEvent' end}
function remote:FireServer(origin,endpoint)
    calls+=1
    assert(origin.Position and endpoint.Position)
    if raiseRemote then error('transport failure') end
end
local gun={Enabled=true,FindFirstChild=function(_,name) return name=='Shoot' and remote or nil end,
    GetAttribute=function() return nil end}
local target={Character={}}
local targetRoot={Position=Vector3.new(30,0,0)}
local character={}
local localRoot={CFrame=CFrame.new(Vector3.zero)}
local function getGunOriginCFrame() return CFrame.new(Vector3.zero) end
local function computeTargetEndpoint() return targetRoot.Position end
local settings={wallCheck=true}
local lastShotSentAt=0
local clear=true
local function isWeaponPathClear() return clear end
local state={}
''' + section(AUTO, '    local function fireCFrameShotImmediate(',
              '    -- Shared helper for Auto Win') + r'''
local functions={fireCFrameShotImmediate,fireBulletShotImmediate}
local keys={'mm2FireSilentShot','mm2FireGunShot'}
for index,fire in ipairs(functions) do
    local key=keys[index]
    calls=0; now=42; lastShotSentAt=0
    state[key]=function(_,opts)
        assert(opts.wallCheck==true and opts.continuous==true)
        return false
    end
    assert(fire(target,targetRoot,character,localRoot,gun)==false)
    assert(calls==0 and lastShotSentAt==0, 'refusal triggered fallback')
    state[key]=function() error('uncertain shared result') end
    assert(fire(target,targetRoot,character,localRoot,gun)==false)
    assert(calls==0 and lastShotSentAt==now, 'exception triggered fallback or was not paced')
    lastShotSentAt=0
    state[key]=function()
        remote:FireServer(CFrame.new(Vector3.zero), CFrame.new(targetRoot.Position))
        error('error after possible send')
    end
    assert(fire(target,targetRoot,character,localRoot,gun)==false)
    assert(calls==1 and lastShotSentAt==now, 'uncertain send caused duplicate packet or was not paced')
    calls=0
    state[key]=function() return true end
    assert(fire(target,targetRoot,character,localRoot,gun)==true)
    assert(calls==0 and lastShotSentAt==now, 'shared success triggered fallback')
    state[key]=nil
    clear=false; calls=0; lastShotSentAt=0
    assert(fire(target,targetRoot,character,localRoot,gun)==false)
    assert(calls==0, 'fallback bypassed WallCheck')
    clear=true; raiseRemote=true
    assert(fire(target,targetRoot,character,localRoot,gun)==false)
    assert(calls==1 and lastShotSentAt==now, 'transport exception reported success or was not paced')
    raiseRemote=false; calls=0
    assert(fire(target,targetRoot,character,localRoot,gun)==true)
    assert(calls==1 and lastShotSentAt==now, 'fallback must send once and report only dispatch')
end
print('PASS Auto Shoot Bullet/CFrame: no retry after refusal/error; fallback wall and dispatch result')
'''
with tempfile.TemporaryDirectory(prefix='mm2-auto-shoot-dispatch-') as directory:
    script = Path(directory) / 'dispatch.luau'
    script.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], check=True)
