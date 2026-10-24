-- Match-aware X2 Duels ESP. Team colors use the same resolver as combat.

local Module = {
    Name = "X2Duels Team ESP",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local moduleCleanup: () -> () = function(): () end

local function buildTeamESP(runtime: any): ()
    local host: any = getfenv()
    local state: any = runtime.State or host.state
    local core: any = state and state.x2duelsCore
    assert(type(core) == "table", "X2Duels base must initialize before Team ESP")

    local players: Players = game:GetService("Players")
    local localPlayer: Player = players.LocalPlayer
    local playerGui: PlayerGui = localPlayer:WaitForChild("PlayerGui")
    local settings: {[string]: boolean} = {
        enabled = false,
        enemies = true,
        teammates = true,
        unknown = true,
        names = true,
    }
    local visuals: {[Player]: any} = {}
    local connections: {any} = {}
    local container: Folder? = nil
    local nextUpdateAt: number = 0

    local COLORS: {[string]: Color3} = core.RoleColors or {
        Enemy = Color3.fromRGB(255, 82, 82),
        Teammate = Color3.fromRGB(75, 220, 135),
        Unknown = Color3.fromRGB(255, 190, 75),
    }

    local function destroyVisual(player: Player): ()
        local visual: any = visuals[player]
        visuals[player] = nil
        if visual then
            pcall(function(): () visual.highlight:Destroy() end)
            pcall(function(): () visual.billboard:Destroy() end)
        end
    end

    local function clearVisuals(): ()
        for player: Player, _visual: any in pairs(visuals) do
            destroyVisual(player)
        end
        table.clear(visuals)
    end

    local function ensureContainer(): Folder
        if container and container.Parent then
            return container
        end
        local created: Folder = Instance.new("Folder")
        created.Name = "Wurst_X2Duels_TeamESP"
        created.Parent = playerGui
        container = created
        return created
    end

    local function ensureVisual(
        player: Player,
        character: Model,
        head: BasePart
    ): any
        local existing: any = visuals[player]
        if existing and existing.character == character and existing.head == head
            and existing.highlight.Parent and existing.billboard.Parent then
            return existing
        end
        destroyVisual(player)
        local parent: Folder = ensureContainer()
        local highlight: Highlight = Instance.new("Highlight")
        highlight.Name = "X2DuelsESP_" .. tostring(player.UserId)
        highlight.Adornee = character
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.82
        highlight.OutlineTransparency = 0.05
        highlight.Parent = parent

        local billboard: BillboardGui = Instance.new("BillboardGui")
        billboard.Name = "X2DuelsName_" .. tostring(player.UserId)
        billboard.Adornee = head
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 1500
        billboard.Size = UDim2.fromOffset(190, 38)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
        billboard.ResetOnSpawn = false
        billboard.Parent = parent

        local label: TextLabel = Instance.new("TextLabel")
        label.Name = "Name"
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextStrokeTransparency = 0.45
        label.TextWrapped = false
        label.Parent = billboard

        local visual: any = {
            character = character,
            head = head,
            highlight = highlight,
            billboard = billboard,
            label = label,
        }
        visuals[player] = visual
        return visual
    end

    local function shouldShow(relation: string): boolean
        return relation == "Enemy" and settings.enemies
            or relation == "Teammate" and settings.teammates
            or relation == "Unknown" and settings.unknown
    end

    local function update(_deltaTime: number): ()
        if not settings.enabled then
            return
        end
        local now: number = os.clock()
        if now < nextUpdateAt then
            return
        end
        nextUpdateAt = now + 0.15
        local seen: {[Player]: boolean} = {}
        for _, player: Player in ipairs(players:GetPlayers()) do
            if player ~= localPlayer and core.isAlive(player) then
                local relation: string = core.relation(player)
                local character: Model? = player.Character
                local head: Instance? = character and character:FindFirstChild("Head")
                if shouldShow(relation) and character and head
                    and head:IsA("BasePart") then
                    seen[player] = true
                    local visual: any = ensureVisual(player, character, head :: BasePart)
                    local color: Color3 = COLORS[relation] or COLORS.Unknown
                    visual.highlight.FillColor = color
                    visual.highlight.OutlineColor = color
                    visual.highlight.Enabled = true
                    visual.billboard.Enabled = settings.names
                    visual.label.Text = tostring(player.DisplayName or player.Name)
                        .. "\n" .. string.upper(relation)
                    visual.label.TextColor3 = color
                end
            end
        end
        for player: Player, _visual: any in pairs(visuals) do
            if not seen[player] then
                destroyVisual(player)
            end
        end
    end

    moduleCleanup = function(): ()
        settings.enabled = false
        if host.featureConnections.X2DuelsTeamESP then
            host.disconnectFeatureConnection("X2DuelsTeamESP")
        end
        for _, connection: any in ipairs(connections) do
            pcall(function(): () connection:Disconnect() end)
        end
        table.clear(connections)
        clearVisuals()
        if container then
            pcall(function(): () container:Destroy() end)
            container = nil
        end
    end

    local espCard: any = host.createUniversalFeature(
        "Team ESP",
        "Match-aware outlines: enemies red, teammates green and unknown sides amber",
        7,
        function(enabled: boolean): ()
            settings.enabled = enabled
            nextUpdateAt = 0
            if not enabled then
                clearVisuals()
                if container then
                    container:Destroy()
                    container = nil
                end
            end
        end,
        {
            parent = state.mvsdScroll,
            registry = state.mvsdFeatures,
            categoryName = "Render",
        }
    )
    host.addToggleOption(espCard, "Enemies", true, function(value: boolean): ()
        settings.enemies = value
        nextUpdateAt = 0
    end)
    host.addToggleOption(espCard, "Teammates", true, function(value: boolean): ()
        settings.teammates = value
        nextUpdateAt = 0
    end)
    host.addToggleOption(espCard, "Unknown sides", true, function(value: boolean): ()
        settings.unknown = value
        nextUpdateAt = 0
    end)
    host.addToggleOption(espCard, "Names", true, function(value: boolean): ()
        settings.names = value
        nextUpdateAt = 0
    end)
    host.addInformationOption(
        espCard,
        "The same Team provider also feeds Wurst PlayerESP/Chams. Unknown sides are not targets while Team Check is ON."
    )

    table.insert(connections, players.PlayerRemoving:Connect(function(player: Player): ()
        destroyVisual(player)
    end))
    host.featureConnections.X2DuelsTeamESP = runtime.TaskManager:Connect(update)
end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    assert(type(runtime) == "table" and runtime.TaskManager,
        "X2Duels Team ESP requires Runtime.TaskManager")
    Module.Runtime = runtime
    local ok: boolean, failure: any = pcall(buildTeamESP, runtime)
    if not ok then
        moduleCleanup()
        Module.Runtime = nil
        error(failure)
    end
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    moduleCleanup()
    moduleCleanup = function(): () end
    Module.Runtime = nil
    Module.Initialized = false
end

return Module
