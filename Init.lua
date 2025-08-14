-- Streamlined Init using Framework Bootstrap + ServiceRegistry
---@diagnostic disable: undefined-global, invisible, undefined-field
local __params = { ... }
local ADDON_NAME, AddonNamespace = __params[1], __params[2]
local Addon = AddonNamespace or _G[ADDON_NAME] or {}
_G[ADDON_NAME] = Addon

-- Centralized product title (single source of truth)
Addon.TITLE = "Guild Prospector" -- formerly "Guild Recruiter"

-- Attempt to parse our own .toc file once to capture version (avoids manual duplication)
if not Addon.VERSION then
  local tocName = ADDON_NAME .. '.toc'
  local pathCandidates = { tocName, 'Interface/AddOns/' .. ADDON_NAME .. '/' .. tocName }
  local versionFound
  for _, pth in ipairs(pathCandidates) do
    local data = pcall and select(2, pcall(function() return C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, 'Version') end))
    if data and data ~= '' then versionFound = data; break end
  end
  -- Fallback: try global metadata retrieval API (retail / classic differences handled by nil checks)
  if not versionFound and GetAddOnMetadata then
    local v = GetAddOnMetadata(ADDON_NAME, 'Version')
    if v and v ~= '' then versionFound = v end
  end
  Addon.VERSION = versionFound or '0.0.0'
end

local function logBoot(msg)
  local frame = rawget(_G, 'DEFAULT_CHAT_FRAME')
  if frame and frame.AddMessage then frame:AddMessage("|cff66ccff[GuildRecruiter][Boot]|r "..tostring(msg)) end
end

local function runBoot()
  local specs = Addon._ServiceSpecs or {}
  local svc = {}
  for _,s in ipairs(specs) do if type(s.register)=="function" then svc[#svc+1]={ key=s.key, register=s.register, resolve=s.resolve } end end
  if type(Addon.FrameworkBootstrap) == "table" and type(Addon.FrameworkBootstrap.Run) == "function" then
    Addon.FrameworkBootstrap.Run({ services = svc, readyEvent = ADDON_NAME..".Ready", skipResolve = true })
    -- Deferred interface validation
    local after = rawget(_G, 'C_Timer') and C_Timer.After
    if type(after) == "function" then
      after(0.25, function()
        local ok, err = pcall(function() if Addon.ValidateImplementations then Addon.ValidateImplementations() end end)
        if not ok then logBoot("Interface validation error: "..tostring(err)) end
      end)
    end
  else
    logBoot("FrameworkBootstrap missing")
  end
end

local boot = CreateFrame("Frame")
if boot and boot.RegisterEvent and boot.SetScript then
  boot["RegisterEvent"](boot, "ADDON_LOADED")
  boot["SetScript"](boot, "OnEvent", function(_, _, name)
    if name==ADDON_NAME then
      if type(boot.UnregisterEvent) == "function" then boot["UnregisterEvent"](boot, "ADDON_LOADED") end
      local after = rawget(_G,'C_Timer') and C_Timer.After
      if type(after) == "function" then after(0.05, runBoot) else runBoot() end
    end
  end)
end

local shutdown = CreateFrame("Frame")
if shutdown and shutdown.RegisterEvent and shutdown.SetScript then
  shutdown["RegisterEvent"](shutdown, "PLAYER_LOGOUT"); shutdown["RegisterEvent"](shutdown, "PLAYER_LEAVING_WORLD")
  shutdown["SetScript"](shutdown, "OnEvent", function()
  logBoot("Shutdown")
  if not Addon.require then return end
  for _,k in ipairs({"InviteService","Recruiter","Scheduler","Options"}) do local ok, svc = pcall(Addon.require, k); if ok and type(svc)=="table" and type(svc.Stop)=="function" then pcall(svc.Stop, svc); logBoot("✓ "..k.." stopped") end end
  local dispose = true
  do
    local okCfg, cfg = pcall(Addon.require, "Config")
    if okCfg then
      local getter = (type(cfg) == "table") and cfg.Get or nil
      if type(getter) == "function" then
        dispose = (getter(cfg, "disposeContainerOnShutdown", true) ~= false)
      end
    end
  end
  if dispose and Addon.DisposeContainer then pcall(Addon.DisposeContainer); logBoot("✓ Container disposed") end
  end)
end

function Addon.DebugBoot() logBoot("Specs="..tostring(#(Addon._ServiceSpecs or {}))) end

-- Lightweight settings opener (no dependency on removed root Config.lua registration)
if not Addon.OpenSettings then
  function Addon.OpenSettings()
    -- Prefer Blizzard Settings category if previously registered elsewhere
    local Settings = rawget(_G, 'Settings')
    if Settings and Addon._OptionsCategoryID and type(Settings.OpenToCategory) == 'function' then
      pcall(Settings.OpenToCategory, Addon._OptionsCategoryID)
      return
    end
    -- Fallback: open our main UI and select the settings category tab
    local ui = Addon.UI and Addon.UI.Main
    if ui and ui.Show then
      ui:Show()
      if ui.SelectCategoryByKey then pcall(ui.SelectCategoryByKey, ui, 'settings') end
    else
      local frame = _G['GuildRecruiterFrame']
      if frame and frame.Show then frame:Show() end
    end
  end
end
