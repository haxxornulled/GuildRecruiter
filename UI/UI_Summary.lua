-- UI.Summary.lua — Summary / landing page
---@diagnostic disable: undefined-global, undefined-field, inject-field, param-type-mismatch
local Addon = select(2, ...)
local M = {}

local function safeRequire(key)
  local ok, mod = pcall(Addon.require, key); if ok then return mod end
end
local function getProspectManager()
  return (Addon.Get and Addon.Get('IProspectManager')) or safeRequire('IProspectManager')
end
local function getProvider()
  return (Addon.Get and Addon.Get('IProspectsReadModel')) or safeRequire('IProspectsReadModel')
end

function M:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints(); f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  title:SetPoint("TOP", 0, -28)
  local guildName = GetGuildInfo("player")
  if guildName then title:SetText(guildName) else title:SetText("Not in a Guild"); title:SetTextColor(.85,.85,.85) end

  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
  sub:SetText("Guild Recruiter — Summary")

  -- Stats block (simple textured background to avoid BackdropTemplate analyzer issues)
  local statsBox = CreateFrame("Frame", nil, f)
  statsBox:SetPoint("TOP", sub, "BOTTOM", 0, -14)
  statsBox:SetSize(480, 170)
  do
    local bg = statsBox:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(0.06,0.06,0.08,0.85)
    -- inner border
    local border = statsBox:CreateTexture(nil, "BACKGROUND", nil, -6)
    border:SetPoint("TOPLEFT", 1, -1)
    border:SetPoint("BOTTOMRIGHT", -1, 1)
    border:SetColorTexture(0.3,0.3,0.35,0.9)
  end

  local header = statsBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOPLEFT", 10, -8)
  header:SetText("Live Stats")

  local lines = {}
  local labels = {
    "Prospects Total","Queue Size","Queue Runtime (heap)","Queue Duplicates","Blacklist Size","Avg Level","Top Classes","Invite History (entries/max)"
  }
  for i,lbl in ipairs(labels) do
    local line = statsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, - ( (i-1) * 16 ) - 4 )
    line:SetText(lbl..": ...")
    lines[lbl] = line
  end

  local hint = statsBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", statsBox, "BOTTOMLEFT", 10, 8)
  hint:SetText("Updates on capture / blacklist / every 10s")

  -- Description block
  local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  desc:SetPoint("TOP", statsBox, "BOTTOM", 0, -14)
  desc:SetJustifyH("CENTER")
  desc:SetText("• Prospects: captured from target, mouseover & nameplates.\n• Queue: FIFO of unguilded, same-faction players.\n• Broadcast: Rotates configured messages to selected channel.")

  -- Event handling
  local bus = safeRequire("EventBus")
  local scheduler = safeRequire("Scheduler")

  local function calcAndRender()
    local pm = getProspectManager()
    local provider = getProvider()
    local cfg = safeRequire("IConfiguration")
    local recruiter = safeRequire("Recruiter") -- only for queue stats fallback
    -- Prospect stats via provider
    local prospectStats = (provider and provider.GetStats and provider:GetStats()) or { total=0, avgLevel=0, topClasses={} }
    local top = prospectStats.topClasses or {}
    local topStr = ""
    for i,t in ipairs(top) do if i>3 then break end topStr = topStr .. (i>1 and "," or "") .. (t.class or "?") .. "("..t.count..")" end
    -- Blacklist via manager
    local blCount = 0
    if pm and pm.GetBlacklist then local bl = pm:GetBlacklist() or {}; for _ in pairs(bl) do blCount = blCount + 1 end end
    -- Queue stats (legacy recruiter)
    local qs = recruiter and recruiter.QueueStats and recruiter:QueueStats() or { total=0, runtime=0, duplicates=0 }
    -- Invite history (best-effort)
    local inviteSvc = safeRequire("InviteService")
    local histCount, histMax = 0, (cfg and cfg:Get("inviteHistoryMax", 1000)) or 1000
    if inviteSvc and inviteSvc.GetInviteHistory then
      local ih = inviteSvc._history or inviteSvc.inviteHistory
      if type(ih) == "table" then for _ in pairs(ih) do histCount = histCount + 1 end end
    end
    lines["Prospects Total"]:SetText("Prospects Total: "..tostring(prospectStats.total or 0))
    lines["Queue Size"]:SetText("Queue Size: "..tostring(qs.total or 0))
    lines["Queue Runtime (heap)"]:SetText("Queue Runtime (heap): "..tostring(qs.runtime or 0))
    lines["Queue Duplicates"]:SetText("Queue Duplicates: "..tostring(qs.duplicates or 0))
    lines["Blacklist Size"]:SetText("Blacklist Size: "..tostring(blCount))
    lines["Avg Level"]:SetText("Avg Level: "..string.format("%.1f", prospectStats.avgLevel or 0))
    lines["Top Classes"]:SetText("Top Classes: "..(topStr ~= "" and topStr or "-"))
    lines["Invite History (entries/max)"]:SetText("Invite History (entries/max): "..histCount.."/"..histMax)
  end

  local tokens = {}
  local function subscribe()
    if not bus or not bus.Subscribe then return end
    local events = { "Recruiter.QueueStats", "Prospects.Changed", "ProspectsManager.Event" }
    for _,ev in ipairs(events) do
      local tok = bus:Subscribe(ev, function() calcAndRender() end, { namespace = "UI.Summary" })
      tokens[#tokens+1] = tok
    end
  end

  function f:Render()
    calcAndRender()
  end

  local refreshTimer
  f:SetScript("OnShow", function()
    bus = bus or safeRequire("EventBus")
    scheduler = scheduler or safeRequire("Scheduler")
    subscribe()
    calcAndRender()
    -- periodic refresh fallback every 10s
    if scheduler and not refreshTimer then
      refreshTimer = scheduler:Every(10, function()
        if f and f.IsShown and f:IsShown() then calcAndRender() end
      end, { namespace = "UI.Summary" })
    end
  end)
  f:SetScript("OnHide", function()
    for _,tok in ipairs(tokens) do bus:Unsubscribe(tok) end
    bus:UnsubscribeNamespace("UI.Summary")
    tokens = {}
  end)

  return f
end

Addon.provide("UI.Summary", M)
return M
