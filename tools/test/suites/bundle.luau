--!strict
--
-- Headless tests: bundle.
--
-- Loaded by tools/test/run.luau. Suites share one world through the context
-- so the checks stay under Luau's 200-local ceiling without wrapping
-- sections in do-end.
--
return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Bundle")

    -- Startup is one request for the shell and one for the bundle instead of
    -- forty-five. That is a delivery change, so what has to be asserted is that
    -- delivery is lossless: every path the manifest names is in the bundle, whole.
    -- A truncated entry — one long-bracket level chosen badly — compiles into a
    -- module that fails somewhere inside itself, which is the least debuggable
    -- thing this repository could ship.
    --
    -- The byte-for-byte comparison against the working tree and the stamp check
    -- live in `tools/bundle.py --check`, which the gate runs. This is the half
    -- that can be asserted without a filesystem.
    local bundle: any = require("../../../runtime/bundle")
    local manifestFile: any = require("../../../src/core/Manifest")

    check("the bundle carries a stamp",
        type(bundle.stamp) == "string" and #bundle.stamp > 0)
    check("the bundle carries files", type(bundle.files) == "table")

    local wanted: {string} = {"src/core/Manifest.luau"}
    if type(manifestFile.widgets) == "string" then
        table.insert(wanted, manifestFile.widgets)
    end
    for _, path: string in ipairs(manifestFile.core) do
        table.insert(wanted, path)
    end
    for _, path: string in ipairs(manifestFile.libraries) do
        table.insert(wanted, path)
    end
    for _, entry: any in ipairs(manifestFile.modules) do
        table.insert(wanted, entry.path)
    end
    check("the manifest still lists everything", #wanted > 40,
        "paths: " .. tostring(#wanted))

    local missing: {string} = {}
    local truncated: {string} = {}
    for _, path: string in ipairs(wanted) do
        local packed: any = bundle.files[path]
        if type(packed) ~= "string" then
            table.insert(missing, path)
        elseif string.sub(packed, 1, 9) ~= "--!strict"
            or string.sub(packed, -1) ~= "\n" then
            table.insert(truncated, path)
        end
    end
    check("every manifest file is in the bundle", #missing == 0,
        table.concat(missing, ", "))
    check("no bundled file lost its head or its tail", #truncated == 0,
        table.concat(truncated, ", "))

    -- The per-place modules are deliberately left out: six files, four hundred
    -- kilobytes, and a client runs at most one of them.
    local packedGames: number = 0
    for path: string in pairs(bundle.files) do
        if string.find(path, "^src/games/") then
            packedGames += 1
        end
    end
    check("game modules stay out of the startup bundle", packedGames == 0,
        "found: " .. tostring(packedGames))

end
