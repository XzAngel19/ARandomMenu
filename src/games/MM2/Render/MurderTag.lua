local Module = {
    Name = "MM2 Murder Tag",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Murder Tag requires the MM2 core module")
    Module.Runtime = runtime
    local findMurderer: any = core.findMurderer
    local mm2Settings: any = core.mm2Settings

    -- ---------------------------------------------------------------------------
    -- Murder tag: a single "Murder" billboard over the current murderer's head.
    -- Deliberately independent from Role Tags so it can stay on without
    -- enabling the full per-player nametag set.
    -- ---------------------------------------------------------------------------
    local MurderTagEffects = create("Folder", {
        Parent = core.MM2Effects,
        Name = "MurderTag",
    })

    type MurderTagRecord = {
        billboard: BillboardGui,
        label: TextLabel,
        reference: ObjectValue,
        head: BasePart?,
    }

    local tag: MurderTagRecord? = nil

    local function destroyTag(): ()
        if tag then
            tag.billboard:Destroy()
            tag.reference:Destroy()
            tag = nil
        end
    end

    local function createTag(head: BasePart): MurderTagRecord
        local billboard: BillboardGui = Instance.new("BillboardGui")
        billboard.Name = "Wurst_MurderTag"
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.Size = UDim2.fromOffset(150, 22)
        -- Role Tags sit at 2.7 studs when enabled; sit higher so the two do
        -- not overlap.
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.MaxDistance = 1500
        billboard.Adornee = head
        -- A BillboardGui nested inside a ScreenGui never renders (nested layer
        -- collectors are skipped), so it lives on the part like the rest of the
        -- MM2 markers and the folder only keeps a reference for cleanup.
        billboard.Parent = head

        local reference: ObjectValue = Instance.new("ObjectValue")
        reference.Name = "MurderTagReference"
        reference.Value = billboard
        reference.Parent = MurderTagEffects

        local label: TextLabel = Instance.new("TextLabel")
        label.Name = "Murder"
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.FontFace = CONTROL_FONT
        label.TextSize = 14
        label.TextScaled = false
        label.Text = "Murder"
        label.TextColor3 = mm2Settings.murdererColor
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.TextStrokeTransparency = 0.3
        label.Parent = billboard

        return {
            billboard = billboard,
            label = label,
            reference = reference,
            head = head,
        }
    end

    local function refreshTag(): ()
        local murderer: Player? = findMurderer()
        local character: Model? = murderer and murderer.Character or nil
        local head: BasePart? = character
            and (character:FindFirstChild("Head")
                or character:FindFirstChild("HumanoidRootPart"))
            :: BasePart?
        if not head then
            destroyTag()
            return
        end
        -- Head dies with the character (and the round hands the knife to
        -- someone else), so a dead adornee means a full rebuild.
        if tag and (not tag.billboard.Parent or tag.head ~= head) then
            destroyTag()
        end
        if not tag then
            tag = createTag(head :: BasePart)
        end
        -- Re-applied every pass so the live colour picker takes effect without
        -- waiting for a rebuild.
        local colour: Color3 = mm2Settings.murdererColor
        if tag.label.TextColor3 ~= colour then
            tag.label.TextColor3 = colour
        end
    end

    local murderTagEnabled: boolean = false

    local function toggleMurderTag(enabled: boolean): ()
        murderTagEnabled = enabled
        disconnectFeatureConnection("MM2MurderTag")
        destroyTag()
        if not enabled then
            return
        end
        local elapsed: number = 1
        featureConnections.MM2MurderTag = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.2 then
                return
            end
            elapsed = 0
            refreshTag()
        end)
    end

    local unsubscribeRoles: () -> () = core.onRoundRoles(function(): ()
        if murderTagEnabled then
            refreshTag()
        end
    end)

    -- Default on: the point of the card is that the tag shows without hunting
    -- for a second toggle. A stored user choice still wins over the default.
    if type(configData) == "table" and type(configData.states) == "table"
        and configData.states["MM2.MurderTag"] == nil then
        configData.states["MM2.MurderTag"] = true
        queueConfigSave()
    end

    createUniversalFeature(
        "Murder Tag",
        "A 'Murder' tag floating above the murderer's head, always visible",
        14,
        toggleMurderTag,
        {
            noOptions = true,
            categoryName = "Render",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    activeCleanup = function(): ()
        pcall(unsubscribeRoles)
        toggleMurderTag(false)
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
