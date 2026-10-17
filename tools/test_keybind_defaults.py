#!/usr/bin/env python3
"""Execute the real default-key migration and activation registration."""
import os
import re
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import section
ROOT = Path(__file__).resolve().parents[1]
W = (ROOT / 'src/Wurst.lua').read_text()
migration = section(W, '-- One-time reset of old automatic key defaults.', 'local state: any =')
registration = section(W, 'state.bindFeatureActivationKey = function(', '\ndo\nlocal function shortcutInputAllowed')
script = r'''
local Enum={KeyCode={Unknown='Unknown',RightShift='RightShift',Q='Q',G='G',J='J'}}
local configData={ui={toggleKey='Unknown'},values={['Shortcut.MM2Shoot']='Q',['MM2Teleport.GetGunkey']='G',
    ['TRSShoot.Shotkey']='G',['Options.Target']='PlayerName',['Options.Amount']=4}}
local function loadDefaults()
''' + migration + r'''
return savedToggleKey
end
assert(loadDefaults()=='RightShift')
assert(configData.values['Shortcut.MM2Shoot']=='Unknown')
assert(configData.values['MM2Teleport.GetGunkey']=='Unknown')
assert(configData.values['TRSShoot.Shotkey']=='Unknown')
assert(configData.values['Options.Target']=='PlayerName' and configData.values['Options.Amount']==4)
configData.values['Shortcut.MM2Shoot']='J';configData.ui.toggleKey='J'
assert(loadDefaults()=='J' and configData.values['Shortcut.MM2Shoot']=='J','migration must run only once')
local state={shortcutBindings={Shoot={key='Unknown'}}}
''' + registration + r'''
local fired=0
local feature={configKey='Shoot'}
state.bindFeatureActivationKey(feature,'Q',function() fired+=1 end)
assert(state.shortcutBindings.Shoot.key=='Unknown','registering an action must not bind Q')
state.shortcutBindings.Shoot.key='J'
state.bindFeatureActivationKey(feature,'Q',function() fired+=1 end)
assert(state.shortcutBindings.Shoot.key=='J','explicit user assignment must survive registration')
state.shortcutBindings.Shoot.onPress();assert(fired==1)
print('PASS keybinds: one-time reset, no registration defaults, explicit assignments persist')
'''
for filename in ['src/games/MM2/base.lua', 'src/games/TRS/base.lua', 'src/games/MM2.luau', 'src/games/TRS.luau']:
    text = (ROOT / filename).read_text()
    for value in re.findall(r'\b(?:shootKey|getGunKey|powerShotKey|longShotKey|pickupKey|passKey)\s*=\s*Enum.KeyCode\.(\w+)', text):
        assert value == 'Unknown', (filename, value)
assert 'state.isMobile or state.toggleKey == Enum.KeyCode.Unknown' in W
with tempfile.TemporaryDirectory(prefix='keybind-defaults-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
