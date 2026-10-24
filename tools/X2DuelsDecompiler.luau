-- X2 Duels live source/remote evidence collector.
--
-- Run this in the executor while in X2 Duels, then play one complete round:
-- shoot, throw, slash, collect a pumpkin and press Play Again. Files are
-- written under X2DuelsDecompiler/<place>-<timestamp>/.
--
-- Controls:
--   getgenv().X2DuelsDecompiler.snapshot() -- refresh live hierarchy
--   getgenv().X2DuelsDecompiler.stop()     -- restore hooks and disconnect
--
-- This uses the executor's decompile/getscriptbytecode facilities. It does
-- not pretend a failed decompilation is recovered source, and never changes
-- remote arguments or executes the dumped code.

local environment: any = getfenv()
local globalEnvironment: any = type(getgenv) == "function" and getgenv() or _G
if type(globalEnvironment.X2DuelsDecompiler) == "table"
    and type(globalEnvironment.X2DuelsDecompiler.stop) == "function" then
    pcall(globalEnvironment.X2DuelsDecompiler.stop)
end

local players: Players = game:GetService("Players")
local localPlayer: Player = players.LocalPlayer
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local httpService: HttpService = game:GetService("HttpService")
local starterPlayer: StarterPlayer = game:GetService("StarterPlayer")
local playerGui: PlayerGui = localPlayer:WaitForChild("PlayerGui")

local writeFile: any = environment.writefile
local appendFile: any = environment.appendfile
local makeFolder: any = environment.makefolder
assert(type(writeFile) == "function" and type(makeFolder) == "function",
    "X2DuelsDecompiler requires writefile and makefolder")

local sessionName: string = tostring(game.PlaceId) .. "-" .. tostring(os.time())
local rootFolder: string = "X2DuelsDecompiler/" .. sessionName
local sourcesFolder: string = rootFolder .. "/sources"
makeFolder("X2DuelsDecompiler")
makeFolder(rootFolder)
makeFolder(sourcesFolder)

local remoteLogPath: string = rootFolder .. "/remote-calls.jsonl"
writeFile(remoteLogPath, "")

local stopped: boolean = false
local sourcesDone: boolean = false
local incomingConnections: {any} = {}
local oldNamecall: any = nil
local namecallInstalled: boolean = false
local remoteEventCount: number = 0
local fallbackContents: {[string]: string} = {}

local function fullPath(instance: any): string
    if instance == nil then
        return "nil"
    end
    local ok: boolean, path: any = pcall(function(): any
        return instance:GetFullName()
    end)
    if ok then
        return tostring(path)
    end
    local fallbackOk: boolean, fallback: any = pcall(function(): string
        local parts: {string} = {}
        local current: any = instance
        while current do
            table.insert(parts, 1, tostring(current.Name))
            current = current.Parent
        end
        return table.concat(parts, ".")
    end)
    return fallbackOk and fallback or tostring(instance)
end

local function parentPath(instance: any): string
    local ok: boolean, parent: any = pcall(function(): any
        return instance.Parent
    end)
    return ok and fullPath(parent) or "?"
end

local function appendText(path: string, text: string): ()
    if stopped then
        return
    end
    if type(appendFile) == "function" then
        pcall(appendFile, path, text)
        return
    end
    -- Compatibility fallback for executors without appendfile. Keep an
    -- in-memory copy too: without readfile, repeatedly starting from "" would
    -- silently overwrite every earlier remote call.
    local previous: string? = fallbackContents[path]
    if previous == nil and type(environment.readfile) == "function" then
        local ok: boolean, contents: any = pcall(environment.readfile, path)
        if ok and type(contents) == "string" then
            previous = contents
        end
    end
    local combined: string = (previous or "") .. text
    fallbackContents[path] = combined
    pcall(writeFile, path, combined)
end

local function serialize(value: any, depth: number?, seen: {[any]: boolean}?): any
    local level: number = depth or 0
    if level > 6 then
        return {type = "depth-limit"}
    end
    local kind: string = typeof(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then
        return value
    end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return {type = "number", value = tostring(value)}
        end
        return value
    end
    if kind == "Instance" then
        return {
            type = "Instance",
            className = tostring(value.ClassName),
            path = fullPath(value),
        }
    end
    if kind == "Vector3" then
        return {type = kind, x = value.X, y = value.Y, z = value.Z}
    end
    if kind == "Vector2" then
        return {type = kind, x = value.X, y = value.Y}
    end
    if kind == "CFrame" then
        return {type = kind, components = {value:GetComponents()}}
    end
    if kind == "Color3" then
        return {type = kind, r = value.R, g = value.G, b = value.B}
    end
    if kind == "EnumItem" then
        return {type = kind, value = tostring(value)}
    end
    if kind == "Ray" then
        return {
            type = kind,
            origin = serialize(value.Origin, level + 1, seen),
            direction = serialize(value.Direction, level + 1, seen),
        }
    end
    if kind == "buffer" and type(buffer) == "table"
        and type(buffer.len) == "function" and type(buffer.readu8) == "function" then
        local length: number = buffer.len(value)
        local captured: number = math.min(length, 4096)
        local hex: {string} = table.create(captured * 2)
        for index: number = 0, captured - 1 do
            table.insert(hex, string.format("%02X", buffer.readu8(value, index)))
        end
        return {
            type = kind,
            length = length,
            hex = table.concat(hex),
            truncated = length > captured,
        }
    end
    if type(value) == "table" then
        local visited: {[any]: boolean} = seen or {}
        if visited[value] then
            return {type = "cycle"}
        end
        visited[value] = true
        local entries: {any} = {}
        local truncated: boolean = false
        local count: number = 0
        for key: any, entry: any in pairs(value) do
            count += 1
            if count > 100 then
                truncated = true
                break
            end
            table.insert(entries, {
                key = serialize(key, level + 1, visited),
                value = serialize(entry, level + 1, visited),
            })
        end
        visited[value] = nil
        return {type = "table", entries = entries, truncated = truncated}
    end
    return {type = kind, value = tostring(value)}
end

local function encode(record: any): string
    local ok: boolean, encoded: any = pcall(function(): any
        return httpService:JSONEncode(record)
    end)
    if ok then
        return encoded
    end
    return httpService:JSONEncode({
        error = "JSONEncode failed",
        detail = tostring(encoded),
    })
end

local function writeJson(path: string, value: any): ()
    pcall(writeFile, path, encode(value) .. "\n")
end

local function recordRemote(
    direction: string,
    remote: Instance,
    method: string,
    arguments: {any},
    callingScript: any
): ()
    if stopped then
        return
    end
    local record: {[string]: any} = {
        at = os.clock(),
        unix = os.time(),
        direction = direction,
        method = method,
        name = remote.Name,
        className = remote.ClassName,
        path = fullPath(remote),
        parent = parentPath(remote),
        caller = callingScript and fullPath(callingScript) or "unknown",
        arguments = serialize(arguments),
    }
    if type(environment.checkcaller) == "function" then
        local ok: boolean, executor: any = pcall(environment.checkcaller)
        record.executor = ok and executor == true
    end
    appendText(remoteLogPath, encode(record) .. "\n")
end

local function safeRecordRemote(...: any): ()
    local ok: boolean, failure: any = pcall(recordRemote, ...)
    if not ok then
        appendText(rootFolder .. "/errors.log", "remote record: " .. tostring(failure) .. "\n")
    end
end

local function attributesOf(instance: Instance): any
    local ok: boolean, attributes: any = pcall(function(): any
        return instance:GetAttributes()
    end)
    return ok and serialize(attributes) or {error = tostring(attributes)}
end

local function basicInfo(instance: Instance): {[string]: any}
    return {
        name = instance.Name,
        className = instance.ClassName,
        path = fullPath(instance),
        parent = parentPath(instance),
        attributes = attributesOf(instance),
    }
end

local roots: {Instance} = {
    replicatedStorage,
    workspace,
    playerGui,
}
local starterScripts: Instance? = starterPlayer:FindFirstChild("StarterPlayerScripts")
if starterScripts then
    table.insert(roots, starterScripts)
end
local backpack: Instance? = localPlayer:FindFirstChildOfClass("Backpack")
if backpack then
    table.insert(roots, backpack)
end
if localPlayer.Character then
    table.insert(roots, localPlayer.Character)
end

local function collectInstances(classPredicate: (Instance) -> boolean): {Instance}
    local result: {Instance} = {}
    local seen: {[Instance]: boolean} = {}
    for _, root: Instance in ipairs(roots) do
        if classPredicate(root) and not seen[root] then
            seen[root] = true
            table.insert(result, root)
        end
        for _, descendant: Instance in ipairs(root:GetDescendants()) do
            if classPredicate(descendant) and not seen[descendant] then
                seen[descendant] = true
                table.insert(result, descendant)
            end
        end
    end
    return result
end

local function snapshot(): ()
    if stopped then
        return
    end
    local remotes: {any} = {}
    local scripts: {any} = {}
    local tools: {any} = {}
    local spawnables: {any} = {}
    local buttons: {any} = {}
    local instances: {Instance} = collectInstances(function(instance: Instance): boolean
        return instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")
            or instance:IsA("RemoteFunction") or instance:IsA("LocalScript")
            or instance:IsA("ModuleScript") or instance:IsA("Script")
            or instance:IsA("Tool") or instance:IsA("Model")
            or instance:IsA("TextButton") or instance:IsA("ImageButton")
    end)
    for _, instance: Instance in ipairs(instances) do
        if instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")
            or instance:IsA("RemoteFunction") then
            table.insert(remotes, basicInfo(instance))
        elseif instance:IsA("LocalScript") or instance:IsA("ModuleScript")
            or instance:IsA("Script") then
            table.insert(scripts, basicInfo(instance))
        elseif instance:IsA("Tool") then
            local info: any = basicInfo(instance)
            info.children = {}
            for _, child: Instance in ipairs(instance:GetChildren()) do
                table.insert(info.children, {
                    name = child.Name,
                    className = child.ClassName,
                    path = fullPath(child),
                })
            end
            table.insert(tools, info)
        elseif instance:IsA("Model")
            and string.match(instance.Name, "^PumpkinCurrency_%d+$") then
            local info: any = basicInfo(instance)
            info.parts = {}
            for _, child: Instance in ipairs(instance:GetChildren()) do
                if child:IsA("BasePart") then
                    table.insert(info.parts, {
                        name = child.Name,
                        path = fullPath(child),
                        position = serialize(child.Position),
                        transparency = child.Transparency,
                        canTouch = child.CanTouch,
                    })
                end
            end
            table.insert(spawnables, info)
        elseif instance:IsA("TextButton") or instance:IsA("ImageButton") then
            local info: any = basicInfo(instance)
            info.visible = (instance :: any).Visible
            info.text = (instance :: any).Text
            table.insert(buttons, info)
        end
    end
    local playerData: {any} = {}
    for _, player: Player in ipairs(players:GetPlayers()) do
        table.insert(playerData, {
            name = player.Name,
            displayName = player.DisplayName,
            userId = player.UserId,
            neutral = player.Neutral,
            team = player.Team and player.Team.Name or nil,
            character = fullPath(player.Character),
            attributes = attributesOf(player),
        })
    end
    writeJson(rootFolder .. "/inventory.json", {
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        capturedAt = os.time(),
        remotes = remotes,
        scripts = scripts,
        tools = tools,
        spawnables = spawnables,
        buttons = buttons,
        players = playerData,
    })
end

local function connectIncoming(remote: Instance): ()
    if not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
        return
    end
    local ok: boolean, connection: any = pcall(function(): any
        return (remote :: any).OnClientEvent:Connect(function(...: any): ()
            safeRecordRemote("incoming", remote, "OnClientEvent", {...}, nil)
        end)
    end)
    if ok and connection then
        table.insert(incomingConnections, connection)
    end
end

for _, remote: Instance in ipairs(collectInstances(function(instance: Instance): boolean
    return instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")
end)) do
    remoteEventCount += 1
    connectIncoming(remote)
end

if type(environment.hookmetamethod) == "function"
    and type(environment.getnamecallmethod) == "function" then
    local callback: any = function(self: any, ...: any): any
        local method: string = string.lower(environment.getnamecallmethod())
        if method == "fireserver" or method == "invokeserver" then
            local isRemote: boolean = typeof(self) == "Instance" and (
                self:IsA("RemoteEvent") or self:IsA("UnreliableRemoteEvent")
                or self:IsA("RemoteFunction")
            )
            if isRemote then
                local callingScript: any = nil
                if type(environment.getcallingscript) == "function" then
                    local ok: boolean, script: any = pcall(environment.getcallingscript)
                    if ok then callingScript = script end
                end
                safeRecordRemote("outgoing", self, environment.getnamecallmethod(), {...}, callingScript)
            end
        end
        return oldNamecall(self, ...)
    end
    local wrapped: any = type(environment.newcclosure) == "function"
        and environment.newcclosure(callback) or callback
    local ok: boolean, predecessor: any = pcall(
        environment.hookmetamethod, game, "__namecall", wrapped
    )
    if ok and predecessor ~= nil then
        oldNamecall = predecessor
        namecallInstalled = true
    else
        appendText(rootFolder .. "/errors.log",
            "hookmetamethod(__namecall) failed: " .. tostring(predecessor) .. "\n")
    end
else
    appendText(rootFolder .. "/errors.log",
        "Outgoing capture requires hookmetamethod and getnamecallmethod.\n")
end

local function stop(): ()
    if stopped then
        return
    end
    snapshot()
    stopped = true
    if namecallInstalled and oldNamecall ~= nil
        and type(environment.hookmetamethod) == "function" then
        pcall(environment.hookmetamethod, game, "__namecall", oldNamecall)
        namecallInstalled = false
    end
    for _, connection: any in ipairs(incomingConnections) do
        pcall(function(): () connection:Disconnect() end)
    end
    table.clear(incomingConnections)
    writeJson(rootFolder .. "/status.json", {
        stopped = true,
        sourcesDone = sourcesDone,
        incomingRemotes = remoteEventCount,
        outgoingHook = oldNamecall ~= nil,
    })
    print("[X2DuelsDecompiler] stopped; evidence in " .. rootFolder)
end

globalEnvironment.X2DuelsDecompiler = {
    folder = rootFolder,
    snapshot = snapshot,
    stop = stop,
    isSourceDumpDone = function(): boolean return sourcesDone end,
}

snapshot()
print("[X2DuelsDecompiler] capturing remotes in " .. rootFolder)
print("[X2DuelsDecompiler] play a round: Shoot, Throw, Slash, pumpkin and Play Again")

task.spawn(function(): ()
    local scripts: {Instance} = collectInstances(function(instance: Instance): boolean
        return instance:IsA("LocalScript") or instance:IsA("ModuleScript")
            or instance:IsA("Script")
    end)
    local manifest: {any} = {}
    for index: number, script: Instance in ipairs(scripts) do
        if stopped then
            break
        end
        local safeName: string = string.gsub(script.Name, "[^%w_%-]", "_")
        safeName = string.sub(safeName, 1, 60)
        local stem: string = string.format("%04d_%s", index, safeName)
        local entry: {[string]: any} = basicInfo(script)
        entry.decompiled = false
        entry.usableSource = false

        if type(environment.decompile) == "function" then
            local ok: boolean, source: any = pcall(environment.decompile, script)
            if ok and type(source) == "string" and #source > 0 then
                local sourcePath: string = sourcesFolder .. "/" .. stem .. ".luau"
                local written: boolean, writeFailure: any = pcall(writeFile, sourcePath, source)
                entry.decompiled = true
                entry.usableSource = not string.find(source, "decompilation panicked", 1, true)
                    and not string.find(source, "decompilation failed", 1, true)
                if written then
                    entry.sourceFile = sourcePath
                else
                    entry.sourceWriteError = tostring(writeFailure)
                end
            else
                entry.error = ok and "decompile returned empty/non-string source" or tostring(source)
                pcall(writeFile, sourcesFolder .. "/" .. stem .. ".error.txt", entry.error)
            end
        else
            entry.error = "Executor has no decompile function"
        end

        if type(environment.getscriptbytecode) == "function" then
            local ok: boolean, bytecode: any = pcall(environment.getscriptbytecode, script)
            if ok and type(bytecode) == "string" and #bytecode > 0 then
                local bytecodePath: string = sourcesFolder .. "/" .. stem .. ".luauc"
                local written: boolean, writeFailure: any = pcall(writeFile, bytecodePath, bytecode)
                if written then
                    entry.bytecodeFile = bytecodePath
                    entry.bytecodeBytes = #bytecode
                else
                    entry.bytecodeError = tostring(writeFailure)
                end
            else
                entry.bytecodeError = ok and "empty/non-string bytecode" or tostring(bytecode)
            end
        else
            entry.bytecodeError = "Executor has no getscriptbytecode function"
        end
        table.insert(manifest, entry)
        if index % 10 == 0 then
            writeJson(rootFolder .. "/sources.json", manifest)
            print(string.format("[X2DuelsDecompiler] sources %d/%d", index, #scripts))
        end
        task.wait()
    end
    writeJson(rootFolder .. "/sources.json", manifest)
    if stopped then
        print("[X2DuelsDecompiler] source dump stopped; partial manifest saved")
        return
    end
    sourcesDone = true
    writeJson(rootFolder .. "/capabilities.json", {
        decompile = type(environment.decompile) == "function",
        getscriptbytecode = type(environment.getscriptbytecode) == "function",
        hookmetamethod = namecallInstalled,
        appendfile = type(appendFile) == "function",
    })
    print("[X2DuelsDecompiler] source dump complete; remote capture remains active")
end)
