tools.equipped=gunTool;gunTool.Parent=character
installGunFeatures(screenGui);AngelHub.setters['Gun Aimbot'](true);drain();heartbeat:Fire(.1)
local t=AngelHub._testPrediction
local start=CFrame.new(Vector3.new(2,1,0));local finish=CFrame.new(Vector3.new(21,0,0))
local info={endpoint=Vector3.new(20,0,0),velocity=Vector3.new(10,0,0)}
t.queue(gunTool,start,finish,other,info,'Bullet')
fakeNow+=.1;t.observe(gunTool,CFrame.new(Vector3.new(100,0,0)),finish)
assert(t.prediction.getLeadSamples('Bullet')==0)
targetRoot.Position=Vector3.new(21,0,0);t.observe(gunTool,start,finish)
assert(t.prediction.getLeadSamples('Bullet')==1 and t.prediction.getLeadSamples('CFrame')==0)
-- Distinct matched feedback trains independently and refuses a duplicated echo.
t.observe(gunTool,start,finish);assert(t.prediction.getLeadSamples('Bullet')==1)
for i=1,6 do fakeNow+=1;t.queue(gunTool,start,finish,other,info,'Bullet');fakeNow+=.1;t.observe(gunTool,start,finish) end
assert(t.prediction.getLeadSamples('Bullet')==7 and t.prediction.getLeadCorrection('Bullet')>0)
local learned=t.prediction.exportLeadState();assert(learned.Bullet.samples==7)
t.prediction.seedLeadError('CFrame',.04,6);assert(t.prediction.getLeadCorrection('CFrame')>0)
-- Overlapping shots are ambiguous and cannot pollute feedback.
fakeNow+=1;t.queue(gunTool,start,finish,other,info,'Bullet');t.queue(gunTool,start,finish,other,info,'Bullet');fakeNow+=.1;t.observe(gunTool,start,finish)
assert(t.prediction.getLeadSamples('Bullet')==7)
AngelHub.setters['Gun Aimbot'](false);screenGui.Destroying:Fire()
