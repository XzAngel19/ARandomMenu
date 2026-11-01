#!/usr/bin/env python3
"""Boot an unrecognized game and test universal cards plus delayed renaming."""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text()
anchor = 'game = {\n    PlaceId = 142823291,\n    GameId = 20260716,'
assert source.count(anchor) == 1
source = source.replace(anchor, 'game = {\n    PlaceId = 123456789,\n    GameId = 20260716,', 1)
# Make the replicated hierarchy genuinely unknown rather than MM2-like.
for name in ('HarnessRoundStart', 'HarnessRoundEnd', 'HarnessRoleRemote'):
    old = f'{name}.Parent = gameplayFolder'
    assert source.count(old) == 1
    source = source.replace(old, f'{name}.Parent = nil', 1)
source += r'''
local function byName(name)
    for _, feature in ipairs(ex.allFeatures) do
        if feature.name == name then return feature end
    end
end
assert(ex.state.activeGameName == nil, 'the test must boot Universal, not MM2')
assert(not ex.state.clickGui.categories.Combat, 'Combat is no longer a window')
assert(ex.state.framework.Categories.Combat == ex.state.framework.Categories.Exploits,
    'legacy Combat modules must resolve into Exploits')
local aura, aim = byName('KillAura'), byName('Aimbot')
assert(aura and aim and not byName('Knife Stab') and not byName('Aim Assist'))
assert(aura.categoryName=='Exploits' and aim.categoryName=='Exploits')
assert(aura.configKey=='Universal.KillAura' and aim.configKey=='Universal.AimAssist')
assert(ex.state.moduleSearch.Resolve('Aim Assist').entry.displayName=='Aimbot')
assert(ex.state.moduleSearch.Resolve('KillAura').entry.feature==aura)

-- A late game fingerprint adapts the existing card without duplicating it.
local cardCount = #ex.allFeatures
local oldKey = aura.configKey
aura.description = 'MM2 knife controller'
aura:SetName('Knife Stab')
assert(#ex.allFeatures==cardCount and aura.configKey==oldKey and aura.name=='Knife Stab')
assert(not byName('KillAura') and byName('Knife Stab')==aura)
assert(aura.registry['Knife Stab']==aura and aura.registry.KillAura==nil)
assert(ex.state.moduleSearch.Resolve('Knife Stab').entry.feature==aura)
assert(aura.row:GetAttribute('FeatureSortName')=='knife stab')
local title = aura.row:FindFirstChild('Title')
local record = title and ex.state.bitmapText._live[title]
assert(record and record.request.segments[1].text=='Knife Stab', 'bitmap title must actually repaint')
local rows = {}
for _, row in ipairs(ex.state.clickGui.categories.Exploits.window.body:GetChildren()) do
    local key=row:GetAttribute('FeatureSortName')
    if type(key)=='string' then table.insert(rows, row) end
end
table.sort(rows, function(a,b) return a.LayoutOrder < b.LayoutOrder end)
for i=2,#rows do
    assert(rows[i-1]:GetAttribute('FeatureSortName') <= rows[i]:GetAttribute('FeatureSortName'),
        'late rename must retain alphabetical order')
end
aura:SetName('KillAura')
assert(ex.state.moduleSearch.Resolve('KillAura').entry.feature==aura and aura.configKey==oldKey)
assert(record.request.segments[1].text=='KillAura', 'restored title must repaint')
print('PASS menu organization: universal cards, legacy category alias and late MM2 rename/search/order')
'''

with tempfile.TemporaryDirectory(prefix='menu-organization-') as tmp:
    script = Path(tmp) / 'boot.luau'
    script.write_text(source)
    result = subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stdout[-5000:] + '\n' + result.stderr)
    assert 'PASS menu organization:' in result.stdout
    print('PASS menu organization: universal cards, legacy category alias and late MM2 rename/search/order')
