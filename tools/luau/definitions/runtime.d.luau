-- Host and executor globals for the Wurst runtime.
--
-- Wurst.lua is injected by a Roblox executor, so besides the Roblox API it sees
-- two extra namespaces:
--
--   1. Executor functions (`getgenv`, `gethui`, `getconnections`, ...). Only the
--      ones this repository actually calls are declared; add a line here when a
--      new one shows up, never sprinkle `any` casts through the sources.
--   2. Menu host globals. Wurst.lua publishes `create`, `Theme`, `state`,
--      `notify`, `TaskManager`, `configData`, `featureConnections`... and every
--      card module runs inside that shared environment (see
--      docs/skills/roblox-menu-change.md, "el módulo corre dentro del entorno del
--      menú"). They are declared permissively on purpose: their real shapes are
--      typed in the modules that build them, and a wrong guess here would turn
--      valid card code into false errors.

-- Executor surface -------------------------------------------------------
declare getgenv: () -> { [string]: any }
declare getrenv: () -> { [string]: any }
declare gethui: () -> Instance
declare getconnections: (any) -> { any }
declare firesignal: (any, ...any) -> ()
declare getnamecallmethod: () -> string?
declare hookmetamethod: (any, string, (...any) -> ...any) -> (...any) -> ...any
declare newcclosure: ((...any) -> ...any) -> (...any) -> ...any
declare setclipboard: (string) -> ()
declare readfile: (string) -> string
declare writefile: (string, string) -> ()
declare isfile: (string) -> boolean
declare isfolder: (string) -> boolean
declare makefolder: (string) -> ()
declare delfile: (string) -> ()
declare identifyexecutor: () -> (string, string)
declare getcustomasset: (string) -> string
declare queue_on_teleport: (string) -> ()
declare request: (any) -> any

-- Menu host surface ------------------------------------------------------
-- Published by Wurst.lua, used unqualified by every card.
declare create: any
declare Theme: { [string]: Color3 }
declare state: { [string]: any }
declare notify: (string, string?) -> ()
declare configData: { [string]: any }
declare savedList: { [string]: any }
declare services: { [string]: any }
declare settings: { [string]: any }
declare card: any
declare feature: any
declare featureConnections: { [string]: any }
declare TaskManager: any
declare queueConfigSave: () -> ()
declare setOptionVisible: (string, boolean) -> ()
declare colorFromConfig: (any) -> Color3
declare normalizeFeatureCategory: (string) -> string
declare isWeaponPathClear: (...any) -> boolean
declare findPlayerByText: (string) -> Player?
declare getCharacterParts: (Model) -> { [string]: BasePart }
declare jump: () -> ()
declare refreshFeatureToggle: (string, any) -> ()
declare disconnectFeatureConnection: (string) -> ()
declare registerEspExtra: (...any) -> ()
declare registerRoleProvider: (...any) -> ()
declare startPoseMirror: (...any) -> ()
declare createUniversalFeature: (...any) -> any
declare addToggleOption: (...any) -> any
declare addKeyOption: (...any) -> any
declare addColorOption: (...any) -> any
declare addNumberOption: (...any) -> any
declare addTextOption: (...any) -> any
declare addListOption: (...any) -> any
declare addCycleOption: (...any) -> any
declare addActionOption: (...any) -> any
declare addSectionOption: (...any) -> any
declare addInformationOption: (...any) -> any

-- Runtime-only globals the bundle reads back with _G ---------------------
declare GAME_CHECK: any
declare MM2Scroll: any
declare initialViewport: any
declare lastResolvedSlots: any
declare missReason: any
declare mm2Features: any

-- Services the host publishes unqualified because every card calls them on the
-- frame path. They are the real singletons, so they share the engine types.
declare Players: Players
declare LocalPlayer: Player
declare PlayerGui: PlayerGui
declare RunService: RunService
declare UserInputService: UserInputService
declare Lighting: Lighting
declare HttpService: HttpService
declare CollectionService: CollectionService
declare ScreenGui: ScreenGui
declare tick: () -> number
declare warn: (...any) -> ()
