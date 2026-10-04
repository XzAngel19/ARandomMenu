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

    widgets = "src/GUI's/Wurst/Code/Widgets.lua",
    core = {
        "src/library/Framework.lua",
    },
    libraries = {
        "src/library/Entity.lua",
        "src/library/Targeting.lua",
        "src/library/Weapons.lua",
        "src/library/Render.lua",

        "src/GUI's/Wurst/Code/Cards.lua",

        "src/GUI's/Wurst/Code/WindowManager.lua",

        "src/GUI's/Wurst/Code/ClickGui.lua",

        "src/GUI's/Wurst/Code/FloatingWindows.lua",

        "src/GUI's/Wurst/Code/SettingsPage.lua",

        "src/GUI's/Wurst/Code/MobileActions.lua",

        "src/GUI's/Wurst/Code/Furniture.lua",
    },
    modules = {

        {
            path = "src/Hacks/FriendList.lua",
            name = "Friend List",
            category = "Other",
        },
        {
            path = "src/Hacks/ItemRender.lua",
            name = "ItemESP",
            category = "Render",
        },
        {
            path = "src/Hacks/PlayerESP.lua",
            name = "PlayerESP",
            category = "Render",
        },
        {
            path = "src/Hacks/Chams.lua",
            name = "Chams",
            category = "Render",
        },
        {
            path = "src/Hacks/Arrows.lua",
            name = "Arrows",
            category = "Render",
        },
        {
            path = "src/Hacks/NPCESP.lua",
            name = "NPCESP",
            category = "Render",
        },
        {
            path = "src/Hacks/KillAura.lua",
            name = "Killaura",
            category = "Combat",
        },
        {
            path = "src/Hacks/RemoteLogger.lua",
            name = "Remote Logger",
            category = "Other",
        },
        {
            path = "src/Hacks/Learning.lua",
            name = "Learning",
            category = "Other",
        },
        {
            path = "src/Hacks/ClickTeleport.lua",
            name = "Click Teleport",
            category = "Movement",
        },
        {
            path = "src/Hacks/AutoClicker.lua",
            name = "Auto Clicker",
            category = "Combat",
        },
        {
            path = "src/Hacks/TriggerBot.lua",
            name = "TriggerBot",
            category = "Combat",
        },
        {
            path = "src/Hacks/AimAssist.lua",
            name = "Aim Assist",
            category = "Combat",
        },

        {
            path = "src/Hacks/XRay.lua",
            name = "X-Ray",
            category = "Render",
        },
        {
            path = "src/Hacks/HighJump.lua",
            name = "HighJump",
            category = "Movement",
        },
        {
            path = "src/Hacks/Spider.lua",
            name = "Spider",
            category = "Movement",
        },
        {
            path = "src/Hacks/WallHop.lua",
            name = "WallHop",
            category = "Movement",
        },
        {
            path = "src/Hacks/SafeWalk.lua",
            name = "SafeWalk",
            category = "Movement",
        },
        {
            path = "src/Hacks/RejoinServer.lua",
            name = "Rejoin Server",
            category = "Other",
        },
        {
            path = "src/Hacks/ZoomUnlocker.lua",
            name = "Zoom",
            category = "Render",
        },
        {
            path = "src/Hacks/InteractExtender.lua",
            name = "Interact Extender",
            category = "Other",
        },
        {
            path = "src/Hacks/PhaseDash.lua",
            name = "Phase Dash",
            category = "Movement",
        },
        {
            path = "src/Hacks/NoFall.lua",
            name = "NoFall",
            category = "Movement",
        },
        {
            path = "src/Hacks/Fly.lua",
            name = "Flight",
            category = "Movement",
        },
        {
            path = "src/Hacks/VehicleSpeed.lua",
            name = "Vehicle Speed",
            category = "Movement",
        },
        {
            path = "src/Hacks/AntiVoid.lua",
            name = "Anti-Void",
            category = "Movement",
        },
        {
            path = "src/Hacks/Gravity.lua",
            name = "Gravity",
            category = "Movement",
        },
        {
            path = "src/Hacks/JumpPower.lua",
            name = "Jump Power",
            category = "Movement",
        },
        {
            path = "src/Hacks/InfiniteJump.lua",
            name = "Infinite Jump",
            category = "Movement",
        },
        {
            path = "src/Hacks/FieldOfView.lua",
            name = "FOV",
            category = "Render",
        },
        {
            path = "src/Hacks/Noclip.lua",
            name = "Noclip",
            category = "Movement",
        },
        {
            path = "src/Hacks/AntiAfk.lua",
            name = "AntiAFK",
            category = "Other",
        },
        {
            path = "src/Hacks/AntiFling.lua",
            name = "Anti-Fling",
            category = "Other",
        },
        {
            path = "src/Hacks/LagSwitch.lua",
            name = "Lag Switch",
            category = "Other",
        },
        {
            path = "src/Hacks/Fling.lua",
            name = "Fling",
            category = "Other",
        },
        {
            path = "src/Hacks/ImproveFps.lua",
            name = "Improve FPS",
            category = "Other",
        },
        {
            path = "src/Hacks/Fullbright.lua",
            name = "Fullbright",
            category = "Render",
        },
        {
            path = "src/Hacks/FreezeMovements.lua",
            name = "Freeze Movements",
            category = "Movement",
        },
        {
            path = "src/Hacks/Speed.lua",
            name = "SpeedHack",
            category = "Movement",
        },
        {
            path = "src/Hacks/Hitboxes.lua",
            name = "Hitboxes",
            category = "Combat",
        },
        {
            path = "src/Hacks/ProjectileCalibration.lua",
            name = "Projectile Calibration",
            category = "Render",
        },
        {
            path = "src/Hacks/SpinBot.lua",
            name = "SpinBot",
            category = "Fun",
        },
        {
            path = "src/Hacks/Disguise.lua",
            name = "Disguise",
            category = "Fun",
        },
        {
            path = "src/Hacks/AnimationChanger.lua",
            name = "Animation Changer",
            category = "Fun",
        },
        {
            path = "src/Hacks/EmotePlayer.lua",
            name = "Emote Player",
            category = "Fun",
        },
    },
}

return Manifest
