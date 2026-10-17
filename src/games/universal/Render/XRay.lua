-- Vape Xray's kept-part list, with bounded updates and owned-only restoration.
local Module = {Name="XRay",PlaceId=0,Initialized=false}
local card
function Module.init(context)
    local host, world = context.host, context.host.workspace or workspace
    local records = setmetatable({}, {__mode="k"})
    local indexed = setmetatable({}, {__mode="k"})
    local candidates, cursor, pause = {}, 1, 0
    local named, kept = {}, {}
    local function names(text)
        local result={}
        for name in string.gmatch(string.lower(text or ""),"[^,]+") do
            name=string.match(name,"^%s*(.-)%s*$")
            if name~="" then result[name]=true end
        end
        return result
    end
    local function restore(part)
        local record=records[part]
        if not record then return end
        pcall(function()
            if part.LocalTransparencyModifier==record.applied then part.LocalTransparencyModifier=record.base end
        end)
        records[part]=nil
    end
    local function restoreAll()
        for part in pairs(records) do restore(part) end
    end
    local function changed()
        restoreAll();cursor=1;pause=0
        if card and card.Options["Part names"] and card.Options["Keep visible"] then
            named=names(card.Options["Part names"].Value)
            kept=names(card.Options["Keep visible"].Value)
        end
    end
    local function add(part)
        if part:IsA("BasePart") and not indexed[part] then
            indexed[part]=true;table.insert(candidates,part)
        end
    end
    local function eligible(part,origin,root)
        local opts=card.Options
        if part.Transparency>=0.98 or kept[string.lower(part.Name)] then return false end
        if not opts["Include unanchored"].Value and not part.Anchored then return false end
        if opts["Collidable only"].Value and not part.CanCollide then return false end
        if opts["Limit range"].Value and origin and (part.Position-origin).Magnitude>opts.Range.Value+part.Size.Magnitude*0.5 then return false end
        if part.Name=="Wurst_AntiVoidPlatform" or host.isMenuOwned and host.isMenuOwned(part) then return false end
        local ancestor=part.Parent
        while ancestor and ancestor~=world do
            if ancestor:IsA("Tool") or ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then return false end
            ancestor=ancestor.Parent
        end
        local thinFloor=part.Size.Y<=math.min(part.Size.X,part.Size.Z)*0.35
        if opts["Keep floors"].Value and thinFloor and root and part.Position.Y<=root.Position.Y then return false end
        local mode=opts.Scope.Value
        if mode=="Named parts" then return named[string.lower(part.Name)]==true end
        if mode=="Walls" then return not thinFloor and part.Size.Y>math.min(part.Size.X,part.Size.Z)*1.5 end
        return true
    end
    local function step(dt)
        pause=math.max(0,pause-(dt or 0))
        if pause>0 or #candidates==0 then return end
        local camera=world.CurrentCamera
        local character=host.LocalPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local origin=camera and camera.CFrame.Position or root and root.Position
        for _=1,200 do
            local part=candidates[cursor]
            if not part then cursor=1;pause=0.2;break end
            if not part.Parent or not part:IsDescendantOf(world) then
                restore(part);indexed[part]=nil
                candidates[cursor]=candidates[#candidates];candidates[#candidates]=nil
            else
                if eligible(part,origin,root) then
                    local current=part.LocalTransparencyModifier
                    local record=records[part]
                    if not record then record={base=current};records[part]=record
                    elseif current~=record.applied then record.base=current end
                    record.applied=math.max(record.base,card.Options.Transparency.Value)
                    part.LocalTransparencyModifier=record.applied
                else restore(part) end
                cursor+=1
            end
        end
    end
    card=context.framework.Categories.Render:CreateModule({Name="X-Ray",Category="Render",ConfigKey="Universal.XRay",
        Tooltip="Fade map parts locally. Keep named objects visible; never fade characters or held tools.",Function=function(enabled)
            restoreAll();table.clear(candidates);table.clear(indexed);cursor=1;pause=0
            if not enabled then card:SetStatus(nil);return end
            changed()
            for _,part in ipairs(world:GetDescendants()) do add(part) end
            card:Clean(restoreAll)
            card:Clean(world.DescendantAdded:Connect(add))
            card:Loop(step);step(0)
        end})
    card:CreateDropdown({Name="Scope",List={"All map","Walls","Named parts"},Index=1,Function=changed})
    card:CreateSlider({Name="Transparency",Min=0,Max=1,Default=0.5,Step=0.05,Decimal=2,Function=changed})
    card:CreateTextBox({Name="Part names",Default="",Placeholder="Wall, Window",Show={Option="Scope",Values={"Named parts"}},Function=changed,
        Tooltip="Exact part names, separated by commas. Only these names fade in Named parts scope."})
    card:CreateTextBox({Name="Keep visible",Default="",Placeholder="Spawn, Objective",Function=changed,
        Tooltip="Vape-style kept-part list. Exact names separated by commas; these parts never fade."})
    card:CreateToggle({Name="Keep floors",Default=true,Function=changed})
    card:CreateToggle({Name="Collidable only",Default=true,Function=changed})
    card:CreateToggle({Name="Include unanchored",Default=false,Function=changed})
    card:CreateToggle({Name="Limit range",Default=true,Function=changed})
    card:CreateSlider({Name="Range",Min=25,Max=5000,Default=250,Show={Option="Limit range",Values={true}},Function=changed})
    Module.Initialized=true
    return card
end
function Module.destroy()
    if card and card.Enabled then card:Toggle(false) end
    card=nil;Module.Initialized=false
end
return Module
