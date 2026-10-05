export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Disguise",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function looksNumeric(text: string): boolean
    return string.match(text, "^%s*%d+%s*$") ~= nil
end

local function trimmed(text: string): string
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- Miniature Animate script for the local body double. The real character
-- keeps its own animations; the double copies the pose through these tracks.
local PUPPET_ANIMATIONS: {{key: string, field: string, priority: any}} = {
    {key = "idle", field = "IdleAnimation", priority = Enum.AnimationPriority.Idle},
    {key = "walk", field = "WalkAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "run", field = "RunAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "jump", field = "JumpAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "fall", field = "FallAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "climb", field = "ClimbAnimation", priority = Enum.AnimationPriority.Movement},
    {key = "swim", field = "SwimAnimation", priority = Enum.AnimationPriority.Movement},
}

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local spoofAvatar: any = context.services.spoofAvatar
    local currentWorkspace: Workspace = host.workspace or workspace

    local runtime: any = {
        busy = false,
        generation = 0,
        target = nil :: any?,
        puppet = nil :: Model?,
        puppetParts = {} :: {BasePart},
        puppetTracks = {} :: {[string]: AnimationTrack},
        puppetHidden = false,
        diedWatch = nil :: RBXScriptConnection?,
        originals = nil :: any?,
        applied = false,
    }

    local disguise: any

    local function currentCharacter(): Model?
        local character: Model? = localPlayer.Character
        if character and character.Parent then
            return character
        end
        return nil
    end

    local function currentHumanoid(): Humanoid?
        local character: Model? = currentCharacter()
        if not character then
            return nil
        end
        return (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
    end

    local function characterDescription(humanoid: Humanoid): HumanoidDescription?
        local existing: Instance? = humanoid:FindFirstChild("HumanoidDescription")
        if existing and existing:IsA("HumanoidDescription") then
            return existing :: HumanoidDescription
        end
        local ok: boolean, found: any = pcall(function(): any
            return (humanoid :: any).HumanoidDescription
        end)
        if ok and typeof(found) == "Instance" then
            return found :: HumanoidDescription
        end
        return nil
    end

    -- Client-side transparency: only this client stops seeing the real body.
    local hidingConnection: RBXScriptConnection? = nil

    local function hidePart(part: BasePart): ()
        if part.LocalTransparencyModifier ~= 1 then
            part.LocalTransparencyModifier = 1
        end
    end

    local function hideCharacter(character: Model): ()
        for _, descendant: Instance in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") then
                hidePart(descendant :: BasePart)
            end
        end
        if hidingConnection then
            return
        end
        hidingConnection = character.DescendantAdded:Connect(function(descendant: Instance): ()
            if descendant:IsA("BasePart") then
                hidePart(descendant :: BasePart)
            end
        end)
    end

    local function showCharacter(): ()
        if hidingConnection then
            pcall(function(): ()
                (hidingConnection :: RBXScriptConnection):Disconnect()
            end)
            hidingConnection = nil
        end
        local character: Model? = currentCharacter()
        if character then
            for _, descendant: Instance in ipairs((character :: Model):GetDescendants()) do
                if descendant:IsA("BasePart") then
                    (descendant :: BasePart).LocalTransparencyModifier = 0
                end
            end
        end
    end

    -- Capture the real avatar once: display name, emote wheel and animation
    -- ids, so everything can be restored exactly on disable.
    local function rememberOriginals(humanoid: Humanoid): ()
        if runtime.originals then
            return
        end
        local description: HumanoidDescription? = nil
        local ok: boolean, applied: any = pcall(function(): any
            return humanoid:GetAppliedDescription()
        end)
        if ok and typeof(applied) == "Instance" then
            description = applied :: HumanoidDescription
        end
        local emotes: any = {}
        local equippedNames: {string} = {}
        local wheel: HumanoidDescription? = characterDescription(humanoid)
        if wheel then
            local emotesOk: boolean, current: any = pcall(function(): any
                return (wheel :: HumanoidDescription):GetEmotes()
            end)
            if emotesOk and type(current) == "table" then
                emotes = current
            end
            local equippedOk: boolean, equipped: any = pcall(function(): any
                return (wheel :: HumanoidDescription):GetEquippedEmotes()
            end)
            if equippedOk and type(equipped) == "table" then
                for _, entry: any in ipairs(equipped) do
                    local name: string = tostring(type(entry) == "table" and entry.name or entry)
                    if name ~= "" then
                        table.insert(equippedNames, name)
                    end
                end
            end
        end
        runtime.originals = {
            displayName = humanoid.DisplayName,
            emotes = emotes,
            equippedNames = equippedNames,
            myDescription = description,
        }
    end

    local function restoreOriginals(): ()
        local originals: any = runtime.originals
        if not originals then
            return
        end
        local humanoid: Humanoid? = currentHumanoid()
        if humanoid then
            pcall(function(): ()
                (humanoid :: Humanoid).DisplayName = originals.displayName
            end)
            local wheel: HumanoidDescription? = characterDescription(humanoid :: Humanoid)
            if wheel then
                pcall(function(): ()
                    (wheel :: HumanoidDescription):SetEmotes(originals.emotes)
                    if #originals.equippedNames > 0 then
                        (wheel :: HumanoidDescription):SetEquippedEmotes(originals.equippedNames)
                    end
                end)
            end
        end
    end

    local function teardownPuppet(): ()
        local puppet: Model? = runtime.puppet
        runtime.puppet = nil
        runtime.puppetTracks = {}
        runtime.puppetParts = {}
        runtime.puppetHidden = false
        spoofAvatar.setRig(nil)
        if puppet then
            pcall(function(): ()
                (puppet :: Model):Destroy()
            end)
        end
    end

    local function setPuppetHidden(hidden: boolean): ()
        if runtime.puppetHidden == hidden then
            return
        end
        runtime.puppetHidden = hidden
        for _, part: BasePart in ipairs(runtime.puppetParts) do
            part.LocalTransparencyModifier = hidden and 1 or 0
        end
    end

    local function playPuppetTrack(key: string, fade: number): ()
        local track: AnimationTrack? = runtime.puppetTracks[key]
        if not track then
            return
        end
        for otherKey: string, other: AnimationTrack in pairs(runtime.puppetTracks) do
            if otherKey ~= key and other.IsPlaying then
                pcall(function(): ()
                    other:Stop(fade)
                end)
            end
        end
        if not (track :: AnimationTrack).IsPlaying then
            pcall(function(): ()
                (track :: AnimationTrack):Play(fade)
            end)
        end
    end

    -- Builds the local body double. Humanoid:ApplyDescription is server-only
    -- for replicated characters, so the disguise is a client-created rig from
    -- CreateHumanoidModelFromDescription that mirrors the hidden real one.
    local function buildPuppet(target: any): ()
        local character: Model? = currentCharacter()
        local humanoid: Humanoid? = character
            and (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not character or not humanoid then
            return
        end
        rememberOriginals(humanoid :: Humanoid)
        teardownPuppet()

        runtime.generation += 1
        local generation: number = runtime.generation
        local rigType: Enum.HumanoidRigType = (humanoid :: Humanoid).RigType
        local description: HumanoidDescription = target.description

        local created: boolean, rig: any = pcall(function(): any
            return (host.Players :: Players):CreateHumanoidModelFromDescription(
                description,
                rigType
            )
        end)
        if generation ~= runtime.generation then
            if created and typeof(rig) == "Instance" then
                pcall(function(): ()
                    (rig :: Model):Destroy()
                end)
            end
            return
        end
        if not created or typeof(rig) ~= "Instance" then
            disguise:Notify("could not build the disguise body")
            return
        end

        local puppet: Model = rig :: Model
        puppet.Name = "WurstDisguise"
        -- Marked so NPC detection, targeting and ESP treat the double as
        -- scenery instead of a second character standing on top of you.
        puppet:SetAttribute("WurstDisguise", true)
        local puppetHumanoid: Humanoid? = puppet:FindFirstChildOfClass("Humanoid")
        if puppetHumanoid then
            local resolvedPuppetHumanoid: Humanoid = puppetHumanoid :: Humanoid
            -- None hides both the name and the health bar over the double.
            resolvedPuppetHumanoid.DisplayDistanceType =
                Enum.HumanoidDisplayDistanceType.None
            pcall(function(): ()
                resolvedPuppetHumanoid.EvaluateStateMachine = false
            end)
        end
        for _, descendant: Instance in ipairs(puppet:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local part: BasePart = descendant :: BasePart
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
                part.Massless = true
                if part.Name == "HumanoidRootPart" then
                    part.Anchored = true
                end
                table.insert(runtime.puppetParts, part)
            end
        end
        puppet:PivotTo((character :: Model):GetPivot())
        puppet.Parent = currentWorkspace

        local animator: Animator? = puppetHumanoid
            and (puppetHumanoid :: Humanoid):FindFirstChildOfClass("Animator") :: Animator?
        if not animator then
            local made: boolean, createdAnimator: any = pcall(function(): any
                local instance: Animator = Instance.new("Animator")
                instance.Parent = puppetHumanoid
                return instance
            end)
            animator = made and createdAnimator or nil
        end
        if animator then
            local source: HumanoidDescription =
                (not disguise.Options["Take animations"].Value and runtime.originals
                    and runtime.originals.myDescription)
                or description
            for _, definition: any in ipairs(PUPPET_ANIMATIONS) do
                local animationId: number = tonumber((source :: any)[definition.field]) or 0
                if animationId > 0 then
                    local animation: Animation = Instance.new("Animation")
                    animation.Name = "WurstDisguise" .. definition.key
                    animation.AnimationId = "rbxassetid://" .. tostring(animationId)
                    animation.Parent = puppet
                    local loaded: boolean, track: any = pcall(function(): any
                        return (animator :: Animator):LoadAnimation(animation)
                    end)
                    if loaded and typeof(track) == "Instance" then
                        (track :: AnimationTrack).Priority = definition.priority
                        runtime.puppetTracks[definition.key] = track :: AnimationTrack
                    else
                        animation:Destroy()
                    end
                end
            end
        end

        runtime.puppet = puppet
        spoofAvatar.setRig(puppet)
        runtime.applied = true
    end

    local function publishEmotes(target: any): ()
        if not disguise.Options["Take emotes"].Value then
            spoofAvatar.setEmotes({})
            return
        end
        local collected: {any} = {}
        local ok: boolean, emotes: any = pcall(function(): any
            return (target.description :: HumanoidDescription):GetEmotes()
        end)
        if ok and type(emotes) == "table" then
            for name: string, ids: any in pairs(emotes) do
                if type(ids) == "table" and type(ids[1]) == "number" then
                    table.insert(collected, {name = name, id = ids[1]})
                end
            end
        end
        table.sort(collected, function(left: any, right: any): boolean
            return left.name < right.name
        end)
        spoofAvatar.setEmotes(collected)
    end

    local function applyToCharacter(target: any): ()
        local character: Model? = currentCharacter()
        local humanoid: Humanoid? = character
            and (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not character or not humanoid then
            publishEmotes(target)
            return
        end
        rememberOriginals(humanoid :: Humanoid)

        -- Name above your head, for your eyes only.
        if disguise.Options["Take name"].Value then
            pcall(function(): ()
                (humanoid :: Humanoid).DisplayName = target.name
            end)
        elseif runtime.originals then
            pcall(function(): ()
                (humanoid :: Humanoid).DisplayName = runtime.originals.displayName
            end)
        end

        -- Emote wheel: swap the character's HumanoidDescription emotes.
        if disguise.Options["Take emotes"].Value then
            local wheel: HumanoidDescription? = characterDescription(humanoid :: Humanoid)
            if wheel then
                local emotesOk: boolean, emotes: any = pcall(function(): any
                    return (target.description :: HumanoidDescription):GetEmotes()
                end)
                local equippedOk: boolean, equipped: any = pcall(function(): any
                    return (target.description :: HumanoidDescription):GetEquippedEmotes()
                end)
                if emotesOk and type(emotes) == "table" then
                    local names: {string} = {}
                    if equippedOk and type(equipped) == "table" then
                        for _, entry: any in ipairs(equipped) do
                            local name: string = tostring(
                                type(entry) == "table" and entry.name or entry
                            )
                            if name ~= "" then
                                table.insert(names, name)
                            end
                        end
                    end
                    pcall(function(): ()
                        (wheel :: HumanoidDescription):SetEmotes(emotes)
                        if #names > 0 then
                            (wheel :: HumanoidDescription):SetEquippedEmotes(names)
                        end
                    end)
                end
            end
        elseif runtime.originals then
            local wheel: HumanoidDescription? = characterDescription(humanoid :: Humanoid)
            if wheel then
                pcall(function(): ()
                    (wheel :: HumanoidDescription):SetEmotes(runtime.originals.emotes)
                    if #runtime.originals.equippedNames > 0 then
                        (wheel :: HumanoidDescription):SetEquippedEmotes(
                            runtime.originals.equippedNames
                        )
                    end
                end)
            end
        end

        if disguise.Options["Hide my real body"].Value then
            hideCharacter(character :: Model)
        else
            showCharacter()
        end
        buildPuppet(target)
        spoofAvatar.setDescription(target.description)
        publishEmotes(target)
        disguise:SetStatus(target.name .. " · " .. tostring(target.userId))
    end

    local function restoreEverything(): ()
        teardownPuppet()
        showCharacter()
        restoreOriginals()
        spoofAvatar.setDescription(nil)
        spoofAvatar.setEmotes({})
        runtime.applied = false
        disguise:SetStatus(nil)
    end

    local function onCharacterAdded(): ()
        -- The previous body and its double are gone; start the new one clean.
        teardownPuppet()
        hidingConnection = nil
        runtime.diedWatch = nil
        if not disguise.Enabled or not runtime.target then
            return
        end
        if runtime.applied and not disguise.Options["Keep on respawn"].Value then
            return
        end
        local target: any = runtime.target
        task.spawn(function(): ()
            task.wait(0.5)
            if disguise.Enabled and runtime.target == target then
                applyToCharacter(target)
            end
        end)
    end

    disguise = framework.Categories.Utility:CreateModule({
        Name = "Disguise",
        Category = "Fun",
        Order = 1,
        ConfigKey = "Universal.Disguise",
        Tooltip = "Wear another user's avatar locally: body, name above your "
            .. "head and emote wheel. Only your screen shows it.",
        Function = function(enabled: boolean): ()
            if not enabled then
                restoreEverything()
                return
            end
            disguise:Event(localPlayer.CharacterAdded, onCharacterAdded)
            disguise:Render(function(): ()
                local puppet: Model? = runtime.puppet
                local character: Model? = currentCharacter()
                if not puppet or not character then
                    return
                end
                local humanoid: Humanoid? =
                    (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
                local root: BasePart? =
                    (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
                    or (character :: Model).PrimaryPart
                if not humanoid or not root then
                    return
                end

                -- Reveal the real ragdoll the moment the body dies.
                local watch: RBXScriptConnection? = runtime.diedWatch
                if not watch or not watch.Connected then
                    runtime.diedWatch = (humanoid :: Humanoid).Died:Once(function(): ()
                        teardownPuppet()
                        showCharacter()
                    end)
                end

                local pivot: CFrame = (character :: Model):GetPivot()
                local resolvedPuppet: Model = puppet :: Model
                resolvedPuppet:PivotTo(pivot)

                -- Do not block the view when the camera dives into the double.
                local camera: Camera? = currentWorkspace.CurrentCamera
                if camera then
                    local distance: number =
                        ((camera :: Camera).CFrame.Position - pivot.Position).Magnitude
                    setPuppetHidden(distance < 3)
                end

                -- Copy the real body's motion state onto the double.
                local resolvedHumanoid: Humanoid = humanoid :: Humanoid
                local state: Enum.HumanoidStateType = resolvedHumanoid:GetState()
                local velocity: Vector3 = (root :: BasePart).AssemblyLinearVelocity
                local horizontal: number = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
                if state == Enum.HumanoidStateType.Climbing then
                    playPuppetTrack("climb", 0.2)
                elseif state == Enum.HumanoidStateType.Swimming then
                    playPuppetTrack("swim", 0.2)
                elseif state == Enum.HumanoidStateType.Jumping then
                    playPuppetTrack("jump", 0.1)
                elseif state == Enum.HumanoidStateType.Freefall then
                    playPuppetTrack("fall", 0.2)
                elseif horizontal > 0.75 then
                    local walkSpeed: number = math.max(resolvedHumanoid.WalkSpeed, 0.1)
                    local key: string = horizontal > walkSpeed * 0.75 and "run" or "walk"
                    local track: AnimationTrack? = runtime.puppetTracks[key]
                        or runtime.puppetTracks["walk"]
                    if track then
                        playPuppetTrack(key, 0.2)
                        pcall(function(): ()
                            (track :: AnimationTrack):AdjustSpeed(
                                math.max(horizontal / walkSpeed, 0.25)
                            )
                        end)
                    else
                        playPuppetTrack("idle", 0.2)
                    end
                else
                    playPuppetTrack("idle", 0.3)
                end
            end)

            if runtime.target then
                -- Module toggled back on: put the last disguise back on.
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
                return
            end
            local remembered: string = trimmed(
                tostring(disguise.Options["User ID or name"].Value or "")
            )
            if remembered ~= "" then
                task.spawn(function(): ()
                    Module.wear(context, disguise, runtime, applyToCharacter)
                end)
                return
            end
            disguise:SetStatus("waiting")
            disguise:Notify("type a user id or name, then press Apply")
        end,
    })

    disguise:CreateTextBox({
        Name = "User ID or name",
        Default = "",
        Tooltip = "Whose avatar to wear. With the module on, pressing enter "
            .. "puts it on immediately.",
        Function = function(value: string): ()
            if not disguise.Enabled or trimmed(value) == "" then
                return
            end
            task.spawn(function(): ()
                Module.wear(context, disguise, runtime, applyToCharacter)
            end)
        end,
    })
    disguise:CreateButton({
        Name = "Apply",
        Tooltip = "Fetch the avatar in the box and wear it now.",
        Function = function(): ()
            if not disguise.Enabled then
                disguise:Notify("switch the module on first")
                return
            end
            task.spawn(function(): ()
                Module.wear(context, disguise, runtime, applyToCharacter)
            end)
        end,
    })
    disguise:CreateToggle({
        Name = "Keep on respawn",
        Default = true,
        Tooltip = "Put the disguise back on every time you respawn.",
    })
    disguise:CreateToggle({
        Name = "Take animations",
        Default = true,
        Tooltip = "Walk, run and idle like their avatar package. Off keeps "
            .. "your own animation set on their body.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateToggle({
        Name = "Take name",
        Default = true,
        Tooltip = "Show their name above your head instead of yours.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateToggle({
        Name = "Take emotes",
        Default = true,
        Tooltip = "Fill your emote wheel and the Emote Player list with the "
            .. "emotes they have equipped.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateToggle({
        Name = "Hide my real body",
        Default = true,
        Tooltip = "The disguise is a local body double; this hides the real "
            .. "one on your screen. Tools stay attached to the hidden body.",
        Function = function(_value: any): ()
            if disguise.Enabled and runtime.target then
                task.spawn(function(): ()
                    applyToCharacter(runtime.target)
                end)
            end
        end,
    })
    disguise:CreateButton({
        Name = "Reset to my avatar",
        Tooltip = "Take the disguise off without switching the module off.",
        Function = function(): ()
            runtime.target = nil
            restoreEverything()
            disguise:Notify("back to your own avatar")
        end,
    })
    disguise:CreateNote(
        "Client sided only: the server, other players, the player list and "
            .. "the chat still show the real you. Emotes played from the "
            .. "Emote Player appear on the double; the wheel plays on the "
            .. "hidden real body."
    )

    activeCleanup = function(): ()
        restoreEverything()
    end
    Module.Initialized = true
    return disguise
end

function Module.wear(
    context: Runtime,
    disguise: any,
    runtime: any,
    applyToCharacter: (any) -> ()
): ()
    if runtime.busy then
        return
    end
    local players: Players = context.host.Players
    local text: string = trimmed(
        tostring(disguise.Options["User ID or name"].Value or "")
    )
    if text == "" then
        disguise:Notify("type a user id or name first")
        return
    end

    runtime.busy = true
    local userId: number = 0
    if looksNumeric(text) then
        userId = tonumber(text) or 0
    else
        local resolved: boolean, id: any = pcall(function(): number
            return players:GetUserIdFromNameAsync(text)
        end)
        if resolved and type(id) == "number" then
            userId = id
        end
    end
    if userId <= 0 then
        runtime.busy = false
        disguise:Notify("no such user")
        return
    end

    local fetched: boolean, description: any = pcall(function(): any
        return players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if not fetched or typeof(description) ~= "Instance" then
        runtime.busy = false
        disguise:Notify("could not read that avatar")
        return
    end

    -- Resolve a friendly label: display name when reachable, username else.
    local name: string = tostring(userId)
    local named: boolean, username: any = pcall(function(): string
        return players:GetNameFromUserIdAsync(userId)
    end)
    if named and type(username) == "string" and username ~= "" then
        name = username
    end
    local displayed: boolean, display: any = pcall(function(): string
        local body: string = (game :: any):HttpGet(
            "https://users.roblox.com/v1/users/" .. tostring(userId)
        )
        local decoded: any = game:GetService("HttpService"):JSONDecode(body)
        return tostring(decoded.displayName)
    end)
    if displayed and type(display) == "string" and display ~= "" then
        name = display
    end

    runtime.busy = false
    runtime.target = {
        description = description,
        name = name,
        userId = userId,
    }
    applyToCharacter(runtime.target)
    disguise:Notify("disguised as " .. name .. " - only you can see it")
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
