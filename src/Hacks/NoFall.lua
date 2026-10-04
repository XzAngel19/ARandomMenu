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
        Name = "NoFall",
        Category = "Movement",
        ConfigKey = "Universal.NoFall",
        Tooltip = "Fall damage is written by the game, on this client: this "
            .. "hands its formula a landing it considers safe instead of "
            .. "blocking anything.",
        Function = function(enabled: boolean): ()
            if not enabled then
                noFall:SetStatus(nil)
                return
            end
            noFall:SetStatus(noFallSettings.mode)
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

                local now: number = os.clock()
                if noFallSettings.resetRecord
                    and noFallSettings.mode ~= "Impact"
                    and now >= nextRecordResetAt then
                    nextRecordResetAt = now + 0.35
                    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
                end

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
            if noFall.Enabled then
                noFall:SetStatus(value)
            end
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

    Module.Initialized = false
end

return Module
