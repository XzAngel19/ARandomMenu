--!strict
--
-- Click Teleport.
--
-- The old implementation raycast through `Camera:ViewportPointToRay` using the
-- raw `InputObject.Position`. Those are two different coordinate spaces: input
-- positions include the 36-pixel top bar, viewport points do not, so every
-- teleport landed above wherever the finger actually was — and on a phone,
-- where the offset is a good part of a thumb, it usually landed on nothing at
-- all and the module looked dead. `ScreenPointToRay` is the one that takes
-- input coordinates.
--
-- Gesture, on every device: hold the module's key (or its placed button), then
-- tap where you want to go. On desktop the arming step can be skipped with
-- CTRL + click, and Vape's "Lerp" travel is available for games that reject a
-- single large position change.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "ClickTeleport",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace
    local state: any = host.state

    local armedUntil: number = 0

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local character: Model? = localPlayer.Character
        if not character then
            return nil, nil, nil
        end
        return character,
            character:FindFirstChildOfClass("Humanoid") :: Humanoid?,
            character:FindFirstChild("HumanoidRootPart") :: BasePart?
    end

    local function resolveDestination(screenPosition: Vector3?): Vector3?
        local camera: Camera? = currentWorkspace.CurrentCamera
        if not camera then
            return nil
        end
        local resolvedCamera: Camera = camera :: Camera
        local ray: Ray
        if screenPosition then
            -- Screen space, not viewport space: this is the whole reason the
            -- module used to miss.
            ray = resolvedCamera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
        else
            local aim: Ray? = state.getAimRay and state.getAimRay()
            if not aim then
                return nil
            end
            ray = aim :: Ray
        end

        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.IgnoreWater = true
        parameters.FilterDescendantsInstances = {
            localPlayer.Character :: any,
            resolvedCamera,
        }
        local result: RaycastResult? = currentWorkspace:Raycast(
            ray.Origin,
            ray.Direction.Unit * 4096,
            parameters
        )
        if not result then
            return nil
        end
        return result.Position
    end

    local teleport: any
    teleport = framework.Categories.Movement:CreateModule({
        Name = "Click Teleport",
        Category = "Movement",
        Order = 1,
        Tooltip = "Hold the key, then tap where you want to go.",
        Function = function(enabled: boolean): ()
            armedUntil = 0
            if not enabled then
                return
            end

            teleport:Event(
                userInput.InputBegan,
                function(input: InputObject, processed: boolean): ()
                    if processed then
                        -- A tap on the menu is not a tap on the world.
                        return
                    end
                    if state.keyCaptureCallback or state.waitingForKey then
                        return
                    end
                    local touched: boolean =
                        input.UserInputType == Enum.UserInputType.Touch
                    local clicked: boolean =
                        input.UserInputType == Enum.UserInputType.MouseButton1
                    if not touched and not clicked then
                        return
                    end

                    local options: any = teleport.Options
                    local trigger: string = options["Trigger"].Value
                    local armed: boolean = os.clock() < armedUntil
                    if trigger == "Hold key" and not armed then
                        return
                    end
                    if trigger == "CTRL + click" then
                        if not userInput.KeyboardEnabled
                            or not userInput:IsKeyDown(Enum.KeyCode.LeftControl) then
                            return
                        end
                    end

                    armedUntil = 0
                    Module.travel(context, teleport, resolveDestination(input.Position))
                end
            )
        end,
    })

    teleport:CreateDropdown({
        Name = "Trigger",
        List = {"Hold key", "Tap anywhere", "CTRL + click"},
        Index = 1,
        Tooltip = "Hold key arms the module first; Tap anywhere teleports on "
            .. "any tap while the module is on.",
    })
    teleport:CreateDropdown({
        Name = "Travel",
        List = {"Instant", "Glide"},
        Index = 1,
        Tooltip = "Glide walks the character there in steps, which some games "
            .. "accept when a single jump is rejected.",
    })
    teleport:CreateSlider({
        Name = "Glide step",
        Min = 4,
        Max = 60,
        Default = 18,
        Tooltip = "Studs per step while gliding.",
    })
    teleport:CreateSlider({
        Name = "Height offset",
        Min = 0,
        Max = 12,
        Default = 3,
        Tooltip = "Studs above the surface you land on.",
    })
    teleport:CreateSlider({
        Name = "Arm window",
        Min = 1,
        Max = 10,
        Default = 4,
        Tooltip = "Seconds the module stays armed after the key is released.",
    })
    teleport:CreateNote(
        "On touch, tap the module's key slot to place a button, hold it, then "
            .. "tap the ground."
    )

    -- Arming lives on `state` so the card's key slot (and its placed mobile
    -- button) can drive it through the shared keybind registry.
    state.armClickTeleport = function(armed: boolean): ()
        if not teleport.Enabled then
            armedUntil = 0
            return
        end
        if armed then
            armedUntil = math.huge
            if host.notify then
                host.notify("Click Teleport: tap where you want to go.")
            end
            return
        end
        -- Keep it armed briefly after release so the same hand can let go of
        -- the button and then tap the destination.
        armedUntil = os.clock() + teleport.Options["Arm window"].Value
    end

    if state.bindFeatureActivationKey then
        state.bindFeatureActivationKey(
            teleport.Feature,
            Enum.KeyCode.Unknown,
            function(): ()
                state.armClickTeleport(true)
            end,
            function(): ()
                state.armClickTeleport(false)
            end
        )
    end

    activeCleanup = function(): ()
        armedUntil = 0
        state.armClickTeleport = nil
    end
    Module.Initialized = true
    return teleport
end

function Module.travel(context: Runtime, teleport: any, destination: Vector3?): ()
    local host: any = context.host
    local localPlayer: Player = host.LocalPlayer
    if not destination then
        if host.notify then
            host.notify("Click Teleport: nothing under that point.")
        end
        return
    end

    local character: Model? = localPlayer.Character
    local root: BasePart? = character
        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not root then
        return
    end
    local resolvedRoot: BasePart = root :: BasePart

    -- Land on top of the surface rather than inside it: hip height is what
    -- keeps the character from spawning knee-deep in the floor.
    local hipHeight: number = humanoid and humanoid.HipHeight or 2
    local target: Vector3 = (destination :: Vector3)
        + Vector3.new(0, hipHeight + teleport.Options["Height offset"].Value, 0)

    if teleport.Options["Travel"].Value == "Instant" then
        resolvedRoot.CFrame = CFrame.new(target)
        resolvedRoot.AssemblyLinearVelocity = Vector3.zero
        return
    end

    local step: number = teleport.Options["Glide step"].Value
    task.spawn(function(): ()
        for _ = 1, 240 do
            if not resolvedRoot.Parent then
                return
            end
            local offset: Vector3 = target - resolvedRoot.Position
            if offset.Magnitude < 3 then
                resolvedRoot.CFrame = CFrame.new(target)
                resolvedRoot.AssemblyLinearVelocity = Vector3.zero
                return
            end
            resolvedRoot.CFrame = resolvedRoot.CFrame
                + offset.Unit * math.min(offset.Magnitude, step)
            resolvedRoot.AssemblyLinearVelocity = Vector3.zero
            task.wait()
        end
    end)
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
