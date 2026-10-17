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

    local teleport = state.framework:GetModule("Teleport")
    assert(teleport, "MM2 extends the universal Teleport module")
    for _, id in ipairs({"GetGunkey", "Gunpickupdelay", "Playername"}) do
        local key = "Universal.ClickTeleport." .. id
        if configData.values[key] == nil then configData.values[key] = configData.values["MM2.Teleport." .. id] end
    end
    local autoKey = "Universal.ClickTeleport.AutoGetGun"
    if configData.states[autoKey] == nil then configData.states[autoKey] = configData.states["MM2.Teleport.AutoGetGun"] end
    local show = {Option = "Destination", Values = {"MM2 Map", "MM2 Lobby", "MM2 Player", "MM2 Gun"}}
    teleport:CreateTextBox({Name = "Player name", Default = "", Show = {Option = "Destination", Values = {"MM2 Player"}},
        Function = function(value) teleportTargetName = value end})
    state.mm2TeleportRun = function()
        local target = teleport.Options.Destination.Value
        if target == "MM2 Map" then teleportToMap()
        elseif target == "MM2 Lobby" then teleportToLobby()
        elseif target == "MM2 Player" then teleportToPlayer()
        elseif target == "MM2 Gun" then teleportToDroppedGun() end
    end
    local key = teleport:CreateBind({Name = "Get Gun key", Default = mm2Settings.getGunKey, Show = show,
        Function = function(value) mm2Settings.getGunKey = value end})
    if state.bindMobileActionPlacement and key.Object then
        state.bindMobileActionPlacement(key.Object, "MM2GetGun", "GUN", teleportToDroppedGun)
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
    teleport:CreateToggle({Name = "Auto Get Gun", Default = false, Show = show, Function = toggleAutoGetGun})
    teleport:CreateSlider({Name = "Gun pickup delay", Default = mm2Settings.autoGetGunDelay,
        Min = 0.05, Max = 2, Decimal = 2, Show = show,
        Function = function(value) mm2Settings.autoGetGunDelay = value end})

    activeCleanup = function(): ()
        toggleAutoGetGun(false)
        state.mm2TeleportRun = nil
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
