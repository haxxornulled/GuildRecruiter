-- UI.GuildRoster.lua — Guild Roster panel
---@diagnostic disable: undefined-global, undefined-field, inject-field
local __args = {...}
local AddonName, Addon = __args[1], (__args[2] or _G[__args[1]] or {})
if type(AddonName) ~= 'string' or AddonName == '' then AddonName = 'GuildRecruiter' end
local M = {}

local function safeRequire(key)
  local ok, mod = pcall(Addon.require, key); if ok then return mod end
end

-- Build a simple roster snapshot (best-effort across versions)
local function BuildRoster()
  local out = {}
  if not (IsInGuild and IsInGuild()) then return out end
  if not (GetNumGuildMembers and GetGuildRosterInfo) then return out end
  local n = tonumber(GetNumGuildMembers() or 0) or 0
  for i = 1, n do
    local r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r13,r14,r15,r16,r17 = GetGuildRosterInfo(i)
    local name = r1
    local rank = r2
    local level = r4
    local classDisplay = r5
    local zone = r6
    local note = r7
    local officerNote = r8
    local online = r9 and true or false
    local status = r10
    local classToken = r11 -- class filename token (e.g., WARRIOR)
    local guid = r17
    if type(name) == 'string' and name ~= '' then
      -- Strip realm from name for display
      local short = name:match('^([^%-]+)') or name
      out[#out+1] = {
        name = short,
        fullName = name,
        rank = rank or '',
        level = tonumber(level) or 0,
        className = classDisplay or '',
        classToken = classToken or nil,
        zone = zone or '',
        online = online,
        status = status,
        note = note or '',
        officerNote = officerNote or '',
        guid = guid,
      }
    end
  end
  return out
end

local COLUMNS = {
  { key='classIcon', label='', width=22, sortable=false, renderer=function(cell, _, rec)
      if not cell.icon then
        cell.icon = cell:CreateTexture(nil, 'ARTWORK')
        cell.icon:SetPoint('CENTER')
        cell.icon:SetSize(20,20)
      end
      local token = rec and rec.classToken and rec.classToken:upper()
      if token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token] then
        cell.icon:SetTexture('Interface/GLUES/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES')
        cell.icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[token]))
        cell.icon:Show()
      else
        cell.icon:Hide()
      end
    end },
  { key='name', label='Name', width=160, sortable=true, renderer=function(cell, val, rec)
      if not cell.text then return end
      cell.text:SetText(val or '?')
      local token = rec and rec.classToken
      if token and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(token)
        if c then cell.text:SetTextColor(c.r, c.g, c.b) end
      else
        cell.text:SetTextColor(0.85,0.85,0.9)
      end
    end },
  { key='level', label='Lvl', width=34, sortable=true, renderer=function(cell,val)
      if cell.text then cell.text:SetText(val or '?'); cell.text:SetTextColor(1,1,1) end
    end },
  { key='className', label='Class', width=100, sortable=true, renderer=function(cell,val,rec)
      if not cell.text then return end
      local token = rec and rec.classToken
      if token and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(token); if c then cell.text:SetTextColor(c.r,c.g,c.b) end
      else
        cell.text:SetTextColor(0.8,0.8,0.85)
      end
      cell.text:SetText(val or '')
    end },
  { key='rank', label='Rank', width=120, sortable=true },
  { key='zone', label='Zone', width=140, sortable=true },
  { key='online', label='Online', width=60, sortable=true, renderer=function(cell,val)
      if not cell.text then return end
      if val then cell.text:SetText('Yes'); cell.text:SetTextColor(0.3,0.95,0.3) else cell.text:SetText('No'); cell.text:SetTextColor(0.9,0.5,0.5) end
    end },
}

function M:Create(parent)
    local frame = CreateFrame('Frame', nil, parent)
    frame:SetAllPoints()

    -- Header
    local header = CreateFrame('Frame', nil, frame)
    header:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -16)
    header:SetPoint('RIGHT', frame, 'RIGHT', -16, 0)
    header:SetHeight(32)
  local hbg = header:CreateTexture(nil, 'BACKGROUND'); hbg:SetAllPoints(); hbg:SetColorTexture(0.1, 0.1, 0.12, 0.6)
    local titleFS = header:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    titleFS:SetPoint('LEFT', header, 'LEFT', 8, 0)
    titleFS:SetText('Guild Roster')
  titleFS:SetTextColor(0.9, 0.8, 0.6)
    local countFS = header:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    countFS:SetPoint('RIGHT', header, 'RIGHT', -8, 0)
  countFS:SetTextColor(0.7, 0.7, 0.9)
    frame._countFS = countFS

    -- Refresh button
    local refreshBtn = CreateFrame('Button', nil, header, 'UIPanelButtonTemplate')
    refreshBtn:SetPoint('RIGHT', countFS, 'LEFT', -8, 0)
    refreshBtn:SetSize(70, 22)
    refreshBtn:SetText('Refresh')
  refreshBtn:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_TOP')
    GameTooltip:AddLine('Request latest guild roster from server', 1, 1, 1)
    GameTooltip:Show()
  end)
    refreshBtn:SetScript('OnLeave', function() if GameTooltip:IsOwned(refreshBtn) then GameTooltip:Hide() end end)

    -- Grid container
    local gridParent = CreateFrame('Frame', nil, frame)
    gridParent:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 0, -8)
    gridParent:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -8, 8)

    local DataGrid = Addon.Get and (Addon.Get('UI.DataGrid') or Addon.require and Addon.require('UI.DataGrid'))
    if not DataGrid then error('UI.DataGrid not available') end

    local grid = DataGrid:Create(gridParent, COLUMNS, {
        resizable = true,
        multiSelect = false,
        rowStyler = function(r, rec, i)
            if not r._bg then return end
            local alt = (i % 2) == 0
            local token = rec and rec.classToken
            local c
            if token and C_ClassColor and C_ClassColor.GetClassColor then c = C_ClassColor.GetClassColor(token) end
      local baseR, baseG, baseB = 0.07, 0.07, 0.09
      if rec and (rec.online) then baseR, baseG, baseB = 0.09, 0.12, 0.08 end
      if c then -- gentle class tint
        baseR = baseR * 0.5 + c.r * 0.5; baseG = baseG * 0.5 + c.g * 0.5; baseB = baseB * 0.5 + c.b * 0.5
      end
      local a = alt and 0.40 or 0.48
      r._bg:SetColorTexture(baseR, baseG, baseB, a)
            if not r._stripe then
                local s = r:CreateTexture(nil,'BORDER'); s:SetPoint('TOPLEFT', 0, 0); s:SetPoint('BOTTOMLEFT', 0, 0); s:SetWidth(2); r._stripe = s
            end
            if c then r._stripe:SetColorTexture(c.r, c.g, c.b, 0.9) else r._stripe:SetColorTexture(1, 1, 1, 0.08) end
        end,
    })
    frame.grid = grid

    -- Empty/Info state overlay
    local emptyFS = gridParent:CreateFontString(nil, 'OVERLAY', 'GameFontDisableLarge')
    emptyFS:SetPoint('CENTER', gridParent, 'CENTER', 0, 0)
    emptyFS:SetText('')
    emptyFS:Hide()
    frame._emptyFS = emptyFS

    local function updateCount(data)
        local total = #data
        local online = 0; for _,r in ipairs(data) do if r.online then online = online + 1 end end
        countFS:SetText(string.format('%d online / %d total', online, total))
    end

    local function render()
        local inGuild = IsInGuild and IsInGuild()
        local data = BuildRoster()
        -- Default sort: online desc, then name
        table.sort(data, function(a,b)
            if a.online ~= b.online then return a.online and not b.online end
            return (a.name or '') < (b.name or '')
        end)
        grid:SetData(data)
        updateCount(data)
        -- Empty state messaging
        if not inGuild then
            emptyFS:SetText('|cffbbbbbbNot in a guild|r')
            emptyFS:Show()
        elseif #data == 0 then
            emptyFS:SetText('|cffbbbbbbLoading roster…|r')
            emptyFS:Show()
        else
            emptyFS:Hide()
        end
    end
    frame.Render = render

    -- Events: refresh on roster updates
    frame:SetScript('OnShow', function()
        frame:RegisterEvent('GUILD_ROSTER_UPDATE')
        frame:RegisterEvent('PLAYER_GUILD_UPDATE')
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
        elseif GuildRoster then GuildRoster() end
        render()
    end)
    frame:SetScript('OnHide', function()
        frame:UnregisterEvent('GUILD_ROSTER_UPDATE')
        frame:UnregisterEvent('PLAYER_GUILD_UPDATE')
    end)
    frame:SetScript('OnEvent', function(_, evt)
        if evt == 'GUILD_ROSTER_UPDATE' or evt == 'PLAYER_GUILD_UPDATE' then render() end
    end)

    -- Wire refresh button action
    refreshBtn:SetScript('OnClick', function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
        render()
    end)

    -- Lightweight sanity self-test (invoked once after grid build) to ensure DataGrid methods present
    if grid and not frame._gridSelfTested then
        frame._gridSelfTested = true
        local ok = type(grid.SetData) == 'function' and type(grid.SetFilter) == 'function' and type(grid.SetSort) == 'function'
        if not ok then
            local printf = function(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffff6666[GR:RosterGridTest]|r '..tostring(msg)) end end
            printf('DataGrid API incomplete')
        end
    end
    return frame
end

if Addon.provide then Addon.provide('UI.GuildRoster', M) end
return M
