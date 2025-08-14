-- QueueService.lua -- Extracted from legacy GuildRecruiter queue logic
local ADDON_NAME, Addon = ...

local QueueService = {}
local Status = (Addon and Addon.ResolveOptional and Addon.ResolveOptional('ProspectStatus')) or { Blacklisted='Blacklisted' }

local function root()
    local sv = (Addon.Get and Addon.Get('SavedVarsService')) or (Addon.Peek and Addon.Peek('SavedVarsService'))
    if sv and sv.GetNamespace then return sv:GetNamespace('', { prospects = {}, queue = {}, blacklist = {} }) end
    _G.GuildRecruiterDB = _G.GuildRecruiterDB or { prospects = {}, queue = {}, blacklist = {} }
    return _G.GuildRecruiterDB
end

local function bus() return (Addon.Get and Addon.Get('EventBus')) or (Addon.Peek and Addon.Peek('EventBus')) end
local function logger() local l=(Addon.Get and Addon.Get('Logger')) or (Addon.Peek and Addon.Peek('Logger')) return l and l:ForContext('Subsystem','QueueService') or { Info=function() end, Debug=function() end } end

-- forward declare for use in _ensureRuntime
local function publishStats(self) end

-- Runtime queue (Collections.Queue) + index set
function QueueService:_ensureRuntime()
    if self._queueObj then return end
    local ok, Q = pcall(Addon.require, 'Collections.Queue')
    if not ok or not Q then return end
    self._queueObj = Q.new()
    self._index = self._index or {}
    local db = root()
    local rebuilt, seen = {}, {}
    for _, guid in ipairs(db.queue or {}) do
        local p = db.prospects[guid]
    if guid and p and p.status ~= Status.Blacklisted and not db.blacklist[guid] and not seen[guid] then
            seen[guid] = true
            self._queueObj:Enqueue(guid)
            rebuilt[#rebuilt+1] = guid
            self._index[guid] = true
        end
    end
    db.queue = rebuilt
    publishStats(self)
end

publishStats = function(self)
    local b = bus(); if not b or not b.Publish then return end
    local stats = self:QueueStats()
    -- New canonical event name
    b:Publish('QueueService.Stats', stats)
    -- Backwards compat (UI may still listen temporarily)
    b:Publish('Recruiter.QueueStats', stats)
end

function QueueService:Dequeue()
    self:_ensureRuntime(); local db=root()
    if self._queueObj then
        while not self._queueObj:IsEmpty() do
            local guid = self._queueObj:Dequeue()
            if self._index and self._index[guid] then
                self._index[guid] = nil
                local newQ = {}
                for _,g in ipairs(db.queue) do if g ~= guid then newQ[#newQ+1]=g end end
                db.queue = newQ
            end
            local p = db.prospects[guid]
            if p and p.status ~= Status.Blacklisted then publishStats(self); return guid, p end
        end
    else
        while #db.queue > 0 do
            local guid = table.remove(db.queue,1)
            local p = db.prospects[guid]
            if p and p.status ~= Status.Blacklisted then publishStats(self); return guid, p end
        end
    end
end

function QueueService:Requeue(guid)
    if not guid then return end
    local db=root(); local p=db.prospects[guid]; if not p or p.status==Status.Blacklisted then return end
    self._index = self._index or {}
    if self._index[guid] then return end
    db.queue[#db.queue+1]=guid; self._index[guid]=true
    self:_ensureRuntime(); if self._queueObj then self._queueObj:Enqueue(guid) end
    publishStats(self)
    local b=bus(); if _G.GR_TEST_MODE and b and b.Publish then b:Publish('QueueService.Debug','requeue',guid,#(db.queue or {})) end
    return true
end

function QueueService:ClearQueue()
    local db=root(); db.queue = {}; self._index = {};
    if self._queueObj then self._queueObj:Clear() end
    publishStats(self)
end

function QueueService:RepairQueue()
    self._queueObj=nil; self._index=nil; self:_ensureRuntime(); return #(root().queue or {})
end

function QueueService:GetQueue()
    self:_ensureRuntime(); local db=root()
    if self._queueObj then local arr={}; for guid in self._queueObj:Iter() do arr[#arr+1]=guid end; return arr end
    return db.queue
end

function QueueService:QueueStats()
    local db=root(); local dupes, seen = 0, {}
    for _,g in ipairs(db.queue or {}) do if seen[g] then dupes=dupes+1 else seen[g]=true end end
    return { total = #(db.queue or {}), duplicates = dupes, runtime = (self._queueObj and self._queueObj:Count()) or #(db.queue or {}) }
end

-- Test-only helper: fully reset runtime + persisted queue state
function QueueService:ResetState()
    if not _G.GR_TEST_MODE then return end
    local db = root(); db.queue = {}
    self._queueObj = nil; self._index = nil
    publishStats(self)
end

local function RegisterQueueService()
    if not Addon.provide then return end
    if not (Addon.IsProvided and Addon.IsProvided('QueueService')) then
        Addon.provide('QueueService', function() return setmetatable({}, { __index = QueueService }) end, { lifetime='SingleInstance', meta={ layer='Infrastructure', area='queue' } })
    end
end

RegisterQueueService(); Addon._RegisterQueueService = RegisterQueueService

return QueueService
