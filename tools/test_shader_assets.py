#!/usr/bin/env python3
"""Check shipped weather art and exercise the loader's real AssetManager.

The network, filesystem and getcustomasset are mocked; this does not claim
Delta can display a custom particle texture on a particular device.
"""
import hashlib
import os
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "src/guis/Wurst/Assets/Shaders"
WURST = (ROOT / "src/Wurst.lua").read_text()
SHADERS = (ROOT / "src/games/universal/Render/Shaders.lua").read_text()
FIXTURES = {
    "shaderRainTexture": ("rain-trace.png", (128, 128),
        "490645453f55411ff5cb9a353fff3b2d433654ae7b32ceb0526b3afea9d447ad"),
    "shaderSnowTexture": ("snow-soft.png", (64, 64),
        "9c1eb972063c9b189a4c24ee99a9687e10622a7a02dc42b8c364bc3df0ca0f91"),
    "shaderAutumnTexture": ("autumn-maple.png", (256, 256),
        "7b63c0d4d7e19c1aafb555e4a5378ae41fe7c4adbdc9f94739254f651cf5016d"),
}
for key, (name, dimensions, digest) in FIXTURES.items():
    data = (ASSETS / name).read_bytes()
    assert data.startswith(b"\x89PNG\r\n\x1a\n")
    assert struct.unpack(">II", data[16:24]) == dimensions, name
    assert data[25] in (4, 6), f"{name} needs an alpha channel"
    assert hashlib.sha256(data).hexdigest() == digest, f"unexpected asset bytes: {name}"
    assert f"{key} = {{" in WURST and f'Assets/Shaders/{name}' in WURST
    assert f'asset = "{key}"' in SHADERS
for name in ("LICENSE-Photoreal-MIT.txt", "LICENSE-Weather-ISC.txt",
             "LICENSE-Kenney-CC0.txt", "LICENSE-RPicster-CC0.txt"):
    assert (ROOT / "docs/third-party/shaders" / name).is_file(), name

block = WURST[WURST.index("local AssetManager: any = {"):
              WURST.index("function AssetManager.resolveFont(")]


def lua_bytes(value: bytes) -> str:
    return '"' + ''.join(f'\\{byte:03d}' for byte in value) + '"'


samples = "\n".join(
    f'samples["{name}"] = {lua_bytes((ASSETS / name).read_bytes()[:128])}'
    for name, _, _ in FIXTURES.values()
)

prelude = r'''
local CONFIG_FOLDER = "Wurst"
local REPOSITORY_RAW_BASE = "https://example.invalid/"
local PRODUCT = {logPrefix="Wurst"}
local files, folders, samples = {}, {}, {}
local requests = 0
local environment = {}
local function getEnvironmentValue(name) return environment[name] end
environment.isfolder = function(path) return folders[path] == true end
environment.makefolder = function(path) folders[path] = true end
environment.isfile = function(path) return files[path] ~= nil end
environment.readfile = function(path) return files[path] end
environment.writefile = function(path, bytes) files[path] = bytes end
environment.getcustomasset = function(path) return "custom://" .. path end
environment.request = function(request)
    requests += 1
    local name = request.Url:match("([^/]+)$")
    return {StatusCode=200, Body=samples[name] or "404: not found"}
end
local task = {wait=function() end}
'''
body = r'''
local paths = {
    shaderRainTexture = "Wurst/Assets/shader-rain-v1.png",
    shaderSnowTexture = "Wurst/Assets/shader-snow-v1.png",
    shaderAutumnTexture = "Wurst/Assets/shader-autumn-v1.png",
}
for key, path in pairs(paths) do
    local asset, err = AssetManager.resolve(key)
    assert(asset == "custom://" .. path, tostring(err))
    assert(files[path] and #files[path] >= 64, "download cached and verified")
end
assert(requests == 3, "one request for each selected texture")
AssetManager.resolve("shaderRainTexture")
assert(requests == 3, "resolved textures do not redownload")
AssetManager.resolved.shaderSnowTexture = nil
files[paths.shaderSnowTexture] = "<html>bad cache</html>"
local snow, err = AssetManager.resolve("shaderSnowTexture")
assert(snow == "custom://" .. paths.shaderSnowTexture and requests == 4, tostring(err))
AssetManager.resolved.shaderRainTexture = nil
environment.getcustomasset = nil
local noAsset, reason = AssetManager.resolve("shaderRainTexture")
assert(noAsset == nil and reason:find("unavailable", 1, true), "missing executor API is reported")
print("PASS shader assets: actual AssetManager download, cache, invalid cache and missing API")
'''

with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "shader_assets.luau"
    script.write_text(prelude + "\n" + samples + "\n" + block + "\n" + body)
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
print("PASS shader assets: three alpha PNGs, sizes, SHA-256, mappings and licence files")
