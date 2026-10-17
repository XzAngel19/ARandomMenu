#!/usr/bin/env python3
"""Execute Blurt Roles with its private Instant Roles option and round lifecycle."""
import os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Fun/BlurtRoles.lua').read_text()
script=r'''
local active=false
local murderer={Name='Murderer'}
local sheriff={Name='Sheriff'}
local round,unsubscribed
local settings={instantRoleNotify=false,blurtDelay=1.5,blurtRepeat=false,blurtFake=false}
local core={mm2Settings=settings,findMurderer=function() return murderer end,findSheriff=function() return sheriff end,
 hasActiveRoundRoles=function() return active end,onRoundRoles=function(fn) round=fn;return function() unsubscribed=true end end}
local state={mm2Core=core}
local messages={}
local function notify(m) table.insert(messages,m) end
local featureConnections={}
local function disconnectFeatureConnection() end
local options={}
local count=0
local function createUniversalFeature(name,_,_,fn,config)
 assert(name=='Blurt Roles' and config.categoryName=='World');count+=1
 return {onToggle=fn}
end
local function addToggleOption(_,name,value,fn) options[name]=fn;fn(value) end
local function addNumberOption(_,_,value,_,_,fn) fn(value) end
local function addActionOption() end
local function addInformationOption() end
'''+'\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({});assert(count==1 and options['Instant Roles'])
options['Instant Roles'](true);assert(#messages==0)
active=true;round(true);assert(#messages==1 and messages[1]:find('Murderer',1,true))
round(true);assert(#messages==1,'one private notice per round, not per role refresh')
active=false;round(false);active=true;round(true);assert(#messages==2)
options['Instant Roles'](false);active=false;round(false);active=true;round(true);assert(#messages==2)
options['Instant Roles'](true);assert(#messages==3,'option can be enabled mid-round without enabling public chat')
Module.destroy();assert(unsubscribed and not settings.instantRoleNotify)
print('PASS Instant Roles: one World card, option only, private once per round, mid-round enable, OFF, unsubscribe')
'''
with tempfile.TemporaryDirectory(prefix='instant-roles-') as tmp:
 p=Path(tmp)/'test.luau';p.write_text(script)
 subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
