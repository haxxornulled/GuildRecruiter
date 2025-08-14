-- WoW loads files with ... = addonName, (optional table). Fall back to folder name if absent.
local ADDON_NAME = ...
if type(ADDON_NAME) ~= 'string' then ADDON_NAME = 'GuildRecruiter' end
local Addon = _G[ADDON_NAME]
if not Addon then Addon = {}; _G[ADDON_NAME] = Addon end
Addon.DI = Addon.DI or {}

local M = {}

-- Utilities (kept local; exposed selectively if needed elsewhere)
local function new_id_gen(prefix)
  local c = 0
  return function() c = c + 1; return (prefix or 'id')..":"..c end
end
local newRegId = new_id_gen('reg')

local function is_callable(v)
  if type(v) == 'function' then return true end
  local mt = getmetatable(v); return mt and type(mt.__call)=='function'
end

function M.newRegistry()
  return { regs={}, map={}, decorators={}, order={} }
end

local function newRegistrationBuilder(registry, factory)
  local reg = {
    id = newRegId(), factory=factory, services={}, lifetime='InstancePerDependency', parameters={}, meta={},
    events = { OnPreparing=nil, OnActivating=nil, OnActivated=nil, OnRelease=nil },
    isDecorator=false, decoratesKey=nil, asSelfKey=nil,
  }
  local rb = {}
  function rb:As(key) reg.services[key]=true; return self end
  function rb:AsSelf() reg.asSelfKey=reg.factory; reg.services[reg.asSelfKey]=true; return self end
  function rb:SingleInstance() reg.lifetime='SingleInstance'; return self end
  function rb:InstancePerDependency() reg.lifetime='InstancePerDependency'; return self end
  function rb:InstancePerLifetimeScope() reg.lifetime='InstancePerLifetimeScope'; return self end
  function rb:WithParameter(name, value) reg.parameters[name]=value; return self end
  function rb:WithMetadata(name, value) reg.meta[name]=value; return self end
  function rb:WithMetadataTable(tbl) for k,v in pairs(tbl) do reg.meta[k]=v end return self end
  function rb:OnPreparing(fn) reg.events.OnPreparing=fn; return self end
  function rb:OnActivating(fn) reg.events.OnActivating=fn; return self end
  function rb:OnActivated(fn) reg.events.OnActivated=fn; return self end
  function rb:OnRelease(fn) reg.events.OnRelease=fn; return self end
  function rb:AsDecorator(key) reg.isDecorator=true; reg.decoratesKey=key; return self end
  function rb:_commit()
    registry.regs[reg.id]=reg; registry.order[#registry.order+1]=reg.id
    if reg.decoratesKey then
      local arr=registry.decorators[reg.decoratesKey]; if not arr then arr={}; registry.decorators[reg.decoratesKey]=arr end
      arr[#arr+1]=reg.id
    else
      for key,_ in pairs(reg.services) do
        local arr = registry.map[key]; if not arr then arr={}; registry.map[key]=arr end; arr[#arr+1]=reg.id
      end
    end
  end
  return rb, reg
end
M.newRegistrationBuilder = newRegistrationBuilder

function M.newBuilder()
  local registry = M.newRegistry()
  local builder = {}
  function builder:Register(factory)
    if not is_callable(factory) then error('Register(factory) requires callable') end
    return newRegistrationBuilder(registry, factory)
  end
  function builder:RegisterInstance(key, instance)
    local rb = newRegistrationBuilder(registry, function() return instance end)
    rb:As(key):SingleInstance(); rb:_commit(); return rb
  end
  function builder:Build() return registry end -- container wiring happens in Container module
  function builder:_commit(rb) rb:_commit(); return builder end
  builder._registry = registry
  return builder, registry
end

Addon.DI.Registration = M

return M
