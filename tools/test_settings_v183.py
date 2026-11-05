#!/usr/bin/env python3
"""Boot both input profiles and exercise the retained mobile Move dock action."""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
check = r'''
local gui=assert(ex.state.frameworkEnvironment.ScreenGui)
local move,report
for _,item in ipairs(gui:GetDescendants()) do
 if item.Name=='Option_Movedock' then move=item end
 if item.Name=='Option_Perfreport' then report=item end
end
assert(not report and ex.state.perfReport==nil,'Perf report is absent')
if ex.state.isMobile then
 assert(move,'mobile retains Move dock')
 local button
 for _,child in ipairs(move:GetChildren()) do
  if child.ClassName=='TextButton' and child.Text=='RUN' then button=child end
 end
 assert(button,'actual Move dock action exists')
 local moved=0;ex.state.dock.BeginMove=function() moved+=1 end
 -- Production tasks run concurrently; skip only the nested spinner in this
 -- synchronous harness so the real action can finish deterministically.
 local depth=0
 task.spawn=function(fn,...)
  if depth>0 then return end
  depth+=1;local ok,err=pcall(fn,...);depth-=1
  assert(ok,err)
 end
 button.MouseButton1Click:Fire()
 assert(moved==1,'mobile action calls its dock placement controller')
else
 assert(not move,'desktop must not show Move dock')
end
print('PASS settings '..(ex.state.isMobile and 'mobile' or 'PC'))
'''
with tempfile.TemporaryDirectory(prefix='settings-v183-') as tmp:
    for mobile in (False, True):
        boot=source
        if mobile:
            boot=boot.replace('UserInputService.props.TouchEnabled = false',
                              'UserInputService.props.TouchEnabled = true',1)
            boot=boot.replace('UserInputService.props.KeyboardEnabled = true',
                              'UserInputService.props.KeyboardEnabled = false',1)
        path=Path(tmp)/'test.luau';path.write_text(boot+check,encoding='utf-8')
        result=subprocess.run([os.environ.get('LUAU','luau'),str(path)],capture_output=True,text=True)
        if result.returncode: raise SystemExit(result.stdout[-3000:]+'\n'+result.stderr)
        assert 'PASS settings' in result.stdout
        print(result.stdout[result.stdout.rfind('PASS settings'):].strip())
