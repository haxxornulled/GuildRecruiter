---@diagnostic disable: undefined-global, undefined-field, inject-field
local __args = {...}
local AddonName, Addon = __args[1], (__args[2] or _G[__args[1]] or {})
if type(AddonName) ~= 'string' or AddonName == '' then AddonName = 'GuildRecruiter' end
local M = {}

-- Dependency shortcuts (resolved lazily for safety)
local function getProvider()
  if Addon.Get then return Addon.Get("IProspectsReadModel") end
end
local function getProspectManager()
  -- Prefer interface abstraction; fall back to legacy Recruiter for backward compat
  local m = Addon.Get and Addon.Get('IProspectManager')
  if m then return m end
  return Addon.Get and Addon.Get('Recruiter')
end
local function getBus() return Addon.Get and Addon.Get("EventBus") end
local function getLogger()
  local l = Addon.Get and Addon.Get("Logger")
  if l and l.ForContext then return l:ForContext("UI.Prospects") end
  -- Fallback shim with variadic no-op methods to satisfy calls
  local noop = function(...) end
  return { Info=noop, Debug=noop, Warn=noop, Error=noop }
end

-- Column definitions for DataGrid
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
  { key='name', label='Name', width=170, sortable=true, renderer=function(cell, val, rec)
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
  { key='status', label='Status', width=70, sortable=true, renderer=function(cell, val)
      if not cell.text then return end
      local t = val or ''
      cell.text:SetText(t)
      if t == 'Blacklisted' then cell.text:SetTextColor(1,0.35,0.35)
      elseif t == 'New' then cell.text:SetTextColor(0.3,0.95,0.3)
      elseif t == 'Invited' then cell.text:SetTextColor(0.3,0.7,1)
      else cell.text:SetTextColor(1,0.95,0.7) end
    end },
  { key='lastSeen', label='Last Seen', width=90, sortable=true, renderer=function(cell, _, rec)
      if not cell.text or not rec then return end
      local ts = rec.lastSeen or 0
      local out
      if ts == 0 then out = 'Never' else
        local d = (rawget(_G,'time') or function() return 0 end)() - ts
        if d < 60 then out = 'now'
        elseif d < 3600 then out = math.floor(d/60)..'m'
        elseif d < 86400 then out = math.floor(d/3600)..'h'
        else out = math.floor(d/86400)..'d' end
      end
      cell.text:SetText(out)
      cell.text:SetTextColor(0.8,0.8,0.85)
    end },
  { key='actions', label='Actions', width=120, sortable=false }
}

local STATUS_FILTERS = {
  { value='all', label='All' },
  { value='active', label='Active' },
  { value='blacklisted', label='Blacklisted' },
  { value='new', label='New' },
}

local state = { search='', status='all' }
local DEBUG_SPAM=false

local function buildFilterFn()
  local search = (state.search or ''):lower()
  local status = state.status
  local hasSearch = search ~= ''
  return function(p)
  local ps = tostring(p.status or '')
  local st = tostring(status or 'all')
  local okStatus = (st=='all') or (st=='active' and ps~='Blacklisted') or (st=='blacklisted' and ps=='Blacklisted') or (st=='new' and ps=='New')
  if not okStatus then return false end
    if hasSearch then
      local name=(p.name or ''):lower(); local cls=(p.className or p.classToken or ''):lower()
      if not (name:find(search,1,true) or cls:find(search,1,true)) then return false end
    end
    return true
  end
end

function M:Create(parent)
  local frame = CreateFrame('Frame', nil, parent)
  frame:SetAllPoints()

  -- Themed background similar to blacklist view
  -- Texture-based background (avoid BackdropTemplate analyzer complaints)
  local bg = CreateFrame('Frame', nil, frame)
  bg:SetAllPoints()
  local bgTex = bg:CreateTexture(nil,'BACKGROUND',nil,-8)
  bgTex:SetAllPoints(); bgTex:SetColorTexture(0.05,0.05,0.08,0.85)
  local border = bg:CreateTexture(nil,'BACKGROUND',nil,-7)
  border:SetPoint('TOPLEFT', 1, -1); border:SetPoint('BOTTOMRIGHT', -1, 1)
  border:SetColorTexture(0.3,0.3,0.35,0.8)

  -- Title / count header bar
  local headerFrame = CreateFrame('Frame', nil, frame)
  headerFrame:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -16)
  headerFrame:SetPoint('RIGHT', frame, 'RIGHT', -16, 0)
  headerFrame:SetHeight(32)
  local hbg = headerFrame:CreateTexture(nil, 'BACKGROUND')
  hbg:SetAllPoints(); hbg:SetColorTexture(0.1,0.1,0.12,0.6)
  local titleFS = headerFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
  titleFS:SetPoint('LEFT', headerFrame, 'LEFT', 8, 0)
  titleFS:SetText('Active Prospects')
  titleFS:SetTextColor(0.9,0.8,0.6)
  local countFS = headerFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
  countFS:SetPoint('RIGHT', headerFrame, 'RIGHT', -8, 0)
  countFS:SetTextColor(0.7,0.7,0.9)
  frame.countFS = countFS

  -- Filter bar -------------------------------------------------------------
  local bar = CreateFrame('Frame', nil, frame)
  bar:SetPoint('TOPLEFT', headerFrame, 'BOTTOMLEFT', 0, -6)
  bar:SetPoint('TOPRIGHT', headerFrame, 'BOTTOMRIGHT', 0, -6)
  bar:SetHeight(26)
  frame.filterBar = bar

  local search = CreateFrame('EditBox', nil, bar)
  search:SetSize(180,20); search:SetPoint('LEFT', bar, 'LEFT', 0, 0)
  -- style input
  if not search._styled then
    local sb = search:CreateTexture(nil,'BACKGROUND'); sb:SetAllPoints(); sb:SetColorTexture(0.10,0.10,0.12,0.85); search._bg = sb
    local bd = search:CreateTexture(nil,'BACKGROUND'); bd:SetPoint('TOPLEFT', 1, -1); bd:SetPoint('BOTTOMRIGHT', -1, 1); bd:SetColorTexture(0.35,0.35,0.40,0.9)
  end
  search:SetAutoFocus(false); search:SetText(state.search)
  search:SetScript('OnTextChanged', function(self)
    state.search = self:GetText() or ''
    if frame.grid then frame.grid:SetFilter(buildFilterFn()) end
  end)

  -- Replace dropdown with a compact segmented control (buttons)
  local seg = CreateFrame('Frame', nil, bar)
  seg:SetPoint('LEFT', search, 'RIGHT', 8, 0)
  seg:SetHeight(20)
  local x = 0
  for _,f in ipairs(STATUS_FILTERS) do
    local b = CreateFrame('Button', nil, seg)
    b:SetSize(70, 20)
    b:SetPoint('LEFT', seg, 'LEFT', x, 0)
    x = x + 72
    b._bg = b:CreateTexture(nil,'BACKGROUND'); b._bg:SetAllPoints(); b._bg:SetColorTexture(0.16,0.16,0.18,0.85)
    b._hl = b:CreateTexture(nil,'HIGHLIGHT'); b._hl:SetAllPoints(); b._hl:SetColorTexture(1,1,1,0.08)
    local fs = b:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); fs:SetPoint('CENTER'); fs:SetText(f.label)
    b._label = fs
    b:SetScript('OnClick', function()
      state.status = f.value
      if frame.grid then frame.grid:SetFilter(buildFilterFn()); if frame.UpdateStatus then frame:UpdateStatus() end end
      -- update visual selection
      for _,child in ipairs({seg:GetChildren()}) do
        if child._bg then child._bg:SetColorTexture(0.16,0.16,0.18, child==b and 0.95 or 0.85) end
      end
    end)
  end

  -- Bulk action buttons (right side of filter bar)
  local bulk = CreateFrame('Frame', nil, bar)
  bulk:SetPoint('RIGHT', bar, 'RIGHT', 0, 0)
  bulk:SetSize(140, 20)

  local inviteBtn = CreateFrame('Button', nil, bulk)
  inviteBtn:SetSize(60,20)
  inviteBtn:SetPoint('RIGHT', bulk, 'RIGHT', 0, 0)
  inviteBtn:SetText('Invite')
  if not inviteBtn._styled then
    local ntex = inviteBtn:CreateTexture(nil,'BACKGROUND'); ntex:SetAllPoints(); ntex:SetColorTexture(0.18,0.18,0.22,0.85); inviteBtn:SetNormalTexture(ntex)
    local ptex = inviteBtn:CreateTexture(nil,'BACKGROUND'); ptex:SetAllPoints(); ptex:SetColorTexture(0.28,0.28,0.34,0.95); inviteBtn:SetPushedTexture(ptex)
    local htex = inviteBtn:CreateTexture(nil,'HIGHLIGHT'); htex:SetAllPoints(); htex:SetColorTexture(0.35,0.35,0.45,0.9); inviteBtn:SetHighlightTexture(htex)
    inviteBtn._styled = true
  end

  local blBtn = CreateFrame('Button', nil, bulk)
  blBtn:SetSize(70,20)
  blBtn:SetPoint('RIGHT', inviteBtn, 'LEFT', -4, 0)
  blBtn:SetText('Blacklist')
  if not blBtn._styled then
    local ntex = blBtn:CreateTexture(nil,'BACKGROUND'); ntex:SetAllPoints(); ntex:SetColorTexture(0.18,0.18,0.22,0.85); blBtn:SetNormalTexture(ntex)
    local ptex = blBtn:CreateTexture(nil,'BACKGROUND'); ptex:SetAllPoints(); ptex:SetColorTexture(0.28,0.28,0.34,0.95); blBtn:SetPushedTexture(ptex)
    local htex = blBtn:CreateTexture(nil,'HIGHLIGHT'); htex:SetAllPoints(); htex:SetColorTexture(0.35,0.35,0.45,0.9); blBtn:SetHighlightTexture(htex)
    blBtn._styled = true
  end

  -- Grid container ---------------------------------------------------------
  local gridParent = CreateFrame('Frame', nil, frame)
  gridParent:SetPoint('TOPLEFT', bar, 'BOTTOMLEFT', 0, -8)
  gridParent:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -8, 8)

  local DataGrid = Addon.Get and (Addon.Get('UI.DataGrid') or Addon.require and Addon.require('UI.DataGrid'))
  if not DataGrid then error('UI.DataGrid not available') end

  -- Apply persisted column widths & sort
  pcall(function()
    local sv = Addon.Get and Addon.Get('SavedVarsService') or (Addon.require and Addon.require('SavedVarsService'))
    if sv and sv.Get then
      local widths = sv:Get('ui','prospectsColumns')
      if type(widths)=='table' then
        for _,col in ipairs(COLUMNS) do
          local w = widths[col.key]
          if type(w)=='number' and w>=24 and w<=600 then
            ---@diagnostic disable-next-line: assign-type-mismatch
            col.width = w
          end
        end
      end
      local sortState = sv:Get('ui','prospectsSort')
      if type(sortState)=='table' then
        state._initialSortKey = sortState.key
        state._initialSortDesc = sortState.desc and true or false
      end
    end
  end)

  local grid = DataGrid:Create(gridParent, COLUMNS, {
    multiSelect = true,
    resizable = true,
    onRenderRow = function(row, rec)
      local cell = row.cols and row.cols.actions; if not cell then return end
      cell.buttons = cell.buttons or {}
      for _,b in ipairs(cell.buttons) do b:Hide() end
      local idx = 0
      local function make(label, r,g,b, cb, tooltip)
        local btn = cell.buttons[idx+1]
        if not btn then
          btn = CreateFrame('Button', nil, cell)
          cell.buttons[idx+1]=btn
          btn:SetSize(24,18)
        end
        btn:SetPoint('LEFT', cell, 'LEFT', idx*26, 0)
        btn:SetText(label)
        local fs = btn:GetFontString(); fs:ClearAllPoints(); fs:SetPoint('CENTER'); fs:SetFont('Fonts/FRIZQT__.TTF', 10, '')
        if r then fs:SetTextColor(r,g,b) else fs:SetTextColor(0.9,0.9,0.9) end
        -- Pill style
        if not btn._styled then
          -- Replace panel template look with flat backplate without touching internal fields
          local ntex = btn:CreateTexture(nil,'BACKGROUND')
          ntex:SetAllPoints(); ntex:SetColorTexture(0.18,0.18,0.22,0.85)
          btn._bg = ntex
          btn:SetNormalTexture(ntex)
          local ptex = btn:CreateTexture(nil,'BACKGROUND')
          ptex:SetAllPoints(); ptex:SetColorTexture(0.28,0.28,0.34,0.95)
          btn:SetPushedTexture(ptex)
          local htex = btn:CreateTexture(nil,'HIGHLIGHT')
          htex:SetAllPoints(); htex:SetColorTexture(0.35,0.35,0.45,0.9)
          btn:SetHighlightTexture(htex)
          btn._styled=true
        end
        btn:SetScript('OnClick', function() cb(rec) end)
        if tooltip then
          btn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:ClearLines(); GameTooltip:AddLine(tooltip,1,1,1); GameTooltip:Show()
          end)
          btn:SetScript('OnLeave', function() GameTooltip:Hide() end)
        end
        btn:Show(); idx=idx+1; return btn
      end
      make('I',0.3,1,0.3,function(r)
        local pm=getProspectManager(); if pm and pm.InviteProspect and r.guid then pm:InviteProspect(r.guid) end
      end,'Invite')
      if rec.status=='Blacklisted' then
        make('U',0.3,0.3,1,function(r) local pm=getProspectManager(); if pm and pm.Unblacklist and r.guid then pm:Unblacklist(r.guid) end end,'Unblacklist')
      else
        make('B',1,0.3,0.3,function(r) local pm=getProspectManager(); if pm and pm.Blacklist and r.guid then pm:Blacklist(r.guid,'manual') end end,'Blacklist')
      end
      make('X',0.8,0.8,0.8,function(r) local pm=getProspectManager(); if pm and pm.RemoveProspect and r.guid then pm:RemoveProspect(r.guid) end end,'Remove')

      -- Row theming after actions built (match blacklist aesthetics)
  -- Background now handled in rowStyler
      -- Tooltips: status & last seen
      if row.cols and row.cols.status and row.cols.status.text then
        row.cols.status:SetScript('OnEnter', function(self)
          if not rec then return end
          GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:ClearLines()
          GameTooltip:AddLine('Status: '..(rec.status or 'Unknown'),1,1,1)
          if rec.blacklistReason then GameTooltip:AddLine('Reason: '..tostring(rec.blacklistReason),1,0.4,0.4) end
          GameTooltip:Show()
        end)
        row.cols.status:SetScript('OnLeave', function() GameTooltip:Hide() end)
      end
      if row.cols and row.cols.lastSeen and row.cols.lastSeen.text then
        row.cols.lastSeen:SetScript('OnEnter', function(self)
          if not rec then return end
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:ClearLines()
            local ts = rec.lastSeen or 0
            if ts>0 then
              local DateFn = rawget(_G,'date') or function(_,t) return tostring(t or 0) end
              GameTooltip:AddLine(DateFn('%Y-%m-%d %H:%M', ts),0.9,0.9,0.9)
            else
              GameTooltip:AddLine('Never seen',0.9,0.9,0.9)
            end
            GameTooltip:Show()
        end)
        row.cols.lastSeen:SetScript('OnLeave', function() GameTooltip:Hide() end)
      end
    end,
    rowStyler = function(r, rec, i)
      if not r._bg then return end
      local alt = (i % 2)==0
      local token = rec and rec.classToken
      local c
      if token and C_ClassColor and C_ClassColor.GetClassColor then c = C_ClassColor.GetClassColor(token) end
      local baseR,baseG,baseB = 0.07,0.07,0.09
      if rec and rec.status == 'Blacklisted' then
        baseR,baseG,baseB = 0.32,0.05,0.05
  elseif (c ~= nil) then
        -- subtle blend toward class
        baseR = baseR*0.4 + c.r*0.6
        baseG = baseG*0.4 + c.g*0.6
        baseB = baseB*0.4 + c.b*0.6
      end
      local a = alt and 0.40 or 0.48
      r._bg:SetColorTexture(baseR,baseG,baseB,a)
      -- thin class color strip on left
      if not r._classStrip then
        r._classStrip = r:CreateTexture(nil,'OVERLAY')
        r._classStrip:SetPoint('TOPLEFT', r, 'TOPLEFT', 0, 0)
        r._classStrip:SetPoint('BOTTOMLEFT', r, 'BOTTOMLEFT', 0, 0)
        r._classStrip:SetWidth(2)
      end
  if (c ~= nil) then
        r._classStrip:SetColorTexture(c.r,c.g,c.b,1)
        r._classStrip:Show()
      else
        r._classStrip:Hide()
      end
    end
    , onRowClick = function() if frame.UpdateStatus then frame:UpdateStatus() end end
  })
  frame.grid = grid
  grid:SetFilter(buildFilterFn())
  if state._initialSortKey then
    grid:SetSort(state._initialSortKey, state._initialSortDesc)
  end

  -- Style grid header columns to match blacklist palette
  if grid.header and grid.header._colButtons then
    for _,btn in ipairs(grid.header._colButtons) do
      if btn.labelFS then btn.labelFS:SetTextColor(1,0.9,0.6) end
    end
    local rule = grid.header:CreateTexture(nil, 'BORDER')
    rule:SetColorTexture(0.6,0.5,0.3,0.8)
    rule:SetPoint('BOTTOMLEFT', grid.header, 'BOTTOMLEFT', 0, -2)
    rule:SetPoint('BOTTOMRIGHT', grid.header, 'BOTTOMRIGHT', 0, -2)
    rule:SetHeight(2)
    grid.header:SetHeight(grid.header:GetHeight()+2)
    local hb = grid.header:CreateTexture(nil,'BACKGROUND')
    hb:SetAllPoints(); hb:SetColorTexture(0.15,0.12,0.08,0.8)
  end
  
  -- Info bar / status summary
  local info = CreateFrame('Frame', nil, frame)
  info:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 8, 6)
  info:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -8, 6)
  info:SetHeight(18)
  local statusFS = info:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  statusFS:SetPoint('LEFT', info, 'LEFT', 0, 0)
  statusFS:SetText('')
  frame.statusFS = statusFS

  function frame:UpdateStatus()
    if not self.grid then return end
    local total = #self.grid.data
    local filtered = #self.grid.filtered
    local selected = 0
    for _ in pairs(self.grid.selection) do selected = selected + 1 end
    local txt = string.format('Showing %d of %d', filtered, total)
    if selected > 0 then txt = txt .. string.format('  (%d selected)', selected) end
    if self.statusFS then self.statusFS:SetText(txt) end
    if self.countFS then
      local label = (state.status=='active' and 'Active') or (state.status=='blacklisted' and 'Blacklisted') or (state.status=='new' and 'New') or 'Total'
      self.countFS:SetText(string.format('%s: %d', label, filtered))
    end
  end

  -- Bulk button handlers (after UpdateStatus defined)
  inviteBtn:SetScript('OnClick', function()
    local selection = grid:GetSelection()
    local pm = getProspectManager()
    if pm and pm.InviteProspect then
      for _,rec in ipairs(grid.data) do
        if rec.guid and selection[rec.guid] then pm:InviteProspect(rec.guid) end
      end
    end
    grid:ClearSelection(); frame:UpdateStatus()
  end)
  blBtn:SetScript('OnClick', function()
    local selection = grid:GetSelection()
    local pm = getProspectManager()
    if pm and pm.Blacklist then
      for _,rec in ipairs(grid.data) do
        if rec.guid and selection[rec.guid] then pm:Blacklist(rec.guid, 'bulk') end
      end
    end
    grid:ClearSelection(); frame:UpdateStatus()
  end)

  -- Skip auto-reset of filter to 'all' to reduce analyzer noise and keep user intent
  function frame:RefreshData()
    local provider = getProvider()
    if not provider or not grid then return end
    local list = (provider.GetAll and provider:GetAll()) or {}
    grid:SetData(list)
  -- Optional debug logging removed to keep analyzer clean
    self:UpdateStatus()
    if not frame._rowCountFS then
      frame._rowCountFS = frame:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
      frame._rowCountFS:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -10, 6)
      frame._rowCountFS:SetTextColor(0.55,0.75,1)
    end
    frame._rowCountFS:SetText(string.format('Rows: %d', grid and #grid.filtered or 0))
  end

  function frame:ScheduleRefresh()
    if frame._refreshScheduled then return end
    frame._refreshScheduled = true
    C_Timer.After(0.15, function()
      frame._refreshScheduled = false
      if frame:IsShown() then frame:RefreshData() end
    end)
  end

  -- Events -----------------------------------------------------------------
  local bus = getBus()
  if bus and bus.Subscribe and not frame._subscribed then
    frame._subscribed=true
    bus:Subscribe('Prospects.Changed', function() frame:ScheduleRefresh() end, { namespace='UI.Prospects' })
    -- Prefer namespaced events; generics still published but avoid duplicate subscriptions that spam refresh
    bus:Subscribe('GuildRecruiter.ServicesReady', function() frame:ScheduleRefresh() end, { namespace='UI.Prospects.Boot' })
    bus:Subscribe('GuildRecruiter.Ready', function() frame:ScheduleRefresh() end, { namespace='UI.Prospects.Boot' })
  end
  frame:SetScript('OnShow', function() frame:RefreshData() end)
  frame:SetScript('OnHide', function() local b=getBus(); if b and b.UnsubscribeNamespace then b:UnsubscribeNamespace('UI.Prospects') end end)

  frame:RefreshData()
  getLogger():Info('Prospects DataGrid ready')
  frame:UpdateStatus()
  return frame
end

if Addon.provide then Addon.provide('UI.Prospects', M, { meta = { layer = 'UI', area = 'prospects' } }) end
return M