-- Infrastructure/Time/Clock.lua
-- Provides Clock port implementation backed by WoW GetTime()/time().
local Addon = select(2, ...) or {}

local function CreateClock()
  local self = {}
  local getTime = (GetTime or function() return 0 end)
  local epoch = ( (_G and _G.time) and _G.time or function() return math.floor(getTime()) end )
  function self:Now() return getTime() end
  function self:Epoch() return epoch() end
  return self
end

if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('Clock')) then
  Addon.provide('Clock', function() return CreateClock() end, { lifetime = 'SingleInstance' })
end

return CreateClock
