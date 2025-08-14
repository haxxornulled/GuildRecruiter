-- tools/tests/prospect_status_spec.lua
-- Tests ProspectStatus constants & helper predicates.
local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

if not Addon.IsProvided('ProspectStatus') then
  dofile('Core/ProspectStatus.lua')
end

Harness.AddTest('ProspectStatus List returns copy', function()
  local S = Addon.require('ProspectStatus')
  local l1 = S.List(); local l2 = S.List()
  Addon.AssertEquals(#l1, #l2, 'list size mismatch')
  l1[1] = 'Mutate'
  Addon.AssertTrue(l2[1] ~= 'Mutate', 'List should return copy')
end)

Harness.AddTest('ProspectStatus predicates', function()
  local S = Addon.require('ProspectStatus')
  Addon.AssertTrue(S.IsNew(S.New), 'IsNew failed')
  Addon.AssertTrue(S.IsActive(S.New), 'IsActive failed for New')
  Addon.AssertTrue(S.IsBlacklisted(S.Blacklisted), 'IsBlacklisted failed')
  Addon.AssertFalse(S.IsActive(S.Blacklisted), 'IsActive should be false for Blacklisted')
end)

return true
