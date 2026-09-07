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
    -- Optional hook: seed world.files / folders / JSONDecode before the
    -- chunk runs. Cache sweeps and loadConfig fire during bootstrap.
    if type(ctx.prepareWorld) == "function" then
        ctx.prepareWorld(world)
    end
    local playerGui: any = Mock.newInstance("PlayerGui")
    playerGui.Name = "PlayerGui"
    playerGui.Parent = world.localPlayer

    local chunk: any, compileError: any = loadstring(source, "@src/ARandomMenu.luau")
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
        -- A suite may serve specific extra files (game modules are not in the
        -- bundle; they are fetched per-URL at runtime). Anything not served
        -- here stays a 404, exactly like the real world's rejected URL.
        if type(ctx.httpGet) == "function" then
            local served: any = ctx.httpGet(url)
            if type(served) == "string" then
                return served
            end
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
