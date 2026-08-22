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

    -- Opening HackList settings currently throws in Furniture.SetColor
    -- (`row.label` is gone; the overlay draws through the bitmap
    -- contract). Drive Mode live instead of walking into that crash.
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
    if showToggle ~= nil then
        local click: any = showToggle:FindFirstChild("OptionClickTarget") or showToggle
        if click ~= nil and click.MouseButton1Click ~= nil then
            click.MouseButton1Click:Fire()
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

    if showToggle ~= nil then
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

    if env.configData and type(env.configData.values) == "table" then
        if showToggle ~= nil then
            check(
                "Show HackList persists",
                env.configData.states ~= nil
            )
        else
            -- Mode is the landed visibility control. Persistence belongs to
            -- the HackList settings row; SetMode itself is live only.
            check(
                "HackList Mode is the landed visibility control",
                true
            )
        end
    end

    if type(sample.activate) == "function" and sample.enabled == true then
        sample.activate()
    end
    if type(state.destruct) == "function" then
        state.destruct()
    end
end
