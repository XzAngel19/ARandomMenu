#!/usr/bin/env python3
"""Execute the real bitmap text layout, including its overflow handling."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
s = (ROOT / 'src/Wurst.lua').read_text()
setup = s.split('        local truncated: boolean = false', 1)[1].split('        local function blit(', 1)[0]
start = s.index('        for segmentIndex, segment: any in ipairs(segments) do', s.index('        local function blit('))
layout = s[start:s.index('        height = glyphHeight', start)]
script = r'''
local Color3={new=function() return {} end}
local function run(text, budget, ellipsis)
    local atlas={first=32,last=126,fallbackGlyph=63}
    local scale,textSize=1,16
    local segments={{text=text}}
    local maxWidth,wantsEllipsis=budget,ellipsis
    local Theme={text={R=1,G=1,B=1}}
    local contract={}
    local function contractAdvanceFor(_,code) return code==46 and 1 or code==105 and 2 or 6 end
    function contract.eachCode(text,fn) for i=1,#text do fn(string.byte(text,i)) end end
    function contract.measure(segments)
        local w=0;for i=1,#text do w+=contractAdvanceFor(nil,string.byte(text,i)) end;return w
    end
    local x,y,width,lineCount,lineAdvance=0,0,0,1,16
    local shadow,shadowOffset,zIndex=false,1,1
    local truncated=false
    local painted={}
    local function blit(code,color,dx,dy,z) table.insert(painted,{code=code,x=dx}) end
''' + setup + layout + r'''
    return painted,width
end
local p,w=run('WWi',8,false)
assert(#p==1 and p[1].code==87 and w==6,'overflow cannot skip W then squeeze i into the line')
p,w=run('WWi',8,true)
assert(#p==3 and p[1].code==87 and p[2].code==46 and p[2].x>=6 and p[3].x>=7,'ellipsis cannot overwrite text')
p,w=run('Wi',8,true)
assert(#p==2 and p[2].code==105 and w==8,'exact fit must not be truncated')
p,w=run('WW',0,true)
assert(#p==0 and w==0,'zero-width control is safe')
print('PASS bitmap layout: contiguous truncation, reserved ellipsis, exact fit, zero-width control')
'''
with tempfile.TemporaryDirectory(prefix='bitmap-layout-') as tmp:
    path = Path(tmp) / 'layout.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
