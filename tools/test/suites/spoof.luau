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
    for _, name: string in ipairs({"Pack", "Bundle ID", "Apply through", "Apply"}) do
        check("animation option: " .. name, animations.Options[name] ~= nil)
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

    local EmoteFile: any = require("../../../src/modules/Spoof/EmotePlayer")
    Mock.inject(world, EmoteFile.init)
    local emotePlayer: any = EmoteFile.init(espContext)
    check("emote player is registered", emotePlayer.Name == "Emote Player")
    for _, name: string in ipairs({"Emote", "Emote ID", "Speed", "Loop", "Play", "Stop"}) do
        check("emote option: " .. name, emotePlayer.Options[name] ~= nil)
    end

    emotePlayer:Toggle()
    emotePlayer.Options["Emote ID"].Value = "507770239"
    emotePlayer.Feature.options["Play"].run()
    local animatorInstance: any = localHumanoid:FindFirstChildOfClass("Animator")
    check("the emote is loaded and playing",
        animatorInstance ~= nil
            and #animatorInstance.Tracks == 1
            and animatorInstance.Tracks[1].IsPlaying == true
            and animatorInstance.Tracks[1].AnimationId == "rbxassetid://507770239",
        animatorInstance and tostring(#animatorInstance.Tracks) or "no animator")
    emotePlayer.Feature.options["Stop"].run()
    check("stopping stops the track",
        animatorInstance.Tracks[1].IsPlaying == false)
    emotePlayer:Toggle()

    -- Teardown -------------------------------------------------------------------

    ctx.DisguiseFile = DisguiseFile
    ctx.AnimationFile = AnimationFile
    ctx.EmoteFile = EmoteFile
end
