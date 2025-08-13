-- ProspectsDataProvider.lua - Enterprise Data Access Layer
-- Implements Repository and Provider patterns for clean data abstraction
local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or _G[__p[1]] or {})

local function CreateProspectsDataProvider(scope)
    local self = {}
    local ipairs, GetTime = ipairs, GetTime
    local function getProspectsService()
        if scope and scope.Resolve then
            local ok, svc = pcall(function() return scope:Resolve('ProspectsService') end)
            if ok then return svc end
        end
        if Addon.Get then
            local ok, svc = pcall(function() return Addon.Get('ProspectsService') end)
            if ok then return svc end
        end
        return nil
    end
    local function getRecruiter() return (scope and scope.Resolve and scope:Resolve("Recruiter")) or Addon.Get("Recruiter") end
    local function getEventBus() return (scope and scope.Resolve and scope:Resolve("EventBus")) or Addon.Get("EventBus") end
    local baseLogger -- lazy to avoid early DI resolution during file load
    local function getLogger()
        if baseLogger == nil and Addon and Addon.Get then
            local ok, l = pcall(Addon.Get, "Logger")
            baseLogger = ok and l or false -- cache false to avoid repeated attempts
        end
        local logger = (baseLogger ~= false) and baseLogger or nil
        return logger and logger.ForContext and logger:ForContext("DataProvider.Prospects") or nil
    end
    local cache = { list = {}, byGuid = {}, version = 0, lastUpdate = 0, stats = nil, statsDirty = true }
    local lru
    do
        local cacheSvc = (scope and scope.Resolve and scope:Resolve('InMemoryCache')) or (Addon.Get and Addon.Get('InMemoryCache'))
        if cacheSvc and cacheSvc.New then lru = cacheSvc:New(64) end
    end
    local function logDebug(msg, bag)
        local l = getLogger()
        local fn = l and l.Debug
        if type(fn) == 'function' then if bag ~= nil then fn(l, msg, bag) else fn(l, msg) end end
    end
    local function invalidate(reason)
        cache.version = cache.version + 1
        local now = GetTime()
        cache.lastUpdate = (type(now) == 'number') and math.floor(now) or 0
        cache.statsDirty = true
        logDebug("invalidate v={Version} reason={Reason}",{Version=cache.version,Reason=reason or "?"})
    end
    local function sanitize(p,guid)
        if not p then return nil end
    local realmFn = _G and _G.GetRealmName
        local realm = (p.realm or (realmFn and realmFn()) or "Unknown")
        return { guid=p.guid or guid,name=p.name or "Unknown",realm=realm,level=p.level or 0,classToken=p.classToken,className=p.className or p.classToken or "Unknown",raceName=p.raceName,raceToken=p.raceToken,status=p.status or "New",firstSeen=p.firstSeen or 0,lastSeen=p.lastSeen or 0,seenCount=p.seenCount or 0,sources=p.sources or {},faction=p.faction,sex=p.sex,mapID=p.mapID,declinedAt=p.declinedAt,declinedBy=p.declinedBy }
    end
    local function getDataSource() return getProspectsService() or getRecruiter() end
    local function fullRebuild() cache.list = {}; cache.byGuid = {}; local src=getDataSource(); if src and src.GetAllGuids then local guids=src:GetAllGuids() or {}; for _,guid in ipairs(guids) do local p=(src.GetProspect and src:GetProspect(guid)) or (src.Get and src:Get(guid)); local c=sanitize(p,guid); if c then cache.list[#cache.list+1]=c; cache.byGuid[c.guid]=c end end end invalidate("full"); logDebug("Full rebuild count={Count}",{Count=#cache.list}) end
    local function upsertSingle(guid) local src=getDataSource(); if not src then return fullRebuild() end local raw=(src.GetProspect and src:GetProspect(guid)) or (src.Get and src:Get(guid)); if not raw then return end local ex=cache.byGuid[guid]; if ex then ex.name=raw.name or ex.name; ex.realm=raw.realm or ex.realm; ex.level=raw.level or ex.level; ex.classToken=raw.classToken or ex.classToken; ex.className=raw.className or raw.classToken or ex.className; ex.raceName=raw.raceName or ex.raceName; ex.raceToken=raw.raceToken or ex.raceToken; ex.status=raw.status or ex.status; ex.firstSeen=raw.firstSeen or ex.firstSeen; ex.lastSeen=raw.lastSeen or ex.lastSeen; ex.seenCount=raw.seenCount or ex.seenCount; ex.sources=raw.sources or ex.sources; ex.faction=raw.faction or ex.faction; ex.sex=raw.sex or ex.sex; ex.mapID=raw.mapID or ex.mapID; ex.declinedAt=raw.declinedAt; ex.declinedBy=raw.declinedBy else local c=sanitize(raw,guid); if c then cache.list[#cache.list+1]=c; cache.byGuid[c.guid]=c end end invalidate("upsert") end
    local function removeSingle(guid) if not guid or not cache.byGuid[guid] then return end cache.byGuid[guid]=nil; for i,p in ipairs(cache.list) do if p.guid==guid then local last=cache.list[#cache.list]; cache.list[i]=last; cache.list[#cache.list]=nil; break end end invalidate("remove") end
    local function handleChange(action,guid) if not guid or not action then return fullRebuild() end if action=="queued" or action=="updated" or action=="unblacklisted" or action=="blacklisted" or action=="declined" then upsertSingle(guid) elseif action=="removed" then removeSingle(guid) else fullRebuild() end end
    local function computeStats() local total,active,blacklisted,new,byClass,totalLevels=0,0,0,0,{},0; for _,p in ipairs(cache.list) do total=total+1; if p.status=='Blacklisted' then blacklisted=blacklisted+1 elseif p.status=='New' then new=new+1; active=active+1 else active=active+1 end local cls=p.className or p.classToken or 'Unknown'; byClass[cls]=(byClass[cls] or 0)+1; if p.level and p.level>0 then totalLevels=totalLevels+p.level end end cache.stats={ total=total, active=active, blacklisted=blacklisted, new=new, byClass=byClass, avgLevel= total>0 and (math.floor((totalLevels/total)*10+0.5)/10) or 0 }; cache.statsDirty=false end
    
    local function subscribeToEvents() local bus=getEventBus(); if not bus or not bus.Subscribe then return end bus:Subscribe('Prospects.Changed', function(_,action,guid) handleChange(action,guid) end, { namespace='ProspectsDataProvider' }); logDebug('Subscribed Prospects.Changed') end
    
    -- Public API
    
    -- Initialize the provider
    function self:Initialize() fullRebuild(); subscribeToEvents(); local l=getLogger(); local infoFn = l and l.Info; if type(infoFn)=='function' then infoFn(l,'ProspectsDataProvider initialized') end return self end
    
    -- Get all prospects (returns array of prospect objects)
        function self:GetAll() return cache.list end
    
    -- Get prospects with filtering and sorting (cached if LRU available)
    function self:GetFiltered(filters, sortColumn, sortDescending)
        local prospects = self:GetAll()
        local List = Addon.Get("Collections.List")
        if not List then
            return prospects -- lean fallback (already basic array)
        end
        local result
        local key
    if type(lru) == 'table' and lru.Get then
            local fkey = tostring(filters and filters.status or 'all') .. '|' .. tostring(filters and filters.search or '') .. '|' .. tostring(sortColumn or '') .. '|' .. tostring(sortDescending or false) .. '|' .. tostring(cache.version)
            key = fkey
            local hit = lru:Get(fkey)
            if hit then return hit end
        end
        result = List.from(prospects)
        
        -- Apply status filter
        if filters.status and filters.status ~= 'all' then
            if filters.status == 'active' then
                result = result:Where(function(p) return p.status ~= 'Blacklisted' end)
            elseif filters.status == 'blacklisted' then
                result = result:Where(function(p) return p.status == 'Blacklisted' end)
            elseif filters.status == 'new' then
                result = result:Where(function(p) return p.status == 'New' end)
            end
        end
        
        -- Apply search filter
        if filters.search and filters.search ~= '' then
            local searchLower = filters.search:lower()
            result = result:Where(function(p)
                local name = (p.name or ''):lower()
                local class = (p.className or ''):lower()
                return name:find(searchLower, 1, true) or class:find(searchLower, 1, true)
            end)
        end
        
        -- Apply sorting
        if sortColumn then
            local sortFunc
            if sortColumn == 'name' then
                sortFunc = function(p) return p.name or '' end
            elseif sortColumn == 'level' then
                sortFunc = function(p) return p.level or 0 end
            elseif sortColumn == 'class' then
                sortFunc = function(p) return p.className or '' end
            elseif sortColumn == 'status' then
                sortFunc = function(p) return p.status or '' end
            elseif sortColumn == 'lastSeen' then
                sortFunc = function(p) return p.lastSeen or 0 end
            end
            
            if sortFunc then
                if sortDescending then
                    result = result:OrderByDescending(sortFunc)
                else
                    result = result:OrderBy(sortFunc)
                end
            end
        end
        local arr = result:ToArray()
    if type(lru) == 'table' and lru.Set and key then lru:Set(key, arr) end
        return arr
    end

    -- Paging facade via Infrastructure Persistence DataPager
    function self:GetPage(pageSize, cursor, opts)
        local pager = (scope and scope.Resolve and scope:Resolve('DataPager')) or (Addon.Get and Addon.Get('DataPager'))
        if pager and pager.GetPage then return pager:GetPage('prospects', pageSize, cursor, opts) end
        -- fallback: simple slice of local cache
        local list = self:GetAll()
        local start = (cursor and cursor>0) and cursor or 1
        local out, n = {}, 0
        local i = start
        while list[i] and n < pageSize do n=n+1; out[n]=list[i]; i=i+1 end
        local nextCursor = list[i] and i or nil
        return out, nextCursor
    end
    
    -- Get single prospect by GUID
    function self:GetByGuid(guid)
        if not guid then return nil end
        
        local prospects = self:GetAll()
        for _, prospect in ipairs(prospects) do
            if prospect.guid == guid then
                return prospect
            end
        end
        
        return nil
    end
    
    -- Get cache version (for change detection)
    function self:GetVersion()
        return cache.version
    end
    
    -- Force refresh from data source
        function self:Refresh() fullRebuild(); return self end
    
    -- Get statistics
    function self:GetStats()
        computeStats()
        return cache.stats
    end
    
    -- Action methods (delegate to Recruiter service)
    function self:InviteProspect(guid)
        local f = Addon.Get and Addon.Get("InviteService.Factory")
        local svc = type(f)=="function" and f() or Addon.Get("InviteService")
        if svc and svc.InviteProspect then
            return svc:InviteProspect(guid)
        end
        return false
    end
    
    function self:BlacklistProspect(guid, reason)
        local recruiter = getRecruiter()
        if recruiter and recruiter.Blacklist then
            return recruiter:Blacklist(guid, reason or 'manual')
        end
        return false
    end
    
    function self:UnblacklistProspect(guid)
        local recruiter = getRecruiter()
        if recruiter and recruiter.Unblacklist then
            return recruiter:Unblacklist(guid)
        end
        return false
    end
    
    function self:RemoveProspect(guid)
        local recruiter = getRecruiter()
        if recruiter and recruiter.RemoveProspect then
            return recruiter:RemoveProspect(guid)
        end
        return false
    end
    
    -- Bulk operations
    function self:BulkInvite(guids)
        local count = 0
    local f = Addon.Get and Addon.Get("InviteService.Factory")
    local inviteService = type(f)=="function" and f() or Addon.Get("InviteService")
    if not inviteService or not inviteService.InviteProspect then return count end
        
        for _, guid in ipairs(guids) do
            if inviteService:InviteProspect(guid) then
                count = count + 1
            end
        end
        
        return count
    end
    
    function self:BulkBlacklist(guids, reason)
        local count = 0
        local recruiter = getRecruiter()
        if not recruiter or not recruiter.Blacklist then return count end
        
        for _, guid in ipairs(guids) do
            if recruiter:Blacklist(guid, reason or 'bulk') then
                count = count + 1
            end
        end
        
        return count
    end
    
    function self:BulkRemove(guids)
        local count = 0
        local recruiter = getRecruiter()
        if not recruiter or not recruiter.RemoveProspect then return count end
        
        for _, guid in ipairs(guids) do
            if recruiter:RemoveProspect(guid) then
                count = count + 1
            end
        end
        
        return count
    end
    
    -- Cleanup
    function self:Dispose() local bus=getEventBus(); if type(bus)=='table' and type(bus.UnsubscribeNamespace)=='function' then bus:UnsubscribeNamespace('ProspectsDataProvider') end cache.list,cache.byGuid,cache.stats = {},{},nil; local l=getLogger(); local infoFn=l and l.Info; if type(infoFn)=='function' then infoFn(l,'ProspectsDataProvider disposed') end end
    
    return self
end

local function RegisterProspectsDataProvider()
    if not Addon.provide then
        error("ProspectsDataProvider: Addon.provide not available")
    end
    
    if not (Addon.IsProvided and Addon.IsProvided("ProspectsDataProvider")) then
    Addon.provide("ProspectsDataProvider", function(scope)
            local provider = CreateProspectsDataProvider(scope)
            return provider:Initialize()
    end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'provider' } })
    end
    
    -- Lazy export
    Addon.ProspectsDataProvider = setmetatable({}, {
        __index = function(_, k)
            if Addon._booting then
                error("Cannot access ProspectsDataProvider during boot phase")
            end
            local inst = Addon.Get("ProspectsDataProvider")
            return inst and inst[k] or nil
        end,
        __call = function(_, ...)
            return Addon.Get("ProspectsDataProvider"), ...
        end
    })
end

Addon._RegisterProspectsDataProvider = RegisterProspectsDataProvider

return RegisterProspectsDataProvider
