-- GuildRecruiter.lua — Prospect capture + persistence + queue  
-- TRUE lazy resolution - dependencies resolved on-demand
-- Ensure your .toc has:  ## SavedVariables: GuildRecruiterDB
--
-- Mutation Contract:
-- Any mutation to prospects or blacklist MUST emit the specific event plus unified:
-- Legacy events (Recruiter.* / *Updated) removed for new development phase.
-- Only Prospects.Changed (action, guid) is emitted plus Recruiter.QueueStats for queue metrics.
-- Actions used: queued, updated, blacklisted, declined, unblacklisted, removed.
-- Data consumers (e.g., ProspectsDataProvider, UI) may rely solely on Prospects.Changed.

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
local function CreateRecruiter(scope)
    migrateIfNeeded()
  -- Runtime optimized queue (Collections.Queue) + index set for fast membership tests
  local runtimeQueue = nil
  local queueIndex = {}
    local function ensureRuntimeQueue()
      if runtimeQueue then return end
      local ok, QueueMod = pcall(function() return Addon.require("Collections.Queue") end)
      if not ok or not QueueMod then return end
      runtimeQueue = QueueMod.new()
      -- seed from current DB.queue (dedup + skip blacklisted)
      local seen = {}
      local rebuilt = {}
      for _,guid in ipairs(DB.queue) do
        if guid and DB.prospects[guid] and not DB.blacklist[guid] and not seen[guid] then
          seen[guid]=true
          runtimeQueue:Enqueue(guid)
          rebuilt[#rebuilt+1]=guid
          queueIndex[guid]=true
        end
      end
      DB.queue = rebuilt
    end
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
    
  -- Resolve core dependencies once (lean path)
  -- Resolve core dependencies via DI scope to ensure proper container usage
  local logger = (scope and scope.Resolve and scope:Resolve("Logger") or Addon.Get("Logger")):ForContext("Subsystem","Recruiter")
  local bus = (scope and scope.Resolve and scope:Resolve("EventBus") or Addon.Get("EventBus"))
  local scheduler = (scope and scope.Resolve and scope:Resolve("Scheduler") or Addon.Get("Scheduler"))

  local function rebuildRuntimeQueue()
        if not runtimeQueue then return end
        runtimeQueue:Clear()
        local seen = {}
        local newOrder = {}
        for _,guid in ipairs(DB.queue) do
          if guid and DB.prospects[guid] and not DB.blacklist[guid] and not seen[guid] then
            seen[guid]=true
            runtimeQueue:Enqueue(guid)
            newOrder[#newOrder+1] = guid
            queueIndex[guid]=true
          end
        end
        DB.queue = newOrder
      end
    
    -- Resolve collections via DI container (explicit) to satisfy requirement
    local function getList()
      local ok, listMod = pcall(Addon.require, "Collections.List")
      if ok and listMod then return listMod end
      -- fallback to previously exported Addon.List
      return Addon.List
    end

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
  queueIndex[guid]=true
        -- Persist immediately
        if Addon.SavedVars and Addon.SavedVars.Set then
          -- Store individual prospect under namespace 'prospects', key is guid
          p._persistedAt = t
          p._lastUpdate = t
          p._version = CURRENT_SCHEMA
          p._sources = nil -- avoid duplicating sources table key naming; main sources stays
          Addon.SavedVars:Set("prospects", guid, p)
        end
  logger:Debug("Queued {Name}-{Realm} ({Class}/{Level})", { Name=b.name, Realm=b.realm or GetRealmName(), Class=b.classToken, Level=b.level })
	bus:Publish("Prospects.Changed", "queued", guid)
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
  bus:Publish("Prospects.Changed", "updated", guid)
      end
    end

    -- Queue ops
    local function dequeueNext()
      ensureRuntimeQueue()
      if runtimeQueue then
        while not runtimeQueue:IsEmpty() do
          local guid = runtimeQueue:Dequeue()
          -- mirror removal in DB.queue (remove first occurrence)
          if queueIndex[guid] then
            queueIndex[guid] = nil
            local newQ = {}
            for _,g in ipairs(DB.queue) do if g ~= guid then newQ[#newQ+1]=g end end
            DB.queue = newQ
          end
          local p = DB.prospects[guid]
          if p and p.status ~= STATUS.Blacklisted then return guid, p end
        end
      else
        while #DB.queue > 0 do
          local guid = table.remove(DB.queue, 1)
          local p = DB.prospects[guid]
          if p and p.status ~= STATUS.Blacklisted then return guid, p end
        end
      end
    end

    local function requeue(guid)
      -- Idempotent requeue with dedupe
      if not guid then return end
      if not DB.prospects[guid] or DB.prospects[guid].status == STATUS.Blacklisted then return end
  if queueIndex[guid] then return end
  DB.queue[#DB.queue+1] = guid; queueIndex[guid]=true
      ensureRuntimeQueue()
      if runtimeQueue then runtimeQueue:Enqueue(guid) end
    end
    
    local function blacklistGUID(guid, reason)
      DB.blacklist[guid] = DB.blacklist[guid] or { reason = reason or "manual", timestamp = now_s() }
      local p = DB.prospects[guid]; if p then p.status = STATUS.Blacklisted end
  logger:Info("Blacklisted {GUID} {Reason}", { GUID=guid, Reason=reason or "" })
  bus:Publish("Prospects.Changed", "blacklisted", guid)
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
          scheduler:Throttle(key, 0.10, function() upsertFromUnit(unit, src) end)
        end

  -- bus already resolved
        tokens[#tokens+1] = bus:RegisterWoWEvent("PLAYER_TARGET_CHANGED").token
        tokens[#tokens+1] = bus:Subscribe("PLAYER_TARGET_CHANGED", function() capture("target", "target") end, { namespace="Recruiter" })

        tokens[#tokens+1] = bus:RegisterWoWEvent("UPDATE_MOUSEOVER_UNIT").token
        tokens[#tokens+1] = bus:Subscribe("UPDATE_MOUSEOVER_UNIT", function() capture("mouseover", "mouseover") end, { namespace="Recruiter" })

        tokens[#tokens+1] = bus:RegisterWoWEvent("NAME_PLATE_UNIT_ADDED").token
        tokens[#tokens+1] = bus:Subscribe("NAME_PLATE_UNIT_ADDED", function(_, unit) capture(unit, "nameplate") end, { namespace="Recruiter" })
        
  logger:Info("Recruiter events registered. Ready to capture prospects.")
      end)
      
      -- Immediate startup log
      local count=0; for _ in pairs(DB.prospects) do count = count + 1 end
  logger:Info("Recruiter starting. Prospects={Count} Queue={Q}", { Count=count, Q=#DB.queue })
      -- Auto-prune schedule (size based)
      pcall(function()
  local cfg = Addon.require and Addon.require("IConfiguration")
        if cfg and cfg.Get then
          local function schedulePrune()
            if not self._started then return end
            local pMax = tonumber(cfg:Get("prospectsMax", 0)) or 0
            local bMax = tonumber(cfg:Get("blacklistMax", 0)) or 0
            if pMax > 0 then self:PruneProspects(pMax) end
            if bMax > 0 then self:PruneBlacklist(bMax) end
            local iv = tonumber(cfg:Get("autoPruneInterval", 1800)) or 1800
            scheduler:After(math.max(60, iv), schedulePrune, { namespace = "Recruiter" })
          end
          schedulePrune()
        end
      end)
      -- Listen for invite declines to update prospect status (InviteService already handles blacklisting)
  -- bus already resolved
      if bus and bus.Subscribe then
        self._declineTok = bus:Subscribe("InviteService.InviteDeclined", function(_, guid, who)
          if guid and DB.prospects[guid] then
            -- Update prospect status but DON'T remove from prospects - keep the data
            local p = DB.prospects[guid]
            if p then
              local autoBL = true
              pcall(function()
                local cfg = Addon.require and Addon.require("IConfiguration")
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
                rebuildRuntimeQueue()
              else
                -- Keep status as-is (New/Invited). Optionally tag declined flag
                if p.status == STATUS.New then p.status = STATUS.New end
              end
              if Addon.SavedVars and Addon.SavedVars.Set then
                p._lastUpdate = now_s()
                Addon.SavedVars:Set("prospects", guid, p)
              end
              bus:Publish("Prospects.Changed", "declined", guid)
            end
            
            local showToast = false
            pcall(function()
              local cfg = Addon.require and Addon.require("IConfiguration")
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
            logger:Info("Prospect declined invite {GUID} {Player} - status updated", { GUID=guid, Player=who or "?" })
          end
        end, { namespace = "Recruiter" })
      end
        local function triggerStats()
          pcall(function()
            -- scheduler & bus already resolved
            scheduler:Debounce("recruiter.queueStats", 0.5, function()
              local stats = self:QueueStats()
              bus:Publish("Recruiter.QueueStats", stats)
            end)
          end)
        end
        triggerStats()
    end

    function self:Stop()
      self._started = false
    for i=1,#tokens do bus:Unsubscribe(tokens[i]) end
    bus:UnsubscribeNamespace("Recruiter")
  if self._declineTok then bus:Unsubscribe(self._declineTok); self._declineTok = nil end
      tokens = {}
    end

    -- Public API
    function self:Dequeue() return dequeueNext() end
    function self:Requeue(guid)
      -- prevent duplicate queue entries
      if not guid then return end
      for _, qg in ipairs(DB.queue) do if qg == guid then return end end
      return requeue(guid)
    end
    function self:Blacklist(guid, reason)
      local pm = (Addon.Get and Addon.Get('IProspectManager')) or (Addon.require and Addon.require('ProspectsManager'))
      if pm and pm.Blacklist then return pm:Blacklist(guid, reason) end
      return blacklistGUID(guid, reason)
    end

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
  ensureRuntimeQueue()
  if runtimeQueue then
        local arr = {}
        for guid in runtimeQueue:Iter() do arr[#arr+1]=guid end
        return arr
      end
      local List = getList()
      return (List and List.from(DB.queue):ToArray()) or DB.queue
    end
    
    function self:IsBlacklisted(guid) return DB.blacklist[guid] or false end
  function self:ClearQueue() DB.queue = {}; queueIndex = {}; if runtimeQueue then runtimeQueue:Clear() end end
    function self:RepairQueue()
      rebuildRuntimeQueue(); return #DB.queue
    end
    function self:QueueStats()
      local dupes=0; local seen={}
      for _,g in ipairs(DB.queue) do if seen[g] then dupes=dupes+1 else seen[g]=true end end
      return { total=#DB.queue, duplicates=dupes, runtime=(runtimeQueue and runtimeQueue:Count()) or #DB.queue }
    end

    -- Prune helpers (size-based for prospects/blacklist) using List for ordering by lastSeen / timestamp
    function self:PruneProspects(max)
      local pm = (Addon.Get and Addon.Get('IProspectManager')) or (Addon.require and Addon.require('ProspectsManager'))
      if pm and pm.PruneProspects then return pm:PruneProspects(max) end
      max = tonumber(max); if not max or max < 0 then return 0 end
      local items = {}
      for guid,p in pairs(DB.prospects) do if p and p.lastSeen then items[#items+1] = p end end
      table.sort(items, function(a,b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
      local keep = {}
      for i,p in ipairs(items) do if i <= max then keep[p.guid]=true end end
      local removed=0
      local sv = Addon.SavedVars or (pcall(Addon.require, "SavedVarsService") and Addon.require("SavedVarsService"))
      for guid,_ in pairs(DB.prospects) do
        if not keep[guid] then
          DB.prospects[guid]=nil; removed=removed+1
          -- mark removal in saved vars so it does not rehydrate next session
          if sv and sv.Set then pcall(sv.Set, sv, "prospects", guid, false) end
        end
      end
      -- Rebuild queue excluding removed & dedupe
      local seen = {}
      local newQ = {}
      queueIndex = {}
      for _,guid in ipairs(DB.queue) do
        if DB.prospects[guid] and not seen[guid] then
          seen[guid]=true; newQ[#newQ+1]=guid; queueIndex[guid]=true
        end
      end
  DB.queue = newQ; rebuildRuntimeQueue()
      return removed
    end
    function self:PruneBlacklist(max)
      local pm = (Addon.Get and Addon.Get('IProspectManager')) or (Addon.require and Addon.require('ProspectsManager'))
      if pm and pm.PruneBlacklist then return pm:PruneBlacklist(max) end
      max = tonumber(max); if not max or max < 0 then return 0 end
      local entries = {}
      for guid,entry in pairs(DB.blacklist) do entries[#entries+1] = { guid=guid, ts = (type(entry)=="table" and entry.timestamp) or 0 } end
      table.sort(entries, function(a,b) return (a.ts or 0) > (b.ts or 0) end)
      local keep = {}
      for i,e in ipairs(entries) do if i <= max then keep[e.guid]=true end end
      local removed=0
      local sv = Addon.SavedVars or (pcall(Addon.require, "SavedVarsService") and Addon.require("SavedVarsService"))
      for guid,_ in pairs(DB.blacklist) do
        if not keep[guid] then
          DB.blacklist[guid]=nil; removed=removed+1
          if sv and sv.Set then pcall(sv.Set, sv, "blacklist", guid, false) end
        end
      end
      return removed
    end

    -- === LINQ-powered analytics ===
    function self:GetProspectStats()
  -- Unified analytics path: resolve the read model interface only.
  local provider = Addon.Get and Addon.Get('IProspectsReadModel')
      if provider and provider.GetStats then
        local st = provider:GetStats()
        -- Map provider schema to legacy fields used by UI summary (topClasses expected)
        if st and not st.topClasses and st.byClass then
          local top = {}
          -- build topClasses with { class=, count= } fields
          for cls,count in pairs(st.byClass) do top[#top+1] = { class = cls, count = count } end
          table.sort(top, function(a,b) return a.count > b.count end)
          st.topClasses = top
        end
        return st
      end
      -- Fallback: minimal stats if provider not available yet.
      local count=0; local totalLevel=0; local byClass={}
      for _,p in pairs(DB.prospects) do
        count = count + 1
        if p.level then totalLevel = totalLevel + (p.level or 0) end
        local cls = p.classToken or p.className or "Unknown"
        byClass[cls] = (byClass[cls] or 0) + 1
      end
      local avg = count>0 and (totalLevel / count) or 0
      local top = {}
      for k,v in pairs(byClass) do top[#top+1] = { class=k, count=v } end
      table.sort(top, function(a,b) return a.count > b.count end)
      return { total=count, avgLevel=avg, byClass=byClass, topClasses=top }
    end
    
    function self:GetRecentProspects(hours)
      hours = hours or 24
      local cutoff = now_s() - (hours * 3600)
      local List = getList()
      if not List then return {} end
      return List.from(DB.prospects)
          :Where(function(p) return (p.lastSeen or 0) > cutoff end)
          :OrderByDescending(function(p) return p.lastSeen or 0 end)
          :ToArray()
    end
    
    function self:GetBlacklist()
      local pm = (Addon.Get and Addon.Get('IProspectManager')) or (Addon.require and Addon.require('ProspectsManager'))
      if pm and pm.GetBlacklist then return pm:GetBlacklist() end
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
      local pm = (Addon.Get and Addon.Get('IProspectManager')) or (Addon.require and Addon.require('ProspectsManager'))
      if pm and pm.Unblacklist then return pm:Unblacklist(guid) end
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
  local found=false; for _,qguid in ipairs(DB.queue) do if qguid==guid then found=true break end end
  if not found then DB.queue[#DB.queue+1] = guid; ensureRuntimeQueue(); if runtimeQueue then runtimeQueue:Enqueue(guid) end end
        
        -- Persist changes
        if Addon.SavedVars and Addon.SavedVars.Set then
          Addon.SavedVars:Set("prospects", guid, prospect)
          Addon.SavedVars:Set("blacklist", guid, false)
        end
        
  bus:Publish("Prospects.Changed", "unblacklisted", guid)
      end
      
  logger:Info("Unblacklisted {GUID}", { GUID=guid })
    end

    function self:RemoveProspect(guid)
      if not guid then return end
      if DB.prospects then DB.prospects[guid] = nil end
      -- remove any queue entries for this guid
      local nq = {}
      for _,g in ipairs(DB.queue or {}) do if g ~= guid then nq[#nq+1] = g end end
      DB.queue = nq
  bus:Publish("Prospects.Changed", "removed", guid)
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
  
  if not (Addon.IsProvided and Addon.IsProvided("Recruiter")) then
  Addon.provide("Recruiter", function(scope) return CreateRecruiter(scope) end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'capture/queue' } })
  end
  
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
