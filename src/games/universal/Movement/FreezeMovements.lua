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

    local function clearStickyEmoteTracks(): ()
        stickyEmoteTracks = {}
        emoteLastSeen = setmetatable({}, {__mode = "k"})
    end

    local EMOTE_NAME_KEYWORDS = {
        "dance", "wave", "point", "cheer", "laugh", "emote", "spin", "tutorial",
    }

    local function isEmoteTrack(track: any): boolean
        -- The Roblox emote menu (the dancing emotes) plays its animations
        -- through the local Animate script at Action priority. Some games
        -- leave them at Core/Idle, so also accept the classic emote names
        -- (Dance1..3, Wave, Point, Cheer, Laugh...).
        local priority: any = nil
        pcall(function(): ()
            priority = track.Priority
        end)
        if priority == Enum.AnimationPriority.Action
            or priority == Enum.AnimationPriority.Action2
            or priority == Enum.AnimationPriority.Action3
            or priority == Enum.AnimationPriority.Action4 then
            return true
        end
        local label: string = string.lower(tostring(track.Name or ""))
        local animation: any = track.Animation
        if typeof(animation) == "Instance" then
            label = label .. " " .. string.lower(tostring(animation.Name or ""))
        end
        for _, keyword: string in ipairs(EMOTE_NAME_KEYWORDS) do
            if string.find(label, keyword, 1, true) then
                return true
            end
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
                        track:Play(0.1)
                    end)
                elseif now - lastSeen > 0.5 then
                    table.remove(stickyEmoteTracks, index)
                    emoteLastSeen[track] = nil
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
