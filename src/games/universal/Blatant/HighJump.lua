export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "HighJump",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local highJumpSettings: {velocity: number} = {velocity = 72}

    local function performHighJump(): ()
        local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not humanoid or not root or humanoid.Health <= 0 then
            return
        end
        local current: Vector3 = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(
            current.X,
            highJumpSettings.velocity,
            current.Z
        )

        if humanoid.FloorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        end
    end

    local HighJumpFeature = createUniversalFeature(
        "HighJump",
        "Press the key slot to launch a single high jump",
        19,
        performHighJump,
        {
            action = true,
            silentAction = true,
            configKey = "Universal.HighJump",
            categoryName = "Blatant",
        }
    )
    addNumberOption(
        HighJumpFeature,
        "Jump velocity",
        highJumpSettings.velocity,
        25,
        220,
        function(value: number): ()
            highJumpSettings.velocity = value
        end
    )

    activeCleanup = function(): ()

    end
    Module.Initialized = true
    return HighJumpFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
