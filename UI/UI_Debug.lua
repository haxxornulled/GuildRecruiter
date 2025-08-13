-- UI_Debug.lua — A lightweight debug page that plugs into UI.Main
---@diagnostic disable: undefined-global, undefined-field
local __args = { ... }
local ADDON_NAME, Addon = __args[1], (__args[2] or _G[__args[1]] or {})

local M = {}

function M:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 10, -10)
  title:SetText("Debug")

  -- Basic diagnostics: list registered DI keys
  local list = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  list:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  list:SetJustifyH("LEFT")
  list:SetText("")

  local function render()
    local keys = (Addon.ListRegistered and Addon.ListRegistered()) or {}
    local lines = { string.format("%d registered services:", #keys) }
    for i=1,math.min(#keys, 200) do lines[#lines+1] = keys[i] end
    list:SetText(table.concat(lines, "\n"))
  end

  function f:Render() render() end
  render()
  return f
end

-- Provide module under UI.Debug for UI_MainFrame to attach lazily
if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('UI.Debug')) then
  Addon.provide('UI.Debug', M, { lifetime = 'SingleInstance' })
end

return M
