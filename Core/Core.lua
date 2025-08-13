-- Core.lua — Autofac-style DI for WoW (Lua 5.1-safe)

local Core = {}

-----------------------------------------------------------------------
-- Utils
-----------------------------------------------------------------------
local function tbl_shallow_copy(t)
  local n = {}
  for k,v in pairs(t) do n[k] = v end
  return n
end

local function push(stack, v) stack[#stack+1] = v end
local function pop(stack) stack[#stack] = nil end

local function join(arr, sep)
  local b = {}
  for i=1,#arr do b[#b+1] = tostring(arr[i]) end
  return table.concat(b, sep or ", ")
end

local function new_id_gen(prefix)
  local c = 0
  return function()
    c = c + 1
    return (prefix or "id") .. ":" .. c
  end
end

local newRegId = new_id_gen("reg")

local function is_callable(v)
  if type(v) == "function" then return true end
  local mt = getmetatable(v)
  return mt and type(mt.__call) == "function"
end

Core.__gr_version = 1
-----------------------------------------------------------------------
local function newRegistry()
  return {
    regs = {},            -- [regId] = registration
    map = {},             -- [key] = array of regIds (registration order)
    decorators = {},      -- [key] = array of decorator regIds (registration order)
    order = {},           -- all regIds in registration order
  }
end

-----------------------------------------------------------------------
-- RegistrationBuilder
-----------------------------------------------------------------------
local function newRegistrationBuilder(registry, factory)
  local reg = {
    id = newRegId(),
    factory = factory,            -- function(scope, params) -> instance
    services = {},                -- set-like of keys this provides
    lifetime = "InstancePerDependency", -- default
    parameters = {},              -- default parameter providers { name = const | function(scope) -> value }
  meta = {},                    -- tiny metadata bag (for future policies/diagnostics)
    events = {
      OnPreparing = nil,          -- fn(scope, ctx) -> may mutate ctx.Parameters
      OnActivating = nil,         -- fn(scope, instance, ctx)
      OnActivated = nil,          -- fn(scope, instance, ctx)
      OnRelease = nil,            -- fn(instance) (also called before Stop)
    },
  isDecorator = false,
    decoratesKey = nil,           -- if decorator, which key it decorates
    asSelfKey = nil,              -- used for AsSelf
  }

  local function indexOf(t, v)
    for i=1,#t do if t[i] == v then return i end end
    return nil
  end

  local rb = {}

  function rb:As(key)
    if key == nil then error("As(key): key cannot be nil") end
    reg.services[key] = true
    return self
  end

  function rb:AsSelf()
    reg.asSelfKey = reg.factory
    reg.services[reg.asSelfKey] = true
    return self
  end

  function rb:SingleInstance() reg.lifetime = "SingleInstance"; return self end
  function rb:InstancePerDependency() reg.lifetime = "InstancePerDependency"; return self end
  function rb:InstancePerLifetimeScope() reg.lifetime = "InstancePerLifetimeScope"; return self end

  function rb:WithParameter(name, valueOrFunc)
    if not name or name == "" then error("WithParameter(name, ...) requires a name") end
    reg.parameters[name] = valueOrFunc
    return self
  end

    -- Attach arbitrary metadata to this registration (does not affect resolve)
    function rb:WithMetadata(name, value)
      if not name or name == "" then error("WithMetadata(name, value) requires a name") end
      reg.meta[name] = value
      return self
    end

    -- Bulk attach a table of metadata keys (shallow-merged)
    function rb:WithMetadataTable(tbl)
      if type(tbl) ~= "table" then error("WithMetadataTable(tbl) requires a table") end
      for k,v in pairs(tbl) do reg.meta[k] = v end
      return self
    end
  function rb:OnPreparing(fn) reg.events.OnPreparing = fn; return self end
  function rb:OnActivating(fn) reg.events.OnActivating = fn; return self end
  function rb:OnActivated(fn) reg.events.OnActivated = fn; return self end
  function rb:OnRelease(fn) reg.events.OnRelease = fn; return self end

  function rb:AsDecorator(key)
    if not key then error("AsDecorator(key) requires a key to decorate") end
    reg.isDecorator = true
    reg.decoratesKey = key
    return self
  end

  function rb:_commit()
    registry.regs[reg.id] = reg
    registry.order[#registry.order+1] = reg.id
    -- Use presence of decoratesKey instead of boolean flag to avoid static "always false" diagnostics
    if reg.decoratesKey ~= nil then
      local arr = registry.decorators[reg.decoratesKey]
      if not arr then arr = {}; registry.decorators[reg.decoratesKey] = arr end
      arr[#arr+1] = reg.id
    else
      -- map all provided services
      for key,_ in pairs(reg.services) do
        local arr = registry.map[key]
        if not arr then arr = {}; registry.map[key] = arr end
        -- maintain registration order; newest is last
        arr[#arr+1] = reg.id
      end
    end
  end

  return rb, reg
end

-----------------------------------------------------------------------
-- Builder
-----------------------------------------------------------------------
local function newBuilder()
  local registry = newRegistry()

  local builder = {}

  function builder:Register(factory)
    if not is_callable(factory) then
      error("Register(factory): factory must be callable")
    end
    local rb = newRegistrationBuilder(registry, factory)
    return rb
  end

  function builder:RegisterInstance(key, instance)
    local rb = newRegistrationBuilder(registry, function() return instance end)
    rb:As(key):SingleInstance()
    rb:_commit()
    return rb
  end

  function builder:RegisterModule(mod)
    if type(mod) ~= "table" or type(mod.Load) ~= "function" then
      error("RegisterModule: expected table with Load(self, builder) function")
    end
    mod:Load(builder)
    return builder
  end

  function builder:Build()
    -- finalize all registrations (commit any uncommitted)
    -- (In this design, we commit on As/AsDecorator and Build expects everything already committed by rb users.)
    -- Still, we sanity check: ensure each reg has at least one service unless decorator or AsSelf
    for _, regId in ipairs(registry.order) do
      local r = registry.regs[regId]
      if r.decoratesKey == nil then
        local count = 0
        for _ in pairs(r.services) do count = count + 1 break end
        if count == 0 then
          error("Registration " .. r.id .. " has no services. Use :As(key) or :AsSelf().")
        end
      end
    end
    return Core._newContainer(registry)
  end

  -- expose a way to finalize an RB (so user doesn’t forget)
  function builder:_commit(rb)
    rb:_commit()
    return builder
  end

  return builder, registry
end

-----------------------------------------------------------------------
-- Lifetime Scope / Container
-----------------------------------------------------------------------
local function newScope(registry, parent, tag, root)
  local scope = {}

  scope._registry = registry
  scope._parent = parent
  scope._tag = tag
  scope._root = root or parent and parent._root or nil

  -- caches and tracking
  scope._singletons = parent and parent._singletons or {}    -- only root owns this table
  scope._scoped = {}                                          -- [regId] = instance (for InstancePerLifetimeScope)
  scope._perDepTracked = {}                                   -- instances created in this scope for per-dep tracking
  scope._disposables = {}                                     -- array of instances (Stop/OnRelease) to call on dispose (in reverse)
  -- Do not eagerly initialize _isDisposed; nil means "not disposed" and avoids static-analyzer false positives

  -- resolution chain stack for *this* scope (not shared across scopes)
  -- Contains strings like "<key>#<regId>" to keep chains readable & unique
  scope._resChain = {}

  local function isDisposed()
    -- Use rawget to avoid metatable surprises and placate static analyzers
    local v = rawget(scope, '_isDisposed')
    return v == true
  end

  local function ensureNotDisposed()
    if isDisposed() then error("This lifetime scope has already been disposed: " .. tostring(scope._tag or "(untagged)")) end
  end

  local function lifetimedRegisterDisposable(instance, onRelease)
    -- register instance for disposal on scope dispose (per-dep + per-scope)
    scope._disposables[#scope._disposables+1] = { inst = instance, onRelease = onRelease }
  end

  local function callStart(instance)
    local s = nil
    if type(instance) == "table" then s = instance.Start end
    if type(s) == "function" then
      local ok, err = pcall(s, instance)
      if not ok then error("Start() failed: " .. tostring(err)) end
    end
  end

  local function callStopAndRelease(entry)
    local inst, onRelease = entry.inst, entry.onRelease
    -- OnRelease first
    if type(onRelease) == "function" then
      pcall(onRelease, inst)
    end
    -- Stop afterwards
    local stop = (type(inst) == "table") and inst.Stop or nil
    if type(stop) == "function" then
      pcall(stop, inst)
    end
  end

  local function buildContext(reg, overrides)
    local ctx = {
      Registration = reg,
      Parameters = {},  -- merged defaults + overrides
      Overrides = overrides or {},
    }
    -- merge defaults
    for name, prov in pairs(reg.parameters) do
      ctx.Parameters[name] = prov
    end
    -- merge overrides (wins)
    local ovp = (overrides and overrides.Parameters) or (overrides and overrides.parameters)
    if type(ovp) == "table" then
      for name, prov in pairs(ovp) do
        ctx.Parameters[name] = prov
      end
    end
    return ctx
  end

  local function evaluateParams(ctx)
    local evaluated = {}
    for name, prov in pairs(ctx.Parameters) do
      local v = prov
      if is_callable(prov) then
        v = prov(scope)
      end
      evaluated[name] = v
    end
    return evaluated
  end

  local function resolveKeyLabel(key)
    if type(key) == "string" then return key end
    if type(key) == "function" then return "fn@" .. tostring(key) end
    return tostring(key)
  end

  local function chainToken(key, regId)
    return resolveKeyLabel(key) .. "#" .. regId
  end

  local function inChain(token)
    for i=1,#scope._resChain do
      if scope._resChain[i] == token then return i end
    end
    return nil
  end

  -- Builds a nice chain like "A -> B -> C -> A"
  local function chainToString(loopAtIndex, reenterToken)
    local labels = {}
    for i=1,#scope._resChain do
      labels[#labels+1] = scope._resChain[i]
    end
    if reenterToken then
      labels[#labels+1] = reenterToken
    end
    if loopAtIndex then
      -- highlight the cycle start
      -- (no special formatting needed; the repeated token shows the loop)
    end
    return join(labels, " -> ")
  end

  -- Core instance creation (no decorator wrapping). Returns instance and the reg used.
  local function constructFromRegistration(key, reg, overrides)
    local token = chainToken(key, reg.id)
    local existingIndex = inChain(token)
    if existingIndex then
      -- *** Circular dependency detection (correctly only when actual loop) ***
      error("Circular dependency detected while resolving '" .. resolveKeyLabel(key) .. "': " .. chainToString(existingIndex, token))
    end

    push(scope._resChain, token)

    local ctx = buildContext(reg, overrides)
    local okPrepare, prepErr = true, nil
    if reg.events.OnPreparing then
      okPrepare, prepErr = pcall(reg.events.OnPreparing, scope, ctx)
      if not okPrepare then
        pop(scope._resChain)
        error("OnPreparing failed for " .. token .. ": " .. tostring(prepErr))
      end
    end

    local params = evaluateParams(ctx)

    -- Instantiate
    local okInst, instanceOrErr = pcall(reg.factory, scope, params)
    if not okInst then
      -- *** IMPORTANT FIX: propagate original factory error; do NOT mislabel as circular ***
      pop(scope._resChain)
      error("Activation failed for " .. token .. ": " .. tostring(instanceOrErr))
    end

    local instance = instanceOrErr

    -- OnActivating
    if reg.events.OnActivating then
      local okAct, actErr = pcall(reg.events.OnActivating, scope, instance, ctx)
      if not okAct then
        pop(scope._resChain)
        error("OnActivating failed for " .. token .. ": " .. tostring(actErr))
      end
    end

    -- Lifecycle Start()
    callStart(instance)

    -- Track for disposal depending on lifetime
    local onRelease = reg.events.OnRelease

    if reg.lifetime == "SingleInstance" then
      -- root cache handles lifetime; only register once when it’s first created (done at cache point)
      -- still ensure release is called when root is disposed (handled by root’s _disposables)
    elseif reg.lifetime == "InstancePerLifetimeScope" then
      lifetimedRegisterDisposable(instance, onRelease)
    else -- InstancePerDependency
      lifetimedRegisterDisposable(instance, onRelease)
    end

    -- OnActivated
    if reg.events.OnActivated then
      local okAed, aedErr = pcall(reg.events.OnActivated, scope, instance, ctx)
      if not okAed then
        pop(scope._resChain)
        error("OnActivated failed for " .. token .. ": " .. tostring(aedErr))
      end
    end

    pop(scope._resChain)
    return instance, reg
  end

  local function getLatestNonDecoratorRegFor(key)
    local arr = scope._registry.map[key]
    if not arr or #arr == 0 then return nil end
    return scope._registry.regs[arr[#arr]]
  end

  local function getAllNonDecoratorRegsFor(key)
    local arr = scope._registry.map[key]
    local regs = {}
    if arr then
      for i=1,#arr do regs[#regs+1] = scope._registry.regs[arr[i]] end
    end
    return regs
  end

  local function getDecoratorsFor(key)
    local arr = scope._registry.decorators[key]
    local regs = {}
    if arr then
      for i=1,#arr do regs[#regs+1] = scope._registry.regs[arr[i]] end
    end
    return regs
  end

  local function applyDecorators(key, baseInstance, overrides)
    local decs = getDecoratorsFor(key)
    if #decs == 0 then return baseInstance end
    -- outermost = last-registered decorator; wrap in reverse reg order
    local wrapped = baseInstance
    for i = #decs, 1, -1 do
      local dReg = decs[i]
      -- Decorator factory signature: function(scope, params) -> returns object
      -- It should accept an 'inner' param if needed; we pass via params["inner"]
      local ov = { Parameters = { inner = function() return wrapped end } }
      if overrides and overrides.Parameters then
        -- Allow caller to override decorator params too (but not 'inner')
        for k,v in pairs(overrides.Parameters) do if k ~= "inner" then ov.Parameters[k] = v end end
      end
      wrapped = constructFromRegistration(key, dReg, ov)
    end
    return wrapped
  end

  -- *** Resolution caches with lifetimes ***
  local function resolveCore(key, overrides, wantAll, forbidDecorators)
    ensureNotDisposed()

    -- InstancePerDependency: always construct (but still track for disposal)
    -- InstancePerLifetimeScope: cache in this scope
    -- SingleInstance: cache in root scope

    local regs = wantAll and getAllNonDecoratorRegsFor(key) or (getLatestNonDecoratorRegFor(key) and { getLatestNonDecoratorRegFor(key) } or {})

    if #regs == 0 then
      error("No registration for key: " .. resolveKeyLabel(key))
    end

    if wantAll then
      local result = {}
      for i=1,#regs do
        local reg = regs[i]
        local inst

        if reg.lifetime == "SingleInstance" then
          local cached = scope._root._singletons[reg.id]
          if not cached then
            local created = constructFromRegistration(key, reg, overrides)
            scope._root._singletons[reg.id] = created
            -- singletons disposed at root
            scope._root._disposables[#scope._root._disposables+1] = { inst = created, onRelease = reg.events.OnRelease }
            inst = created
          else
            inst = cached
          end
        elseif reg.lifetime == "InstancePerLifetimeScope" then
          local cached = scope._scoped[reg.id]
          if not cached then
            local created = constructFromRegistration(key, reg, overrides)
            scope._scoped[reg.id] = created
            inst = created
          else
            inst = cached
          end
        else -- InstancePerDependency
          inst = constructFromRegistration(key, reg, overrides)
        end

  if not forbidDecorators then inst = applyDecorators(key, inst, overrides) end

        result[#result+1] = inst
      end
      return result
    else
      local reg = regs[1]
      local instance

      if reg.lifetime == "SingleInstance" then
        local cached = scope._root._singletons[reg.id]
        if not cached then
          local created = constructFromRegistration(key, reg, overrides)
          scope._root._singletons[reg.id] = created
          -- ensure root disposes singleton
          scope._root._disposables[#scope._root._disposables+1] = { inst = created, onRelease = reg.events.OnRelease }
          instance = created
        else
          instance = cached
        end
      elseif reg.lifetime == "InstancePerLifetimeScope" then
        local cached = scope._scoped[reg.id]
        if not cached then
          local created = constructFromRegistration(key, reg, overrides)
          scope._scoped[reg.id] = created
          instance = created
        else
          instance = cached
        end
      else -- InstancePerDependency
        instance = constructFromRegistration(key, reg, overrides)
      end

  if not forbidDecorators then instance = applyDecorators(key, instance, overrides) end

      return instance
    end
  end

  -- Public API on scope
  function scope:Resolve(key, overrides)
    return resolveCore(key, overrides, false, false)
  end

  function scope:TryResolve(key, overrides)
    local ok, res = pcall(resolveCore, key, overrides, false, false)
    if ok then return res, nil else return nil, res end
  end

  function scope:ResolveNamed(name, overrides) -- alias for Resolve(string)
    return resolveCore(name, overrides, false, false)
  end

  function scope:ResolveKeyed(key, overrides)  -- keyed can be string, fn, table, etc.
    return resolveCore(key, overrides, false, false)
  end

  function scope:ResolveAll(key, overrides)
    return resolveCore(key, overrides, true, false)
  end

  -- Owned<T> — build in a child scope; disposing Owned disposes that scope (and instance)
  function scope:ResolveOwned(key, overrides)
    local child = scope:BeginLifetimeScope("Owned<" .. resolveKeyLabel(key) .. ">")
    local inst = child:Resolve(key, overrides)
    return {
      Instance = inst,
      Dispose = function()
        child:Dispose()
      end
    }
  end

  function scope:BeginLifetimeScope(tag)
    ensureNotDisposed()
    local child = newScope(scope._registry, scope, tag, scope._root)
    return child
  end

  function scope:Dispose()
    if isDisposed() then return end
    scope._isDisposed = true
    -- dispose in LIFO
    for i=#scope._disposables,1,-1 do
      local entry = scope._disposables[i]
      callStopAndRelease(entry)
      scope._disposables[i] = nil
    end
    -- clear scoped caches
    for k,_ in pairs(scope._scoped) do scope._scoped[k] = nil end
    for k,_ in pairs(scope._perDepTracked) do scope._perDepTracked[k] = nil end
    -- root keeps singletons until root dispose; if this is root, clear them now
    if not scope._parent then
      for k,_ in pairs(scope._singletons) do scope._singletons[k] = nil end
    end
  end

  return scope
end

-----------------------------------------------------------------------
-- Container (root)
-----------------------------------------------------------------------
function Core._newContainer(registry)
  local root = newScope(registry, nil, "root", nil)
  root._root = root
  function root:DisposeRoot()
  if rawget(self, '_isDisposed') then return end
    self:Dispose()
  end
  return root
end

function Core.Builder()
  return newBuilder()
end

-----------------------------------------------------------------------
-- Addon.provide / Addon.require convenience
-----------------------------------------------------------------------
-- A single, lazily-created global root container for simple usage.
---@class GR_Global
---@field builder table|nil
---@field container table|nil
---@type GR_Global
local _global = {
  builder = nil,
  container = nil,
}

local _providedKeys = {}
local _validation_ran = false
local function hasContainer()
  return _global and _global.container ~= nil
end
local _overrideWhitelist = { -- optional: populate with high-risk keys allowed to be overridden in dev
}

local function warn(msg)
  local frame = rawget(_G, 'DEFAULT_CHAT_FRAME')
  if frame and frame.AddMessage then frame:AddMessage("|cffff8800[GuildRecruiter][DI]|r "..tostring(msg)) end
end

local function ensureGlobalBuilt()
  if not _global.container then
    if not _global.builder then
      _global.builder = Core.Builder()
    end
  _global.container = _global.builder:Build()
  -- Expose built container for diagnostics (ListRegistered) & tooling
  Core._container = _global.container
  end
end

local Addon = {}

-- Addon.provide(key, valueOrFactory [, opts])
-- opts = { lifetime = "SingleInstance"|"InstancePerDependency"|"InstancePerLifetimeScope" }
function Addon.provide(key, valueOrFactory, opts)
  if hasContainer() then
    error("Cannot register service '"..tostring(key).."' after container has been built (register earlier before first require)")
  end
  if not _global.builder then
    _global.builder = Core.Builder()
  end
  local lifetime = (opts and opts.lifetime) or "SingleInstance"

  if key then
    if _providedKeys[key] then
      -- Attempt to read devMode without building the container
      local dev = false
      pcall(function()
        local cfg = (Addon.Peek and Addon.Peek("IConfiguration"))
        if cfg and cfg.Get then dev = cfg:Get("devMode", false) end
      end)
      if not dev then
        error("Duplicate service registration for key '"..tostring(key).."' (enable devMode to override)")
      else
        warn("[devMode] overriding existing service key: "..tostring(key))
      end
    end
    _providedKeys[key] = true
  end

  local factory
  if is_callable(valueOrFactory) then
    factory = valueOrFactory
  else
    local const = valueOrFactory
    factory = function() return const end
  end

  local rb = _global.builder:Register(function(scope, params)
    if factory == valueOrFactory and is_callable(factory) then
      -- Detect arity (Lua doesn't expose directly; attempt pcall with 2 args then fallback)
      local ok, res = pcall(factory, scope, params)
      if ok then return res end
      -- fallback: try no args
      local ok2, res2 = pcall(factory)
      if ok2 then return res2 end
      error(res)
    else
      return factory()
    end
  end):As(key)

  if lifetime == "SingleInstance" then rb:SingleInstance()
  elseif lifetime == "InstancePerLifetimeScope" then rb:InstancePerLifetimeScope()
  else rb:InstancePerDependency() end

  -- Optional metadata bag (for policies/diagnostics). Does not affect resolve path.
  local metaTbl = (opts and (opts.metadata or opts.meta))
  if type(metaTbl) == "table" then rb:WithMetadataTable(metaTbl) end

  _global.builder:_commit(rb)
end

-- Explicit override API: allowed only in devMode, and optionally gated by whitelist.
function Addon.override(key, valueOrFactory, opts)
  if hasContainer() then
    error("Cannot override service '"..tostring(key).."' after container has been built")
  end
  if not key or key == "" then error("override(key, ...) requires a key") end
  local dev = false
  pcall(function()
  local cfg = (Addon.Peek and Addon.Peek("IConfiguration"))
    if cfg and cfg.Get then dev = cfg:Get("devMode", false) end
  end)
  if not dev then error("Addon.override requires devMode=true") end
  if _overrideWhitelist and next(_overrideWhitelist) ~= nil then
    if not _overrideWhitelist[key] then
      error("Override not permitted for key '"..tostring(key).."' (not in whitelist)")
    end
  end
  -- Mark as provided so subsequent provides won't fail, then register new value
  _providedKeys[key] = true
  return Addon.provide(key, valueOrFactory, opts)
end

-- Safe provide helper (no error on duplicates, idempotent)
function Addon.safeProvide(key, valueOrFactory, opts)
  if Addon.IsProvided and Addon.IsProvided(key) then return end
  if hasContainer() then return end
  local ok, err = pcall(Addon.provide, key, valueOrFactory, opts)
  if not ok then
    local msg = tostring(err)
    if not (msg:match("Duplicate service registration") or msg:match("already registered")) then error(err) end
  end
end

-- Core-level safety alias: ensure IConfiguration is always present pre-build.
-- This avoids races if contract/implementation modules haven’t run yet.
do
  local ok = pcall(function()
    if type(Addon.safeProvide) == 'function' then
      Addon.safeProvide('IConfiguration', function(scope)
        return scope:Resolve('Config')
      end, { lifetime = 'SingleInstance' })
    end
  end)
  -- ignore errors; this is best-effort, idempotent
end

function Addon.require(key, overrides)
  ensureGlobalBuilt()
  local c = assert(_global.container, 'DI container not built')
  return c:Resolve(key, overrides)
end

-- Query if a service key has already been registered
function Addon.IsProvided(key)
  return key ~= nil and _providedKeys[key] == true
end

-- Convenience Addon.Get (safe) for optional dependencies (defined early so ns export sees it)
function Addon.Get(key)
  -- Non-building optional accessor; returns instance only if already available
  return Addon.Peek(key)
end

-- Non-building peek: returns instance only if the container already exists; never builds it
function Addon.Peek(key)
  if not hasContainer() then return nil end
  local c = _global.container
  if not c or not c.Resolve then return nil end
  local ok, inst = pcall(function() return c:Resolve(key) end)
  if ok then return inst end
end

-- Alias Try for semantic clarity when refactoring older "fallback" code
Addon.Try = Addon.Get

-- ResolveAll helper (returns empty table on error)
function Addon.ResolveAll(key)
  local ok, list = pcall(function()
  ensureGlobalBuilt(); local c = _global.container; if not c then error('DI container not built') end; return c:ResolveAll(key) or {}
  end)
  if ok and list then return list end
  return {}
end

-- Strict assertion for critical services; raises descriptive error early instead of silent nil
function Addon.Assert(key)
  local inst = Addon.Get(key)
  if not inst then
    error("[GuildRecruiter][Assert] Missing required service: "..tostring(key))
  end
  return inst
end

-- Helper: mark an instance as implementing an interface by name and attach the nominal token if available
function Addon.MarkImplements(instance, ifaceName)
  if type(instance) ~= 'table' or type(ifaceName) ~= 'string' or ifaceName == '' then return instance end
  local iface = Addon.Get and Addon.Get(ifaceName)
  if iface and iface.__interface then
    instance.__implements = instance.__implements or {}
    instance.__implements[ifaceName] = true
    if iface.__id then
      instance.__implementsTokens = instance.__implementsTokens or {}
      instance.__implementsTokens[iface.__id] = true
    end
  end
  return instance
end

-- ClassProvide sugar: Addon.ClassProvide('ServiceName', ClassType, opts)
-- ClassType.__deps = { 'Logger', 'Clock', ... }
-- ClassType.__implements = { 'IService', 'IOther' }
-- opts.lifetime (default SingleInstance)
function Addon.ClassProvide(name, classType, opts)
  if type(name) ~= 'string' or name=='' then error('ClassProvide: name required') end
  if type(classType) ~= 'table' and type(classType) ~= 'function' then error('ClassProvide: classType must be class table/callable') end
  local lifetime = (opts and opts.lifetime) or 'SingleInstance'
  local deps = classType.__deps or {}
  if hasContainer() then error('ClassProvide must be called before container build') end
  local metaTbl = opts and (opts.meta or opts.metadata)
  Addon.provide(name, function(scope)
    local resolved = {}
    for i=1,#deps do
      local depKey = deps[i]
      local ok, dep = pcall(function() return scope:Resolve(depKey) end)
      if not ok then error('ClassProvide resolve failed for '..tostring(depKey)..': '..tostring(dep)) end
      resolved[#resolved+1] = dep
    end
  -- luacheck: push ignore
  local instance = classType(unpack(resolved)) -- Lua 5.1/JIT global 'unpack'
  -- luacheck: pop
    if type(instance) ~= 'table' then error('ClassProvide ctor for '..name..' did not return a table instance') end
    -- Mark implements and provide alias keys
    if classType.__implements then
      instance.__implements = instance.__implements or {}
      for _,ifaceName in ipairs(classType.__implements) do
        instance.__implements[ifaceName] = true
      end
    end
    return instance
  end, { lifetime = lifetime, meta = metaTbl, metadata = metaTbl })
  -- Interface alias keys
  if classType.__implements then
    for _,ifaceName in ipairs(classType.__implements) do
      if not (Addon.IsProvided and Addon.IsProvided(ifaceName)) then
  Addon.safeProvide(ifaceName, function(sc) return sc:Resolve(name) end, { lifetime = lifetime, meta = metaTbl, metadata = metaTbl })
      end
    end
  end
end

-- Validate all implementations that declare __implements against loaded interface contracts
local function _getInterface(name)
  -- interface contracts are provided under their own key
  local ok, iface = pcall(function() return Addon.require(name) end)
  if ok and iface and iface.__interface then return iface end
end

local function _implementsAll(obj, iface)
  if not iface or not iface.__methods then return true end
  for m,_ in pairs(iface.__methods) do
    if type(obj[m]) ~= 'function' then return false, m end
  end
  return true
end

local function _hasNominalToken(obj, iface)
  local tokens = obj and obj.__implementsTokens
  local id = iface and iface.__id
  if tokens and id then
    return tokens[id] == true
  end
  return true -- no tokens present => opt-out, accept
end

local function _warn(msg)
  local frame = rawget(_G,'DEFAULT_CHAT_FRAME')
  if frame and frame.AddMessage then frame:AddMessage("|cffff8800[GuildRecruiter][DI]|r "..tostring(msg)) else print("[GuildRecruiter][DI] "..tostring(msg)) end
end

function Addon.ValidateImplementations()
  ensureGlobalBuilt()
  if _validation_ran then return true end
  _validation_ran = true
  local keys = Addon.ListRegistered and Addon.ListRegistered() or {}
  for _, key in ipairs(keys) do
    local ok, inst = pcall(function() return Addon.require(key) end)
    if ok and type(inst) == 'table' and inst.__implements then
      for ifaceName, flag in pairs(inst.__implements) do if flag then
        local iface = _getInterface(ifaceName)
        if iface then
          -- If implementer opted-in to nominal tokens, enforce it
          if not _hasNominalToken(inst, iface) then
            _warn(string.format("Service '%s' claims %s but is missing nominal token (__implementsTokens[%s])", tostring(key), tostring(ifaceName), tostring(iface.__id or '?')))
          end
          local good, missing = _implementsAll(inst, iface)
          if not good then
            _warn(string.format("Service '%s' claims %s but is missing method '%s'", tostring(key), tostring(ifaceName), tostring(missing)))
          end
        end
      end end
    end
  end
  return true
end

-----------------------------------------------------------------------
-- Public API
-----------------------------------------------------------------------
Core.Addon = Addon

-- Register Core itself so other modules can resolve it via Addon.require("Core")
-- This is safe because the factory just returns the already-loaded Core table.
-- luacheck: push ignore 542
if not Addon.IsProvided("Core") then
  Addon.provide("Core", function() return Core end, { lifetime = "SingleInstance", meta = { layer = 'Core' } })
end
-- luacheck: pop

-- Helper sugar to align with docs in your notes:
function Core.ContainerBuilder()
  return Core.Builder()
end

-- Create a thin, scoped ServiceProvider wrapper for injection
function Core._makeServiceProvider(scope)
  return {
    Resolve = function(self, key, overrides) return scope:Resolve(key, overrides) end,
    TryResolve = function(self, key, overrides) return scope:TryResolve(key, overrides) end,
    ResolveAll = function(self, key, overrides) return scope:ResolveAll(key, overrides) end,
    ResolveOwned = function(self, key, overrides) return scope:ResolveOwned(key, overrides) end,
    BeginLifetimeScope = function(self, tag) return scope:BeginLifetimeScope(tag) end,
    Scope = scope,
  }
end

-- Export so other addon files can access Core without require()
_G.Core = Core

-- Export into addon namespace (preferred)
local __va = { ... }
local addonName = __va[1]
local ns = __va[2]
if type(ns) ~= "table" then ns = _G[addonName] or {}; end
ns.Core = Core
-- Expose DI convenience onto the addon namespace for consumer files
ns.provide = Addon.provide
ns.require = Addon.require
ns.Get = Addon.Get
ns.IsProvided = Addon.IsProvided


-- Factory registration helpers (scoped factories avoid global root and protect resolve path)
function Addon.provideFactory(factoryKey, targetKey, opts)
  if not factoryKey or not targetKey then error("provideFactory(factoryKey, targetKey, opts) requires keys") end
  local lifetime = (opts and opts.lifetime) or "InstancePerLifetimeScope"
  local metaTbl = opts and (opts.meta or opts.metadata)
  Addon.provide(factoryKey, function(scope)
    return function(overrides) return scope:Resolve(targetKey, overrides) end
  end, { lifetime = lifetime, meta = metaTbl, metadata = metaTbl })
end

function Addon.provideAllFactory(factoryKey, targetKey, opts)
  if not factoryKey or not targetKey then error("provideAllFactory(factoryKey, targetKey, opts) requires keys") end
  local lifetime = (opts and opts.lifetime) or "InstancePerLifetimeScope"
  local metaTbl = opts and (opts.meta or opts.metadata)
  Addon.provide(factoryKey, function(scope)
    return function(overrides) return scope:ResolveAll(targetKey, overrides) end
  end, { lifetime = lifetime, meta = metaTbl, metadata = metaTbl })
end

function Addon.provideOwnedFactory(factoryKey, targetKey, opts)
  if not factoryKey or not targetKey then error("provideOwnedFactory(factoryKey, targetKey, opts) requires keys") end
  local lifetime = (opts and opts.lifetime) or "InstancePerLifetimeScope"
  local metaTbl = opts and (opts.meta or opts.metadata)
  Addon.provide(factoryKey, function(scope)
    return function(overrides) return scope:ResolveOwned(targetKey, overrides) end
  end, { lifetime = lifetime, meta = metaTbl, metadata = metaTbl })
end
-- Enumerate registered keys (sorted) for diagnostics
function Addon.ListRegistered()
  local c = Core and Core._container
  -- luacheck: push ignore 542
  if not c or not c._registry or not c._registry.map then return {} end
  -- luacheck: pop
  local keys = {}
  for k,_ in pairs(c._registry.map) do keys[#keys+1]=k end
  table.sort(keys)
  return keys
end

-- Diagnostics: fetch metadata for non-decorator registrations of a key
function Addon.GetRegistrationMetadata(key)
  local c = Core and Core._container
  if not c or not c._registry then return {} end
  local regIds = c._registry.map[key]
  if not regIds then return {} end
  local out = {}
  for i=1,#regIds do
    local id = regIds[i]
    local r = c._registry.regs[id]
    local m = (r and r.meta) or {}
    local copy = {}
    for k,v in pairs(m) do copy[k] = v end
    out[#out+1] = { regId = id, meta = copy }
  end
  return out
end

-- Diagnostics: fetch metadata for decorators registered against a key
function Addon.GetDecoratorMetadata(key)
  local c = Core and Core._container
  if not c or not c._registry then return {} end
  local regIds = c._registry.decorators[key]
  if not regIds then return {} end
  local out = {}
  for i=1,#regIds do
    local id = regIds[i]
    local r = c._registry.regs[id]
    local m = (r and r.meta) or {}
    local copy = {}
    for k,v in pairs(m) do copy[k] = v end
    out[#out+1] = { regId = id, meta = copy }
  end
  return out
end

-- Diagnostics: filter registered keys by a metadata predicate
-- predicate(meta, key, regId) -> boolean
function Addon.FilterKeysByMetadata(predicate)
  local c = Core and Core._container
  if type(predicate) ~= 'function' or not c or not c._registry then return {} end
  local result = {}
  for key, regIds in pairs(c._registry.map or {}) do
    for i=1,#regIds do
      local id = regIds[i]
      local r = c._registry.regs[id]
      local meta = (r and r.meta) or {}
  local success, val = pcall(predicate, meta, key, id)
  if success and val then result[#result+1] = key; break end
    end
  end
  table.sort(result)
  return result
end

-- Convenience: list keys where meta[name] == value
function Addon.ListKeysWithMeta(name, value)
  return Addon.FilterKeysByMetadata(function(meta)
    return type(meta) == 'table' and meta[name] == value
  end)
end
-- Public dispose helper (idempotent)
function ns.DisposeContainer()
  -- luacheck: push ignore 542
  if hasContainer() then
    local c = _global.container
  local dispose = rawget(c, 'DisposeRoot')
  if type(dispose) == 'function' then dispose(c) end
  end
  -- luacheck: pop
end

-- Version tag for safety
Core.__gr_version = 1

-----------------------------------------------------------------------
-- (Addon.Get was defined earlier; no late reassignment needed)

