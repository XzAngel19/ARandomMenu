--!strict
-- Definitions for the ARandomMenu executor + menu runtime environment.
-- These globals are injected at runtime; the type-check needs them declared
-- so it can focus on real logic errors inside the game modules.

declare function hookmetamethod(
    instance: any,
    name: string,
    hook: (...any) -> any
): (...any) -> any

declare function getnamecallmethod(): string

declare function newcclosure(callback: (...any) -> any): (...any) -> any

declare function checkcaller(): boolean

declare function hookfunction(target: any, replacement: any): any

declare Ray: any

declare function mouse1press(): ()

declare function mouse1release(): ()

declare function mouse1click(): ()

declare function firesignal(signal: any, ...: any): ()

-- Modern executors expose the connection list of a signal, which is how the
-- MM2 timer replays the game's own RoundStart handler locally.
declare function getconnections(signal: any): {any}

declare function getcustomasset(path: string): string

type Feature = {
    name: string,
    enabled: boolean,
}

declare function createUniversalFeature(
    name: string,
    description: string,
    layoutOrder: number,
    onToggle: (boolean) -> (),
    configuration: any?
): Feature

declare function addToggleOption(
    feature: Feature,
    label: string,
    defaultValue: boolean,
    callback: (boolean) -> ()
): any

declare function addCycleOption(
    feature: Feature,
    label: string,
    values: {string},
    initialIndex: number?,
    callback: (string) -> ()
): any

declare function addNumberOption(
    feature: Feature,
    label: string,
    defaultValue: number,
    minimum: number,
    maximum: number,
    callback: (number) -> ()
): any

declare function addInformationOption(feature: Feature, text: string): ()

-- The game bridge. A game module contributes what only it can know — which
-- role a player has, and the objects only this game has — to the universal
-- modules, instead of building a second ESP of its own.
declare function registerRoleProvider(provider: any): ()

declare function registerEspExtra(extra: any): ()

declare function onGameBridge(listener: (string, any) -> ()): ()

declare function playerRole(player: any): string?

-- Teardown hook the shell calls when it unloads the MM2 module. It is a global
-- on purpose: the shell reads it back out of the module's environment.
declare cleanupMM2Runtime: () -> ()

declare function disconnectFeatureConnection(name: string): ()

declare featureConnections: {[string]: any}

declare state: any

type TaskManagerType = {
    Connect: (self: TaskManagerType, callback: (number) -> ()) -> any,
    Destroy: (self: TaskManagerType) -> (),
}

declare TaskManager: TaskManagerType

-- Service globals injected by the runtime environment (not Roblox global types).
declare game: any
declare workspace: any
declare Players: any
declare Stats: any
declare UserInputService: any
declare RunService: any
declare LocalPlayer: any
declare PlayerGui: any
declare Lighting: any
declare TweenService: any
declare HttpService: any
declare CollectionService: any

declare Theme: {
    AccentCyan: Color3,
    AccentViolet: Color3,
    AccentSoft: Color3,
    Surface: Color3,
    SurfaceRaised: Color3,
    TextMuted: Color3,
    Success: Color3,
    Outline: Color3,
}

declare function warn(...: any): ()

declare ScreenGui: ScreenGui
declare notify: (message: any) -> ()
