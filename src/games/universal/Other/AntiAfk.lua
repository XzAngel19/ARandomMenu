export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AntiAfk",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip

    -- Try the available executor input methods in order. A successful API
    -- call alone does not prove that Roblox reset its server idle timer.
    local function pokeAfk(): boolean
        local camera: Camera? = host.workspace.CurrentCamera
        local centre: Vector2 = Vector2.new(400, 300)
        if camera then
            centre = camera.ViewportSize / 2
        end

        -- Strategy 1: VirtualUser button press (the classic path, but
        -- as an explicit down/up instead of a corner click).
        local virtualUser: any = nil
        pcall(function(): ()
            virtualUser = (game :: any):GetService("VirtualUser")
        end)
        if virtualUser then
            local ok: boolean = pcall(function(): ()
                virtualUser:CaptureController()
                virtualUser:Button2Down(centre, camera and camera.CFrame)
                virtualUser:Button2Up(centre, camera and camera.CFrame)
            end)
            if ok then
                return true
            end
            local legacyOk: boolean = pcall(function(): ()
                virtualUser:ClickButton2(centre)
            end)
            if legacyOk then
                return true
            end
        end

        -- Strategy 2: VirtualInputManager mouse event at screen centre.
        local virtualInput: any = nil
        pcall(function(): ()
            virtualInput = (game :: any):GetService("VirtualInputManager")
        end)
        if virtualInput then
            local ok: boolean = pcall(function(): ()
                virtualInput:SendMouseButtonEvent(centre.X, centre.Y, 0, true, game, false)
                virtualInput:SendMouseButtonEvent(centre.X, centre.Y, 0, false, game, false)
            end)
            if ok then
                return true
            end
        end
        return false
    end

    local function toggleAntiAfk(enabled: boolean): ()
        disconnectFeatureConnection("AntiAFK")
        disconnectFeatureConnection("AntiAFKTimer")

        if not enabled then
            return
        end

        -- Reactive: respond to the local Idled event.
        featureConnections.AntiAFK = LocalPlayer.Idled:Connect(function(): ()
            pokeAfk()
        end)
        -- Also attempt input every 150 seconds if Idled is not raised.
        local elapsed: number = 0
        featureConnections.AntiAFKTimer = host.TaskManager:Connect(
            function(deltaTime: number): ()
                elapsed += deltaTime
                if elapsed < 150 then
                    return
                end
                elapsed = 0
                pokeAfk()
            end
        , nil, "Anti AFK")
    end

    local AntiAfkFeature = createUniversalFeature(
        "Anti AFK",
        "Simulate input before Roblox's idle kick (about every 2.5 minutes, and on the idle warning)",
        13,
        toggleAntiAfk,
        {
            noOptions = true,
            configKey = "Universal.AntiAFK",
            categoryName = "World",
        }
    )
    addFeatureTooltip(AntiAfkFeature, "Attempts input every ~150 seconds and on Idled. "
        .. "Tries VirtualUser first, then VirtualInputManager; availability depends on the executor. "
        .. "Disconnects immediately when disabled.")

    activeCleanup = function(): ()
        disconnectFeatureConnection("AntiAFK")
        disconnectFeatureConnection("AntiAFKTimer")
    end
    Module.Initialized = true
    return AntiAfkFeature
end

function Module.destroy(): ()
    if activeCleanup then
        activeCleanup()
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
