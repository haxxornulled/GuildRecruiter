-- Init.lua — Centralized boot sequence with proper DI container loading
-- MUST BE LOADED LAST in .toc file after all services have registered their functions
local ADDON_NAME, Addon = ...

local function logBoot(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[GuildRecruiter][Boot]|r " .. tostring(msg))
  end
end

local function safe(fn, ...)
  local ok, res = pcall(fn, ...)
  if not ok then 
    logBoot("ERROR: " .. tostring(res))
    return false, res
  end
  return ok, res
end

-- ===========================
-- PHASE 1: Register all service factories
-- ===========================
local function RegisterFactories()
  logBoot("Phase 1: Registering factories...")
  Addon._booting = true -- Prevent lazy facade access during boot
  
  -- Verify Core.lua loaded properly
  if not Addon.provide then
    logBoot("FATAL: Addon.provide not available - Core.lua failed to load")
    return false
  end
  
  if not Addon.Core then
    logBoot("FATAL: Addon.Core not available - Core.lua failed to load")
    return false
  end
  
  -- Register Core first (it provides Addon.provide)
  Addon.provide("Core", function() return Addon.Core end, { lifetime = "SingleInstance" })
  logBoot("✓ Core registered")
  
  -- Debug: Check what registration functions are available
  local available = {}
  local missing = {}
  local registrations = {
  { name = "SavedVarsService", func = Addon._RegisterSavedVarsService },
    { name = "Logger", func = Addon._RegisterLogger },
    { name = "EventBus", func = Addon._RegisterEventBus },
    { name = "Scheduler", func = Addon._RegisterScheduler },
    { name = "Config", func = Addon._RegisterConfig },
    { name = "Recruiter", func = Addon._RegisterRecruiter },
    { name = "InviteService", func = Addon._RegisterInviteService },
    { name = "Options", func = Addon._RegisterOptions },
  }
  
  for _, reg in ipairs(registrations) do
    if reg.func and type(reg.func) == "function" then
      available[#available + 1] = reg.name
    else
      missing[#missing + 1] = reg.name
    end
  end
  
  logBoot("Available registration functions: " .. table.concat(available, ", "))
  if #missing > 0 then
    logBoot("Missing registration functions: " .. table.concat(missing, ", "))
  end
  
  -- Register available services
  local successCount = 0
  for _, reg in ipairs(registrations) do
    if reg.func and type(reg.func) == "function" then
      local ok, err = safe(reg.func)
      if ok then
        logBoot("✓ " .. reg.name .. " factory registered")
        successCount = successCount + 1
      else
        logBoot("✗ " .. reg.name .. " registration failed: " .. tostring(err))
      end
    else
      logBoot("⚠ " .. reg.name .. " registration function not found - file may not have loaded")
    end
  end
  
  logBoot(string.format("Phase 1 complete: %d/%d services registered", successCount, #registrations))
  return successCount > 0 -- Continue if we registered at least some services
end

-- ===========================
-- PHASE 2: Resolve core services (construction)
-- ===========================
local function WarmContainer()
  logBoot("Phase 2: Warming container...")
  
  if not Addon.require then
    logBoot("ERROR: Addon.require not available")
    return false
  end
  
  -- Resolve in dependency order (only try services we know were registered)
  local services = {
  "SavedVarsService", "Logger", "EventBus", "Scheduler", "Config", 
    "Recruiter", "InviteService", "Options"
  }
  
  local successCount = 0
  for _, serviceName in ipairs(services) do
    local ok, instance = safe(Addon.require, serviceName)
    if ok and instance then
      logBoot("✓ " .. serviceName .. " resolved")
      successCount = successCount + 1
    else
      logBoot("⚠ " .. serviceName .. " failed to resolve: " .. tostring(instance))
      -- Don't fail completely - continue with other services
    end
  end
  
  logBoot(string.format("Phase 2 complete: %d/%d services resolved", successCount, #services))
  return successCount > 0
end



-- ===========================
-- Boot orchestration with graceful Start() failure handling
-- ===========================
local function DeferredBoot()
  logBoot("=== Guild Recruiter Boot Sequence ===")
  
  -- Phase 1: Register all service factories
  if not RegisterFactories() then
    logBoot("Boot failed at Phase 1 - aborting")
    return
  end
  
  -- Phase 2: Resolve/construct core services 
  if not WarmContainer() then
    logBoot("Boot failed at Phase 2 - aborting")
    return
  end
  
  -- Phase 3: Start services (graceful failure handling)
  logBoot("Phase 3: Starting services (graceful failure mode)...")
  
  -- End boot phase - allow lazy facade access
  Addon._booting = false
  
  -- Publish services ready event
  local ok, eventBus = safe(Addon.require, "EventBus")
  if ok and eventBus and eventBus.Publish then
    safe(eventBus.Publish, eventBus, "GuildRecruiter.ServicesReady")
    logBoot("✓ ServicesReady event published")
  end
  
  -- Start services with individual error handling (non-blocking)
  local startableServices = { "Scheduler", "Recruiter", "InviteService", "Options" }
  local startedCount = 0
  
  for _, serviceName in ipairs(startableServices) do
    local serviceOk, service = safe(Addon.require, serviceName)
    if serviceOk and service and service.Start then
      local startOk, startErr = safe(service.Start, service)
      if startOk then
        logBoot("✓ " .. serviceName .. " started")
        startedCount = startedCount + 1
      else
        -- PRODUCTION: Log the circular dependency but continue
        if startErr and startErr:find("Circular dependency") then
          logBoot("⚠ " .. serviceName .. " start deferred due to circular dependency")
          
          -- Retry after other services have started
          C_Timer.After(1.0, function()
            local retryOk, retryErr = safe(service.Start, service)
            if retryOk then
              logBoot("✓ " .. serviceName .. " started (retry)")
            else
              logBoot("⚠ " .. serviceName .. " start failed (retry): " .. tostring(retryErr))
            end
          end)
        else
          logBoot("✗ " .. serviceName .. " start failed: " .. tostring(startErr))
        end
      end
    elseif serviceOk and service then
      logBoot("⚠ " .. serviceName .. " has no Start method")
      startedCount = startedCount + 1 -- Count as success
    end
  end
  
  -- Final readiness signal (always fire - addon is functional)
  if ok and eventBus and eventBus.Publish then
    safe(eventBus.Publish, eventBus, "GuildRecruiter.Ready")
    logBoot("✓ Ready event published")
  end
  
  logBoot(string.format("Phase 3 complete: %d/%d services started", startedCount, #startableServices))
  logBoot("Guild Recruiter ready! (Start() issues are non-blocking)")
  logBoot("=== Boot Sequence Complete ===")
end

-- ===========================
-- Addon loading event handler
-- ===========================
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
  if name == ADDON_NAME then
    boot:UnregisterEvent("ADDON_LOADED")
    
    -- Small delay to ensure all files have finished loading
    C_Timer.After(0.1, DeferredBoot)
  end
end)

-- ===========================
-- Shutdown handling
-- ===========================
local shutdown = CreateFrame("Frame")
shutdown:RegisterEvent("PLAYER_LOGOUT")
shutdown:RegisterEvent("PLAYER_LEAVING_WORLD")
shutdown:SetScript("OnEvent", function()
  logBoot("Shutting down services...")
  
  if not Addon.require then return end
  
  local services = { "InviteService", "Recruiter", "Scheduler" }
  for _, serviceName in ipairs(services) do
    local ok, service = safe(Addon.require, serviceName)
    if ok and service and service.Stop then
      safe(service.Stop, service)
      logBoot("✓ " .. serviceName .. " stopped")
    end
  end
end)

-- Debug function for manual inspection
function Addon.DebugBoot()
  logBoot("=== Debug Boot Status ===")
  logBoot("Addon.provide available: " .. tostring(Addon.provide ~= nil))
  logBoot("Addon.require available: " .. tostring(Addon.require ~= nil))
  logBoot("Addon.Core available: " .. tostring(Addon.Core ~= nil))
  
  local regFuncs = {
    "_RegisterLogger", "_RegisterEventBus", "_RegisterScheduler", 
    "_RegisterConfig", "_RegisterRecruiter", "_RegisterInviteService", "_RegisterOptions"
  }
  
  for _, funcName in ipairs(regFuncs) do
    local func = Addon[funcName]
    logBoot(funcName .. ": " .. tostring(type(func)))
  end
  logBoot("=== End Debug ===")
end
