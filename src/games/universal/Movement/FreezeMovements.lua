export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "FreezeMovements",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addCycleOption: any = host.addCycleOption
    local addInformationOption: any = host.addInformationOption
    local freezeSettings = {mode = "Anchor"}
    local FreezeFeature: any = nil
    local originalFreezeState = setmetatable({}, {__mode = "k"})
    -- Animation modes (Freeze Emotes / Glitch Animations) never touch
    -- WalkSpeed; they only drive the local Animator, which replicates to
    -- everyone else automatically because we own the character.
    local stickyEmoteTracks: {any} = {}

    local function getAnimator(humanoid: any): any
        local animator: any = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if not animator and humanoid and humanoid.Parent then
            local character: any = humanoid.Parent
            animator = character and character:FindFirstChildOfClass("Animator", true)
        end
        return animator
    end

    local function clearStickyEmoteTracks(): ()
        stickyEmoteTracks = {}
    end

    local function freezeEmotesTick(humanoid: any): ()
        -- Walk while an emote plays: the default Animate script stops an
        -- emote track the moment the character moves - here every emote
        -- (Action priority) track is remembered and replayed, so dances
        -- and poses keep playing while the player walks around freely.
        local animator: any = getAnimator(humanoid)
        if not animator then
            return
        end
        local okTracks: boolean, tracks: any = pcall(function(): any
            return animator:GetPlayingAnimationTracks()
        end)
        if not okTracks or type(tracks) ~= "table" then
            return
        end
        local seen: {[any]: boolean} = {}
        for _, track: any in ipairs(tracks) do
            if track
                and track.IsPlaying
                and track.Priority == Enum.AnimationPriority.Action then
                seen[track] = true
                if #stickyEmoteTracks == 0 or stickyEmoteTracks[1] ~= track then
                    stickyEmoteTracks = {track}
                end
            end
        end
        for index: number = #stickyEmoteTracks, 1, -1 do
            local track: any = stickyEmoteTracks[index]
            if not track or seen[track] then
                table.remove(stickyEmoteTracks, index)
            end
        end
        if #stickyEmoteTracks > 0 then
            local character: any = humanoid.Parent
            local moving: boolean = character ~= nil
                and character.PrimaryPart ~= nil
                and character.PrimaryPart.AssemblyLinearVelocity.Magnitude > 1
            if moving then
                for _, track: any in ipairs(stickyEmoteTracks) do
                    pcall(function(): ()
                        if not track.IsPlaying then
                            track:Play(0.1)
                        end
                    end)
                end
            end
        end
    end

    local function glitchAnimationsTick(humanoid: any): ()
        -- Glitch Animations: restarting the live movement tracks every
        -- frame makes the character visibly twitch/jitter - onlookers see
        -- the rig stutter in place while it keeps moving.
        local animator: any = getAnimator(humanoid)
        if not animator then
            return
        end
        local okTracks: boolean, tracks: any = pcall(function(): any
            return animator:GetPlayingAnimationTracks()
        end)
        if not okTracks or type(tracks) ~= "table" then
            return
        end
        for _, track: any in ipairs(tracks) do
            if track and track.IsPlaying then
                pcall(function(): ()
                    track:Play(0.05)
                end)
            end
        end
    end

    local function restoreFreezeMovements()
        for humanoid, original in pairs(originalFreezeState) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = original.walkSpeed
                humanoid.JumpPower = original.jumpPower
                humanoid.AutoRotate = original.autoRotate
                if original.root and original.root.Parent then
                    original.root.Anchored = original.rootAnchored
                end
            end
        end
        originalFreezeState = setmetatable({}, {__mode = "k"})
    end

    local function toggleFreezeMovements(enabled)
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()

        if not enabled then
            if FreezeFeature then
                FreezeFeature:SetStatus(nil)
            end
            return
        end

        clearStickyEmoteTracks()
        FreezeFeature:SetStatus(freezeSettings.mode)
        featureConnections.FreezeMovements = TaskManager:Connect(function()
            local _, humanoid, root = getCharacterParts()
            if not humanoid then
                return
            end

            if freezeSettings.mode == "Freeze Emotes" then
                freezeEmotesTick(humanoid)
                return
            elseif freezeSettings.mode == "Glitch Animations" then
                glitchAnimationsTick(humanoid)
                return
            end

            if not root then
                return
            end

            if not originalFreezeState[humanoid] then
                originalFreezeState[humanoid] = {
                    walkSpeed = humanoid.WalkSpeed,
                    jumpPower = humanoid.JumpPower,
                    autoRotate = humanoid.AutoRotate,
                    root = root,
                    rootAnchored = root.Anchored,
                }
            end

            local original = originalFreezeState[humanoid]
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.AutoRotate = false
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.Anchored = freezeSettings.mode == "Anchor"
                and true
                or original.rootAnchored
        end)
    end

    FreezeFeature = createUniversalFeature(
        "Freeze Movements",
        "Prevent the local character from moving",
        1,
        toggleFreezeMovements,
        {
            categoryName = "Movement",
            configKey = "Movement.FreezeMovements",
        }
    )
    addCycleOption(
        FreezeFeature,
        "Freeze mode",
        {"Anchor", "Humanoid", "Freeze Emotes", "Glitch Animations"},
        1,
        function(value)
            freezeSettings.mode = value
            if FreezeFeature.enabled then
                FreezeFeature:SetStatus(value)
            end
        end
    )
    addInformationOption(
        FreezeFeature,
        "Anchor stops all physics; Humanoid only blocks character controls."
    )
    addInformationOption(
        FreezeFeature,
        "Freeze Emotes keeps emotes playing while you walk; Glitch Animations makes your character stutter."
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()
        clearStickyEmoteTracks()
    end
    Module.Initialized = true
    return FreezeFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
