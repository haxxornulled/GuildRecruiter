local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or _G[__args[1]] or {})

-- Never build the container at file load; defer until CategoryManager is present.
local function SafeManager()
  -- Prefer interface; fall back to legacy recruiter if needed
  local okM, m = pcall(function() return Addon.require and Addon.require("IProspectManager") end); if okM and m then return m end
  local okR, r = pcall(function() return Addon.require and Addon.require("Recruiter") end); if okR and r then return r end
end

local function CountProspects()
  local m = SafeManager(); if not m or not m.GetAllGuids then return 0 end
  local ok, res = pcall(m.GetAllGuids, m); if ok and type(res)=="table" then return #res end; return 0
end

local function CountBlacklist()
  local m = SafeManager(); if not m then return 0 end
  if m.GetBlacklist then
    local ok, bl = pcall(m.GetBlacklist, m); if ok and type(bl)=="table" then
      local c=0; for _ in pairs(bl) do c=c+1 end; return c
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
      for i=1,n do
        local r1,r2,r3,r4,r5,r6,r7,r8,r9 = GetGuildRosterInfo(i)
        if r9 then count = count + 1 end
      end
    end
  end)
  return count
end

local attached = false
local function TryAttach()
  if attached then return true end
  -- Use non-building Peek first; tolerate Get if container already built by this time
  -- Never call Addon.Get here; only attach once the container exists (Peek returns non-nil)
  local CM = (Addon.Peek and (Addon.Peek("UI.CategoryManager") or Addon.Peek("Tools.CategoryManager")))
  if not CM then return false end
  if not (CM.RegisterCategoryDecorator and CM.ApplyDecorators) then return false end
  -- Register decorators
  pcall(CM.RegisterCategoryDecorator, CM, "prospects", function()
    return FormatSuffix(CountProspects())
  end)
  pcall(CM.RegisterCategoryDecorator, CM, "blacklist", function()
    return FormatSuffix(CountBlacklist())
  end)
  pcall(CM.RegisterCategoryDecorator, CM, "roster", function()
    return FormatSuffix(CountGuildOnline())
  end)
  attached = true
  return true
end

-- Periodic refresh using animation loop (UI only, light) and deferred attach
local f = CreateFrame("Frame")
local acc = 0
f:SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  -- First, attempt to attach once the manager exists
  if not attached then TryAttach() end
  if acc > 5 then -- every ~5s
    acc = 0
    if attached then
  -- Only peek; do not build the container from here
  local CM = (Addon.Peek and (Addon.Peek("UI.CategoryManager") or Addon.Peek("Tools.CategoryManager")))
      if CM and CM.ApplyDecorators then pcall(CM.ApplyDecorators, CM) end
      -- force sidebar rebuild if main UI present
      if Addon.UI and Addon.UI.RefreshCategories then pcall(Addon.UI.RefreshCategories, Addon.UI) end
    end
  end
end)
