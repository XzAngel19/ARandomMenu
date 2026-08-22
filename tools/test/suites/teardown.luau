--!strict
--
-- Headless tests: teardown.
--
-- Loaded by tools/test/run.luau. Suites share one world through the context
-- so the checks stay under Luau's 200-local ceiling without wrapping
-- sections in do-end.
--
return function(ctx: any): ()
    local world: any = ctx.world
    local stub: any = ctx.stub
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local entity: any = ctx.entity
    local enemy: any = ctx.enemy
    local weapons: any = ctx.weapons
    local DisguiseFile: any = ctx.DisguiseFile
    local AnimationFile: any = ctx.AnimationFile
    local EmoteFile: any = ctx.EmoteFile
    local LoggerFile: any = ctx.LoggerFile
    local ItemFile: any = ctx.ItemFile
    local WeaponsFile: any = ctx.WeaponsFile
    local RenderFile: any = ctx.RenderFile
    local ClickFile: any = ctx.ClickFile
    local ClickerFile: any = ctx.ClickerFile
    local AuraFile: any = ctx.AuraFile
    local FriendFile: any = ctx.FriendFile
    local EspFile: any = ctx.EspFile
    local TriggerFile: any = ctx.TriggerFile
    local EntityFile: any = ctx.EntityFile
    local FrameworkFile: any = ctx.FrameworkFile
    local framework: any = ctx.framework

    section("Performance")

    -- One refresh per frame no matter how many modules ask. Three consumers in the
    -- same frame used to mean three full sweeps of the player list. The clock
    -- is nudged first so a budget sample that just ran does not eat this frame.
    world.clock += 0.2
    local sweeps: number = 0
    local realPlayers: any = world.players.GetPlayers
    world.players.GetPlayers = function(self: any): {any}
        sweeps += 1
        return realPlayers(self)
    end
    entity:Refresh()
    entity:Refresh()
    entity:Refresh()
    check("repeated refreshes in one frame do the work once", sweeps == 1,
        "sweeps: " .. tostring(sweeps))
    world.clock += 0.2
    entity:Refresh()
    check("a later frame refreshes again", sweeps == 2, "sweeps: " .. tostring(sweeps))
    world.players.GetPlayers = realPlayers

    -- Rig lookups are cached: fourteen FindFirstChild pairs per player per frame
    -- was pure waste.
    local firstRig: any = entity:Rig(entity:Get(enemy))
    local secondRig: any = entity:Rig(entity:Get(enemy))
    check("rig bones are cached per character", rawequal(firstRig, secondRig))

    -- The weapon scan walks the whole PlayerGui, so it is cached too.
    local guiWalks: number = 0
    local realGetDescendants: any = nil
    local playerGuiForCount: any = world.localPlayer:FindFirstChild("PlayerGui")
    if playerGuiForCount then
        realGetDescendants = playerGuiForCount.GetDescendants
        playerGuiForCount.GetDescendants = function(self: any): {any}
            guiWalks += 1
            return realGetDescendants(self)
        end
    end
    weapons:Invalidate()
    weapons:Scan({All = true})
    weapons:Scan({All = true})
    weapons:Scan({All = true})
    check("weapon scans are cached", guiWalks == 1, "walks: " .. tostring(guiWalks))
    if playerGuiForCount then
        playerGuiForCount.GetDescendants = realGetDescendants
    end

    section("Teardown")

    DisguiseFile.destroy()
    AnimationFile.destroy()
    EmoteFile.destroy()
    LoggerFile.destroy()
    ItemFile.destroy()
    WeaponsFile.destroy()
    RenderFile.destroy()
    ClickFile.destroy()
    ClickerFile.destroy()
    AuraFile.destroy()
    FriendFile.destroy()
    EspFile.destroy()
    TriggerFile.destroy()
    EntityFile.destroy()
    FrameworkFile.destroy()
    check("framework releases its modules", framework.Order ~= nil and #framework.Order == 0)
    check("no task callbacks survive teardown", stub.taskCount() == 0,
        "tasks left: " .. tostring(stub.taskCount()))
end
