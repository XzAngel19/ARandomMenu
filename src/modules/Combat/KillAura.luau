--!strict
--
-- Kill Aura.
--
-- Swings whatever melee weapon you are holding at everyone around you. Vape's
-- version is one range slider, a CPS slider and an angle; this one separates
-- the three decisions that actually change how it behaves in a game:
--
--   * When to swing      — reach, field of view, wall check, priority.
--   * How to hit         — the tool's own Activate, plus contact firing
--                          (`firetouchinterest`) for weapons that only damage
--                          on touch.
--   * How obvious to be  — rotation off, snapped for a single frame around the
--                          swing (silent), or held on the target.
--
-- Reach is one number. It used to be two — a swing range that picked the
-- targets and a shorter attack range that gated the touch events — and at the
-- shipped defaults the second one never fired, because every target inside 12
-- studs was already inside 14. One distance, one row: the aura swings at, and
-- fires contact on, exactly the players it selected.
--
-- Kill Aura is not a cursor trigger. Its default 360° cone scans every
-- direction around the character; Field of view is only a deliberate way to
-- narrow that scan. Defaults are deliberately useful: three targets, 18-stud
-- reach, 8 swings a second, walls ignored and friends skipped.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "KillAura",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- Melee damage in Roblox arrives one of three ways, and a weapon can use any
-- combination of them, so all three are attempted per swing.
-- Weapon detection.
--
-- `character:FindFirstChildOfClass("Tool")` is not enough: plenty of games keep
-- the weapon somewhere else, hand you two tools at once, or give the sword a
-- name the module cannot guess. So the module learns instead of guessing — it
-- watches `Tool.Activated`, and whatever you swing manually becomes the weapon
-- it swings from then on. There is also a button that binds whatever is in
-- your hands right now, and a name box for the stubborn cases.
local function collectTools(localPlayer: Player): {Tool}
    local tools: {Tool} = {}
    local character: Model? = localPlayer.Character
    if character then
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(tools, child :: Tool)
            end
        end
    end
    local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, child: Instance in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(tools, child :: Tool)
            end
        end
    end
    return tools
end

local function toolHandle(tool: Tool?): BasePart?
    if not tool then
        return nil
    end
    local resolved: Tool = tool :: Tool
    local handle: Instance? = resolved:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        return handle :: BasePart
    end
    -- Some weapons name their handle anything at all; the first part in the
    -- tool is a better guess than nothing.
    for _, descendant: Instance in ipairs(resolved:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant :: BasePart
        end
    end
    return nil
end

local function activateTool(tool: Tool?): ()
    if not tool then
        return
    end
    pcall(function(): ()
        tool:Activate()
    end)
end

local function fireContact(handle: BasePart?, target: BasePart): ()
    if not handle then
        return
    end
    local environment: any = getfenv()
    local fire: any = environment.firetouchinterest
    if type(fire) ~= "function" then
        return
    end
    -- 1 = TouchEnded, 0 = TouchBegan; both are needed or the game keeps
    -- thinking the parts are still overlapping and ignores the next swing.
    pcall(fire, handle, target, 1)
    pcall(fire, handle, target, 0)
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local entityLibrary: any = context.entity
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace

    local nextSwingAt: number = 0
    local nextStatusAt: number = 0
    local highlights: {[any]: Highlight} = {}

    local function clearHighlights(keep: {[any]: boolean}?): ()
        for key: any, highlight: Highlight in pairs(highlights) do
            if not keep or not keep[key] then
                pcall(function(): ()
                    highlight:Destroy()
                end)
                highlights[key] = nil
            end
        end
    end

    local function markTarget(entity: any, options: any): ()
        if not options["Highlight targets"].Value then
            return
        end
        local key: any = entity.Player or entity.Character
        local existing: Highlight? = highlights[key]
        if not existing or not existing.Parent then
            local created: Highlight = Instance.new("Highlight")
            created.Name = "RTM_KillAuraTarget"
            created.FillTransparency = 0.75
            created.Parent = entity.Character
            highlights[key] = created
            existing = created
        end
        local highlight: Highlight = existing :: Highlight
        highlight.Adornee = entity.Character
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        local colour: Color3 = options["Highlight colour"].Value
        highlight.FillColor = colour
        highlight.OutlineColor = colour
    end

    -- Declared before the helpers below because they read its options: the
    -- card is built further down, but `equippedTool` is written against it.
    local aura: any = nil
    local weapons: any = context.weapons

    local function updateTargetStatus(count: number): ()
        local now: number = os.clock()
        if now < nextStatusAt then
            return
        end
        nextStatusAt = now + 0.25
        aura:SetStatus(tostring(count) .. " in range")
    end

    -- The weapon the player last swung by hand. Everything else is a fallback.
    local learnedWeapon: string? = nil
    local learnConnections: {RBXScriptConnection} = {}

    local function watchTool(tool: Tool): ()
        table.insert(
            learnConnections,
            tool.Activated:Connect(function(): ()
                learnedWeapon = tool.Name
            end)
        )
    end

    local function watchAllTools(): ()
        for _, connection: RBXScriptConnection in ipairs(learnConnections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        learnConnections = {}
        for _, tool: Tool in ipairs(collectTools(localPlayer)) do
            watchTool(tool)
        end
    end

    local function matchesWanted(tool: Tool, wanted: string): boolean
        return string.find(string.lower(tool.Name), string.lower(wanted), 1, true) ~= nil
    end

    -- Order of preference: the name you typed, the weapon you last swung, then
    -- whatever is in your hands.
    local function equippedTool(): (Tool?, BasePart?)
        local character: Model? = localPlayer.Character
        if not character then
            return nil, nil
        end
        local wanted: string = tostring(aura.Options["Weapon name"].Value or "")
        local held: {Tool} = {}
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(held, child :: Tool)
            end
        end

        if wanted ~= "" then
            for _, tool: Tool in ipairs(held) do
                if matchesWanted(tool, wanted) then
                    return tool, toolHandle(tool)
                end
            end
        end
        if learnedWeapon then
            for _, tool: Tool in ipairs(held) do
                if tool.Name == learnedWeapon then
                    return tool, toolHandle(tool)
                end
            end
        end
        local first: Tool? = held[1]
        return first, toolHandle(first)
    end

    -- Equipping: the wanted weapon if the backpack has it, otherwise the first
    -- tool there, because a game that stows your sword on respawn should not
    -- end the aura.
    local function equipFromBackpack(): ()
        local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
        local humanoid: Humanoid? = localPlayer.Character
            and localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not backpack or not humanoid then
            return
        end
        local wanted: string = tostring(aura.Options["Weapon name"].Value or "")
        local chosen: Tool? = nil
        for _, child: Instance in ipairs(backpack:GetChildren()) do
            if not child:IsA("Tool") then
                continue
            end
            local tool: Tool = child :: Tool
            if wanted ~= "" and matchesWanted(tool, wanted) then
                chosen = tool
                break
            end
            if learnedWeapon and tool.Name == learnedWeapon then
                chosen = tool
                break
            end
            if not chosen then
                chosen = tool
            end
        end
        if chosen then
            pcall(function(): ()
                humanoid:EquipTool(chosen :: Tool)
            end)
        end
    end

    -- Reach replaced the swing-range / attack-range pair. Carry a saved swing
    -- range across only when the new key has never been written, and keep the
    -- old key so an older build can still read the same profile.
    local store: any = host.configData
    if store and store.values then
        local reachKey: string = "Universal.KillAura.Reach"
        local stored: any = store.values["Universal.KillAura.Swingrange"]
        if store.values[reachKey] == nil and type(stored) == "number" then
            store.values[reachKey] = stored
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
        end
    end

    aura = framework.Categories.Combat:CreateModule({
        Name = "Killaura",
        Category = "Combat",
        ConfigKey = "Universal.KillAura",
        Order = 1,
        Tooltip = "Swings your weapon at everyone in reach, with its own "
            .. "range, rate, field of view and rotation.",
        Function = function(enabled: boolean): ()
            nextSwingAt = 0
            nextStatusAt = 0
            if not enabled then
                aura:SetStatus(nil)
                clearHighlights()
                return
            end
            aura:SetStatus("0 in range")

            aura:Clean(function(): ()
                clearHighlights()
            end)
            -- Learn from the player: whichever tool they swing by hand becomes
            -- the weapon the aura uses.
            watchAllTools()
            aura:Event(localPlayer.CharacterAdded, function(): ()
                task.defer(watchAllTools)
            end)
            local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
            if backpack then
                aura:Event(backpack.ChildAdded, function(child: Instance): ()
                    if child:IsA("Tool") then
                        watchTool(child :: Tool)
                    end
                end)
            end
            aura:Clean(function(): ()
                for _, connection: RBXScriptConnection in ipairs(learnConnections) do
                    pcall(function(): ()
                        connection:Disconnect()
                    end)
                end
                learnConnections = {}
            end)

            aura:Loop(function(): ()
                local options: any = aura.Options
                if options["Activation"].Value == "Hold key"
                    and not userInput:IsKeyDown(options["Hold key"].Value) then
                    updateTargetStatus(0)
                    clearHighlights()
                    return
                end
                if not entityLibrary:IsAlive() then
                    updateTargetStatus(0)
                    clearHighlights()
                    return
                end

                local tool: Tool?, handle: BasePart? = equippedTool()
                if not tool then
                    if options["Auto equip"].Value then
                        equipFromBackpack()
                    end
                    if options["Require tool"].Value then
                        -- Opt-in only. Most games this module is useful in do
                        -- not put a Tool in your hands at all.
                        updateTargetStatus(0)
                        clearHighlights()
                        return
                    end
                end

                entityLibrary:Refresh()
                local targets: {any} = entityLibrary:InRange({
                    Range = options["Reach"].Value,
                    Limit = math.round(options["Max targets"].Value),
                    IgnoreTeam = not options["Team check"].Value,
                    IgnoreWalls = not options["Wall check"].Value,
                    Angle = options["Field of view"].Value,
                    IncludeNPCs = options["Target NPCs"].Value,
                    Sort = options["Priority"].Value,
                })
                updateTargetStatus(#targets)
                if #targets == 0 then
                    clearHighlights()
                    return
                end
                local now: number = os.clock()
                local rate: number = math.max(options["Swings per second"].Value, 0.5)
                -- A perfectly even swing interval is a signature, so a
                -- quarter of it is thrown away at random. Not a setting:
                -- nobody wants a machine-exact rate, and the row asking about
                -- it was one more thing to read.
                local jitter: number = 1 / rate * 0.25
                local canSwing: boolean = now >= nextSwingAt
                local keep: {[any]: boolean} = {}

                local root: BasePart? = entityLibrary.LocalEntity
                    and entityLibrary.LocalEntity.RootPart
                local rotation: string = options["Rotation"].Value
                local originalCFrame: CFrame? = root and root.CFrame or nil

                if canSwing then
                    -- One randomised interval per swing rather than a fixed
                    -- clock: a perfectly even 9.00 CPS is the easiest thing in
                    -- the world for a server to notice.
                    nextSwingAt = now
                        + (1 / rate)
                        + (math.random() - 0.5) * 2 * jitter
                end

                if rotation ~= "Off" and root then
                    local first: any = targets[1]
                    local flat: Vector3 = first.RootPart.Position
                        * Vector3.new(1, 0, 1)
                    root.CFrame = CFrame.lookAt(
                        root.Position,
                        Vector3.new(flat.X, root.Position.Y + 0.01, flat.Z)
                    )
                end

                for _, entity: any in ipairs(targets) do
                    keep[entity.Player or entity.Character] = true
                    markTarget(entity, options)

                    if not canSwing then
                        continue
                    end
                    -- Three ways to swing, tried in order, because a game
                    -- that answers to none of them is a game the aura cannot
                    -- help with:
                    --   1. whatever the player ticked,
                    --   2. the tool in their hands,
                    --   3. whatever the weapon library can find — the touch
                    --      button, a hotbar slot, a view model. Without this
                    --      third step the aura found its target, outlined it,
                    --      and then pressed nothing at all in every game that
                    --      does not use Tool instances.
                    local swung: boolean = false
                    if weapons then
                        for _, label: string in ipairs(aura.Options["Weapons"].Selected or {}) do
                            local candidate: any = weapons:Find(label)
                            if candidate and weapons:Activate(candidate) then
                                swung = true
                            end
                        end
                    end
                    if not swung and tool then
                        activateTool(tool)
                        swung = true
                    end
                    if not swung and weapons then
                        -- Falling back to "whatever the library can find"
                        -- means a melee weapon, never the bow that happened
                        -- to be in the same hotbar.
                        local fallback: any = weapons:Best({Melee = true})
                        swung = fallback ~= nil and weapons:Activate(fallback)
                    end
                    -- Extra presses for games that count each one as a hit.
                    local extraHits: number =
                        math.max(math.round(options["Hits per swing"].Value) - 1, 0)
                    for _ = 1, extraHits do
                        if tool then
                            activateTool(tool)
                        elseif weapons then
                            weapons:Swing()
                        end
                    end
                    if not options["Contact damage"].Value then
                        -- Swing and nothing else: the tool's own Activate, no
                        -- touch events. What a player's hand does.
                        continue
                    end
                    -- Walls are a separate decision from reach, so a player can
                    -- have one without the other.
                    if not options["Hit through walls"].Value
                        and not entityLibrary:VisibleFrom(entity) then
                        continue
                    end
                    -- Contact firing needs a part to touch: the parts actually
                    -- inside the target's box, not just the root, or weapons
                    -- with limb-only hitboxes never register.
                    local overlap: OverlapParams = OverlapParams.new()
                    overlap.FilterType = Enum.RaycastFilterType.Include
                    overlap.FilterDescendantsInstances = {entity.Character}
                    local parts: {BasePart} = currentWorkspace:GetPartBoundsInBox(
                        entity.RootPart.CFrame,
                        Vector3.new(5, 6, 5),
                        overlap
                    )
                    for _, part: BasePart in ipairs(parts) do
                        fireContact(handle, part)
                    end
                end

                -- Silent rotation puts the character back the way the player
                -- left it, so the camera never fights the aura.
                if rotation == "Silent" and root and originalCFrame then
                    root.CFrame = originalCFrame :: CFrame
                end

                clearHighlights(keep)
            end)
        end,
    })

    -- Melee only, and only when asked.
    --
    -- This list used to offer everything the client owned: bows, blocks, the
    -- first-person rig ("RightUpperArm"), animation tracks, the emote wheel.
    -- None of those can be swung, and burying the sword among them is worse
    -- than showing nothing. The library now answers one question — is this a
    -- blade, a haft or a fist — and only those are listed. Leave every row
    -- unticked and the aura swings whatever is in your hands, which is what
    -- most games need.
    aura:CreateList({
        Name = "Weapons",
        Items = function(): {string}
            if not weapons then
                return {}
            end
            return weapons:Labels({All = true, Melee = true})
        end,
        -- Blank on purpose — the user read "auto" as a stuck value. The
        -- tooltip still explains that empty means whatever you hold.
        EmptyText = "",
        Tooltip = "Melee weapons this module may swing: tools, view models, "
            .. "inventory slots and the game's own attack button. Empty means "
            .. "whatever you are holding.",
    })
    aura:CreateTextBox({
        Name = "Weapon name",
        Default = "",
        Tooltip = "Part of the tool's name. Leave empty and the module uses "
            .. "whatever you last swung by hand.",
    })
    aura:CreateButton({
        Name = "Bind held tool",
        Tooltip = "Remembers whatever is in your hands right now.",
        Function = function(): ()
            local tool: Tool? = equippedTool()
            if not tool then
                aura:Notify("nothing equipped")
                return
            end
            learnedWeapon = (tool :: Tool).Name
            aura:Notify((tool :: Tool).Name .. " bound")
        end,
    })
    aura:CreateSlider({
        Name = "Reach",
        Min = 5,
        Max = 60,
        Default = 18,
        Tooltip = "Distance at which the weapon swings and its touch events "
            .. "fire. This is the only Kill Aura distance.",
    })
    aura:CreateSlider({
        Name = "Max targets",
        Min = 1,
        Max = 10,
        Default = 3,
        Tooltip = "How many valid players or NPCs one swing may hit. One "
            .. "sticks to the best target.",
    })
    aura:CreateDropdown({
        Name = "Priority",
        List = {"Distance", "Health", "Threat"},
        Index = 1,
        Tooltip = "Which target comes first: nearest, weakest, or the one "
            .. "most dangerous to you.",
    })
    aura:CreateSlider({
        Name = "Swings per second",
        Min = 1,
        Max = 20,
        Default = 8,
        Tooltip = "A fast human clicks about 8-12 times a second. Twenty is "
            .. "not a person, and a server that logs click rates knows it.",
    })

    aura:CreateDropdown({
        Name = "Activation",
        List = {"Always", "Hold key"},
        Index = 1,
    })
    aura:CreateBind({
        Name = "Hold key",
        Show = {Option = "Activation", Values = {"Hold key"}},
        Default = Enum.KeyCode.Unknown,
    })
    aura:CreateSlider({
        Name = "Field of view",
        Min = 30,
        Max = 360,
        Default = 360,
        Tooltip = "Degrees around your character. 360 scans every direction; "
            .. "this is not cursor aim.",
    })
    aura:CreateDropdown({
        Name = "Rotation",
        List = {"Off", "Silent", "Face"},
        Index = 2,
        Tooltip = "Silent turns you for the swing only and puts you back; "
            .. "Face keeps you pointed at the target.",
    })
    aura:CreateSlider({
        Name = "Hits per swing",
        Min = 1,
        Max = 8,
        Default = 1,
        Tooltip = "How many times the weapon is pressed for each swing the "
            .. "rate allows. Some games count every press.",
    })
    aura:CreateToggle({
        Name = "Hit through walls",
        Default = true,
        Tooltip = "Fire contact damage even when the target is behind "
            .. "geometry. Independent of the wall check, which decides "
            .. "whether the target is picked at all.",
    })
    aura:CreateToggle({
        Name = "Contact damage",
        Default = true,
        Tooltip = "Also fire the weapon's touch events. Needed by most melee "
            .. "weapons; requires firetouchinterest.",
    })
    aura:CreateToggle({
        Name = "Wall check",
        Default = false,
        Tooltip = "Off by default: the aura hits through walls and floors "
            .. "until you ask it not to.",
    })
    aura:CreateToggle({
        Name = "Team check",
        Default = true,
        Tooltip = "Skip teammates and Friend List entries.",
    })
    aura:CreateToggle({
        Name = "Target NPCs",
        Default = false,
        Tooltip = "Include non-player humanoid models in the reach scan.",
    })
    aura:CreateToggle({
        Name = "Require tool",
        Default = false,
        Tooltip = "Do nothing while your hands are empty.",
    })
    aura:CreateToggle({
        Name = "Auto equip",
        Default = false,
        Tooltip = "Pull the weapon out of the backpack when empty-handed. Off "
            .. "by default: most games this module helps in do not need "
            .. "anything in your hands at all.",
        Function = function(value: boolean): ()
            if weapons then
                weapons:SetAllowEquip(value)
            end
        end,
    })
    aura:CreateToggle({
        Name = "Highlight targets",
        Default = false,
    })
    aura:CreateColor({
        Name = "Highlight colour",
        Show = {Option = "Highlight targets"},
        Default = Color3.fromRGB(235, 110, 110),
    })

    aura:CreateNote(
        "Safe band: 8-12 swings a second and a reach close to the weapon's "
            .. "own. Reach is the only distance this card reads; there is no "
            .. "second, longer one. Friend List protects players from this "
            .. "module in every game."
    )

    activeCleanup = function(): ()
        clearHighlights()
    end
    Module.Initialized = true
    return aura
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
