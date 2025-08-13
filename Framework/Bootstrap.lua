-- Framework/Bootstrap.lua
-- Reusable minimal bootstrap for WoW addon architecture (DI + Common Services)
-- Copy this file (and Core directory + Infrastructure adapters you want) into a new addon to scaffold.

local __params = { ... }
local ADDON_NAME, Addon = __params[1], __params[2]
Addon = Addon or _G[ADDON_NAME] or {}
_G[ADDON_NAME] = Addon

-- Expect Core/Core.lua already loaded (defines Addon.provide/require)
local function log(msg)
    local frame = rawget(_G, 'DEFAULT_CHAT_FRAME')
    if frame and frame.AddMessage then frame:AddMessage("|cff55aaee[" .. ADDON_NAME .. ":Boot]|r " .. tostring(msg)) end
end

local Bootstrap = {}
Addon.FrameworkBootstrap = Bootstrap

---@class FrameworkServiceSpec
---@field key string
---@field register fun()  # function that registers DI factory (idempotent)
---@field resolve boolean|nil  # optional eager resolve (discouraged; prefer lazy)

---@class FrameworkConfig
---@field services FrameworkServiceSpec[]
---@field publishReady boolean|nil
---@field readyEvent string|nil  # default: ADDON_NAME..".Ready"
---@field skipResolve boolean|nil # when true, do not perform any eager resolves even if spec.resolve=true

--- Perform a structured boot with phases.
---@param cfg FrameworkConfig
function Bootstrap.Run(cfg)
    cfg = cfg or {}
    local services = cfg.services or {}
    Addon._booting = true
    log("Phase 1: Register factories")
    for _, spec in ipairs(services) do
        local ok, err = pcall(spec.register)
        if ok then
            log("✓ Registered " .. spec.key)
        else
            log("✗ Failed " .. spec.key .. ": " .. tostring(err))
        end
    end
    -- Build the DI container (lazily) so diagnostics like ListRegistered can see keys.
    -- This keeps behavior lazy for all other services while ensuring Core._container exists.
    do
        local okBuild, errBuild = pcall(function()
            if type(Addon.require) == "function" then
                Addon.require("Core") -- minimal resolve triggers container build
            end
        end)
        if okBuild then
            log("✓ Container built")
        else
            log("⚠ Container build failed: " .. tostring(errBuild))
        end
    end
    if cfg.skipResolve then
        log("Phase 2: Eager resolve skipped (lazy by default)")
    else
        log("Phase 2: Optional eager resolve")
        for _, spec in ipairs(services) do
            if spec.resolve then
                local rok, inst = pcall(Addon.require, spec.key)
                if rok and inst then
                    log("✓ Resolved " .. spec.key)
                else
                    log("⚠ Resolve " .. spec.key .. " failed: " .. tostring(inst))
                end
            end
        end
    end
    Addon._booting = false
    log("Phase 3: Start (call .Start if present)")
    for _, spec in ipairs(services) do
        local sok, inst = pcall(Addon.require, spec.key)
        if sok and inst and type(inst.Start) == "function" then
            local sOk, sErr = pcall(inst.Start, inst)
            if sOk then
                log("✓ Started " .. spec.key)
            else
                log("✗ Start failed " .. spec.key .. ": " .. tostring(sErr))
            end
        end
    end
    -- Optional phase 3.5: Publish a services-registered (but not necessarily started) event
    do
        local evt = ADDON_NAME .. ".ServicesReady"
        local bok, bus = pcall(Addon.require, "EventBus")
        if bok and type(bus) == "table" and type(bus.Publish) == "function" then
            pcall(bus.Publish, bus, evt)
            log("✓ Published services-ready event " .. evt)
        end
    end
    if cfg.publishReady ~= false then
        local evt = cfg.readyEvent or (ADDON_NAME .. ".Ready")
        local bok, bus = pcall(Addon.require, "EventBus")
        if bok and type(bus) == "table" and type(bus.Publish) == "function" then
            pcall(bus.Publish, bus, evt)
            log("✓ Published ready event " .. evt)
        end
    end
    log("Boot complete")
end

return Bootstrap
