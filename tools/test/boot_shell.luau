--!strict
--
-- Boot the real shell inside a fresh mock world. Furniture, Navigator and
-- ClickGUI already each copy this sequence; C4–C6 share it so a surface
-- check and a budget check look at the same contract.

return function(ctx: any): any
    local Mock: any = ctx.Mock
    local source: any = ctx.shellSource
    local bundleSource: any = ctx.bundleSource
    if type(source) ~= "string" or type(bundleSource) ~= "string" then
        return {
            ok = false,
            error = "shell/bundle source missing",
        }
    end

    local world: any = Mock.install()
    local playerGui: any = Mock.newInstance("PlayerGui")
    playerGui.Name = "PlayerGui"
    playerGui.Parent = world.localPlayer

    local chunk: any, compileError: any = loadstring(source, "@ARandomMenu.luau")
    if type(chunk) ~= "function" then
        return {
            ok = false,
            error = tostring(compileError),
            world = world,
        }
    end

    Mock.inject(world, chunk)
    world.globals.game.HttpGet = function(_self: any, url: any, _cache: any): string
        if type(url) == "string" and string.find(url, "runtime/bundle.luau", 1, true) then
            return bundleSource
        end
        return "404: Not Found"
    end

    local captured: any = nil
    local environment: any = getfenv(chunk)
    local realSetfenv: any = environment.setfenv
    environment.setfenv = function(fn: any, env: any): any
        if type(env) == "table" and env.ThemeEngine ~= nil then
            captured = env
        end
        return realSetfenv(fn, env)
    end

    local ran: boolean, failure: any = xpcall(chunk, function(message: any): string
        return tostring(message)
    end)
    if not ran then
        return {
            ok = false,
            error = tostring(failure),
            world = world,
        }
    end
    if captured == nil or captured.state == nil then
        return {
            ok = false,
            error = "boot did not publish the module environment",
            world = world,
        }
    end

    return {
        ok = true,
        env = captured,
        state = captured.state,
        world = world,
        playerGui = playerGui,
    }
end
