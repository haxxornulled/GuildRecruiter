---@diagnostic disable: undefined-field, undefined-global, param-type-mismatch
-- Port of headless ProspectsService tests into in-game runner.
local Addon = _G.GuildProspector or _G.GuildRecruiter or select(2, ...)
if not Addon or not Addon.RegisterInGameTest then return end

local function svc()
  return Addon.Get and Addon.Get('ProspectsService')
end

local function clearEvents()
  if Addon.TestEvents then for i=#Addon.TestEvents,1,-1 do Addon.TestEvents[i]=nil end end
end

Addon.RegisterInGameTest('InGame Upsert + GetAll', function()
  local s = svc(); if not s then return end
  s:Upsert({ guid='IG-UP-1', name='A', level=10, lastSeen=10 })
  s:Upsert({ guid='IG-UP-2', name='B', level=20, lastSeen=20 })
  local all = s:GetAll(); if #all < 2 then error('expected >=2 prospects') end
end)

Addon.RegisterInGameTest('InGame Update Merge', function()
  local s = svc(); if not s then return end
  s:Upsert({ guid='IG-UP-1', name='A', level=11 })
  local p = s:Get('IG-UP-1'); if not p or p.level ~= 11 then error('level merge failed') end
end)

Addon.RegisterInGameTest('InGame Blacklist + Unblacklist', function()
  local s = svc(); if not s then return end
  s:Blacklist('IG-BL-1','r')
  if not s:IsBlacklisted('IG-BL-1') then error('should be blacklisted') end
  s:Unblacklist('IG-BL-1')
  if s:IsBlacklisted('IG-BL-1') then error('should be unblacklisted') end
end)

Addon.RegisterInGameTest('InGame PruneProspects keeps newest', function()
  local s = svc(); if not s then return end
  s:Upsert({ guid='IG-P-OLDER', lastSeen=1 })
  s:Upsert({ guid='IG-P-NEWER', lastSeen=999 })
  s:Upsert({ guid='IG-P-MID', lastSeen=500 })
  local removed = s:PruneProspects(2)
  local remaining = s:GetAll()
  if #remaining ~= 2 then error('expected 2 remaining after prune') end
  if removed < 1 then error('expected at least one removal') end
end)

Addon.RegisterInGameTest('InGame RemoveProspect publishes event (dup check)', function()
  local s = svc(); if not s then return end
  s:Upsert({ guid='IG-RM-1', lastSeen=123 })
  clearEvents(); s:RemoveProspect('IG-RM-1')
  local found=false
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events')
  local EV = (E and E.Prospects and E.Prospects.Changed) or 'Prospects.Changed'
  if Addon.TestEvents then
    for _,e in ipairs(Addon.TestEvents) do
      if e.event==EV and e.args[1]=='removed' and e.args[2]=='IG-RM-1' then found=true break end
    end
  end
  if not found then error('removed event missing for '..EV) end
end)

Addon.RegisterInGameTest('InGame PruneBlacklist retains newest entries', function()
  local s = svc(); if not s then return end
  s:Blacklist('IG-BL-K1','r1')
  s:Blacklist('IG-BL-K2','r2')
  s:Blacklist('IG-BL-K3','r3')
  local removed = s:PruneBlacklist(2)
  if removed < 1 then error('expected blacklist removal') end
  local bl = s:GetBlacklist(); local count=0; for _ in pairs(bl) do count=count+1 end
  if count ~= 2 then error('expected 2 blacklist entries after prune') end
end)

Addon.RegisterInGameTest('InGame Blacklist events publish', function()
  local s = svc(); if not s then return end
  clearEvents(); s:Blacklist('IG-EVT-1','t'); s:Unblacklist('IG-EVT-1')
  local sawBL,sawUB=false,false
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events')
  local EV = (E and E.Prospects and E.Prospects.Changed) or 'Prospects.Changed'
  if Addon.TestEvents then
    for _,e in ipairs(Addon.TestEvents) do
      if e.event==EV and e.args[1]=='blacklisted' then sawBL=true end
      if e.event==EV and e.args[1]=='unblacklisted' then sawUB=true end
    end
  end
  if not (sawBL and sawUB) then error('missing blacklist change events for '..EV) end
end)
