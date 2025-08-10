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

    if reg.isDecorator then
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
      if not r.isDecorator then
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
  scope._isDisposed = false

  -- resolution chain stack for *this* scope (not shared across scopes)
  -- Contains strings like "<key>#<regId>" to keep chains readable & unique
  scope._resChain = {}

  local function ensureNotDisposed()
    if scope._isDisposed then error("This lifetime scope has already been disposed: " .. tostring(scope._tag or "(untagged)")) end
  end

  local function lifetimedRegisterDisposable(instance, onRelease)
    -- register instance for disposal on scope dispose (per-dep + per-scope)
    scope._disposables[#scope._disposables+1] = { inst = instance, onRelease = onRelease }
  end

  local function callStart(instance)
    local s = instance and instance.Start
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
    local stop = inst and inst.Stop
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

        if not forbidDecorators then
          inst = applyDecorators(key, inst, overrides)
        end

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

      if not forbidDecorators then
        instance = applyDecorators(key, instance, overrides)
      end

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
    if scope._isDisposed then return end
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
    -- root keeps singletons until root dispose; if this is root, clear them too
    if not scope._parent then
      for i=#scope._disposables,1,-1 do
        local entry = scope._disposables[i]
        callStopAndRelease(entry)
        scope._disposables[i] = nil
      end
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
    if self._isDisposed then return end
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
local _global = {
  builder = nil,
  container = nil,
}

local _providedKeys = {}

local function warn(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[GuildRecruiter][DI]|r "..tostring(msg))
  end
end

local function ensureGlobalBuilt()
  if not _global.container then
    if not _global.builder then
      _global.builder = Core.Builder()
    end
    _global.container = _global.builder:Build()
  end
end

local Addon = {}

-- Addon.provide(key, valueOrFactory [, opts])
-- opts = { lifetime = "SingleInstance"|"InstancePerDependency"|"InstancePerLifetimeScope" }
function Addon.provide(key, valueOrFactory, opts)
  if not _global.builder then
    _global.builder = Core.Builder()
  end
  local lifetime = (opts and opts.lifetime) or "SingleInstance"

  -- Duplicate registration warning (non-fatal) to help catch accidental overrides
  if key and _providedKeys[key] then
    warn("Service key already registered: "..tostring(key).." (overriding previous registration)")
  end
  _providedKeys[key] = true

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

  _global.builder:_commit(rb)
end

function Addon.require(key, overrides)
  ensureGlobalBuilt()
  return _global.container:Resolve(key, overrides)
end

-- Convenience Addon.Get (safe) for optional dependencies (defined early so ns export sees it)
function Addon.Get(key)
  local ok, inst = pcall(Addon.require, key)
  if ok then return inst end
end

-- Alias Try for semantic clarity when refactoring older "fallback" code
Addon.Try = Addon.Get

-- ResolveAll helper (returns empty table on error)
function Addon.ResolveAll(key)
  local ok, list = pcall(function()
    ensureGlobalBuilt(); return _global.container:ResolveAll(key) or {}
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

-----------------------------------------------------------------------
-- Public API
-----------------------------------------------------------------------
Core.Addon = Addon

-- Register Core itself so other modules can resolve it via Addon.require("Core")
-- This is safe because the factory just returns the already-loaded Core table.
Addon.provide("Core", function() return Core end, { lifetime = "SingleInstance" })

-- Helper sugar to align with docs in your notes:
function Core.ContainerBuilder()
  return Core.Builder()
end

-- Export so other addon files can access Core without require()
_G.Core = Core

-- Export into addon namespace (preferred)
local addonName, ns = ...
if type(ns) ~= "table" then ns = {}; end
ns.Core = Core
-- Expose DI convenience onto the addon namespace for consumer files
ns.provide = Addon.provide
ns.require = Addon.require
ns.Get = Addon.Get
-- Public dispose helper (idempotent)
function ns.DisposeContainer()
  if _global and _global.container and _global.container.DisposeRoot then
    _global.container:DisposeRoot()
  end
end

-- Version tag for safety
Core.__gr_version = 1

-----------------------------------------------------------------------
-- (Addon.Get was defined earlier; no late reassignment needed)

