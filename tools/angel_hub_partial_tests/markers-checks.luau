game.PlaceId=142823291;Enum.KeyCode.Escape='escape';Enum.UserInputType.MouseButton1='mouse1'
local lists={};AngelHub.listOptions={}
for _,name in ipairs({'Marker Point','Teleport Point'})do
 AngelHub.setters[name]=function(value)if table.find(lists[name] or {},value)then V[name]=value end end
 AngelHub.listOptions[name]=function(items)
  lists[name]=table.clone(items)
  if not table.find(items,V[name])then V[name]=items[1]end
 end
end
AngelHub.mainWindow={Visible=true}
V['Marker Name']='Home';V['Marker Distance']=true;V['Marker Colour']='white'
V['Teleport Movement']='Instant';V['Teleport Destination']='Waypoint';V['Teleport Height Offset']=3
root.AssemblyAngularVelocity=Vector3.new(0,0,0)
local frameMeta={};frameMeta.__add=function(cf,delta)return setmetatable({Position=cf.Position+delta},frameMeta)end
root.CFrame=setmetatable({Position=root.Position},frameMeta)
function character:PivotTo(cf)self.lastPivot=cf;root.Position=cf.Position;root.CFrame=setmetatable({Position=cf.Position},frameMeta)end
installGameplay(screenGui)
AngelHub.actions['Save Here']();assert(V['Marker Points by Place']['142823291'].Home[1]==0)
assert(V['Marker Point']=='Home' and V['Teleport Point']=='Home')
heartbeat:Fire(.3);local label=created[#created];local gui=created[#created-1];local part=created[#created-2]
assert(part.Name=='AngelHubMarker' and not part.CanCollide and gui.Adornee==part and label.Text=='Home [0]')
V['Marker Name']='Peak';V['Manual Coordinates']=true;V['Coordinates']='12, 20, -4';AngelHub.actions['Save Coordinates']()
assert(#lists['Marker Point']==2 and V['Teleport Point']=='Peak')
AngelHub.actions['Teleport To Point']();assert(root.Position.X==12 and root.Position.Y==20 and root.Position.Z==-4)
V['Teleport Destination']='Last Position';AngelHub.actions['Teleport To Point']();assert(root.Position.X==0 and root.Position.Y==0)
V['Teleport Destination']='Waypoint';V['Teleport Movement']='Glide';AngelHub.actions['Teleport To Point']();assert(root.Position.X==0)
V['Teleport Movement']='Instant';AngelHub.setters['Marker Point']('Home');AngelHub.actions['Delete Marker']()
assert(V['Marker Points by Place']['142823291'].Home==nil and part.destroyed and #lists['Teleport Point']==1)
V['Coordinates']='nan, 5, 2';V['Marker Name']='Bad';AngelHub.actions['Save Coordinates']();assert(not V['Marker Points by Place']['142823291'].Bad)
-- Stored markers are validated and are scoped to the place.
AngelHub.setters['Marker Points by Place']({['142823291']={Safe={1,2,3},Invalid={math.huge,0,0}},['999']={Other={4,5,6}},bad={X={0,0,0}}})
assert(#lists['Marker Point']==1 and lists['Marker Point'][1]=='Safe' and not V['Marker Points by Place'].bad)
-- Point picking hides/restores the menu and saves a surface point.
camera.ScreenPointToRay=function()return {Origin=Vector3.new(0,0,0),Direction=Vector3.new(1,0,0)}end
function workspace:Raycast()return {Position=Vector3.new(25,5,0)}end
V['Marker Name']='Surface';AngelHub.actions['Touch']();assert(not AngelHub.mainWindow.Visible)
userInputService.InputBegan:Fire({UserInputType='mouse1',Position={X=30,Y=40}},false)
assert(AngelHub.mainWindow.Visible and V['Marker Points by Place']['142823291'].Surface[4]=='surface')
AngelHub.actions['Touch']();userInputService.InputBegan:Fire({UserInputType='mouse1',Position={X=30,Y=40}},false)
assert(V['Marker Points by Place']['142823291']['Surface #1'] and V['Marker Points by Place']['142823291'].Surface)
V['Teleport Destination']='Waypoint';AngelHub.actions['Teleport To Point']();assert(root.Position.X==25 and root.Position.Y==8)
V['Teleport Destination']='Tap Point';V['Teleport Arm Window']=1;AngelHub.actions['Teleport To Point']();assert(not AngelHub.mainWindow.Visible)
fakeNow+=2;heartbeat:Fire(.3);assert(AngelHub.mainWindow.Visible)
AngelHub.actions['Touch']();userInputService.InputBegan:Fire({KeyCode='escape',UserInputType='keyboard'},false);assert(AngelHub.mainWindow.Visible)
heartbeat:Fire(.3);screenGui.Destroying:Fire()
for _,object in ipairs(created)do if object.Name=='AngelHubMarker' or object.Name=='AngelHubMarkerLabel'then assert(object.destroyed)end end
