local Module = {
    Name = "MM2 Teleport",
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
    local getPlayerRole: any = core.getPlayerRole
    local isRoundLifecycleActive: any = core.isRoundLifecycleActive
    local mm2Settings: any = core.mm2Settings

    -- Auto Get Gun is an innocent-only, in-round action. As Murderer it
    -- must never run (the knife role has no use for the sheriff gun and
    -- grabbing it exposes the role), and in the lobby there is no dropped
    -- gun worth chasing. Fail closed when the role or round state is not
    -- positively known.
    local function canAutoGetGun(): boolean
        if type(getPlayerRole) ~= "function"
            or getPlayerRole(LocalPlayer) ~= "Innocent" then
            return false
        end
        if type(isRoundLifecycleActive) ~= "function"
            or isRoundLifecycleActive() ~= true then
            return false
        end
        if type(findMM2Map) ~= "function" or not findMM2Map() then
            return false
        end
        return true
    end

    -- Immediate pickup without moving the character: pulse the touch
    -- between our root and the dropped gun's part, with no sleep or
    -- configurable delay. The next Heartbeat can retry while weapon
    -- replication is still catching up.
    local function touchDroppedGun(gunDrop: Instance): boolean
        if type(state.fireTouchInterest) ~= "function" then
            return false
        end
        local character: Model? = LocalPlayer.Character
        local root: Instance? = character
            and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return false
        end
        local touchPart: Instance? = nil
        if gunDrop:IsA("BasePart") then
            touchPart = gunDrop
        elseif gunDrop:IsA("Model") then
            touchPart = gunDrop:FindFirstChild("Handle", true)
                or gunDrop:FindFirstChildWhichIsA("BasePart", true)
        end
        if not touchPart then
            return false
        end
        pcall(state.fireTouchInterest, root, touchPart, 0)
        pcall(state.fireTouchInterest, root, touchPart, 1)
        local backpack: Instance? =
            LocalPlayer:FindFirstChildOfClass("Backpack")
        return (backpack ~= nil and backpack:FindFirstChild("Gun") ~= nil)
            or (character ~= nil and character:FindFirstChild("Gun") ~= nil)
    end

    local autoGetGunBusy = false

    local function toggleAutoGetGun(enabled)
        disconnectFeatureConnection("MM2AutoGetGun")
        autoGetGunBusy = false
        state.mm2AutoGetGunEnabled = enabled == true

        if not enabled then
            return
        end

        -- No polling throttle: TaskManager already runs this on
        -- Heartbeat, so checking every frame is the fastest the
        -- client can react (one frame, never a 0.5 s wait). The tick
        -- also runs once synchronously on enable, so a gun that is
        -- already on the ground is grabbed in the same frame the
        -- toggle turns on instead of waiting for the next Heartbeat.
        local function autoGetGunTick(): ()
            if autoGetGunBusy then
                return
            end

            local character = LocalPlayer.Character
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            local gunDrop = findDroppedGun()
            if not character or not gunDrop
                or not canAutoGetGun()
                or (backpack and backpack:FindFirstChild("Gun"))
                or character:FindFirstChild("Gun") then
                return
            end

            -- Instant touch first: no PivotTo, no position the server
            -- can call invalid. If the touch does not deliver the gun,
            -- stay put and let the next frame retry instead of falling
            -- back to a teleport the user did not ask for.
            autoGetGunBusy = true
            task.spawn(function()
                pcall(touchDroppedGun, gunDrop)
                autoGetGunBusy = false
            end)
        end
        featureConnections.MM2AutoGetGun =
            TaskManager:Connect(autoGetGunTick)
        autoGetGunTick()
    end

    local function moveCharacterTo(character: any, destination: CFrame): ()
        local root: any = character:FindFirstChild("HumanoidRootPart")
        if root then
            pcall(function(): ()
                root.Anchored = false
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
        character:PivotTo(destination)
        if root then
            pcall(function(): ()
                root.CFrame = destination
            end)
        end
    end

    local function teleportToMap()
        local map = findMM2Map()
        local spawns = map and (map:FindFirstChild("Spawns") or map:FindFirstChild("Spawns", true))
        local character = LocalPlayer.Character
        if not map or not character then
            notify("No active MM2 map was found.")
            return
        end

        local target = nil
        if spawns and type(spawns.GetChildren) == "function" then
            local spawnList = spawns:GetChildren()
            target = spawnList[math.random(1, math.max(1, #spawnList))]
            if target and not target:IsA("BasePart") and type(target.FindFirstChildWhichIsA) == "function" then
                target = target:FindFirstChildWhichIsA("BasePart", true)
            end
        end
        if (not target or not target:IsA("BasePart"))
            and spawns
            and type(spawns.FindFirstChildWhichIsA) == "function" then
            target = spawns:FindFirstChildWhichIsA("BasePart", true)
        end
        if (not target or not target:IsA("BasePart"))
            and type(map.FindFirstChildWhichIsA) == "function" then
            target = map:FindFirstChildWhichIsA("BasePart", true)
        end
        if target and target:IsA("BasePart") then
            moveCharacterTo(character, target.CFrame + Vector3.new(0, 3, 0))
        else
            notify("No active MM2 map spawn was found.")
        end
    end

    local function findLobbySpawn()
        local lobby = workspace:FindFirstChild("Lobby")
            or workspace:FindFirstChild("MainLobby")
            or workspace:FindFirstChild("RegularLobby")
        if not lobby and type(workspace.GetChildren) == "function" then
            for _, child in ipairs(workspace:GetChildren()) do
                local lowerName = string.lower(tostring(child.Name))
                if string.find(lowerName, "lobby", 1, true) ~= nil
                    or child:FindFirstChild("VotePads", true) ~= nil
                    or child:FindFirstChild("VotePad1", true) ~= nil
                    or child:FindFirstChild("VoteIcons", true) ~= nil then
                    lobby = child
                    break
                end
            end
        end
        if lobby then
            local spawns = lobby:FindFirstChild("Spawns")
                or lobby:FindFirstChild("Spawns", true)
            if spawns then
                if type(spawns.FindFirstChildWhichIsA) == "function" then
                    local spawn = spawns:FindFirstChildWhichIsA("SpawnLocation")
                        or spawns:FindFirstChildWhichIsA("BasePart")
                        or spawns:FindFirstChildWhichIsA("BasePart", true)
                    if spawn then
                        return spawn
                    end
                end
                if type(spawns.GetChildren) == "function" then
                    for _, item in ipairs(spawns:GetChildren()) do
                        if type(item.IsA) == "function" and item:IsA("BasePart") then
                            return item
                        end
                    end
                end
            end
            if type(lobby.FindFirstChildWhichIsA) == "function" then
                local directSpawn = lobby:FindFirstChildWhichIsA("SpawnLocation", true)
                if directSpawn then
                    return directSpawn
                end
            end
            local votePads = lobby:FindFirstChild("VotePads", true)
                or lobby:FindFirstChild("VotePad1", true)
            if votePads and type(votePads.FindFirstChildWhichIsA) == "function" then
                local padPart = votePads:FindFirstChildWhichIsA("BasePart", true)
                if padPart then
                    return padPart
                end
            end
            if type(lobby.FindFirstChildWhichIsA) == "function" then
                local anyPart = lobby:FindFirstChildWhichIsA("BasePart", true)
                if anyPart then
                    return anyPart
                end
            end
        end
        local worldSpawns = workspace:FindFirstChild("Spawns")
        if worldSpawns and type(worldSpawns.FindFirstChildWhichIsA) == "function" then
            local spawn = worldSpawns:FindFirstChildWhichIsA("SpawnLocation")
                or worldSpawns:FindFirstChildWhichIsA("BasePart")
            if spawn then
                return spawn
            end
        end
        if type(workspace.FindFirstChildWhichIsA) == "function" then
            return workspace:FindFirstChildWhichIsA("SpawnLocation", true)
        end
        return nil
    end

    local function teleportToLobby()
        local spawn = findLobbySpawn()
        local character = LocalPlayer.Character
        if spawn and character then
            moveCharacterTo(character, spawn.CFrame + Vector3.new(0, 3, 0))
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

    local function grabDroppedGun()
        local gunDrop = findDroppedGun()
        if gunDrop and LocalPlayer.Character then
            touchDroppedGun(gunDrop)
        else
            notify("No dropped gun was found.")
        end
    end

    local teleport = state.framework:GetModule("Teleport")
    assert(teleport, "MM2 extends the universal Teleport module")
    for _, id in ipairs({"GetGunkey", "Playername"}) do
        local key = "Universal.ClickTeleport." .. id
        if configData.values[key] == nil then configData.values[key] = configData.values["MM2.Teleport." .. id] end
    end
    local autoKey = "Universal.ClickTeleport.AutoGetGun"
    if configData.states[autoKey] == nil then configData.states[autoKey] = configData.states["MM2.Teleport.AutoGetGun"] end
    local show = {Option = "Destination", Values = {"MM2"}}
    teleport:CreateButton({Name = "Teleport to Map", Show = show, Function = teleportToMap})
    teleport:CreateButton({Name = "Teleport to Lobby", Show = show, Function = teleportToLobby})
    teleport:CreateTextBox({Name = "Player name", Default = "", Show = show,
        Function = function(value) teleportTargetName = value end})
    teleport:CreateButton({Name = "Teleport to Player", Show = show, Function = teleportToPlayer})
    teleport:CreateButton({Name = "Get Gun", Show = show, Function = grabDroppedGun})
    local key = teleport:CreateBind({Name = "Get Gun key", Default = mm2Settings.getGunKey, Show = show,
        Function = function(value) mm2Settings.getGunKey = value end})
    if state.bindMobileActionPlacement and key.Object then
        state.bindMobileActionPlacement(key.Object, "MM2GetGun", "GUN", grabDroppedGun)
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
                task.spawn(grabDroppedGun)
            end
        end
    )
    teleport:CreateToggle({Name = "Auto Get Gun", Default = false, Show = show, Function = toggleAutoGetGun})

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
