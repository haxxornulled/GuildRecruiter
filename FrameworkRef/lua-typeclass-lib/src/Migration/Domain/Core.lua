-- Domain/Core.lua
-- Enhanced dependency injection container with better error handling

-- Ensure global namespace exists before anything else
_G.GuildRecruiter = _G.GuildRecruiter or {}

local Core = {}
Core._services = {}
Core._singletons = {}
Core._tags = {}
Core._initialized = false

local function Log(msg, ...)
    if msg then
        print("|cff33ff99[Core]|r " .. string.format(msg, ...))
    else
        print("|cff33ff99[Core]|r (no message)")
    end
end

function Core.Register(name, ctor, opts)
    assert(type(name) == "string" and name ~= "", "Service name required")
    assert(type(ctor) == "function", "Constructor required")
    opts = opts or {}
    Core._services[name] = ctor
    Core._tags[name] = opts.tags or {}
    if opts.singleton then
        Core._singletons[name] = false -- instantiate later
        Log("Registered singleton service '%s'", name)
    else
        Core._singletons[name] = nil
        Log("Registered transient service '%s'", name)
    end
end

function Core.Resolve(name, ...)
    assert(type(name) == "string", "Service name required")
    local ctor = Core._services[name]
    assert(ctor, "Service '" .. tostring(name) .. "' not registered")

    if Core._singletons[name] ~= nil then
        if not Core._singletons[name] then
            Log("Instantiating singleton service '%s'", name)
            local ok, instanceOrErr = pcall(ctor, Core, ...)
            if not ok then
                error(("Failed to instantiate singleton service '%s': %s"):format(name, tostring(instanceOrErr)))
            end
            Core._singletons[name] = instanceOrErr
        else
            Log("Returning existing singleton instance of '%s'", name)
        end
        return Core._singletons[name]
    else
        Log("Creating transient instance of '%s'", name)
        local ok, instanceOrErr = pcall(ctor, Core, ...)
        if not ok then
            error(("Failed to create transient instance of '%s': %s"):format(name, tostring(instanceOrErr)))
        end
        return instanceOrErr
    end
end

function Core.InitAll()
    if Core._initialized then
        Log("Core already initialized, skipping")
        return
    end

    Log("Starting Core initialization...")
    
    for name, ctor in pairs(Core._services) do
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
                print("|cffff0000[GuildRecruiter]|r Error initializing service '" .. name .. "': " .. tostring(err))
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
    print("|cff33ff99[GuildRecruiter]|r -- DI Container Diagnostic --")
    for name, ctor in pairs(Core._services) do
        local status, result = pcall(function()
            local svc = Core.Resolve(name)
            return svc and "OK" or "nil"
        end)
        if status and result == "OK" then
            print(string.format("|cff00ff00Service '%s': OK|r", name))
        else
            print(string.format("|cffff0000Service '%s': FAIL - %s|r", name, tostring(result)))
        end
    end
    print("|cff33ff99[GuildRecruiter]|r -- End Diagnostic --")
end

-- Make Core globally available
_G.GuildRecruiterCore = Core

-- Register EventHandler (event bus, events layer)
Core.Register("EventHandler", function(core)
    return _G.GuildRecruiter.EventHandler or error("EventHandler module missing")
end, { singleton = true })

-- Register RecruitScoring (domain layer)
Core.Register("RecruitScoring", function(core)
    return _G.GuildRecruiter.RecruitScoring or error("RecruitScoring module missing")
end, { singleton = true })

-- Register MessageTemplateService (domain/application layer)
Core.Register("MessageTemplateService", function(core)
    return _G.GuildRecruiter.MessageTemplateService or error("MessageTemplateService module missing")
end, { singleton = true })

-- Register Logger (infrastructure layer)
Core.Register("Logger", function(core)
    local Logger = _G.GuildRecruiter.Logger
    if not Logger then
        error("Logger module missing at registration time")
    end
    if Logger.Init then
        return Logger.Init(core)
    end
    return Logger
end, { singleton = true })

-- Register WoWApiAdapter (infrastructure layer) - FIXED
Core.Register("WoWApiAdapter", function(core)
    local Api = _G.GuildRecruiter.WoWApiAdapter 
    if not Api then
        error("WoWApiAdapter module missing")
    end
    if Api.Init then
        return Api.Init(core)
    end
    return Api
end, { singleton = true })

-- Register SlashCommands (infrastructure layer)
Core.Register("SlashCommands", function(core)
    local SCS = _G.GuildRecruiter.SlashCommands 
    if not SCS then
        error("SlashCommands module missing")
    end
    if SCS.Init then
        return SCS.Init(core)
    end
    return SCS
end, { singleton = true })

-- Register RecruitmentService (application layer)
Core.Register("RecruitmentService", function(core)
    local RSvc = _G.GuildRecruiter.RecruitmentService 
    if not RSvc then
        error("RecruitmentService module missing")
    end
    if RSvc.Init then
        return RSvc.Init({
            Logger = core.Resolve("Logger"),
            RecruitScoring = core.Resolve("RecruitScoring"),
            MessageTemplateService = core.Resolve("MessageTemplateService"),
            WoWApiAdapter = core.Resolve("WoWApiAdapter"),
            EventHandler = core.Resolve("EventHandler"),
        })
    end
    return RSvc
end, { singleton = true })

-- Register ExportService (infrastructure layer)
Core.Register("ExportService", function(core)
    return _G.GuildRecruiter.ExportService or error("ExportService module missing")
end, { singleton = true })

-- Register PlayerDataCollectorService (infrastructure layer)
Core.Register("PlayerDataCollectorService", function(core)
    return _G.GuildRecruiter_PlayerDataCollectorService or error("PlayerDataCollectorService not loaded")
end, { singleton = true })

return Core