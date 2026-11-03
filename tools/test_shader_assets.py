#!/usr/bin/env python3
"""Check shipped shader art and exercise the real lazy AssetManager with mocks.

A valid image and mocked getcustomasset do not prove Delta renders an asset.
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
    "shaderRainTexture": ("rain-trace.png", (128, 128), "490645453f55411ff5cb9a353fff3b2d433654ae7b32ceb0526b3afea9d447ad", "shader-rain-v1.png"),
    "shaderSnowTexture": ("snow-soft.png", (64, 64), "9c1eb972063c9b189a4c24ee99a9687e10622a7a02dc42b8c364bc3df0ca0f91", "shader-snow-v1.png"),
    "shaderAutumnTexture": ("autumn-maple.png", (256, 256), "7b63c0d4d7e19c1aafb555e4a5378ae41fe7c4adbdc9f94739254f651cf5016d", "shader-autumn-v1.png"),
    "shaderConcreteTexture": ("surface-concrete.jpg", (512, 256), "0b99ae767f6f3b36216961978a6894fb3c8413b237f370e4f1addf263723be91", "shader-concrete-v1.jpg"),
    "shaderWoodTexture": ("surface-wood-floor.jpg", (512, 512), "3c9d916ca4e08bb177767bfe444b5e7ba8a8a11188c9e47de0c181b71752d90e", "shader-wood-floor-v1.jpg"),
    "shaderBrickTexture": ("surface-brick.jpg", (512, 256), "2e720e5fa7a63779abd525403fd9923cd0df7d1402077e5ef71a9c22182112a6", "shader-brick-v1.jpg"),
    "shaderGrassTexture": ("surface-grass.jpg", (512, 512), "fa7ce682100c1222dbb849d90a0ad46fcd78f9b4842dadf86abc9f44aa52dee6", "shader-grass-v1.jpg"),
    "shaderMarbleTexture": ("surface-marble.jpg", (512, 512), "e31659e6d41ea8b4dba91b9f237891555701801a3f4de3419a162bc8008d9ffe", "shader-marble-v1.jpg"),
}


def jpeg_dimensions(data: bytes) -> tuple[int, int]:
    assert data[:3] == b"\xff\xd8\xff"
    offset = 2
    while offset < len(data):
        assert data[offset] == 0xFF
        while data[offset] == 0xFF:
            offset += 1
        marker = data[offset]
        offset += 1
        length = int.from_bytes(data[offset:offset + 2], "big")
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            height, width = struct.unpack(">HH", data[offset + 3:offset + 7])
            return width, height
        offset += length
    raise AssertionError("JPEG has no start-of-frame marker")


for key, (name, dimensions, digest, cache_name) in FIXTURES.items():
    data = (ASSETS / name).read_bytes()
    if name.endswith(".png"):
        assert data.startswith(b"\x89PNG\r\n\x1a\n")
        assert struct.unpack(">II", data[16:24]) == dimensions, name
        assert data[25] in (4, 6), f"{name} needs an alpha channel"
    else:
        assert jpeg_dimensions(data) == dimensions, name
    assert hashlib.sha256(data).hexdigest() == digest, f"unexpected asset bytes: {name}"
    assert f"{key} = {{" in WURST and f'Assets/Shaders/{name}' in WURST
    assert f'asset = "{key}"' in SHADERS
for name in ("LICENSE-Photoreal-MIT.txt", "LICENSE-Weather-ISC.txt",
             "LICENSE-Kenney-CC0.txt", "LICENSE-RPicster-CC0.txt", "LICENSE-ambientCG-CC0.txt",
             "LICENSE-Rain-Apache-2.0.txt", "NOTICE-Rain.txt"):
    assert (ROOT / "docs/third-party/shaders" / name).is_file(), name

block = WURST[WURST.index("local AssetManager: any = {"):
              WURST.index("function AssetManager.resolveFont(")]


def lua_bytes(value: bytes) -> str:
    return '"' + ''.join(f'\\{byte:03d}' for byte in value) + '"'


samples = "\n".join(
    f'samples["{name}"] = {lua_bytes((ASSETS / name).read_bytes()[:128])}'
    for name, _, _, _ in FIXTURES.values()
)
paths = "\n".join(f'    {key} = "Wurst/Assets/{cache}",'
                  for key, (_, _, _, cache) in FIXTURES.items())
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
PATHS_PLACEHOLDER
}
for key, path in pairs(paths) do
    local asset, err = AssetManager.resolve(key)
    assert(asset == "custom://" .. path, tostring(err))
    assert(files[path] and #files[path] >= 64, "download cached and verified")
end
assert(requests == 8, "one request for each particle or surface image")
AssetManager.resolve("shaderConcreteTexture")
assert(requests == 8, "resolved textures do not redownload")
AssetManager.resolved.shaderSnowTexture = nil
files[paths.shaderSnowTexture] = "<html>bad cache</html>"
local snow, err = AssetManager.resolve("shaderSnowTexture")
assert(snow == "custom://" .. paths.shaderSnowTexture and requests == 9, tostring(err))
AssetManager.resolved.shaderConcreteTexture = nil
files[paths.shaderConcreteTexture] = "not an image" .. string.rep("!", 100)
local concrete, jpegErr = AssetManager.resolve("shaderConcreteTexture")
assert(concrete == "custom://" .. paths.shaderConcreteTexture and requests == 10, tostring(jpegErr))
AssetManager.resolved.shaderRainTexture = nil
environment.getcustomasset = nil
local noAsset, reason = AssetManager.resolve("shaderRainTexture")
assert(noAsset == nil and reason:find("unavailable", 1, true), "missing executor API is reported")
print("PASS shader assets: real AssetManager, PNG/JPEG, cache, invalid cache and missing API (mock)")
'''.replace("PATHS_PLACEHOLDER", paths)

with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "shader_assets.luau"
    script.write_text(prelude + "\n" + samples + "\n" + block + "\n" + body)
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
print("PASS shader assets: 3 alpha PNGs, 5 colour JPEGs, dimensions, hashes, mappings and licences")
