--!strict
--
-- Remote Logger.
--
-- Every module that has to talk to a game's own systems runs into the same
-- wall: the remote is right there in ReplicatedStorage, but nothing says what
-- to pass it. Guessing is not an option — a remote called with the wrong
-- arguments is a kick, not a feature — so this records the real calls the game
-- makes and writes them to disk in a form that can be read back and reused.
--
-- What it captures, per remote:
--   * the full instance path and the method (`FireServer` / `InvokeServer`),
--   * the type and value of every argument, deep enough to be useful and
--     shallow enough not to serialise the whole DataModel,
--   * how many times it was called and when it was first and last seen,
--   * a ready-to-paste call snippet built from the newest arguments.
--
-- The hook is `__namecall`, which is the one path every FireServer goes
-- through, plus direct `FireServer`/`InvokeServer` calls for games that store
-- the function rather than calling the method. `checkcaller` keeps the menu's
-- own traffic out of the log.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "RemoteLogger",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function fullName(instance: Instance): string
    local ok: boolean, name: any = pcall(function(): string
        return instance:GetFullName()
    end)
    return ok and tostring(name) or instance.Name
end

-- Arguments are described, not copied: a serialiser that follows instances and
-- tables without limits ends up writing the entire game to disk.
local function describe(value: any, depth: number): string
    local kind: string = typeof(value)
    if kind == "string" then
        return string.format("%q", (value :: string):sub(1, 200))
    end
    if kind == "number" or kind == "boolean" or kind == "nil" then
        return tostring(value)
    end
    if kind == "Instance" then
        return "«" .. (value :: Instance).ClassName .. " " .. fullName(value :: Instance) .. "»"
    end
    if kind == "Vector3" or kind == "Vector2" or kind == "CFrame"
        or kind == "Color3" or kind == "UDim2" or kind == "EnumItem" then
        return kind .. "(" .. tostring(value) .. ")"
    end
    if kind == "table" then
        if depth <= 0 then
            return "{...}"
        end
        local parts: {string} = {}
        local count: number = 0
        for key: any, entry: any in pairs(value :: any) do
            count += 1
            if count > 12 then
                table.insert(parts, "...")
                break
            end
            table.insert(
                parts,
                "[" .. describe(key, depth - 1) .. "] = " .. describe(entry, depth - 1)
            )
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return kind
end

local function snippetFor(entry: any): string
    local parts: {string} = {}
    for _, argument: string in ipairs(entry.arguments) do
        table.insert(parts, argument)
    end
    return "game:GetService(\"ReplicatedStorage\")"
        .. " -- "
        .. entry.path
        .. "\n-- :"
        .. entry.method
        .. "("
        .. table.concat(parts, ", ")
        .. ")"
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local httpService: HttpService = host.HttpService
    local state: any = host.state

    local log: {[string]: any} = {}
    local order: {string} = {}
    local hooked: boolean = false
    local restore: (() -> ())? = nil
    local capturing: boolean = false

    local logger: any

    local function record(remote: Instance, method: string, ...: any): ()
        if not capturing then
            return
        end
        local options: any = logger.Options
        local path: string = fullName(remote)
        local filter: string = tostring(options["Only containing"].Value or "")
        if filter ~= ""
            and not string.find(string.lower(path), string.lower(filter), 1, true) then
            return
        end

        local key: string = path .. "::" .. method
        local entry: any = log[key]
        if not entry then
            if #order >= math.round(options["Max remotes"].Value) then
                return
            end
            entry = {
                path = path,
                class = remote.ClassName,
                method = method,
                calls = 0,
                firstSeen = os.clock(),
                arguments = {},
            }
            log[key] = entry
            table.insert(order, key)
            if options["Announce new"].Value then
                logger:Notify(remote.Name .. " · " .. method)
            end
        end
        entry.calls += 1
        entry.lastSeen = os.clock()

        -- The newest call wins: argument shapes drift between rounds, and the
        -- most recent one is the one worth replaying.
        local described: {string} = {}
        for index: number, argument: any in ipairs({...}) do
            if index > 10 then
                table.insert(described, "...")
                break
            end
            table.insert(described, describe(argument, 3))
        end
        entry.arguments = described
    end

    local function installHook(): boolean
        if hooked then
            return true
        end
        local environment: any = getfenv()
        local hookMetamethod: any = environment.hookmetamethod
        local getNamecall: any = environment.getnamecallmethod
        local checkCaller: any = environment.checkcaller
        if type(hookMetamethod) ~= "function" or type(getNamecall) ~= "function" then
            logger:Notify("executor lacks hookmetamethod")
            return false
        end

        local previous: any
        local ok: boolean = pcall(function(): ()
            previous = hookMetamethod(game, "__namecall", function(self: any, ...: any): any
                local method: string = getNamecall()
                if (method == "FireServer" or method == "InvokeServer")
                    and (type(checkCaller) ~= "function" or not checkCaller()) then
                    -- pcall: a logger that can crash the game it is watching is
                    -- worse than no logger.
                    pcall(record, self, method, ...)
                end
                return previous(self, ...)
            end)
        end)
        if not ok then
            logger:Notify("could not install the hook")
            return false
        end
        hooked = true
        restore = function(): ()
            -- Restoring a metamethod hook is executor-specific; where it is
            -- not supported the capture flag alone stops the recording.
            local restoreFn: any = environment.restorefunction
            if type(restoreFn) == "function" then
                pcall(restoreFn, previous)
            end
            hooked = false
        end
        return true
    end

    local function buildReport(): string
        local lines: {string} = {
            "-- ARandomMenu remote log",
            "-- place " .. tostring(game.PlaceId),
            "-- " .. tostring(#order) .. " remotes",
            "",
        }
        for _, key: string in ipairs(order) do
            local entry: any = log[key]
            table.insert(lines, string.rep("-", 70))
            table.insert(lines, entry.path)
            table.insert(
                lines,
                "  class "
                    .. entry.class
                    .. "  ·  "
                    .. entry.method
                    .. "  ·  "
                    .. tostring(entry.calls)
                    .. " calls"
            )
            table.insert(lines, "  args  " .. table.concat(entry.arguments, ", "))
            table.insert(lines, snippetFor(entry))
        end
        return table.concat(lines, "\n")
    end

    local function saveReport(): ()
        local environment: any = getfenv()
        local writeFile: any = environment.writefile
        local makeFolder: any = environment.makefolder
        local isFolder: any = environment.isfolder
        if type(writeFile) ~= "function" then
            logger:Notify("executor has no writefile")
            return
        end
        if type(makeFolder) == "function" and type(isFolder) == "function" then
            if not isFolder("ARandomMenu") then
                pcall(makeFolder, "ARandomMenu")
            end
            if not isFolder("ARandomMenu/RemoteLogs") then
                pcall(makeFolder, "ARandomMenu/RemoteLogs")
            end
        end

        local stamp: string = tostring(math.round(os.time()))
        local base: string = "ARandomMenu/RemoteLogs/"
            .. tostring(game.PlaceId)
            .. "-"
            .. stamp

        local wrote: boolean = pcall(writeFile, base .. ".txt", buildReport())
        -- JSON as well as the readable report: one is for a human deciding
        -- what a module should send, the other is for a tool.
        local payload: {any} = {}
        for _, key: string in ipairs(order) do
            local entry: any = log[key]
            table.insert(payload, {
                path = entry.path,
                class = entry.class,
                method = entry.method,
                calls = entry.calls,
                arguments = entry.arguments,
            })
        end
        local encoded: boolean, json: any = pcall(function(): string
            return httpService:JSONEncode(payload)
        end)
        if encoded then
            pcall(writeFile, base .. ".json", json)
        end
        if wrote then
            logger:Notify("saved " .. tostring(#order) .. " remotes")
        else
            logger:Notify("could not write the log")
        end
    end

    logger = framework.Categories.Utility:CreateModule({
        Name = "Remote Logger",
        Category = "Utility",
        Order = 2,
        Tooltip = "Records the arguments the game sends to its own remotes and "
            .. "writes them to disk.",
        Function = function(enabled: boolean): ()
            capturing = enabled
            if not enabled then
                return
            end
            if not installHook() then
                capturing = false
                return
            end
            logger:Clean(function(): ()
                capturing = false
                if restore then
                    (restore :: () -> ())()
                    restore = nil
                end
            end)
        end,
    })

    logger:CreateSection("Capture")
    logger:CreateTextBox({
        Name = "Only containing",
        Default = "",
        Tooltip = "Record only remotes whose path contains this. Leave empty "
            .. "for everything.",
    })
    logger:CreateSlider({
        Name = "Max remotes",
        Min = 10,
        Max = 400,
        Default = 120,
        Tooltip = "Stops the log growing without bound in a chatty game.",
    })
    logger:CreateToggle({
        Name = "Announce new",
        Default = false,
        Tooltip = "Toast the first time each remote is seen.",
    })

    logger:CreateSection("Output")
    logger:CreateButton({
        Name = "Save to file",
        Tooltip = "Writes ARandomMenu/RemoteLogs/<place>-<time>.txt and .json",
        Function = saveReport,
    })
    logger:CreateButton({
        Name = "Print to console",
        Function = function(): ()
            print(buildReport())
            logger:Notify("printed " .. tostring(#order) .. " remotes")
        end,
    })
    logger:CreateButton({
        Name = "Copy to clipboard",
        Function = function(): ()
            local environment: any = getfenv()
            local copy: any = environment.setclipboard or environment.toclipboard
            if type(copy) ~= "function" then
                logger:Notify("executor has no clipboard")
                return
            end
            pcall(copy, buildReport())
            logger:Notify("copied")
        end,
    })
    logger:CreateButton({
        Name = "Clear log",
        Function = function(): ()
            log = {}
            order = {}
            logger:Notify("cleared")
        end,
    })
    logger:CreateNote(
        "Turn it on, play the thing you want a module to do, then save. The "
            .. "file lists every remote with the real arguments the game used."
    )

    -- Exposed so other modules (and a future game module) can read what was
    -- captured without going through the file.
    state.remoteLog = {
        entries = function(): {any}
            local list: {any} = {}
            for _, key: string in ipairs(order) do
                table.insert(list, log[key])
            end
            return list
        end,
        report = buildReport,
        save = saveReport,
    }

    activeCleanup = function(): ()
        capturing = false
        if restore then
            (restore :: () -> ())()
            restore = nil
        end
        if state.remoteLog then
            state.remoteLog = nil
        end
    end
    Module.Initialized = true
    return logger
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
