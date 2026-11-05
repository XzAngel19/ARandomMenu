#!/usr/bin/env python3
"""Execute the loader's real team-provider and advanced verdict code."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'src/Wurst.lua').read_text()
register = source[source.index('state.registerTeamProvider = function'):source.index('\nstate.registerRoleProvider = function')]
team = source[source.index('local TEAM_SIDE_BY_ROLE:'):source.index('\nstate.playerRole = function')]
script = r'''
local state={gameBridge={listeners={}}}
local lobbyTeam={Name='Lobby'}
local function player(name)
    local obj={Name=name,Neutral=false,Team=lobbyTeam,TeamColor='White',attributes={}}
    function obj:GetAttribute(name) return self.attributes[name] end
    function obj:FindFirstChild(name) return self.children and self.children[name] end
    return obj
end
local LocalPlayer=player('Local')
local other=player('Other')
local game={FindService=function() return {GetTeams=function() return {lobbyTeam} end} end}
''' + register + '\n' + team + r'''
local function verdict() return state.teamCheck.analyze(other) end
local function check(same, hostile, method)
    local v=verdict()
    assert(v.sameTeam==same and v.hostile==hostile and (not method or v.method==method),
        'unexpected verdict: '..tostring(v.sameTeam)..'/'..tostring(v.hostile)..'/'..tostring(v.method))
end
-- Explicit factions beat a shared Roblox lobby Team, even if Neutral.
LocalPlayer.attributes.Team='Red';other.attributes.Team='Blue'
LocalPlayer.Neutral=true;other.Neutral=true
check(false,true,'attributes')
other.attributes.Team='red';check(true,false,'attributes')
other.attributes.Team=nil;check(nil,nil,'attributes-unknown')
LocalPlayer.attributes.Team='FFA';other.attributes.Team='FFA'
check(false,true,'attributes-ffa')
LocalPlayer.attributes.Team=nil;other.attributes.Team=nil
check(false,true,'neutral')
LocalPlayer.Neutral=false;other.Neutral=false;check(true,false,'teams')
LocalPlayer.children={Team={Value='Red'}};other.children={Team={Value='Blue'}}
check(false,true,'attributes')
other.children.Team.Value='Red';check(true,false,'attributes')
other.children.Team.Value='FFA';check(nil,nil,'attributes-unknown')
LocalPlayer.children=nil;other.children=nil

-- MM2's role provider replaces Roblox lobby teams; missing/dead roles do not
-- invent either allies or enemies. Known roles remain correct.
local roles={[LocalPlayer]='Sheriff',[other]='Innocent'}
state.gameBridge.roleProvider={ReplacesTeams=true}
state.playerRole=function(p) return roles[p] end
check(true,false,'roles')
roles[other]='Murderer';check(false,true,'roles')
roles[other]='Dead';check(nil,nil,'roles-unknown')
roles[other]=nil;check(nil,nil,'roles-unknown')
state.gameBridge.roleProvider=nil

-- A Get-only provider is authoritative, handles case/whitespace, and never
-- falls back to shared Teams if only one token has arrived.
local tokens={[LocalPlayer]=' red ',[other]='BLUE'}
state.registerTeamProvider({Get=function(p) return tokens[p] end})
check(false,true,'provider')
tokens[other]='Red';check(true,false,'provider')
tokens[other]=nil;check(nil,nil,'provider-unknown')
tokens[other]='FFA';check(nil,nil,'provider-unknown')
tokens[LocalPlayer]='FFA';check(false,true,'provider-ffa')
tokens[LocalPlayer]='red'
state.registerTeamProvider({Get=function(p) return tokens[p] end, IsFriendly=function() error('late') end})
tokens[other]='Blue';check(false,true,'provider')

-- Registering an adapter with only GetRelation must work, and Unknown is
-- not converted into a confirmed hostile by the Roblox Team fallback.
local relation='Unknown'
state.registerTeamProvider({GetRelation=function() return relation end})
assert(state.gameBridge.teamProvider.GetRelation)
check(nil,nil,'provider-unknown')
assert(not state.teamCheck.isEnemy(other) and not state.teamCheck.isSameTeam(other))
relation='Enemy';check(false,true,'provider');assert(state.teamCheck.isEnemy(other))
relation='Teammate';check(true,false,'provider');assert(state.teamCheck.isSameTeam(other))
print('PASS advanced Team Check: relation-only registration, attributes/FFA, neutral, role and token providers, unknown states')
'''
with tempfile.TemporaryDirectory(prefix='teamcheck-v184-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
