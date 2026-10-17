export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AntiVoid",
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
    local addFeatureTooltip: any = host.addFeatureTooltip
    local workspace: any = host.workspace
    local antiFling, velocityLimit, safeCFrame, safeCharacter = false, 120, nil, nil
    local antiVoidPlatform: Part? = nil
    local antiVoidLastGroundY: number? = nil
    local antiVoidFreefallSeconds: number = 0
    local antiVoidPlatformToken: number = 0

    local function removeAntiVoidPlatform(): ()
        antiVoidPlatformToken = antiVoidPlatformToken + 1
        if antiVoidPlatform then
            antiVoidPlatform:Destroy()
            antiVoidPlatform = nil
        end
    end

    local function createAntiVoidPlatform(root: BasePart, humanoid: Humanoid): ()
        removeAntiVoidPlatform()

        local platform: Part = Instance.new("Part")
        platform.Name = "Wurst_AntiVoidPlatform"
        platform.Anchored = true
        platform.CanCollide = true
        platform.CanQuery = false
        platform.CanTouch = false
        platform.CastShadow = false
        platform.Size = Vector3.new(42, 1, 42)
        platform.Transparency = 1
        platform.CFrame = CFrame.new(root.Position - Vector3.new(0, 4.25, 0))
        platform.Parent = workspace
        antiVoidPlatform = platform

        local velocity: Vector3 = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(velocity.X * 0.25, 0, velocity.Z * 0.25)
        root.AssemblyAngularVelocity = Vector3.zero
        humanoid:ChangeState(Enum.HumanoidStateType.Landed)

        local token: number = antiVoidPlatformToken
        task.delay(3, function(): ()
            if antiVoidPlatformToken == token then
                removeAntiVoidPlatform()
            end
        end)
    end

    local function toggleAntiVoid(enabled: boolean): ()
        disconnectFeatureConnection("AntiVoid")
        removeAntiVoidPlatform()
        safeCFrame, safeCharacter = nil, nil
        antiVoidLastGroundY = nil
        antiVoidFreefallSeconds = 0

        if not enabled then
            return
        end

        featureConnections.AntiVoid = TaskManager:Connect(function(deltaTime: number): ()
            local character, humanoid, root = getCharacterParts()
            if not humanoid or not root or humanoid.Health <= 0 then
                return
            end

            if safeCharacter ~= character then safeCharacter, safeCFrame = character, nil end
            if antiFling and not context.services.activity.isActive("fling") then
                local linear, angular = root.AssemblyLinearVelocity.Magnitude, root.AssemblyAngularVelocity.Magnitude
                if linear > velocityLimit or angular > velocityLimit then
                    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
                    if safeCFrame then root.CFrame = safeCFrame end
                elseif humanoid.FloorMaterial ~= Enum.Material.Air and linear < velocityLimit * 0.45 then
                    safeCFrame = root.CFrame
                end
            end
            if humanoid.FloorMaterial ~= Enum.Material.Air then
                antiVoidLastGroundY = root.Position.Y
                antiVoidFreefallSeconds = 0
                return
            end

            antiVoidFreefallSeconds = antiVoidFreefallSeconds + deltaTime
            local destroyHeight: number = workspace.FallenPartsDestroyHeight
            if destroyHeight ~= destroyHeight then
                destroyHeight = -500
            end

            local nearDestroyLayer: boolean = root.Position.Y <= destroyHeight + 45
            local fellFarFromGround: boolean = antiVoidLastGroundY ~= nil
                and root.Position.Y <= (antiVoidLastGroundY :: number) - 120
                and antiVoidFreefallSeconds >= 1.1
                and root.AssemblyLinearVelocity.Y < -45

            if nearDestroyLayer or fellFarFromGround then
                createAntiVoidPlatform(root, humanoid)
                antiVoidFreefallSeconds = 0
            end
        end)
    end

    local AntiVoidFeature = createUniversalFeature(
        "Anti Void",
        "Create an invisible rescue platform only when death is imminent",
        4,
        toggleAntiVoid,
        {categoryName = "Utilities"}
    )
    local velocityRow
    local function showVelocityLimit()
        if not velocityRow then return end
        if host.setOptionVisible then host.setOptionVisible(AntiVoidFeature,velocityRow,antiFling)
        else velocityRow.Visible = antiFling end
    end
    host.addToggleOption(AntiVoidFeature, "Anti fling", false, function(value)
        antiFling, safeCFrame = value, nil
        showVelocityLimit()
    end, "Block extreme velocity while Anti Void is enabled.")
    velocityRow = host.addNumberOption(AntiVoidFeature, "Velocity limit", 120, 40, 1000, function(value) velocityLimit = value end)
    showVelocityLimit()
    addFeatureTooltip(
        AntiVoidFeature,
        "Detects a deep lethal fall and creates a temporary invisible platform beneath you."
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("AntiVoid")
        removeAntiVoidPlatform()
    end
    Module.Initialized = true
    return AntiVoidFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
