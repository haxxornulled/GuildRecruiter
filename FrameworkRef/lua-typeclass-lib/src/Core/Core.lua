local ADDON_NAME = "TaintedSin" -- Change this ONCE per project!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

Addon._modules = Addon._modules or {}

if not Addon.provide then
    function Addon.provide(name, mod)
        if not name or not mod then
            error("Usage: Addon.provide(name, mod)")
        end
        Addon._modules[name] = mod
    end
end

if not Addon.require then
    function Addon.require(name)
        local m = Addon._modules[name]
        if not m then
            error("Module '"..tostring(name).."' not found. " ..
                "Did you forget to load the file in your .toc, or forget Addon.provide?")
        end
        return m
    end
end

--[[
===============================================================================
    Core.lua - Enterprise Dependency Injection Container for Lua
===============================================================================

    A lightweight, portable, feature-complete DI container for advanced Lua apps
    and addons. Supports constructor injection, explicit dependency wiring,
    singleton/transient lifetimes, opt-in service locator (factory) pattern, 
    diagnostics, and robust circular dependency detection.

-------------------------
  Why use this container?
-------------------------
- Clean, testable, and decoupled code: Dependencies are *explicit*, not hidden.
- No reliance on global state or implicit lookup.
- All services are registered by name, with clear dependency lists.
- Singleton or transient lifetimes per service.
- Supports cross-version Lua (5.1, LuaJIT, 5.2+, 5.4).
- Explicit opt-in for "service locator" (anti-pattern) if you really need it.

-------------------------
  Key Concepts:
-------------------------
- **Register:** Define a service by name, constructor function, and options.
- **Resolve:** Get an instance of a service, with its dependencies injected.
- **Singleton:** One shared instance for the app (default: off).
- **Transient:** New instance each Resolve().
- **Constructor injection:** Dependencies are passed as arguments, not fetched from inside.
- **Pure DI:** Services don’t see the container, unless you *opt in* via `injectCore`.
- **Service locator:** *Opt-in only* via `{ injectCore = true }`; discouraged unless you are writing factories or cross-wiring.

-------------------------
  Usage Examples:
-------------------------
-- Register a basic service with dependencies:
Core.Register("FooService", function(bar, baz) 
    -- bar, baz are injected
end, { deps = { "BarService", "BazService" } })

-- Register a singleton service (one instance for app lifetime):
Core.Register("Config", function() 
    return { version = 1 }
end, { singleton = true })

-- Register a factory or a cross-wiring service (gets container as first arg):
Core.Register("Factory", function(core, config) 
    -- can resolve on demand: core.Resolve("FooService")
end, { deps = { "Config" }, injectCore = true })

-- Resolve a service (extra arguments are passed after dependencies):
local foo = Core.Resolve("FooService", "runtime", 42)

-------------------------
  API Reference:
-------------------------
Core.Register(name: string, ctor: function, opts: table)
    - Registers a service.
    - name: Service name (string, required)
    - ctor: Constructor function (required)
        - Arguments: If injectCore=true, (core, dep1, dep2, ...); else (dep1, dep2, ...)
        - Returns: the service instance
    - opts: Table (optional)
        - deps: Array of service names (dependency order is preserved)
        - singleton: true|false (default false)
        - injectCore: true|false (default false; if true, passes container as first arg)
        - tags: Array of string tags (for deferred init etc.)

Core.Unregister(name)
    - Removes a registered service. Returns true if removed, false if not found.

Core.HasService(name)
    - Returns true if a service is registered.

Core.ListServices()
    - Returns a table (array) of registered service names.

Core.Resolve(name, ...)
    - Instantiates or retrieves a service by name, injecting dependencies.
    - ... : Additional arguments passed to the constructor after DI deps.
    - For singleton: Only the *first* call receives varargs.

Core.InitAll()
    - Initializes all services not tagged with "defer-init".
    - Good for apps that want to ensure all key services are up before use.

Core.DiagnoseServices()
    - Checks if all registered services can be resolved, prints per-service status.

Core.EnableLogging(val)
    - Enables/disables diagnostic logging.

-------------------------
  Design Notes:
-------------------------
- Circular dependency detection is robust; will throw with a clear path if found.
- The container itself is never injected unless you ask for it (pure DI by default).
- All errors are surfaced with detailed, contextual information.

-------------------------
  Singleton Varargs Note:
-------------------------
- If you pass varargs to Resolve() of a singleton, *only the first call* will use those args.
- All subsequent Resolve() calls will return the cached instance.

-------------------------
  Version compatibility:
-------------------------
- Works in Lua 5.1, 5.2, 5.3, 5.4, LuaJIT, WoW/Lua sandbox (uses local unpack = table.unpack or unpack).

===============================================================================
]]

local Core = {}
Core._services = {}
Core._singletons = {}
Core._tags = {}
Core._deps = {}
Core._injectCore = {}  -- Maps service name -> true if container should be injected
Core._initialized = false
Core._logEnabled = true

local resolvingStack = {}

-- Cross-version unpack
local unpack = table.unpack or unpack

local function Log(msg, ...)
    if Core._logEnabled then
        if msg then
            print("[Core] " .. string.format(msg, ...))
        else
            print("[Core] (no message)")
        end
    end
end

function Core.EnableLogging(val)
    Core._logEnabled = val ~= false
end

function Core.Register(name, ctor, opts)
    assert(type(name) == "string" and name ~= "", "Service name required")
    assert(type(ctor) == "function", "Constructor required")
    if Core._services[name] then
        error("Service '" .. name .. "' already registered")
    end
    opts = opts or {}
    Core._services[name] = ctor
    Core._tags[name] = opts.tags or {}
    Core._deps[name] = opts.deps or {}
    Core._injectCore[name] = opts.injectCore == true
    if opts.singleton then
        Core._singletons[name] = false
        Log("Registered singleton service '%s'", name)
    else
        Core._singletons[name] = nil
        Log("Registered transient service '%s'", name)
    end
end

function Core.Unregister(name)
    local existed = Core._services[name] ~= nil
    Core._services[name] = nil
    Core._singletons[name] = nil
    Core._tags[name] = nil
    Core._deps[name] = nil
    Core._injectCore[name] = nil
    if existed then
        Log("Unregistered service '%s'", name)
    else
        Log("Tried to unregister non-existent service '%s'", name)
    end
    return existed
end

function Core.HasService(name)
    return Core._services[name] ~= nil
end

function Core.ListServices()
    local out = {}
    for name in pairs(Core._services) do table.insert(out, name) end
    return out
end

local function resolveDeps(depNames)
    local instances = {}
    for _, depName in ipairs(depNames or {}) do
        table.insert(instances, Core.Resolve(depName))
    end
    return instances
end

local function checkCircularDependency(name)
    for _, n in ipairs(resolvingStack) do
        if n == name then
            error("Circular dependency detected: " .. table.concat(resolvingStack, " -> ") .. " -> " .. name)
        end
    end
end

-- DRY helper for merging args tables (for constructor: DI deps + varargs)
local function mergeArgs(a, b)
    local out = {}
    for _, v in ipairs(a) do table.insert(out, v) end
    for _, v in ipairs(b) do table.insert(out, v) end
    return out
end

function Core.Resolve(name, ...)
    assert(type(name) == "string", "Service name required")
    local ctor = Core._services[name]
    assert(ctor, "Service '" .. tostring(name) .. "' not registered")

    checkCircularDependency(name)
    table.insert(resolvingStack, name)
    
    local extraArgs = {...}
    local depInstances
    local instance

    -- Always clean up the resolvingStack, even on error
    local function doResolve()
        depInstances = resolveDeps(Core._deps[name])
        local injectCore = Core._injectCore[name]
        local args

        if injectCore then
            args = {Core}
            for _, v in ipairs(depInstances) do table.insert(args, v) end
        else
            args = depInstances
        end

        local allArgs = mergeArgs(args, extraArgs)

        if Core._singletons[name] ~= nil then
            if not Core._singletons[name] then
                Log("Instantiating singleton service '%s'", name)
                local ok, instanceOrErr = pcall(ctor, unpack(allArgs))
                if not ok then
                    error(("Failed to instantiate singleton service '%s': %s"):format(name, tostring(instanceOrErr)))
                end
                Core._singletons[name] = instanceOrErr
                instance = instanceOrErr
            else
                Log("Returning existing singleton instance of '%s'", name)
                instance = Core._singletons[name]
            end
        else
            Log("Creating transient instance of '%s'", name)
            local ok, instanceOrErr = pcall(ctor, unpack(allArgs))
            if not ok then
                error(("Failed to create transient instance of '%s': %s"):format(name, tostring(instanceOrErr)))
            end
            instance = instanceOrErr
        end
        return instance
    end

    local ok, result = pcall(doResolve)
    table.remove(resolvingStack)
    if not ok then error(result) end
    return result
end

function Core.InitAll()
    if Core._initialized then
        Log("Core already initialized, skipping")
        return
    end

    Log("Starting Core initialization...")

    for name in pairs(Core._services) do
        local tags = Core._tags[name] or {}
        local deferInit = false
        for _, t in ipairs(tags) do
            if t == "defer-init" then
                deferInit = true
                break
            end
        end

        if not deferInit then
            Log("Initializing service: %s", name)
            local ok, err = pcall(function() Core.Resolve(name) end)
            if not ok then
                Log("ERROR initializing service '%s': %s", name, tostring(err))
                print("[Core] Error initializing service '" .. name .. "': " .. tostring(err))
            else
                Log("Successfully initialized service: %s", name)
            end
        else
            Log("Skipped deferred init for service: %s", name)
        end
    end

    Core._initialized = true
    Log("Core initialization complete")
end

function Core.DiagnoseServices()
    print("[Core] -- DI Container Diagnostic --")
    local results = {}
    for name in pairs(Core._services) do
        local status, result = pcall(function()
            local svc = Core.Resolve(name)
            return svc and "OK" or "nil"
        end)
        if status and result == "OK" then
            print(string.format("Service '%s': OK", name))
            results[name] = true
        else
            print(string.format("Service '%s': FAIL - %s", name, tostring(result)))
            results[name] = false
        end
    end
    print("[Core] -- End Diagnostic --")
    return results
end

Addon.provide("Core", Core)

return Core
