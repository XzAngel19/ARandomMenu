#!/usr/bin/env python3
"""Execute shared selector geometry from Widgets, including screen-edge fallbacks."""
import os
import subprocess
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'src/guis/Wurst/Code/Widgets.lua').read_text()
start = source.index('    local function selectorGeometry(')
end = source.index('    local function openChoiceList(', start)
geometry = source[start:end]
script = r'''
local UDim2={fromOffset=function(x,y) return {X={Offset=x},Y={Offset=y}} end}
local function v(x,y) return {X=x,Y=y} end
local ScreenGui={AbsoluteSize=v(1568,882)}
local workspace={CurrentCamera={ViewportSize=v(1568,882)}}
local function node(x,y,w,h,parent,owner)
 return {AbsolutePosition=v(x,y),AbsoluteSize=v(w,h),Parent=parent,GetAttribute=function(_,key) return key=='SelectorOwner' and owner end}
end
''' + geometry + r'''
local function bounded(p,s)
 assert(p.X.Offset>=8 and p.Y.Offset>=8)
 assert(p.X.Offset+s.X.Offset<=ScreenGui.AbsoluteSize.X-8)
 assert(p.Y.Offset+s.Y.Offset<=ScreenGui.AbsoluteSize.Y-8)
end
local window=node(278,220,280,172,ScreenGui,true)
local row=node(282,342,272,26,window)
local anchor=node(418,346,130,22,row)
local p,s=selectorGeometry(anchor,176)
bounded(p,s);assert(p.Y.Offset==398 and s.X.Offset==160,'popup belongs below the complete settings panel')
-- Both native selectors must use this same geometry.
assert(p.X.Offset==418)
ScreenGui.AbsoluteSize=v(800,600)
window.AbsolutePosition=v(250,420);window.AbsoluteSize=v(280,170)
row.AbsolutePosition=v(254,548);anchor.AbsolutePosition=v(390,552)
p,s=selectorGeometry(anchor,176);bounded(p,s)
assert(p.X.Offset==536,'use the right side when below is out of view')
window.AbsolutePosition=v(510,420);window.AbsoluteSize=v(280,170)
row.AbsolutePosition=v(514,548);anchor.AbsolutePosition=v(650,552)
p,s=selectorGeometry(anchor,176);bounded(p,s);assert(p.X.Offset==344,'fall back to left side')
ScreenGui.AbsoluteSize=v(320,480)
window.AbsolutePosition=v(8,230);window.AbsoluteSize=v(304,242)
row.AbsolutePosition=v(12,440);anchor.AbsolutePosition=v(168,444)
p,s=selectorGeometry(anchor,176);bounded(p,s);assert(p.Y.Offset==48,'otherwise place above the panel within the viewport')
p,s=selectorGeometry(anchor,2000);bounded(p,s);assert(s.Y.Offset==464,'long lists are bounded and remain scrollable')
-- Fallback viewport during initial GUI layout.
ScreenGui.AbsoluteSize=v(0,0)
p,s=selectorGeometry(anchor,176);assert(s.Y.Offset==176 and p.Y.Offset>=8)
-- A control outside a managed window still opens below its full row.
ScreenGui.AbsoluteSize=v(800,600)
row=node(200,200,280,44,ScreenGui);anchor=node(340,202,120,22,row)
p,s=selectorGeometry(anchor,100);bounded(p,s);assert(p.Y.Offset==250)
print('PASS shared selector geometry: below whole panel/row, width, right/left/above edge fallbacks, long list, mobile and initial viewport')
'''
assert source.count('selectorGeometry(anchor, listHeight)') == 2
wurst = (ROOT/'src/Wurst.lua').read_text()
blur = wurst.split('state.setChoiceBlur = function',1)[1].split('local menuVisibilityListeners',1)[0]
assert 'MenuBlur.Size' not in blur, 'selectors must never reduce the menu blur'
assert 'single = definition2.Single == true' in (ROOT/'src/libraries/Framework.lua').read_text()
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp)/'selectors.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)], check=True)
