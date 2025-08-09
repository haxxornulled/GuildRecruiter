-- Config.lua — persistent settings (DI-safe, EventBus-friendly)
-- SavedVariables declared in .toc: GuildRecruiterDB

local ADDON_NAME, Addon = ...

-- ===========================
-- SavedVariables root
-- ===========================
local DB_NAME = "GuildRecruiterDB"
_G[DB_NAME] = _G[DB_NAME] or {}
local DB = _G[DB_NAME]

-- ===========================
-- Defaults (extend as needed)
-- ===========================
local DEFAULTS = {
    broadcastEnabled    = false,
    broadcastChannel    = "AUTO",
    broadcastInterval   = 300,  -- seconds
    jitterPercent       = 0.15, -- 0.00 - 0.50
    customMessage1      = "",
    customMessage2      = "",
    customMessage3      = "",
    messageCollapse     = {},   -- accordion sections collapsed
    messageOpenKey      = "customMessage1",

    -- UI invite feedback durations (seconds)
    inviteClickCooldown = 3,
    invitePillDuration  = 3,
}

-- ===========================
-- Utils
-- ===========================
local function shallow_copy(t)
    if not t then return {} end
    local r = {}; for k, v in pairs(t) do r[k] = v end; return r
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

-- Prefer DI, but fall back safely — use pcall around Core.Addon.require
local function try_require(key)
    if not Core or not Core.Addon or not Core.Addon.require then return nil end
    local ok, inst = pcall(Core.Addon.require, key)
    if ok then return inst end
    return nil
end

local function publish(event, ...)
    local bus = try_require("EventBus")
    if bus and bus.Publish then pcall(bus.Publish, bus, event, ...) end
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
        for k, v in pairs(props) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        line = line .. "  {" .. table.concat(parts, ", ") .. "}"
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff66ccff[%s][Config]|r %s", ADDON_NAME, line))
    end
end

-- ===========================
-- Config object (backed by SavedVariables)
-- ===========================
local Config = {}

function Config:Get(key, fallback)
    if key == nil then return DB end
    local v = DB[key]
    if v == nil then return fallback end
    return v
end

function Config:Set(key, value)
    DB[key] = value
    publish("ConfigChanged", key, value)
end

function Config:All()
    return DB
end

function Config:Reset()
    -- Preserve other collections sharing the same SV root (if any)
    local savedProspects = DB and DB.prospects
    local savedBlacklist = DB and (DB.blacklist or DB.doNotInvite)

    wipe(DB)
    apply_defaults(DB, DEFAULTS)

    if savedProspects then DB.prospects = savedProspects end
    if savedBlacklist then DB.blacklist = savedBlacklist end

    publish("ConfigChanged", "*reset*", true)
end

-- ===========================
-- Initialize function (called from Init.lua)
-- ===========================
local function InitializeConfig()
    -- Migrate legacy blacklist key if present
    if _G[DB_NAME].doNotInvite and not _G[DB_NAME].blacklist then
        _G[DB_NAME].blacklist = _G[DB_NAME].doNotInvite
        _G[DB_NAME].doNotInvite = nil
    end
    _G[DB_NAME] = apply_defaults(_G[DB_NAME], DEFAULTS)
    DB = _G[DB_NAME]

    publish("ConfigReady")

    local n = 0; for _ in pairs(DB) do n = n + 1 end
    info("Config initialized (keys: {Count})", { Count = n })
end

-- ===========================
-- DI registration function (called from Init.lua)
-- ===========================
local function RegisterConfigFactory()
    if not Addon.provide then
        error("Config: Addon.provide not available")
    end
    
    Addon.provide("Config", function() return Config end, { lifetime = "SingleInstance" })
    
    -- Initialize the config data
    InitializeConfig()
end

-- Expose a lightweight facade on the addon namespace (safe)
Addon.Config = setmetatable({}, {
    __index = function(_, k)
        if Addon._booting then
            error("Cannot access Config during boot phase")
        end
        local inst = Addon.require("Config"); return inst[k]
    end,
    __call  = function(_, ...) return Addon.require("Config"), ... end
})

-- Export registration function
Addon._RegisterConfig = RegisterConfigFactory

return RegisterConfigFactory
