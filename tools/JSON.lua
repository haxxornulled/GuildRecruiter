-- Tools/JSON.lua - JSON utility (encode + pretty + decode) for WoW addon (deterministic order for objects)
-- Supports: nil -> null, boolean, number, string (escaped), tables (object vs array heuristic)
-- Decode: numbers parsed via tonumber, strings, true/false/null, nested arrays/objects.
-- Unicode: \uXXXX sequences are preserved as-is (Lua in WoW lacks native UTF-16 decode without extra tables).
-- Array if keys are 1..n contiguous; otherwise object with lexicographically sorted keys.

local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})
local JSON = {}

local function escape_str(s)
  -- Properly escape backslash and quotes first, then control characters
  s = tostring(s)
  s = s:gsub('\\', '\\\\')
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

-- Decoder (robust enough for config/state payloads)
do
  local function decode_error(str, idx, msg)
    return nil, string.format("%s at position %d", msg or "decode error", idx or 1), idx or 1
  end

  local function skip_ws(str, i)
    local _, j = string.find(str, "^[\t\n\r ]*", i)
    return (j or (i-1)) + 1
  end

  local function parse_value(str, i)
    i = skip_ws(str, i)
    local c = string.sub(str, i, i)
    if c == '"' then
      return (function()
        i = i + 1
        local out = {}
        while i <= #str do
          local ch = string.sub(str, i, i)
          if ch == '"' then
            return table.concat(out), i + 1
          elseif ch == '\\' then
            local nxt = string.sub(str, i+1, i+1)
            if nxt == '"' or nxt == '\\' or nxt == '/' then out[#out+1] = nxt; i = i + 2
            elseif nxt == 'b' then out[#out+1] = '\b'; i = i + 2
            elseif nxt == 'f' then out[#out+1] = '\f'; i = i + 2
            elseif nxt == 'n' then out[#out+1] = '\n'; i = i + 2
            elseif nxt == 'r' then out[#out+1] = '\r'; i = i + 2
            elseif nxt == 't' then out[#out+1] = '\t'; i = i + 2
            elseif nxt == 'u' then
              -- Preserve as-is: \uXXXX
              local seg = string.sub(str, i+1, i+5)
              if not seg:match('^u[%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F]$') then
                return decode_error(str, i, "invalid unicode escape")
              end
              out[#out+1] = '\\'..seg
              i = i + 6
            else
              return decode_error(str, i, "invalid escape")
            end
          else
            out[#out+1] = ch
            i = i + 1
          end
        end
        return decode_error(str, i, "unterminated string")
      end)()
    elseif c == '-' or c:match('%d') then
      local j = i
      local hasDot, hasExp = false, false
      while j <= #str do
        local ch = string.sub(str, j, j)
        if ch >= '0' and ch <= '9' then
          j = j + 1
        elseif ch == '.' and not hasDot then
          hasDot = true; j = j + 1
        elseif (ch == 'e' or ch == 'E') and not hasExp then
          hasExp = true; j = j + 1
          local sign = string.sub(str, j, j)
          if sign == '+' or sign == '-' then j = j + 1 end
        else
          break
        end
      end
  local ii = math.floor(i)
  local jj = math.floor(j-1)
  local num = tonumber(string.sub(str, ii, jj))
      if not num then return decode_error(str, i, "invalid number") end
      return num, j
    elseif string.sub(str, i, i+3) == 'true' then
      return true, i + 4
    elseif string.sub(str, i, i+4) == 'false' then
      return false, i + 5
    elseif string.sub(str, i, i+3) == 'null' then
      return nil, i + 4
    elseif c == '{' then
      local obj = {}
      i = i + 1
      i = skip_ws(str, i)
      if string.sub(str, i, i) == '}' then return obj, i + 1 end
      while true do
        i = skip_ws(str, i)
        if string.sub(str, i, i) ~= '"' then return decode_error(str, i, "expected string key") end
        local key; key, i = parse_value(str, i)
        if key == nil then return decode_error(str, i, "nil key") end
        i = skip_ws(str, i)
        if string.sub(str, i, i) ~= ':' then return decode_error(str, i, "expected colon") end
        local val; val, i = parse_value(str, i + 1)
  obj[tostring(key)] = val
        i = skip_ws(str, i)
        local ch = string.sub(str, i, i)
        if ch == '}' then return obj, i + 1 end
        if ch ~= ',' then return decode_error(str, i, "expected comma or }") end
        i = i + 1
      end
    elseif c == '[' then
      local arr = {}
      i = i + 1
      i = skip_ws(str, i)
      if string.sub(str, i, i) == ']' then return arr, i + 1 end
      local n = 1
      while true do
        local val; val, i = parse_value(str, i)
        arr[n] = val; n = n + 1
        i = skip_ws(str, i)
        local ch = string.sub(str, i, i)
        if ch == ']' then return arr, i + 1 end
        if ch ~= ',' then return decode_error(str, i, "expected comma or ]") end
        i = i + 1
      end
    end
    return decode_error(str, i, "unexpected character")
  end

  function JSON.Decode(str)
    if type(str) ~= 'string' then return nil, "expected string" end
    local val, posOrErr, pos = parse_value(str, 1)
    if pos and type(posOrErr) == 'string' then return nil, posOrErr, pos end
    local i = skip_ws(str, posOrErr or 1)
    if i <= #str then
      -- Trailing non-ws garbage
      return nil, "trailing characters", i
    end
    return val
  end

  function JSON.TryDecode(str)
    local ok, res, err, pos = pcall(JSON.Decode, str)
    if ok then return true, res else return false, res or err, pos end
  end
end

-- No explicit NULL sentinel exposed (nil is sufficient for consumer logic)

Addon.JSON = Addon.JSON or JSON
if Addon.provide then Addon.provide("Tools.JSON", JSON, { lifetime = "SingleInstance" }) end
return JSON
