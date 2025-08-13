-- Services/SavedVarsService.lua -- simple namespaced SavedVariables helper
-- Provides a DI-friendly wrapper to Get/Set/reset namespaced data blobs within the addon SavedVariables root.
-- NOTE: The .toc must declare ## SavedVariables: GuildRecruiterDB for persistence (already present).

local Addon = select(2, ...)

local ROOT_NAME = "GuildRecruiterDB" -- align with existing config / recruiter usage
_G[ROOT_NAME] = _G[ROOT_NAME] or {}

local function now_s()
  local tf = rawget(_G, "time") or function() return 0 end
  return tf()
end

local function ensureNamespace(root, ns)
  if type(ns) ~= "string" or ns == "" then return root end
  root[ns] = root[ns] or {}
  return root[ns]
end

local function shallow_copy(t)
  if type(t) ~= "table" then return t end
  local r = {}; for k,v in pairs(t) do r[k] = v end; return r
end

local function deep_merge(dst, src)
  if type(src) ~= "table" then return dst end
  for k,v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      deep_merge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function CreateSavedVarsService()
  local self = {}
  local root = _G[ROOT_NAME]
  local cache = nil
  local dirty = false

  local function cloneDeep(t)
    if type(t) ~= "table" then return t end
    local r = {}; for k,v in pairs(t) do r[k] = cloneDeep(v) end; return r
  end

  local function loadCache()
    if cache ~= nil then return end
    cache = cloneDeep(root or {})
    dirty = false
  end

  local function syncToRoot()
    if not cache then return end
    -- In-place sync to preserve the SavedVariables table identity
    for k in pairs(root) do root[k] = nil end
    local function assign(dst, src)
      for k,v in pairs(src) do
        if type(v) == "table" then
          dst[k] = dst[k] or {}
          assign(dst[k], v)
        else
          dst[k] = v
        end
      end
    end
    assign(root, cache)
    dirty = false
  end

  local function getRoot()
    loadCache(); cache = cache or {}; return cache
  end

  -- Retrieve entire namespace table (creates if missing). If defaults provided, they are merged (missing keys only)
  function self:GetNamespace(ns, defaults)
    local tbl = ensureNamespace(getRoot(), ns)
    if defaults and type(defaults) == "table" then
      deep_merge(tbl, defaults)
      dirty = true
    end
    return tbl
  end

  -- Get a single value inside a namespace.
  function self:Get(ns, key, fallback)
    local tbl = ensureNamespace(getRoot(), ns)
    local v = tbl[key]
    if v == nil then return fallback end
    return v
  end

  -- Set a value inside a namespace.
  function self:Set(ns, key, value)
    local tbl = ensureNamespace(getRoot(), ns)
    tbl[key] = value
    dirty = true
    return true
  end

  -- Bulk assign (table of key->value) into namespace.
  function self:Assign(ns, kv)
    if type(kv) ~= "table" then return false, "kv not table" end
    local tbl = ensureNamespace(getRoot(), ns)
    for k,v in pairs(kv) do tbl[k] = v end
    dirty = true
    return true
  end

  -- Reset a namespace (optionally preserving provided keys)
  function self:Reset(ns, preserveKeys)
    local old = ensureNamespace(getRoot(), ns)
    local keep = {}
    if type(preserveKeys) == "table" then
      for _,k in ipairs(preserveKeys) do keep[k] = old[k] end
    end
    getRoot()[ns] = {}
    for k,v in pairs(keep) do getRoot()[ns][k] = v end
    dirty = true
    return true
  end

  -- Export snapshot (deep copy) of namespace data
  function self:Export(ns)
    local function clone(t)
      if type(t) ~= "table" then return t end
      local r = {}; for k,v in pairs(t) do r[k] = clone(v) end; return r
    end
    return clone(ensureNamespace(getRoot(), ns))
  end

  -- History utility: append an entry to a list under ns.key (auto timestamps). Creates list if missing.
  function self:Append(ns, key, value)
    local tbl = ensureNamespace(getRoot(), ns)
    tbl[key] = tbl[key] or {}
    table.insert(tbl[key], { at = now_s(), value = value })
    dirty = true
    return #tbl[key]
  end

  -- Prune list under ns.key to max items (oldest first) if over limit.
  function self:Prune(ns, key, max)
    local tbl = ensureNamespace(getRoot(), ns)
    local list = tbl[key]
    if type(list) ~= "table" or max <= 0 then return 0 end
    while #list > max do table.remove(list, 1) end
    dirty = true
    return #list
  end

  -- Advanced prune with filters: opts = { max=number, minTimestamp=epochSeconds, match=substr, drop=substr }
  -- Order of operations: age filter -> match/drop filters -> max trimming (keep newest items assuming chronological order)
  function self:PruneFiltered(ns, key, opts)
    opts = opts or {}
    local tbl = ensureNamespace(getRoot(), ns)
    local list = tbl[key]
    if type(list) ~= "table" then return { before=0, after=0, removed=0, reason="not-table" } end
    local before = #list
    if before == 0 then return { before=0, after=0, removed=0 } end
  local minTs = tonumber(opts.minTimestamp)
  ---@type any
  local matchSub = opts.match
  ---@type any
  local dropSub  = opts.drop
    local filtered = {}
    for i=1,#list do
      local e = list[i]
      local keep = true
      if minTs and minTs > 0 then
        local t = (type(e)=="table" and (e.at or e.timestamp)) or 0
        if t < minTs then keep = false end
      end
      if keep and matchSub then
        local s = tostring(type(e)=="table" and (e.value or e.msg or e.message or e.guid) or e)
        if not s:find(matchSub, 1, true) then keep = false end
      end
      if keep and dropSub then
        local s = tostring(type(e)=="table" and (e.value or e.msg or e.message or e.guid) or e)
        if s:find(dropSub, 1, true) then keep = false end
      end
      if keep then filtered[#filtered+1] = e end
    end
    -- Trim to max (keep newest => assume chronological order; keep tail)
    local max = tonumber(opts.max)
    if max and max >= 0 and #filtered > max then
      local start = #filtered - max + 1
      local trimmed = {}
      for i=start,#filtered do trimmed[#trimmed+1] = filtered[i] end
      filtered = trimmed
    end
    tbl[key] = filtered
    local after = #filtered
    dirty = true
    return { before=before, after=after, removed=before-after }
  end

  -- Sync cache into SavedVariables root table
  function self:Sync()
    loadCache(); syncToRoot(); return not dirty
  end

  -- Reload cache from SavedVariables root (discarding unsynced changes)
  function self:Reload()
    cache = nil; dirty = false; loadCache(); return true
  end

  -- Initialize cache immediately on first creation
  loadCache()

  -- Hook WoW reload/logout to persist cache, without building DI container during boot
  local function tryHookBus()
    local Bus = (Addon.Get and Addon.Get("EventBus")) or (Addon.Peek and Addon.Peek("EventBus"))
    if Bus and Bus.RegisterWoWEvent and Bus.Subscribe then
      for _, ev in ipairs({ "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT" }) do
        Bus:RegisterWoWEvent(ev)
        Bus:Subscribe(ev, function()
          pcall(syncToRoot)
        end, { namespace = "SavedVarsService" })
      end
      return true
    end
    return false
  end
  if not tryHookBus() then
    local After = rawget(_G, 'C_Timer') and _G.C_Timer.After
    if type(After) == 'function' then
      local retries = 0
      local function retry()
        if tryHookBus() then return end
        retries = retries + 1
        if retries < 10 then After(0.10, retry) end
      end
      After(0, retry)
    end
  end

  return self
end

local function RegisterSavedVarsService()
  if not Addon.provide then error("SavedVarsService: Addon.provide not available") end
  if not (Addon.IsProvided and Addon.IsProvided("SavedVarsService")) then
    Addon.provide("SavedVarsService", CreateSavedVarsService, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'persistence' } })
  end
  Addon.SavedVars = setmetatable({}, {
    __index = function(_, k)
      if Addon._booting then error("Cannot access SavedVarsService during boot phase") end
      local inst = (Addon.Get and Addon.Get("SavedVarsService")) or Addon.require("SavedVarsService"); return inst and inst[k] or nil
    end,
    __call = function(_, ...)
      if Addon._booting then error("Cannot access SavedVarsService during boot phase") end
      local inst = (Addon.Get and Addon.Get("SavedVarsService")) or Addon.require("SavedVarsService"); return inst, ...
    end
  })
end

Addon._RegisterSavedVarsService = RegisterSavedVarsService
return RegisterSavedVarsService
