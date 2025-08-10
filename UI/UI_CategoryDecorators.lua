-- UI_CategoryDecorators.lua — attach dynamic decorators (counts) to categories
local ADDON_NAME, Addon = ...

local CM = Addon.require and Addon.require("Tools.CategoryManager") or nil
if not CM then return end

local function SafeRecruiter()
  local ok, r = pcall(Addon.require, "Recruiter"); if ok then return r end
end

local function CountProspects()
  local r = SafeRecruiter(); if not r or not r.GetAllGuids then return 0 end
  local ok, res = pcall(r.GetAllGuids, r); if ok and type(res)=="table" then return #res end; return 0
end

local function CountBlacklist()
  local r = SafeRecruiter(); if not r then return 0 end
  if r.GetBlacklistGuids then
    local ok, res = pcall(r.GetBlacklistGuids, r); if ok and type(res)=="table" then return #res end
  end
  if r.GetBlacklist then
    local ok, bl = pcall(r.GetBlacklist, r); if ok and type(bl)=="table" then
      local c=0; for _ in pairs(bl) do c=c+1 end; return c
    end
  end
  return 0
end

local function FormatSuffix(count)
  if count <= 0 then return "" end
  return string.format(" |cffffaa33(%d)|r", count)
end

CM:RegisterCategoryDecorator("prospects", function()
  return FormatSuffix(CountProspects())
end)

CM:RegisterCategoryDecorator("blacklist", function()
  return FormatSuffix(CountBlacklist())
end)

-- Periodic refresh using animation loop (UI only, light)
local f = CreateFrame("Frame")
local acc = 0
f:SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  if acc > 5 then -- every 5s
    acc = 0
    if CM.ApplyDecorators then CM:ApplyDecorators() end
    -- force sidebar rebuild if main UI present
    if Addon.UI and Addon.UI.RefreshCategories then Addon.UI:RefreshCategories() end
  end
end)
