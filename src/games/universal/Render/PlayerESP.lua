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
        Tooltip = "Boxes, skeletons, name tags, health, tracers and chams, "
            .. "each independently switchable.",
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
    esp:CreateToggle({
        Name = "Name tags",
        Default = true,
        Tooltip = "The player's name above the box.",
    })
    esp:CreateToggle({
        Name = "Display name",
        Show = {Option = "Name tags"},
        Default = true,
        Tooltip = "Show the display name rather than the account name.",
    })
    esp:CreateToggle({
        Name = "Health bar",
        Default = true,
        Tooltip = "Vertical bar on the left edge of the box.",
    })
    esp:CreateToggle({
        Name = "Health text",
        Default = false,
        Tooltip = "Print the exact hit points next to the name.",
    })
    esp:CreateToggle({
        Name = "Distance",
        Default = true,
        Tooltip = "Studs between you and the target.",
    })
    esp:CreateToggle({
        Name = "Held tool",
        Default = false,
        Tooltip = "Name of whatever the target currently has equipped.",
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
    esp:CreateToggle({
        Name = "Name plate",
        Default = true,
        Tooltip = "Put the name on a dark plate so it stays readable against "
            .. "a bright map.",
    })
    esp:CreateSlider({
        Name = "Text size",
        Min = 8,
        Max = 24,
        Default = 13,
    })

    local extraRuntime: any = {
        roles = nil :: any,
        extras = {} :: {any},
    }
    Module.bridge = extraRuntime

    local function addRoleRows(provider: any): ()
        if extraRuntime.roles then
            return
        end
        extraRuntime.roles = provider

        for _, redundant: string in
            ipairs({"Team check", "Visibility check", "Team colours", "Colour"})
        do
            local row: any = esp.Options[redundant]
            if row then

                row.Show = {Option = "__roles", Values = {true}}
                pcall(function(): ()
                    row:SetVisible(false)
                    row.Visible = false
                end)
            end
        end
        esp:CreateToggle({
            Name = "Role colours",
            Default = true,
            Tooltip = "Colour every drawing by what the player is in this "
                .. "game instead of by team.",
        })
        esp:CreateToggle({
            Name = "Show role",
            Show = {Option = "Name tags"},
            Default = true,
            Tooltip = "Print the role next to the name.",
        })
        for _, roleName: string in ipairs(provider.Roles or {}) do
            esp:CreateColor({
                Name = roleName .. " colour",
                Default = (provider.Colors or {})[roleName]
                    or Color3.fromRGB(236, 236, 240),
                Function = function(value: Color3): ()

                    if type(provider.SetColor) == "function" then
                        pcall(provider.SetColor, roleName, value)
                    end
                end,
            })
        end
    end

    local function addExtraRows(extra: any): ()
        table.insert(extraRuntime.extras, extra)
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
        gameBridge.onEvent(function(kind: string, payload: any): ()
            if kind == "roles" then
                addRoleRows(payload)
            elseif kind == "extra" then
                addExtraRows(payload)
            end
        end)
    end

    activeCleanup = function(): ()
        render:ReleaseAll(container)
        table.clear(pool)
        container.Visible = false
    end
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
        return
    end
    local resolvedCamera: Camera = camera :: Camera
    local options: any = esp.Options
    local viewport: Vector2 = resolvedCamera.ViewportSize

    entityLibrary:Refresh()
    local seen: {[Player]: boolean} = {}

    for _, entity: any in ipairs(entityLibrary.List) do
        local player: Player = entity.Player
        if options["Team check"].Value and entity.IsFriendly then
            continue
        end
        if entity.Distance > options["Max distance"].Value then

            continue
        end

        local rect: any = render:ModelRect(resolvedCamera, entity.Character)
        if not rect then
            continue
        end

        seen[player] = true
        pool[player] = true
        local drawings: any = render:Set(container, player)

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
        local colour: Color3 = options["Colour"].Value

        local role: string? = nil
        if type(gameBridge.playerRole) == "function" then
            role = gameBridge.playerRole(player)
        end
        local roleOption: any = role and options[role .. " colour"] or nil
        local useRoleColour: boolean = roleOption ~= nil
            and options["Role colours"] ~= nil
            and options["Role colours"].Value == true
        if useRoleColour then
            colour = roleOption.Value
        end

        if not useRoleColour and options["Team colours"].Value and entity.Team then

            local teamOk: boolean, teamColour: any = pcall(function(): Color3
                return (entity.Team :: any).TeamColor.Color
            end)
            if teamOk and typeof(teamColour) == "Color3" then
                colour = teamColour
            end
        end

        if not visible then
            colour = colour:Lerp(Color3.new(0, 0, 0), 0.45)
        end

        local left: number = rect.left
        local right: number = rect.right
        local top: number = rect.top
        local bottom: number = rect.bottom
        local width: number = rect.width
        local height: number = rect.height
        local centreX: number = rect.centreX

        drawings:Show(true)
        if right < 0 or left > viewport.X or bottom < 0 or top > viewport.Y then
            drawings:Show(false)
            continue
        end
        if width > viewport.X * 2.5 or height > viewport.Y * 2.5 then
            drawings:Show(false)
            continue
        end

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

        if options["Health bar"].Value then
            drawings:Bar(
                Vector2.new(left - 4, top),
                height,
                entity.Health / math.max(entity.MaxHealth, 1)
            )
        else
            drawings:HideBar()
        end

        local textSize: number = math.round(options["Text size"].Value)
        if options["Name tags"].Value then
            local shown: string = options["Display name"].Value
                and player.DisplayName
                or player.Name
            drawings:Label(
                "NameTag",
                (role
                        and options["Show role"] ~= nil
                        and options["Show role"].Value)
                    and (shown .. "  [" .. (role :: string) .. "]")
                    or shown,
                Vector2.new(centreX, top - 3),
                1,
                textSize,
                colour,
                options["Name plate"].Value
            )
        else
            drawings:HideLabel("NameTag")
        end

        local details: {string} = {}
        if options["Distance"].Value then
            table.insert(details, tostring(math.round(entity.Distance)) .. "m")
        end
        if options["Health text"].Value then
            table.insert(
                details,
                tostring(math.round(entity.Health))
                    .. "/"
                    .. tostring(math.round(entity.MaxHealth))
            )
        end
        if options["Held tool"].Value then
            local tool: Instance? = entity.Character:FindFirstChildOfClass("Tool")
            if tool then
                table.insert(details, tool.Name)
            end
        end
        if #details > 0 then
            drawings:Label(
                "Details",
                table.concat(details, "  "),
                Vector2.new(centreX, bottom + 2),
                0,
                math.max(textSize - 2, 8),
                colour,
                options["Name plate"].Value
            )
        else
            drawings:HideLabel("Details")
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
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
