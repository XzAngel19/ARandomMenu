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

    -- Simulate one user input. The old build relied on a single legacy
    -- call (VirtualUser:CaptureController + ClickButton2 at (0,0)):
    -- on current clients the capture silently does nothing, so the
    -- handler ran, "worked", and the idle kick landed anyway. Every
    -- strategy is tried in order until one reports success, and a
    -- failure is never mistaken for a success again.
    local function pokeAfk(): boolean
        local camera: any = nil
        pcall(function(): ()
            camera = (host.workspace :: any).CurrentCamera
        end)
        local centre: Vector2 = Vector2.new(400, 300)
        if camera and camera.ViewportSize then
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

        -- Reactive: Roblox warns through Idled shortly before the
        -- 20-minute kick. Answer it.
        featureConnections.AntiAFK = LocalPlayer.Idled:Connect(function(): ()
            pokeAfk()
        end)
        -- Proactive: never let the idle timer get anywhere near the
        -- kick in the first place. Simulated input every 150 s keeps
        -- the session "active" even if the Idled event never fires
        -- (it does not fire while some menus hold focus).
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
        )
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
    addFeatureTooltip(AntiAfkFeature, "Simulates a real input every ~150 seconds and "
        .. "answers Roblox's idle warning, so the 20-minute idle kick never lands. "
        .. "Tries VirtualUser first, then VirtualInputManager. Disconnects immediately when disabled.")

    activeCleanup = function(): ()
        disconnectFeatureConnection("AntiAFK")
        disconnectFeatureConnection("AntiAFKTimer")
    end
    Module.Initialized = true
    return AntiAfkFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
