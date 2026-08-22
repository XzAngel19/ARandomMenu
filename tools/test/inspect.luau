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

return Inspect
