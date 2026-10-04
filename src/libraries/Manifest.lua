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
        "src/libraries/Framework.lua",
    },
    libraries = {
        "src/libraries/Entity.lua",
        "src/libraries/Targeting.lua",
        "src/libraries/Weapons.lua",
        "src/libraries/Render.lua",

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
            path = "src/games/universal/FriendList.lua",
            name = "Friend List",
            category = "Other",
        },
        {
            path = "src/games/universal/ItemRender.lua",
            name = "ItemESP",
            category = "Render",
        },
        {
            path = "src/games/universal/PlayerESP.lua",
            name = "PlayerESP",
            category = "Render",
        },
        {
            path = "src/games/universal/Chams.lua",
            name = "Chams",
            category = "Render",
        },
        {
            path = "src/games/universal/Arrows.lua",
            name = "Arrows",
            category = "Render",
        },
        {
            path = "src/games/universal/NPCESP.lua",
            name = "NPCESP",
            category = "Render",
        },
        {
            path = "src/games/universal/KillAura.lua",
            name = "Killaura",
            category = "Combat",
        },
        {
            path = "src/games/universal/RemoteLogger.lua",
            name = "Remote Logger",
            category = "Other",
        },
        {
            path = "src/games/universal/Learning.lua",
            name = "Learning",
            category = "Other",
        },
        {
            path = "src/games/universal/ClickTeleport.lua",
            name = "Click Teleport",
            category = "Movement",
        },
        {
            path = "src/games/universal/AutoClicker.lua",
            name = "Auto Clicker",
            category = "Combat",
        },
        {
            path = "src/games/universal/TriggerBot.lua",
            name = "TriggerBot",
            category = "Combat",
        },
        {
            path = "src/games/universal/AimAssist.lua",
            name = "Aim Assist",
            category = "Combat",
        },

        {
            path = "src/games/universal/XRay.lua",
            name = "X-Ray",
            category = "Render",
        },
        {
            path = "src/games/universal/HighJump.lua",
            name = "HighJump",
            category = "Movement",
        },
        {
            path = "src/games/universal/Spider.lua",
            name = "Spider",
            category = "Movement",
        },
        {
            path = "src/games/universal/WallHop.lua",
            name = "WallHop",
            category = "Movement",
        },
        {
            path = "src/games/universal/SafeWalk.lua",
            name = "SafeWalk",
            category = "Movement",
        },
        {
            path = "src/games/universal/RejoinServer.lua",
            name = "Rejoin Server",
            category = "Other",
        },
        {
            path = "src/games/universal/ZoomUnlocker.lua",
            name = "Zoom",
            category = "Render",
        },
        {
            path = "src/games/universal/InteractExtender.lua",
            name = "Interact Extender",
            category = "Other",
        },
        {
            path = "src/games/universal/PhaseDash.lua",
            name = "Phase Dash",
            category = "Movement",
        },
        {
            path = "src/games/universal/NoFall.lua",
            name = "NoFall",
            category = "Movement",
        },
        {
            path = "src/games/universal/Fly.lua",
            name = "Flight",
            category = "Movement",
        },
        {
            path = "src/games/universal/VehicleSpeed.lua",
            name = "Vehicle Speed",
            category = "Movement",
        },
        {
            path = "src/games/universal/AntiVoid.lua",
            name = "Anti-Void",
            category = "Movement",
        },
        {
            path = "src/games/universal/Gravity.lua",
            name = "Gravity",
            category = "Movement",
        },
        {
            path = "src/games/universal/JumpPower.lua",
            name = "Jump Power",
            category = "Movement",
        },
        {
            path = "src/games/universal/InfiniteJump.lua",
            name = "Infinite Jump",
            category = "Movement",
        },
        {
            path = "src/games/universal/FieldOfView.lua",
            name = "FOV",
            category = "Render",
        },
        {
            path = "src/games/universal/Noclip.lua",
            name = "Noclip",
            category = "Movement",
        },
        {
            path = "src/games/universal/AntiAfk.lua",
            name = "AntiAFK",
            category = "Other",
        },
        {
            path = "src/games/universal/AntiFling.lua",
            name = "Anti-Fling",
            category = "Other",
        },
        {
            path = "src/games/universal/LagSwitch.lua",
            name = "Lag Switch",
            category = "Other",
        },
        {
            path = "src/games/universal/Fling.lua",
            name = "Fling",
            category = "Other",
        },
        {
            path = "src/games/universal/ImproveFps.lua",
            name = "Improve FPS",
            category = "Other",
        },
        {
            path = "src/games/universal/Fullbright.lua",
            name = "Fullbright",
            category = "Render",
        },
        {
            path = "src/games/universal/FreezeMovements.lua",
            name = "Freeze Movements",
            category = "Movement",
        },
        {
            path = "src/games/universal/Speed.lua",
            name = "SpeedHack",
            category = "Movement",
        },
        {
            path = "src/games/universal/Hitboxes.lua",
            name = "Hitboxes",
            category = "Combat",
        },
        {
            path = "src/games/universal/ProjectileCalibration.lua",
            name = "Projectile Calibration",
            category = "Render",
        },
        {
            path = "src/games/universal/SpinBot.lua",
            name = "SpinBot",
            category = "Fun",
        },
        {
            path = "src/games/universal/Disguise.lua",
            name = "Disguise",
            category = "Fun",
        },
        {
            path = "src/games/universal/AnimationChanger.lua",
            name = "Animation Changer",
            category = "Fun",
        },
        {
            path = "src/games/universal/EmotePlayer.lua",
            name = "Emote Player",
            category = "Fun",
        },
    },
}

return Manifest
