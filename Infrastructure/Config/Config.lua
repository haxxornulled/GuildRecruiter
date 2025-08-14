-- (Standard varargs destructure used across the repo)
local __params = { ... }
local ADDON_NAME, Addon = __params[1], __params[2]

local DB_NAME = "GuildRecruiterDB"
_G[DB_NAME] = _G[DB_NAME] or {}
local DB = _G[DB_NAME]

local DEFAULTS = {
    broadcastEnabled    = false,
    broadcastChannel    = "AUTO",
    broadcastInterval   = 300,
    jitterPercent       = 0.15,
    customMessage1      = "",
    customMessage2      = "",
    customMessage3      = "",
    messageCollapse     = {},
    messageOpenKey      = "customMessage1",
    devMode             = false,
    inviteClickCooldown = 3,
    invitePillDuration  = 3,
    inviteCycleEnabled  = true,
    toastOnDecline      = true,
    autoBlacklistDeclines = true,
    allowSayFallbackConfirm = false,
    logLevel            = "INFO",
    logBufferCapacity   = 500,
    inviteHistoryMax    = 1000,
    disposeContainerOnShutdown = true,
    prospectsMax        = 0,
    blacklistMax        = 0,
    autoPruneInterval   = 1800,
    chatLogMinLevel     = "INFO",
    dbVersion           = 1,
}

local VALID_CHANNEL_SPECS = { AUTO = true, SAY = true, YELL = true, GUILD = true, OFFICER = true, INSTANCE_CHAT = true }
local function isValidChannelSpec(spec)
    if type(spec) ~= "string" then return false end
    if VALID_CHANNEL_SPECS[spec] then return true end
    if spec:match("^CHANNEL:%w+") then return true end
    return false
end

local function shallow_copy(t)
    if not t then return {} end
    local r = {}
    for k, v in pairs(t) do
        r[k] = v
    end
    return r
end

local function apply_defaults(dst, src)
    dst = dst or {}
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = (type(v) == "table") and shallow_copy(v) or v
        end
    end
    return dst
end

local function try_require(key)
    if not Core or not Core.Addon then return nil end
    local pk = rawget(Core.Addon, 'Peek')
    if type(pk) == 'function' then
        local inst = pk(key); if inst ~= nil then return inst end
    end
    -- Do not call Addon.require here; we are in Phase 1 and must not build the container
    -- Only emit a one-time dev-mode diagnostic (avoid noise for end users)
    local isDev = (type(DB) == 'table' and not not DB.devMode) or false
    if isDev then
        _G.__GR_TRY_REQ_FAILS = _G.__GR_TRY_REQ_FAILS or {}
        if not _G.__GR_TRY_REQ_FAILS[key] then
            _G.__GR_TRY_REQ_FAILS[key] = true
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[%s][Config]|r Failed to require '%s' (lazy dependency)", ADDON_NAME or "GR", tostring(key)))
            end
        end
    end
    return nil
end
-- Publish with graceful deferral until EventBus is available (no container build)
local __pending = {}
local __flushScheduled = false
local __retries = 0
local function scheduleFlush()
    if __flushScheduled then return end
    __flushScheduled = true
    local delay = (__retries == 0) and 0 or 0.10
    local tf = rawget(_G, 'C_Timer') and _G.C_Timer.After
    if type(tf) ~= 'function' then __flushScheduled = false; return end
    tf(delay, function()
        __flushScheduled = false
        local bus = try_require('EventBus')
        if bus and bus.Publish then
            while #__pending > 0 do
                local e = table.remove(__pending, 1)
                if e and e.event then
                    pcall(bus.Publish, bus, e.event, unpack(e.args or {}))
                end
            end
            __retries = 0
            return
        end
        __retries = __retries + 1
        if __retries < 10 then scheduleFlush() end
    end)
end
local function publish(event, ...)
    local bus = try_require("EventBus")
    if bus and bus.Publish then
        pcall(bus.Publish, bus, event, ...)
        return true
    end
    __pending[#__pending + 1] = { event = event, args = { ... } }
    scheduleFlush()
    return false
end
local function info(template, props)
    local log = try_require("Logger")
    if log and log.Info then
        log:ForContext("Subsystem", "Config"):Info(template or "", props or {})
        return
    end
    local line = tostring(template or "")
    if props and next(props) then
        local parts = {}
        for k, v in pairs(props) do
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        end
        line = line .. "  {" .. table.concat(parts, ", ") .. "}"
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff66ccff[%s][Config]|r %s", ADDON_NAME, line))
    end
end

-- Helper to decide if we should publish events (avoids analyzer 'impossible if')
local Config = {}
local function shouldPublish()
    local sup = rawget(Config, '_suppressEvents')
    return not sup
end
function Config:Get(key, fallback)
    if key == nil then return DB end
    local v = DB[key]
    if v == nil then return fallback end
    return v
end
function Config:Set(key, value)
    if key == nil then return end
    local original = value

    if key == "jitterPercent" then
        value = tonumber(value) or DEFAULTS.jitterPercent
        if value < 0 then value = 0 elseif value > 0.50 then value = 0.50 end
    elseif key == "broadcastInterval" then
        value = tonumber(value) or DEFAULTS.broadcastInterval
        if value < 30 then value = 30 elseif value > 3600 then value = 3600 end
    elseif key == "inviteClickCooldown" or key == "invitePillDuration" then
        value = tonumber(value) or DEFAULTS[key]
        if value < 0 then value = 0 elseif value > 120 then value = 120 end
    elseif key == "broadcastChannel" then
        if not isValidChannelSpec(value) then value = DEFAULTS.broadcastChannel end
    elseif key == "logLevel" then
        value = tostring(value):upper()
        local allowed = { TRACE = true, DEBUG = true, INFO = true, WARN = true, ERROR = true, FATAL = true }
        if not allowed[value] then value = DEFAULTS.logLevel end
    elseif key == "inviteHistoryMax" then
        value = tonumber(value) or DEFAULTS.inviteHistoryMax
        if value < 100 then value = 100 elseif value > 20000 then value = 20000 end
        value = math.floor(value)
    elseif key == "disposeContainerOnShutdown" then
        value = not not value
    end

    DB[key] = value
    if shouldPublish() then publish("ConfigChanged", key, value) end
    return value ~= original
end

function Config:All()
    return DB
end

function Config:IsDev()
    return not not DB.devMode
end
function Config:Reset()
    local savedProspects = DB and DB.prospects
    local savedBlacklist = DB and (DB.blacklist or DB.doNotInvite)
    local w = rawget(_G, 'wipe')
    if type(w) == 'function' then w(DB) else for k in pairs(DB) do DB[k] = nil end end
    apply_defaults(DB, DEFAULTS)
    if savedProspects then DB.prospects = savedProspects end
    if savedBlacklist then DB.blacklist = savedBlacklist end
    publish("ConfigChanged", "*reset*", true)
end
local function normalizeKey(key)
    local before = DB[key]
    Config:Set(key, before)
end
local function InitializeConfig()
    if _G[DB_NAME].doNotInvite and not _G[DB_NAME].blacklist then
        _G[DB_NAME].blacklist = _G[DB_NAME].doNotInvite
        _G[DB_NAME].doNotInvite = nil
    end
    _G[DB_NAME] = apply_defaults(_G[DB_NAME], DEFAULTS)
    -- Simple migration scaffold
    local curVersion = tonumber(_G[DB_NAME].dbVersion) or 1
    local targetVersion = DEFAULTS.dbVersion
    if curVersion < targetVersion then
        -- future: iterate migrations[curVersion+1 .. targetVersion]
        _G[DB_NAME].dbVersion = targetVersion
    end
    DB = _G[DB_NAME]
    Config._suppressEvents = true
    local normalized = 0
    for _, k in ipairs({
        "broadcastChannel", "broadcastInterval", "jitterPercent", "inviteClickCooldown", "invitePillDuration",
        "logLevel", "inviteHistoryMax", "disposeContainerOnShutdown", "prospectsMax", "blacklistMax",
        "autoPruneInterval", "chatLogMinLevel"
    }) do
        local before = DB[k]
        normalizeKey(k)
        if DB[k] ~= before then normalized = normalized + 1 end
    end
    Config._suppressEvents = nil
    publish("ConfigReady")
    local n = 0
    for _ in pairs(DB) do n = n + 1 end
    info("Config initialized (keys: {Count}, normalized: {Norm})", { Count = n, Norm = normalized })
end
local function RegisterConfigFactory()
    if not Addon.provide then error("Config: Addon.provide not available") end
    if not (Addon.IsProvided and Addon.IsProvided("Config")) then
        Addon.provide("Config", function() return Config end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'config' } })
    end
    -- Mark implementation and provide interface alias for IConfiguration
    Config.__implements = Config.__implements or {}; Config.__implements['IConfiguration'] = true
    if Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('IConfiguration')) then
        Addon.safeProvide('IConfiguration', function(sc) return sc:Resolve('Config') end, { lifetime = 'SingleInstance', meta = { layer = 'Core', role = 'contract-alias' } })
    end
    InitializeConfig()
end
-- Note: No Addon.Config compatibility proxy; consumers should resolve 'IConfiguration'.
Addon._RegisterConfig = RegisterConfigFactory
-- Auto-register on load to ensure IConfiguration is available even before bootstrap runs (idempotent)
pcall(RegisterConfigFactory)
return RegisterConfigFactory
