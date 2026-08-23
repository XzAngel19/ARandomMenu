--!strict
--
-- Headless tests: the shell survives every executor shape we ship to.
--
-- Full executor, getsynasset-only, no filesystem, no HTTP (assets),
-- mobile full, mobile limited. Each boot must fall back honestly and
-- never throw. The 43-module inventory still starts.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bundleSource: any = ctx.bundleSource

    section("CapabilityMatrix")

    if type(source) ~= "string" or type(bundleSource) ~= "string" then
        check("capability boot source missing", false)
        return
    end

    local function bootVariant(label: string, setup: (any) -> ()): any
        local world: any = Mock.install()
        setup(world)
        local playerGui: any = Mock.newInstance("PlayerGui")
        playerGui.Name = "PlayerGui"
        playerGui.Parent = world.localPlayer

        local chunk: any, compileError: any = loadstring(source, "@ARandomMenu.luau")
        if type(chunk) ~= "function" then
            return {
                ok = false,
                error = tostring(compileError),
                label = label,
            }
        end
        Mock.inject(world, chunk)
        world.globals.game.HttpGet = world.httpGet
            or function(_self: any, url: any, _cache: any): string
                if type(url) == "string"
                    and string.find(url, "runtime/bundle.luau", 1, true)
                then
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
        return {
            ok = ran == true and captured ~= nil and captured.state ~= nil,
            error = ran and (captured and nil or "no state") or tostring(failure),
            state = captured and captured.state or nil,
            env = captured,
            world = world,
            label = label,
        }
    end

    local files: {[string]: string} = {}
    local function fullFiles(world: any): ()
        world.globals.writefile = function(path: string, contents: string): ()
            files[path] = contents
        end
        world.globals.readfile = function(path: string): string
            return files[path] or ""
        end
        world.globals.isfile = function(path: string): boolean
            return files[path] ~= nil
        end
        world.globals.isfolder = function(_path: string): boolean
            return true
        end
        world.globals.makefolder = function(_path: string): () end
    end

    local variants: {any} = {
        {
            "full executor",
            function(world: any): ()
                fullFiles(world)
                world.globals.getcustomasset = function(path: string): string
                    return "rbxasset://full/" .. path
                end
                world.globals.getsynasset = world.globals.getcustomasset
            end,
        },
        {
            "getsynasset-only",
            function(world: any): ()
                fullFiles(world)
                world.globals.getsynasset = function(path: string): string
                    return "syn://" .. path
                end
            end,
        },
        {
            "no filesystem",
            function(_world: any): () end,
        },
        {
            "no HTTP",
            function(world: any): ()
                world.httpGet = function(_self: any, url: any, _cache: any): string
                    if type(url) == "string"
                        and string.find(url, "runtime/bundle.luau", 1, true)
                    then
                        return bundleSource
                    end
                    error("HTTP disabled", 0)
                end
            end,
        },
        {
            "mobile full",
            function(world: any): ()
                world.services.UserInputService.TouchEnabled = true
                world.services.UserInputService.KeyboardEnabled = false
                world.services.UserInputService.MouseEnabled = false
                fullFiles(world)
                world.globals.getcustomasset = function(path: string): string
                    return "rbxasset://mobile/" .. path
                end
            end,
        },
        {
            "mobile limited",
            function(world: any): ()
                world.services.UserInputService.TouchEnabled = true
                world.services.UserInputService.KeyboardEnabled = false
                world.services.UserInputService.MouseEnabled = false
            end,
        },
    }

    for _, variant: any in ipairs(variants) do
        local label: string = variant[1]
        local setup: (any) -> () = variant[2]
        local boot: any = bootVariant(label, setup)
        check(label .. " boots without crashing", boot.ok == true, boot.error)
        if boot.ok and boot.state ~= nil then
            local bitmap: any = boot.state.bitmapText
            if bitmap ~= nil then
                check(
                    label .. " never claims Minecraft exact without a pack",
                    bitmap.source ~= "minecraft-exact",
                    tostring(bitmap.source)
                )
            end
            local modules: number = tonumber(
                boot.state.boot
                    and boot.state.boot.timing
                    and boot.state.boot.timing.moduleCount
            ) or 0
            check(
                label .. " still starts the 43-module inventory",
                modules == 43,
                tostring(modules)
            )
            if type(boot.state.destruct) == "function" then
                local torn: boolean = pcall(boot.state.destruct)
                check(label .. " tears down without crashing", torn == true)
            end
        end
    end
end
