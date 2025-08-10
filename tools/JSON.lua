-- Tools/JSON.lua - minimal JSON utility (encode + pretty + light decode) for WoW addon (deterministic order for objects)
-- Supports: nil -> null, boolean, number, string (escaped), tables (object vs array heuristic)
-- Decode caveats: numbers parsed via tonumber, strings, true/false/null, nested arrays/objects. No unicode escapes beyond basic \n \r \t. Escaped quotes and backslashes handled. \uXXXX left literal.
-- Array if keys are 1..n contiguous; otherwise object with lexicographically sorted keys.

local ADDON_NAME, Addon = ...
local JSON = {}

local function escape_str(s)
  s = s:gsub('\\', '\\')
       :gsub('"', '\\"')
       :gsub('\n', '\\n')
       :gsub('\r', '\\r')
       :gsub('\t', '\\t')
  return '"'..s..'"'
end

local function is_array(t)
  local count = 0
  for k,_ in pairs(t) do
    if type(k) ~= 'number' then return false end
    count = count + 1
  end
  for i=1,count do if t[i] == nil then return false end end
  return true, count
end

local function encode_val(v, stack)
  local tv = type(v)
  if tv == 'nil' then return 'null'
  elseif tv == 'boolean' then return v and 'true' or 'false'
  elseif tv == 'number' then return tostring(v)
  elseif tv == 'string' then return escape_str(v)
  elseif tv == 'table' then
    if stack[v] then return 'null' end -- circular guard
    stack[v] = true
    local arr, n = is_array(v)
    if arr then
      local parts = {}
      for i=1,n do parts[#parts+1] = encode_val(v[i], stack) end
      stack[v] = nil
      return '['..table.concat(parts, ',')..']'
    else
      local keys = {}
      for k,_ in pairs(v) do keys[#keys+1] = k end
      table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
      local parts = {}
      for _,k in ipairs(keys) do
        local kk = tostring(k)
        parts[#parts+1] = escape_str(kk)..':'..encode_val(v[k], stack)
      end
      stack[v] = nil
      return '{'..table.concat(parts, ',')..'}'
    end
  end
  return 'null'
end

function JSON.Encode(value)
  return encode_val(value, {})
end

-- Pretty-print variant
local function indent(n) return string.rep('  ', n) end
local function encode_pretty(v, stack, depth)
  local tv = type(v)
  if tv ~= 'table' then return encode_val(v, stack) end
  if stack[v] then return 'null' end
  stack[v] = true
  local arr, n = is_array(v)
  if arr then
    if n == 0 then stack[v]=nil; return '[]' end
    local parts = {}
    for i=1,n do parts[#parts+1] = encode_pretty(v[i], stack, depth+1) end
    stack[v]=nil
    return '[\n'..indent(depth+1)..table.concat(parts, ',\n'..indent(depth+1))..'\n'..indent(depth)..']'
  else
    local keys={} ; for k,_ in pairs(v) do keys[#keys+1]=k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    if #keys==0 then stack[v]=nil; return '{}' end
    local parts={}
    for _,k in ipairs(keys) do
      local kv = encode_pretty(v[k], stack, depth+1)
      parts[#parts+1] = indent(depth+1)..escape_str(tostring(k))..': '..kv
    end
    stack[v]=nil
    return '{\n'..table.concat(parts, ',\n')..'\n'..indent(depth)..'}'
  end
end

function JSON.EncodePretty(value)
  return encode_pretty(value, {}, 0)
end

-- No explicit NULL sentinel exposed (nil is sufficient for consumer logic)

Addon.JSON = JSON
Addon.provide("Tools.JSON", JSON, { lifetime = "SingleInstance" })
return JSON
