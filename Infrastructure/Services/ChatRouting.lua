-- Infrastructure/Services/ChatRouting.lua
-- Guard-railed chat/addon message routing across Retail/Classic API variants.
-- luacheck: push ignore 113 212/SendAddonMessage 212/RegisterAddonMessagePrefix 212/IsInGuild
local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})

local function CreateChatRouting()
  local self = {}

  local C_ChatInfo = _G.C_ChatInfo
  local SendAddonMessage = rawget(_G, 'SendAddonMessage')
  local RegisterAddonMessagePrefix = rawget(_G, 'RegisterAddonMessagePrefix')

  local function hasCChat()
    return type(C_ChatInfo) == 'table'
  end

  local function tryRegister(prefix)
    if not prefix or prefix == '' then return true end
    if hasCChat() and type(C_ChatInfo.RegisterAddonMessagePrefix) == 'function' then
      local ok = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
      return ok ~= false
    elseif type(RegisterAddonMessagePrefix) == 'function' then
      local ok = RegisterAddonMessagePrefix(prefix)
      return ok ~= false
    end
    return true
  end

  -- Normalize channel and call the best API available
  function self:SendAddon(prefix, message, channel, target)
    prefix = tostring(prefix or ADDON_NAME or 'GR')
    if not tryRegister(prefix) then return false, 'prefix_register_failed' end
    message = tostring(message or '')
    channel = channel or 'GUILD'

    if hasCChat() and type(C_ChatInfo.SendAddonMessage) == 'function' then
      -- Retail signature: (prefix, message, channel[, target])
      local ok, err = pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
      if ok then return true end
      return false, err
    elseif type(SendAddonMessage) == 'function' then
      -- Classic signature compatible with same params
      local ok, err = pcall(SendAddonMessage, prefix, message, channel, target)
      if ok then return true end
      return false, err
    end
    return false, 'no_send_api'
  end

  function self:SendChat(message, chatType, target)
    chatType = chatType or 'SAY'
    if type(_G.SendChatMessage) == 'function' then
      local ok, err = pcall(_G.SendChatMessage, tostring(message or ''), chatType, nil, target)
      if ok then return true end
      return false, err
    end
    return false, 'no_chat_api'
  end

  function self:RegisterPrefix(prefix)
    return tryRegister(prefix)
  end

  -- Small helper to detect best addon channel (fall back to SAY for debug)
  function self:PreferredAddonChannel()
    local ok, inGuild = pcall(function()
      local fn = rawget(_G, 'IsInGuild')
      if type(fn) == 'function' then return fn() end
      return false
    end)
    if ok and inGuild then return 'GUILD' end
    return 'SAY'
  end

  return self
end

if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('ChatRouting')) then
  Addon.provide('ChatRouting', function() return CreateChatRouting() end, { lifetime = 'SingleInstance' })
end

return CreateChatRouting
