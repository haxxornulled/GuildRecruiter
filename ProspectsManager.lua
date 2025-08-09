-- ProspectsManager.lua — complete (SV-backed), no shims
local ADDON_NAME, Addon = ...
local Bus   = (Addon.Get and Addon.Get("EventBus")) or Addon.EventBus
local rawLogger = (Addon.Get and Addon.Get("Logger")) or Addon.Logger
local Log = rawLogger and rawLogger:ForContext("Prospects") or { Info=function() end, Error=function() end }

local PM = {}
Addon.ProspectsManager = PM
if Addon.provide then Addon.provide("ProspectsManager", PM) end

-- ===== SavedVariables =====
local function SV() _G.GuildRecruiterDB = _G.GuildRecruiterDB or {}; return _G.GuildRecruiterDB end
local function Prospects()
    local db = SV(); db.prospects = db.prospects or {}; return db.prospects
end
local function Blacklist()
    local db = SV();
    -- Migrate legacy key once
    if db.doNotInvite and not db.blacklist then
        db.blacklist = db.doNotInvite; db.doNotInvite = nil
    end
    db.blacklist = db.blacklist or {}
    return db.blacklist
end

-- ===== Utilities =====
local function FullName(unit)
    if not UnitExists(unit) then return nil end
    local name, realm = UnitName(unit)
    if not name or name == "" then return nil end
    realm = realm or GetNormalizedRealmName()
    return realm and (name.."-"..realm) or name
end

local function PlayerInfo(unit)
    local name = FullName(unit); if not name then return nil end
    local classLocal, classToken = UnitClass(unit)
    return {
        name       = name,
        level      = UnitLevel(unit) or 0,
        class      = classToken or "",
        classLocal = classLocal or "",
        zone       = GetZoneText() or "",
        guid       = UnitGUID(unit) or "",
        online     = (not UnitIsGhost(unit) and not UnitIsDeadOrGhost(unit)) and true or false,
        faction    = UnitFactionGroup(unit) or "",
    }
end

local function IsPlayer(unit) return UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") end
local function HasGuild(unit) return GetGuildInfo(unit) ~= nil end
local function IsBL(name)     return Blacklist()[name] == true end

local function Find(list, name)
    for i, row in ipairs(list) do if row.name == name then return i, row end end
end

local function Publish(ev, ...) if Bus and Bus.Publish then pcall(Bus.Publish, Bus, ev, ...) end end

-- ===== Public API =====
function PM:GetList() return Prospects() end
function PM:GetBlacklist() return Blacklist() end
function PM:IsBlacklisted(name) return IsBL(name) end

function PM:Clear()
    wipe(Prospects())
    Publish("ProspectsUpdated")
end

function PM:Remove(name)
    if not name or name == "" then return end
    local list = Prospects()
    local idx = Find(list, name)
    if idx then table.remove(list, idx) end
    Publish("ProspectsUpdated")
end

function PM:AddToBlacklist(name, reason)
    if not name or name == "" then return end
    local bl = Blacklist()
    bl[name] = { reason = reason or "manual", ts = time() }
    -- ensure it disappears from visible prospects
    self:Remove(name)
    Publish("BlacklistUpdated", name, true)
end

function PM:RemoveFromBlacklist(name)
    if not name or name == "" then return end
    Blacklist()[name] = nil
    Publish("BlacklistUpdated", name, false)
end

--- Add or refresh a unit as a prospect (idempotent on name).
-- @param unit "mouseover" | "target" | "party1" | "raid3" | etc.
-- @param source string tag for telemetry ("mouseover", "target", "group", "scan")
-- @param list optional prospects table to mutate (micro-alloc optimization)
-- @return boolean addedOrUpdated, string "added"|"updated"|reasonForSkip
function PM:TryAddUnit(unit, source, list)
    list = list or Prospects()

    if not IsPlayer(unit) then return false, "not player" end
    if UnitIsEnemy("player", unit) then return false, "enemy" end

    local name = FullName(unit); if not name then return false, "no name" end
    if HasGuild(unit) then return false, "has guild" end
    if IsBL(name) then return false, "blacklisted" end

    local info = PlayerInfo(unit); if not info then return false, "no info" end
    info.source = source or "scan"
    info.seenAt = time()

    local idx, row = Find(list, name)
    if row then
        row.level      = info.level
        row.class      = info.class
        row.classLocal = info.classLocal
        row.zone       = info.zone
        row.guid       = info.guid
        row.online     = info.online
        row.source     = info.source
        row.seenAt     = info.seenAt
        Publish("ProspectsUpdated")
        return true, "updated"
    else
        table.insert(list, info)
        Publish("ProspectsUpdated")
        return true, "added"
    end
end

-- Optional helper to add by explicit name if you already resolved realm.
function PM:TryAddName(name, props)
    if not name or name == "" then return false, "no name" end
    if IsBL(name) then return false, "blacklisted" end
    local list = Prospects()
    local idx = Find(list, name)
    local row = props or { name = name, level = 0, class = "", classLocal = "", zone = "", guid = "", online = true, source = "manual", seenAt = time() }
    if idx then list[idx] = row else table.insert(list, row) end
    Publish("ProspectsUpdated")
    return true, idx and "updated" or "added"
end

return PM
