--!strict
--
-- Headless tests: silence by default, teleport-boot survival when
-- LocalPlayer arrives late, and the queued reinject snippet.
--
-- The 422 from the field was boot indexing Players.LocalPlayer while
-- it was still nil. The silence contract is getgenv().ARANDOMMENU_DEBUG.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")

    local function captureConsole(world: any, sink: {any}): ()
        -- Inject copies these into the chunk env — and on this CLI,
        -- that env is the runner's. Forward so check()/section() still
        -- write to stdout after the boot. `warn` is not a default
        -- global in every module env; never call a nil forwarder.
        local realPrint: any = print
        local realWarn: any = warn
        world.globals.print = function(...: any): ()
            table.insert(sink, {kind = "print", n = select("#", ...), select(1, ...)})
            if type(realPrint) == "function" then
                realPrint(...)
            end
        end
        world.globals.warn = function(...: any): ()
            table.insert(sink, {kind = "warn", n = select("#", ...), select(1, ...)})
            if type(realWarn) == "function" then
                realWarn(...)
            elseif type(realPrint) == "function" then
                realPrint("[warn]", ...)
            end
        end
    end

    local function countKind(sink: {any}, kind: string): number
        local total: number = 0
        for _, entry: any in ipairs(sink) do
            if entry.kind == kind then
                total += 1
            end
        end
        return total
    end

    section("Silence")

    local muteLog: {any} = {}
    ctx.prepareWorld = function(world: any): ()
        world.deferLocalPlayer(3)
        world.genv.ARANDOMMENU_DEBUG = nil
        world.queuedTeleport = nil
        world.globals.queue_on_teleport = function(source: string): ()
            world.queuedTeleport = source
        end
        captureConsole(world, muteLog)
    end

    local muteBoot: any = bootShell(ctx)
    ctx.prepareWorld = nil
    -- Snapshot before check() prints, which ride the same wrapper.
    local mutePrints: number = countKind(muteLog, "print")
    local muteWarns: number = countKind(muteLog, "warn")
    check("mute boot survives a late LocalPlayer", muteBoot.ok == true, muteBoot.error)
    if not muteBoot.ok then
        return
    end
    check("mute boot prints nothing", mutePrints == 0, tostring(mutePrints))
    check("mute boot warns nothing", muteWarns == 0, tostring(muteWarns))
    check(
        "LocalPlayer is published after the wait",
        muteBoot.world.players.LocalPlayer ~= nil
    )
    check(
        "the deferred player is the same instance",
        muteBoot.world.players.LocalPlayer == muteBoot.world.localPlayer
    )

    section("TeleportSnippet")

    local snippet: any = muteBoot.world.queuedTeleport
    check("a teleport snippet was queued", type(snippet) == "string", type(snippet))
    if type(snippet) == "string" then
        check(
            "snippet waits for game.Loaded",
            string.find(snippet, "game.Loaded:Wait()", 1, true) ~= nil
        )
        check(
            "snippet checks game:IsLoaded first",
            string.find(snippet, "game:IsLoaded()", 1, true) ~= nil
        )
        check(
            "snippet honours ARANDOMMENU_STOPPED",
            string.find(snippet, "ARANDOMMENU_STOPPED", 1, true) ~= nil
        )
        local compiled: any, compileError: any = loadstring(snippet, "@teleport-snippet")
        check(
            "snippet compiles",
            type(compiled) == "function",
            tostring(compileError)
        )
    end

    if type(muteBoot.state.destruct) == "function" then
        pcall(muteBoot.state.destruct)
    end

    section("DebugLogs")

    local debugLog: {any} = {}
    ctx.prepareWorld = function(world: any): ()
        world.genv.ARANDOMMENU_DEBUG = true
        -- A leftover queue_on_teleport from the mute inject would
        -- otherwise re-arm on this boot; this world does not need one.
        world.globals.queue_on_teleport = nil
        captureConsole(world, debugLog)
    end
    local debugBoot: any = bootShell(ctx)
    ctx.prepareWorld = nil
    local debugPrints: number = countKind(debugLog, "print")
    check("debug boot runs", debugBoot.ok == true, debugBoot.error)
    if debugBoot.ok then
        check(
            "debug flag restores console output",
            debugPrints >= 1,
            tostring(debugPrints)
        )
        if type(debugBoot.state.destruct) == "function" then
            pcall(debugBoot.state.destruct)
        end
    end
end
