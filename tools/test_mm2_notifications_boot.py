#!/usr/bin/env python3
"""Boot the real bundle/UI with legacy and explicit Notifications settings."""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
anchor = 'states = { ["ClickGUI.Showdock"] = false },'
assert source.count(anchor) == 1
cases = [
    ('legacy-on', '["MM2.BlurtRoles.InstantRoles"] = true', True, True),
    ('legacy-off', '["MM2.BlurtRoles.InstantRoles"] = false', False, False),
    ('explicit-off', '["MM2.BlurtRoles.InstantRoles"] = true, ["MM2.Notifications.InstantRoles"] = false, ["MM2.Notifications"] = false', False, False),
    ('master-off', '["MM2.BlurtRoles.InstantRoles"] = false, ["MM2.Notifications.InstantRoles"] = true, ["MM2.Notifications"] = false', True, False),
]
with tempfile.TemporaryDirectory(prefix='notifications-boot-') as temp:
    for name, states, option, master in cases:
        body = source.replace(anchor, 'states = { ["ClickGUI.Showdock"] = false, ' + states + ' },', 1)
        probe = r'''
local feature
for _,item in ipairs(ex.allFeatures) do if item.configKey=='MM2.Notifications' then feature=item end end
assert(feature and feature.categoryName=='Utilities')
-- v191: the alert set grew (configurable radius/cooldown + the sheriff alert)
-- and every row must exist in the real booted UI, not just in the source.
assert(ex.state.toggleControls['MM2.Notifications.SheriffDown'],
 'v191: the Sheriff Down alert must be a real row')
local radius=assert(ex.state.valueControls['MM2.Notifications.Closeradius'],
 'v191: Close radius must be a real slider')
local cooldown=assert(ex.state.valueControls['MM2.Notifications.Closecooldown'],
 'v191: Close cooldown must be a real slider')
assert(radius.default == 30, 'Close radius defaults to 30 studs')
assert(cooldown.default == 8, 'Close cooldown defaults to 8 s')
assert(ex.state.toggleControls['MM2.Notifications.MurderClose'],
 'the proximity alert itself still exists')
local instant=assert(ex.state.toggleControls['MM2.Notifications.InstantRoles'])
assert(instant.getChecked()==EXPECT_OPTION, 'real UI must restore the migrated option')
assert(feature.enabled==EXPECT_MASTER, 'real card must restore the migrated master')
assert((ex.featureConnections.MM2NotificationsTick~=nil)==EXPECT_MASTER,
 'the restored master controls the actual scheduler')
assert(ex.configData.states['MM2.BlurtRoles.InstantRoles']==nil, 'legacy key is removed after migration')
assert(ex.state.mm2Core.mm2Settings.instantRoleNotify==EXPECT_OPTION)
assert(ex.state.toggleControls['MM2.BlurtRoles.InstantRoles']==nil, 'public Blurt has no private checkbox')
print('PASS actual Notifications boot/migration: CASE')
'''.replace('EXPECT_OPTION', str(option).lower()).replace('EXPECT_MASTER', str(master).lower()).replace('CASE', name)
        path = Path(temp) / (name + '.luau')
        path.write_text(body + '\n' + probe, encoding='utf-8')
        result = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(f'{name} failed:\n{result.stdout[-6000:]}\n{result.stderr}')
        print(next(line for line in result.stdout.splitlines() if line.startswith('PASS actual Notifications')))
