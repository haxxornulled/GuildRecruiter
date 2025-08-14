local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

-- Use real DI Registration + Container modules for proper circular detection test.
local Registration = dofile('Core/DI/Registration.lua')
local ContainerMod = dofile('Core/DI/Container.lua')
local builder, registry = Registration.newBuilder()

-- Register two services with mutual dependency to trigger cycle detection.
builder:Register(function(scope)
  -- A depends on B
  return { id='A', b = scope:Resolve('ServiceB') }
end):As('ServiceA'):InstancePerDependency():_commit()

builder:Register(function(scope)
  -- B depends on A
  return { id='B', a = scope:Resolve('ServiceA') }
end):As('ServiceB'):InstancePerDependency():_commit()

local root = ContainerMod.BuildContainer(registry)

Harness.AddTest('DI circular dependency detection path', function()
  local ok, err = pcall(function() root:Resolve('ServiceA') end)
  Addon.AssertFalse(ok, 'Expected circular dependency error resolving ServiceA')
  Addon.AssertTrue(type(err)=='string' and err:find('Circular dependency detected'), 'Missing circular dependency marker')
end)

Harness.AddTest('DI root diagnostics shape', function()
  local d = root:Diagnostics()
  Addon.AssertTrue(d.isRoot == true, 'root diagnostics isRoot flag false')
  Addon.AssertTrue(d.services >= 2, 'expected at least 2 services in registry')
end)

return true
