local Module = {
    Name = "MM2 Auto Shoot",
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
    assert(type(core) == "table", "MM2 Auto Shoot requires the MM2 core module")
    local prediction: any = state.mm2Prediction
    assert(type(prediction) == "table", "MM2 Auto Shoot requires MM2 Prediction")
    Module.Runtime = runtime
    
    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local isWeaponPathClear: any = core.isWeaponPathClear
    local validateGunShot: any = core.validateGunShot
    local getGunOriginCFrame: any = core.getGunOriginCFrame
    
    local settings = {
        mode = "Shoot",
        wallCheck = true,
        aura = 20,
    }
    
    local autoShootActive = false
    local lastShootAttempt = 0
    
    local function getGun(): Tool?
        local character = LocalPlayer.Character
        if not character then return nil end
        return getPlayerWeapon(LocalPlayer, "Gun", true)
    end
    
    local function findTarget(): Player?
        local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not localRoot then return nil end
        
        local murderer = findMurderer()
        if not murderer then return nil end
        
        local targetRoot = murderer.Character and murderer.Character:FindFirstChild("HumanoidRootPart")
        if not targetRoot then return nil end
        
        local distance = (targetRoot.Position - localRoot.Position).Magnitude
        if distance > settings.aura then return nil end
        
        if not isPlayerAlive(murderer) or isProtectedTarget(murderer) then
            return nil
        end
        
        return murderer
    end
    
    local function tryCframeShoot(target: Player): boolean
        local character = LocalPlayer.Character
        local gun = getGun()
        if not character or not gun then return false end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not root or not targetRoot then return false end
        
        -- Teleport near target (5 studs behind)
        local offset = targetRoot.CFrame.LookVector * -5
        local newCFrame = targetRoot.CFrame + offset
        root.CFrame = newCFrame
        
        -- Wait a frame for position to sync
        task.wait(0.05)
        
        -- Fire the gun
        gun:Activate()
        return true
    end
    
    local function tryNormalShoot(target: Player): boolean
        local gun = getGun()
        if not gun then return false end
        
        local character = LocalPlayer.Character
        if not character then return false end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not root or not targetRoot then return false end
        
        -- Wall check
        if settings.wallCheck then
            local origin = root.Position
            local endpoint = targetRoot.Position
            if not isWeaponPathClear(origin, endpoint, {}) then
                return false
            end
        end
        
        -- Fire the gun
        gun:Activate()
        return true
    end
    
    local function autoShootTick(): ()
        if not autoShootActive then return end
        
        local now = os.clock()
        if now - lastShootAttempt < 0.1 then return end
        lastShootAttempt = now
        
        local gun = getGun()
        if not gun then return end
        
        local target = findTarget()
        if not target then return end
        
        if settings.mode == "Cframe" then
            tryCframeShoot(target)
        else
            tryNormalShoot(target)
        end
    end
    
    local function toggleAutoShoot(enabled: boolean): ()
        autoShootActive = enabled
        
        if enabled then
            featureConnections.MM2AutoShoot = TaskManager:Connect(autoShootTick)
            autoShootTick()
        else
            disconnectFeatureConnection("MM2AutoShoot")
        end
    end
    
    local AutoShootFeature: any = createUniversalFeature(
        "Auto Shoot",
        "Automatically shoots at the murderer when they're within aura range. Use CFrame mode to teleport near the target before shooting, or Shoot mode for normal silent aim.",
        4,
        toggleAutoShoot,
        {
            categoryName = "Combat",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoShootFeature = AutoShootFeature
    
    addCycleOption(AutoShootFeature, "Mode", {"Shoot", "Cframe"}, 1,
        function(value: string): ()
            settings.mode = value
        end,
        "Shoot: normal silent aim. CFrame: teleport near target before shooting.")
    
    addToggleOption(AutoShootFeature, "WallCheck", true,
        function(value: boolean): ()
            settings.wallCheck = value
        end,
        "Only shoot if there's a clear path to the target.")
    
    addNumberOption(AutoShootFeature, "Aura", 20, 5, 40,
        function(value: number): ()
            settings.aura = value
            if AutoShootFeature.enabled then
                AutoShootFeature:SetStatus(tostring(value) .. " studs")
            end
        end,
        "Maximum distance in studs to automatically shoot at the murderer.", 1)
    
    activeCleanup = function(): ()
        toggleAutoShoot(false)
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
