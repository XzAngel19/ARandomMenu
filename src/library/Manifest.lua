--!strict
--
-- Module manifest.
--
-- The single ordered list of everything the runtime downloads on top of
-- `ARandomMenu.lua`: the kernel first, then shared libraries, then the module
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
    widgets = "src/library/Widgets.lua",
    core = {
        "src/library/Framework.lua",
    },
    libraries = {
        "src/library/Entity.lua",
        "src/library/Targeting.lua",
        "src/library/Weapons.lua",
        "src/library/Render.lua",
        -- The card factory. Every module calls it, so it comes before the
        -- pages that read the cards it builds.
        "src/library/Cards.lua",
        -- Before anything that draws a floating window, because they all ask
        -- it to build one rather than writing drag and clamp out again.
        "src/library/WindowManager.lua",
        -- Wurst's layout: one window per category. It only moves the cards
        -- the factory already built, so it comes after both.
        "src/library/ClickGui.lua",
        -- Before the pages below: a favourite registers as its card is built,
        -- and the settings page reads the overlay registry.
        "src/library/FloatingWindows.lua",
        -- Not a service the modules ask for: it fills the Config. tab. It is
        -- listed here because it needs the same environment and the same
        -- start-once/stop-once handling every other library gets.
        "src/library/SettingsPage.lua",
        -- Placed phone shortcuts. The launcher that opens the menu is not here:
        -- it stays in the shell, because on a phone it is the only way in.
        "src/library/MobileActions.lua",
        -- The HUD furniture: wordmark, stats block. Last because it only
        -- draws — nothing below it asks it for anything.
        "src/library/Furniture.lua",
    },
    modules = {
        -- Friend List comes first: every targeting module below asks it who
        -- must not be touched.
        {
            path = "src/modules/Utility/FriendList.lua",
            name = "Friend List",
            category = "Other",
        },
        {
            path = "src/modules/Visuals/ItemRender.lua",
            name = "ItemESP",
            category = "Render",
        },
        {
            path = "src/modules/Visuals/PlayerESP.lua",
            name = "PlayerESP",
            category = "Render",
        },
        {
            path = "src/modules/Visuals/Chams.lua",
            name = "Chams",
            category = "Render",
        },
        {
            path = "src/modules/Visuals/Arrows.lua",
            name = "Arrows",
            category = "Render",
        },
        {
            path = "src/modules/Visuals/NPCESP.lua",
            name = "NPCESP",
            category = "Render",
        },
        {
            path = "src/modules/Combat/KillAura.lua",
            name = "Killaura",
            category = "Combat",
        },
        {
            path = "src/modules/Utility/RemoteLogger.lua",
            name = "Remote Logger",
            category = "Other",
        },
        {
            path = "src/modules/Utility/Learning.lua",
            name = "Learning",
            category = "Other",
        },
        {
            path = "src/modules/Movement/ClickTeleport.lua",
            name = "Click Teleport",
            category = "Movement",
        },
        {
            path = "src/modules/Combat/AutoClicker.lua",
            name = "Auto Clicker",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/TriggerBot.lua",
            name = "TriggerBot",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/AimAssist.lua",
            name = "Aim Assist",
            category = "Combat",
        },
        -- Spoof: cosmetic only, and each one lands on its own page.
        {
            path = "src/modules/Visuals/XRay.lua",
            name = "X-Ray",
            category = "Render",
        },
        {
            path = "src/modules/Movement/HighJump.lua",
            name = "HighJump",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/Spider.lua",
            name = "Spider",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/WallHop.lua",
            name = "WallHop",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/SafeWalk.lua",
            name = "SafeWalk",
            category = "Movement",
        },
        {
            path = "src/modules/Utility/RejoinServer.lua",
            name = "Rejoin Server",
            category = "Other",
        },
        {
            path = "src/modules/Visuals/ZoomUnlocker.lua",
            name = "Zoom",
            category = "Render",
        },
        {
            path = "src/modules/Utility/InteractExtender.lua",
            name = "Interact Extender",
            category = "Other",
        },
        {
            path = "src/modules/Movement/PhaseDash.lua",
            name = "Phase Dash",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/NoFall.lua",
            name = "NoFall",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/Fly.lua",
            name = "Flight",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/VehicleSpeed.lua",
            name = "Vehicle Speed",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/AntiVoid.lua",
            name = "Anti-Void",
            category = "Movement",
        },
        {
            path = "src/modules/Utility/Gravity.lua",
            name = "Gravity",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/JumpPower.lua",
            name = "Jump Power",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/InfiniteJump.lua",
            name = "Infinite Jump",
            category = "Movement",
        },
        {
            path = "src/modules/Visuals/FieldOfView.lua",
            name = "FOV",
            category = "Render",
        },
        {
            path = "src/modules/Movement/Noclip.lua",
            name = "Noclip",
            category = "Movement",
        },
        {
            path = "src/modules/Utility/AntiAfk.lua",
            name = "AntiAFK",
            category = "Other",
        },
        {
            path = "src/modules/Protection/AntiFling.lua",
            name = "Anti-Fling",
            category = "Other",
        },
        {
            path = "src/modules/Utility/LagSwitch.lua",
            name = "Lag Switch",
            category = "Other",
        },
        {
            path = "src/modules/Utility/Fling.lua",
            name = "Fling",
            category = "Other",
        },
        {
            path = "src/modules/Utility/ImproveFps.lua",
            name = "Improve FPS",
            category = "Other",
        },
        {
            path = "src/modules/Visuals/Fullbright.lua",
            name = "Fullbright",
            category = "Render",
        },
        {
            path = "src/modules/Movement/FreezeMovements.lua",
            name = "Freeze Movements",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/Speed.lua",
            name = "SpeedHack",
            category = "Movement",
        },
        {
            path = "src/modules/Combat/Hitboxes.lua",
            name = "Hitboxes",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/ProjectileCalibration.lua",
            name = "Projectile Calibration",
            category = "Render",
        },
        {
            path = "src/modules/Movement/SpinBot.lua",
            name = "SpinBot",
            category = "Fun",
        },
        {
            path = "src/modules/Spoof/Disguise.lua",
            name = "Disguise",
            category = "Fun",
        },
        {
            path = "src/modules/Spoof/AnimationChanger.lua",
            name = "Animation Changer",
            category = "Fun",
        },
        {
            path = "src/modules/Spoof/EmotePlayer.lua",
            name = "Emote Player",
            category = "Fun",
        },
    },
}

return Manifest
