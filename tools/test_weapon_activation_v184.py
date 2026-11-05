#!/usr/bin/env python3
"""Real Weapons selection/activation rejects no-op tools and can equip when allowed."""
import os
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'src/libraries/Weapons.lua').read_text()
segment=s[s.index('    function library:Best('):s.index('    function library:Destroy(')]
script=r'''
local swings=0
local character={}
function character:FindFirstChildOfClass() return {EquipTool=function(_,tool) tool.Parent=character end} end
local backpack={}
local localPlayer={Character=character}
local tool={Parent=backpack,Enabled=true,Activate=function() swings+=1 end}
local candidate={kind='Tool',instance=tool,label='Sword'}
local library={allowEquip=false,Scan=function() return {candidate} end}
''' + segment + r'''
assert(library:Best({Melee=true})==nil, 'skipped backpack tool cannot be returned as fallback')
assert(not library:Activate(candidate) and swings==0, 'unequipped tool is a no-op, not success')
tool.Parent=character;tool.Enabled=false
assert(not library:Activate(candidate) and swings==0, 'disabled held tool is not usable')
tool.Enabled=true;assert(library:Activate(candidate) and swings==1, 'held enabled tool swings')
tool.Parent=backpack;library.allowEquip=true
assert(library:Best()==candidate and library:Activate(candidate) and tool.Parent==character and swings==2,
    'explicit Auto equip still works')
tool.Activate=function() error('unequip race') end
assert(not library:Activate(candidate), 'tool activation errors are reported')
print('PASS Weapons: no-op backpack/disabled tools, real held tool, explicit equip, failure propagation')
'''
with tempfile.TemporaryDirectory(prefix='weapons-v184-') as tmp:
    p=Path(tmp)/'test.luau';p.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
