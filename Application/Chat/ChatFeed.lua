-- Application/Chat/ChatFeed.lua
-- IChatFeed implementation: manages subscribers, filters, and sends via ChatRouting.
-- luacheck: push ignore 113
local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})

local function CreateChatFeed(scope)
  local self = {}

  local eventBus = Addon.Get and Addon.Get('EventBus') -- optional; could be used later for message events
  -- Lazily resolve ChatRouting to tolerate boot order
  local router = nil
  local function resolveRouter()
    if router and type(router.SendChat) == 'function' then return router end
    -- Try scope first
    if scope and scope.Resolve then
      local ok, r = pcall(scope.Resolve, scope, 'ChatRouting')
      if ok and r and r.SendChat then router = r; return router end
    end
    -- Then container
    if Addon.Get then
      local r = Addon.Get('ChatRouting')
      if r and r.SendChat then router = r; return router end
    end
    -- Last resort, require (constructor returns instance via provider side-effect or factory)
    if Addon.require then
      pcall(Addon.require, 'ChatRouting')
      if Addon.Get then
        local r = Addon.Get('ChatRouting')
        if r and r.SendChat then router = r; return router end
      end
    end
    return nil
  end
  local SV = Addon.Get and Addon.Get('SavedVarsService')

  local subscribers = {}
  local defaultFilters = { WHISPER=true, GUILD=true, SAY=false, SYSTEM=true }
  local filters = {}
  -- Observed author->guid cache from incoming messages
  local nameGuid = {}
  -- Load persisted filters (namespace 'ui', key 'chatFilters')
  do
    local persisted = SV and SV.Get and SV:Get('ui', 'chatFilters', nil) or nil
    if type(persisted) == 'table' then
      for k,v in pairs(defaultFilters) do filters[k] = (persisted[k] ~= nil) and not not persisted[k] or v end
    else
      for k,v in pairs(defaultFilters) do filters[k] = v end
    end
  end

  function self:Subscribe(handler)
    if type(handler) ~= 'function' then return function() end end
    subscribers[#subscribers+1] = handler
    local active = true
    return function()
      if not active then return end
      active = false
      for i=1,#subscribers do
        if subscribers[i] == handler then table.remove(subscribers, i) break end
      end
    end
  end

  function self:GetFilters()
    local copy = {}
    for k,v in pairs(filters) do copy[k] = v end
    return copy
  end

  function self:SetFilters(f)
    if type(f) ~= 'table' then return end
    filters = {}
    for k,v in pairs(f) do filters[tostring(k)] = not not v end
  if SV and SV.Set then SV:Set('ui', 'chatFilters', filters); if SV.Sync then SV:Sync() end end
  end

  function self:GetGuidForName(name)
    if type(name) ~= 'string' or name == '' then return nil end
    local key = name:lower()
    -- also try without realm suffix if provided
    local bare = key:match('^([^%-]+)') or key
    return nameGuid[key] or nameGuid[bare] or nil
  end

  local function broadcast(msg)
    for i=1,#subscribers do
      local h = subscribers[i]
      local ok = pcall(h, msg)
      if not ok then -- swallow handler errors
      end
    end
  end

  -- Accept a normalized message shape from Infrastructure bridges
  function self:OnIncomingMessage(msg)
    if not msg or type(msg) ~= 'table' then return end
    local ch = tostring(msg.channel or '')
    if ch ~= '' and filters[ch] == false then return end
    -- Learn name->guid mapping from meta when available
    local a = msg.author; local meta = msg.meta
    local guid = meta and meta.guid or nil
    if type(a) == 'string' and a ~= '' and type(guid) == 'string' and guid ~= '' then
      local k = a:lower(); nameGuid[k] = guid; nameGuid[(k:match('^([^%-]+)') or k)] = guid
    end
    broadcast(msg)
  end

  function self:Send(target, text, opts)
    opts = opts or {}
    local chatType = opts.chatType or 'WHISPER'
    local r = resolveRouter()
    if not (r and r.SendChat) then return false, 'router_unavailable' end
    return r:SendChat(text, chatType, target)
  end

  return self
end

if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('ChatFeed')) then
  Addon.provide('ChatFeed', function(scope) return CreateChatFeed(scope) end, { lifetime = 'SingleInstance', meta = { area = 'chat', role = 'app-feed' } })
  -- Provide interface alias for future use (safe even if safeProvide isn't available yet)
  if Addon.safeProvide then
    Addon.safeProvide('IChatFeed', function(sc) return sc:Resolve('ChatFeed') end, { lifetime = 'SingleInstance', meta = { area = 'chat', role = 'iface' } })
  elseif Addon.provide and not (Addon.IsProvided and Addon.IsProvided('IChatFeed')) then
    pcall(Addon.provide, 'IChatFeed', function(sc) return sc:Resolve('ChatFeed') end, { lifetime = 'SingleInstance', meta = { area = 'chat', role = 'iface' } })
  end
end

return CreateChatFeed
-- luacheck: pop
