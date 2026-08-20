--!strict
--
-- Weapon discovery.
--
-- `Character:FindFirstChildOfClass("Tool")` describes one way of holding a
-- weapon, and plenty of games do not use it. The BedFight dump in `reference/`
-- is the worked example: that game contains **no Tool instances at all**. Its
-- swords are
--
--   * view models — `workspace.CurrentCamera.ViewModel["Wooden Sword"]`, a
--     plain Model swapped in and out by the client;
--   * hotbar slots — GuiButtons under `PlayerGui.BackpackGui.HotbarList`,
--     driven by an `InventoryHandler` module keyed by item class
--     ("Swords", "Katanas", "Daggers", "Battle Axes", "Maces", "Spears");
--   * and, on touch, a dedicated button at
--     `PlayerGui.MobileGui.ButtonsFrame.Sword` whose `MouseButton1Click` is
--     what actually swings.
--
-- So this library does not look for a class. It collects every plausible way of
-- swinging that exists right now — tools, view models, inventory buttons,
-- on-screen action buttons — labels each one, and lets the module (and the
-- player, through a selection list) decide which of them to use. Activation is
-- per kind: a Tool is activated, a button is pressed the way a finger presses
-- it, a view model is swung by pressing whatever button owns it.

export type Candidate = {
    id: string,
    label: string,
    kind: string,
    instance: Instance,
}

export type WeaponLibrary = {
    Scan: (self: WeaponLibrary, query: any?) -> {Candidate},
    Labels: (self: WeaponLibrary, query: any?) -> {string},
    Find: (self: WeaponLibrary, label: string) -> Candidate?,
    Activate: (self: WeaponLibrary, candidate: Candidate) -> boolean,
    Best: (self: WeaponLibrary) -> Candidate?,
    Invalidate: (self: WeaponLibrary) -> (),
    SetAllowEquip: (self: WeaponLibrary, allowed: boolean) -> (),
    Swing: (self: WeaponLibrary) -> boolean,
    PressButton: (self: WeaponLibrary, button: GuiButton) -> boolean,
    Destroy: (self: WeaponLibrary) -> (),
}

local Module = {
    Name = "Weapons",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

-- Words that mean "this hits things". Deliberately generous: a false positive
-- costs one unticked row in a list, a false negative costs a module that does
-- nothing and no way to find out why.
local WEAPON_WORDS: {string} = {
    "sword",
    "katana",
    "dagger",
    "blade",
    "knife",
    "axe",
    "mace",
    "spear",
    "scythe",
    "sabre",
    "saber",
    "machete",
    "hammer",
    "club",
    "bat",
    "staff",
    "pickaxe",
    "fist",
    "punch",
    "attack",
    "swing",
    "hit",
    "melee",
    "weapon",
    "combat",
}

-- Words that mean "this is not a weapon". A hotbar holds wool, planks, emotes
-- and cosmetics next to the sword, and listing all of it turned the picker
-- into an inventory dump. A blocked word always wins: nothing called
-- "EmoteWheel" is a blade, whatever else its name contains.
local NOT_WEAPON_WORDS: {string} = {
    "emote",
    "animation",
    "anim",
    "dance",
    "cosmetic",
    "cape",
    "skin",
    "kit",
    "shop",
    "setting",
    "gift",
    "trade",
    "coin",
    "gem",
    "wool",
    "block",
    "plank",
    "brick",
    "glass",
    "ladder",
    "wood ",
    "sand",
    "dirt",
    "obsidian",
    "potion",
    "food",
    "apple",
    "bed",
    "chest",
    "music",
    "sound",
    "menu",
    "close",
    "back",
    "shopkeeper",
}

-- Containers whose children are inventory slots rather than decoration.
local INVENTORY_WORDS: {string} = {
    "hotbar",
    "backpack",
    "inventory",
    "toolbar",
    "slots",
    "items",
}

-- Containers a game builds for touch controls.
local TOUCH_WORDS: {string} = {
    "mobile",
    "touch",
    "buttons",
    "controls",
}

local activeLibrary: WeaponLibrary? = nil

local function containsWord(text: string, words: {string}): boolean
    local lowered: string = string.lower(text)
    for _, word: string in ipairs(words) do
        if string.find(lowered, word, 1, true) then
            return true
        end
    end
    return false
end

local function ancestryMatches(instance: Instance, words: {string}, depth: number): boolean
    local current: Instance? = instance
    local steps: number = 0
    while current and steps < depth do
        if containsWord(current.Name, words) then
            return true
        end
        current = current.Parent
        steps += 1
    end
    return false
end

function Module.init(context: any): WeaponLibrary
    local host: any = context
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    local menuGui: Instance? = host.ScreenGui

    local library: any = {
        -- Scanning walks every GuiButton in the PlayerGui. Kill Aura asks for
        -- a weapon on every swing and the Auto Clicker on every click, so the
        -- answer is cached for a second: a hotbar does not change nine times a
        -- second, and this is the difference between a scan per swing and a
        -- scan per second.
        cache = {},
        cachedAt = -1,
        cachedAll = false,
        -- Off by default: nothing in this menu should decide for the player
        -- what is in their hands.
        allowEquip = false,
    }

    -- Firing a GuiButton the way a real press does. BedFight's mobile sword
    -- listens on MouseButton1Down and MouseButton1Click and does its work in a
    -- one-shot InputBegan opened by the former, so both are fired, in order.
    function library:PressButton(button: GuiButton): boolean
        local environment: any = getfenv()
        local connectionsOf: any = environment.getconnections
        local fireSignal: any = environment.firesignal
        local pressed: boolean = false

        if type(connectionsOf) == "function" then
            for _, signal: any in
                ipairs({
                    button.MouseButton1Down,
                    button.MouseButton1Click,
                    (button :: any).Activated,
                    button.MouseButton1Up,
                })
            do
                local ok: boolean, connections: any = pcall(connectionsOf, signal)
                if not ok or type(connections) ~= "table" then
                    continue
                end
                for _, connection: any in ipairs(connections) do
                    local fired: boolean = pcall(function(): ()
                        connection:Fire()
                    end)
                    pressed = pressed or fired
                end
            end
        end
        if not pressed and type(fireSignal) == "function" then
            pressed = pcall(fireSignal, (button :: any).Activated) == true
        end
        return pressed
    end

    local function isMenuOwned(instance: Instance): boolean
        return menuGui ~= nil and instance:IsDescendantOf(menuGui :: Instance)
    end

    function library:Invalidate(): ()
        library.cachedAt = -1
    end

    function library:SetAllowEquip(allowed: boolean): ()
        library.allowEquip = allowed == true
    end

    function library:Scan(query: any?): {Candidate}
        local options: any = query or {}
        local everything: boolean = options.All == true
        local now: number = os.clock()
        if now - library.cachedAt < 1 and library.cachedAll == everything then
            return library.cache
        end
        local found: {Candidate} = {}
        local seen: {[string]: boolean} = {}

        local function add(kind: string, label: string, instance: Instance): ()
            local id: string = kind .. ":" .. label
            if seen[id] then
                return
            end
            seen[id] = true
            table.insert(found, {
                id = id,
                label = label,
                kind = kind,
                instance = instance,
            })
        end

        -- 1. Classic tools, held or stowed.
        local character: Model? = localPlayer.Character
        if character then
            for _, child: Instance in ipairs(character:GetChildren()) do
                if child:IsA("Tool") then
                    add("Tool", child.Name, child)
                end
            end
        end
        local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
        if backpack then
            for _, child: Instance in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") then
                    add("Tool", child.Name, child)
                end
            end
        end

        -- 2. View models: the weapon you can see but cannot pick up. They live
        -- under the camera in BedFight, and under the character in others.
        local viewRoots: {Instance} = {}
        local camera: Camera? = currentWorkspace.CurrentCamera
        if camera then
            table.insert(viewRoots, camera)
        end
        if character then
            table.insert(viewRoots, character)
        end
        for _, root: Instance in ipairs(viewRoots) do
            for _, child: Instance in ipairs(root:GetChildren()) do
                if not child:IsA("Model") then
                    continue
                end
                if containsWord(child.Name, WEAPON_WORDS)
                    and not containsWord(child.Name, NOT_WEAPON_WORDS) then
                    add("ViewModel", child.Name, child)
                end
                if string.find(string.lower(child.Name), "viewmodel", 1, true) then
                    -- Whatever the client has put in your hands right now.
                    for _, held: Instance in ipairs(child:GetChildren()) do
                        if not held:IsA("Model") and not held:IsA("BasePart") then
                            continue
                        end
                        if containsWord(held.Name, NOT_WEAPON_WORDS) then
                            continue
                        end
                        add("ViewModel", held.Name, held)
                    end
                end
            end
        end

        -- 3. Interface: inventory slots and touch buttons the game built.
        local playerGui: Instance? = localPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            for _, descendant: Instance in ipairs(playerGui:GetDescendants()) do
                if not descendant:IsA("GuiButton") then
                    continue
                end
                if isMenuOwned(descendant) then
                    -- The menu's own controls are not the game's weapons.
                    continue
                end
                if containsWord(descendant.Name, NOT_WEAPON_WORDS) then
                    continue
                end
                local named: boolean = containsWord(descendant.Name, WEAPON_WORDS)
                if not named then
                    -- Unnamed buttons are only interesting when the caller
                    -- explicitly asks for everything, and even then only from
                    -- the touch controls, where the swing button lives.
                    if not everything then
                        continue
                    end
                    if not ancestryMatches(descendant, TOUCH_WORDS, 4) then
                        continue
                    end
                    add("Button", descendant.Name, descendant)
                    continue
                end
                local inInventory: boolean =
                    ancestryMatches(descendant, INVENTORY_WORDS, 4)
                add(inInventory and "Slot" or "Button", descendant.Name, descendant)
            end
        end

        library.cache = found
        library.cachedAt = now
        library.cachedAll = everything
        return found
    end

    function library:Labels(query: any?): {string}
        local labels: {string} = {}
        for _, candidate: Candidate in ipairs(library:Scan(query)) do
            table.insert(labels, candidate.label .. "  ·  " .. candidate.kind)
        end
        table.sort(labels)
        return labels
    end

    function library:Find(label: string): Candidate?
        local wanted: string = string.lower(label)
        for _, candidate: Candidate in ipairs(library:Scan({All = true})) do
            if string.lower(candidate.label) == wanted then
                return candidate
            end
            if string.lower(candidate.label .. "  ·  " .. candidate.kind) == wanted then
                return candidate
            end
        end
        return nil
    end

    -- What to hit with when nobody has picked anything. Held tools first,
    -- because that is what most games mean by "your weapon"; then the touch
    -- button, which is the only thing that swings in games like BedFight; then
    -- a hotbar slot, which at least equips the thing.
    function library:Best(): Candidate?
        local found: {Candidate} = library:Scan({All = false})
        local order: {string} = {"Tool", "Button", "Slot", "ViewModel"}
        local character: Model? = localPlayer.Character
        for _, kind: string in ipairs(order) do
            for _, candidate: Candidate in ipairs(found) do
                if candidate.kind ~= kind then
                    continue
                end
                if kind == "Tool"
                    and character
                    and candidate.instance.Parent ~= character
                    and not library.allowEquip then
                    -- A stowed tool is a worse answer than the button that
                    -- swings whatever is already equipped, and taking it out
                    -- of the backpack is not this module's decision.
                    continue
                end
                return candidate
            end
        end
        return found[1]
    end

    function library:Swing(): boolean
        local candidate: Candidate? = library:Best()
        if not candidate then
            return false
        end
        return library:Activate(candidate :: Candidate)
    end

    function library:Activate(candidate: Candidate): boolean
        local instance: Instance = candidate.instance
        if not instance.Parent then
            return false
        end
        if candidate.kind == "Tool" then
            local tool: Tool = instance :: Tool
            -- Equipping is a visible action that takes the weapon out of the
            -- player's hands and puts a different one in them, so it only
            -- happens when the caller asks for it. A stowed tool is activated
            -- where it stands otherwise; games that ignore that are the reason
            -- the button and view-model paths exist.
            if library.allowEquip and tool.Parent ~= localPlayer.Character then
                local humanoid: Humanoid? = localPlayer.Character
                    and localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if humanoid then
                    pcall(function(): ()
                        (humanoid :: Humanoid):EquipTool(tool)
                    end)
                end
            end
            return pcall(function(): ()
                tool:Activate()
            end)
        end
        if candidate.kind == "Button" or candidate.kind == "Slot" then
            return library:PressButton(instance :: GuiButton)
        end
        if candidate.kind == "ViewModel" then
            -- A view model is scenery: the swing belongs to whatever button
            -- drives it, so the nearest touch button wins and the caller falls
            -- back to its own click path when there is none.
            for _, other: Candidate in ipairs(library:Scan({All = true})) do
                if other.kind == "Button" then
                    return library:PressButton(other.instance :: GuiButton)
                end
            end
            return false
        end
        return false
    end

    function library:Destroy(): ()
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = (library :: any) :: WeaponLibrary
    Module.Initialized = true
    return (library :: any) :: WeaponLibrary
end

function Module.destroy(): ()
    local library: WeaponLibrary? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
