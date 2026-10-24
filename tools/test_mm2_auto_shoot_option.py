#!/usr/bin/env python3
"""Execute the nested Auto Shoot controller, not a reimplementation of its loop."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section
ROOT = Path(__file__).resolve().parents[1]
S = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()
script = PRELUDE + r'''
local configData={states={['MM2.AutoShoot']=true},values={['Shortcut.MM2AutoShoot']='J'}}
local state={}
local shootOptionsReady=true
local shootFeatureActive=false
local autoShootActive=false
local autoShootWanted=false
local updateAutoShootConnection
local status=nil
local ShootFeature={SetStatus=function(_,s) status=s end}
local loop
local featureConnections={}
local TaskManager={Connect=function(_,fn)
 loop=fn;return {Disconnect=function() loop=nil end}
end}
local function disconnectFeatureConnection(k)
 if featureConnections[k] then featureConnections[k]:Disconnect();featureConnections[k]=nil end
end
local infrastructure=false
local function refreshShootInfrastructure() infrastructure=shootFeatureActive or autoShootActive end
local character={}
local LocalPlayer={Character=character}
local gun={Parent=character,Enabled=true}
local target={position=Vector3.new(1000,0,0)}
local targetAvailable=true
local lastRejectReason=''
local requests,accepted=0,0
local lastPosition
local function getPlayerWeapon(_,_,held) assert(held);return gun end
local function getSelectedShootTarget() return targetAvailable and target or nil end
local function fireGunAtTarget(t,opts)
 requests+=1
 assert(opts.whenReady and opts.quiet and opts.silent==nil and opts.maxError==nil)
 if not gun.Enabled then lastRejectReason='Reloading';return false end
 accepted+=1;lastPosition=t.position;return true
end
''' + section(S, '    local function toggleShootMurderer(', '    ShootFeature = createUniversalFeature(') + r'''
assert(configData.states['MM2.Shoot.AutoShoot'] and configData.states['MM2.Shoot'] and configData.values['Shortcut.MM2ShootAutoShoot']=='J','migrate prior Auto Shoot and explicit binding')
toggleAutoShoot(true)
assert(not loop and not autoShootActive and requests==0 and not infrastructure,'checkbox cannot bypass the Shoot master')
toggleShootMurderer(true)
assert(loop and infrastructure and autoShootActive and accepted==1 and lastPosition.X==1000,'enable attempts immediately, without distance gate')
loop(1/120);assert(accepted==2)
gun.Enabled=false;loop(1/120);assert(status=='Reloading' and accepted==2)
gun.Enabled=true;target.position=Vector3.new(1001,0,0);loop(1/120)
assert(accepted==3 and lastPosition.X==1001,'next current frame after readiness, not 3.1s after a rejected request')
gun.Parent={};local before=requests;loop(1/120)
assert(status=='Equip gun' and before==requests,'no autoequip')
gun.Parent=character;targetAvailable=false;loop(1/120);assert(status=='No target')
targetAvailable=true;toggleShootMurderer(false)
assert(not loop and not autoShootActive and autoShootWanted and not infrastructure)
toggleShootMurderer(true);assert(loop and autoShootActive)
toggleAutoShoot(false);assert(not loop and not autoShootActive and shootFeatureActive and status==nil)
toggleShootMurderer(false);shootOptionsReady=false;toggleAutoShoot(true)
local previous=accepted
toggleShootMurderer(true);assert(not loop and accepted==previous,'do not fire before saved Gun settings finish restoring')
shootOptionsReady=true;updateAutoShootConnection();assert(loop and accepted==previous+1)
print('PASS nested Auto Shoot: immediate/current-frame, 1000 studs, current target, native readiness, master/option OFF, restart, held-only, status')
'''
assert 'local AutoShootFeature' not in S and '"Fire delay"' not in S
for removed in (
    'Silent sweep', 'Silent spawn', 'Spawn A/B status', 'Shot gate status',
    'Auto lead', 'Lead offset ms', 'Prediction status', 'Reset prediction',
):
    assert f'"{removed}"' not in S, f'{removed} must not be an ordinary menu row'
for retained in ('Auto Shoot', 'Aim method', 'Target', 'Raw', 'Macro'):
    assert f'"{retained}"' in S
assert 'mm2ShotGateHold' not in S and 'spawnStats' not in S
with tempfile.TemporaryDirectory(prefix='auto-shoot-option-') as tmp:
    p=Path(tmp)/'test.luau'
    p.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
