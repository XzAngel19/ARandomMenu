#!/usr/bin/env python3
"""Run the actual token engine and bitmap recolor path; assert bounded work."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import section
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/Wurst.lua').read_text()
script=r'''
local Color3={}
local mt={__eq=function(a,b) return a.R==b.R and a.G==b.G and a.B==b.B end}
function Color3.new(r,g,b) return setmetatable({R=r,G=g,B=b},mt) end
local red,green,blue=Color3.new(1,0,0),Color3.new(0,1,0),Color3.new(0,0,1)
local Theme={accent=red,background=blue,text=green,arrows=green,enabled=red}
local THEME_PRESETS={Wurst=table.clone(Theme)}
local function signal()
 local s={list={}};function s:Connect(fn) local c={fn=fn,Connected=true};function c:Disconnect() self.Connected=false end;table.insert(self.list,c);return c end
 function s:Fire() for _,c in ipairs(self.list) do if c.Connected then c.fn() end end end
 return s
end
local writes={}
local function object(name)
 local properties={Parent=true,Destroying=signal()}
 return setmetatable({}, {__index=properties,__newindex=function(_,k,v) properties[k]=v;writes[name]=(writes[name] or 0)+1 end})
end
'''+section(SOURCE,'local ThemeEngine = {','local DEFAULT_HEADER_COLOR:')+r'''
local a,t=object('accent'),object('text')
ThemeEngine.Bind(a,'BackgroundColor3','accent');ThemeEngine.Bind(a,'BackgroundColor3','accent')
ThemeEngine.Bind(t,'TextColor3','text')
local textCalls,total=0,0
ThemeEngine.OnChange(function() textCalls+=1 end,{'text'})
ThemeEngine.OnChange(function() total+=1 end)
writes={}
local input={accent=green}
ThemeEngine.SetMany(input)
assert(writes.accent==1 and not writes.text,'only affected token bindings; repeated Bind must not duplicate')
assert(textCalls==0 and total==1 and input.accentDim==nil,'filtered listeners and immutable caller input')
writes={};ThemeEngine.SetMany({accent=Color3.new(0,1,0)})
assert(next(writes)==nil and total==1,'equal colours are no-op updates')
ThemeEngine.Bind(a,'BackgroundColor3','text');writes={}
ThemeEngine.SetMany({accent=blue});assert(not writes.accent,'rebinding removes obsolete token ownership')
ThemeEngine.SetMany({text=red});assert(writes.accent==1 and writes.text==1 and textCalls==1)
a.Destroying:Fire();writes={};ThemeEngine.SetMany({text=blue});assert(not writes.accent and writes.text==1,'destroyed bindings released')
local state={bitmapText={_live={},stats={draws=4}}}
'''+section(SOURCE,'state.bitmapText.recolor = function(', 'state.bitmapText.release = function(')+r'''
local holder={Size='unchanged',Position='sliding'}
local g1={Parent=true,ImageColor3=red};local g2={Parent=true,ImageColor3=red};local status={Parent=true,ImageColor3=green}
local record={signature='old',request={segments={{text='Speed',color=red},{text=' [ON]',color=green}}},glyphs={g1,g2,status},paintMap={{segment=1,factor=1},{segment=1,factor=.25},{segment=2,factor=1}}}
state.bitmapText._live[holder]=record
assert(state.bitmapText.recolor(holder,{blue,green}))
assert(g1.ImageColor3==blue and g2.ImageColor3.B==.25 and status.ImageColor3==green)
assert(holder.Position=='sliding' and holder.Size=='unchanged' and state.bitmapText.stats.draws==4,'no layout, glyph rebuild or tween reset')
assert(record.signature==nil and state.bitmapText.stats.recolors==1)
state.bitmapText.recolor(holder,{blue,green});assert(state.bitmapText.stats.recolors==1,'unchanged colours skip writes')
record.fallback={Visible=true,Text=''};record.request.segments[1].text='<Gun&>'
state.bitmapText.recolor(holder,{red,green});assert(record.fallback.Text:find('&lt;Gun&amp;&gt;',1,true),'fallback text remains escaped')
assert(not state.bitmapText.recolor({},{}))
print('PASS Theme: token-scoped writes, bind dedup/rebind/destroy, unchanged updates, filtered listeners; colour-only atlas/fallback without layout')
'''
with tempfile.TemporaryDirectory(prefix='theme-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
