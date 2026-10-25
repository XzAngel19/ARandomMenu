local Module = {
    Name = "MM2 Proximity Warning",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Proximity Warning requires the MM2 core module")
    Module.Runtime = runtime

    local settings = {
        radius = 50,
        alertRadius = 25,
        criticalRadius = 15,
        showArrow = true,
        showDistance = true,
    }

    local function getLocalRole(): string?
        if type(core.getPlayerRole) == "function" then
            return core.getPlayerRole(LocalPlayer)
        end
        return nil
    end

    local function findMurderer(): Player?
        if type(core.getPlayerRole) ~= "function" then
            return nil
        end
        for _, player: Player in ipairs(game:GetService("Players"):GetPlayers()) do
            if player ~= LocalPlayer and core.getPlayerRole(player) == "Murderer" then
                return player
            end
        end
        return nil
    end

    local function characterRoot(player: Player): BasePart?
        local character = player.Character
        if not character then return nil end
        return character:FindFirstChild("HumanoidRootPart")
    end

    local function toggleProximityWarning(enabled: boolean): ()
        disconnectFeatureConnection("MM2ProximityWarning")

        if not enabled then
            return
        end

        local lastUpdate: number = -math.huge

        featureConnections.MM2ProximityWarning = TaskManager:Connect(function(): ()
            local now: number = os.clock()
            if now - lastUpdate < 0.1 then
                return
            end
            lastUpdate = now

            local localRole: string? = getLocalRole()
            
            -- Don't show warning if you're the murderer
            if localRole == "Murderer" then
                return
            end

            local myRoot: BasePart? = characterRoot(LocalPlayer)
            if not myRoot then
                return
            end

            local murderer: Player? = findMurderer()
            if not murderer then
                return
            end

            local murdererRoot: BasePart? = characterRoot(murderer)
            if not murdererRoot then
                return
            end

            local distance: number = (murdererRoot.Position - myRoot.Position).Magnitude
            local myRoot: BasePart? = characterRoot(LocalPlayer)
            if not myRoot then
                return
            end

            -- Determine alert level based on distance
            local alertLevel: string
            local alertColor: Color3
            
            if distance <= settings.criticalRadius then
                alertLevel = "CRITICAL"
                alertColor = Color3.fromRGB(255, 50, 50)
            elseif distance <= settings.alertRadius then
                alertLevel = "WARNING"
                alertColor = Color3.fromRGB(255, 200, 50)
            elseif distance <= settings.radius then
                alertLevel = "NEARBY"
                alertColor = Color3.fromRGB(100, 255, 100)
            else
                return
            end

            -- Build status text
            local statusParts: {string} = {alertLevel}
            
            if settings.showDistance then
                table.insert(statusParts, string.format("%.1f studs", distance))
            end
            
            if settings.showArrow then
                local direction: Vector3 = (murdererRoot.Position - myRoot.Position).Unit
                local angle: number = math.atan2(direction.Z, direction.X)
                local arrowIndex: number = math.floor((angle + math.pi) / (math.pi / 4)) % 8
                local arrows: {string} = {"→", "↘", "↓", "↙", "←", "↖", "↑", "↗"}
                table.insert(statusParts, arrows[arrowIndex + 1])
            end

            local status: string = table.concat(statusParts, " ")
            
            -- Update the feature status
            local feature = state.mm2ProximityWarningFeature
            if feature then
                feature:SetStatus(status)
            end
        end)
    end

    local ProximityWarningFeature: any = createUniversalFeature(
        "Proximity Warning",
        "Alerts you when the murderer is nearby. Shows distance and direction. Only works if you're not the murderer.",
        8,
        toggleProximityWarning,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2ProximityWarningFeature = ProximityWarningFeature

    addNumberOption(ProximityWarningFeature, "Detection Radius", 50, 10, 100,
        function(value: number): ()
            settings.radius = value
        end,
        "Maximum distance to detect the murderer (in studs).", 1)

    addNumberOption(ProximityWarningFeature, "Alert Radius", 25, 5, 50,
        function(value: number): ()
            settings.alertRadius = value
        end,
        "Distance at which to show WARNING alert (yellow).", 1)

    addNumberOption(ProximityWarningFeature, "Critical Radius", 15, 5, 30,
        function(value: number): ()
            settings.criticalRadius = value
        end,
        "Distance at which to show CRITICAL alert (red).", 1)

    addToggleOption(ProximityWarningFeature, "Show Arrow", true,
        function(value: boolean): ()
            settings.showArrow = value
        end,
        "Show directional arrow pointing to the murderer.")

    addToggleOption(ProximityWarningFeature, "Show Distance", true,
        function(value: boolean): ()
            settings.showDistance = value
        end,
        "Show distance to the murderer in studs.")

    activeCleanup = function(): ()
        toggleProximityWarning(false)
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
