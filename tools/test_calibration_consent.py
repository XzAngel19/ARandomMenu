#!/usr/bin/env python3
"""Boot the real MM2 recorder with pre-existing telemetry and mocked IO.

Checks only executor filesystem calls, not Roblox behavior or prediction quality.
"""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source=audit_menu.build(debug=True).read_text(encoding='utf-8')
setup=r'''
local TELEMETRY='Wurst/Telemetry/MM2_Trajectory_Calibration.json'
local FILES={[TELEMETRY]='existing-history'}
local WRITES={}
-- The boot harness runs task.delay synchronously. Keep 3-second callbacks
-- queued so Calibration's prompt runs after Module.Initialized, like Roblox.
local DEFERRED_3={}
local originalDelay=task.delay
task.delay=function(delay,fn,...)
 if delay==3 then table.insert(DEFERRED_3,fn);return end
 return originalDelay(delay,fn,...)
end
function isfolder(_) return true end
function makefolder(_) end
function isfile(path) return FILES[path]~=nil or tostring(path):find('Game_20260716',1,true)~=nil end
function readfile(path)
 if FILES[path]~=nil then return FILES[path] end
 if tostring(path):find('Game_20260716',1,true) then return HarnessSavedConfig end
 error('missing file')
end
function writefile(path,content)
 if tostring(path):find('/Telemetry/',1,true) then table.insert(WRITES,{path,content}) end
 FILES[path]=content
end
function delfile(path) FILES[path]=nil end
DateTime={now=function() return {ToIsoDate=function() return 'now' end} end}
'''
assert source.count('SOURCES = {\n')==1
source=source.replace('SOURCES = {\n',setup+'\nSOURCES = {\n',1)
probe=r'''
local c=assert(ex.state.mm2TrajectoryCalibration)
assert(c:getConsent()==nil,'initial consent must be unanswered')
assert(#WRITES==0 and FILES[TELEMETRY]=='existing-history',
 'boot must not even make a history backup before consent')
c:setConsent(nil)
assert(FILES[TELEMETRY]=='existing-history' and #WRITES==0,
 'reopening the question must neither delete nor write the previous history')
assert(c:setConsent(true)==true,'successful consent save must report success')
assert(c:getConsent()==true and #WRITES==2,'Yes must back up old bytes before saving a snapshot')
assert(WRITES[1][1]~=TELEMETRY and WRITES[1][2]=='existing-history','first write must be byte-exact backup')
assert(WRITES[2][1]==TELEMETRY and FILES[TELEMETRY]=='{}','second write is the new snapshot')
c:setConsent(nil)
assert(FILES[TELEMETRY]=='{}','Ask again must not delete an existing snapshot before an answer')
c:setConsent(false)
assert(c:getConsent()==false and FILES[TELEMETRY]==nil,'No stops saving and removes the current file when supported')
local before=#WRITES
assert(not c:save('manual') and #WRITES==before,'No must prohibit manual writes')
-- Explicitly clearing history with an executor lacking delfile must not write
-- a replacement file while the user has not consented.
getfenv().delfile=nil
c:reset();assert(#WRITES==before,'Clear history cannot write {} without consent')
print('PASS calibration consent: no boot backup/write, safe ask-again, verified backup after Yes, No and reset')
'''
conflict = r'''
local c=assert(ex.state.mm2TrajectoryCalibration)
FILES[TELEMETRY]='changed-by-another-session'
assert(c:setConsent(true)==false,'conflicted consent save must report failure')
assert(c:status():find('saving unavailable',1,true),'status must disclose blocked saving')
assert(FILES[TELEMETRY]=='changed-by-another-session' and #WRITES==0,
 'must not overwrite a file that changed after import')
assert(not c:save('manual') and #WRITES==0,'a conflict must keep later saves blocked')
print('PASS calibration conflict: changed file is preserved')
'''
backup_error = r'''
local c=assert(ex.state.mm2TrajectoryCalibration)
local originalWrite=writefile
function writefile(path,content)
 if path~=TELEMETRY and tostring(path):find('/Telemetry/',1,true) then
  error('backup denied')
 end
 return originalWrite(path,content)
end
assert(c:setConsent(true)==false,'failed backup must report failure')
assert(FILES[TELEMETRY]=='existing-history' and #WRITES==0,
 'failed backup must never overwrite the original')
assert(not c:save('manual') and #WRITES==0,'failed backup must block later saves')
print('PASS calibration backup error: original is preserved')
'''
prompt_success = r'''
for _,fn in ipairs(table.clone(DEFERRED_3)) do pcall(fn) end
local gui=assert(ex.state.frameworkEnvironment.ScreenGui)
local backdrop=assert(gui:FindFirstChild('ConfirmDialog'),'Calibration must actually ask on first boot')
local panel=assert(backdrop:FindFirstChild('Panel'))
assert(panel.Parent.Parent==gui and panel.Position.X.Scale==0.5 and panel.Position.Y.Scale==0.5,
 'the actual Calibration prompt must be centred under ScreenGui')
assert(#WRITES==0,'the prompt alone must not write telemetry')
assert(panel:FindFirstChild('Actions'):FindFirstChild('Yes')).MouseButton1Click:Fire()
assert(ex.state.mm2CalibrationFeature.status=='giving calibration' and #WRITES==2,
 'Yes must save and update the actual Calibration card')
print('PASS calibration prompt: centred real callback and successful Yes')
'''
prompt_failure = r'''
for _,fn in ipairs(table.clone(DEFERRED_3)) do pcall(fn) end
local gui=assert(ex.state.frameworkEnvironment.ScreenGui)
local backdrop=assert(gui:FindFirstChild('ConfirmDialog'))
local yes=assert(backdrop:FindFirstChild('Panel'):FindFirstChild('Actions'):FindFirstChild('Yes'))
FILES[TELEMETRY]='external-change'
yes.MouseButton1Click:Fire()
assert(ex.state.mm2CalibrationFeature.status=='saving unavailable',
 'failed Yes must not claim the file is being saved')
assert(FILES[TELEMETRY]=='external-change' and #WRITES==0,
 'the real prompt must preserve a conflicted file')
print('PASS calibration prompt: save failures reach the card')
'''
backup_corrupt = r'''
local c=assert(ex.state.mm2TrajectoryCalibration)
local originalWrite=writefile
function writefile(path,content)
 if path~=TELEMETRY and tostring(path):find('/Telemetry/',1,true) then
  table.insert(WRITES,{path,'truncated'})
  FILES[path]='truncated'
  return
 end
 return originalWrite(path,content)
end
assert(c:setConsent(true)==false,'corrupted backup must report failure')
assert(FILES[TELEMETRY]=='existing-history' and #WRITES==1,
 'a backup with different bytes must never replace the original')
assert(not c:save('manual') and #WRITES==1,'unverified backup must block later saves')
print('PASS calibration backup verification: original is preserved')
'''
with tempfile.TemporaryDirectory(prefix='calibration-consent-') as tmp:
    for name, case in [('consent',probe),('conflict',conflict),
                       ('backup-error',backup_error),('backup-corrupt',backup_corrupt),
                       ('prompt-success',prompt_success),('prompt-failure',prompt_failure)]:
        path=Path(tmp)/(name+'.luau');path.write_text(source+case,encoding='utf-8')
        result=subprocess.run([os.environ.get('LUAU','luau'),str(path)],capture_output=True,text=True)
        if result.returncode: raise SystemExit(name+' failed:\n'+result.stdout[-2000:]+'\n'+result.stderr)
        assert 'PASS calibration' in result.stdout
        print(result.stdout[result.stdout.rfind('PASS calibration'):].strip())
