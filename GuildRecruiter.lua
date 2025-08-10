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
    -- Rehydrate from SavedVarsService (prospects & blacklist) if available
    if Addon.SavedVars and Addon.SavedVars.GetNamespace then
      local svPros = Addon.SavedVars:GetNamespace("prospects")
      if svPros and type(svPros) == "table" then
        for guid, p in pairs(svPros) do
          if type(p)=="table" and p.guid then
            -- Only add if not already present in core DB
            if not DB.prospects[guid] then
              DB.prospects[guid] = p
              -- ensure queue membership if new and not blacklisted
              if not DB.blacklist[guid] then
                DB.queue[#DB.queue+1] = guid
              end
            end
          end
        end
      end
      local svBL = Addon.SavedVars:GetNamespace("blacklist")
      if svBL and type(svBL) == "table" then
        for guid, entry in pairs(svBL) do
          if entry == false then
            -- explicit removed marker; ensure not in blacklist
            DB.blacklist[guid] = nil
          elseif type(entry) == "table" then
            DB.blacklist[guid] = entry
            local p = DB.prospects[guid]; if p then p.status = STATUS.Blacklisted end
          end
        end
      end
    end
    
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
        -- Persist immediately
        if Addon.SavedVars and Addon.SavedVars.Set then
          -- Store individual prospect under namespace 'prospects', key is guid
          p._persistedAt = t
          p._lastUpdate = t
          p._version = CURRENT_SCHEMA
          p._sources = nil -- avoid duplicating sources table key naming; main sources stays
          Addon.SavedVars:Set("prospects", guid, p)
        end
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
        if Addon.SavedVars and Addon.SavedVars.Set then
          p._lastUpdate = t
          Addon.SavedVars:Set("prospects", guid, p)
        end
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
      if Addon.SavedVars and Addon.SavedVars.Set then
        local entry = DB.blacklist[guid]
        entry._persistedAt = entry._persistedAt or now_s()
        entry._lastUpdate = now_s()
        Addon.SavedVars:Set("blacklist", guid, entry)
      end
    end

    -- Service implementation
    local self = {}
    local tokens = {}

    function self:Start()
      -- Dependency-free startup - just mark as started
      self._started = true
      
  -- Deferred event registration (delay reduced to 0 to minimize race window while still deferring)
  C_Timer.After(0, function()
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
      -- Listen for invite declines to update prospect status (InviteService already handles blacklisting)
      local bus = getBus()
      if bus and bus.Subscribe then
        self._declineTok = bus:Subscribe("InviteService.InviteDeclined", function(_, guid, who)
          if guid and DB.prospects[guid] then
            -- Update prospect status but DON'T remove from prospects - keep the data
            local p = DB.prospects[guid]
            if p then
              local autoBL = true
              pcall(function()
                local cfg = Addon.require and Addon.require("Config")
                if cfg and cfg.Get then autoBL = cfg:Get("autoBlacklistDeclines", true) end
              end)
              p.declinedAt = now_s()
              p.declinedBy = who
              if autoBL then
                p.status = STATUS.Blacklisted
                -- Remove from queue since they're blacklisted
                local newQueue = {}
                for _, qguid in ipairs(DB.queue) do if qguid ~= guid then newQueue[#newQueue+1] = qguid end end
                DB.queue = newQueue
              else
                -- Keep status as-is (New/Invited). Optionally tag declined flag
                if p.status == STATUS.New then p.status = STATUS.New end
              end
              if Addon.SavedVars and Addon.SavedVars.Set then
                p._lastUpdate = now_s()
                Addon.SavedVars:Set("prospects", guid, p)
              end
              getBus():Publish("Recruiter.ProspectUpdated", guid, p)
            end
            
            local showToast = false
            pcall(function()
              local cfg = Addon.require and Addon.require("Config")
              if cfg and cfg.Get then showToast = cfg:Get("toastOnDecline", true) end
            end)
            local msg
            if p and p.status == STATUS.Blacklisted then
              msg = (who and (who.." declined guild invite - moved to blacklist") or "Invite declined - moved to blacklist")
            else
              msg = (who and (who.." declined guild invite") or "Invite declined")
            end
            if showToast and DEFAULT_CHAT_FRAME then
              DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[GR]|r "..msg)
            end
            getLog():Info("Prospect declined invite {GUID} {Player} - status updated", { GUID=guid, Player=who or "?" })
          end
        end, { namespace = "Recruiter" })
      end
    end

    function self:Stop()
      self._started = false
      for i=1,#tokens do getBus():Unsubscribe(tokens[i]) end
      getBus():UnsubscribeNamespace("Recruiter")
  if self._declineTok then getBus():Unsubscribe(self._declineTok); self._declineTok = nil end
      tokens = {}
    end

    -- Public API
    function self:Dequeue() return dequeueNext() end
    function self:Requeue(guid) return requeue(guid) end
    function self:Blacklist(guid, reason) return blacklistGUID(guid, reason) end

    function self:GetProspect(guid) return DB.prospects[guid] end
    -- Return sorted array of prospect GUID keys (fix: previously returned numeric indices)
    function self:GetAllGuids()
      local keys = {}
      for guid, _ in pairs(DB.prospects) do
        keys[#keys+1] = guid
      end
      table.sort(keys)
      return keys
    end
    
    function self:GetQueue() 
      return List.from(DB.queue):ToArray()
    end
    
    function self:IsBlacklisted(guid) return DB.blacklist[guid] or false end
    function self:ClearQueue() DB.queue = {} end

    -- Prune helpers (size-based for prospects/blacklist) using List for ordering by lastSeen / timestamp
    function self:PruneProspects(max)
      max = tonumber(max); if not max or max < 0 then return 0 end
      local items = {}
      for guid,p in pairs(DB.prospects) do if p and p.lastSeen then items[#items+1] = p end end
      table.sort(items, function(a,b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
      local keep = {}
      for i,p in ipairs(items) do if i <= max then keep[p.guid]=true end end
      local removed=0
      for guid,_ in pairs(DB.prospects) do if not keep[guid] then DB.prospects[guid]=nil; removed=removed+1 end end
      -- Rebuild queue excluding removed
      local newQ = {}
      for _,guid in ipairs(DB.queue) do if DB.prospects[guid] then newQ[#newQ+1]=guid end end
      DB.queue = newQ
      return removed
    end
    function self:PruneBlacklist(max)
      max = tonumber(max); if not max or max < 0 then return 0 end
      local entries = {}
      for guid,entry in pairs(DB.blacklist) do entries[#entries+1] = { guid=guid, ts = (type(entry)=="table" and entry.timestamp) or 0 } end
      table.sort(entries, function(a,b) return (a.ts or 0) > (b.ts or 0) end)
      local keep = {}
      for i,e in ipairs(entries) do if i <= max then keep[e.guid]=true end end
      local removed=0
      for guid,_ in pairs(DB.blacklist) do if not keep[guid] then DB.blacklist[guid]=nil; removed=removed+1 end end
      return removed
    end

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

    -- Return sorted array of blacklist GUID keys (mirrors GetAllGuids for prospects)
    function self:GetBlacklistGuids()
      local bl = DB.blacklist; if not bl then return {} end
      local keys = {}
      for guid, _ in pairs(bl) do keys[#keys+1] = guid end
      table.sort(keys)
      return keys
    end

    function self:Unblacklist(guid)
      if not guid then return end
      if DB.blacklist then DB.blacklist[guid] = nil end
      
      -- Update prospect status back to active and clear decline info
      local prospect = DB.prospects[guid]
      if prospect then
        prospect.status = "New"
        prospect.declinedAt = nil
        prospect.declinedBy = nil
        prospect._lastUpdate = now_s()
        
        -- Re-add to queue if not already there
        local inQueue = false
        for _, qguid in ipairs(DB.queue) do
          if qguid == guid then
            inQueue = true
            break
          end
        end
        if not inQueue then
          DB.queue[#DB.queue+1] = guid
        end
        
        -- Persist changes
        if Addon.SavedVars and Addon.SavedVars.Set then
          Addon.SavedVars:Set("prospects", guid, prospect)
          Addon.SavedVars:Set("blacklist", guid, false)
        end
        
        getBus():Publish("Recruiter.ProspectUpdated", guid, prospect)
      end
      
      getBus():Publish("BlacklistUpdated")
      getLog():Info("Unblacklisted {GUID}", { GUID=guid })
    end

    function self:RemoveProspect(guid)
      if not guid then return end
      if DB.prospects then DB.prospects[guid] = nil end
      -- remove any queue entries for this guid
      local nq = {}
      for _,g in ipairs(DB.queue or {}) do if g ~= guid then nq[#nq+1] = g end end
      DB.queue = nq
      getBus():Publish("ProspectsUpdated")
      if Addon.SavedVars and Addon.SavedVars.Set then
        -- Mark removal in SavedVars namespace so it is not rehydrated next load
        Addon.SavedVars:Set("prospects", guid, false)
      end
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
