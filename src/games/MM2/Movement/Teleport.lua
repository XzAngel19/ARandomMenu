local Module = {
    Name = "MM2 Teleport",
    PlaceId = 142823291,
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
    assert(type(core) == "table", "MM2 Teleport requires the MM2 core module")
    Module.Runtime = runtime
    local findDroppedGun: any = core.findDroppedGun
    local findMM2Map: any = core.findMM2Map
    local mm2Settings: any = core.mm2Settings

    local autoGetGunBusy = false

    local function toggleAutoGetGun(enabled)
        disconnectFeatureConnection("MM2AutoGetGun")
        autoGetGunBusy = false

        if not enabled then
            return
        end

        local elapsed = 0
        featureConnections.MM2AutoGetGun = TaskManager:Connect(function(deltaTime)
            elapsed = elapsed + deltaTime
            if elapsed < 0.5 or autoGetGunBusy then
                return
            end
            elapsed = 0

            local character = LocalPlayer.Character
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            local gunDrop = findDroppedGun()
            if not character or not gunDrop
                or (backpack and backpack:FindFirstChild("Gun"))
                or character:FindFirstChild("Gun") then
                return
            end

            autoGetGunBusy = true
            task.spawn(function()
                local savedCFrame = character:GetPivot()
                character:PivotTo(gunDrop:GetPivot() + Vector3.new(0, 2, 0))
                task.wait(mm2Settings.autoGetGunDelay)
                if character.Parent then
                    character:PivotTo(savedCFrame)
                end
                autoGetGunBusy = false
            end)
        end)
    end

    local function teleportToMap()
        local map = findMM2Map()
        local spawns = map and map:FindFirstChild("Spawns")
        local character = LocalPlayer.Character
        if not spawns or not character then
            notify("No active MM2 map was found.")
            return
        end

        local spawnList = spawns:GetChildren()
        local target = spawnList[math.random(1, math.max(1, #spawnList))]
        if target and target:IsA("BasePart") then
            character:PivotTo(target.CFrame + Vector3.new(0, 3, 0))
        end
    end

    local function teleportToLobby()
        local lobby = workspace:FindFirstChild("Lobby")
        local spawns = lobby and lobby:FindFirstChild("Spawns")
        local spawn = spawns and spawns:FindFirstChildWhichIsA("SpawnLocation")
        local character = LocalPlayer.Character
        if spawn and character then
            character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
        else
            notify("The MM2 lobby spawn was not found.")
        end
    end

    -- Name typed into the "Player name" box; "Teleport to Player" moves you to
    -- that player (case-insensitive, partial names allowed).
    local teleportTargetName = ""

    local function teleportToPlayer()
        local character = LocalPlayer.Character
        if not character then
            notify("Your character is not available.")
            return
        end
        local needle = string.lower(
            string.gsub(teleportTargetName or "", "%s+", "")
        )
        if needle == "" then
            notify("Type a player name in the Player name box first.")
            return
        end
        local exact, partial = nil, nil
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local name = string.lower(player.Name)
                if string.gsub(name, "%s+", "") == needle then
                    exact = player
                    break
                end
                if not partial and string.find(name, needle, 1, true) then
                    partial = player
                end
            end
        end
        local target = exact or partial
        local targetRoot = target
            and target.Character
            and target.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            character:PivotTo(targetRoot.CFrame + Vector3.new(0, 3, 0))
        elseif target then
            notify(target.Name .. " has no character to teleport to.")
        else
            notify("No player named \"" .. teleportTargetName .. "\" was found.")
        end
    end

    local function teleportToDroppedGun()
        local gunDrop = findDroppedGun()
        local character = LocalPlayer.Character
        if gunDrop and character then
            local savedCFrame = character:GetPivot()
            character:PivotTo(gunDrop:GetPivot() + Vector3.new(0, 2, 0))
            task.wait(mm2Settings.autoGetGunDelay)
            if character.Parent then
                character:PivotTo(savedCFrame)
            end
        else
            notify("No dropped gun was found.")
        end
    end

    local TeleportFeature = createUniversalFeature(
        "Teleport",
        "Map, lobby, and temporary gun pickup",
        14,
        function() end,
        {
            category = true,
            categoryName = "Movement",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addActionOption(TeleportFeature, "Teleport to Map", teleportToMap)
    addActionOption(TeleportFeature, "Teleport to Lobby", teleportToLobby)
    addTextOption(
        TeleportFeature,
        "Player name",
        "",
        function(value)
            teleportTargetName = value
        end,
        false,
        "Exact or partial name"
    )
    addActionOption(TeleportFeature, "Teleport to Player", teleportToPlayer)
    addActionOption(TeleportFeature, "Get Gun", teleportToDroppedGun)
    local GetGunKeyButton: TextButton = addKeyOption(
        TeleportFeature,
        "Get Gun key",
        mm2Settings.getGunKey,
        function(value: Enum.KeyCode): ()
            mm2Settings.getGunKey = value
        end
    )
    if state.bindMobileActionPlacement then
        state.bindMobileActionPlacement(
            GetGunKeyButton,
            "MM2GetGun",
            "GUN",
            teleportToDroppedGun
        )
    end
    featureConnections.MM2GetGunKey = UserInputService.InputBegan:Connect(
        function(input, gameProcessed)
            if gameProcessed
                or state.keyCaptureCallback
                or state.waitingForKey
                or UserInputService:GetFocusedTextBox() then
                return
            end
            if input.UserInputType == Enum.UserInputType.Keyboard
                and input.KeyCode == mm2Settings.getGunKey then
                task.spawn(teleportToDroppedGun)
            end
        end
    )
    addToggleOption(TeleportFeature, "Auto Get Gun", false, toggleAutoGetGun)
    addNumberOption(
        TeleportFeature,
        "Gun pickup delay",
        mm2Settings.autoGetGunDelay,
        0.05,
        2,
        function(value)
            mm2Settings.autoGetGunDelay = value
        end
    )

    activeCleanup = function(): ()
        toggleAutoGetGun(false)
                disconnectFeatureConnection("MM2GetGunKey")
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
