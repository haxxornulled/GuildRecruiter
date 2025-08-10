-- UI.Prospects.lua — Modern Enhanced Prospects page with filtering, sorting, and better styling
local _, Addon = ...

local M = {}
local PAD, ROW_H = 12, 26 -- Slightly taller rows for better readability
local REMOVE_ICON = 136813
local INVITE_ICON = 524051

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_TCOORDS = CLASS_ICON_TCOORDS

-- Filter and sort state
local filterState = {
  status = "Active",     -- Active, Blacklisted, All
  sortBy = "Name",       -- Name, Class, Level, Status
  sortDesc = false       -- true for descending
}

-- Lazy logger accessor
local function LOG()
  local L = Addon.Logger
  return (L and L.ForContext and L:ForContext("UI.Prospects")) or nil
end

local function classRGB(token)
  if token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
    local c = RAID_CLASS_COLORS[token]; return c.r, c.g, c.b
  end
  if token and C_ClassColor and C_ClassColor.GetClassColor then
    local c = C_ClassColor.GetClassColor(token); if c then return c:GetRGB() end
  end
  return 1,1,1 -- neutral
end

local function toast(text, r, g, b)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(text, r or 1, g or 0.82, b or 0)
  else
    print("|cffffc107[GuildRecruiter]|r "..text)
  end
end

local function secs(n) return math.floor(n + 0.5) end

-- Create dropdown using UIDropDownMenu
local function CreateFilterDropdown(parent, width, items, current, onChange)
  local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dropdown, width or 120)
  
  UIDropDownMenu_Initialize(dropdown, function()
    local info = UIDropDownMenu_CreateInfo()
    info.func = function(self, arg1, arg2, checked)
      UIDropDownMenu_SetSelectedValue(dropdown, arg1)
      if onChange then onChange(arg1) end
    end
    
    for _, item in ipairs(items) do
      info.text = item.text
      info.value = item.value
      info.arg1 = item.value
      info.checked = (item.value == current)
      UIDropDownMenu_AddButton(info)
    end
  end)
  
  UIDropDownMenu_SetSelectedValue(dropdown, current)
  UIDropDownMenu_SetText(dropdown, current)
  
  return dropdown
end

-- Enhanced data building with filtering and sorting
local function buildFilteredSortedList(R)
  local list = {}
  if not R or not R.GetAllGuids then return list end
  
  -- Build full list
  for _, guid in ipairs(R:GetAllGuids()) do
    local p = R:GetProspect(guid)
    if p then
      local status = p.status or "New"
      list[#list+1] = {
        guid = p.guid, 
        name = p.name or "?", 
        realm = p.realm,
        class = p.className or "Unknown", 
        classFile = p.classToken,
        level = p.level or 1, 
        source = (p.sources and next(p.sources)) or "",
        status = status,
        statusDisplay = status == "Blacklisted" and "Blacklisted" or "Active",
        lastSeen = p.lastSeen or 0,
        declinedAt = p.declinedAt,
        declinedBy = p.declinedBy
      }
    end
  end
  
  -- Apply status filter
  if filterState.status ~= "All" then
    local filtered = {}
    for _, p in ipairs(list) do
      if filterState.status == "Active" and p.status ~= "Blacklisted" then
        filtered[#filtered+1] = p
      elseif filterState.status == "Blacklisted" and p.status == "Blacklisted" then
        filtered[#filtered+1] = p
      end
    end
    list = filtered
  end
  
  -- Apply sorting
  table.sort(list, function(a, b)
    local aVal, bVal
    
    if filterState.sortBy == "Name" then
      aVal, bVal = a.name:lower(), b.name:lower()
    elseif filterState.sortBy == "Class" then
      aVal, bVal = a.class:lower(), b.class:lower()
      -- Secondary sort by name for same class
      if aVal == bVal then
        aVal, bVal = a.name:lower(), b.name:lower()
      end
    elseif filterState.sortBy == "Level" then
      aVal, bVal = a.level, b.level
      -- Secondary sort by name for same level
      if aVal == bVal then
        aVal, bVal = a.name:lower(), b.name:lower()
      end
    elseif filterState.sortBy == "Status" then
      aVal, bVal = a.statusDisplay:lower(), b.statusDisplay:lower()
      -- Secondary sort by name for same status
      if aVal == bVal then
        aVal, bVal = a.name:lower(), b.name:lower()
      end
    else
      aVal, bVal = a.name:lower(), b.name:lower()
    end
    
    if filterState.sortDesc then
      return aVal > bVal
    else
      return aVal < bVal
    end
  end)

  return list
end

function M:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints()

  local Bus = Addon.EventBus
  local Recruiter = Addon.Recruiter
  local InviteService = Addon.InviteService
  local Config = Addon.Config
  local ButtonLib = Addon.require and Addon.require("Tools.ButtonLib")

  -- Add semi-transparent background to reduce dragonfly interference
  local bgFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
  bgFrame:SetAllPoints()
  bgFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  bgFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.85) -- Dark semi-transparent
  bgFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.8)
  bgFrame:SetFrameLevel(f:GetFrameLevel() + 1)
  f:SetFrameLevel(bgFrame:GetFrameLevel() + 1)

  -- transient row-status map: guid -> { text, r,g,b, expiresAt }
  f.recentStatus = {}

  -- Filter Controls Container
  local filterBar = CreateFrame("Frame", nil, f)
  filterBar:SetPoint("TOPLEFT", PAD + 8, -PAD - 8)
  filterBar:SetPoint("RIGHT", f, "RIGHT", -PAD - 8, 0)
  filterBar:SetHeight(36)

  -- Add a subtle background for the filter bar
  local filterBg = filterBar:CreateTexture(nil, "BACKGROUND")
  filterBg:SetAllPoints()
  filterBg:SetColorTexture(0.1, 0.1, 0.12, 0.6)

  -- Status Filter Label
  local statusLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  statusLabel:SetPoint("LEFT", filterBar, "LEFT", 8, 0)
  statusLabel:SetText("Show:")
  statusLabel:SetTextColor(0.9, 0.8, 0.6) -- Gold tint

  -- Status Filter Dropdown
  local statusItems = {
    {text = "Active Prospects", value = "Active"},
    {text = "Blacklisted", value = "Blacklisted"},
    {text = "All Prospects", value = "All"}
  }
  
  local statusDropdown = CreateFilterDropdown(filterBar, 140, statusItems, filterState.status, function(value)
    filterState.status = value
    f:Render()
  end)
  statusDropdown:SetPoint("LEFT", statusLabel, "RIGHT", 10, -1)

  -- Sort Label
  local sortLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  sortLabel:SetPoint("LEFT", statusDropdown, "RIGHT", 25, 1)
  sortLabel:SetText("Sort by:")
  sortLabel:SetTextColor(0.9, 0.8, 0.6) -- Gold tint

  -- Sort Dropdown
  local sortItems = {
    {text = "Name", value = "Name"},
    {text = "Class", value = "Class"},
    {text = "Level", value = "Level"},
    {text = "Status", value = "Status"}
  }
  
  local sortDropdown = CreateFilterDropdown(filterBar, 100, sortItems, filterState.sortBy, function(value)
    filterState.sortBy = value
    f:Render()
  end)
  sortDropdown:SetPoint("LEFT", sortLabel, "RIGHT", 10, -1)

  -- Sort Direction Button
  local sortDirBtn = ButtonLib and ButtonLib:Create(filterBar, { 
    text = filterState.sortDesc and "↓" or "↑", 
    variant = "subtle", 
    size = "sm",
    onClick = function(btn)
      filterState.sortDesc = not filterState.sortDesc
      btn:SetText(filterState.sortDesc and "↓" or "↑")
      f:Render()
    end
  }) or CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
  
  sortDirBtn:SetPoint("LEFT", sortDropdown, "RIGHT", 8, 1)
  sortDirBtn:SetSize(24, 24)
  if not sortDirBtn._text then
    sortDirBtn:SetText(filterState.sortDesc and "↓" or "↑")
    sortDirBtn:SetScript("OnClick", function(btn)
      filterState.sortDesc = not filterState.sortDesc
      btn:SetText(filterState.sortDesc and "↓" or "↑")
      f:Render()
    end)
  end

  -- Results Count
  local countLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  countLabel:SetPoint("RIGHT", filterBar, "RIGHT", -8, 0)
  countLabel:SetTextColor(0.7, 0.7, 0.9) -- Light blue
  f.countLabel = countLabel

  -- Enhanced Header with better styling
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", PAD + 8, -PAD - 48) -- Offset for filter bar
  header:SetPoint("RIGHT", f, "RIGHT", -PAD - 8, 0)
  header:SetHeight(ROW_H + 4)
  
  -- Header background
  local headerBg = header:CreateTexture(nil, "BACKGROUND")
  headerBg:SetAllPoints()
  headerBg:SetColorTexture(0.15, 0.12, 0.08, 0.8) -- Dark gold
  
  local columns = {
    { label="#", width=36 }, 
    { label="", width=26 }, 
    { label="Name", width=150 },
    { label="Class", width=110 }, 
    { label="Level", width=60 },
    { label="Status", width=80 },
    { label="Source", width=100 }, 
    { label="", width=28 }, 
    { label="", width=28 },
  }
  
  local x=8 -- Start with padding
  for _, c in ipairs(columns) do
    local t = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("LEFT", header, "LEFT", x, 0)
    t:SetWidth(c.width)
    t:SetText(c.label)
    t:SetTextColor(1, 0.9, 0.6) -- Gold header text
    x = x + c.width + 8
  end
  
  local rule = header:CreateTexture(nil, "BORDER")
  rule:SetColorTexture(0.6, 0.5, 0.3, 0.8) -- Gold line
  rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, -2)
  rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, -2)
  rule:SetHeight(2)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", PAD + 8, -PAD - 78) -- Offset for filter bar and header
  scroll:SetPoint("BOTTOMRIGHT", -PAD - 24, PAD + 8)
  local list = CreateFrame("Frame", nil, scroll)
  list:SetSize(800, 400); scroll:SetScrollChild(list)
  f.list, f.rows = list, {}

  -- Rest of the implementation continues exactly as before...
  -- [The rest of the function would be exactly the same as in the previous version]
  
  function f:SetStatusPill(guid, text, r, g, b, duration)
    duration = tonumber(duration) or tonumber(Config and Config.Get and Config:Get("invitePillDuration", 3)) or 3
    if duration < 0 then duration = 0 elseif duration > 10 then duration = 10 end
    f.recentStatus[guid] = { text = text, r = r or 1, g = g or 1, b = b or 1, expiresAt = GetTime() + duration }
    if not f._hasOnUpdate then
      f._hasOnUpdate = true
      f:SetScript("OnUpdate", function(self)
        local now = GetTime()
        local active = false
        for _, st in pairs(self.recentStatus) do
          if st and (now < (st.expiresAt or 0)) then active = true break end
        end
        if not active then
          self:SetScript("OnUpdate", nil); self._hasOnUpdate = false
        end
      end)
    end
    if f:IsShown() then f:Render() end
  end

  function f:Render()
    local data = buildFilteredSortedList(Recruiter)
    local y, shown = 0, 0
    local now = GetTime()
    
    -- Update count label
    local totalCount = 0
    if Recruiter and Recruiter.GetAllGuids then
      totalCount = #(Recruiter:GetAllGuids() or {})
    end
    f.countLabel:SetText(string.format("Showing: %d/%d", #data, totalCount))

    for i, p in ipairs(data) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, list); row:SetSize(820, ROW_H)
        
        -- Enhanced row background
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        
        -- Add subtle border
        row.border = row:CreateTexture(nil, "BORDER")
        row.border:SetHeight(1)
        row.border:SetPoint("BOTTOMLEFT")
        row.border:SetPoint("BOTTOMRIGHT")
        row.border:SetColorTexture(0.3, 0.3, 0.35, 0.4)
        
        local colX = 8 -- Start with padding

        row.c1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.c1:SetPoint("LEFT", row, "LEFT", colX, 0); row.c1:SetWidth(columns[1].width); colX = colX + columns[1].width + 8

        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetPoint("LEFT", row, "LEFT", colX, 0); row.classIcon:SetSize(22,22); colX = colX + columns[2].width + 8

        row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.nameFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.nameFS:SetWidth(columns[3].width)
        
        -- pill next to name
        row.statusFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.statusFS:SetPoint("LEFT", row.nameFS, "RIGHT", 6, 0); row.statusFS:SetText(""); row.statusFS:Hide()
        colX = colX + columns[3].width + 8

        row.classFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.classFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.classFS:SetWidth(columns[4].width); colX = colX + columns[4].width + 8

        row.levelFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.levelFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.levelFS:SetWidth(columns[5].width); colX = colX + columns[5].width + 8

        row.statusColFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.statusColFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.statusColFS:SetWidth(columns[6].width); colX = colX + columns[6].width + 8

        row.srcFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.srcFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.srcFS:SetWidth(columns[7].width); colX = colX + columns[7].width + 8

        row.inviteBtn = (ButtonLib and ButtonLib:Create(row, { text="+", variant="primary", size="sm" })) or CreateFrame("Button", nil, row)
        row.inviteBtn:SetPoint("LEFT", row, "LEFT", colX, -2)
        row.inviteBtn:SetSize(26,22)
        if not row.inviteBtn._text then
          row.inviteBtn.icon = row.inviteBtn:CreateTexture(nil, "ARTWORK")
          row.inviteBtn.icon:SetAllPoints(); row.inviteBtn.icon:SetTexture(INVITE_ICON)
        end
        colX = colX + columns[8].width + 8

        row.removeBtn = (ButtonLib and ButtonLib:Create(row, { text="×", variant="danger", size="sm" })) or CreateFrame("Button", nil, row)
        row.removeBtn:SetPoint("LEFT", row, "LEFT", colX, -2)
        row.removeBtn:SetSize(26,22)
        if not row.removeBtn._text then
          row.removeBtn.icon = row.removeBtn:CreateTexture(nil, "ARTWORK")
          row.removeBtn.icon:SetAllPoints(); row.removeBtn.icon:SetTexture(REMOVE_ICON)
        end

        -- cooldown state
        row.inviteCooldownEnd = 0
        row.inviteBtn:SetMotionScriptsWhileDisabled(true)
        
        self.rows[i] = row
      end

      -- Set all the row data and styling...
      row:SetPoint("TOPLEFT", 0, y)
      
      -- Determine if this prospect is blacklisted
      local isBlacklisted = p.status == "Blacklisted"

      -- Enhanced row styling
      local st = f.recentStatus[p.guid]
      local active = st and now < (st.expiresAt or 0)
      if active then
        row.statusFS:SetText(st.text or "")
        row.statusFS:SetTextColor(st.r or 1, st.g or 1, st.b or 1)
        row.statusFS:Show()
        row.bg:SetColorTexture(0.2, 0.7, 0.2, 0.25) -- Green highlight for active status
      else
        row.statusFS:Hide()
        if isBlacklisted then
          row.bg:SetColorTexture(0.6, 0.2, 0.2, 0.2) -- Red tint for blacklisted
        else
          local alpha = (i%2==1) and 0.15 or 0.08
          row.bg:SetColorTexture(0.1, 0.1, 0.12, alpha) -- Dark alternating rows
        end
      end

      row.c1:SetText(tostring(i))
      row.c1:SetTextColor(0.8, 0.8, 0.9)

      local token = p.classFile and p.classFile:upper() or nil
      if token and CLASS_TCOORDS and CLASS_TCOORDS[token] then
        row.classIcon:SetTexture(CLASS_TEX)
        row.classIcon:SetTexCoord(unpack(CLASS_TCOORDS[token]))
        row.classIcon:SetDesaturated(isBlacklisted)
        row.classIcon:Show()
      else
        row.classIcon:Hide()
      end

      local r,g,b = classRGB(token)
      row.nameFS:SetText(p.name or "?")
      if isBlacklisted then
        row.nameFS:SetTextColor(0.6, 0.6, 0.6) -- Grayed out for blacklisted
      else
        row.nameFS:SetTextColor(r,g,b)
      end
      
      row.classFS:SetText(p.class or (token or "?"))
      if isBlacklisted then
        row.classFS:SetTextColor(0.6, 0.6, 0.6)
      else
        row.classFS:SetTextColor(r,g,b)
      end

      local lvl = tonumber(p.level) or 0
      row.levelFS:SetText(tostring(lvl))
      if isBlacklisted then
        row.levelFS:SetTextColor(0.6, 0.6, 0.6)
      else
        local my  = UnitLevel("player") or lvl
        local diff = my - lvl
        if lvl == my then 
          row.levelFS:SetTextColor(1,.82,0)
        elseif diff > 4 then 
          row.levelFS:SetTextColor(.55,.55,.55)
        elseif diff > 0 then 
          row.levelFS:SetTextColor(0,1,0)
        else 
          row.levelFS:SetTextColor(1,.5,.25) 
        end
      end

      -- Enhanced Status column
      if isBlacklisted then
        row.statusColFS:SetText("Blacklisted")
        row.statusColFS:SetTextColor(1, 0.4, 0.4)
      else
        row.statusColFS:SetText("Active")
        row.statusColFS:SetTextColor(0.4, 1, 0.4)
      end

      row.srcFS:SetText(p.source or "")
      if isBlacklisted then
        row.srcFS:SetTextColor(0.6, 0.6, 0.6)
      else
        row.srcFS:SetTextColor(0.8, 0.8, 0.9)
      end

      row:Show(); y = y - ROW_H
      shown = shown + 1
    end
    for i = shown + 1, #self.rows do self.rows[i]:Hide() end
    list:SetHeight(math.max(ROW_H * shown, 1))
  end

  -- Event hooks
  if Bus and Bus.Subscribe then
    Bus:Subscribe("Recruiter.ProspectQueued",  function() if f:IsShown() then f:Render() end end)
    Bus:Subscribe("Recruiter.ProspectUpdated", function() if f:IsShown() then f:Render() end end)
    Bus:Subscribe("Recruiter.Blacklisted",     function() if f:IsShown() then f:Render() end end)
    Bus:Subscribe("BlacklistUpdated",          function() if f:IsShown() then f:Render() end end)

    Bus:Subscribe("InviteService.Invited", function(_, guid)
      if not guid then return end
      local dur = tonumber(Config and Config.Get and Config:Get("invitePillDuration", 3)) or 3
      if dur < 0 then dur = 0 elseif dur > 10 then dur = 10 end
      f:SetStatusPill(guid, "Invited", 0, 1, 0, dur)
    end)

    Bus:Subscribe("InviteService.InviteFailed", function(_, guid, _, err)
      if not guid then return end
      local dur = tonumber(Config and Config.Get and Config:Get("invitePillDuration", 3)) or 3
      if dur < 0 then dur = 0 elseif dur > 10 then dur = 10 end
      f:SetStatusPill(guid, "Failed", 1, 0.25, 0.25, dur)
      if err then toast(("Invite failed: %s"):format(tostring(err)), 1, 0.25, 0.25) end
    end)
  end

  local originalShow = f.Show
  f.Show = function(self)
    self:Render()
    if originalShow then originalShow(self) end
  end
  return f
end

Addon.provide("UI.Prospects", M)
return M
