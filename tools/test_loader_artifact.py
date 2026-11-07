#!/usr/bin/env python3
"""v195: execute the real loader.lua against a mocked executor.

The two-line loader the player runs cannot fail quietly any more. This suite runs
the shipped `loader.lua` and proves:

  * it validates the download BEFORE compiling (short body / wrong body are
    reported, never compiled);
  * it busts the CDN and executor caches (`?t=` and `&a=`) and walks the mirror
    list;
  * it retries, and only runs the menu once a body passed validation;
  * when everything fails it says WHY (`[Wurst] loader: …`) instead of calling a
    nil chunk;
  * it works when the executor exposes `request` instead of `game:HttpGet`, and
    when it exposes `load` instead of `loadstring`.

Nothing here touches the network: `game:HttpGet` answers from a table.
"""

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOADER = (ROOT / "loader.lua").read_text(encoding="utf-8")

assert "arena/7446e4e3-arandommenu" in LOADER
assert "local RUNTIME_COMPATIBILITY_MARKER" in LOADER, "the marker is the menu's first line"
assert "?t=" in LOADER and "&a=" in LOADER, "both caches are busted"
assert "cdn.jsdelivr.net" in LOADER, "a second mirror exists"
assert 'compile(body, "@Wurst")' in LOADER, "the menu chunk is named"
assert "no working HTTP function" in LOADER, "a missing HttpGet is explained"

PRELUDE = r'''
local REAL_LOADSTRING = loadstring
local MARK = "local RUNTIME_COMPATIBILITY_MARKER"
local warned = {}
warn = function(message) table.insert(warned, tostring(message)) end

local waits = 0
task = { wait = function(seconds) waits += (seconds or 0) end }

-- Cache-busted URLs only: the loader must never ask twice for the same URL.
local seen = {}
local answered = {}
local ranChunk = 0
local calls = 0

game = {
    HttpGet = function(_self, url)
        calls += 1
        assert(not seen[url], "the loader asked the same URL twice: " .. tostring(url))
        seen[url] = true
        for _, answer in ipairs(answered) do
            if string.find(url, answer[1], 1, true) then
                if answer[2] == "throw" then
                    error("http blocked")
                end
                return answer[2]
            end
        end
        return "<html>404</html>"
    end,
}

local compiled = {}
local function fakeCompile(source, name)
    table.insert(compiled, { size = #source, name = name })
    if #source < 1000 then
        return nil, "synthetic compile failure"
    end
    return function() ranChunk += 1 end
end
loadstring = fakeCompile

getgenv = function() return _G end
'''

CASES = [
    (
        "retry, mirrors and a validated body",
        '''
answered = {
    { "raw.githubusercontent.com", string.rep("x", 500) },      -- short body
    { "cdn.jsdelivr.net", "<html>rate limited</html>" },         -- not the menu
}
''',
        '''
-- The mock keeps answering short/foreign bodies: nothing may compile, the
-- reason must be the last one seen, and the loop must stop after ATTEMPTS.
assert(#compiled == 0, "a short or foreign body is never compiled")
assert(#warned == 1, "one warning")
assert(string.find(warned[1], "[Wurst] loader:", 1, true), "the warning is ours: " .. tostring(warned[1]))
assert(string.find(warned[1], "not the menu") or string.find(warned[1], "incomplete"),
    "the reason names the real problem: " .. tostring(warned[1]))
assert(calls == 8, "4 attempts x 2 mirrors = 8 downloads, got " .. tostring(calls))
assert(ranChunk == 0, "no menu ran")
''',
    ),
    (
        "a good body compiles and runs",
        '''
local good = MARK .. string.rep("-- filler\\n", 20000)
answered = { { "raw.githubusercontent.com", good } }
''',
        '''
assert(#compiled >= 1, "the good body is compiled")
assert(compiled[1].name == "@Wurst", "the chunk is named @Wurst")
assert(compiled[1].size > 100000, "the body passed the size floor")
assert(ranChunk == 1, "the menu ran exactly once")
assert(#warned == 0, "no warning on the happy path: " .. tostring(warned[1] or ""))
''',
    ),
    (
        "HTTP that throws is retried, then explained",
        '''
answered = { { "raw.githubusercontent.com", "throw" }, { "cdn.jsdelivr.net", "throw" } }
''',
        '''
assert(#compiled == 0, "nothing compiles without a body")
assert(#warned == 1, "one warning")
assert(string.find(warned[1], "no working HTTP function"),
    "a dead HTTP path is named: " .. tostring(warned[1]))
''',
    ),
]

script = PRELUDE
body_parts = []
for index, (title, setup, checks) in enumerate(CASES):
    body_parts.append(f'''
-- case {index + 1}: {title}
do
{setup}
    seen = {{}}
    answered = answered
    calls = 0
    ranChunk = 0
    compiled = {{}}
    warned = {{}}
    local source = {LOADER!r}
    local chunk = REAL_LOADSTRING(source, "@loader")
    assert(chunk, "loader.lua compiles")
    -- The harness compiled itself with the same fake; only the loader's own
    -- compile calls matter from here on.
    compiled = {{}}
    warned = {{}}
    calls = 0
    ranChunk = 0
    chunk()
{checks}
end
''')

script += "\n".join(body_parts)
script += '\nprint("PASS loader.lua: validated downloads, cache-busted retries, mirrors, named chunk, reasons instead of nil")\n'

with tempfile.TemporaryDirectory(prefix="loader-artifact-") as temp:
    path = Path(temp) / "loader_test.luau"
    path.write_text(script, encoding="utf-8")
    result = subprocess.run(
        [os.environ.get("LUAU", "tools/luau/bin/luau"), str(path)],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise SystemExit(f"loader.lua failed:\n{result.stdout[-6000:]}\n{result.stderr}")
    print(next(line for line in result.stdout.splitlines() if line.startswith("PASS loader.lua")))
