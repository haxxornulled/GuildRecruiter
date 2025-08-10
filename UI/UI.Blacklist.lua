-- UI.Blacklist.lua — Blacklist page (Recruiter-backed)
local _, Addon = ...
local M = {}

local PAD, ROW_H = 12, 24
local REMOVE_ICON = 136813

local function getBlacklist()
  local R = Addon.Recruiter
  if R and R.GetBlacklist then
    return R:GetBlacklist() -- { [guid]=true, ... } or { guid -> {reason,timestamp} }
  end
  local DB = _G.GuildRecruiterDB
  return (DB and DB.blacklist) or {}
end

local function toArray(bl)
  local out = {}
  for guid, val in pairs(bl) do
    local reason, ts = "manual", 0
    if type(val) == "table" then
      reason = val.reason or "manual"
      ts     = tonumber(val.timestamp) or 0
    end
    out[#out+1] = { guid=guid, reason=reason, ts=ts }
  end
  table.sort(out, function(a,b) return a.ts > b.ts end)
  return out
end

function M:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints()
  local R = Addon.Recruiter
  local Bus = Addon.EventBus
  local Log = Addon.Logger and Addon.Logger:ForContext("UI.Blacklist")

  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", PAD, -PAD)
  header:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
  header:SetHeight(ROW_H)
  local cols = {
    { label="#", width=36 }, { label="Name", width=220 },
    { label="Reason", width=220 }, { label="When", width=160 }, { label="", width=28 },
  }
  local x=0
  for _, c in ipairs(cols) do
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
  f.rows, f.list = {}, list

  f:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then list:SetWidth(w - (PAD*2 + 16)) end
  end)

  local function fmtWhen(ts) ts=tonumber(ts) or 0; if ts<=0 then return "-" end; return date("%Y-%m-%d %H:%M", ts) end
  local function nameFromGuid(guid)
    local p = R and R.GetProspect and R:GetProspect(guid)
    return (p and p.name) or guid
  end

  function f:Render()
    local entries = toArray(getBlacklist())
    local y, shown = 0, 0
    for i, e in ipairs(entries) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, list); row:SetSize(820, ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
        local colX = 0
        row.col1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.col1:SetPoint("LEFT", row, "LEFT", colX, 0); row.col1:SetWidth(cols[1].width); colX = colX + cols[1].width + 6
        row.col2 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.col2:SetPoint("LEFT", row, "LEFT", colX, 0); row.col2:SetWidth(cols[2].width); colX = colX + cols[2].width + 6
        row.col3 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.col3:SetPoint("LEFT", row, "LEFT", colX, 0); row.col3:SetWidth(cols[3].width); colX = colX + cols[3].width + 6
        row.col4 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.col4:SetPoint("LEFT", row, "LEFT", colX, 0); row.col4:SetWidth(cols[4].width); colX = colX + cols[4].width + 6
        local ButtonLib = (Addon.require and Addon.require("Tools.ButtonLib"))
        local btn = (ButtonLib and ButtonLib:Create(row, { text="×", variant="danger", size="sm" })) or CreateFrame("Button", nil, row)
        btn:SetPoint("LEFT", row, "LEFT", colX, -2)
        btn:SetSize(26,22)
        if not btn._text then
          btn.icon = btn:CreateTexture(nil, "ARTWORK")
          btn.icon:SetAllPoints(); btn.icon:SetTexture(REMOVE_ICON)
        end
        row.removeBtn = btn
        self.rows[i] = row
      end

      row:SetPoint("TOPLEFT", 0, y)
      row.bg:SetColorTexture((i%2==1) and 0.95 or 1, (i%2==1) and 0.89 or 1, (i%2==1) and 0.68 or 1, (i%2==1) and 0.08 or 0.02)

  row.col1:SetText(tostring(i))
      row.col2:SetText(nameFromGuid(e.guid))
      row.col3:SetText(e.reason or "manual")
      row.col4:SetText(fmtWhen(e.ts))

      row.removeBtn:SetScript("OnClick", function()
        if R and R.Unblacklist then R:Unblacklist(e.guid) end
        if Log then Log:Info("Unblacklisted {GUID}", { GUID=e.guid }) end
        if Bus and Bus.Publish then Bus:Publish("BlacklistUpdated") end
        f:Render()
      end)

      row:Show(); y = y - ROW_H; shown = shown + 1
    end
    for i = shown + 1, #self.rows do self.rows[i]:Hide() end
    list:SetHeight(math.max(ROW_H * shown, 1))
  end

  if Bus and Bus.Subscribe then
    Bus:Subscribe("Recruiter.Blacklisted", function() if f:IsShown() then f:Render() end end)
    Bus:Subscribe("BlacklistUpdated",      function() if f:IsShown() then f:Render() end end)
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
