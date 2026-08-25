--!strict
--
-- Module manifest.
--
-- The single ordered list of everything the runtime downloads on top of
-- `ARandomMenu.luau`: the kernel first, then shared libraries, then the module
-- files themselves. Adding a module means adding one line here and one file
-- under `src/modules/<Category>/`; nothing in the main file has to change.
--
-- The runtime keeps a copy of this list as a fallback for the case where the
-- manifest itself cannot be downloaded, and the repository's validation
-- workflow fails if the two ever drift apart.

export type ModuleEntry = {
    path: string,
    name: string,
    category: string,
}

export type Manifest = {
    version: number,
    widgets: string,
    core: {string},
    libraries: {string},
    modules: {ModuleEntry},
}

local Manifest: Manifest = {
    version = 1,
    -- Listed on its own rather than among the libraries: the option builders
    -- have to exist before any other file runs, because every module builds
    -- its panel out of them the moment it starts.
    widgets = "src/library/Widgets.luau",
    core = {
        "src/core/Framework.luau",
    },
    libraries = {
        "src/library/Entity.luau",
        "src/library/Targeting.luau",
        "src/library/Weapons.luau",
        "src/library/Render.luau",
        -- The card factory. Every module calls it, so it comes before the
        -- pages that read the cards it builds.
        "src/library/Cards.luau",
        -- Before anything that draws a floating window, because they all ask
        -- it to build one rather than writing drag and clamp out again.
        "src/library/WindowManager.luau",
        -- Wurst's layout: one window per category. It only moves the cards
        -- the factory already built, so it comes after both.
        "src/library/ClickGui.luau",
        -- Before the pages below: a favourite registers as its card is built,
        -- and the settings page reads the overlay registry.
        "src/library/FloatingWindows.luau",
        -- Not a service the modules ask for: it fills the Config. tab. It is
        -- listed here because it needs the same environment and the same
        -- start-once/stop-once handling every other library gets.
        "src/library/SettingsPage.luau",
        -- Placed phone shortcuts. The launcher that opens the menu is not here:
        -- it stays in the shell, because on a phone it is the only way in.
        "src/library/MobileActions.luau",
        -- The HUD furniture: wordmark, stats block. Last because it only
        -- draws — nothing below it asks it for anything.
        "src/library/Furniture.luau",
    },
    modules = {
        -- Friend List comes first: every targeting module below asks it who
        -- must not be touched.
        {
            path = "src/modules/Utility/FriendList.luau",
            name = "Friend List",
            category = "Other",
        },
        {
            path = "src/modules/Visuals/ItemRender.luau",
            name = "ItemESP",
            category = "Render",
        },
        {
            path = "src/modules/Visuals/PlayerESP.luau",
            name = "PlayerESP",
            category = "Render",
        },
        {
            path = "src/modules/Visuals/Chams.luau",
            name = "Chams",
            category = "Render",
        },
        {
            path = "src/modules/Visuals/Arrows.luau",
            name = "Arrows",
            category = "Render",
        },
        {
            path = "src/modules/Visuals/NPCESP.luau",
            name = "NPCESP",
            category = "Render",
        },
        {
            path = "src/modules/Combat/KillAura.luau",
            name = "Killaura",
            category = "Combat",
        },
        {
            path = "src/modules/Utility/RemoteLogger.luau",
            name = "Remote Logger",
            category = "Other",
        },
        {
            path = "src/modules/Utility/Learning.luau",
            name = "Learning",
            category = "Other",
        },
        {
            path = "src/modules/Movement/ClickTeleport.luau",
            name = "Click Teleport",
            category = "Movement",
        },
        {
            path = "src/modules/Combat/AutoClicker.luau",
            name = "Auto Clicker",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/TriggerBot.luau",
            name = "TriggerBot",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/AimAssist.luau",
            name = "Aim Assist",
            category = "Combat",
        },
        -- Spoof: cosmetic only, and each one lands on its own page.
        {
            path = "src/modules/Visuals/XRay.luau",
            name = "X-Ray",
            category = "Render",
        },
        {
            path = "src/modules/Movement/HighJump.luau",
            name = "HighJump",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/Spider.luau",
            name = "Spider",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/WallHop.luau",
            name = "WallHop",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/SafeWalk.luau",
            name = "SafeWalk",
            category = "Movement",
        },
        {
            path = "src/modules/Utility/RejoinServer.luau",
            name = "Rejoin Server",
            category = "Other",
        },
        {
            path = "src/modules/Visuals/ZoomUnlocker.luau",
            name = "Zoom",
            category = "Render",
        },
        {
            path = "src/modules/Utility/InteractExtender.luau",
            name = "Interact Extender",
            category = "Other",
        },
        {
            path = "src/modules/Movement/PhaseDash.luau",
            name = "Phase Dash",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/NoFall.luau",
            name = "NoFall",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/Fly.luau",
            name = "Flight",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/VehicleSpeed.luau",
            name = "Vehicle Speed",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/AntiVoid.luau",
            name = "Anti-Void",
            category = "Movement",
        },
        {
            path = "src/modules/Utility/Gravity.luau",
            name = "Gravity",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/JumpPower.luau",
            name = "Jump Power",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/InfiniteJump.luau",
            name = "Infinite Jump",
            category = "Movement",
        },
        {
            path = "src/modules/Visuals/FieldOfView.luau",
            name = "FOV",
            category = "Render",
        },
        {
            path = "src/modules/Movement/Noclip.luau",
            name = "Noclip",
            category = "Movement",
        },
        {
            path = "src/modules/Utility/AntiAfk.luau",
            name = "AntiAFK",
            category = "Other",
        },
        {
            path = "src/modules/Protection/AntiFling.luau",
            name = "Anti-Fling",
            category = "Other",
        },
        {
            path = "src/modules/Utility/LagSwitch.luau",
            name = "Lag Switch",
            category = "Other",
        },
        {
            path = "src/modules/Utility/Fling.luau",
            name = "Fling",
            category = "Other",
        },
        {
            path = "src/modules/Utility/ImproveFps.luau",
            name = "Improve FPS",
            category = "Other",
        },
        {
            path = "src/modules/Visuals/Fullbright.luau",
            name = "Fullbright",
            category = "Render",
        },
        {
            path = "src/modules/Movement/FreezeMovements.luau",
            name = "Freeze Movements",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/Speed.luau",
            name = "SpeedHack",
            category = "Movement",
        },
        {
            path = "src/modules/Combat/Hitboxes.luau",
            name = "Hitboxes",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/ProjectileCalibration.luau",
            name = "Projectile Calibration",
            category = "Render",
        },
        {
            path = "src/modules/Movement/SpinBot.luau",
            name = "SpinBot",
            category = "Fun",
        },
        {
            path = "src/modules/Spoof/Disguise.luau",
            name = "Disguise",
            category = "Fun",
        },
        {
            path = "src/modules/Spoof/AnimationChanger.luau",
            name = "Animation Changer",
            category = "Fun",
        },
        {
            path = "src/modules/Spoof/EmotePlayer.luau",
            name = "Emote Player",
            category = "Fun",
        },
    },
}

return Manifest
