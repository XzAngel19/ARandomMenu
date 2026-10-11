export type Runtime = {
    framework: any,
    entity: any,
    render: any,
    host: any,
    services: any,
}

local Module = {
    Name = "NPCESP",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

-- Normalized names of the parts every R6/R15 character rig is built from.
-- Character-shaped models (including display statues of players) are built
-- from these; random props and creature rigs are not.
local STANDARD_PART_NAMES: {[string]: boolean} = {
    head = true,
    torso = true,
    uppertorso = true,
    lowertorso = true,
    humanoidrootpart = true,
    leftarm = true,
    rightarm = true,
    leftleg = true,
    rightleg = true,
    leftupperarm = true,
    leftlowerarm = true,
    lefthand = true,
    rightupperarm = true,
    rightlowerarm = true,
    righthand = true,
    leftupperleg = true,
    leftlowerleg = true,
    leftfoot = true,
    rightupperleg = true,
    rightlowerleg = true,
    rightfoot = true,
}

-- A model re-classified more often than this keeps its previous verdict until
-- the burst of changes settles, so a streaming model never turns
-- reclassification into a per-frame cost.
local VERDICT_COOLDOWN: number = 0.5

local function normalizeName(value: string): string
    local normalized: string = string.lower(value):gsub("[%s_%-]", "")
    return normalized
end

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local render: any = context.render
    local host: any = context.host
    local players: Players = host.Players
    local currentWorkspace: Workspace = host.workspace or workspace
    local layer: Frame = render:Layer("NpcEspLayer")
    local lastStatusAt: number = -math.huge
    local lastSweepAt: number = -math.huge

    -- Tracked models, their resolved root/humanoid, and the structural
    -- verdict per model: "rig" is a character-shaped model (with or without
    -- a living Humanoid — display statues count), "creature" merely carries a
    -- Humanoid, "reject" is neither. Verdicts and rig info are weak so
    -- destroyed models never leak, and both are only recomputed when the
    -- model's direct children actually change.
    local bots: {[Model]: boolean} = {}
    local rigInfo: any = setmetatable({}, {__mode = "k"})
    local verdicts: any = setmetatable({}, {__mode = "k"})
    local forcedNames: {string} = {}

    local function modelFor(instance: Instance): Model?
        if instance:IsA("Model") then
            return instance :: Model
        end
        return instance:FindFirstAncestorOfClass("Model") :: Model?
    end

    local function isPlayerCharacterModel(model: Model): boolean
        if players:GetPlayerFromCharacter(model) ~= nil then
            return true
        end
        for _, player: Player in ipairs(players:GetPlayers()) do
            local character: Model? = player.Character
            if character and model:IsDescendantOf(character) then
                return true
            end
        end
        return false
    end

    local function matchesForcedName(model: Model): boolean
        local name: string = string.lower(model.Name)
        for _, needle: string in ipairs(forcedNames) do
            if needle ~= "" and string.find(name, needle, 1, true) then
                return true
            end
        end
        return false
    end

    -- Classification only inspects direct children, which is what a character
    -- rig is made of, so even huge models cost one GetChildren call.
    local function classify(model: Model): string
        -- The local Disguise body double is scenery, not an NPC.
        if model:GetAttribute("WurstDisguise") == true then
            return "reject"
        end
        if matchesForcedName(model) then
            return "rig"
        end
        local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local standardParts: number = 0
        local motors: number = 0
        for _, child: Instance in ipairs(model:GetChildren()) do
            if child:IsA("BasePart") then
                if STANDARD_PART_NAMES[normalizeName(child.Name)] then
                    standardParts += 1
                end
            elseif child:IsA("Motor6D") then
                motors += 1
            end
        end
        if humanoid ~= nil then
            -- A character model is still a character model when its Humanoid
            -- is dead or purely decorative; health never gates detection.
            if standardParts >= 3 then
                return "rig"
            end
            return "creature"
        end
        -- Humanoid-less character structures: display rigs and statues keep
        -- the standard limbs (and usually their Motor6D joints).
        if standardParts >= 4 or (standardParts >= 3 and motors >= 2) then
            return "rig"
        end
        if model:FindFirstChildWhichIsA("Humanoid", true) ~= nil then
            return "creature"
        end
        return "reject"
    end

    local function verdictFor(model: Model): string
        local entry: any = verdicts[model]
        if entry == nil then
            entry = {
                verdict = isPlayerCharacterModel(model) and "reject" or classify(model),
                at = os.clock(),
                dirty = false,
            }
            verdicts[model] = entry
            return entry.verdict
        end
        if entry.dirty then
            local now: number = os.clock()
            if now - entry.at >= VERDICT_COOLDOWN then
                entry.verdict =
                    isPlayerCharacterModel(model) and "reject" or classify(model)
                entry.at = now
                entry.dirty = false
            end
        end
        return entry.verdict
    end

    local function markDirty(model: Model): ()
        local entry: any = verdicts[model]
        if entry and not entry.dirty then
            entry.dirty = true
        end
        rigInfo[model] = nil
    end

    -- Only the model whose direct children changed needs a fresh look.
    local function invalidate(instance: Instance): ()
        local parent: Instance? = instance.Parent
        if parent and parent:IsA("Model") then
            markDirty(parent :: Model)
        end
        if instance:IsA("Model") then
            markDirty(instance :: Model)
        end
    end

    local function add(model: Model, verdict: string): ()
        if verdict ~= "rig" then
            bots[model] = true
            return
        end
        -- Prefer the innermost rig so a rig nested inside a wrapper never
        -- draws two boxes.
        for existing: Model in pairs(bots) do
            if existing:IsDescendantOf(model) then
                return
            end
            if model:IsDescendantOf(existing) then
                bots[existing] = nil
                render:Release(layer, existing)
            end
        end
        bots[model] = true
    end

    local function inspect(instance: Instance): ()
        if not (instance:IsA("Model") or instance:IsA("Humanoid")
            or instance:IsA("BasePart") or instance:IsA("Motor6D")) then
            return
        end
        invalidate(instance)
        local model: Model? = modelFor(instance)
        local creature: Model? = nil
        while model and model ~= currentWorkspace do
            local verdict: string = verdictFor(model)
            if verdict == "rig" then
                add(model, "rig")
                return
            end
            if verdict == "creature" and creature == nil then
                creature = model
            end
            local parent: Instance? = model.Parent
            if not parent then
                break
            end
            model = parent:IsA("Model") and parent :: Model
                or parent:FindFirstAncestorOfClass("Model") :: Model?
        end
        if creature then
            add(creature, "creature")
        end
    end

    -- Models stream in over time; a dirty verdict that no further event
    -- refreshes is settled here so nothing stays undetected.
    local function sweep(now: number): ()
        for model: any, entry: any in pairs(verdicts) do
            if entry.dirty and now - entry.at >= VERDICT_COOLDOWN then
                local resolved: Model = model :: Model
                local verdict: string =
                    isPlayerCharacterModel(resolved) and "reject" or classify(resolved)
                entry.verdict = verdict
                entry.at = now
                entry.dirty = false
                if verdict == "rig" then
                    add(resolved, "rig")
                end
            end
        end
    end

    local function scan(): ()
        table.clear(bots)
        for _, object: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if object:IsA("Model") then
                inspect(object)
            end
        end
    end

    local function clear(): ()
        render:ReleaseAll(layer)
        table.clear(bots)
        layer.Visible = false
    end

    local card: any
    card = framework.Categories.Visuals:CreateModule({
        Name = "NPCESP",
        Category = "Render",
        ConfigKey = "Universal.NPCESP",
        Order = 4,
        Tooltip = "Displays character-shaped NPC models - bots, shopkeepers "
            .. "and display statues like the creator's rig - whether or not "
            .. "their Humanoid is alive.",
        Function = function(enabled: boolean): ()
            layer.Visible = enabled
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            scan()
            card:Event(currentWorkspace.DescendantAdded, inspect)
            card:Event(currentWorkspace.DescendantRemoving, invalidate)
            card:Render(function(): ()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not camera then
                    return
                end
                local resolvedCamera: Camera = camera :: Camera
                local now: number = os.clock()
                if now - lastSweepAt >= 1 then
                    lastSweepAt = now
                    sweep(now)
                end

                local maxDistance: number = card.Options["Max distance"].Value
                local includeCreatures: boolean = card.Options["All humanoids"].Value
                local localCharacter: Model? = host.LocalPlayer.Character
                local localRoot: BasePart? = localCharacter and (
                    localCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
                    or localCharacter.PrimaryPart
                    or localCharacter:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
                ) or nil
                local origin: Vector3 = localRoot and localRoot.Position
                    or resolvedCamera.CFrame.Position
                local count: number = 0
                for model: Model in pairs(bots) do
                    if not model:IsDescendantOf(currentWorkspace)
                        or players:GetPlayerFromCharacter(model) ~= nil then
                        bots[model] = nil
                        render:Release(layer, model)
                        -- The model turned out to be a player character; pin
                        -- the verdict so streaming parts do not re-add it.
                        verdicts[model] = {verdict = "reject", at = now, dirty = false}
                        continue
                    end
                    local verdict: string = verdictFor(model)
                    if verdict == "reject" then
                        bots[model] = nil
                        render:Release(layer, model)
                        continue
                    end

                    if verdict == "creature" and not includeCreatures then
                        -- Not tracked right now; make sure nothing is left
                        -- over from a previous frame and move on.
                        render:Release(layer, model)
                        continue
                    end

                    local drawing: any = render:Set(layer, model)

                    local info: any = rigInfo[model]
                    if not (info and info.root and info.root.Parent) then
                        info = {
                            root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
                                or model.PrimaryPart
                                or model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?,
                            humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
                                or model:FindFirstChildWhichIsA("Humanoid", true) :: Humanoid?,
                        }
                        rigInfo[model] = info
                    end
                    local root: BasePart? = info.root
                    if not root or (root.Position - origin).Magnitude > maxDistance then
                        drawing:Show(false)
                        continue
                    end
                    -- Creatures are living things, so a dead one stops
                    -- counting; character rigs stay visible whatever their
                    -- Humanoid says.
                    if verdict == "creature"
                        and info.humanoid
                        and info.humanoid.Health <= 0 then
                        drawing:Show(false)
                        continue
                    end

                    local rect: any = render:ModelRect(resolvedCamera, model)
                    if not rect then
                        drawing:Show(false)
                        continue
                    end

                    local colour: Color3 = card.Options["Colour"].Value
                    drawing:Box(rect, card.Options["Box"].Value and "Full" or "Off", 1, colour)
                    if card.Options["Name"].Value then
                        local text: string = card.Options["Model name"].Value
                            and model.Name ~= "" and model.Name
                            or "BOT"
                        local humanoid: Humanoid? = info.humanoid
                        if humanoid and card.Options["Health"].Value then
                            text ..= " [" .. tostring(math.round(humanoid.Health)) .. "]"
                        end
                        drawing:Label(
                            "NameTag",
                            text,
                            Vector2.new(rect.centreX, rect.top - 4),
                            1,
                            13,
                            colour,
                            true
                        )
                    else
                        drawing:HideLabel("NameTag")
                    end
                    drawing:Highlight(
                        model,
                        colour,
                        0.55,
                        not card.Options["Highlight"].Value and "Off"
                            or (card.Options["Through walls"].Value and "AlwaysOnTop" or "Occluded")
                    )
                    drawing:Show(true)
                    count += 1
                end

                if now - lastStatusAt >= 0.25 then
                    lastStatusAt = now
                    card:SetStatus(tostring(count))
                end
            end)
            card:Clean(clear)
        end,
    })

    card:CreateToggle({Name = "Box", Default = true})
    card:CreateToggle({Name = "Highlight", Default = true})
    card:CreateToggle({Name = "Through walls", Default = true, Show = {Option = "Highlight"}})
    card:CreateToggle({Name = "Name", Default = true})
    card:CreateToggle({
        Name = "Model name",
        Show = {Option = "Name"},
        Default = false,
        Tooltip = "Label each model with its own name instead of BOT.",
    })
    card:CreateToggle({
        Name = "Health",
        Show = {Option = "Name"},
        Default = true,
        Tooltip = "Append the Humanoid's hit points to the label when the "
            .. "model has one.",
    })
    card:CreateToggle({
        Name = "All humanoids",
        Default = false,
        Tooltip = "Also flag non-character models that merely carry a living "
            .. "Humanoid (creatures, monsters). Off by default: NPCESP tracks "
            .. "character-shaped rigs.",
    })
    card:CreateColor({Name = "Colour", Default = Color3.new(1, 1, 1)})
    card:CreateSlider({Name = "Max distance", Min = 25, Max = 2000, Step = 25, Default = 500})

    local addBox: any
    addBox = card:CreateTextBox({
        Name = "Force by name",
        Default = "",
        Tooltip = "Type a model name and it is always treated as an NPC rig, "
            .. "whatever it is built from. Partial names match, so statue "
            .. "catches CreatorStatue.",
        Function = function(value: string): ()
            local trimmed: string = string.match(value, "^%s*(.-)%s*$") or value
            if trimmed == "" then
                return
            end
            local needle: string = string.lower(trimmed)
            if not table.find(forcedNames, needle) then
                table.insert(forcedNames, needle)
            end
            table.clear(verdicts)
            table.clear(rigInfo)
            if card.Enabled then
                scan()
            end
            addBox:Set("")
        end,
    })

    card:CreateButton({
        Name = "Clear forced names",
        Function = function(): ()
            table.clear(forcedNames)
            table.clear(verdicts)
            table.clear(rigInfo)
            if card.Enabled then
                scan()
            end
        end,
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
