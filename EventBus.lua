-- EventBus.lua — lightweight pub/sub + WoW event bridge
local ADDON_NAME, Addon = ...

-- Factory function for DI container (no top-level resolves)
local function CreateEventBus()
  local function newBus()
    local self = {}
    local seq = 0
    local handlers = {}          -- [event] = { { token=..., fn=..., ns=... }, ... }
    local tokenIndex = {}        -- [token] = { event=..., idx=... }
    local wowFrame = CreateFrame("Frame")

    local function logErr(msg)
      -- Try to get logger via global access (avoid DI during error handling)
      if Addon.Logger and Addon.Logger.Error then
        pcall(Addon.Logger.Error, Addon.Logger, "{Msg}", { Msg = msg })
      else
        print("|cffff5555[GuildRecruiter][EventBus]|r " .. tostring(msg))
      end
    end

    function self:Publish(ev, ...)
      local list = handlers[ev]
      if not list or #list == 0 then return end
      -- copy to avoid re-entrancy mutation issues
      local snapshot = {}
      for i=1,#list do snapshot[i] = list[i] end
      for i=1,#snapshot do
        local h = snapshot[i]
        if h and h.fn then
          local ok, err = pcall(h.fn, ev, ...)
          if not ok then logErr("Handler error for "..ev..": "..tostring(err)) end
        end
      end
    end

    function self:Subscribe(ev, fn, opts)
      if not ev or type(fn) ~= "function" then return end
      handlers[ev] = handlers[ev] or {}
      seq = seq + 1
      local token = ev..":"..seq
      handlers[ev][#handlers[ev]+1] = { token = token, fn = fn, ns = opts and opts.namespace }
      tokenIndex[token] = { event = ev }
      return token
    end

    function self:Unsubscribe(token)
      local meta = tokenIndex[token]; if not meta then return end
      local ev = meta.event; local list = handlers[ev]; if not list then return end
      for i=#list,1,-1 do if list[i].token == token then table.remove(list, i) end end
      tokenIndex[token] = nil
    end

    function self:UnsubscribeNamespace(ns)
      if not ns then return end
      for ev, list in pairs(handlers) do
        for i=#list,1,-1 do if list[i].ns == ns then table.remove(list, i) end end
      end
    end

    function self:RegisterWoWEvent(ev)
      wowFrame:RegisterEvent(ev)
      return { token = self:Subscribe(ev, function(_, ...) end), event = ev }
    end

    wowFrame:SetScript("OnEvent", function(_, event, ...)
      self:Publish(event, ...)
    end)

    return self
  end

  return newBus()
end

-- Register factory with DI container (when Core is available)
-- This will be called from Init.lua during proper boot sequence
local function RegisterEventBusFactory()
  if not Addon.provide then
    error("EventBus: Addon.provide not available")
  end
  
  Addon.provide("EventBus", CreateEventBus, { lifetime = "SingleInstance" })

  -- Lazy namespace export (safe)
  Addon.EventBus = setmetatable({}, {
    __index = function(_, k) 
      if Addon._booting then
        error("Cannot access EventBus during boot phase")
      end
      local inst = Addon.require("EventBus")
      return inst[k] 
    end,
    __call = function(_, ...) return Addon.require("EventBus"), ... end
  })
end

-- Export the registration function for Init.lua to call
Addon._RegisterEventBus = RegisterEventBusFactory

return RegisterEventBusFactory
