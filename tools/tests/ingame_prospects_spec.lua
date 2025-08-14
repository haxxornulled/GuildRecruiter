---@diagnostic disable: undefined-field
local Addon = _G.GuildProspector or _G.GuildRecruiter or select(2, ...)
if not Addon or not Addon.RegisterInGameTest then return end

Addon.RegisterInGameTest('InGame RemoveProspect event', function()
  local svc = Addon.Get and Addon.Get('ProspectsService')
  if not svc then return end
  svc:Upsert({ guid='IG-Remove', name='Tmp', level=5, lastSeen=0 })
  if Addon.TestEvents then for i=#Addon.TestEvents,1,-1 do Addon.TestEvents[i]=nil end end
  svc:RemoveProspect('IG-Remove')
  local found=false
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events') -- production constant table if loaded
  local EV = (E and E.Prospects and E.Prospects.Changed) or 'Prospects.Changed'
  if Addon.TestEvents then
    for _,e in ipairs(Addon.TestEvents) do
      if e.event==EV and e.args[1]=='removed' and e.args[2]=='IG-Remove' then found=true break end
    end
  end
  if not found then error(EV..' removed event not seen (in-game)') end
end)
