#!/usr/bin/env python3
"""Real Entity + real loader verdict agree for factions, roles and unknown providers."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_entity_team_provider import PRELUDE, MODULE

ROOT = Path(__file__).resolve().parents[1]
loader = (ROOT / 'src/Wurst.lua').read_text()
team = loader[loader.index('local TEAM_SIDE_BY_ROLE:'):loader.index('\nstate.playerRole = function')]
script = PRELUDE + MODULE.read_text() + '\n]=====]\n' + r'''
local LocalPlayer=localPlayer
function game:FindService() return {GetTeams=function() return {1} end} end
''' + team + r'''
local lobby=makeInstance('Team','Lobby')
for _,p in ipairs({localPlayer,teammate,enemy}) do
    p.Team=lobby;p.Neutral=false;p.TeamColor='White'
end
localPlayer.attributes.Team='Red';teammate.attributes.Team='Red';enemy.attributes.Team='Blue'
local module,library=loadEntityLibrary()
library:Refresh(true)
local function selection()
    local found={}
    for _,e in ipairs(library:InRange({Range=100,IgnoreWalls=true,IgnoreFriends=true})) do
        found[e.Player.Name]=true
    end
    return found
end
local found=selection()
assert(not found.Teammate and found.Enemy, 'faction enemy in shared Lobby Team must survive')
assert(library:IsFriendly(teammate) and not library:IsFriendly(enemy))
local roles={[localPlayer]='Sheriff',[teammate]='Innocent',[enemy]='Murderer'}
localPlayer.attributes.Team=nil;teammate.attributes.Team=nil;enemy.attributes.Team=nil
state.gameBridge.roleProvider={ReplacesTeams=true};state.playerRole=function(p) return roles[p] end
library:Refresh(true);found=selection()
assert(not found.Teammate and found.Enemy, 'role provider overrides shared Lobby Team in Entity')
roles[enemy]=nil;library:Refresh(true);found=selection()
assert(not found.Enemy and not library:IsFriendly(enemy), 'unknown role is not a confirmed enemy or ally')
assert(library:IsEnemy(enemy)==false)
state.gameBridge.roleProvider=nil
-- A StringValue Team can be the only explicit side signal in a game.
for _,p in ipairs({localPlayer,teammate,enemy}) do p.Team=nil;p.Neutral=true end
localPlayer.children.Team={Value='Red'};teammate.children.Team={Value='Red'};enemy.children.Team={Value='Blue'}
library:Refresh(true);found=selection()
assert(not found.Teammate and found.Enemy, 'Team child data overrides Neutral and is consistent in Entity')
localPlayer.children.Team=nil;teammate.children.Team=nil;enemy.children.Team=nil
local relation='Unknown'
state.gameBridge.teamProvider={GetRelation=function(p) if p==teammate then return 'Teammate' end return relation end}
library:Refresh(true);found=selection();assert(not found.Enemy)
relation='Enemy';library:Refresh(true);found=selection();assert(found.Enemy)
module.destroy()
print('PASS Entity integration: consistent factions and MM2 role verdicts, unknown fail-closed, relation update')
'''
with tempfile.TemporaryDirectory(prefix='team-entity-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
