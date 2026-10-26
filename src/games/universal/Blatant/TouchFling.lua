export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Touch Fling",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local state: any = host.state
    local configData: any = host.configData
    local LocalPlayer: any = host.LocalPlayer
    local RunService: any = host.RunService or game:GetService("RunService")
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip

    -- Never auto-enable Touch Fling on script injection from a stale config state.
    if type(configData) == "table" and type(configData.states) == "table" then
        configData.states["Universal.TouchFling"] = false
    end

    local originalCollision = setmetatable({}, {__mode = "k"})
    local touchFlingActive: boolean = false
    local touchFlingSession: number = 0
    local lastSafeVelocity: Vector3 = Vector3.zero
    local TouchFlingFeature: any = nil

    local function restoreCollision(): ()
        for part: any, canCollide: any in pairs(originalCollision) do
            if part and part.Parent then
                pcall(function(): ()
                    part.CanCollide = canCollide
                end)
            end
        end
        originalCollision = setmetatable({}, {__mode = "k"})
    end

    local function getCharacterRoot(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character or not character.Parent then
            return nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        local root: BasePart? = (character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("Torso")
            or character:FindFirstChild("UpperTorso")) :: BasePart?
        if not humanoid or humanoid.Health <= 0 or not root then
            return character, humanoid, nil
        end
        return character, humanoid, root
    end

    local function waitSignal(sig: any): ()
        if sig and (type(sig) == "table" or typeof(sig) == "RBXScriptSignal") and type(sig.Wait) == "function" then
            local ok: boolean = pcall(function(): ()
                sig:Wait()
            end)
            if ok then
                return
            end
        end
        task.wait()
    end

    local function toggleTouchFling(enabled: boolean): ()
        local wanted: boolean = enabled == true
        touchFlingActive = wanted
        touchFlingSession += 1
        local mySession: number = touchFlingSession

        if state and type(state.toggleControls) == "table" then
            local mm2Control: any = state.toggleControls["MM2.Fling.TouchFling"]
            if mm2Control and type(mm2Control.setChecked) == "function" then
                pcall(mm2Control.setChecked, wanted)
            end
        end

        if not wanted then
            local _char: Model?, _hum: Humanoid?, root: BasePart? = getCharacterRoot()
            if root and root.Parent then
                pcall(function(): ()
                    root.Velocity = lastSafeVelocity
                    root.AssemblyLinearVelocity = lastSafeVelocity
                end)
            end
            restoreCollision()
            if TouchFlingFeature then
                TouchFlingFeature:SetStatus(nil)
            end
            return
        end

        if TouchFlingFeature then
            TouchFlingFeature:SetStatus("ON")
        end

        task.spawn(function(): ()
            local movel: number = 0.1
            while touchFlingActive and touchFlingSession == mySession do
                waitSignal(RunService and RunService.Heartbeat)
                if not touchFlingActive or touchFlingSession ~= mySession then
                    break
                end
                local character: Model?, _humanoid: Humanoid?, root: BasePart? = getCharacterRoot()
                if character and root and root.Parent then
                    local savedVel: Vector3 = root.AssemblyLinearVelocity
                    lastSafeVelocity = savedVel
                    for _, part: Instance in ipairs(character:GetChildren()) do
                        if part:IsA("BasePart") then
                            if originalCollision[part] == nil then
                                originalCollision[part] = part.CanCollide
                            end
                            part.CanCollide = false
                        end
                    end
                    local spike: Vector3 = savedVel * 10000 + Vector3.new(0, 10000, 0)
                    pcall(function(): ()
                        root.Velocity = spike
                        root.AssemblyLinearVelocity = spike
                    end)
                    waitSignal(RunService and RunService.RenderStepped)
                    if touchFlingActive and touchFlingSession == mySession and character.Parent and root.Parent then
                        pcall(function(): ()
                            root.Velocity = savedVel
                            root.AssemblyLinearVelocity = savedVel
                        end)
                    end
                    waitSignal(RunService and RunService.Stepped)
                    if touchFlingActive and touchFlingSession == mySession and character.Parent and root.Parent then
                        local osc: Vector3 = savedVel + Vector3.new(0, movel, 0)
                        pcall(function(): ()
                            root.Velocity = osc
                            root.AssemblyLinearVelocity = osc
                        end)
                        movel = -movel
                    end
                else
                    task.wait(0.05)
                end
            end
        end)
    end

    TouchFlingFeature = createUniversalFeature(
        "Touch Fling",
        "Walk into any player to fling them on body contact (Infinite Yield walkfling)",
        14,
        toggleTouchFling,
        {noOptions = true, categoryName = "Exploits"}
    )
    addFeatureTooltip(
        TouchFlingFeature,
        "Spikes physics velocity between Heartbeat and RenderStepped so touching any player's character with your body sends them flying."
    )

    if state then
        state.touchFlingFeature = TouchFlingFeature
        state.setTouchFlingEnabled = function(on: boolean): ()
            if TouchFlingFeature and type(TouchFlingFeature.setEnabled) == "function" then
                TouchFlingFeature.setEnabled(on == true, true)
            else
                toggleTouchFling(on == true)
            end
        end
    end

    activeCleanup = function(): ()
        toggleTouchFling(false)
        if state then
            state.touchFlingFeature = nil
            state.setTouchFlingEnabled = nil
        end
    end
    Module.Initialized = true
    return TouchFlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
