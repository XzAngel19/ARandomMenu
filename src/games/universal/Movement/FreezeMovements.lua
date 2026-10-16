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
    -- WalkSpeed or the root; they only drive the local Animator, which
    -- replicates to everyone else automatically because we own the rig.
    local stickyEmoteTracks: {any} = {}
    local emoteLastSeen: {[any]: number} = setmetatable({}, {__mode = "k"})

    local function getAnimator(humanoid: any): any
        local animator: any = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if not animator and humanoid and humanoid.Parent then
            local character: any = humanoid.Parent
            animator = character and character:FindFirstChildOfClass("Animator", true)
        end
        return animator
    end

    local emoteConnection: any = nil
    local watchedHumanoid: any = nil
    local emoteNames: {[string]: boolean} = {}
    local emoteIds: {[string]: boolean} = {}
    local restarted: {[any]: boolean} = setmetatable({}, {__mode = "k"})
    local lastGlitch: number = -math.huge

    local function clearStickyEmoteTracks(): ()
        if emoteConnection then emoteConnection:Disconnect() end
        emoteConnection = nil
        watchedHumanoid = nil
        for track in pairs(restarted) do
            pcall(function(): () track:Stop(0.15) end)
        end
        restarted = setmetatable({}, {__mode = "k"})
        emoteNames = {}
        emoteIds = {}
        stickyEmoteTracks = {}
        emoteLastSeen = setmetatable({}, {__mode = "k"})
    end

    local CLASSIC_EMOTES = {
        dance = true, dance1 = true, dance2 = true, dance3 = true,
        wave = true, point = true, cheer = true, laugh = true,
    }

    local function isEmoteTrack(track: any): boolean
        -- Action priority is also used by weapon attacks; it is NOT an
        -- emote identifier. Avoid substring matches such as SpinAttack.
        local function knownName(name: string): boolean
            local lower: string = string.lower(name)
            if emoteNames[lower] then return true end
            lower = lower:gsub("anim$", "")
            return CLASSIC_EMOTES[lower] == true
        end
        if knownName(tostring(track.Name or "")) then return true end
        local animation: any = track.Animation
        if typeof(animation) == "Instance" then
            if knownName(animation.Name) then return true end
            local id: string? = string.match(animation.AnimationId, "%d+")
            if id and emoteIds[id] then return true end
        end
        return false
    end

    local function freezeEmotesTick(humanoid: any, root: any): ()
        -- Walk while an emote plays: the default Animate script STOPS the
        -- emote track the moment the character starts moving. Remembered
        -- emote tracks are replayed while moving, so the dance keeps
        -- playing while you walk. A track the game actually ended (you
        -- stopped it from the menu, or jumped it away) is forgotten after
        -- a short grace period instead of being resurrected forever.
        local animator: any = getAnimator(humanoid)
        if not animator then
            return
        end
        if watchedHumanoid ~= humanoid then
            clearStickyEmoteTracks()
            watchedHumanoid = humanoid
            pcall(function(): ()
                local description: any = humanoid:GetAppliedDescription()
                for name: string, ids: any in pairs(description:GetEmotes()) do
                    emoteNames[string.lower(name)] = true
                    for _, id: any in ipairs(ids) do emoteIds[tostring(id)] = true end
                end
                description:Destroy()
            end)
            -- Catch tracks at start, before Animate can cancel them on movement.
            emoteConnection = animator.AnimationPlayed:Connect(function(track: any): ()
                if isEmoteTrack(track) and not emoteLastSeen[track] then
                    emoteLastSeen[track] = os.clock()
                    table.insert(stickyEmoteTracks, track)
                end
            end)
        end
        local okTracks: boolean, tracks: any = pcall(function(): any
            return animator:GetPlayingAnimationTracks()
        end)
        if not okTracks or type(tracks) ~= "table" then
            return
        end
        local playing: {[any]: boolean} = {}
        for _, track: any in ipairs(tracks) do
            if track and track.IsPlaying then
                playing[track] = true
                if not emoteLastSeen[track] and isEmoteTrack(track) then
                    table.insert(stickyEmoteTracks, track)
                    emoteLastSeen[track] = os.clock()
                end
                if emoteLastSeen[track] then
                    emoteLastSeen[track] = os.clock()
                end
            end
        end
        local moving: boolean = root ~= nil
            and root.AssemblyLinearVelocity.Magnitude > 1
        local now: number = os.clock()
        for index: number = #stickyEmoteTracks, 1, -1 do
            local track: any = stickyEmoteTracks[index]
            if not track then
                table.remove(stickyEmoteTracks, index)
            elseif playing[track] then
                emoteLastSeen[track] = now
            else
                local lastSeen: number = emoteLastSeen[track]
                if lastSeen == nil then
                    lastSeen = now
                    emoteLastSeen[track] = now
                end
                -- Absent from the playing list: the game stopped it. While
                -- you are moving that is the Animate script cancelling the
                -- emote - restart it. Standing still means it really ended.
                if moving and now - lastSeen < 1.5 then
                    pcall(function(): ()
                        if track.Looped then
                            track:Play(0.1)
                            restarted[track] = true
                        end
                    end)
                elseif now - lastSeen > 0.5 then
                    table.remove(stickyEmoteTracks, index)
                    emoteLastSeen[track] = nil
                end
            end
        end
    end

    local function glitchAnimationsTick(humanoid: any): ()
        -- Seek locomotion at a fixed cadence instead of calling Play every
        -- frame (which continually resets fades and also interrupts tools).
        local now: number = os.clock()
        if now - lastGlitch < 0.12 then return end
        lastGlitch = now
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
            if track and track.IsPlaying
                and (track.Priority == Enum.AnimationPriority.Movement
                    or track.Priority == Enum.AnimationPriority.Core) then
                pcall(function(): ()
                    track.TimePosition = 0
                end)
            end
        end
    end

    local function restoreFreezeMovements()
        for humanoid, original in pairs(originalFreezeState) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = original.walkSpeed
                humanoid.JumpPower = original.jumpPower
                humanoid.JumpHeight = original.jumpHeight
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
        clearStickyEmoteTracks()
        lastGlitch = -math.huge

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
                freezeEmotesTick(humanoid, root)
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
                    jumpHeight = humanoid.JumpHeight,
                    autoRotate = humanoid.AutoRotate,
                    root = root,
                    rootAnchored = root.Anchored,
                }
            end

            local original = originalFreezeState[humanoid]
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.JumpHeight = 0
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
            if FreezeFeature and FreezeFeature.enabled then
                -- Switching modes re-applies the feature: the previous
                -- mode is fully undone first (Anchor had left the root
                -- anchored with WalkSpeed 0 - "no puedo caminar") and the
                -- new mode starts clean.
                toggleFreezeMovements(false)
                toggleFreezeMovements(true)
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
