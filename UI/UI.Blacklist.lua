-- UI.Blacklist.lua — Modern Enhanced Blacklist page with better styling
local _, Addon = ...
local M = {}

local PAD, ROW_H = 12, 26 -- Slightly taller rows for better readability
local UNBLOCK_ICON = "Interface\\BUTTONS\\UI-RefreshButton"

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_TCOORDS = CLASS_ICON_TCOORDS

local function classRGB(token)
  if token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
    local c = RAID_CLASS_COLORS[token]; return c.r, c.g, c.b
  end
  if token and C_ClassColor and C_ClassColor.GetClassColor then
    local c = C_ClassColor.GetClassColor(token); if c then return c:GetRGB() end
  end
  return 0.6, 0.6, 0.6 -- muted for blacklisted
end

local function getBlacklistWithProspectInfo()
  local R = Addon.Recruiter
  if not R then return {} end
  
  local blacklist = R.GetBlacklist and R:GetBlacklist() or {}
  local prospects = {}
  
  -- Get prospect data for each blacklisted GUID
  for guid, blEntry in pairs(blacklist) do
    local prospect = R.GetProspect and R:GetProspect(guid)
    if prospect then
      local reason, ts = "manual", 0
      if type(blEntry) == "table" then
        reason = blEntry.reason or "manual"
        ts = tonumber(blEntry.timestamp) or 0
      end
      
      prospects[#prospects+1] = {
        guid = guid,
        name = prospect.name or "?",
        realm = prospect.realm,
        class = prospect.className or "Unknown",
        classFile = prospect.classToken,
        level = prospect.level or 1,
        reason = reason,
        timestamp = ts,
        declinedBy = prospect.declinedBy,
        declinedAt = prospect.declinedAt,
        source = (prospect.sources and next(prospect.sources)) or "",
        lastSeen = prospect.lastSeen or 0
      }
    else
      -- Blacklist entry without prospect data (shouldn't happen with new system)
      local reason, ts = "manual", 0
      if type(blEntry) == "table" then
        reason = blEntry.reason or "manual"
        ts = tonumber(blEntry.timestamp) or 0
      end
      
      prospects[#prospects+1] = {
        guid = guid,
        name = guid:sub(1,8) .. "...", -- show part of GUID
        realm = "?",
        class = "Unknown",
        classFile = nil,
        level = 0,
        reason = reason,
        timestamp = ts,
        source = "unknown"
      }
    end
  end
  
  -- Sort by timestamp, newest first
  table.sort(prospects, function(a, b) 
    return (a.timestamp or 0) > (b.timestamp or 0) 
  end)
  
  return prospects
end

local function toast(text, r, g, b)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(text, r or 1, g or 0.82, b or 0)
  else
    print("|cffffc107[GuildRecruiter]|r "..text)
  end
end

function M:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints()
  local R = Addon.Recruiter
  local Bus = Addon.EventBus
  local Log = Addon.Logger and Addon.Logger:ForContext("UI.Blacklist")
  local ButtonLib = Addon.require and Addon.require("Tools.ButtonLib")

  -- Add semi-transparent background to reduce dragonfly interference (same as Prospects)
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

  -- Header with count (same styling as Prospects)
  local headerFrame = CreateFrame("Frame", nil, f)
  headerFrame:SetPoint("TOPLEFT", PAD + 8, -PAD - 8)
  headerFrame:SetPoint("RIGHT", f, "RIGHT", -PAD - 8, 0)
  headerFrame:SetHeight(36)
  
  -- Add a subtle background for the header bar
  local headerFrameBg = headerFrame:CreateTexture(nil, "BACKGROUND")
  headerFrameBg:SetAllPoints()
  headerFrameBg:SetColorTexture(0.1, 0.1, 0.12, 0.6)
  
  local titleLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleLabel:SetPoint("LEFT", headerFrame, "LEFT", 8, 0)
  titleLabel:SetText("Blacklisted Prospects")
  titleLabel:SetTextColor(0.9, 0.8, 0.6) -- Gold tint (same as Prospects)
  
  local countLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  countLabel:SetPoint("RIGHT", headerFrame, "RIGHT", -8, 0)
  countLabel:SetTextColor(0.7, 0.7, 0.9) -- Light blue (same as Prospects)
  f.countLabel = countLabel

  -- Enhanced Column headers (same styling as Prospects)
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", PAD + 8, -PAD - 48)
  header:SetPoint("RIGHT", f, "RIGHT", -PAD - 8, 0)
  header:SetHeight(ROW_H + 4)
  
  -- Header background (same as Prospects)
  local headerBg = header:CreateTexture(nil, "BACKGROUND")
  headerBg:SetAllPoints()
  headerBg:SetColorTexture(0.15, 0.12, 0.08, 0.8) -- Dark gold
  
  local cols = {
    { label="#", width=36 }, 
    { label="", width=26 }, 
    { label="Name", width=150 },
    { label="Class", width=110 }, 
    { label="Level", width=60 },
    { label="Reason", width=100 }, 
    { label="When", width=140 }, 
    { label="Source", width=80 },
    { label="", width=28 },
  }
  
  local x=8 -- Start with padding (same as Prospects)
  for _, c in ipairs(cols) do
    local t = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("LEFT", header, "LEFT", x, 0)
    t:SetWidth(c.width)
    t:SetText(c.label)
    t:SetTextColor(1, 0.9, 0.6) -- Gold header text (same as Prospects)
    x = x + c.width + 8
  end
  
  local rule = header:CreateTexture(nil, "BORDER")
  rule:SetColorTexture(0.6, 0.5, 0.3, 0.8) -- Gold line (same as Prospects)
  rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, -2)
  rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, -2)
  rule:SetHeight(2)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", PAD + 8, -PAD - 78) -- Same offset as Prospects
  scroll:SetPoint("BOTTOMRIGHT", -PAD - 24, PAD + 8)
  local list = CreateFrame("Frame", nil, scroll)
  list:SetSize(800, 400); scroll:SetScrollChild(list)
  f.rows, f.list = {}, list

  f:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then list:SetWidth(w - (PAD*2 + 32)) end
  end)

  local function fmtWhen(ts) 
    ts = tonumber(ts) or 0
    if ts <= 0 then return "-" end
    return date("%m/%d %H:%M", ts)
  end

  function f:Render()
    local entries = getBlacklistWithProspectInfo()
    local y, shown = 0, 0
    
    -- Update count (same as Prospects)
    f.countLabel:SetText(string.format("Total: %d", #entries))
    
    for i, e in ipairs(entries) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, list); row:SetSize(820, ROW_H)
        
        -- Enhanced row background (same as Prospects)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        
        -- Add subtle border (same as Prospects)
        row.border = row:CreateTexture(nil, "BORDER")
        row.border:SetHeight(1)
        row.border:SetPoint("BOTTOMLEFT")
        row.border:SetPoint("BOTTOMRIGHT")
        row.border:SetColorTexture(0.3, 0.3, 0.35, 0.4)
        
        local colX = 8 -- Start with padding (same as Prospects)
        
        row.col1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.col1:SetPoint("LEFT", row, "LEFT", colX, 0); row.col1:SetWidth(cols[1].width); colX = colX + cols[1].width + 8
        
        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetPoint("LEFT", row, "LEFT", colX, 0); row.classIcon:SetSize(22,22); colX = colX + cols[2].width + 8
        
        row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.nameFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.nameFS:SetWidth(cols[3].width); colX = colX + cols[3].width + 8
        
        row.classFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.classFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.classFS:SetWidth(cols[4].width); colX = colX + cols[4].width + 8
        
        row.levelFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.levelFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.levelFS:SetWidth(cols[5].width); colX = colX + cols[5].width + 8
        
        row.reasonFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.reasonFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.reasonFS:SetWidth(cols[6].width); colX = colX + cols[6].width + 8
        
        row.whenFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.whenFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.whenFS:SetWidth(cols[7].width); colX = colX + cols[7].width + 8
        
        row.sourceFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.sourceFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.sourceFS:SetWidth(cols[8].width); colX = colX + cols[8].width + 8
        
        row.unblockBtn = (ButtonLib and ButtonLib:Create(row, { text="↶", variant="secondary", size="sm" })) or CreateFrame("Button", nil, row)
        row.unblockBtn:SetPoint("LEFT", row, "LEFT", colX, -2)
        row.unblockBtn:SetSize(26,22)
        if not row.unblockBtn._text then
          row.unblockBtn.icon = row.unblockBtn:CreateTexture(nil, "ARTWORK")
          row.unblockBtn.icon:SetAllPoints(); row.unblockBtn.icon:SetTexture(UNBLOCK_ICON)
        end
        
        -- Tooltip for unblock button
        row.unblockBtn:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:ClearLines()
          GameTooltip:AddLine("Unblacklist Prospect", 1, 1, 1)
          GameTooltip:AddLine("Move back to active prospects", 0.8, 0.8, 0.8)
          GameTooltip:Show()
        end)
        row.unblockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        self.rows[i] = row
      end

      row:SetPoint("TOPLEFT", 0, y)
      
      -- Enhanced row styling (same red tint pattern as Prospects)
      local alpha = (i%2==1) and 0.2 or 0.12
      row.bg:SetColorTexture(0.6, 0.2, 0.2, alpha) -- Red tint for blacklisted (same as Prospects)

      row.col1:SetText(tostring(i))
      row.col1:SetTextColor(0.8, 0.8, 0.9) -- Same as Prospects

      -- Class icon (same styling as Prospects)
      local token = e.classFile and e.classFile:upper() or nil
      if token and CLASS_TCOORDS and CLASS_TCOORDS[token] then
        row.classIcon:SetTexture(CLASS_TEX)
        row.classIcon:SetTexCoord(unpack(CLASS_TCOORDS[token]))
        row.classIcon:SetDesaturated(true) -- Gray out for blacklisted (same as Prospects)
        row.classIcon:Show()
      else
        row.classIcon:Hide()
      end

      -- Name and class with muted colors (same as Prospects)
      local r, g, b = classRGB(token)
      row.nameFS:SetText(e.name or "?")
      row.nameFS:SetTextColor(r, g, b)
      
      row.classFS:SetText(e.class or "Unknown")
      row.classFS:SetTextColor(r, g, b)

      -- Level with muted color (same as Prospects)
      row.levelFS:SetText(tostring(e.level or 0))
      row.levelFS:SetTextColor(0.6, 0.6, 0.6)

      -- Reason with color coding (same pattern as Prospects)
      local reason = e.reason or "manual"
      row.reasonFS:SetText(reason)
      if reason == "declined" then
        row.reasonFS:SetTextColor(1, 0.4, 0.4) -- Red for declined (same as Prospects)
      else
        row.reasonFS:SetTextColor(0.8, 0.8, 0.9) -- Neutral color
      end
      
      -- Enhanced tooltip for reason if it was a decline (same as Prospects)
      if reason == "declined" and e.declinedBy then
        row.reasonFS:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:ClearLines()
          GameTooltip:AddLine("Declined Invite", 1, 0.4, 0.4)
          if e.declinedBy then
            GameTooltip:AddLine("Player: " .. e.declinedBy, 1, 1, 1)
          end
          if e.declinedAt then
            GameTooltip:AddLine("Date: " .. date("%Y-%m-%d %H:%M", e.declinedAt), 0.8, 0.8, 0.8)
          end
          GameTooltip:Show()
        end)
        row.reasonFS:SetScript("OnLeave", function() GameTooltip:Hide() end)
      else
        row.reasonFS:SetScript("OnEnter", nil)
        row.reasonFS:SetScript("OnLeave", nil)
      end

      -- When (same styling as Prospects)
      row.whenFS:SetText(fmtWhen(e.timestamp))
      row.whenFS:SetTextColor(0.8, 0.8, 0.8)
      
      -- Source (same styling as Prospects)
      row.sourceFS:SetText(e.source or "")
      row.sourceFS:SetTextColor(0.6, 0.6, 0.6)

      -- Unblock button (same interaction pattern as Prospects)
      row.unblockBtn:SetScript("OnClick", function()
        if R and R.Unblacklist then 
          R:Unblacklist(e.guid) 
          toast(("Unblacklisted %s - moved to active prospects"):format(e.name or "?"), 0, 1, 0)
        end
        if Log then Log:Info("Unblacklisted {Name} {GUID}", { Name = e.name, GUID = e.guid }) end
        f:Render()
      end)

      row:Show(); y = y - ROW_H; shown = shown + 1
    end
    
    for i = shown + 1, #self.rows do 
      self.rows[i]:Hide() 
    end
    list:SetHeight(math.max(ROW_H * shown, 1))
  end

  -- Event subscriptions (same as Prospects)
  if Bus and Bus.Subscribe then
    Bus:Subscribe("Recruiter.Blacklisted", function() if f:IsShown() then f:Render() end end)
    Bus:Subscribe("BlacklistUpdated", function() if f:IsShown() then f:Render() end end)
    Bus:Subscribe("Recruiter.ProspectUpdated", function() if f:IsShown() then f:Render() end end)
  end

  local originalShow = f.Show
  f.Show = function(self)
    self:Render()
    if originalShow then originalShow(self) end
  end
  return f
end

Addon.provide("UI.Blacklist", M)
return M
