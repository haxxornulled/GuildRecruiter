-- UI.Prospects.lua — Prospects page (Recruiter + InviteService)
-- Per-row cooldown, toast, and a transient "status pill" on invite events.
local _, Addon = ...

local M = {}
local PAD, ROW_H = 12, 24
local REMOVE_ICON = 136813
local INVITE_ICON = 524051

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_TCOORDS = CLASS_ICON_TCOORDS

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

local function buildListFromRecruiter(R)
  local list = {}
  if not R or not R.GetAllGuids then return list end
  for _, guid in ipairs(R:GetAllGuids()) do
    local p = R:GetProspect(guid)
    if p then
      list[#list+1] = {
        guid = p.guid, name = p.name or "?", realm = p.realm,
        class = p.className, classFile = p.classToken,
        level = p.level, source = (p.sources and next(p.sources)) or "",
        status = p.status,
      }
    end
  end
    table.sort(list, function(a,b)
    local an = a.name or ""; local bn = b.name or ""
    if an ~= bn then return an < bn end
    return (a.level or 0) > (b.level or 0)
  end)

  return list
end

function M:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints()

  local Bus = Addon.EventBus
  local Recruiter = Addon.Recruiter
  local InviteService = Addon.InviteService
  local Config = Addon.Config

  -- transient row-status map: guid -> { text, r,g,b, expiresAt }
  f.recentStatus = {}

  -- Header
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", PAD, -PAD)
  header:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
  header:SetHeight(ROW_H)
  local columns = {
    { label="#", width=36 }, { label="", width=26 }, { label="Name", width=180 },
    { label="Class", width=110 }, { label="Level", width=60 },
    { label="Source", width=120 }, { label="", width=28 }, { label="", width=28 },
  }
  local x=0
  for _, c in ipairs(columns) do
    local t = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("LEFT", header, "LEFT", x, 0); t:SetWidth(c.width); t:SetText(c.label)
    x = x + c.width + 6
  end
  local rule = header:CreateTexture(nil, "BACKGROUND")
  rule:SetColorTexture(1,1,1,0.12)
  rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, -2)
  rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, -2)
  rule:SetHeight(1)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", PAD, -PAD*2 - 2)
  scroll:SetPoint("BOTTOMRIGHT", -PAD-16, PAD)
  local list = CreateFrame("Frame", nil, scroll)
  list:SetSize(800, 400); scroll:SetScrollChild(list)
  f.list, f.rows = list, {}

  f:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then list:SetWidth(w - (PAD*2 + 16)) end
  end)

  function f:SetStatusPill(guid, text, r, g, b, duration)
    duration = tonumber(duration) or tonumber(Config and Config.Get and Config:Get("invitePillDuration", 3)) or 3
    if duration < 0 then duration = 0 elseif duration > 10 then duration = 10 end
    f.recentStatus[guid] = { text = text, r = r or 1, g = g or 1, b = b or 1, expiresAt = GetTime() + duration }
    -- ensure OnUpdate runs while we have active pills
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
    local data = buildListFromRecruiter(Recruiter)
    local y, shown = 0, 0
    local now = GetTime()

    for i, p in ipairs(data) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, list); row:SetSize(820, ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
        local colX = 0

        row.c1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.c1:SetPoint("LEFT", row, "LEFT", colX, 0); row.c1:SetWidth(columns[1].width); colX = colX + columns[1].width + 6

        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetPoint("LEFT", row, "LEFT", colX, 0); row.classIcon:SetSize(20,20); colX = colX + columns[2].width + 6

        row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.nameFS:SetWidth(columns[3].width)
        -- pill next to name
        row.statusFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.statusFS:SetPoint("LEFT", row.nameFS, "RIGHT", 6, 0); row.statusFS:SetText(""); row.statusFS:Hide()
        colX = colX + columns[3].width + 6

        row.classFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.classFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.classFS:SetWidth(columns[4].width); colX = colX + columns[4].width + 6

        row.levelFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.levelFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.levelFS:SetWidth(columns[5].width); colX = colX + columns[5].width + 6

        row.srcFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.srcFS:SetPoint("LEFT", row, "LEFT", colX, 0); row.srcFS:SetWidth(columns[6].width); colX = colX + columns[6].width + 6

        row.inviteBtn = CreateFrame("Button", nil, row)
        row.inviteBtn:SetPoint("LEFT", row, "LEFT", colX, -2)
        row.inviteBtn:SetSize(22,22)
        row.inviteBtn.icon = row.inviteBtn:CreateTexture(nil, "ARTWORK")
        row.inviteBtn.icon:SetAllPoints(); row.inviteBtn.icon:SetTexture(INVITE_ICON)
        colX = colX + columns[7].width + 6

        row.removeBtn = CreateFrame("Button", nil, row)
        row.removeBtn:SetPoint("LEFT", row, "LEFT", colX, -2)
        row.removeBtn:SetSize(22,22)
        row.removeBtn.icon = row.removeBtn:CreateTexture(nil, "ARTWORK")
        row.removeBtn.icon:SetAllPoints(); row.removeBtn.icon:SetTexture(REMOVE_ICON)

        -- cooldown state
        row.inviteCooldownEnd = 0
        row.inviteBtn:SetMotionScriptsWhileDisabled(true)
        row.inviteBtn:SetScript("OnEnter", function(btn)
          if btn:IsEnabled() then return end
          local remain = row.inviteCooldownEnd - GetTime()
          if remain > 0 then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(("Invite available in %ds"):format(secs(remain)), 1, .82, 0)
            GameTooltip:Show()
          end
        end)
        row.inviteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        self.rows[i] = row
      end

      row:SetPoint("TOPLEFT", 0, y)

      -- status pill / highlight
      local st = f.recentStatus[p.guid]
      local active = st and now < (st.expiresAt or 0)
      if active then
        row.statusFS:SetText(st.text or "")
        row.statusFS:SetTextColor(st.r or 1, st.g or 1, st.b or 1)
        row.statusFS:Show()
        row.bg:SetColorTexture(0.2, 0.9, 0.2, 0.10)
      else
        row.statusFS:Hide()
        row.bg:SetColorTexture((i%2==1) and 0.95 or 1, (i%2==1) and 0.89 or 1, (i%2==1) and 0.68 or 1, (i%2==1) and 0.08 or 0.02)
      end

      row.c1:SetText(tostring(i))

      local token = p.classFile and p.classFile:upper() or nil
      if token and CLASS_TCOORDS and CLASS_TCOORDS[token] then
        row.classIcon:SetTexture(CLASS_TEX); row.classIcon:SetTexCoord(unpack(CLASS_TCOORDS[token])); row.classIcon:Show()
      else
        row.classIcon:Hide()
      end

      local r,g,b = classRGB(token)
      row.nameFS:SetText(p.name or "?");  row.nameFS:SetTextColor(r,g,b)
      row.classFS:SetText(p.class or (token or "?")); row.classFS:SetTextColor(r,g,b)

      local lvl = tonumber(p.level) or 0
      local my  = UnitLevel("player") or lvl
      local diff = my - lvl
      if lvl == my then row.levelFS:SetTextColor(1,.82,0)
      elseif diff > 4 then row.levelFS:SetTextColor(.55,.55,.55)
      elseif diff > 0 then row.levelFS:SetTextColor(0,1,0)
      else row.levelFS:SetTextColor(1,.5,.25) end
      row.levelFS:SetText(tostring(lvl))

      row.srcFS:SetText(p.source or "")

      -- Invite with per-row cooldown (configurable)
      local function setInviteEnabled(enabled)
        if enabled then
          row.inviteBtn:Enable()
          row.inviteBtn.icon:SetDesaturated(false)
          row.inviteBtn:SetAlpha(1)
        else
          row.inviteBtn:Disable()
          row.inviteBtn.icon:SetDesaturated(true)
          row.inviteBtn:SetAlpha(0.4)
        end
      end

      local function startCooldown(seconds)
        row.inviteCooldownEnd = GetTime() + seconds
        setInviteEnabled(false)
        C_Timer.After(seconds, function()
          setInviteEnabled(true)
          GameTooltip:Hide()
        end)
      end

      setInviteEnabled(GetTime() >= (row.inviteCooldownEnd or 0))

      row.inviteBtn:SetScript("OnClick", function()
        if GetTime() < (row.inviteCooldownEnd or 0) then return end
        if InviteService and InviteService.InviteGUID then
          toast(("Whisper sent to %s"):format(p.name or "?"))
          local ok, err = InviteService:InviteGUID(p.guid, { whisper = true })
          if ok then
            toast(("Invited %s"):format(p.name or "?"), 0, 1, 0)
          else
            toast(("Invite failed: %s"):format(tostring(err or "error")), 1, 0.25, 0.25)
          end
          local L = LOG(); if L then L:Info("Invite clicked for {Name}", { Name = p.name }) end

          local cd = tonumber(Config and Config.Get and Config:Get("inviteClickCooldown", 3)) or 3
          if cd < 0 then cd = 0 elseif cd > 10 then cd = 10 end
          startCooldown(cd)
        end
      end)

      -- Remove
      row.removeBtn:SetScript("OnClick", function()
        if Recruiter and Recruiter.ClearFromUI then
          Recruiter:ClearFromUI(p.guid)
        end
        local L = LOG(); if L then L:Info("Removed prospect {Name}", { Name = p.name }) end
        f:Render()
      end)

      row:Show(); y = y - ROW_H
      shown = shown + 1
    end
    for i = shown + 1, #self.rows do self.rows[i]:Hide() end
    list:SetHeight(math.max(ROW_H * shown, 1))
  end

  -- Event hooks (pull duration from Config on each event)
  if Bus and Bus.Subscribe then
    Bus:Subscribe("Recruiter.ProspectQueued",  function() if f:IsShown() then f:Render() end end)
    Bus:Subscribe("Recruiter.ProspectUpdated", function() if f:IsShown() then f:Render() end end)
    Bus:Subscribe("Recruiter.Blacklisted",     function() if f:IsShown() then f:Render() end end)

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
  f.Show = function(self, ...) self:Render(); if originalShow then originalShow(self, ...) end end
  return f
end

Addon.provide("UI.Prospects", M)
return M
