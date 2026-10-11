export type Runtime = {
    framework: any,
    entity: any,
    render: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Arrows",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

-- White is the default: an arrow is a direction cue, not a threat rating, so it
-- stays neutral until the game actually tells us something about the player it
-- points at.
local DEFAULT_COLOUR: Color3 = Color3.fromRGB(255, 255, 255)
local PREVIOUS_DEFAULT_COLOUR: Color3 = Color3.fromRGB(0, 204, 255)
local FRIENDLY_COLOUR: Color3 = Color3.fromRGB(255, 255, 255)

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local entity: any = context.entity
    local render: any = context.render
    local host: any = context.host
    local protectedTargets: any = context.services.protectedTargets
    local gameBridge: any = context.services.gameBridge
    local currentWorkspace: Workspace = context.host.workspace or workspace
    local layer: Frame = render:Layer("ArrowsLayer")
    local shown: {[Player]: boolean} = {}

    local card: any
    local function clear(): ()
        render:ReleaseAll(layer)
        table.clear(shown)
        layer.Visible = false
    end

    -- The colour of one arrow.
    --
    -- TeamCheck is the single switch for "paint players by what they are". When
    -- it is on and the running game publishes roles (MM2, MVSD, VD...), every
    -- arrow takes the colour of that player's role, so a Murderer reads red and
    -- a Sheriff reads blue without any per-game code in here. When the game has
    -- no role provider the same switch degrades to the only thing that is still
    -- known - teammate or not - and everything else keeps the configured
    -- colour.
    local function resolveColour(player: Player, isFriendly: boolean): Color3
        local base: Color3 = card.Options["Colour"].Value
        if card.Options["TeamCheck"].Value ~= true then
            return base
        end
        local roleColour: Color3? = nil
        if type(gameBridge) == "table"
            and type(gameBridge.playerRoleColor) == "function" then
            local ok: boolean, resolved: any = pcall(
                gameBridge.playerRoleColor,
                player
            )
            if ok and typeof(resolved) == "Color3" then
                roleColour = resolved :: Color3
            end
        end
        if roleColour then
            return roleColour :: Color3
        end
        if isFriendly then
            return FRIENDLY_COLOUR
        end
        return base
    end

    card = framework.Categories.Visuals:CreateModule({
        Name = "Arrows",
        Category = "Render",
        ConfigKey = "Universal.Arrows",
        Order = 3,
        Tooltip = "Points toward players outside the camera view.",
        Function = function(enabled: boolean): ()
            layer.Visible = enabled
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            card:Render(function(): ()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not camera then
                    render:ReleaseAll(layer)
                    table.clear(shown)
                    return
                end
                local viewport: Vector2 = camera.ViewportSize
                local centre: Vector2 = Vector2.new(viewport.X / 2, viewport.Y / 2)
                local radius: number = math.max(40, math.min(viewport.X, viewport.Y) * 0.4)
                local seen: {[Player]: boolean} = {}
                local count: number = 0
                local teamCheck: boolean = card.Options["TeamCheck"].Value == true
                for _, target: any in ipairs(entity:Refresh()) do
                    local player: Player = target.Player
                    if (not card.Options["Teammates"].Value and target.IsFriendly)
                        or protectedTargets.isProtected(player)
                        or not target.Humanoid
                        or target.Humanoid.Health <= 0
                        or not target.RootPart
                        or target.Distance > card.Options["Max distance"].Value then
                        render:Release(layer, player)
                        continue
                    end
                    local projected: Vector3, onScreen: boolean =
                        camera:WorldToViewportPoint(target.RootPart.Position)
                    if onScreen then
                        render:Release(layer, player)
                        continue
                    end
                    local drawing: any = render:Set(layer, player)
                    local delta: Vector2 = Vector2.new(projected.X, projected.Y) - centre
                    if projected.Z < 0 then
                        delta = Vector2.new(-delta.X, -delta.Y)
                    end
                    if delta.Magnitude < 0.001 then
                        delta = Vector2.new(0, -1)
                    end
                    local direction: Vector2 = delta.Unit
                    local perpendicular: Vector2 = Vector2.new(-direction.Y, direction.X)
                    local tip: Vector2 = centre + direction * radius
                    local back: Vector2 = tip - direction * 16
                    local colour: Color3 = resolveColour(player, target.IsFriendly == true)
                    drawing:Line("Arrow", 1, tip, back + perpendicular * 8, 2, colour)
                    drawing:Line("Arrow", 2, tip, back - perpendicular * 8, 2, colour)
                    drawing:HideLines("Arrow", 3, 8)
                    if card.Options["Distance"].Value then
                        drawing:Label(
                            "Distance",
                            tostring(math.round(target.Distance)) .. "m",
                            tip - direction * 26,
                            0.5,
                            12,
                            colour,
                            true
                        )
                    else
                        drawing:HideLabel("Distance")
                    end
                    drawing:Show(true)
                    seen[player] = true
                    count += 1
                end
                for player: Player in pairs(shown) do
                    if not seen[player] then
                        render:Release(layer, player)
                    end
                end
                shown = seen
                card:SetStatus(tostring(count))
            end)
            card:Clean(clear)
        end,
    })

    -- One-time migration: the previous hard-coded default was cyan. A stored
    -- value that is still exactly that old default has never been touched by
    -- the user, so it becomes the new white default instead of pinning them to
    -- a colour the menu no longer ships with.
    do
        local store: any = host and host.configData
        if store and store.values then
            local migrationKey: string = "Universal.Arrows.ColourSchema"
            if store.values[migrationKey] ~= 2 then
                local stored: any = store.values["Universal.Arrows.Colour"]
                local migrated: boolean = false
                -- Colours are persisted as {r, g, b} channels (see
                -- colorToConfig), so the migration speaks the same shape.
                if stored == nil then
                    store.values["Universal.Arrows.Colour"] = {
                        math.round(DEFAULT_COLOUR.R * 255),
                        math.round(DEFAULT_COLOUR.G * 255),
                        math.round(DEFAULT_COLOUR.B * 255),
                    }
                    migrated = true
                elseif type(stored) == "table" then
                    local r: number = tonumber(stored[1]) or 0
                    local g: number = tonumber(stored[2]) or 0
                    local b: number = tonumber(stored[3]) or 0
                    if math.abs(r - PREVIOUS_DEFAULT_COLOUR.R * 255) <= 1
                        and math.abs(g - PREVIOUS_DEFAULT_COLOUR.G * 255) <= 1
                        and math.abs(b - PREVIOUS_DEFAULT_COLOUR.B * 255) <= 1 then
                        store.values["Universal.Arrows.Colour"] = {
                            math.round(DEFAULT_COLOUR.R * 255),
                            math.round(DEFAULT_COLOUR.G * 255),
                            math.round(DEFAULT_COLOUR.B * 255),
                        }
                        migrated = true
                    end
                end
                store.values[migrationKey] = 2
                if migrated and type(host.queueConfigSave) == "function" then
                    host.queueConfigSave()
                end
            end
        end
    end

    card:CreateColor({Name = "Colour", Default = DEFAULT_COLOUR})
    card:CreateToggle({
        Name = "TeamCheck",
        Default = true,
        Tooltip = "Paints every arrow with that player's role when the game "
            .. "publishes roles (MM2, MVSD...). Without roles it falls back to "
            .. "white teammates and the configured colour for everyone else.",
    })
    card:CreateToggle({Name = "Distance", Default = true})
    card:CreateSlider({Name = "Max distance", Min = 25, Max = 2000, Step = 25, Default = 500})
    card:CreateToggle({Name = "Teammates", Default = false})

    -- Arrows ship enabled. Only a config that has never stored a state for this
    -- module gets the default, so turning them off once is remembered.
    do
        local store: any = host and host.configData
        if store and store.states and store.states["Universal.Arrows"] == nil then
            store.states["Universal.Arrows"] = true
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
            task.defer(function(): ()
                if not Module.Initialized or not activeCard then
                    return
                end
                if activeCard.Enabled then
                    return
                end
                pcall(function(): ()
                    activeCard:Toggle(true)
                end)
            end)
        end
    end

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
