--!strict
--
-- No Fall.
--
-- Roblox has no fall damage of its own: every game that hurts you for landing
-- wrote that code itself, on the client that is falling, and there are only two
-- ways to write it — read the impact, or watch the humanoid's state machine.
-- This answers both, and blocks no remote: a damage remote that never arrives
-- is the one version of this that reads as an exploit in a server log.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "NoFall",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local getCharacterParts: any = host.getCharacterParts
    -- No Fall.
    --
    -- Roblox has no fall damage of its own: every game that hurts you for landing
    -- wrote that code itself, on the client that is falling, and there are only
    -- two ways to write it.
    --
    --   1. **Read the impact.** The vertical speed at touchdown, or the height
    --      difference between where the fall started and where it ended. Both are
    --      numbers this client produces, so the fall is braked a few studs above
    --      the floor and the game reads a landing that is inside its safe band.
    --      A downward raycast is what says when "a few studs" is now, which is
    --      what makes the brake late enough to be invisible from outside.
    --
    --   2. **Watch the humanoid state machine.** `StateChanged` into Freefall
    --      opens the measurement, Landed closes it. A humanoid whose state is put
    --      back before it touches down closes that measurement early, from a
    --      height where the recorded drop is harmless, and "Reset fall record"
    --      does the same thing repeatedly during a long fall: the humanoid is
    --      airborne, so physics puts it straight back into Freefall, and the game
    --      restarts its measurement from the height it is at now.
    --
    -- Neither lies to the server about where the character is, and neither blocks
    -- a remote — a blocked damage remote is the one version of this that shows up
    -- in a server log as "this player never takes fall damage".
    type NoFallSettings = {
        mode: string,
        safeSpeed: number,
        scanDistance: number,
        resetRecord: boolean,
    }
    local noFallSettings: NoFallSettings = {
        mode = "Both",
        safeSpeed = 30,
        scanDistance = 14,
        resetRecord = true,
    }

    local noFall: any
    noFall = framework.Categories.Protection:CreateModule({
        Name = "No Fall",
        Category = "Protection",
        Tooltip = "Fall damage is written by the game, on this client: this "
            .. "hands its formula a landing it considers safe instead of "
            .. "blocking anything.",
        Function = function(enabled: boolean): ()
            if not enabled then
                return
            end
            local nextRecordResetAt: number = 0
            local landedThisFall: boolean = false
            noFall:Loop(function(): ()
                local character: Model?, humanoidOrNil: Humanoid?, rootOrNil: BasePart? =
                    getCharacterParts()
                if not character or not humanoidOrNil or not rootOrNil then
                    return
                end
                local humanoid: Humanoid = humanoidOrNil :: Humanoid
                local root: BasePart = rootOrNil :: BasePart
                if humanoid.SeatPart or humanoid.Health <= 0 then
                    return
                end

                local velocity: Vector3 = root.AssemblyLinearVelocity
                local airborne: boolean = humanoid.FloorMaterial == Enum.Material.Air
                if not airborne or velocity.Y >= -1 then
                    landedThisFall = false
                    nextRecordResetAt = 0
                    return
                end

                -- The fall-record reset: cheap, repeated, and it costs nothing when
                -- the game measures impact speed instead.
                local now: number = os.clock()
                if noFallSettings.resetRecord
                    and noFallSettings.mode ~= "Impact"
                    and now >= nextRecordResetAt then
                    nextRecordResetAt = now + 0.35
                    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
                end

                -- How far ahead to look: the further you are falling, the earlier the
                -- ground has to be seen, or the brake lands after the impact it was
                -- meant to soften.
                local probe: number = math.max(
                    noFallSettings.scanDistance,
                    math.abs(velocity.Y) * 0.16
                )
                local params: RaycastParams = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = {character :: Instance}
                local ground: RaycastResult? = workspace:Raycast(
                    root.Position,
                    Vector3.new(0, -probe, 0),
                    params
                )
                if not ground then
                    return
                end

                if noFallSettings.mode ~= "State"
                    and velocity.Y < -noFallSettings.safeSpeed then
                    root.AssemblyLinearVelocity = Vector3.new(
                        velocity.X,
                        -noFallSettings.safeSpeed,
                        velocity.Z
                    )
                end
                if noFallSettings.mode ~= "Impact" and not landedThisFall then
                    -- Once per fall: the game's Freefall measurement is closed here,
                    -- a couple of studs up, instead of at the bottom.
                    landedThisFall = true
                    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
                end
            end)
        end,
    })
    noFall:CreateDropdown({
        Name = "Mode",
        List = {"Both", "Impact", "State"},
        Index = 1,
        Function = function(value: string): ()
            noFallSettings.mode = value
        end,
        Tooltip = "Impact brakes the fall just above the ground, for games "
            .. "that read your landing speed. State closes the humanoid's "
            .. "fall measurement early, for games that count the drop "
            .. "between Freefall and Landed. Both covers either, and is "
            .. "what you want unless one of them fights the game.",
    })
    noFall:CreateSlider({
        Name = "Safe landing speed",
        Show = {Option = "Mode", Values = {"Both", "Impact"}},
        Min = 5,
        Max = 80,
        Default = noFallSettings.safeSpeed,
        Function = function(value: number): ()
            noFallSettings.safeSpeed = value
        end,
        Tooltip = "The vertical speed the landing is allowed to have. Most "
            .. "games start hurting somewhere above 50.",
    })
    noFall:CreateToggle({
        Name = "Reset fall record",
        Show = {Option = "Mode", Values = {"Both", "State"}},
        Default = noFallSettings.resetRecord,
        Function = function(value: boolean): ()
            noFallSettings.resetRecord = value
        end,
        Tooltip = "Closes the humanoid's fall measurement every third of a "
            .. "second while you are in the air, so a game that measures the "
            .. "drop never sees more than a short one. Costs a little "
            .. "animation flicker on long falls.",
    })
    noFall:CreateSlider({
        Name = "Ground scan",
        Min = 4,
        Max = 40,
        Default = noFallSettings.scanDistance,
        Function = function(value: number): ()
            noFallSettings.scanDistance = value
        end,
        Tooltip = "How many studs above the floor the brake starts. Higher is "
            .. "safer and more visible; the module already scales this with "
            .. "your fall speed.",
    })

    Module.Initialized = true
    return noFall
end

function Module.destroy(): ()
    -- The loop lives on the kernel's cleanup list, which the shell empties on
    -- teardown; this module allocates nothing else.
    Module.Initialized = false
end

return Module
