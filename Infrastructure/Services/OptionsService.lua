-- Infrastructure/Services/OptionsService.lua
-- Provides a thin Options service abstraction (placeholder) for future expansion.
local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

local function CreateOptionsService()
  local self = {}
  function self:Start() end
  function self:Stop() end
  function self:HandleSlash(msg)
    -- Placeholder: could route into UI.Settings in future.
    local frame = _G["GuildRecruiterFrame"]
    if frame and frame.Show then frame:Show() end
  end
  return self
end

local function RegisterOptionsService()
  if not Addon.provide then error("OptionsService: Addon.provide not available") end
  if not (Addon.IsProvided and Addon.IsProvided("Options")) then
    Addon.provide("Options", CreateOptionsService, { lifetime = "SingleInstance" })
  end
end

Addon._RegisterOptions = RegisterOptionsService
return RegisterOptionsService
