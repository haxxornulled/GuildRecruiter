-- UI.Summary.lua — Summary / landing page
local _, Addon = ...
local M = {}

function M:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints(); f:Hide()
  local g = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  g:SetPoint("TOP", 0, -32)
  local name = GetGuildInfo("player")
  if name then g:SetText(name) else g:SetText("Not in a Guild"); g:SetTextColor(.85,.85,.85) end
  local w = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  w:SetPoint("TOP", g, "BOTTOM", 0, -16); w:SetText("Welcome to Guild Recruiter")
  local h = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  h:SetPoint("TOP", w, "BOTTOM", 0, -10)
  h:SetJustifyH("CENTER")
  h:SetText("• Prospects: live queue from target/mouseover/nameplates\n• Blacklist: do-not-invite list\n• Settings: rotation + messages")
  function f:Render() end
  return f
end

Addon.provide("UI.Summary", M)
return M
