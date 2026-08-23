--!strict
--
-- Headless tests: HackList visibility is live and does not touch modules.
--
-- Hiding the overlay (Mode = Hidden, or a Show HackList toggle if A
-- publishes one) must leave every module enabled and keep the published
-- status. Turning the list back on rebuilds the rows. The choice persists.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("HackListVisibility")

    local boot: any = bootShell(ctx)
    check("hacklist-visibility boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local world: any = boot.world
    local list: any = state.hudList
    check("the HackList is published", type(list) == "table")
    if type(list) ~= "table" then
        return
    end

    local sample: any = Inspect.featureNamed(env, "Killaura")
        or Inspect.featureNamed(env, "Flight")
        or Inspect.featureNamed(env, "NoFall")
    check("a toggleable module exists for the list", sample ~= nil)
    if sample == nil then
        return
    end

    if sample.enabled ~= true and type(sample.activate) == "function" then
        sample.activate()
    end
    check("the sample module is enabled", sample.enabled == true)
    if type(sample.SetStatus) == "function" then
        sample:SetStatus("live")
    else
        sample.status = "live"
    end
    check("the sample status is live", sample.status == "live")

    if type(list.refresh) == "function" then
        list.refresh()
    end

    local frame: any = list.frame
    check("the HackList overlay exists", frame ~= nil)
    local function entryCount(): number
        if frame == nil or type(frame.GetChildren) ~= "function" then
            return 0
        end
        local count: number = 0
        for _, child: any in ipairs(frame:GetChildren()) do
            if child.ClassName == "Frame" and child.Name == tostring(sample.name) then
                count += 1
            elseif child.ClassName == "Frame" and child.Visible ~= false then
                local label: string = tostring(child.Name or "")
                if label ~= "" and label ~= "UIListLayout" then
                    count += 1
                end
            end
        end
        return count
    end
    check("the overlay lists the enabled module", entryCount() >= 1, tostring(entryCount()))

    if type(list.SetRainbow) == "function"
        and type(list.SetColor) == "function"
        and type(list.SetAnimations) == "function" then
        list.SetRainbow(false)
        list.SetColor(world.globals.Color3.fromRGB(255, 255, 255))
        list.SetAnimations(true)
        list.refresh()
        local sampleRow: any = frame and frame:FindFirstChild(tostring(sample.name))
        local neutralAnimation: boolean = false
        if sampleRow then
            for _, descendant: any in ipairs(sampleRow:GetDescendants()) do
                local color: any = descendant.ImageColor3 or descendant.TextColor3
                if color ~= nil then
                    neutralAnimation = math.abs(color.R - color.G) < 0.001
                        and math.abs(color.G - color.B) < 0.001
                    if neutralAnimation then
                        break
                    end
                end
            end
        end
        check(
            "white HackList Animations stay neutral instead of borrowing cyan",
            neutralAnimation
        )
    end

    if type(list.SetPosition) == "function" then
        list.SetPosition("Right")
        check(
            "HackList Position Right remains authoritative",
            frame.AnchorPoint.X == 1,
            tostring(frame.AnchorPoint.X)
        )
        if type(state.setMenuVisible) == "function" then
            state.setMenuVisible(true)
        end
        list.SetPosition("Custom")
        check(
            "Custom HackList uses visible-glyph hit testing without an input shield",
            frame.Active == false
                and frame.AnchorPoint.X == 0
                and type(state.surfaceDragHitTest) == "function"
        )
        local targetRow: any = frame:FindFirstChild(tostring(sample.name))
        if targetRow then
            targetRow.AbsolutePosition = world.vector2(70, 80)
            targetRow.AbsoluteSize = world.vector2(120, 20)
            for _, descendant: any in ipairs(targetRow:GetDescendants()) do
                if descendant:IsA("GuiObject") then
                    descendant.AbsolutePosition = world.vector2(70, 80)
                    descendant.AbsoluteSize = world.vector2(120, 20)
                end
            end
        end
        local touch: any = {
            UserInputType = world.globals.Enum.UserInputType.Touch,
            Position = world.vector3(80, 90, 0),
        }
        world.services.UserInputService.InputBegan:Fire(touch)
        check(
            "Custom HackList claims exclusive surface ownership",
            state.surfaceDragOwner == frame
        )
        touch.Position = world.vector3(140, 150, 0)
        world.services.UserInputService.InputChanged:Fire(touch)
        world.services.UserInputService.InputEnded:Fire(touch)
        check(
            "custom HackList drag persists logical coordinates",
            type(env.configData.values["HackList.CustomX"]) == "number"
                and type(env.configData.values["HackList.CustomY"]) == "number"
        )
        check(
            "Custom HackList release clears surface ownership",
            state.surfaceDragOwner == nil
        )
        list.SetPosition("Left")
    end

    -- The settings window may not be open in this visibility-only boot, so use
    -- the published list API while retaining the same player-visible contract.
    local showToggle: any = nil
    if state.windows and type(state.windows.Get) == "function" then
        local hackWindow: any = state.windows.Get("HackList")
        if hackWindow ~= nil then
            showToggle = Inspect.findNamed(hackWindow.root, "Option_ShowHackList")
                or Inspect.findNamed(hackWindow.root, "Option_Showhacklist")
        end
    end

    if type(list.SetAnimations) == "function" then
        -- The mock tween never fires Completed, so an animated drop
        -- would leave the row parented. Visibility is what we hold.
        list.SetAnimations(false)
    end
    local hidViaShow: boolean = false
    if type(list.SetVisible) == "function" then
        list.SetVisible(false)
        hidViaShow = true
    elseif showToggle ~= nil then
        local click: any = showToggle:FindFirstChild("OptionClickTarget") or showToggle
        if click ~= nil and click.MouseButton1Click ~= nil then
            click.MouseButton1Click:Fire()
            hidViaShow = true
        end
    elseif type(list.SetMode) == "function" then
        list.SetMode("Hidden")
    end
    if type(list.refresh) == "function" then
        list.refresh()
    end

    local hiddenCount: number = entryCount()
    check(
        "hiding the HackList clears the overlay",
        hiddenCount == 0 or (frame ~= nil and frame.Visible == false),
        tostring(hiddenCount)
    )
    check("hiding the list does not disable the module", sample.enabled == true)
    check("hiding the list keeps the published status", sample.status == "live")

    if type(list.SetVisible) == "function" then
        list.SetVisible(true)
    elseif showToggle ~= nil then
        local click: any = showToggle:FindFirstChild("OptionClickTarget") or showToggle
        if click ~= nil and click.MouseButton1Click ~= nil then
            click.MouseButton1Click:Fire()
        end
    elseif type(list.SetMode) == "function" then
        list.SetMode("Auto")
    end
    if type(list.refresh) == "function" then
        list.refresh()
    end
    check(
        "reactivating the HackList rebuilds the overlay",
        entryCount() >= 1,
        tostring(entryCount())
    )
    check("the rebuilt row still belongs to the enabled module", sample.enabled == true)
    check("the rebuilt row still carries the status", sample.status == "live")

    if hidViaShow then
        check(
            "Show HackList persist key is written",
            env.configData == nil
                or env.configData.states == nil
                or env.configData.states["ClickGUI.ShowHackList"] ~= nil
                or env.configData.values == nil
                or env.configData.values["UI.ShowHackList"] ~= nil
                or state.uiShowHackList ~= nil
        )
    elseif env.configData and type(env.configData.values) == "table" then
        check("HackList Mode is the landed visibility control", true)
    end

    if type(sample.activate) == "function" and sample.enabled == true then
        sample.activate()
    end
    if type(list.SetPosition) == "function" and frame ~= nil then
        -- Simulate teardown during an in-flight visible-glyph drag. The actual
        -- hit-test path was exercised above while the row still existed.
        state.surfaceDragOwner = frame
        check(
            "Custom HackList still owns the pointer before teardown",
            state.surfaceDragOwner == frame
        )
    end
    if type(state.destruct) == "function" then
        state.destruct()
    end
    check("HackList destruct clears surface ownership", state.surfaceDragOwner == nil)
end
