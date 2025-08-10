-- Services/SavedVarsService.lua -- simple namespaced SavedVariables helper
-- Provides a DI-friendly wrapper to Get/Set/reset namespaced data blobs within the addon SavedVariables root.
-- NOTE: The .toc must declare ## SavedVariables: GuildRecruiterDB for persistence (already present).

local ADDON_NAME, Addon = ...

local ROOT_NAME = "GuildRecruiterDB" -- align with existing config / recruiter usage
_G[ROOT_NAME] = _G[ROOT_NAME] or {}

local function now_s() return time() end

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

  -- Retrieve entire namespace table (creates if missing). If defaults provided, they are merged (missing keys only)
  function self:GetNamespace(ns, defaults)
    local tbl = ensureNamespace(root, ns)
    if defaults and type(defaults) == "table" then
      deep_merge(tbl, defaults)
    end
    return tbl
  end

  -- Get a single value inside a namespace.
  function self:Get(ns, key, fallback)
    local tbl = ensureNamespace(root, ns)
    local v = tbl[key]
    if v == nil then return fallback end
    return v
  end

  -- Set a value inside a namespace.
  function self:Set(ns, key, value)
    local tbl = ensureNamespace(root, ns)
    tbl[key] = value
    return true
  end

  -- Bulk assign (table of key->value) into namespace.
  function self:Assign(ns, kv)
    if type(kv) ~= "table" then return false, "kv not table" end
    local tbl = ensureNamespace(root, ns)
    for k,v in pairs(kv) do tbl[k] = v end
    return true
  end

  -- Reset a namespace (optionally preserving provided keys)
  function self:Reset(ns, preserveKeys)
    local old = ensureNamespace(root, ns)
    local keep = {}
    if type(preserveKeys) == "table" then
      for _,k in ipairs(preserveKeys) do keep[k] = old[k] end
    end
    root[ns] = {}
    for k,v in pairs(keep) do root[ns][k] = v end
    return true
  end

  -- Export snapshot (deep copy) of namespace data
  function self:Export(ns)
    local function clone(t)
      if type(t) ~= "table" then return t end
      local r = {}; for k,v in pairs(t) do r[k] = clone(v) end; return r
    end
    return clone(ensureNamespace(root, ns))
  end

  -- History utility: append an entry to a list under ns.key (auto timestamps). Creates list if missing.
  function self:Append(ns, key, value)
    local tbl = ensureNamespace(root, ns)
    tbl[key] = tbl[key] or {}
    table.insert(tbl[key], { at = now_s(), value = value })
    return #tbl[key]
  end

  -- Prune list under ns.key to max items (oldest first) if over limit.
  function self:Prune(ns, key, max)
    local tbl = ensureNamespace(root, ns)
    local list = tbl[key]
    if type(list) ~= "table" or max <= 0 then return 0 end
    while #list > max do table.remove(list, 1) end
    return #list
  end

  -- Advanced prune with filters: opts = { max=number, minTimestamp=epochSeconds, match=substr, drop=substr }
  -- Order of operations: age filter -> match/drop filters -> max trimming (keep newest items assuming chronological order)
  function self:PruneFiltered(ns, key, opts)
    opts = opts or {}
    local tbl = ensureNamespace(root, ns)
    local list = tbl[key]
    if type(list) ~= "table" then return { before=0, after=0, removed=0, reason="not-table" } end
    local before = #list
    if before == 0 then return { before=0, after=0, removed=0 } end
    local minTs = tonumber(opts.minTimestamp)
    local matchSub = opts.match
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
    return { before=before, after=after, removed=before-after }
  end

  return self
end

local function RegisterSavedVarsService()
  if not Addon.provide then error("SavedVarsService: Addon.provide not available") end
  Addon.provide("SavedVarsService", CreateSavedVarsService, { lifetime = "SingleInstance" })
  Addon.SavedVars = setmetatable({}, {
    __index = function(_, k)
      local inst = Addon.require("SavedVarsService"); return inst[k]
    end,
    __call = function(_, ...) return Addon.require("SavedVarsService"), ... end
  })
end

Addon._RegisterSavedVarsService = RegisterSavedVarsService
return RegisterSavedVarsService
