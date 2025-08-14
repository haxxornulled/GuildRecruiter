-- WoW: acquire addon global
local ADDON_NAME = ...
if type(ADDON_NAME) ~= 'string' then ADDON_NAME = 'GuildRecruiter' end
local Addon = _G[ADDON_NAME]
if not Addon then Addon = {}; _G[ADDON_NAME] = Addon end
Addon.DI = Addon.DI or {}

-- Registration module should already have populated Addon.DI.Registration
local Registration = Addon.DI.Registration -- not directly used but kept for context

local M = {}

local function is_callable(v) if type(v)=='function' then return true end local mt=getmetatable(v); return mt and type(mt.__call)=='function' end
local function join(arr, sep) local b={} for i=1,#arr do b[#b+1]=tostring(arr[i]) end return table.concat(b, sep or ', ') end

local function resolveKeyLabel(key)
  if type(key)=='string' then return key end
  if type(key)=='function' then return 'fn@'..tostring(key) end
  return tostring(key)
end

local function newScope(registry, parent, tag, root)
  local scope = {}
  scope._registry = registry; scope._parent = parent; scope._tag=tag; scope._root = root or (parent and parent._root) or nil
  scope._singletons = parent and parent._singletons or {}
  scope._scoped = {}; scope._perDepTracked = {}; scope._disposables = {}; scope._resChain = {}

  local function isDisposed() return rawget(scope,'_isDisposed')==true end
  local function ensureNotDisposed() if isDisposed() then error('Scope disposed: '..tostring(scope._tag or '(untagged)')) end end
  local function push(s,v) s[#s+1]=v end
  local function pop(s) s[#s]=nil end

  local function chainToken(key, regId) return resolveKeyLabel(key)..'#'..regId end
  local function inChain(token) for i=1,#scope._resChain do if scope._resChain[i]==token then return i end end end
  local function chainToString(loopAtIndex, reenterToken) local labels={} for i=1,#scope._resChain do labels[#labels+1]=scope._resChain[i] end if reenterToken then labels[#labels+1]=reenterToken end return join(labels,' -> ') end

  local function lifetimedRegisterDisposable(instance, onRelease)
    scope._disposables[#scope._disposables+1] = { inst=instance, onRelease=onRelease }
  end

  local function callStart(inst) local s = (type(inst)=='table') and inst.Start or nil; if type(s)=='function' then local ok,err=pcall(s,inst); if not ok then error('Start() failed: '..tostring(err)) end end end
  local function callStopAndRelease(entry)
    local inst, onRelease = entry.inst, entry.onRelease
    if type(onRelease)=='function' then pcall(onRelease, inst) end
    local stop = (type(inst)=='table') and inst.Stop or nil; if type(stop)=='function' then pcall(stop, inst) end
  end

  local function buildContext(reg, overrides)
    local ctx = { Registration=reg, Parameters={}, Overrides=overrides or {} }
    for n,p in pairs(reg.parameters) do ctx.Parameters[n]=p end
    local ovp = (overrides and (overrides.Parameters or overrides.parameters))
    if type(ovp)=='table' then for n,p in pairs(ovp) do ctx.Parameters[n]=p end end
    return ctx
  end
  local function evaluateParams(ctx, scopeRef)
    local out={} for n,prov in pairs(ctx.Parameters) do local v=prov; if is_callable(prov) then v=prov(scopeRef) end out[n]=v end return out end

  local function getLatestNonDecoratorRegFor(key)
    local arr = registry.map[key]; if not arr or #arr==0 then return nil end; return registry.regs[arr[#arr]]
  end
  local function getAllNonDecoratorRegsFor(key)
    local arr = registry.map[key]; local regs={}; if arr then for i=1,#arr do regs[#regs+1]=registry.regs[arr[i]] end end; return regs
  end
  local function getDecoratorsFor(key)
    local arr = registry.decorators[key]; local regs={}; if arr then for i=1,#arr do regs[#regs+1]=registry.regs[arr[i]] end end; return regs
  end

  local function constructFromRegistration(key, reg, overrides)
    local token = chainToken(key, reg.id)
    local loopAt = inChain(token)
    if loopAt then
      local path = chainToString(loopAt, token)
      error('Circular dependency detected: '..path)
    end
    push(scope._resChain, token)
    local ctx = buildContext(reg, overrides)
    if reg.events.OnPreparing then local ok,err=pcall(reg.events.OnPreparing, scope, ctx); if not ok then pop(scope._resChain); error('OnPreparing failed for '..token..': '..tostring(err)) end end
    local params = evaluateParams(ctx, scope)
    local okInst, instanceOrErr = pcall(reg.factory, scope, params)
    if not okInst then pop(scope._resChain); error('Activation failed for '..token..': '..tostring(instanceOrErr)) end
    local instance = instanceOrErr
    if reg.events.OnActivating then local okAct, actErr = pcall(reg.events.OnActivating, scope, instance, ctx); if not okAct then pop(scope._resChain); error('OnActivating failed for '..token..': '..tostring(actErr)) end end
    callStart(instance)
    local onRelease = reg.events.OnRelease
    lifetimedRegisterDisposable(instance, onRelease)
    if reg.events.OnActivated then local okAed, aedErr = pcall(reg.events.OnActivated, scope, instance, ctx); if not okAed then pop(scope._resChain); error('OnActivated failed for '..token..': '..tostring(aedErr)) end end
    pop(scope._resChain)
    return instance, reg
  end

  local function applyDecorators(key, baseInstance, overrides)
    local decs = getDecoratorsFor(key)
    if #decs==0 then return baseInstance end
    local wrapped = baseInstance
    for i=#decs,1,-1 do
      local dReg = decs[i]
      local ov = { Parameters = { inner = function() return wrapped end } }
      if overrides and overrides.Parameters then for k,v in pairs(overrides.Parameters) do if k~='inner' then ov.Parameters[k]=v end end end
      wrapped = constructFromRegistration(key, dReg, ov)
    end
    return wrapped
  end

  local function resolveCore(key, overrides, wantAll)
    ensureNotDisposed()
    local regs = wantAll and getAllNonDecoratorRegsFor(key) or (getLatestNonDecoratorRegFor(key) and { getLatestNonDecoratorRegFor(key) } or {})
    if #regs==0 then error('No registration for key: '..resolveKeyLabel(key)) end
    if wantAll then
      local result = {}
      for i=1,#regs do
        local reg = regs[i]
        local inst
        if reg.lifetime=='SingleInstance' then
          local cached = scope._root._singletons[reg.id]
          if not cached then local created=constructFromRegistration(key, reg, overrides); scope._root._singletons[reg.id]=created; scope._root._disposables[#scope._root._disposables+1]={ inst=created, onRelease=reg.events.OnRelease }; inst=created else inst=cached end
        elseif reg.lifetime=='InstancePerLifetimeScope' then
          local cached = scope._scoped[reg.id]; if not cached then local created=constructFromRegistration(key, reg, overrides); scope._scoped[reg.id]=created; inst=created else inst=cached end
        else
          inst = constructFromRegistration(key, reg, overrides)
        end
        inst = applyDecorators(key, inst, overrides)
        result[#result+1]=inst
      end
      return result
    else
      local reg = regs[1]; local instance
      if reg.lifetime=='SingleInstance' then
        local cached = scope._root._singletons[reg.id]
        if not cached then local created=constructFromRegistration(key, reg, overrides); scope._root._singletons[reg.id]=created; scope._root._disposables[#scope._root._disposables+1]={ inst=created, onRelease=reg.events.OnRelease }; instance=created else instance=cached end
      elseif reg.lifetime=='InstancePerLifetimeScope' then
        local cached = scope._scoped[reg.id]; if not cached then local created=constructFromRegistration(key, reg, overrides); scope._scoped[reg.id]=created; instance=created else instance=cached end
      else
        instance = constructFromRegistration(key, reg, overrides)
      end
      instance = applyDecorators(key, instance, overrides)
      return instance
    end
  end

  function scope:Resolve(key, overrides) return resolveCore(key, overrides, false) end
  function scope:TryResolve(key, overrides) local ok,res=pcall(resolveCore, key, overrides, false); if ok then return res,nil else return nil,res end end
  function scope:ResolveOptional(key, overrides) local arr=self._registry.map[key]; if not arr or #arr==0 then return nil end local ok,i=pcall(resolveCore,key,overrides,false); if ok then return i end end
  function scope:ResolveAll(key, overrides) return resolveCore(key, overrides, true) end
  function scope:ResolveOwned(key, overrides) local child=scope:BeginLifetimeScope('Owned<'..resolveKeyLabel(key)..'>'); local inst=child:Resolve(key, overrides); return { Instance=inst, Dispose=function() child:Dispose() end } end
  function scope:BeginLifetimeScope(tag) local child=newScope(scope._registry, scope, tag, scope._root); return child end
  function scope:Dispose()
    if isDisposed() then return end
    scope._isDisposed=true
    for i=#scope._disposables,1,-1 do local entry=scope._disposables[i]; callStopAndRelease(entry); scope._disposables[i]=nil end
    for k,_ in pairs(scope._scoped) do scope._scoped[k]=nil end
    for k,_ in pairs(scope._perDepTracked) do scope._perDepTracked[k]=nil end
    if not scope._parent then for k,_ in pairs(scope._singletons) do scope._singletons[k]=nil end end
  end

  function scope:Diagnostics()
    local reg = scope._registry
    local counts = { services=0, decorators=0 }
    for _ in pairs(reg.map) do counts.services = counts.services + 1 end
    for _ in pairs(reg.decorators) do counts.decorators = counts.decorators + 1 end
    return {
      tag = scope._tag or 'root',
      isRoot = scope._parent == nil,
      services = counts.services,
      decorators = counts.decorators,
      singletons = scope._root and (function() local c=0 for _ in pairs(scope._root._singletons or {}) do c=c+1 end return c end)() or 0,
      scopedInstances = (function() local c=0 for _ in pairs(scope._scoped or {}) do c=c+1 end return c end)(),
      chainDepth = #scope._resChain,
    }
  end

  return scope
end
M.newScope = newScope

Addon.DI.Scope = M
return M
