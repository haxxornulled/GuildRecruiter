local __args = { ... }
local ADDON_NAME, Addon = __args[1], (__args[2] or _G[__args[1]] or {})

-- Never build the container at file load; defer until CategoryManager is present.
local function SafeManager()
    -- Prefer interface (legacy recruiter removed)
    local okM, m = pcall(function() return Addon.require and Addon.require("IProspectManager") end); if okM and m then return m end
end

local function CountProspects()
    local m = SafeManager(); if not m or not m.GetAllGuids then return 0 end
    local ok, res = pcall(m.GetAllGuids, m); if ok and type(res) == "table" then return #res end; return 0
end

local function CountBlacklist()
    local m = SafeManager(); if not m then return 0 end
    if m.GetBlacklist then
        local ok, bl = pcall(m.GetBlacklist, m); if ok and type(bl) == "table" then
            local c = 0; for _ in pairs(bl) do c = c + 1 end; return c
        end
    end
    return 0
end

local function FormatSuffix(count)
    if count <= 0 then return "" end
    return string.format(" |cffffaa33(%d)|r", count)
end

local function CountGuildOnline()
    local count = 0
    pcall(function()
        if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
            local n = GetNumGuildMembers() or 0
            for i = 1, n do
                local r1, r2, r3, r4, r5, r6, r7, r8, r9 = GetGuildRosterInfo(i)
                if r9 then count = count + 1 end
            end
        end
    end)
    return count
end

-- Event driven attachment & coalesced refreshing (replaces 5s polling)
---@diagnostic disable: undefined-global
local attached = false
local pending = false
local lastApply = 0
local MIN_INTERVAL = 2 -- seconds between forced applies when spammed
local MAX_SUBSCRIBE_ATTEMPTS = 12 -- configurable backoff attempts (6s total default)

local function ApplyAndRefresh()
    local CM = (Addon.Peek and (Addon.Peek("UI.CategoryManager") or Addon.Peek("Tools.CategoryManager")))
    if not CM or not (CM.ApplyDecorators and CM.RegisterCategoryDecorator) then return end
    if not attached then
        pcall(CM.RegisterCategoryDecorator, CM, "prospects", function() return FormatSuffix(CountProspects()) end)
        pcall(CM.RegisterCategoryDecorator, CM, "blacklist", function() return FormatSuffix(CountBlacklist()) end)
        pcall(CM.RegisterCategoryDecorator, CM, "roster", function() return FormatSuffix(CountGuildOnline()) end)
        attached = true
    end
    pcall(CM.ApplyDecorators, CM)
    if Addon.UI then
        local mainUI = Addon.UI.Main or Addon.UI.main or Addon.UI.MAIN
        if mainUI and mainUI.RefreshCategories then pcall(mainUI.RefreshCategories, mainUI) end
    end
    lastApply = GetTime and GetTime() or 0
end

local function QueueRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        local now = GetTime and GetTime() or 0
        if now - lastApply >= MIN_INTERVAL then
            ApplyAndRefresh()
        else
            local delay = (MIN_INTERVAL - (now - lastApply)) + 0.05
            C_Timer.After(delay, function() ApplyAndRefresh() end)
        end
    end)
end

-- Hook game / addon events that affect counts
local function EnsureEventBusRegistered()
    if Addon and Addon._RegisterEventBus then
        local ok = pcall(function() Addon._RegisterEventBus() end)
        -- ignore errors; bootstrap may run later
    end
end

local subscribed = false
local function TrySubscribeBus(attempt)
    if subscribed then return end
    attempt = (attempt or 0) + 1
    EnsureEventBusRegistered()
    local bus
    -- Avoid forcing container build by using pcall on Addon.require
    if Addon and Addon.require then
        local ok, inst = pcall(Addon.require, 'EventBus')
        if ok and inst and inst.Subscribe then bus = inst end
    end
    if not bus and Addon and Addon.EventBus and getmetatable(Addon.EventBus) then
        -- Attempt lazy accessor (may throw if booting)
        local ok, _ = pcall(function() return Addon.EventBus.ListEvents and Addon.EventBus:ListEvents() end)
        if ok then bus = Addon.require and Addon.require('EventBus') or nil end
    end
    if bus and bus.Subscribe then
        -- Try resolving events constants without forcing hard failure; fall back to raw string
        local E = nil
        if Addon.ResolveOptional then
            local ok, ev = pcall(Addon.ResolveOptional, 'Events')
            if ok then E = ev end
        end
        local prospectChanged = (E and E.Prospects and E.Prospects.Changed) or 'Prospects.Changed'
        bus:Subscribe(prospectChanged, function() QueueRefresh() end)
        bus:Subscribe('CategoriesChanged', function() QueueRefresh() end)
        subscribed = true
        QueueRefresh()
    else
        if attempt < MAX_SUBSCRIBE_ATTEMPTS then
            C_Timer.After(0.5, function() TrySubscribeBus(attempt) end)
        end
    end
end

C_Timer.After(0.2, TrySubscribeBus)

-- Guild roster update affects roster count
local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterFrame:SetScript("OnEvent", function() QueueRefresh() end)

-- Fallback slow ticker (manual re-arm every 60s) to catch any missed edge
local function StartFallbackTicker()
    C_Timer.After(60, function()
        QueueRefresh()
        StartFallbackTicker()
    end)
end
C_Timer.After(5, function()
    ApplyAndRefresh()
    StartFallbackTicker()
end)
