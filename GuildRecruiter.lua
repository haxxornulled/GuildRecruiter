-- GuildRecruiter.lua — Prospect capture + persistence + queue  
-- TRUE lazy resolution - dependencies resolved on-demand
-- Ensure your .toc has:  ## SavedVariables: GuildRecruiterDB

local ADDON_NAME, Addon = ...

-- ===========================
-- SavedVariables schema
-- ===========================
local DB_VAR = "GuildRecruiterDB"
_G[DB_VAR] = _G[DB_VAR] or {}
local DB = _G[DB_VAR]
local CURRENT_SCHEMA = 1

local function migrateIfNeeded()
  local v = DB.__schema or 0
  if v == 0 then
    DB.prospects = DB.prospects or {}  -- guid -> prospect
    DB.queue     = DB.queue     or {}  -- array of guid (fifo)
    DB.blacklist = DB.blacklist or {}  -- guid -> true | { reason=..., timestamp=... }
    DB.__schema  = 1; v = 1
  end
  -- future migrations here
end

-- ===========================
-- Helpers
-- ===========================
local function now_s() return time() end
local function playerFaction() return UnitFactionGroup("player") end
local function unitGUIDPlayer(unit) local g=UnitGUID(unit); if g and g:find("^Player") then return g end end
local function unitIsUnguilded(unit)
  if not UnitIsPlayer(unit) then return false end
  local g = GetGuildInfo(unit)  -- nil if unguilded or data unavailable for distant units
  return g == nil
end
local function unitFaction(unit) return UnitFactionGroup(unit) end
local function unitBasics(unit)
  local name, realm = UnitName(unit)
  local clsName, clsToken, classID = UnitClass(unit)
  local raceName, raceToken = UnitRace(unit)
  local level = UnitLevel(unit) or 0
  local sex = UnitSex(unit)
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit(unit) or nil
  return {
    name=name, realm=realm,
    classID=classID, classToken=clsToken, className=clsName,
    raceName=raceName, raceToken=raceToken,
    level=level, sex=sex, mapID=mapID,
  }
end

-- Prospect schema
local STATUS = { New="New", Invited="Invited", Rejected="Rejected", Blacklisted="Blacklisted" }

-- ===========================
-- TRUE Lazy Resolution Pattern
-- ===========================
local function CreateRecruiter()
    migrateIfNeeded()
    
    -- Lazy dependency accessors - resolved only when actually used
    local function getLog()
      return Addon.require("Logger"):ForContext("Subsystem","Recruiter")
    end
    
    local function getBus()
      return Addon.require("EventBus")
    end
    
    local function getScheduler()
      return Addon.require("Scheduler")
    end
    
    local List = Addon.List -- Collections are safe to access immediately

    -- Upsert from a unit token if qualifies (unguilded, same faction)
    local function upsertFromUnit(unit, src)
      local guid = unitGUIDPlayer(unit); if not guid then return end
      local pf = playerFaction()
      local uf = unitFaction(unit)
      if uf ~= pf then return end
      if not unitIsUnguilded(unit) then return end
      if DB.blacklist[guid] then return end

      local t = now_s()
      local p = DB.prospects[guid]
      if not p then
        local b = unitBasics(unit)
        p = {
          guid=guid, name=b.name, realm=b.realm, faction=uf,
          classID=b.classID, classToken=b.classToken, className=b.className,
          raceName=b.raceName, raceToken=b.raceToken,
          level=b.level, sex=b.sex,
          firstSeen=t, lastSeen=t, seenCount=1,
          sources={ [src]=true }, status=STATUS.New,
        }
        DB.prospects[guid] = p
        DB.queue[#DB.queue+1] = guid
        getLog():Debug("Queued {Name}-{Realm} ({Class}/{Level})", { Name=b.name, Realm=b.realm or GetRealmName(), Class=b.classToken, Level=b.level })
        getBus():Publish("Recruiter.ProspectQueued", guid, p)
      else
        p.lastSeen = t; p.seenCount = (p.seenCount or 0) + 1
        p.sources = p.sources or {}; p.sources[src]=true
        local b = unitBasics(unit)
        p.level = b.level or p.level
        p.classID = b.classID or p.classID
        p.classToken = b.classToken or p.classToken
        p.className = b.className or p.className
        p.raceName = b.raceName or p.raceName
        p.raceToken = b.raceToken or p.raceToken
        getBus():Publish("Recruiter.ProspectUpdated", guid, p)
      end
    end

    -- Queue ops
    local function dequeueNext()
      while #DB.queue > 0 do
        local guid = table.remove(DB.queue, 1)
        local p = DB.prospects[guid]
        if p and p.status ~= STATUS.Blacklisted then return guid, p end
      end
    end
    
    local function requeue(guid)
      if DB.prospects[guid] and DB.prospects[guid].status ~= STATUS.Blacklisted then
        DB.queue[#DB.queue+1] = guid
      end
    end
    
    local function blacklistGUID(guid, reason)
      DB.blacklist[guid] = DB.blacklist[guid] or { reason = reason or "manual", timestamp = now_s() }
      local p = DB.prospects[guid]; if p then p.status = STATUS.Blacklisted end
      getLog():Info("Blacklisted {GUID} {Reason}", { GUID=guid, Reason=reason or "" })
      getBus():Publish("Recruiter.Blacklisted", guid, reason)
    end

    -- Service implementation
    local self = {}
    local tokens = {}

    function self:Start()
      -- Dependency-free startup - just mark as started
      self._started = true
      
      -- Deferred event registration to avoid circular dependencies
      C_Timer.After(0.2, function()
        if not self._started then return end
        
        local function capture(unit, src)
          if not UnitExists(unit) then return end
          local guid = unitGUIDPlayer(unit)
          local key = "recruit:capture:"..src..":"..(guid or "noguid")
          getScheduler():Throttle(key, 0.10, function() upsertFromUnit(unit, src) end)
        end

        local bus = getBus()
        tokens[#tokens+1] = bus:RegisterWoWEvent("PLAYER_TARGET_CHANGED").token
        tokens[#tokens+1] = bus:Subscribe("PLAYER_TARGET_CHANGED", function() capture("target", "target") end, { namespace="Recruiter" })

        tokens[#tokens+1] = bus:RegisterWoWEvent("UPDATE_MOUSEOVER_UNIT").token
        tokens[#tokens+1] = bus:Subscribe("UPDATE_MOUSEOVER_UNIT", function() capture("mouseover", "mouseover") end, { namespace="Recruiter" })

        tokens[#tokens+1] = bus:RegisterWoWEvent("NAME_PLATE_UNIT_ADDED").token
        tokens[#tokens+1] = bus:Subscribe("NAME_PLATE_UNIT_ADDED", function(_, unit) capture(unit, "nameplate") end, { namespace="Recruiter" })
        
        getLog():Info("Recruiter events registered. Ready to capture prospects.")
      end)
      
      -- Immediate startup log
      local count=0; for _ in pairs(DB.prospects) do count = count + 1 end
      getLog():Info("Recruiter starting. Prospects={Count} Queue={Q}", { Count=count, Q=#DB.queue })
    end

    function self:Stop()
      self._started = false
      for i=1,#tokens do getBus():Unsubscribe(tokens[i]) end
      getBus():UnsubscribeNamespace("Recruiter")
      tokens = {}
    end

    -- Public API
    function self:Dequeue() return dequeueNext() end
    function self:Requeue(guid) return requeue(guid) end
    function self:Blacklist(guid, reason) return blacklistGUID(guid, reason) end

    function self:GetProspect(guid) return DB.prospects[guid] end
    function self:GetAllGuids() 
      return List.from(DB.prospects)
        :Select(function(_, guid) return guid end)
        :OrderBy()
        :ToArray()
    end
    
    function self:GetQueue() 
      return List.from(DB.queue):ToArray()
    end
    
    function self:IsBlacklisted(guid) return DB.blacklist[guid] or false end
    function self:ClearQueue() DB.queue = {} end

    -- === LINQ-powered analytics ===
    function self:GetProspectStats()
      local prospects = List.from(DB.prospects):Select(function(p) return p end)
      
      if prospects:IsEmpty() then
        return { total = 0, byClass = {}, byLevel = {}, avgLevel = 0 }
      end
      
      local byClass = prospects
        :GroupBy(function(p) return p.classToken or "Unknown" end)
        :Select(function(group) return {
          class = group.Key,
          count = group.Count,
          avgLevel = group.Items:Average(function(p) return p.level or 1 end)
        } end)
        :OrderByDescending(function(stat) return stat.count end)
        :ToArray()
      
      local byLevel = prospects
        :GroupBy(function(p) 
          local level = p.level or 1
          if level >= 80 then return "80+"
          elseif level >= 70 then return "70-79"
          elseif level >= 60 then return "60-69"
          else return "<60"
          end
        end)
        :Select(function(group) return {
          range = group.Key,
          count = group.Count
        } end)
        :ToArray()
      
      return {
        total = prospects:Count(),
        byClass = byClass,
        byLevel = byLevel,
        avgLevel = prospects:Average(function(p) return p.level or 1 end),
        topClasses = List.from(byClass):Take(3):ToArray()
      }
    end
    
    function self:GetRecentProspects(hours)
      hours = hours or 24
      local cutoff = now_s() - (hours * 3600)
      
      return List.from(DB.prospects)
        :Where(function(p) return (p.lastSeen or 0) > cutoff end)
        :OrderByDescending(function(p) return p.lastSeen or 0 end)
        :ToArray()
    end
    
    function self:GetBlacklist()
      return DB.blacklist or {}
    end

    function self:Unblacklist(guid)
      if not guid then return end
      if DB.blacklist then DB.blacklist[guid] = nil end
      getBus():Publish("BlacklistUpdated")
    end

    function self:RemoveProspect(guid)
      if not guid then return end
      if DB.prospects then DB.prospects[guid] = nil end
      -- remove any queue entries for this guid
      local nq = {}
      for _,g in ipairs(DB.queue or {}) do if g ~= guid then nq[#nq+1] = g end end
      DB.queue = nq
      getBus():Publish("ProspectsUpdated")
    end

    function self:ClearFromUI(guid)
      -- For now, fully remove the prospect; adjust if you want a soft remove
      self:RemoveProspect(guid)
    end

    return self
end

-- Registration function for Init.lua
local function RegisterRecruiterFactory()
  if not Addon.provide then
    error("Recruiter: Addon.provide not available")
  end
  
  Addon.provide("Recruiter", CreateRecruiter, { lifetime = "SingleInstance" })
  
  -- Lazy export (safe)
  Addon.Recruiter = setmetatable({}, {
    __index = function(_, k) 
      if Addon._booting then
        error("Cannot access Recruiter during boot phase")
      end
      local inst = Addon.require("Recruiter"); return inst[k] 
    end,
    __call = function(_, ...) return Addon.require("Recruiter"), ... end
  })
end

-- Export registration function
Addon._RegisterRecruiter = RegisterRecruiterFactory

return RegisterRecruiterFactory
