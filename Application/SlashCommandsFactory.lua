-- Application/SlashCommandsFactory.lua
-- Factory that builds the slash command dispatch table and help lines.
---@diagnostic disable: undefined-global
local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})

local function printf(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[%s]|r %s"):format(ADDON_NAME or "GR", tostring(msg))) end
end

local function Args(msg)
    local t = {}
    if not msg then return t end
    for w in tostring(msg):gmatch("%S+") do t[#t + 1] = w end
    return t
end

-- Service helpers (local lookups to avoid repeated global resolution)
local function UI()
    if Addon.Get then
        local svc = Addon.Get('UI.Main') or Addon.Get('UI.MainFrame')
        if svc then return svc end
    end
    if Addon.UI and Addon.UI.Main then return Addon.UI.Main end
    if Addon.require then
        local ok, mod = pcall(Addon.require, 'UI.Main')
        if ok and mod then return mod end
    end
    return nil
end
local function CFG() return (Addon.require and Addon.require('IConfiguration')) or (Addon.Get and Addon.Get('IConfiguration')) end
local function Provider() if Addon.Get then return Addon.Get('IProspectsReadModel') end end
local function Recruiter() return Addon.Get and Addon.Get('Recruiter') end
local function ProspectManager() return (Addon.Get and (Addon.Get('IProspectManager') or Addon.Get('ProspectsManager'))) end

local function Build()
    local version = '?.?'
    -- Try read from toc metadata if baked onto Addon or global
    if Addon and Addon.VERSION then version = tostring(Addon.VERSION)
    elseif _G and _G[ADDON_NAME .. '_VERSION'] then version = tostring(_G[ADDON_NAME .. '_VERSION']) end

    local DISPATCH = {}
    local META = {}  -- command -> { usage, desc, aliasOf, group, schema }
    -- Group labels can be localized; fallback to defaults
    local L = (Addon and (Addon.L or Addon.Locale)) or {}
    local GROUPS = {
        ui = L.GROUP_UI or 'UI',
        admin = L.GROUP_ADMIN or 'Admin',
        data = L.GROUP_DATA or 'Data',
        debug = L.GROUP_DEBUG or 'Debug',
        misc = L.GROUP_MISC or 'Misc'
    }
    local function def(cmd, fn, usage, desc, group, schema)
        DISPATCH[cmd] = fn
        local locKey = 'CMD_' .. string.upper(cmd) .. '_DESC'
        local finalDesc = (L and L[locKey]) or desc or ''
        META[cmd] = { usage = usage or cmd, desc = finalDesc, group = group or 'misc', schema = schema }
        return fn
    end
    local function alias(aliasCmd, target)
        DISPATCH[aliasCmd] = DISPATCH[target]
        META[aliasCmd] = { usage = aliasCmd, desc = '(alias for ' .. target .. ')', aliasOf = target }
    end

    def('ui', function(self, args)
        local ui = UI(); if ui and ui.Show then ui:Show() else printf('Main UI not ready yet.') end
    end, 'ui|toggle', 'Open the main UI', 'ui', { args = {} })
    alias('toggle', 'ui')

    def('roster', function(self, args)
        local ui = UI(); if not ui then printf('UI not ready yet.'); return end
        if ui.AddCategory then pcall(ui.AddCategory, ui, { key = 'roster', label = 'Guild Roster', order = 15 }) end
        if ui.SelectCategoryByKey then pcall(ui.SelectCategoryByKey, ui, 'roster') end
        if ui.Show then pcall(ui.Show, ui) end
        if args[2] == 'refresh' then
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
            printf('Requested guild roster refresh')
        end
    end, 'roster [refresh]', 'Open Guild Roster (optionally refresh)', 'ui', { args = { { name='action', type='enum', values={'refresh'}, optional=true } } })

    def('settings', function(self, args)
        local id = Addon._OptionsCategoryID or (Addon and Addon.TITLE) or 'Guild Prospector'
        local hasSettings = (type(Settings) == 'table') and (type(Settings.OpenToCategory) == 'function')
        if hasSettings then Settings.OpenToCategory(id) else printf('Settings not available.') end
    end, 'settings|options', 'Open settings panel', 'ui', { args = {} })
    alias('options', 'settings')

    def('messages', function(self, args)
        local sub = tostring(args[2] or '')
        if sub == '' or sub == 'help' then printf('Messages: add <n>, remove <n>, list'); return end
        local settingsMod = Addon.require and Addon.require('UI.Settings')
        if not settingsMod then printf('Settings UI not loaded yet'); return end
        if sub == 'add' then
            local n = tonumber(args[3]); if not n then printf('Usage: /gr messages add <n>'); return end
            local ok, res = pcall(settingsMod.AddMessage, settingsMod, n); printf(ok and res or ('Error: ' .. tostring(res)))
        elseif sub == 'remove' then
            local n = tonumber(args[3]); if not n then printf('Usage: /gr messages remove <n>'); return end
            local ok, res = pcall(settingsMod.RemoveMessage, settingsMod, n); printf(ok and res or ('Error: ' .. tostring(res)))
        elseif sub == 'list' then
            local ok, list = pcall(settingsMod.ListMessages, settingsMod)
            if ok and type(list) == 'table' then printf('Messages: ' .. table.concat(list, ', ')) else printf('No messages.') end
        else
            printf('Usage: /gr messages [add <n>|remove <n>|list]')
        end
    end, 'messages add|remove|list', 'Manage rotation messages', 'admin', { dynamic=true }) -- dynamic subcommand validation handled internally

    def('log', function(self, args)
        local action = tostring(args[2] or 'toggle')
        local console = (Addon.require and Addon.require('UI.LogConsole')) or (Addon.Get and Addon.Get('UI.LogConsole'))
        if not console then printf('Log console not available'); return end
        local act = {}
        act.toggle = function()
            local ui = console
            if ui and ui._frame and ui._frame.IsShown then
                local ok, shown = pcall(ui._frame.IsShown, ui._frame)
                if ok and shown then ui:Hide() else ui:Show() end
            else ui:Show() end
        end
        act.show = function() console:Show() end
        act.hide = function() console:Hide() end
        act.clear = function() console:Clear() end
        (act[action] or act.toggle)()
    end, 'log [toggle|show|hide|clear]', 'Log console window', 'debug', { args = { { name='action', type='enum', values={'toggle','show','hide','clear'}, optional=true } } })

    def('devmode', function(self, args)
        local cfg = CFG(); if not cfg then printf('Config not ready.'); return end
        local mode = args[2]
        if mode == 'on' then cfg:Set('devMode', true); printf('Dev mode: ON')
        elseif mode == 'off' then cfg:Set('devMode', false); printf('Dev mode: OFF')
        elseif mode == 'toggle' or not mode then local new = not cfg:Get('devMode', false); cfg:Set('devMode', new); printf('Dev mode toggled: ' .. (new and 'ON' or 'OFF'))
        else printf('Usage: /gr devmode [on|off|toggle]'); return end
        local ui = UI(); if ui and ui.RefreshCategories then pcall(ui.RefreshCategories, ui) end
        if ui and ui.SelectCategoryByKey and not cfg:Get('devMode', false) then ui:SelectCategoryByKey('summary') end
        if ui and ui.ShowToast then pcall(ui.ShowToast, ui, cfg:Get('devMode', false) and 'Dev Mode ENABLED' or 'Dev Mode DISABLED') end
    end, 'devmode [on|off|toggle]', 'Toggle developer mode (shows Debug tab)', 'debug', { args = { { name='mode', type='enum', values={'on','off','toggle'}, optional=true } } })

    def('overlay', function(self, args)
        local action = tostring(args[2] or 'toggle')
        local overlay = (Addon.require and Addon.require('UI.ChatOverlay')) or (Addon.Get and Addon.Get('UI.ChatOverlay'))
        if not overlay then printf('Chat overlay not available'); return end
        local act = {}
        act.toggle = function()
            if overlay.Toggle then overlay:Toggle()
            elseif overlay.Show and overlay.Hide then
                local f = _G and _G['GuildRecruiterChatOverlay']
                if f and f.IsShown and f:IsShown() then overlay:Hide() else overlay:Show() end
            else printf('Overlay API missing Toggle/Show/Hide') end
        end
        act.show = function() if overlay.Show then overlay:Show() end end
        act.hide = function() if overlay.Hide then overlay:Hide() end end
        (act[action] or act.toggle)()
    end, 'overlay [toggle|show|hide]', 'Toggle or control chat overlay', 'ui', { args = { { name='action', type='enum', values={'toggle','show','hide'}, optional=true } } })

    def('prune', function(self, args)
        local which = args[2]; local limit = tonumber(args[3]) or 0
        local pm = ProspectManager(); if not pm then printf('ProspectManager not ready'); return end
        if which == 'prospects' then
            local removed = pm:PruneProspects(limit); printf('Pruned prospects removed=' .. removed .. ' kept=' .. limit)
        elseif which == 'blacklist' then
            local removed = pm:PruneBlacklist(limit); printf('Pruned blacklist removed=' .. removed .. ' kept=' .. limit)
        else printf('Usage: /gr prune prospects <N> | blacklist <N>') end
    end, 'prune prospects|blacklist N', 'Prune stored prospects / blacklist entries', 'data', { args = { { name='which', type='enum', values={'prospects','blacklist'} }, { name='limit', type='number' } } })

    def('queue', function(self, args)
        local sub = args[2]
        if sub ~= 'dedupe' and sub ~= 'fix' then printf('Usage: /gr queue dedupe'); return end
        local rec = Recruiter(); if not rec then printf('Recruiter not ready'); return end
        local before = #rec:GetQueue(); local q = rec:GetQueue(); local seen, newQ = {}, {}
        for _, guid in ipairs(q) do if not seen[guid] then seen[guid] = true; newQ[#newQ + 1] = guid end end
        local ok, err = pcall(function() _G['GuildRecruiterDB'].queue = newQ end)
        local after = #newQ
        printf('Queue deduped: before=' .. before .. ' after=' .. after .. (ok and '' or (' error=' .. tostring(err))))
    end, 'queue dedupe', 'Remove duplicate queue entries', 'data', { args = { { name='action', type='enum', values={'dedupe','fix'} } } })

    def('stats', function(self, args)
        local provider = Provider()
        local providerOk = type(provider)=='table' and type(provider.GetStats)=='function'
        if not providerOk then printf('Stats unavailable (provider)'); return end
        local pm = ProspectManager(); local pmOk = type(pm)=='table' and type(pm.GetBlacklist)=='function'
        if not pmOk then printf('Stats unavailable (manager)'); return end
        local rec = Recruiter(); local recOk = type(rec)=='table' and type(rec.GetQueue)=='function'
        if not recOk then printf('Stats unavailable (recruiter)'); return end
        local st = provider:GetStats() or {}
        local bl = pm:GetBlacklist() or {}
        local blCount = 0; for _ in pairs(bl) do blCount = blCount + 1 end
        printf(string.format('Prospects=%d Active=%d Blacklist=%d Queue=%d AvgLevel=%.1f', st.total or 0, (st.active and st.active.total) or (st.total or 0), blCount, #rec:GetQueue(), st.avgLevel or 0))
    end, 'stats', 'Show prospects / blacklist / queue statistics', 'data', { args = {} })

    def('diag', function(self, args)
        local AddonNs = Addon
        local keys = (AddonNs.ListRegistered and AddonNs.ListRegistered()) or {}
        local groups = { UI = {}, Infrastructure = {}, Core = {}, Application = {}, Other = {} }
        local metaFor = AddonNs.GetRegistrationMetadata or function(_) return {} end
        for _, k in ipairs(keys) do
            local metas = metaFor(k)
            local placed = false
            for _, entry in ipairs(metas) do
                local m = entry.meta or {}
                local layer = m.layer
                local groupTbl = (type(layer)=='string') and groups[layer] or nil
                if groupTbl then table.insert(groupTbl, k); placed = true; break end
            end
            if not placed then
                local s = tostring(k)
                if s:match('^UI[%./]') then table.insert(groups.UI, k)
                elseif s:match('^Infrastructure[%./]') or s:match('^LogSink') or s:match('^LevelSwitch') then table.insert(groups.Infrastructure, k)
                elseif s:match('^Core$') or s:match('^Collections[%.]') or s:match('^Levels$') then table.insert(groups.Core, k)
                elseif s:match('^Application[%./]') or s:match('^IProspectManager$') then table.insert(groups.Application, k)
                else table.insert(groups.Other, k) end
            end
        end
        local function printGroup(name, arr)
            table.sort(arr)
            printf(name .. ' (' .. tostring(#arr) .. '):')
            local line = {}
            for i, kk in ipairs(arr) do
                line[#line + 1] = kk
                if #line >= 6 or i == #arr then
                    printf('  - ' .. table.concat(line, ', '))
                    line = {}
                end
            end
        end
        printGroup('Core', groups.Core)
        printGroup('Infrastructure', groups.Infrastructure)
        printGroup('Application', groups.Application)
        printGroup('UI', groups.UI)
        printGroup('Other', groups.Other)
    end, 'diag layers', 'List registrations grouped by layer', 'debug', { args = { { name='layers', type='literal', value='layers', optional=true } } })

    -- Compact queue / prospects diagnostic (fits within chat frame limits)
    def('qdiag', function(self, args)
        local qs = (Addon.Get and Addon.Get('QueueService')) or (Addon.require and Addon.require('QueueService'))
        local pm = (Addon.Get and (Addon.Get('IProspectManager') or Addon.Get('ProspectsManager')))
        local prov = (Addon.Get and Addon.Get('IProspectsReadModel')) or (Addon.require and Addon.require('IProspectsReadModel'))
        local db = _G.GuildRecruiterDB
        if not db then printf('No DB yet'); return end
        local pCount = 0
        for _ in pairs(db.prospects or {}) do pCount = pCount + 1 end
        local stats = qs and qs.QueueStats and qs:QueueStats() or { total = #(db.queue or {}), duplicates = 0, runtime = #(db.queue or {}) }
        printf(string.format('QDiag P=%d Q=%d tot=%d run=%d dup=%d', pCount, #(db.queue or {}), stats.total or 0, stats.runtime or 0, stats.duplicates or 0))
        local list = {}
        local q = db.queue or {}
        local max = tonumber(args[2]) or 5
        for i = 1, math.min(#q, max) do list[#list+1] = q[i] end
        if #q > max then list[#list+1] = '+' .. (#q - max) end
        if #list > 0 then printf('QList '.. table.concat(list, ',')) else printf('QList <empty>') end
        if args[3] == 'first' and list[1] then
            local g = list[1]
            local p = (db.prospects and db.prospects[g]) or (prov and prov.GetByGuid and prov:GetByGuid(g))
            if p then
                printf(string.format('First %s %s lvl%s status=%s', p.name or '?', p.realm or '', p.level or '?', p.status or '?'))
            end
        end
    end, 'qdiag [N] [first]', 'Quick queue/prospect diagnostics', 'debug', { args = { { name='limit', type='number', optional=true }, { name='detail', type='enum', values={'first'}, optional=true } } })

    -- Seed dummy prospects (test/diagnostics) : /gr pseed 5
    def('pseed', function(self, args)
        local n = tonumber(args[2]) or 1
        if n < 1 then n = 1 elseif n > 50 then n = 50 end
        local ps = (Addon.Get and Addon.Get('ProspectsService')) or nil
        if not ps then
            if Addon.require then pcall(Addon.require, 'ProspectsService') end
            if Addon._RegisterProspectsService then pcall(Addon._RegisterProspectsService) end
            ps = (Addon.Get and Addon.Get('ProspectsService')) or ps
        end
        local qs = Addon.Get and Addon.Get('QueueService') or (Addon.require and Addon.require('QueueService'))
        if not ps then printf('ProspectsService missing (fallback direct)'); end
        local realm = (GetRealmName and GetRealmName()) or 'Realm'
        for i=1,n do
            local guid = string.format('GRTEST-%d-%d', i, math.random(1000,9999))
            local p = { guid = guid, name = 'Test'..i, realm = realm, level = 1 + ((i-1) % 70), classToken = 'WARRIOR', lastSeen = time() }
            if ps and ps.Upsert then
                ps:Upsert(p)
            else
                _G.GuildRecruiterDB = _G.GuildRecruiterDB or { prospects = {}, queue = {}, blacklist = {} }
                local db = _G.GuildRecruiterDB
                db.prospects = db.prospects or {}
                db.prospects[guid] = p
            end
            if qs and qs.Requeue then qs:Requeue(guid) end
        end
        printf('Seeded '..n..' prospects.')
    end, 'pseed N', 'Seed N dummy prospects (+queue)', 'debug', { args = { { name='count', type='number' } } })

    def('about', function(self, args)
        local title = (Addon and Addon.TITLE) or ADDON_NAME or 'Addon'
        printf(string.format('%s v%s - guild recruiting assistant', title, version))
        printf('Type /gr help for commands.')
    end, 'about', 'Show version and addon summary', 'misc', { args = {} })

    def('help', function(self, args)
        printf('Commands (/gr or /gp):')
        local grouped = {}
        for cmd, meta in pairs(META) do
            if not meta.aliasOf then
                local g = meta.group or 'misc'
                grouped[g] = grouped[g] or {}
                table.insert(grouped[g], { cmd = cmd, usage = meta.usage, desc = meta.desc })
            end
        end
        local order = { 'ui','data','admin','debug','misc' }
        for _, code in ipairs(order) do
            local rows = grouped[code]
            if rows then
                table.sort(rows, function(a,b) return a.cmd < b.cmd end)
                printf((' [%s]'):format(GROUPS[code] or code))
                for _, r in ipairs(rows) do
                    printf(string.format('  %-22s - %s', r.usage, r.desc))
                end
            end
        end
        printf(string.format('Version: %s', version))
    end, 'help', 'Show this help', 'misc', { args = {} })

    -- Self-test: iterate through primary commands (excluding those needing arguments) and invoke with safe args
    def('selftest', function(self, args)
        printf('Running command self-test...')
        local skip = { messages = true, prune = true, queue = true, log = true, overlay = true, roster = true }
        local okCount, failCount = 0, 0
        for cmd, meta in pairs(META) do
            local isPrimary = not meta.aliasOf
            local isSkipped = skip[cmd] == true
            local notSelf = cmd ~= 'selftest'
            if isPrimary and (not isSkipped) and notSelf then
                local fn = DISPATCH[cmd]
                local ok, err = pcall(fn, self, { cmd })
                if ok then okCount = okCount + 1 else failCount = failCount + 1; printf('  FAIL ' .. cmd .. ': ' .. tostring(err)) end
            end
        end
        printf(string.format('Self-test complete: ok=%d fail=%d', okCount, failCount))
    end, 'selftest', 'Run lightweight dispatch self-test', 'debug', { args = {} })

    -- In-game test runner bridge
    def('tests', function(self, args)
        -- Ensure runner loaded (attempt soft require)
        if Addon.require then pcall(Addon.require, 'tools.InGameTestRunner') end
        local addonTbl = _G[ADDON_NAME]
        if addonTbl and addonTbl.RunInGameTests then
            addonTbl.RunInGameTests()
        else
            printf('In-game test runner not loaded.')
        end
    end, 'tests|test', 'Run in-game test suite', 'debug', { args = {} })
    alias('test','tests')

    -- Export command (JSON dump of command metadata)
    def('export', function(self, args)
        local sub = args[2]
        if sub ~= 'commands' then printf('Usage: /gr export commands'); return end
        local serializer = (Addon and Addon.require and Addon.require('JSON')) or (Addon and Addon.JSON)
        local exportTbl = { version = version, commands = {} }
        for cmd, meta in pairs(META) do
            if not meta.aliasOf then
                exportTbl.commands[#exportTbl.commands+1] = {
                    name = cmd,
                    usage = meta.usage,
                    desc = meta.desc,
                    group = meta.group,
                    schema = meta.schema
                }
            end
        end
        local encoded
        if serializer and serializer.encode then
            local ok, res = pcall(serializer.encode, exportTbl)
            encoded = ok and res or nil
        end
        if not encoded then
            -- fallback manual simple encoder
            local parts = { '{"version":"'..version..'","commands":[' }
            for i, c in ipairs(exportTbl.commands) do
                parts[#parts+1] = string.format('{"name":"%s","usage":"%s","group":"%s"}', c.name, c.usage, c.group)
                if i < #exportTbl.commands then parts[#parts+1] = ',' end
            end
            parts[#parts+1] = ']}'
            encoded = table.concat(parts)
        end
        -- Split into chat-safe chunks (<=250 chars)
        local maxLen = 230
        local idx = 1
        while idx <= #encoded do
            local chunk = encoded:sub(idx, idx + maxLen - 1)
            printf(chunk)
            idx = idx + maxLen
        end
    end, 'export commands', 'Export command metadata as JSON', 'misc', { args = { { name='what', type='literal', value='commands' } } })

    -- Build completion list (primary commands only)
    local completion = {}
    local subCompletion = {} -- command -> { sub values }
    for cmd, meta in pairs(META) do
        if not meta.aliasOf then
            table.insert(completion, cmd)
            -- derive subcommand completions from schema
            local schema = meta.schema
            if schema and schema.args and schema.args[1] and schema.args[1].type == 'enum' then
                local values = schema.args[1].values
                if type(values)=='table' then
                    subCompletion[cmd] = {}
                    for _,v in ipairs(values) do table.insert(subCompletion[cmd], v) end
                end
            elseif cmd == 'messages' then
                subCompletion[cmd] = { 'add', 'remove', 'list' }
            elseif cmd == 'log' then
                subCompletion[cmd] = { 'toggle','show','hide','clear' }
            elseif cmd == 'overlay' then
                subCompletion[cmd] = { 'toggle','show','hide' }
            end
        end
    end
    table.sort(completion)
    for _, list in pairs(subCompletion) do table.sort(list) end

    -- Validator: basic static schema; dynamic commands (messages) handle internally
    local function validate(cmd, argsTokens)
        local m = META[cmd]; if not m or not m.schema or m.schema.dynamic then return true end
        local schema = m.schema.args or {}
        for i, spec in ipairs(schema) do
            local val = argsTokens[i+1] -- argsTokens[1]=command
            if not val or val == '' then
                if not spec.optional then return false, 'Missing ' .. spec.name end
            else
                if spec.type == 'number' then if not tonumber(val) then return false, 'Expected number for ' .. spec.name end
                elseif spec.type == 'enum' then
                    local ok=false; for _,v in ipairs(spec.values) do if v==val then ok=true break end end
                    if not ok then return false, 'Invalid value for ' .. spec.name end
                elseif spec.type == 'literal' then if val ~= spec.value then return false, 'Expected ' .. spec.value end end
            end
        end
        return true
    end

    local export = { help = {}, dispatch = DISPATCH, Args = Args, meta = META, version = version, completion = completion, subCompletion = subCompletion, groups = GROUPS, validate = validate }
    -- Expose meta API on Addon (idempotent)
    if type(Addon) == 'table' and not Addon.GetCommandMeta then
        function Addon.GetCommandMeta()
            return export.meta, export.groups, export.version
        end
        function Addon.GetCommandCompletion()
            return export.completion, export.subCompletion
        end
    end
    return export
end

if Addon.provide then
    Addon.provide('Application.SlashCommandsFactory', { Build = Build }, { lifetime = 'SingleInstance', meta = { layer = 'Application', area = 'ui/commands', factory = true } })
    Addon.provide('SlashCommandsFactory', { Build = Build }, { lifetime = 'SingleInstance', meta = { layer = 'Application', alias = true } })
end

return { Build = Build }
