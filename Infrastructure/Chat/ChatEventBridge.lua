-- Infrastructure/Chat/ChatEventBridge.lua
-- Bridges WoW CHAT_MSG_* events via EventBus into Application.ChatFeed
---@diagnostic disable: undefined-global
local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})

local function CreateChatEventBridge(scope)
  local self = {}
  -- Avoid building container here: prefer Get/Peek
  local Bus = (Addon.Get and Addon.Get('EventBus')) or (Addon.Peek and Addon.Peek('EventBus'))
  local Feed = (scope and scope.Resolve and scope:Resolve('ChatFeed')) or (Addon.Get and Addon.Get('ChatFeed')) or (Addon.Peek and Addon.Peek('ChatFeed'))
  if not (Bus and Feed) then return self end

  local EVENTS = {
    WHISPER = 'CHAT_MSG_WHISPER',
    GUILD   = 'CHAT_MSG_GUILD',
    SAY     = 'CHAT_MSG_SAY',
    SYSTEM  = 'CHAT_MSG_SYSTEM',
  }

  local function onChat(ev, ...)
    -- Common WoW signature: text, author, languageName, channelName, target, flags, _, channelNumber, channelName2, _, counter, guid
    local text = select(1, ...) or ''
    local author = select(2, ...) or ''
    local guid = select(12, ...)
    local channel = 'SYSTEM'
    if ev == EVENTS.WHISPER then channel = 'WHISPER'
    elseif ev == EVENTS.GUILD then channel = 'GUILD'
    elseif ev == EVENTS.SAY then channel = 'SAY'
    elseif ev == EVENTS.SYSTEM then channel = 'SYSTEM' end
    local now = (rawget(_G, 'time') and _G.time()) or 0
    local msg = { channel = channel, author = author, text = text, time = now, meta = { guid = guid, ev = ev } }
    if Feed and Feed.OnIncomingMessage then pcall(Feed.OnIncomingMessage, Feed, msg) end
  end

  for _, ev in pairs(EVENTS) do
    if Bus.RegisterWoWEvent then Bus:RegisterWoWEvent(ev) end
    if Bus.Subscribe then Bus:Subscribe(ev, onChat, { namespace = 'ChatEventBridge' }) end
  end

  function self:Stop()
    if Bus and Bus.UnsubscribeNamespace then Bus:UnsubscribeNamespace('ChatEventBridge') end
  end

  return self
end

if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('ChatEventBridge')) then
  Addon.provide('ChatEventBridge', function(scope) return CreateChatEventBridge(scope) end, { lifetime = 'SingleInstance', meta = { area='chat', role='bridge' } })
end

return CreateChatEventBridge
