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
    local predictionMath: any = core.predictionMath

    type KnifeRuntimeState = {
        masterEnabled: boolean,
        auraWanted: boolean,
        throwWanted: boolean,
        lastAuraSwing: number,
    }

    local knifeSettings: any = {
        aura = false,
        auraRange = 14,
    }
    state.mm2KnifeRuntime = {
        masterEnabled = false,
        auraWanted = false,
        throwWanted = false,
        lastAuraSwing = -math.huge,
    } :: KnifeRuntimeState

    local function getEffectiveRange(): number
        return knifeSettings.auraRange or 14
    end

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
        if os.clock() - state.mm2KnifeRuntime.lastAuraSwing < 0.86 then return end
        local knife: Tool?, localRoot: BasePart? = canUseEquippedKnife()
        if not knife or not localRoot then
            return
        end

        local currentRange: number = getEffectiveRange()
        local target: Player? =
            findKnifeAuraTarget(localRoot, currentRange)
        local targetCharacter: Model? = target and target.Character
        local targetRoot: BasePart? = targetCharacter
            and targetCharacter:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        if not target
            or not targetCharacter
            or not targetRoot
            or (targetRoot.Position - localRoot.Position).Magnitude
                > currentRange
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
                or currentCharacter ~= targetCharacter
                or not isValidKnifeTarget(target)
                or not currentRoot
                or not currentHandle
                or not currentHandle:IsA("BasePart")
                or (currentRoot.Position - currentLocalRoot.Position).Magnitude
                    > getEffectiveRange() then
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
        if not knifeSettings.aura or not state.mm2KnifeRuntime.masterEnabled then
            return
        end

        local elapsed: number = 0
        featureConnections.MM2KnifeController =
            TaskManager:Connect(function(deltaTime: number): ()
                local due: boolean
                due, elapsed = predictionMath.sampleDue(elapsed, deltaTime, 20)
                if due then processKnifeAura() end
            end)
    end

    local function toggleKnifeAura(enabled: boolean): ()
        knifeSettings.aura = enabled
        state.mm2KnifeRuntime.auraWanted = enabled
        state.mm2KnifeRuntime.lastAuraSwing = -math.huge
        refreshKnifeController()
    end

    local aura: any = state.framework and state.framework:GetModule("KillAura")
    assert(aura, "MM2 Knife requires the existing KillAura module")
    local wasEnabled: boolean = aura.Enabled
    if type(configData) == "table" and not configData.values["MM2.Knife.MigratedToKillAura"] then
        for _, label: string in ipairs({"KnifeAura"}) do
            local old: any = configData.states["MM2.Knife." .. label]
            local key: string = "Universal.KillAura." .. label
            if configData.states[key] == nil and old ~= nil then configData.states[key] = old end
        end
        for _, pair in ipairs({
            {"MM2.Knife.AuraRange", "Universal.KillAura.AuraRange"},
            {"Shortcut.MM2Knife", "Shortcut.UniversalKillAura"},
        }) do
            if configData.values[pair[2]] == nil then configData.values[pair[2]] = configData.values[pair[1]] end
        end
        wasEnabled = wasEnabled or configData.states["MM2.Knife"] == true
        configData.values["MM2.Knife.MigratedToKillAura"] = true
        if type(queueConfigSave) == "function" then queueConfigSave() end
    end
    if wasEnabled then aura:Toggle(false) end
    local KnifeFeature: any = aura.Feature
    local originalDescription: string = KnifeFeature.description
    local originalSearch: string = KnifeFeature.searchText
    KnifeFeature.description = "MM2 melee combat: Knife Aura stabs with your held knife. Knife Throw belongs to SilentAIM."
    KnifeFeature.tooltipText = KnifeFeature.description
    KnifeFeature.searchText = "killaura combat mm2 knife aura range"
    aura.CombatAdapter = function(enabled: boolean): ()
        state.mm2KnifeRuntime.masterEnabled = enabled
        refreshKnifeController()
        aura:SetStatus(enabled and "Knife" or nil)
    end
    -- Generic melee controls do not describe the MM2 remote-based controller.
    aura.OptionFilter = function(name: string): boolean
        return name == "Knife Aura" or name == "Aura Range"
    end
    aura:RefreshVisibility()
    state.mm2KnifeAuraModule = aura
    state.mm2KnifeFeature = KnifeFeature

    aura:CreateToggle({Name = "Knife Aura", Default = true, Function = toggleKnifeAura,
        Tooltip = "MM2 stabs with your equipped knife while KillAura is ON."})
    aura:CreateSlider({Name = "Aura Range", Min = 7, Max = 30, Default = 14,
        Show = {Option = "Knife Aura", Values = {true}},
        Function = function(value: number): () knifeSettings.auraRange = value end})
    if wasEnabled then aura:Toggle(true) end

    activeCleanup = function(): ()
        if aura.Enabled then aura:Toggle(false) end
        toggleKnifeAura(false)
        state.mm2KnifeRuntime.masterEnabled = false
        state.mm2KnifeFeature = nil
        state.mm2KnifeAuraModule = nil
        aura.CombatAdapter = nil
        KnifeFeature.description = originalDescription
        KnifeFeature.tooltipText = originalDescription
        KnifeFeature.searchText = originalSearch
        -- If the adapter is detached before the whole UI is destroyed, do
        -- not expose stale MM2 actions beside the generic controls.
        aura.OptionFilter = function(name: string): boolean
            return name ~= "Knife Aura" and name ~= "Aura Range"
        end
        aura:RefreshVisibility()
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
