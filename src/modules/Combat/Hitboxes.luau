--!strict
--
-- Hitboxes.
--
-- Adds studs to the part enemies are hit on. The reference client does this in
-- four lines — remember a size, add the slider to it every frame, put it back
-- on disable — and that is the right shape: an expansion in studs is a number
-- a player can reason about, where a multiplier ("body scale 2.25") means
-- nothing until you have seen it.
--
-- Three things the reference version leaves out and this keeps: teammates are
-- skipped (inflating the person you cannot hit only hides the person you can),
-- NPCs are opt-in, and a part is restored the moment it stops being a target
-- rather than only when the module is switched off.
--
-- It lived in the shell until now, for no reason other than being written
-- there first.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Hitboxes",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer

    -- Hitboxes.
    --
    -- The reference implementation is four lines: remember a part's size, add the
    -- slider to it every frame, put it back on disable. That is the right shape —
    -- an expansion in studs is a number a player can reason about ("six studs of
    -- extra reach"), where the multiplier this menu used before ("body scale
    -- 2.25") means nothing until you have seen it. So this is that model, with the
    -- three things the reference version leaves out:
    --
    --   * teammates are skipped, because inflating the person you cannot hit only
    --     makes it harder to see the person you can;
    --   * NPCs are opt-in, since half the games this runs in are full of them;
    --   * every part is restored exactly, including when it stops being a target
    --     mid-round (team swap, respawn, mode change), instead of only on disable.
    --
    -- Collision is dropped on the expanded part on purpose: a twelve-stud invisible
    -- box that still collides shoves its owner around the map, which is visible to
    -- everyone in the server.

    type HitboxSettings = {
        part: string,
        expand: number,
        reveal: boolean,
        transparency: number,
        teamCheck: boolean,
        includeNpcs: boolean,
        noCollision: boolean,
    }

    type OriginalHitboxState = {
        size: Vector3,
        transparency: number,
        canCollide: boolean,
        massless: boolean,
    }

    local hitboxSettings: HitboxSettings = {
        part = "Root",
        expand = 6,
        reveal = false,
        transparency = 60,
        teamCheck = true,
        includeNpcs = false,
        noCollision = true,
    }
    local originalHitboxes: {[BasePart]: OriginalHitboxState} =
        setmetatable({}, {__mode = "k"}) :: any

    local function restoreHitboxPart(part: BasePart): ()
        local original: OriginalHitboxState? = originalHitboxes[part]
        if not original then
            return
        end
        if part.Parent then
            part.Size = (original :: OriginalHitboxState).size
            part.Transparency = (original :: OriginalHitboxState).transparency
            part.CanCollide = (original :: OriginalHitboxState).canCollide
            part.Massless = (original :: OriginalHitboxState).massless
        end
        originalHitboxes[part] = nil
    end

    local function restoreHitboxes(): ()
        for part: BasePart in pairs(originalHitboxes) do
            restoreHitboxPart(part)
        end
        originalHitboxes = setmetatable({}, {__mode = "k"}) :: any
    end

    local function applyHitboxToPart(part: BasePart): ()
        local original: OriginalHitboxState? = originalHitboxes[part]
        if not original then
            original = {
                size = part.Size,
                transparency = part.Transparency,
                canCollide = part.CanCollide,
                massless = part.Massless,
            }
            originalHitboxes[part] = original
        end
        local resolved: OriginalHitboxState = original :: OriginalHitboxState
        local expand: number = hitboxSettings.expand
        part.Size = resolved.size + Vector3.new(expand, expand, expand)
        part.Transparency = hitboxSettings.reveal
            and math.clamp(hitboxSettings.transparency / 100, 0, 1)
            or resolved.transparency
        part.CanCollide = not hitboxSettings.noCollision and resolved.canCollide
        part.Massless = true
    end

    -- Which parts of one character the current mode targets. Everything else that
    -- was expanded on that character is put back, which is what makes flipping the
    -- mode mid-round safe.
    local function applyHitboxCharacter(character: Model): ()
        local wanted: {string} = hitboxSettings.part == "Head"
            and {"Head"}
            or (hitboxSettings.part == "Both" and {"HumanoidRootPart", "Head"})
            or {"HumanoidRootPart"}
        for _, child: Instance in ipairs(character:GetChildren()) do
            if not child:IsA("BasePart") then
                continue
            end
            local part: BasePart = child :: BasePart
            if table.find(wanted, part.Name) then
                applyHitboxToPart(part)
            else
                restoreHitboxPart(part)
            end
        end
    end

    -- NPCs are found by walking the workspace, which is the one part of this that
    -- is not cheap, so the answer is kept for two seconds. Players are re-read
    -- every frame: that list is short and a respawn has to be picked up at once.
    local hitboxNpcCache: {Model} = {}
    local hitboxNpcCachedAt: number = -1

    local function hitboxTargets(): {Model}
        local targets: {Model} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then
                continue
            end
            if hitboxSettings.teamCheck
                and LocalPlayer.Team ~= nil
                and player.Team == LocalPlayer.Team then
                continue
            end
            local character: Model? = player.Character
            local humanoid: Humanoid? = character
                and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if character and humanoid and humanoid.Health > 0 then
                table.insert(targets, character :: Model)
            end
        end
        if hitboxSettings.includeNpcs then
            local now: number = os.clock()
            if now - hitboxNpcCachedAt > 2 then
                hitboxNpcCachedAt = now
                hitboxNpcCache = {}
                for _, child: Instance in ipairs(workspace:GetChildren()) do
                    if not child:IsA("Model") or child == LocalPlayer.Character then
                        continue
                    end
                    local humanoid: Humanoid? =
                        child:FindFirstChildOfClass("Humanoid") :: Humanoid?
                    if humanoid
                        and (humanoid :: Humanoid).Health > 0
                        and Players:GetPlayerFromCharacter(child) == nil then
                        table.insert(hitboxNpcCache, child :: Model)
                    end
                end
            end
            for _, npc: Model in ipairs(hitboxNpcCache) do
                if npc.Parent then
                    table.insert(targets, npc)
                end
            end
        end
        return targets
    end

    local function sweepHitboxes(): ()
        local alive: {[BasePart]: boolean} = {}
        for _, character: Model in ipairs(hitboxTargets()) do
            applyHitboxCharacter(character)
            for _, child: Instance in ipairs(character:GetChildren()) do
                if child:IsA("BasePart") and originalHitboxes[child :: BasePart] then
                    alive[child :: BasePart] = true
                end
            end
        end
        -- Anything expanded that is no longer a target (dead, respawned, swapped
        -- to your team) goes back to the size the game gave it.
        for part: BasePart in pairs(originalHitboxes) do
            if not alive[part] then
                restoreHitboxPart(part)
            end
        end
    end

    local hitboxes: any
    hitboxes = framework.Categories.Combat:CreateModule({
        Name = "Hitboxes",
        Category = "Combat",
        Order = 3,
        Tooltip = "Expand the part enemies are hit on, in studs. Every part "
            .. "is restored exactly when it stops being a target.",
        Function = function(enabled: boolean): ()
            restoreHitboxes()
            hitboxNpcCachedAt = -1
            hitboxNpcCache = {}
            if not enabled then
                hitboxes:SetStatus(nil)
                return
            end
            hitboxes:SetStatus(
                hitboxSettings.part .. " +" .. tostring(math.round(hitboxSettings.expand))
            )
            hitboxes:Clean(restoreHitboxes)
            -- Two parts per player is cheap enough to do every frame, and
            -- every frame is what keeps the box on the character while the
            -- game rescales it.
            hitboxes:Loop(function(): ()
                sweepHitboxes()
            end)
        end,
    })
    hitboxes:CreateDropdown({
        Name = "Part",
        List = {"Root", "Head", "Both"},
        Index = 1,
        Function = function(value: string): ()
            hitboxSettings.part = value
            if hitboxes.Enabled then
                hitboxes:SetStatus(
                    value .. " +" .. tostring(math.round(hitboxSettings.expand))
                )
            end
        end,
        Tooltip = "Which part of the character is expanded. Parts the new "
            .. "mode no longer owns are restored on the next sweep.",
    })
    hitboxes:CreateSlider({
        Name = "Expand",
        Min = 0,
        Max = 30,
        Default = hitboxSettings.expand,
        Function = function(value: number): ()
            hitboxSettings.expand = value
            if hitboxes.Enabled then
                hitboxes:SetStatus(
                    hitboxSettings.part .. " +" .. tostring(math.round(value))
                )
            end
        end,
        Tooltip = "Studs added to the target part. Past roughly 10 the box is "
            .. "wider than the character is tall and anyone watching can see "
            .. "hits landing on nothing.",
    })
    hitboxes:CreateToggle({
        Name = "Team check",
        Default = hitboxSettings.teamCheck,
        Function = function(value: boolean): ()
            hitboxSettings.teamCheck = value
        end,
        Tooltip = "Leave teammates at their real size.",
    })
    hitboxes:CreateToggle({
        Name = "Include NPCs",
        Default = hitboxSettings.includeNpcs,
        Function = function(value: boolean): ()
            hitboxSettings.includeNpcs = value
        end,
    })
    hitboxes:CreateToggle({
        Name = "Show hitbox",
        Default = hitboxSettings.reveal,
        Function = function(value: boolean): ()
            hitboxSettings.reveal = value
        end,
        Tooltip = "Draw the expanded part so you can see what you are actually "
            .. "aiming at.",
    })
    hitboxes:CreateSlider({
        Name = "Show transparency %",
        Show = {Option = "Show hitbox"},
        Min = 0,
        Max = 95,
        Default = hitboxSettings.transparency,
        Function = function(value: number): ()
            hitboxSettings.transparency = value
        end,
    })
    hitboxes:CreateToggle({
        Name = "No collision",
        Default = hitboxSettings.noCollision,
        Function = function(value: boolean): ()
            hitboxSettings.noCollision = value
        end,
        Tooltip = "An expanded part that still collides pushes its owner "
            .. "around the map, which everyone in the server can see.",
    })

    activeCleanup = function(): ()
        restoreHitboxes()
    end
    Module.Initialized = true
    return hitboxes
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
