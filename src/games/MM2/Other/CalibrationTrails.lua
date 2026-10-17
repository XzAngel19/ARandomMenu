local Module = {Name = "MM2 Calibration Trails", Initialized = false}
local activeCleanup = function() end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local core = state.mm2Core
    assert(core and state.mm2CalibrationFeature, "TrailESP requires Calibration")
    local options = {trailEsp = false, color = Color3.fromRGB(100, 185, 255)}
    local trailFolder: Folder? = nil
    local connection: any = nil
    local function ensureTrailFolder(): Folder
        if not trailFolder or not trailFolder.Parent then
            trailFolder = Instance.new("Folder")
            trailFolder.Name = "MM2TrailESP"
            trailFolder.Parent = workspace
        end
        -- Bound transient visuals even if many players fire together.
        local children: {Instance} = trailFolder:GetChildren()
        while #children >= 64 do
            children[1]:Destroy()
            table.remove(children, 1)
        end
        return trailFolder :: Folder
    end

    local function clearTrails(): ()
        if trailFolder then
            pcall(function(): () trailFolder:Destroy() end)
            trailFolder = nil
        end
    end

    local function drawShotTrail(origin: Vector3, hit: Vector3, hitPart: any): ()
        local folder: Folder = ensureTrailFolder()
        local segment: Vector3 = hit - origin
        local length: number = segment.Magnitude
        if options.trailEsp and length > 0.5 then
            local beam: Part = Instance.new("Part")
            beam.Name = "TrailSegment"
            beam.Anchored = true
            beam.CanCollide = false
            beam.CanQuery = false
            beam.CanTouch = false
            beam.CastShadow = false
            beam.Material = Enum.Material.Neon
            beam.Color = options.color
            beam.Transparency = 0.25
            beam.Size = Vector3.new(0.07, 0.07, length)
            beam.CFrame = CFrame.lookAt(origin + segment * 0.5, hit)
            beam.Parent = folder
            pcall(function(): ()
                TweenService:Create(
                    beam,
                    TweenInfo.new(1.4, Enum.EasingStyle.Linear),
                    { Transparency = 1 }
                ):Play()
            end)
            task.delay(1.55, function(): ()
                if beam.Parent then
                    pcall(function(): () beam:Destroy() end)
                end
            end)
        end
        -- Pixel-sized ring at the reported endpoint; never highlight the
        -- entire hitPart (a single hitPart can be a whole wall).
        local anchor: Part = Instance.new("Part")
        anchor.Name = "TrailLanding"
        anchor.Size = Vector3.new(0.02, 0.02, 0.02)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanQuery = false
        anchor.CanTouch = false
        anchor.Position = hit
        anchor.Parent = folder
        local billboard: BillboardGui = Instance.new("BillboardGui")
        billboard.Name = "LandingCircle"
        billboard.Adornee = anchor
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(12, 12)
        billboard.Parent = anchor
        local ring: Frame = Instance.new("Frame")
        ring.Size = UDim2.fromScale(1, 1)
        ring.BackgroundTransparency = 1
        ring.Parent = billboard
        local corner: UICorner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = ring
        local stroke: UIStroke = Instance.new("UIStroke")
        stroke.Color = options.color
        stroke.Thickness = 2
        stroke.Parent = ring
        task.delay(1.55, function(): ()
            if anchor.Parent then anchor:Destroy() end
        end)
    end


    local function toggle(enabled: boolean)
        options.trailEsp = enabled
        if connection then connection:Disconnect(); connection = nil end
        clearTrails()
        if not enabled then return end
        local ok, service = pcall(core.getWeaponServiceModule)
        if not ok or type(service) ~= "table" or not service.GunFired then return end
        local connected, result = pcall(function()
            return service.GunFired.OnClientEvent:Connect(function(_handle, origin, hit, hitPart)
                if not options.trailEsp then return end
                local function position(value)
                    local v = typeof(value) == "Vector3" and value
                        or typeof(value) == "CFrame" and value.Position or nil
                    if v and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e7 then return v end
                    return nil
                end
                local a, b = position(origin), position(hit)
                if a and b then drawShotTrail(a, b, hitPart) end
            end)
        end)
        if connected then connection = result end
    end
    local config = configData
    local key = "MM2.Calibration.TrailESP"
    if config.states[key] == nil then config.states[key] = config.states["MM2.WeaponVisuals.TrailESP"] end
    if config.values["MM2.Calibration.Trailcolor"] == nil then
        config.values["MM2.Calibration.Trailcolor"] = config.values["MM2.WeaponVisuals.Trailcolor"]
    end
    addToggleOption(state.mm2CalibrationFeature, "TrailESP", false, toggle,
        "Visualizes replicated GunFired paths/endpoints. Calibration already records shot data; this adds no duplicate recorder.")
    addColorOption(state.mm2CalibrationFeature, "Trail color", options.color, function(color) options.color = color end)
    activeCleanup = function() toggle(false) end
    Module.Initialized = true
    return Module
end
function Module.destroy()
    if not Module.Initialized then return end
    Module.Initialized = false
    activeCleanup()
end
return Module
