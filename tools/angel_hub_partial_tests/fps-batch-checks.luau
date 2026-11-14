V['Remove Textures']=false;AngelHub.setters['Remove Textures']=function(v)V['Remove Textures']=v end
local decals={}
for i=1,500 do
 local d={Name='Decal'..i,Parent=workspace,Transparency=.2}
 function d:IsA(k)return k=='Decal'end
 table.insert(decals,d);table.insert(workspace.objects,d)
end
installGameplay(screenGui);AngelHub.setters['Remove Textures'](true)
heartbeat:Fire(.1)
local changed=0;for _,d in ipairs(decals)do if d.Transparency==1 then changed+=1 end end
assert(changed>0 and changed<=200 and changed<#decals)
AngelHub.setters['Remove Textures'](false)
for _,d in ipairs(decals)do assert(d.Transparency==.2)end
heartbeat:Fire(.1);for _,d in ipairs(decals)do assert(d.Transparency==.2)end
screenGui.Destroying:Fire()
