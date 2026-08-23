--!strict
--
-- Headless tests: spoof.
--
-- Loaded by tools/test/run.luau. Suites share one world through the context
-- so the checks stay under Luau's 200-local ceiling without wrapping
-- sections in do-end.
--
return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local espContext: any = ctx.espContext
    local enemy: any = ctx.enemy

    section("Spoof")

    host.state.spoofScroll = Mock.newInstance("ScrollingFrame")
    host.state.spoofFeatures = {}

    local DisguiseFile: any = require("../../../src/modules/Spoof/Disguise")
    Mock.inject(world, DisguiseFile.init)
    local disguise: any = DisguiseFile.init(espContext)
    check("disguise card is registered", disguise.Name == "Disguise")
    for _, name: string in ipairs({
        "User",
        "Apply",
        "Keep on respawn",
        "Take animations",
        "Take emotes",
    }) do
        check("disguise option: " .. name, disguise.Options[name] ~= nil)
    end

    -- The avatar this user "has": two animation ids and one equipped emote.
    local targetAvatar: any = Mock.newInstance("HumanoidDescription")
    targetAvatar.IdleAnimation = 111
    targetAvatar.RunAnimation = 222
    function targetAvatar:GetEmotes(): any
        return {Salute = {507770239}}
    end
    world.avatars[42] = targetAvatar

    local localHumanoid: any =
        world.localPlayer.Character:FindFirstChildOfClass("Humanoid")
    disguise.Options["User"].Value = "42"
    disguise:Toggle()
    check("disguise enables", disguise.Enabled == true)
    check("the target's avatar is worn",
        localHumanoid.AppliedDescription == targetAvatar,
        tostring(localHumanoid.AppliedDescription))
    check("their emotes reach the emote player",
        #(host.state.spoofEmotes or {}) == 1
            and host.state.spoofEmotes[1].id == 507770239,
        tostring(#(host.state.spoofEmotes or {})))

    disguise:Toggle()
    check("disguise disables", disguise.Enabled == false)
    check("your own avatar comes back",
        localHumanoid.AppliedDescription ~= targetAvatar)

    local AnimationFile: any = require("../../../src/modules/Spoof/AnimationChanger")
    Mock.inject(world, AnimationFile.init)
    local animations: any = AnimationFile.init(espContext)
    check("animation changer is registered", animations.Name == "Animation Changer")
    for _, name: string in ipairs({"Pack", "Custom ID", "Save ID", "Apply", "Reset"}) do
        check("animation option: " .. name, animations.Options[name] ~= nil)
    end

    -- The classic packs ship with the module: no search, no fetch, the
    -- catalog is part of the contract and full at require time.
    do
        local names: {[string]: boolean} = {}
        local shipped: number = 0
        for _, pack: any in ipairs(AnimationFile.builtinPacks or {}) do
            names[tostring(pack.name)] = true
            shipped += 1
            local slots: number = 0
            for _ in pairs(pack.ids or {}) do
                slots += 1
            end
            check("pack " .. tostring(pack.name) .. " carries seven slots",
                slots == 7, tostring(slots))
        end
        check("sixteen packs ship with the module", shipped == 16, tostring(shipped))
        check("the classics are all present",
            names["Ninja"] == true and names["Zombie"] == true
                and names["Astronaut"] == true and names["Robot"] == true
                and names["Werewolf"] == true and names["Vampire"] == true)
    end

    -- Save ID: the Custom ID joins the persisted CSV once, then the
    -- Pack chooser after Refresh. A second click of the same id is a no-op.
    do
        local savedKey: string = "Universal.AnimationChanger.SavedIDs"
        animations.Options["Custom ID"].Value = "619512767"
        animations.Feature.options["Save ID"].run()
        check(
            "Save ID writes the CSV once",
            host.configData.values[savedKey] == "619512767",
            tostring(host.configData.values[savedKey])
        )
        check("Save ID queued a persist", host.saves >= 1)
        local savesAfterFirst: number = host.saves
        animations.Feature.options["Save ID"].run()
        check(
            "Save ID does not duplicate an id",
            host.configData.values[savedKey] == "619512767",
            tostring(host.configData.values[savedKey])
        )
        check("a duplicate Save ID does not persist again", host.saves == savesAfterFirst)
        local listed: {string} = animations.Feature.options["Pack"].itemsList or {}
        local hasSaved: boolean = false
        for _, label: string in ipairs(listed) do
            if label == "Saved 619512767" then
                hasSaved = true
            end
        end
        check("saved id appears in the Pack chooser after Refresh", hasSaved)
        animations.Options["Custom ID"].Value = "1113742618"
        animations.Feature.options["Save ID"].run()
        check(
            "a second Save ID appends",
            host.configData.values[savedKey] == "619512767,1113742618",
            tostring(host.configData.values[savedKey])
        )
        local listedTwo: {string} = animations.Feature.options["Pack"].itemsList or {}
        local hasSecond: boolean = false
        for _, label: string in ipairs(listedTwo) do
            if label == "Saved 1113742618" then
                hasSecond = true
            end
        end
        check("the second saved id appears after Refresh", hasSecond)
    end

    -- The Animate-script path, which is the one that works in a game that ships
    -- its own character scripts.
    local animate: any = Mock.newInstance("LocalScript")
    animate.Name = "Animate"
    animate.Parent = world.localPlayer.Character
    local runFolder: any = Mock.newInstance("Folder")
    runFolder.Name = "run"
    runFolder.Parent = animate
    local runAnim: any = Mock.newInstance("Animation")
    runAnim.Name = "RunAnim"
    runAnim.AnimationId = "rbxassetid://1"
    runAnim.Parent = runFolder
    check("the animate script is rewritten",
        AnimationFile.patchAnimateScript(
            world.localPlayer.Character,
            {RunAnimation = 999}
        ) == true and runAnim.AnimationId == "rbxassetid://999",
        tostring(runAnim.AnimationId))
    check("a character without an animate script is left alone",
        AnimationFile.patchAnimateScript(enemy.Character, {RunAnimation = 999}) == false)

    -- Roblox's default animation packs contain assets such as 619512767. That
    -- id is a container, not a clip Animator can load. Opening it yields the
    -- Animation child whose id belongs in the Animate script.
    local avatarEditor: any = world.globals.game:GetService("AvatarEditorService")
    function avatarEditor:GetItemDetails(_bundleId: number, _itemType: any): any
        return {
            BundledItems = {
                {Name = "Default Run", Id = 619512767},
            },
        }
    end
    local loadedContainer: any = nil
    local opened: {string} = {}
    world.globals.game.GetObjects = function(_self: any, asset: string): {any}
        table.insert(opened, asset)
        local container: any = Mock.newInstance("Folder")
        local clip: any = Mock.newInstance("Animation")
        clip.AnimationId = "rbxassetid://913376220"
        clip.Parent = container
        loadedContainer = container
        return {container}
    end
    Mock.inject(world, AnimationFile.resolveClipId)
    Mock.inject(world, AnimationFile.resolveBundle)
    local resolvedBundle: any = AnimationFile.resolveBundle(12345)
    check(
        "the bundle item is opened before use",
        opened[1] == "rbxassetid://619512767",
        opened[1]
    )
    check("a bundle container resolves to its playable clip",
        resolvedBundle.RunAnimation == 913376220,
        tostring(resolvedBundle.RunAnimation))
    check("the temporary asset container is destroyed",
        loadedContainer ~= nil and loadedContainer.Destroyed == true)

    local EmoteFile: any = require("../../../src/modules/Spoof/EmotePlayer")
    Mock.inject(world, EmoteFile.init)
    local emotePlayer: any = EmoteFile.init(espContext)
    check("emote player is registered", emotePlayer.Name == "Emote Player")
    for _, name: string in ipairs({"Emote", "Custom ID", "Save ID", "Speed", "Loop", "Play", "Stop"}) do
        check("emote option: " .. name, emotePlayer.Options[name] ~= nil)
    end

    emotePlayer:Toggle()
    emotePlayer.Options["Custom ID"].Value = "507770239"
    emotePlayer.Feature.options["Play"].run()
    local animatorInstance: any = localHumanoid:FindFirstChildOfClass("Animator")
    check("the emote is loaded and playing",
        animatorInstance ~= nil
            and #animatorInstance.Tracks == 1
            and animatorInstance.Tracks[1].IsPlaying == true
            and animatorInstance.Tracks[1].AnimationId == "rbxassetid://507770239",
        animatorInstance and tostring(#animatorInstance.Tracks) or "no animator")
    local firstTrack: any = animatorInstance.Tracks[1]
    emotePlayer.Feature.options["Stop"].run()
    check("stopping destroys the track, not only its playback",
        firstTrack.IsPlaying == false and firstTrack.Destroyed == true)

    emotePlayer.Feature.options["Play"].run()
    local oneShot: any = animatorInstance.Tracks[#animatorInstance.Tracks]
    oneShot.Stopped:Fire()
    check("a finished one-shot destroys itself", oneShot.Destroyed == true)

    -- More than Animator's 64-track ceiling can be requested over one session.
    -- At most the current track may remain alive, and teardown owns that one.
    for _ = 1, 70 do
        emotePlayer.Feature.options["Play"].run()
    end
    local liveTracks: number = 0
    for _, track: any in ipairs(animatorInstance.Tracks) do
        if not track.Destroyed then
            liveTracks += 1
        end
    end
    check("replaying never accumulates live tracks past Animator's limit",
        liveTracks == 1, "live tracks: " .. tostring(liveTracks))
    emotePlayer:Toggle()
    liveTracks = 0
    for _, track: any in ipairs(animatorInstance.Tracks) do
        if not track.Destroyed then
            liveTracks += 1
        end
    end
    check("module teardown destroys every track it loaded",
        liveTracks == 0, "live tracks: " .. tostring(liveTracks))

    -- EmotePlayer Save ID: same CSV-once / Refresh contract as Animation
    -- Changer, on its own key, so a rejoin still has the id in the chooser.
    do
        local savedKey: string = "Universal.EmotePlayer.SavedIDs"
        emotePlayer.Options["Custom ID"].Value = "507770239"
        emotePlayer.Feature.options["Save ID"].run()
        check(
            "emote Save ID writes the CSV once",
            host.configData.values[savedKey] == "507770239",
            tostring(host.configData.values[savedKey])
        )
        local savesAfterFirst: number = host.saves
        emotePlayer.Feature.options["Save ID"].run()
        check(
            "emote Save ID does not duplicate an id",
            host.configData.values[savedKey] == "507770239",
            tostring(host.configData.values[savedKey])
        )
        check(
            "a duplicate emote Save ID does not persist again",
            host.saves == savesAfterFirst
        )
        local listed: {string} = emotePlayer.Feature.options["Emote"].itemsList or {}
        local hasSaved: boolean = false
        for _, label: string in ipairs(listed) do
            if label == "Saved 507770239" then
                hasSaved = true
            end
        end
        check("saved emote id appears in the chooser after Refresh", hasSaved)
    end

    -- Teardown -------------------------------------------------------------------

    ctx.DisguiseFile = DisguiseFile
    ctx.AnimationFile = AnimationFile
    ctx.EmoteFile = EmoteFile
end
