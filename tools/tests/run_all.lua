-- tools/tests/run_all.lua
-- Auto-discover *spec.lua files under this directory and run them.
package.path = package.path .. ';./?.lua;./tools/?.lua;./tools/tests/?.lua;./Infrastructure/Services/?.lua'
local Harness = require('tools.HeadlessHarness')

local function listSpecs()
  local specs = {}
  local p = io.popen('dir /b')
  for line in p:lines() do
    local fname = tostring(line)
    if fname:match('spec%.lua$') then specs[#specs+1]=fname end
  end
  p:close()
  return specs
end

for _,f in ipairs(listSpecs()) do
  local path = 'tools/tests/'..f
  local ok, err = pcall(dofile, path)
  if not ok then print('[SPEC-LOAD-FAIL] '..path..'  '..tostring(err)) end
end

Harness.RunAll()
return true
