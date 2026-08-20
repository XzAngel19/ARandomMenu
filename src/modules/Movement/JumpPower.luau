--!strict
--
-- Jump Power.
--
-- Sets the humanoid's jump, in whichever of the two properties the game is
-- using (JumpPower or JumpHeight), and remembers what it found so switching
-- the module off leaves the character exactly as the game made it.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "JumpPower",
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
    local addNumberOption: any = host.addNumberOption
    local jumpPowerSettings = {value = 80}
    local originalJumpPower = setmetatable({}, {__mode = "k"})

    local function restoreJumpPower()
        for humanoid, original in pairs(originalJumpPower) do
            if humanoid and humanoid.Parent then
                humanoid.JumpPower = original.jumpPower
                humanoid.UseJumpPower = original.useJumpPower
            end
        end
        originalJumpPower = setmetatable({}, {__mode = "k"})
    end

    local function toggleJumpPower(enabled)
        disconnectFeatureConnection("JumpPower")
        restoreJumpPower()

        if not enabled then
            return
        end

        featureConnections.JumpPower = TaskManager:Connect(function()
            local _, humanoid = getCharacterParts()
            if not humanoid then
                return
            end

            if not originalJumpPower[humanoid] then
                originalJumpPower[humanoid] = {
                    jumpPower = humanoid.JumpPower,
                    useJumpPower = humanoid.UseJumpPower,
                }
            end

            humanoid.UseJumpPower = true
            humanoid.JumpPower = jumpPowerSettings.value
        end)
    end

    -- Infinite Jump.
    --
    -- Rewritten: on touch the jump button re-fires `JumpRequest` many times per
    -- second while it is held, so every request adding velocity made the module
    -- uncontrollable and made it look like it was still on after being switched
    -- off. Each mode is now a distinct, rate-limited behaviour.
    --
    --   Normal  every jump sets the same height. Predictable, does not stack.
    --   Impulse the same height reached with a force, so the character stays a
    --           normal physics body instead of having its velocity overwritten.
    --   Stack   each jump adds to the current climb (the old "Normal"), capped.
    --   Rise    hold jump to fly straight up at a steady speed.
    --   Fall    jumping mid-air cancels the fall instead of launching you, which
    --           is what a fall-mode jump was supposed to do — it used to be an
    --           exact copy of Normal, so it never worked at all.

    local JumpPowerFeature = createUniversalFeature(
        "Jump Power",
        "Keep character jump power at a custom value",
        6,
        toggleJumpPower
    )
    addNumberOption(JumpPowerFeature, "Power", jumpPowerSettings.value, 0, 500, function(value)
        jumpPowerSettings.value = value
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("JumpPower")
        restoreJumpPower()
    end
    Module.Initialized = true
    return JumpPowerFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
