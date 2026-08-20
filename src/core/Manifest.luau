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
    core: {string},
    libraries: {string},
    modules: {ModuleEntry},
}

local Manifest: Manifest = {
    version = 1,
    core = {
        "src/core/Framework.luau",
    },
    libraries = {
        "src/library/Entity.luau",
        "src/library/Weapons.luau",
        "src/library/Render.luau",
    },
    modules = {
        -- Friend List comes first: every targeting module below asks it who
        -- must not be touched.
        {
            path = "src/modules/Utility/FriendList.luau",
            name = "Friend List",
            category = "Utility",
        },
        {
            path = "src/modules/Visuals/ItemRender.luau",
            name = "Item Render",
            category = "Visuals",
        },
        {
            path = "src/modules/Visuals/PlayerESP.luau",
            name = "Player ESP",
            category = "Visuals",
        },
        {
            path = "src/modules/Combat/KillAura.luau",
            name = "Kill Aura",
            category = "Combat",
        },
        {
            path = "src/modules/Utility/RemoteLogger.luau",
            name = "Remote Logger",
            category = "Utility",
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
        -- Spoof: cosmetic only, and each one lands on its own page.
        {
            path = "src/modules/Visuals/XRay.luau",
            name = "X-Ray",
            category = "Visuals",
        },
        {
            path = "src/modules/Movement/HighJump.luau",
            name = "High Jump",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/Spider.luau",
            name = "Spider",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/SafeWalk.luau",
            name = "Safe Walk",
            category = "Protection",
        },
        {
            path = "src/modules/Utility/RejoinServer.luau",
            name = "Rejoin Server",
            category = "Utility",
        },
        {
            path = "src/modules/Visuals/ZoomUnlocker.luau",
            name = "Zoom Unlocker",
            category = "Visuals",
        },
        {
            path = "src/modules/Utility/InteractExtender.luau",
            name = "Interact Extender",
            category = "Utility",
        },
        {
            path = "src/modules/Movement/PhaseDash.luau",
            name = "Phase Dash",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/NoFall.luau",
            name = "No Fall",
            category = "Protection",
        },
        {
            path = "src/modules/Movement/Fly.luau",
            name = "Fly",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/PhysicsSpeed.luau",
            name = "Physics Speed",
            category = "Movement",
        },
        {
            path = "src/modules/Protection/AntiVoid.luau",
            name = "Anti-Void",
            category = "Protection",
        },
        {
            path = "src/modules/Utility/Gravity.luau",
            name = "Gravity",
            category = "Utility",
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
            category = "Visuals",
        },
        {
            path = "src/modules/Movement/Noclip.luau",
            name = "Noclip",
            category = "Movement",
        },
        {
            path = "src/modules/Utility/AntiAfk.luau",
            name = "Anti-AFK",
            category = "Utility",
        },
        {
            path = "src/modules/Protection/AntiFling.luau",
            name = "Anti-Fling",
            category = "Protection",
        },
        {
            path = "src/modules/Utility/LagSwitch.luau",
            name = "Lag Switch",
            category = "Utility",
        },
        {
            path = "src/modules/Utility/Fling.luau",
            name = "Fling",
            category = "Utility",
        },
        {
            path = "src/modules/Visuals/Fullbright.luau",
            name = "Fullbright",
            category = "Visuals",
        },
        {
            path = "src/modules/Movement/FreezeMovements.luau",
            name = "Freeze Movements",
            category = "Movement",
        },
        {
            path = "src/modules/Movement/Speed.luau",
            name = "Speed",
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
            category = "Combat",
        },
        {
            path = "src/modules/Spoof/Disguise.luau",
            name = "Disguise",
            category = "Spoof",
        },
        {
            path = "src/modules/Spoof/AnimationChanger.luau",
            name = "Animation Changer",
            category = "Spoof",
        },
        {
            path = "src/modules/Spoof/EmotePlayer.luau",
            name = "Emote Player",
            category = "Spoof",
        },
    },
}

return Manifest
