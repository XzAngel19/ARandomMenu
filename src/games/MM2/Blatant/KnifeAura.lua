local Module = {
    Name = "MM2 Knife Aura",
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
    assert(type(core) == "table", "MM2 Knife Aura requires the MM2 core module")
    Module.Runtime = runtime
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local trajectoryCalibration: any = core.trajectoryCalibration

    type KnifeRuntimeState = {
        lastAuraSwing: number,
    }

    local knifeSettings: KnifeSettings = {
        aura = false,
        auraRange = 14,
    }
    state.mm2KnifeRuntime = {
        lastAuraSwing = -math.huge,
    } :: KnifeRuntimeState

    local function getEquippedWeapon(name: string, _tag: string): Tool?
        return getPlayerWeapon(LocalPlayer, name, true)
    end

    local function canUseEquippedKnife(): (Tool?, BasePart?)
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        local root: BasePart? = character
            and character:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        local knife: Tool? = getEquippedWeapon("Knife", "Weapon_Knife")
        if not character
            or not humanoid
            or humanoid.Health <= 0
            or not root
            or not knife
            or knife:GetAttribute("Disabled") == true
            or getPlayerRole(LocalPlayer) ~= "Murderer" then
            return nil, nil
        end
        return knife, root
    end

    local function isValidKnifeTarget(player: Player): boolean
        if player == LocalPlayer
            or isProtectedTarget(player)
            or not isPlayerAlive(player)
            or getPlayerRole(player) == "Murderer" then
            return false
        end
        return player.Character ~= nil
            and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
    end

    local function findKnifeAuraTarget(
        localRoot: BasePart,
        maxDistance: number
    ): Player?
        local closest: Player? = nil
        local closestDistance: number = maxDistance
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isValidKnifeTarget(player) then
                local targetRoot: BasePart? = player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart")
                    :: BasePart?
                if targetRoot then
                    local distance: number =
                        (targetRoot.Position - localRoot.Position).Magnitude
                    if distance <= closestDistance then
                        closest = player
                        closestDistance = distance
                    end
                end
            end
        end
        return closest
    end

    local function processKnifeAura(): ()
        local knife: Tool?, localRoot: BasePart? = canUseEquippedKnife()
        if not knife or not localRoot then
            return
        end

        local target: Player? =
            findKnifeAuraTarget(localRoot, knifeSettings.auraRange)
        local targetCharacter: Model? = target and target.Character
        local targetRoot: BasePart? = targetCharacter
            and targetCharacter:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        if not target
            or not targetCharacter
            or not targetRoot
            or (targetRoot.Position - localRoot.Position).Magnitude
                > knifeSettings.auraRange
            or os.clock() - state.mm2KnifeRuntime.lastAuraSwing < 0.86 then
            return
        end

        local handle: BasePart? = knife:FindFirstChild("Handle") :: BasePart?
        if not handle or not handle:IsA("BasePart") then
            return
        end

        state.mm2KnifeRuntime.lastAuraSwing = os.clock()
        local events: Instance? = knife:FindFirstChild("Events")
        local handleTouched: Instance? = events
            and events:FindFirstChild("HandleTouched")
        knife:Activate()
        task.delay(0.025, function(): ()
            local currentKnife: Tool?, currentLocalRoot: BasePart? =
                canUseEquippedKnife()
            local currentCharacter: Model? = target.Character
            local currentRoot: BasePart? = currentCharacter
                and currentCharacter:FindFirstChild("HumanoidRootPart")
                :: BasePart?
            local currentHandle: BasePart? =
                knife:FindFirstChild("Handle") :: BasePart?
            if not knifeSettings.aura
                or currentKnife ~= knife
                or not currentLocalRoot
                or not currentCharacter
                or not currentRoot
                or not currentHandle
                or not currentHandle:IsA("BasePart")
                or (currentRoot.Position - currentLocalRoot.Position).Magnitude
                    > knifeSettings.auraRange then
                return
            end

            if handleTouched and handleTouched:IsA("RemoteEvent") then
                handleTouched:FireServer(currentRoot)
            elseif type(state.fireTouchInterest) == "function" then
                pcall(state.fireTouchInterest, currentHandle, currentRoot, 0)
                pcall(state.fireTouchInterest, currentHandle, currentRoot, 1)
            end
            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "stab",
                toolName = "Knife",
                originPos = currentLocalRoot.Position,
                aimPos = currentRoot.Position,
                target = target,
            })
        end)
    end

    local function refreshKnifeController(): ()
        disconnectFeatureConnection("MM2KnifeVirtualHitbox")
        disconnectFeatureConnection("MM2KnifeAura")
        disconnectFeatureConnection("MM2KnifeController")
        if not knifeSettings.aura then
            return
        end

        local elapsed: number = 0
        featureConnections.MM2KnifeController =
            TaskManager:Connect(function(deltaTime: number): ()
                elapsed += deltaTime
                if elapsed < 0.05 then
                    return
                end
                elapsed %= 0.05
                processKnifeAura()
            end)
    end

    local function toggleKnifeAura(enabled: boolean): ()
        knifeSettings.aura = enabled
        state.mm2KnifeRuntime.lastAuraSwing = -math.huge
        refreshKnifeController()
    end

    local KnifeFeature = createUniversalFeature(
        "Knife Aura",
        "Stabs the nearest valid target in range through the game's own HandleTouched",
        6,
        toggleKnifeAura,
        {
            categoryName = "Blatant",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addNumberOption(KnifeFeature, "Range", 14, 7, 30, function(
        value: number
    ): ()
        knifeSettings.auraRange = value
    end)

    activeCleanup = function(): ()
        toggleKnifeAura(false)
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
