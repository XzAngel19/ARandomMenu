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
    local httpService: HttpService = host.HttpService
    local product: any = host.PRODUCT
    local remoteLogFolder: string = product.storageFolder .. "/RemoteLogs"

    local notify: any = host.notify
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addTextOption: any = host.addTextOption
    local addActionOption: any = host.addActionOption
    local addInformationOption: any = host.addInformationOption
    local TaskManager: any = host.TaskManager

    local settings = {
        filter = "",
        maxRemotes = 120,
        announceNew = false,
        resampleAlways = false,
    }

    local log: {[string]: any} = {}
    local order: {string} = {}
    local pathCache: any = setmetatable({}, {__mode = "k"})
    local hooked: boolean = false
    local restore: (() -> ())? = nil
    local capturing: boolean = false
    local drainConnection: any = nil

    local function record(remote: Instance, method: string, ...: any): ()
        if not capturing then
            return
        end

        local path: string = pathCache[remote]
        if not path then
            path = fullName(remote)
            pathCache[remote] = path
        end
        if settings.filter ~= ""
            and not string.find(string.lower(path), string.lower(settings.filter), 1, true) then
            return
        end

        local key: string = path .. "::" .. method
        local entry: any = log[key]
        if not entry then
            if #order >= settings.maxRemotes then
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
            if settings.announceNew then
                notify(remote.Name .. " · " .. method)
            end
        end
        entry.calls += 1
        entry.lastSeen = os.clock()

        if entry.samples >= 3 and not settings.resampleAlways then
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
            notify("Remote Logger: executor lacks hookmetamethod")
            return false
        end

        local previous: any
        local ok: boolean = pcall(function(): ()
            previous = hookMetamethod(game, "__namecall", function(self: any, ...: any): any

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
            notify("Remote Logger: could not install the hook")
            return false
        end
        hooked = true
        restore = function(): ()

            local removed: boolean = pcall(hookMetamethod, game, "__namecall", previous)
            if removed then
                hooked = false
                return
            end

            notify("Remote Logger: hook stays until rejoin")
        end
        return true
    end

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
            notify("Remote Logger: executor has no writefile")
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
            notify("Remote Logger: saved " .. tostring(#order) .. " remotes")
        else
            notify("Remote Logger: could not write the log")
        end
    end

    local function stopCapturing(): ()
        capturing = false
        if drainConnection then
            pcall(function(): ()
                drainConnection:Disconnect()
            end)
            drainConnection = nil
        end
    end

    local LearningFeature: any = state.learningFeature
    if not LearningFeature then
        LearningFeature = createUniversalFeature(
            "Learning",
            "Evidence collection in one card: remote logging and screen samples.",
            2,
            function(_enabled: boolean): () end,
            {category = true, categoryName = "Other"}
        )
        state.learningFeature = LearningFeature
    end
    local finishPanel = state.beginCardPanel(LearningFeature, "Remote logger")

    addToggleOption(
        LearningFeature,
        "Remote logger",
        false,
        function(enabled: boolean): ()
            capturing = enabled
            if not enabled then
                stopCapturing()
                return
            end
            if not installHook() then
                capturing = false
                return
            end
            drainConnection = TaskManager:Connect(function(): ()
                drainQueue()
            end)
        end,
        "Records the arguments the game sends to its own remotes. It watches; "
            .. "it never blocks, delays or alters a call."
    )
    addTextOption(
        LearningFeature,
        "Only containing",
        "",
        function(value: string): ()
            settings.filter = value
        end,
        nil,
        "Record only remotes whose path contains this. Leave empty for everything."
    )
    addNumberOption(
        LearningFeature,
        "Max remotes",
        settings.maxRemotes,
        10,
        400,
        function(value: number): ()
            settings.maxRemotes = math.round(value)
        end,
        "Stops the log growing without bound in a chatty game.",
        1
    )
    addToggleOption(
        LearningFeature,
        "Announce new",
        settings.announceNew,
        function(value: boolean): ()
            settings.announceNew = value
        end,
        "Toast the first time each remote is seen."
    )
    addToggleOption(
        LearningFeature,
        "Resample always",
        settings.resampleAlways,
        function(value: boolean): ()
            settings.resampleAlways = value
        end,
        "Describe the arguments of every call instead of the first few. "
            .. "Useful for a remote whose shape changes; heavier."
    )
    addActionOption(LearningFeature, "Save to file", function(): ()
        saveReport()
    end, "Writes " .. remoteLogFolder .. "/<place>-<time>.txt and .json")
    addActionOption(LearningFeature, "Copy to clipboard", function(): ()
        local environment: any = getfenv()
        local copy: any = environment.setclipboard or environment.toclipboard
        if type(copy) ~= "function" then
            notify("Remote Logger: executor has no clipboard")
            return
        end
        pcall(copy, buildReport())
        notify("Remote Logger: copied")
    end)
    addActionOption(LearningFeature, "Clear log", function(): ()
        log = {}
        order = {}
        notify("Remote Logger: cleared")
    end)
    addInformationOption(
        LearningFeature,
        "Turn it on, do the thing you want a module to do — buy, mine, place, "
            .. "hit — then save. The log records what only a live game can "
            .. "tell you: the arguments, in order, as the game really sent "
            .. "them."
    )
    finishPanel()

    Module.entries = function(): {any}
        local list: {any} = {}
        for _, key: string in ipairs(order) do
            table.insert(list, log[key])
        end
        return list
    end
    Module.report = buildReport

    activeCleanup = function(): ()
        stopCapturing()
        if restore then
            (restore :: () -> ())()
            restore = nil
        end
        Module.entries = nil
        Module.report = nil
    end
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
