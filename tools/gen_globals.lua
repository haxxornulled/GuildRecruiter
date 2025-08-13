-- tools/gen_globals.lua
-- Scans addon Lua files for bare global identifiers (simple heuristic) and prints a minimal globals list for settings.json.
-- Usage (run with a standalone Lua interpreter): lua tools/gen_globals.lua > globals.txt

local lfs_ok, lfs = pcall(require, 'lfs')
local root = ... or '.'

local function listFiles(dir, out)
  if lfs_ok then
    for entry in lfs.dir(dir) do
      if entry ~= '.' and entry ~= '..' then
        local p = dir..'/'..entry
        local attr = lfs.attributes(p)
        if attr.mode == 'directory' then listFiles(p, out) elseif entry:match('%.lua$') then out[#out+1]=p end
      end
    end
  else
    -- Fallback: naive (no recursion w/o lfs)
    out[#out+1] = dir
  end
end

local files = {}
listFiles(root, files)

local globals = {}
local function add(g) globals[g]=true end

-- Pre-allow some expected runtime globals
for _,g in ipairs({'Addon','GuildRecruiterDB','Harness'}) do globals[g]=true end

local ioLib = rawget(_G,'io')
for _,file in ipairs(files) do
  local f = ioLib and ioLib.open and ioLib.open(file,'r') or nil
  -- analyzer note: some static analyzers think io.open always returns nil in WoW sandbox; suppress unreachable warning
  ---@diagnostic disable-next-line: unreachable-code
  if f then
    local content = f:read('*a'); f:close()
    -- Remove comments and strings (rough)
    content = content:gsub('%-%-.-\n','\n')
    content = content:gsub('".-"','')
    content = content:gsub("'.-'",'')
    for id in content:gmatch('%f[%a_]%u[%w_]+') do -- uppercase-leading identifiers
      -- Skip common API we don't want to list individually
      if not id:match('^Frame$') then add(id) end
    end
  end
end

local list = {}
for g,_ in pairs(globals) do list[#list+1]=g end
 table.sort(list)
print('Minimal Globals (paste into settings.json Lua.diagnostics.globals):')
print('[')
for i,g in ipairs(list) do
  local comma = (i < #list) and ',' or ''
  print('  "'..g..'"'..comma)
end
print(']')
