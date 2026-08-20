--!strict
--
-- Scaffold.
--
-- Something to walk on that is always there. Every game builds and breaks
-- blocks its own way — the remote, its arguments, the block ids — so a
-- universal scaffold cannot place the game's blocks without knowing them
-- (that is what the Remote Logger is for). What it can do, in any game, is
-- keep a solid surface under your feet while you cross a gap:
--
--   Platform  an anchored part, parented to the camera so it is local to you,
--             kept just under your feet whenever there is nothing below.
--   Bridge    the same part extended forward along the way you are moving, so
--             you can run out over the void instead of stepping tile by tile.
--   Catch     nothing at all until you start falling, then a platform appears
--             under you. Invisible until it matters.
--
-- Whether other players see it depends on the game: the part is local, so it
-- is your footing, not theirs.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Scaffold",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace

    local platform: BasePart? = nil

    local function releasePlatform(): ()
        if platform then
            pcall(function(): ()
                (platform :: BasePart):Destroy()
            end)
            platform = nil
        end
    end

    local function ensurePlatform(size: Vector3, options: any): BasePart
        if platform and (platform :: BasePart).Parent then
            local existing: BasePart = platform :: BasePart
            existing.Size = size
            existing.Transparency = 1 - options["Opacity"].Value
            existing.Color = options["Colour"].Value
            return existing
        end
        local created: BasePart = Instance.new("Part")
        created.Name = "RTM_Scaffold"
        created.Anchored = true
        created.CanCollide = true
        created.CanQuery = false
        created.CanTouch = false
        created.Material = Enum.Material.SmoothPlastic
        created.Size = size
        created.Color = options["Colour"].Value
        created.Transparency = 1 - options["Opacity"].Value
        -- Parented to the camera: it belongs to this client, and it goes away
        -- with the camera rather than littering the workspace.
        created.Parent = currentWorkspace.CurrentCamera
        platform = created
        return created
    end

    local function groundBelow(root: BasePart, reach: number): boolean
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.IgnoreWater = true
        parameters.FilterDescendantsInstances = {
            localPlayer.Character :: any,
            currentWorkspace.CurrentCamera :: any,
            platform :: any,
        }
        local hit: RaycastResult? = currentWorkspace:Raycast(
            root.Position,
            Vector3.new(0, -reach, 0),
            parameters
        )
        return hit ~= nil
    end

    local scaffold: any
    scaffold = framework.Categories.Movement:CreateModule({
        Name = "Scaffold",
        Category = "Movement",
        Order = 2,
        Tooltip = "Keeps a surface under your feet, or ahead of them.",
        Function = function(enabled: boolean): ()
            if not enabled then
                releasePlatform()
                return
            end
            scaffold:Clean(releasePlatform)
            scaffold:Loop(function(): ()
                local options: any = scaffold.Options
                local character: Model? = localPlayer.Character
                local root: BasePart? = character
                    and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                local humanoid: Humanoid? = character
                    and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if not root or not humanoid then
                    releasePlatform()
                    return
                end
                local resolvedRoot: BasePart = root :: BasePart
                local resolvedHumanoid: Humanoid = humanoid :: Humanoid
                local mode: string = options["Mode"].Value
                local reach: number = resolvedHumanoid.HipHeight + 4

                if mode == "Catch" then
                    -- Only when you are actually going down, and only when
                    -- there is nothing to land on.
                    if resolvedRoot.AssemblyLinearVelocity.Y > -6
                        or groundBelow(resolvedRoot, options["Catch depth"].Value) then
                        releasePlatform()
                        return
                    end
                elseif groundBelow(resolvedRoot, reach) then
                    -- There is a floor: stay out of the way so the game's own
                    -- geometry keeps deciding what you stand on.
                    releasePlatform()
                    return
                end

                local width: number = options["Width"].Value
                local length: number = mode == "Bridge"
                    and options["Bridge length"].Value
                    or width
                local surface: BasePart = ensurePlatform(
                    Vector3.new(width, 1, length),
                    options
                )
                local below: Vector3 = resolvedRoot.Position
                    - Vector3.new(0, resolvedHumanoid.HipHeight + 1.5, 0)
                if mode == "Bridge" then
                    -- Laid along the way you are moving, or the way you are
                    -- looking when you are standing still.
                    local heading: Vector3 = resolvedHumanoid.MoveDirection
                    if heading.Magnitude < 0.05 then
                        heading = resolvedRoot.CFrame.LookVector
                    end
                    heading = Vector3.new(heading.X, 0, heading.Z)
                    if heading.Magnitude < 0.05 then
                        heading = Vector3.new(0, 0, -1)
                    end
                    heading = heading.Unit
                    surface.CFrame = CFrame.lookAt(
                        below + heading * (length * 0.5 - 1),
                        below + heading * (length * 0.5 + 1)
                    )
                else
                    surface.CFrame = CFrame.new(below)
                end
            end)
        end,
    })

    scaffold:CreateDropdown({
        Name = "Mode",
        List = {"Platform", "Bridge", "Catch"},
        Index = 1,
        Tooltip = "Platform is a tile under you, Bridge extends it forward, "
            .. "Catch only appears once you start falling.",
    })
    scaffold:CreateSlider({
        Name = "Width",
        Min = 3,
        Max = 24,
        Default = 6,
    })
    scaffold:CreateSlider({
        Name = "Bridge length",
        Min = 6,
        Max = 60,
        Default = 18,
    })
    scaffold:CreateSlider({
        Name = "Catch depth",
        Min = 4,
        Max = 120,
        Default = 24,
        Tooltip = "How far below you the ground has to be missing before Catch "
            .. "builds anything.",
    })
    scaffold:CreateSlider({
        Name = "Opacity",
        Min = 0,
        Max = 1,
        Default = 0.35,
        Tooltip = "0 is invisible. It still holds you up.",
    })
    scaffold:CreateColor({
        Name = "Colour",
        Default = Color3.fromRGB(150, 150, 158),
    })
    scaffold:CreateNote(
        "Local footing, not the game's blocks. Use the Remote Logger to find "
            .. "how a game places its own, and a game module can then do it."
    )

    activeCleanup = releasePlatform
    Module.Initialized = true
    return scaffold
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
