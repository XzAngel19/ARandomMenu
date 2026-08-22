--!strict
--
-- Shared inspectors for the C4–C6 runtime suites. The mock's
-- FindFirstChild is not recursive, AbsoluteContentSize stays at 0, and
-- the bitmap registries are weak tables — every suite that boots the
-- shell needs the same walks.

local Inspect = {}

function Inspect.findNamed(root: any, name: string): any
    if root == nil or type(root.GetDescendants) ~= "function" then
        return nil
    end
    if root.Name == name then
        return root
    end
    for _, node: any in ipairs(root:GetDescendants()) do
        if node.Name == name then
            return node
        end
    end
    return nil
end

function Inspect.eachNamed(root: any, name: string, visit: (any) -> ()): ()
    if root == nil or type(root.GetDescendants) ~= "function" then
        return
    end
    if root.Name == name then
        visit(root)
    end
    for _, node: any in ipairs(root:GetDescendants()) do
        if node.Name == name then
            visit(node)
        end
    end
end

function Inspect.liveCounts(bitmap: any): (number, number)
    local holders: number = 0
    local glyphs: number = 0
    if bitmap == nil or type(bitmap._live) ~= "table" then
        return 0, 0
    end
    for holder: any, record: any in pairs(bitmap._live) do
        if holder ~= nil and holder.Parent ~= nil then
            holders += 1
            if type(record) == "table" and type(record.glyphs) == "table" then
                for _, glyph: any in ipairs(record.glyphs) do
                    if glyph.Visible ~= false then
                        glyphs += 1
                    end
                end
            end
        end
    end
    return holders, glyphs
end

function Inspect.armAtlas(bitmap: any): ()
    if bitmap == nil or bitmap.atlas == nil then
        return
    end
    bitmap.atlas.image = "harness-atlas"
    bitmap.atlas.ready = true
    for holder: any, record: any in pairs(bitmap._live) do
        if holder ~= nil
            and holder.Parent ~= nil
            and type(record) == "table"
            and record.request ~= nil
            and type(bitmap.draw) == "function"
        then
            pcall(function(): ()
                bitmap.draw(
                    record.request.parent,
                    record.request.segments,
                    record.request.options
                )
            end)
        end
    end
end

function Inspect.isOnContract(bitmap: any, node: any): boolean
    if bitmap == nil or node == nil then
        return false
    end
    if bitmap._live[node] ~= nil then
        return true
    end
    if bitmap._adopted[node] == true then
        return true
    end
    local glyphs: any = node:FindFirstChild("Glyphs")
    if glyphs ~= nil and bitmap._live[glyphs] ~= nil then
        return true
    end
    return false
end

function Inspect.vectorInkHidden(node: any): boolean
    if node == nil then
        return true
    end
    if node.ClassName ~= "TextLabel" and node.ClassName ~= "TextButton" then
        return true
    end
    -- Adopted labels keep Text for packing; the pixels come from Glyphs.
    -- The renderer's own Fallback is the stand-in when the atlas is down.
    if node.Name == "Fallback" then
        return true
    end
    local transparency: any = node.TextTransparency
    if type(transparency) == "number" and transparency >= 1 then
        return true
    end
    return false
end

function Inspect.aabb(a: any, b: any, gap: number): boolean
    local ax: number = a.root.Position.X.Offset
    local ay: number = a.root.Position.Y.Offset
    local aw: number = a.root.Size.X.Offset
    local ah: number = a.root.Size.Y.Offset
    local bx: number = b.root.Position.X.Offset
    local by: number = b.root.Position.Y.Offset
    local bw: number = b.root.Size.X.Offset
    local bh: number = b.root.Size.Y.Offset
    return ax < bx + bw + gap
        and bx < ax + aw + gap
        and ay < by + bh + gap
        and by < ay + ah + gap
end

function Inspect.inside(window: any, vw: number, vh: number): boolean
    local x: number = window.root.Position.X.Offset
    local y: number = window.root.Position.Y.Offset
    local w: number = window.root.Size.X.Offset
    local h: number = window.root.Size.Y.Offset
    return x >= 6 and y >= 6 and x + w <= vw - 6 and y + h <= vh - 6
end

function Inspect.clickNamed(root: any, name: string): boolean
    local node: any = Inspect.findNamed(root, name)
    if node == nil or node.MouseButton1Click == nil then
        return false
    end
    node.MouseButton1Click:Fire()
    return true
end

function Inspect.pinClickGuiScale(hostOrLayer: any, scale: number): any
    local layer: any = hostOrLayer
    if layer ~= nil and layer.Name ~= "PopupLayer" then
        layer = hostOrLayer.PopupLayer or hostOrLayer
    end
    if layer == nil or type(layer.FindFirstChild) ~= "function" then
        return nil
    end
    local node: any = layer:FindFirstChild("ClickGuiScale")
    if node ~= nil then
        node.Scale = scale
    end
    return node
end

function Inspect.featureNamed(env: any, name: string): any
    for _, feature: any in ipairs((env and env.allFeatures) or {}) do
        if feature.name == name or feature.configKey == name then
            return feature
        end
    end
    return nil
end

function Inspect.armAtlasFamily(bitmap: any): ()
    Inspect.armAtlas(bitmap)
    if bitmap == nil or type(bitmap.family) ~= "table" then
        return
    end
    for _, member: any in pairs(bitmap.family) do
        if type(member) == "table" then
            member.image = member.image or ("harness-" .. tostring(member.size))
            member.ready = true
        end
    end
end

function Inspect.pickChoice(root: any, rowName: string, value: string): boolean
    local row: any = Inspect.findNamed(root, rowName)
    if row == nil then
        return false
    end
    local combo: any = row:FindFirstChild("ComboValue") or row
    if combo == nil or combo.MouseButton1Click == nil then
        return false
    end
    combo.MouseButton1Click:Fire()
    local list: any = Inspect.findNamed(root, "ChoiceList")
    if list == nil then
        return false
    end
    for _, node: any in ipairs(list:GetDescendants()) do
        if tostring(node.Text or "") == value and node.MouseButton1Click ~= nil then
            node.MouseButton1Click:Fire()
            return true
        end
    end
    return false
end

function Inspect.dockSearch(state: any): any
    local pill: any = state and state.pill
    local root: any = pill and (pill.root or pill)
    if root == nil then
        return nil
    end
    return Inspect.findNamed(root, "DockSearchBox")
        or Inspect.findNamed(root, "Search")
        or Inspect.findNamed(root, "Query")
end

function Inspect.wurstVisible(state: any): boolean
    if state == nil then
        return false
    end
    if state.visible == true then
        return true
    end
    local clickGui: any = state.clickGui
    local combat: any = clickGui
        and clickGui.categories
        and clickGui.categories.Combat
    return combat ~= nil
        and combat.window ~= nil
        and combat.window.root ~= nil
        and combat.window.root.Visible == true
end

function Inspect.findBindSquare(feature: any): any
    if feature == nil then
        return nil
    end
    local named: any = feature.bindSquare
        or feature.keybindSquare
        or feature.keySquare
        or feature.bind
    if named ~= nil then
        return named
    end
    local row: any = feature.row
    if row == nil or type(row.FindFirstChild) ~= "function" then
        return nil
    end
    for _, name: string in ipairs({
        "BindSquare",
        "KeybindSquare",
        "KeySquare",
        "Bind",
        "Keybind",
    }) do
        local child: any = row:FindFirstChild(name)
        if child ~= nil then
            return child
        end
    end
    return nil
end

function Inspect.navigatorVisible(state: any): boolean
    local nav: any = state and state.navigator
    local root: any = nav and nav.root
    return root ~= nil and root.Visible == true
end

return Inspect
