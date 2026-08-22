--!strict
--
-- Headless tests: executor filesystem mock, boot-time cache sweeps,
-- toast placement on the unscaled shell, the 16 px type contract, and
-- the Code-face guard that retired Minecraft (Monocraft).

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("MockFilesystem")

    local fsWorld: any = Mock.install()
    local fs: any = fsWorld.globals
    check("writefile is published", type(fs.writefile) == "function")
    check("readfile is published", type(fs.readfile) == "function")
    check("isfile is published", type(fs.isfile) == "function")
    check("listfiles is published", type(fs.listfiles) == "function")
    check("delfile is published", type(fs.delfile) == "function")

    fs.makefolder("ARandomMenu")
    fs.makefolder("ARandomMenu/src")
    fs.writefile("ARandomMenu/.stamp", "stamp")
    fs.writefile("ARandomMenu/src/keep.luau", "live")
    fs.writefile("ARandomMenu/src/gone.luau", "stale")
    check("isfile sees a written key", fs.isfile("ARandomMenu/.stamp") == true)
    check("isfile misses an unknown key", fs.isfile("ARandomMenu/missing") == false)
    check("readfile returns the stored string", fs.readfile("ARandomMenu/src/keep.luau") == "live")
    local listed: {string} = fs.listfiles("ARandomMenu")
    local listedSrc: {string} = fs.listfiles("ARandomMenu/src")
    local hasStamp: boolean = false
    local hasSrc: boolean = false
    for _, path: string in ipairs(listed) do
        if path == "ARandomMenu/.stamp" then
            hasStamp = true
        end
        if path == "ARandomMenu/src" then
            hasSrc = true
        end
    end
    check("listfiles of a folder returns the stamp", hasStamp == true)
    check("listfiles of a folder returns the child folder, not its files", hasSrc == true)
    check("listfiles is one level (src lists the files)", #listedSrc == 2, tostring(#listedSrc))
    fs.delfile("ARandomMenu/src/gone.luau")
    check("delfile removes the key", fs.isfile("ARandomMenu/src/gone.luau") == false)
    check("delfile leaves the other keys", fs.readfile("ARandomMenu/src/keep.luau") == "live")
    local missingRead: boolean, _missingErr: any = pcall(function(): ()
        fs.readfile("ARandomMenu/src/gone.luau")
    end)
    check("readfile errors on a missing key", missingRead == false)

    section("CacheSweep")

    local staleSource: string = "ARandomMenu/src/modules/RemovedHack.luau"
    local liveSource: string = "ARandomMenu/src/library/Widgets.luau"
    local stampPath: string = "ARandomMenu/.stamp"
    local staleAsset: string = "RandomTestingMenu0001/Assets/candy-fruits-v1.otf"
    local liveAsset: string = "RandomTestingMenu0001/Assets/wurst-logo-v1.png"

    local function seedFolders(world: any, path: string): ()
        world.folders = world.folders or {}
        world.folders[path] = true
        local cursor: string = ""
        for segment: string in string.gmatch(path, "([^/]+)") do
            if cursor == "" then
                cursor = segment
            else
                cursor = cursor .. "/" .. segment
            end
            world.folders[cursor] = true
        end
    end

    ctx.prepareWorld = function(world: any): ()
        seedFolders(world, "ARandomMenu/src/library")
        seedFolders(world, "ARandomMenu/src/modules")
        seedFolders(world, "RandomTestingMenu0001/Assets")
        seedFolders(world, "RandomTestingMenu0001/Profiles")
        world.files[stampPath] = "pre-boot-stamp"
        world.files[liveSource] = "-- live widgets"
        world.files[staleSource] = "-- stale module"
        world.files[liveAsset] = string.rep("A", 80)
        world.files[staleAsset] = string.rep("B", 80)
        world.files["RandomTestingMenu0001/Profiles/Game_0.Config"] = "monocraft-config"
        world.services.HttpService.JSONDecode = function(_self: any, text: any): any
            if tostring(text) == "monocraft-config" then
                return {
                    values = {interfaceFont = "Minecraft (Monocraft)"},
                    states = {},
                    ui = {},
                }
            end
            return {}
        end
    end

    local boot: any = bootShell(ctx)
    ctx.prepareWorld = nil
    check("cache-sweep boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local world: any = boot.world
    local state: any = boot.state
    local env: any = boot.env
    check("sweepStaleSources is published", type(state.sweepStaleSources) == "function")
    check("sweepStaleAssets is published", type(state.sweepStaleAssets) == "function")
    check("the accepted bundle is in hand", type(state.boot) == "table" and type(state.boot.bundle) == "table")
    check("stale source was deleted", world.files[staleSource] == nil)
    check("live source was kept", type(world.files[liveSource]) == "string")
    check(".stamp was kept", type(world.files[stampPath]) == "string")
    check("stale asset was deleted", world.files[staleAsset] == nil)
    check("live asset was kept", type(world.files[liveAsset]) == "string")

    world.files["ARandomMenu/offline-lifeline.luau"] = "keep"
    seedFolders(world, "ARandomMenu")
    local savedBundle: any = state.boot.bundle
    state.boot.bundle = nil
    local offlineRemoved: number = state.sweepStaleSources()
    check(
        "sweep is a no-op when the bundle was not accepted",
        offlineRemoved == 0 and world.files["ARandomMenu/offline-lifeline.luau"] == "keep",
        tostring(offlineRemoved)
    )
    state.boot.bundle = savedBundle

    section("ToastPlacement")

    local screen: any = env.ScreenGui
    local toast: any = screen and screen:FindFirstChild("ToastContainer")
    check("ToastContainer is a direct child of the shell", toast ~= nil and toast.Parent == screen)
    if toast ~= nil then
        check(
            "ToastContainer is not on PopupLayer",
            toast.Parent ~= nil and toast.Parent.Name ~= "PopupLayer"
        )
        local anchor: any = toast.AnchorPoint
        check(
            "ToastContainer AnchorPoint is (1,1)",
            type(anchor) == "table" and anchor.X == 1 and anchor.Y == 1,
            anchor and (tostring(anchor.X) .. "," .. tostring(anchor.Y)) or "nil"
        )
        local pos: any = toast.Position
        check(
            "ToastContainer sits at the physical bottom-right",
            type(pos) == "table"
                and pos.X ~= nil
                and pos.X.Scale == 1
                and pos.X.Offset == -12
                and pos.Y ~= nil
                and pos.Y.Scale == 1
                and pos.Y.Offset == -12
        )
    end

    section("TypeContract")

    check(
        "layout.titleFontSize is the 16 px contract",
        state.layout ~= nil and state.layout.titleFontSize == 16,
        state.layout and tostring(state.layout.titleFontSize) or "nil"
    )
    check(
        "layout.bodyFontSize is the 16 px contract",
        state.layout ~= nil and state.layout.bodyFontSize == 16,
        state.layout and tostring(state.layout.bodyFontSize) or "nil"
    )

    local sample: any = Inspect.featureNamed(env, "Killaura")
        or Inspect.featureNamed(env, "Flight")
        or (env.allFeatures and env.allFeatures[1])
    local title: any = sample and sample.row and sample.row:FindFirstChild("Title")
    local fallback: any = title and title:FindFirstChild("Fallback")
    if fallback ~= nil then
        check(
            "a drawn card title Fallback renders at 16",
            tonumber(fallback.TextSize) == 16,
            tostring(fallback.TextSize)
        )
    elseif sample ~= nil and sample.title ~= nil then
        check(
            "a native card title sits on the 16 px contract",
            tonumber(sample.title.TextSize) == 16
                or tonumber(sample.title.TextSize) == state.layout.titleFontSize,
            tostring(sample.title.TextSize)
        )
    else
        check("a card title exists to measure", sample ~= nil and sample.row ~= nil)
    end

    local fontPackLabel: string? = nil
    if screen ~= nil and type(screen.GetDescendants) == "function" then
        for _, node: any in ipairs(screen:GetDescendants()) do
            local text: string = tostring(node.Text or "")
            if text == "Font pack" or text == "Font Pack" then
                fontPackLabel = node.Name
            end
        end
    end
    check("no Font pack text object exists after boot", fontPackLabel == nil, fontPackLabel)

    section("ConfigFontGuard")

    check("state.fontPack is Code", state.fontPack == "Code", tostring(state.fontPack))
    local storedFont: any = env.configData and env.configData.values and env.configData.values.interfaceFont
    check(
        "a stored Minecraft (Monocraft) config boots into Code",
        storedFont == nil or storedFont == "Code",
        tostring(storedFont)
    )
    if type(state.listInterfaceFonts) == "function" then
        local offered: {string} = state.listInterfaceFonts()
        local stillOffers: string? = nil
        for _, name: string in ipairs(offered) do
            if name == "Minecraft (Monocraft)" or name == "Candy Fruits" then
                stillOffers = name
            end
        end
        check("the picker no longer offers retired bitmap faces", stillOffers == nil, stillOffers)
    end

    if type(state.destruct) == "function" then
        pcall(state.destruct)
    end
end
