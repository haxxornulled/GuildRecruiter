-- Application/SlashCommandHandler.lua
-- Concrete implementation for slash commands, delegating to services/UI
---@diagnostic disable: undefined-global

local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})

local Handler = {}
Handler.__index = Handler

local function printf(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[%s]|r %s"):format(ADDON_NAME or "GR", tostring(msg))) end
end

local function Args(msg)
  local t = {}; if not msg then return t end
  for w in tostring(msg):gmatch("%S+") do t[#t+1] = w end
  return t
end

-- Dependencies via container
local function UI() return Addon.UI or (Addon.require and Addon.require("UI.Main")) end
local function CFG() return (Addon.require and Addon.require("IConfiguration")) or (Addon.Get and Addon.Get("IConfiguration")) end
local function Provider()
  if Addon.Get then return Addon.Get("IProspectsReadModel") end
end
local function Recruiter() return Addon.Get and Addon.Get("Recruiter") end
local function ProspectManager() return (Addon.Get and (Addon.Get('IProspectManager') or Addon.Get('ProspectsManager'))) end

function Handler.new()
  return setmetatable({}, Handler)
end

function Handler:Help()
  return {
    " /gr ui|toggle        - Open the main UI",
    " /gr settings         - Open settings panel",
  " /gr roster           - Open the Guild Roster panel",
  " /gr log [toggle|show|hide|clear] - Log console",
    " /gr messages add N   - Add rotation message N (creates new section)",
    " /gr messages remove N- Remove rotation message N ( >3 core protected)",
    " /gr messages list    - List existing rotation message indices",
    " /gr devmode [on|off|toggle] - Show/hide Debug tab",
    " /gr prune prospects N- Keep newest N prospects (persist removal)",
    " /gr prune blacklist N- Keep newest N blacklist entries",
    " /gr queue dedupe     - Remove duplicate queue entries",
  " /gr stats            - Quick prospect/queue/blacklist stats snapshot",
  " /gr diag layers      - List registrations grouped by layer (heuristic)",
  }
end

function Handler:Handle(msg)
  msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" or msg == "ui" or msg == "toggle" then
    local ui = UI(); if ui and ui.Show then ui:Show() else printf("Main UI not ready yet.") end; return
  elseif msg == "roster" then
    local ui = UI(); if not ui then printf("UI not ready yet."); return end
    -- Ensure category exists then select it
    if ui.AddCategory then pcall(ui.AddCategory, ui, { key = "roster", label = "Guild Roster", order = 15 }) end
    if ui.SelectCategoryByKey then pcall(ui.SelectCategoryByKey, ui, "roster") end
    if ui.Show then pcall(ui.Show, ui) end
    return
  elseif msg == "settings" or msg == "options" then
    local id = Addon._OptionsCategoryID or "Guild Recruiter"
    if Settings and Settings.OpenToCategory then Settings.OpenToCategory(id) else printf("Settings not available.") end
    return
  elseif msg:match("^messages") then
    local parts = Args(msg)
    local sub = tostring(parts[2] or "")
    if sub == "" or sub == "help" then printf("Messages: add <n>, remove <n>, list"); return end
    local settingsMod = Addon.require and Addon.require("UI.Settings")
    if not settingsMod then printf("Settings UI not loaded yet"); return end
    local actions = {}
    actions.add = function()
      local n = tonumber(parts[3]); if not n then printf("Usage: /gr messages add <n>"); return end
      local ok, res = pcall(settingsMod.AddMessage, settingsMod, n); printf(ok and res or ("Error: "..tostring(res)))
    end
    actions.remove = function()
      local n = tonumber(parts[3]); if not n then printf("Usage: /gr messages remove <n>"); return end
      local ok, res = pcall(settingsMod.RemoveMessage, settingsMod, n); printf(ok and res or ("Error: "..tostring(res)))
    end
    actions.list = function()
      local ok, list = pcall(settingsMod.ListMessages, settingsMod)
      if ok and type(list)=="table" then printf("Messages: "..table.concat(list, ", ")) else printf("No messages.") end
    end
    local fn = actions[sub]
    if fn then fn() else printf("Usage: /gr messages [add <n>|remove <n>|list]") end
    return
  elseif msg:match("^log") then
    local parts = Args(msg); local action = tostring(parts[2] or "toggle")
    local console = (Addon.require and Addon.require('UI.LogConsole')) or (Addon.Get and Addon.Get('UI.LogConsole'))
    if not console then printf("Log console not available"); return end
    local act = {}
    act.toggle = function()
      local ui = console
      if ui and ui._frame and ui._frame.IsShown then
        local ok, shown = pcall(ui._frame.IsShown, ui._frame)
        if ok and shown then ui:Hide() else ui:Show() end
      else ui:Show() end
    end
    act.show = function() console:Show() end
    act.hide = function() console:Hide() end
    act.clear = function() console:Clear() end
    (act[action] or act.toggle)()
    return
  elseif msg:match("^devmode") then
    local cfg = CFG(); if not cfg then printf("Config not ready."); return end
    local parts = Args(msg); local mode = parts[2]
    if mode == "on" then cfg:Set("devMode", true); printf("Dev mode: ON")
    elseif mode == "off" then cfg:Set("devMode", false); printf("Dev mode: OFF")
    elseif mode == "toggle" or not mode then local new = not cfg:Get("devMode", false); cfg:Set("devMode", new); printf("Dev mode toggled: "..(new and "ON" or "OFF"))
    else printf("Usage: /gr devmode [on|off|toggle]"); return end
    local ui = UI(); if ui and ui.RefreshCategories then pcall(ui.RefreshCategories, ui) end
    if ui and ui.SelectCategoryByKey and not cfg:Get("devMode", false) then ui:SelectCategoryByKey("summary") end
    if ui and ui.ShowToast then pcall(ui.ShowToast, ui, cfg:Get("devMode", false) and "Dev Mode ENABLED" or "Dev Mode DISABLED") end
    return
  elseif msg:match("^prune") then
    local parts = Args(msg); local which = parts[2]; local limit = tonumber(parts[3]) or 0
  local pm = ProspectManager(); if not pm then printf("ProspectManager not ready"); return end
  if which == "prospects" then local removed = pm:PruneProspects(limit); printf("Pruned prospects removed="..removed.." kept="..limit)
  elseif which == "blacklist" then local removed = pm:PruneBlacklist(limit); printf("Pruned blacklist removed="..removed.." kept="..limit)
    else printf("Usage: /gr prune prospects <N> | blacklist <N>") end
    return
  elseif msg == "queue fix" or msg == "queue dedupe" then
    local rec = Recruiter(); if not rec then printf("Recruiter not ready"); return end
    local before = #rec:GetQueue(); local q = rec:GetQueue(); local seen, newQ = {}, {}
    for _,guid in ipairs(q) do if not seen[guid] then seen[guid]=true; newQ[#newQ+1]=guid end end
    local ok, err = pcall(function() _G["GuildRecruiterDB"].queue = newQ end)
    local after = #newQ
    printf("Queue deduped: before="..before.." after="..after..(ok and "" or (" error="..tostring(err))))
    return
  elseif msg == "stats" then
    local provider = Provider(); local pm = ProspectManager(); local rec = Recruiter()
    if provider and provider.GetStats and pm and rec then
      local st = provider:GetStats() or {}; local blCount = 0; local bl = pm:GetBlacklist(); for _ in pairs(bl or {}) do blCount=blCount+1 end
      printf(string.format("Prospects=%d Active=%d Blacklist=%d Queue=%d AvgLevel=%.1f", st.total or 0, (st.active and st.active.total) or (st.total or 0), blCount, #rec:GetQueue(), st.avgLevel or 0))
    else printf("Stats unavailable (provider or manager not ready)") end
    return
  elseif msg == "diag layers" or msg == "diag" then
    local AddonNs = Addon
    local keys = (AddonNs.ListRegistered and AddonNs.ListRegistered()) or {}
    local groups = { UI = {}, Infrastructure = {}, Core = {}, Application = {}, Other = {} }
    -- Prefer metadata grouping when available
  local metaFor = AddonNs.GetRegistrationMetadata or function(_) return {} end
    for _,k in ipairs(keys) do
      local metas = metaFor(k)
      local placed = false
      for _,entry in ipairs(metas) do
        local m = entry.meta or {}
        local layer = m.layer
        if layer and groups[layer] then table.insert(groups[layer], k); placed = true; break end
      end
      if not placed then
        local s = tostring(k)
        if s:match("^UI[%./]") then table.insert(groups.UI, k)
        elseif s:match("^Infrastructure[%./]") or s:match("^LogSink") or s:match("^LevelSwitch") then table.insert(groups.Infrastructure, k)
        elseif s:match("^Core$") or s:match("^Collections[%.]") or s:match("^Levels$") then table.insert(groups.Core, k)
        elseif s:match("^Application[%./]") or s:match("^IProspectManager$") then table.insert(groups.Application, k)
        else table.insert(groups.Other, k) end
      end
    end
    local function printGroup(name, arr)
      table.sort(arr)
      printf(name.." ("..tostring(#arr).."):")
      local line = {}
      for i,kk in ipairs(arr) do
        line[#line+1] = kk
        if #line >= 6 or i == #arr then
          printf("  - "..table.concat(line, ", "))
          line = {}
        end
      end
    end
    printGroup("Core", groups.Core)
    printGroup("Infrastructure", groups.Infrastructure)
    printGroup("Application", groups.Application)
    printGroup("UI", groups.UI)
    printGroup("Other", groups.Other)
    return
  elseif msg == "help" then
    for _,line in ipairs(self:Help()) do printf(line) end
    return
  end
  printf("Unknown command. Try /gr help.")
end

if Addon.provide then
  Addon.provide("Application.SlashCommandHandler", Handler, { lifetime = "SingleInstance", meta = { layer = 'Application', area = 'ui/commands' } })
  -- Interface aliases for resolution by contract
  Addon.provide("ISlashCommandHandler", Handler, { lifetime = "SingleInstance", meta = { layer = 'Application', area = 'ui/commands', alias = true } })
end
return Handler
