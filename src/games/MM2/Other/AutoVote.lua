local Module = {
    Name = "MM2 Auto Vote",
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
    assert(type(core) == "table", "MM2 Auto Vote requires the MM2 core module")
    Module.Runtime = runtime

    local TICK_INTERVAL: number = 0.10
    local MAP_REFRESH_INTERVAL: number = 0.50
    local VOTE_HOLD_Before_RESET: number = 0.22

    local mapChoices: {string} = {"Map 1", "Map 2", "Map 3"}
    local selectedSlot: number = 1
    local selectedMapName: string = mapChoices[1]
    local selectMapButton: TextButton? = nil
    local AutoVoteFeature: any = nil

    local cachedLobby: Instance? = nil
    local lastLobbyCheckAt: number = -math.huge
    local lastMapRefreshAt: number = -math.huge
    local savedDetectorCFrames: {[BasePart]: CFrame} = {}
    local roundBlockingVote: boolean = false
    local lastBillboardVotingState: boolean = false

    local function trim(s: string): string
        return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
    end

    local function isValidMapTitle(title: string?): boolean
        if type(title) ~= "string" then
            return false
        end
        local clean = trim(title)
        if clean == "" then
            return false
        end
        local upper = string.upper(clean)
        if upper == "MAP NAME" or upper == "LOADING" or upper == "NONE" then
            return false
        end
        return true
    end

    local function findLobbyModel(): Instance?
        local now: number = os.clock()
        if cachedLobby and cachedLobby.Parent == workspace and now - lastLobbyCheckAt < 1.0 then
            return cachedLobby
        end
        lastLobbyCheckAt = now

        for _, name: string in ipairs({"RegularLobby", "Lobby", "MainLobby"}) do
            local candidate: Instance? = workspace:FindFirstChild(name)
            if candidate and (
                candidate:FindFirstChild("VotePad1")
                or candidate:FindFirstChild("VotePads")
                or candidate:FindFirstChild("VoteIcons")
            ) then
                cachedLobby = candidate
                return candidate
            end
        end

        local okChildren: boolean, children: any = pcall(function(): any
            return workspace:GetChildren()
        end)
        if okChildren and type(children) == "table" then
            for _, child: Instance in ipairs(children) do
                if child:IsA("Model") or child:IsA("Folder") then
                    if child:FindFirstChild("VotePad1")
                        or child:FindFirstChild("VotePads")
                        or child:FindFirstChild("VoteIcons") then
                        cachedLobby = child
                        return child
                    end
                end
            end
        end

        cachedLobby = nil
        return nil
    end

    -- Read the map name displayed on billboard slot i (1..3) from RegularLobby.
    local function readSlotMapName(lobby: Instance?, slot: number): string?
        if not lobby then
            return nil
        end
        local padModel: Instance? = lobby:FindFirstChild("VotePad" .. tostring(slot))
        if padModel then
            local voteInfoGui: Instance? = padModel:FindFirstChild("VoteInfoGui")
            local container: Instance? = voteInfoGui and voteInfoGui:FindFirstChild("Container")
            local mapLabel: Instance? = container and container:FindFirstChild("MapName")
            if mapLabel and mapLabel:IsA("TextLabel") then
                local text: string = (mapLabel :: TextLabel).Text
                if isValidMapTitle(text) then
                    return trim(text)
                end
            end
        end

        local voteIcons: Instance? = lobby:FindFirstChild("VoteIcons")
        local iconPart: Instance? = voteIcons and voteIcons:FindFirstChild("VotePad" .. tostring(slot))
        if iconPart then
            local mapInfo: Instance? = iconPart:FindFirstChild("MapInfo")
            local surface: Instance? = mapInfo and mapInfo:FindFirstChild("Surface")
            local frame: Instance? = surface and surface:FindFirstChildWhichIsA("Frame")
            local mapLabel: Instance? = frame and frame:FindFirstChild("MapName")
            if mapLabel and mapLabel:IsA("TextLabel") then
                local text: string = (mapLabel :: TextLabel).Text
                if isValidMapTitle(text) then
                    return trim(text)
                end
            end
            local mapObj: Instance? = iconPart:FindFirstChild("Map")
            if mapObj and mapObj:IsA("ObjectValue") then
                local val: Instance? = (mapObj :: ObjectValue).Value
                if val and isValidMapTitle(val.Name) then
                    return trim(val.Name)
                end
            end
        end

        return nil
    end

    -- Read the current vote count on slot i (1..3).
    local function readSlotVoteCount(lobby: Instance?, slot: number): number?
        if not lobby then
            return nil
        end
        local voteIcons: Instance? = lobby:FindFirstChild("VoteIcons")
        local iconPart: Instance? = voteIcons and voteIcons:FindFirstChild("VotePad" .. tostring(slot))
        if iconPart then
            local votesVal: Instance? = iconPart:FindFirstChild("Votes")
            if votesVal and votesVal:IsA("IntValue") then
                return (votesVal :: IntValue).Value
            end
        end
        local padModel: Instance? = lobby:FindFirstChild("VotePad" .. tostring(slot))
        if padModel then
            local voteInfoGui: Instance? = padModel:FindFirstChild("VoteInfoGui")
            local container: Instance? = voteInfoGui and voteInfoGui:FindFirstChild("Container")
            local votesLabel: Instance? = container and container:FindFirstChild("Votes")
            if votesLabel and votesLabel:IsA("TextLabel") then
                local numStr: string? = string.match((votesLabel :: TextLabel).Text, "(%d+)")
                if numStr then
                    return tonumber(numStr)
                end
            end
        end
        return nil
    end

    -- Refresh the 3 map choices in-place from the lobby billboard so the
    -- "Select Map" dropdown always displays the 3 maps on the board.
    local function refreshMapChoices(force: boolean?): ()
        local now: number = os.clock()
        if not force and now - lastMapRefreshAt < MAP_REFRESH_INTERVAL then
            return
        end
        lastMapRefreshAt = now

        local lobby: Instance? = findLobbyModel()
        if not lobby then
            return
        end

        local changed: boolean = false
        for slot: number = 1, 3 do
            local title: string? = readSlotMapName(lobby, slot)
            local fallback: string = "Map " .. tostring(slot)
            local nextLabel: string = title or mapChoices[slot] or fallback
            if mapChoices[slot] ~= nextLabel then
                mapChoices[slot] = nextLabel
                changed = true
            end
        end

        -- If the user previously selected a specific map name that is present
        -- in one of the 3 slots, track that slot; otherwise follow selectedSlot.
        if isValidMapTitle(selectedMapName) then
            local matchedSlot: number? = nil
            local targetLower: string = string.lower(selectedMapName)
            for slot: number = 1, 3 do
                if string.lower(mapChoices[slot]) == targetLower then
                    matchedSlot = slot
                    break
                end
            end
            if matchedSlot then
                selectedSlot = matchedSlot
            end
        end

        selectedSlot = math.clamp(selectedSlot, 1, 3)
        selectedMapName = mapChoices[selectedSlot]

        if changed and selectMapButton then
            pcall(function(): ()
                selectMapButton.Text = mapChoices[selectedSlot]
            end)
        end
    end

    -- Resolve the wooden pad detector parts for slot (1..3):
    -- RegularLobby.VotePads.Detector{slot} and RegularLobby.VotePad{slot}.Pad
    local function getSlotDetectorParts(lobby: Instance?, slot: number): {BasePart}
        local parts: {BasePart} = {}
        if not lobby then
            return parts
        end

        local votePads: Instance? = lobby:FindFirstChild("VotePads")
        if votePads then
            local detector: Instance? = votePads:FindFirstChild("Detector" .. tostring(slot))
            if detector and detector:IsA("BasePart") then
                parts[#parts + 1] = detector :: BasePart
            end
        end

        local padModel: Instance? = lobby:FindFirstChild("VotePad" .. tostring(slot))
        if padModel then
            local padPart: Instance? = padModel:FindFirstChild("Pad")
            if padPart and padPart:IsA("BasePart") then
                parts[#parts + 1] = padPart :: BasePart
            end
        end

        return parts
    end

    local function rememberDetectorPart(part: BasePart): ()
        if savedDetectorCFrames[part] then
            return
        end
        local ok: boolean, cf: any = pcall(function(): any
            return part.CFrame
        end)
        if ok and cf then
            savedDetectorCFrames[part] = cf
        end
    end

    local function restoreAllDetectorParts(): ()
        for part, cf in pairs(savedDetectorCFrames) do
            if part and part.Parent then
                pcall(function(): ()
                    part.CFrame = cf
                end)
            end
        end
        table.clear(savedDetectorCFrames)
    end

    -- Check whether the lobby voting billboards are currently enabled.
    -- In MM2 (place, source.rbxlx), VotePad{1..3}.VoteInfoGui.Enabled,
    -- VotePad{1..3}.MapInfoGui.Enabled, and VoteIcons.VotePad{1..3}.Voting.Value
    -- are true ONLY during the voting intermission and turn false as soon as
    -- voting ends.
    local function areVotingBillboardsActive(lobby: Instance?): boolean
        if not lobby then
            return false
        end

        for slot: number = 1, 3 do
            local padModel: Instance? = lobby:FindFirstChild("VotePad" .. tostring(slot))
            if padModel then
                local voteGui: Instance? = padModel:FindFirstChild("VoteInfoGui")
                if voteGui and voteGui:IsA("SurfaceGui") and (voteGui :: SurfaceGui).Enabled == true then
                    return true
                end
                local mapGui: Instance? = padModel:FindFirstChild("MapInfoGui")
                if mapGui and mapGui:IsA("SurfaceGui") and (mapGui :: SurfaceGui).Enabled == true then
                    return true
                end
            end

            local voteIcons: Instance? = lobby:FindFirstChild("VoteIcons")
            local iconPart: Instance? = voteIcons and voteIcons:FindFirstChild("VotePad" .. tostring(slot))
            if iconPart then
                local votingFlag: Instance? = iconPart:FindFirstChild("Voting")
                if votingFlag and votingFlag:IsA("BoolValue") and (votingFlag :: BoolValue).Value == true then
                    return true
                end
                local surface: Instance? = iconPart:FindFirstChild("Surface")
                if surface and surface:IsA("SurfaceGui") and (surface :: SurfaceGui).Enabled == true then
                    return true
                end
                local mapInfo: Instance? = iconPart:FindFirstChild("MapInfo")
                local infoSurface: Instance? = mapInfo and mapInfo:FindFirstChild("Surface")
                if infoSurface and infoSurface:IsA("SurfaceGui") and (infoSurface :: SurfaceGui).Enabled == true then
                    return true
                end
            end
        end

        return false
    end

    -- Strict check: returns true ONLY while the lobby voting intermission is
    -- actively open. Returns false the instant voting ends or a map/round starts.
    local function isVotingIntermissionActive(): boolean
        local lobby: Instance? = findLobbyModel()
        local billboardsOn: boolean = areVotingBillboardsActive(lobby)

        -- If the voting billboards just turned on for a new intermission, clear
        -- any previous round lock.
        if billboardsOn and not lastBillboardVotingState then
            roundBlockingVote = false
        end
        lastBillboardVotingState = billboardsOn

        if not billboardsOn then
            return false
        end
        if roundBlockingVote then
            return false
        end

        if type(core.isRoundLifecycleActive) == "function"
            and core.isRoundLifecycleActive() == true then
            return false
        end

        if type(core.findMM2Map) == "function"
            and core.findMM2Map() ~= nil then
            return false
        end

        local timerPart: Instance? = workspace:FindFirstChild("RoundTimerPart")
        if timerPart then
            local okTime: boolean, roundTime: any = pcall(function(): any
                return timerPart:GetAttribute("Time")
            end)
            if okTime and type(roundTime) == "number" and roundTime > 0 then
                return false
            end
        end

        return true
    end

    local function resolveTargetSlot(lobby: Instance?): number
        refreshMapChoices(false)
        if lobby and isValidMapTitle(selectedMapName) then
            local targetLower: string = string.lower(selectedMapName)
            for slot: number = 1, 3 do
                local nameOnBoard: string? = readSlotMapName(lobby, slot)
                if nameOnBoard and string.lower(nameOnBoard) == targetLower then
                    selectedSlot = slot
                    return slot
                end
            end
        end
        return math.clamp(selectedSlot, 1, 3)
    end

    -- Touch the wooden vote pad detectors without moving the local character.
    local function pulseVotePad(root: BasePart, detectors: {BasePart}): ()
        local fireTouch: any = state.fireTouchInterest
        local rootCF: CFrame? = root.CFrame
        for _, part: BasePart in ipairs(detectors) do
            rememberDetectorPart(part)
            pcall(function(): ()
                part.CanCollide = false
                if rootCF then
                    part.CFrame = rootCF
                end
            end)
            if type(fireTouch) == "function" then
                pcall(fireTouch, root, part, 0)
                pcall(fireTouch, root, part, 1)
            end
        end
    end

    local function resetLocalCharacter(character: Model, humanoid: Humanoid): ()
        pcall(function(): ()
            humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        end)
        pcall(function(): ()
            humanoid.Health = 0
        end)
        pcall(function(): ()
            if humanoid.Health > 0 then
                character:BreakJoints()
            end
        end)
    end

    local lastStatus: string? = nil
    local function setStatus(text: string?): ()
        if text == lastStatus then
            return
        end
        lastStatus = text
        if AutoVoteFeature then
            AutoVoteFeature:SetStatus(text)
        end
    end

    local function connectGameplayRemotes(): ()
        local okRs: boolean, rs: any = pcall(function(): any
            return game:GetService("ReplicatedStorage")
        end)
        if not okRs or not rs then
            return
        end
        local remotes: Instance? = rs:FindFirstChild("Remotes")
        local gameplay: Instance? = remotes and remotes:FindFirstChild("Gameplay")
        if not gameplay then
            return
        end

        for _, stopName: string in ipairs({
            "LoadingMap",
            "RoleSelect",
            "ShowRoleSelect",
            "ShowRoleSelectNew",
            "RoundStart",
            "CoinsStarted",
        }) do
            local rem: Instance? = gameplay:FindFirstChild(stopName)
            if rem and rem:IsA("RemoteEvent") then
                local key: string = "MM2AutoVoteStop_" .. stopName
                disconnectFeatureConnection(key)
                featureConnections[key] = (rem :: RemoteEvent).OnClientEvent:Connect(function(): ()
                    roundBlockingVote = true
                    restoreAllDetectorParts()
                end)
            end
        end

        for _, endName: string in ipairs({
            "RoundEndFade",
            "VictoryScreen",
            "GameOver",
        }) do
            local rem: Instance? = gameplay:FindFirstChild(endName)
            if rem and rem:IsA("RemoteEvent") then
                local key: string = "MM2AutoVoteEnd_" .. endName
                disconnectFeatureConnection(key)
                featureConnections[key] = (rem :: RemoteEvent).OnClientEvent:Connect(function(): ()
                    roundBlockingVote = false
                    refreshMapChoices(true)
                end)
            end
        end
    end

    local function disconnectAllAutoVoteConnections(): ()
        disconnectFeatureConnection("MM2AutoVote")
        for key in pairs(featureConnections) do
            if string.sub(key, 1, 11) == "MM2AutoVote" then
                disconnectFeatureConnection(key)
            end
        end
    end

    local function toggleAutoVote(enabled: boolean): ()
        disconnectAllAutoVoteConnections()
        restoreAllDetectorParts()

        if not enabled then
            setStatus(nil)
            return
        end

        refreshMapChoices(true)
        connectGameplayRemotes()

        local lastTickAt: number = -math.huge
        local currentChar: Model? = nil
        local firstTouchAt: number = 0
        local voteCountBeforeTouch: number? = nil
        local resetSentForChar: boolean = false

        local function autoVoteTick(): ()
            local now: number = os.clock()
            if now - lastTickAt < TICK_INTERVAL then
                return
            end
            lastTickAt = now

            refreshMapChoices(false)

            -- Stop immediately if the voting intermission is not active or has ended!
            if not isVotingIntermissionActive() then
                restoreAllDetectorParts()
                firstTouchAt = 0
                resetSentForChar = false
                setStatus("Waiting for vote · " .. tostring(mapChoices[selectedSlot] or "Map 1"))
                return
            end

            local lobby: Instance? = findLobbyModel()
            local slot: number = resolveTargetSlot(lobby)
            local targetMapLabel: string = mapChoices[slot] or ("Map " .. tostring(slot))
            local detectors: {BasePart} = getSlotDetectorParts(lobby, slot)
            if #detectors == 0 then
                setStatus("No vote pad")
                return
            end

            local character: Model? = LocalPlayer and LocalPlayer.Character
            if not character then
                restoreAllDetectorParts()
                return
            end
            local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
            local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if not root or not humanoid or humanoid.Health <= 0 then
                restoreAllDetectorParts()
                return
            end

            if character ~= currentChar then
                currentChar = character
                firstTouchAt = 0
                voteCountBeforeTouch = readSlotVoteCount(lobby, slot)
                resetSentForChar = false
            end

            -- Cast vote for this character life via firetouchinterest + detector overlap
            pulseVotePad(root, detectors)
            if firstTouchAt == 0 then
                firstTouchAt = now
            end

            local currentVotes: number? = readSlotVoteCount(lobby, slot)
            local voteIncremented: boolean = (
                currentVotes ~= nil
                and voteCountBeforeTouch ~= nil
                and currentVotes > voteCountBeforeTouch
            )

            setStatus(
                "Voting " .. targetMapLabel
                .. (currentVotes ~= nil and (" (" .. tostring(currentVotes) .. ")") or "")
            )

            -- Once this character life has cast its vote (either vote count incremented
            -- or VOTE_HOLD_Before_RESET elapsed), re-verify voting intermission is STILL
            -- active before resetting the character to vote again.
            if not resetSentForChar and (voteIncremented or (now - firstTouchAt >= VOTE_HOLD_Before_RESET)) then
                restoreAllDetectorParts()
                if isVotingIntermissionActive() then
                    resetSentForChar = true
                    resetLocalCharacter(character, humanoid)
                end
            end
        end

        featureConnections.MM2AutoVote = TaskManager:Connect(autoVoteTick)
        autoVoteTick()
    end

    -- Populate initial map names if already in the lobby
    pcall(refreshMapChoices, true)

    AutoVoteFeature = createUniversalFeature(
        "Auto Vote",
        "Detects the 3 maps on the lobby voting billboard, votes for your selected map via firetouchinterest without teleporting, and resets repeatedly until voting intermission ends.",
        7,
        toggleAutoVote,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoVoteFeature = AutoVoteFeature

    selectMapButton = addCycleOption(
        AutoVoteFeature,
        "Select Map",
        mapChoices,
        1,
        function(value: string): ()
            refreshMapChoices(false)
            selectedMapName = tostring(value)
            for slot: number = 1, 3 do
                if mapChoices[slot] == selectedMapName then
                    selectedSlot = slot
                    break
                end
            end
            if AutoVoteFeature and AutoVoteFeature.enabled then
                setStatus("Voting " .. tostring(mapChoices[selectedSlot] or selectedMapName))
            end
        end,
        "Select which of the 3 lobby billboard maps to vote for."
    )

    -- Refresh the 3 billboard map names whenever the user clicks "Select Map",
    -- even before Auto Vote is toggled ON.
    if selectMapButton and selectMapButton.MouseButton1Click then
        pcall(function(): ()
            selectMapButton.MouseButton1Click:Connect(function(): ()
                refreshMapChoices(true)
            end)
        end)
    end

    activeCleanup = function(): ()
        toggleAutoVote(false)
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
