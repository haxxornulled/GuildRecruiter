local ADDON_NAME = ...
if type(ADDON_NAME) ~= 'string' then ADDON_NAME = 'GuildRecruiter' end
local Addon = _G[ADDON_NAME]
if not Addon then Addon = {}; _G[ADDON_NAME] = Addon end
Addon.DI = Addon.DI or {}

local Registration = Addon.DI.Registration -- loaded earlier by TOC
local ScopeMod = Addon.DI.Scope           -- loaded earlier by TOC

local M = {}

function M.BuildContainer(registry)
  local root = ScopeMod.newScope(registry, nil, 'root', nil)
  root._root = root
  function root:DisposeRoot() if not rawget(self,'_isDisposed') then self:Dispose() end end
  return root
end

-- Higher level convenience builder wrapper similar to original Core.Builder
function M.ContainerBuilder()
  local builder, registry = Registration.newBuilder()
  local api = {}
  function api:Register(factory) return builder:Register(factory) end
  function api:Build() local reg = builder._registry or registry; return M.BuildContainer(reg) end
  function api:_commit(rb) builder:_commit(rb); return api end
  api._registry = registry
  return api
end

Addon.DI.Container = M
return M
