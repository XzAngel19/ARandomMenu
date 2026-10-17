export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "PlayerESP",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil
local activeCard: any = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local players: Players = host.Players

    local render: any = context.render

    local container: Frame = render:Layer("PlayerEspLayer")
    local pool: {[Player]: boolean} = {}
    local lastStatusAt: number = -math.huge
    local visibilityCache: any = setmetatable({}, {__mode = "k"})

    local esp: any
    esp = framework.Categories.Visuals:CreateModule({
        Name = "PlayerESP",
        Category = "Render",
        ConfigKey = "Universal.PlayerESP",
        Order = 1,
        Tooltip = "Outlined boxes, skeletons and tracers. Nametags and HP are independent modules.",
        Function = function(enabled: boolean): ()
            container.Visible = enabled
            if not enabled then
                esp:SetStatus(nil)
                render:ReleaseAll(container)
                table.clear(pool)
                return
            end
            lastStatusAt = -math.huge
            esp:SetStatus("0")
            esp:Render(function(): ()
                Module.render(context, container, pool, esp, visibilityCache)
                local now: number = os.clock()
                if now - lastStatusAt >= 0.25 then
                    lastStatusAt = now
                    local count: number = 0
                    for _player: Player in pairs(pool) do
                        count += 1
                    end
                    esp:SetStatus(tostring(count))
                end
            end)
            esp:Event(players.PlayerRemoving, function(player: Player): ()
                render:Release(container, player)
                pool[player] = nil
            end)
            esp:Clean(function(): ()
                render:ReleaseAll(container)
                table.clear(pool)
                container.Visible = false
            end)
        end,
    })

    esp:CreateDropdown({
        Name = "Boxes",
        List = {"Corner", "Full", "Off"},
        Index = 1,
        Tooltip = "Corner draws four brackets, Full draws the whole rectangle.",
    })
    esp:CreateSlider({
        Name = "Box thickness",
        Show = {Option = "Boxes", Values = {"Corner", "Full"}},
        Min = 1,
        Max = 5,
        Default = 1,
    })
    esp:CreateToggle({
        Name = "Filled box",
        Show = {Option = "Boxes", Values = {"Corner", "Full"}},
        Default = false,
        Tooltip = "Wash the inside of the box in the target's colour. Reads "
            .. "at a glance across a map; noisy in a crowd.",
    })
    esp:CreateToggle({
        Name = "Skeleton",
        Default = false,
        Tooltip = "Draw the rig's bones. Works on both R6 and R15.",
    })
    esp:CreateDropdown({
        Name = "Tracers",
        List = {"Off", "Bottom", "Centre", "Cursor"},
        Index = 1,
        Tooltip = "Where the line to each target starts.",
    })
    esp:CreateToggle({
        Name = "Team check",
        Default = false,
        Tooltip = "Skip players on your own team.",
    })
    esp:CreateToggle({
        Name = "Visibility check",
        Default = false,
        Tooltip = "Recolour targets that are behind geometry.",
    })
    esp:CreateSlider({
        Name = "Max distance",
        Min = 50,
        Max = 5000,
        Default = 2000,
    })

    esp:CreateColor({
        Name = "Colour",
        Default = Color3.fromRGB(255, 255, 255),
        Tooltip = "Used for every target the game gives no colour of its own.",
    })
    esp:CreateToggle({
        Name = "Team colours",
        Default = true,
        Tooltip = "Draw each player in their own team's colour where the game "
            .. "has teams.",
    })
    local roles = context.services.gameRoles:Bind(esp)
    Module.roles = roles
    esp.OptionFilter = function(name)
        return not (roles.provider and roles.provider.ReplacesTeams and (name == "Team check" or name == "Team colours"))
    end
    esp:RefreshVisibility()
    local function addExtraRows(extra: any): ()
        if type(extra) ~= "table" or type(extra.Name) ~= "string" or esp.Options[extra.Name] then return end
        esp:CreateToggle({
            Name = extra.Name,
            Default = extra.Default == true,
            Tooltip = extra.Tooltip,
            Function = function(value: boolean): ()
                if type(extra.Toggle) == "function" then
                    pcall(extra.Toggle, value)
                end
            end,
        })
        if extra.Color then
            esp:CreateColor({
                Name = extra.Name .. " colour",
                Show = {Option = extra.Name},
                Default = extra.Color,
                Function = function(value: Color3): ()
                    if type(extra.SetColor) == "function" then
                        pcall(extra.SetColor, value)
                    end
                end,
            })
        end

        for _, definition: any in ipairs(extra.Options or {}) do
            local rowName: string = extra.Name .. " " .. definition.Name
            if definition.Kind == "toggle" then
                esp:CreateToggle({
                    Name = rowName,
                    Show = {Option = extra.Name},
                    Default = definition.Default == true,
                    Tooltip = definition.Tooltip,
                    Function = function(value: boolean): ()
                        if type(definition.Set) == "function" then
                            pcall(definition.Set, value)
                        end
                    end,
                })
            else
                esp:CreateSlider({
                    Name = rowName,
                    Show = {Option = extra.Name},
                    Min = definition.Min or 0,
                    Max = definition.Max or 100,
                    Default = definition.Default or definition.Min or 0,
                    Tooltip = definition.Tooltip,
                    Function = function(value: number): ()
                        if type(definition.Set) == "function" then
                            pcall(definition.Set, value)
                        end
                    end,
                })
            end
        end
    end

    local gameBridge: any = context.services.gameBridge
    if type(gameBridge.onEvent) == "function" then
        Module.bridgeCleanup = gameBridge.onEvent(function(kind: string, payload: any): ()
            if kind == "extra" then
                addExtraRows(payload)
            end
        end)
    end

    activeCleanup = function(): ()
        render:ReleaseAll(container)
        table.clear(pool)
        container.Visible = false
    end
    activeCard = esp
    Module.Initialized = true
    return esp
end

function Module.render(
    context: Runtime,
    container: Frame,
    pool: {[Player]: any},
    esp: any,
    visibilityCache: any
): ()
    local host: any = context.host
    local entityLibrary: any = context.entity
    local render: any = context.render
    local gameBridge: any = context.services.gameBridge
    local currentWorkspace: Workspace = host.workspace or workspace
    local camera: Camera? = currentWorkspace.CurrentCamera
    if not camera then
        container.Visible = false
        return
    end
    container.Visible = true
    local resolvedCamera: Camera = camera :: Camera
    local options: any = esp.Options
    local viewport: Vector2 = resolvedCamera.ViewportSize

    entityLibrary:Refresh()
    local seen: {[Player]: boolean} = {}

    for _, entity: any in ipairs(entityLibrary.List) do
        local player: Player = entity.Player
        if not (Module.roles and Module.roles.provider and Module.roles.provider.ReplacesTeams)
            and options["Team check"].Value and entity.IsFriendly then
            continue
        end
        if entity.Distance > options["Max distance"].Value then

            continue
        end

        local rect: any = render:ModelRect(resolvedCamera, entity.Character)

        seen[player] = true
        pool[player] = true
        local drawings: any = render:Set(container, player)

        if not rect then

            drawings:Show(false)
            continue
        end

        local visible: boolean = true
        if options["Visibility check"].Value then
            local cache: any = visibilityCache[player]
            local now: number = os.clock()
            if not cache or now - cache.at > 0.12 then
                cache = {at = now, value = entityLibrary:VisibleFrom(entity)}
                visibilityCache[player] = cache
            end
            visible = cache.value
        end
        local colour = options["Colour"].Value
        local roles = Module.roles
        local roleColour = roles and roles:Resolve(player, nil)
        if roleColour then
            colour = roleColour
        elseif not (roles and roles.provider and roles.provider.ReplacesTeams)
            and options["Team colours"].Value and player.Team then
            colour = player.Team.TeamColor.Color
        end

        if not visible then
            colour = colour:Lerp(Color3.new(0, 0, 0), 0.45)
        end

        local left: number = rect.left
        local top: number = rect.top
        local bottom: number = rect.bottom
        local height: number = rect.height
        local centreX: number = rect.centreX

        drawings:Show(true)

        local thickness: number = math.round(options["Box thickness"].Value)
        local boxMode: string = options["Boxes"].Value
        drawings:Fill(
            options["Filled box"].Value and boxMode ~= "Off" and rect or nil,
            colour,
            0.82
        )
        drawings:Box(rect, boxMode, thickness, colour)

        if options["Skeleton"].Value then
            local bones: {{BasePart}} = entityLibrary:Rig(entity)
            for index: number = 1, 14 do
                local pair: {BasePart}? = bones[index]
                local first: Vector2? = pair
                    and render:Project(resolvedCamera, pair[1].Position)
                local second: Vector2? = pair
                    and render:Project(resolvedCamera, pair[2].Position)
                if first and second then
                    drawings:Line(
                        "Bone",
                        index,
                        first :: Vector2,
                        second :: Vector2,
                        1,
                        colour
                    )
                else
                    drawings:HideLines("Bone", index, index)
                end
            end
        else
            drawings:HideLines("Bone", 1, 14)
        end

        local tracerMode: string = options["Tracers"].Value
        if tracerMode == "Off" then
            drawings:HideLines("Tracer", 1, 1)
        else
            local origin: Vector2
            if tracerMode == "Bottom" then
                origin = Vector2.new(viewport.X * 0.5, viewport.Y)
            elseif tracerMode == "Centre" then
                origin = viewport * 0.5
            else
                origin = host.UserInputService:GetMouseLocation()
            end
            drawings:Line(
                "Tracer",
                1,
                origin,
                Vector2.new(centreX, bottom),
                1,
                colour
            )
        end

    end

    for player: Player in pairs(pool) do
        if not seen[player] then
            render:Release(container, player)
            pool[player] = nil
        end
    end
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then activeCard:Toggle(false) end
    if activeCleanup then
        pcall(activeCleanup)
    end
    if Module.roles then Module.roles:Destroy(); Module.roles = nil end
    if Module.bridgeCleanup then Module.bridgeCleanup(); Module.bridgeCleanup = nil end
    activeCleanup = nil
    activeCard = nil
    Module.Initialized = false
end

return Module
