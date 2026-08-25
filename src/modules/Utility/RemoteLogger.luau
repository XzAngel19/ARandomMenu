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
-- The hook is `__namecall`, which is the one path a `remote:FireServer(...)`
-- call goes through. A game that stored the function instead of calling the
-- method is not covered, and that gap is deliberate: the alternative is a
-- second hook on an instance method, which is a second process-wide surface
-- this card would have to own. `checkcaller` keeps the menu's own traffic out
-- of the log.

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
    local product: any = host.PRODUCT
    local remoteLogFolder: string = product.storageFolder .. "/RemoteLogs"

    local log: {[string]: any} = {}
    local order: {string} = {}
    local pathCache: any = setmetatable({}, {__mode = "k"})
    local hooked: boolean = false
    local restore: (() -> ())? = nil
    local capturing: boolean = false

    local logger: any

    local function record(remote: Instance, method: string, ...: any): ()
        if not capturing then
            return
        end
        local options: any = logger.Options
        -- Built here rather than in the hook: `GetFullName` is itself a
        -- namecall, and calling it from inside the namecall hook is how the
        -- logger used to re-enter itself.
        local path: string = pathCache[remote]
        if not path then
            path = fullName(remote)
            pathCache[remote] = path
        end
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
                samples = 0,
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

        -- Sampling, not recording every call: a movement remote fires sixty
        -- times a second and the sixtieth copy of the same shape teaches
        -- nothing. The first few calls are described, then only the count
        -- keeps rising unless resampling is on.
        if entry.samples >= 3 and not options["Resample always"].Value then
            return
        end
        entry.samples += 1
        local described: {string} = {}
        local packed: {any} = table.pack(...)
        for index: number = 1, math.min(packed.n, 10) do
            table.insert(described, describe(packed[index], 3))
        end
        if packed.n > 10 then
            table.insert(described, "...")
        end
        entry.arguments = described
    end

    -- The hook is deliberately tiny.
    --
    -- Everything expensive used to happen inside `__namecall`: building the
    -- instance path (itself a namecall, so the hook re-entered itself),
    -- formatting arguments, string.format on every call. On a shop button that
    -- fires three remotes, that is enough delay and enough re-entrancy to make
    -- the purchase fail — the logger was changing the game it was supposed to
    -- be watching.
    --
    -- Now the hook captures references into a queue and returns; a normal loop
    -- drains that queue a frame later, where taking a millisecond costs
    -- nothing. Nothing inside the hook calls a method on an Instance, nothing
    -- allocates a string, and the original is always called with the arguments
    -- it was given.
    local queue: {any} = {}
    local queued: number = 0
    local inHook: boolean = false

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
                -- Fast path first: one boolean, then straight through.
                if not capturing or inHook then
                    return previous(self, ...)
                end
                local method: string = getNamecall()
                if method ~= "FireServer" and method ~= "InvokeServer" then
                    return previous(self, ...)
                end
                if type(checkCaller) == "function" and checkCaller() then
                    return previous(self, ...)
                end
                if queued < 256 then
                    inHook = true
                    queued += 1
                    queue[queued] = {
                        remote = self,
                        method = method,
                        count = select("#", ...),
                        arguments = table.pack(...),
                        at = os.clock(),
                    }
                    inHook = false
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
            -- Handing the original metamethod back is the only thing that
            -- removes the hook. `restorefunction` takes a hooked *function*,
            -- not the closure `hookmetamethod` returned, so the version this
            -- replaced never removed anything: the hook stayed installed for
            -- the rest of the session with only the capture flag between it
            -- and every remote in the game.
            local removed: boolean = pcall(hookMetamethod, game, "__namecall", previous)
            if removed then
                hooked = false
                return
            end
            -- An executor that will not give the metamethod back keeps an inert
            -- hook — one boolean test, then straight through. `hooked` stays
            -- true so a later enable cannot stack a second one on top.
            logger:Notify("hook stays until rejoin")
        end
        return true
    end

    -- Drains what the hook captured, off the game's own call stack.
    local function drainQueue(): ()
        if queued == 0 then
            return
        end
        local pending: {any} = queue
        queue = {}
        local count: number = queued
        queued = 0
        for index: number = 1, count do
            local item: any = pending[index]
            if item then
                pcall(function(): ()
                    record(
                        item.remote,
                        item.method,
                        table.unpack(item.arguments, 1, item.count)
                    )
                end)
            end
        end
        logger:SetStatus(tostring(#order))
    end

    local function buildReport(): string
        local lines: {string} = {
            "-- " .. tostring(product.name) .. " remote log",
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
            if not isFolder(product.storageFolder) then
                pcall(makeFolder, product.storageFolder)
            end
            if not isFolder(remoteLogFolder) then
                pcall(makeFolder, remoteLogFolder)
            end
        end

        local stamp: string = tostring(math.round(os.time()))
        local base: string = remoteLogFolder
            .. "/"
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
        Category = "Other",
        Order = 2,
        Tooltip = "Records the arguments the game sends to its own remotes and "
            .. "writes them to disk.",
        Function = function(enabled: boolean): ()
            capturing = enabled
            if not enabled then
                logger:SetStatus(nil)
                return
            end
            logger:SetStatus(tostring(#order))
            if not installHook() then
                capturing = false
                return
            end
            logger:Loop(drainQueue)
            logger:Clean(function(): ()
                capturing = false
                queue = {}
                queued = 0
                if restore then
                    (restore :: () -> ())()
                    restore = nil
                end
            end)
        end,
    })

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
    logger:CreateToggle({
        Name = "Resample always",
        Default = false,
        Tooltip = "Describe the arguments of every call instead of the first "
            .. "few. Useful for a remote whose shape changes; heavier.",
    })

    logger:CreateButton({
        Name = "Save to file",
        Tooltip = "Writes " .. remoteLogFolder .. "/<place>-<time>.txt and .json",
        Function = saveReport,
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
            if logger.Enabled then
                logger:SetStatus("0")
            end
            logger:Notify("cleared")
        end,
    })
    logger:CreateNote(
        "Turn it on, do the thing you want a module to do — buy, mine, place, "
            .. "hit — then save. The log records what only a live game can "
            .. "tell you: the arguments, in order, as the game really sent "
            .. "them. It watches; it never blocks, delays or alters a call."
    )

    -- Test and diagnostics access stays on this module, not on shell state.
    Module.entries = function(): {any}
        local list: {any} = {}
        for _, key: string in ipairs(order) do
            table.insert(list, log[key])
        end
        return list
    end
    Module.report = buildReport


    activeCleanup = function(): ()
        capturing = false
        if restore then
            (restore :: () -> ())()
            restore = nil
        end
        Module.entries = nil
        Module.report = nil
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
