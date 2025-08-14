---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- UI/UI_ChatPanel.lua
-- Minimal embedded chat panel (feed + input). Safe for Retail/Classic.
-- luacheck: push ignore 113
local __args = { ... }; local ADDON_NAME, Addon = __args[1], (__args[2] or {})

local UI = {}
-- Keep a single chat panel instance across attachments
local _instance = nil

local function CreateChatPanel(parent)
    local frame = CreateFrame('Frame', nil, parent)
    frame:SetSize(400, 160)

    -- Background using textures (avoid BackdropTemplate)
    local bg = frame:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints(frame)
    -- Darker, less transparent for readability
    bg:SetColorTexture(0, 0, 0, 0.85)
    -- Subtle inner border
    local border = frame:CreateTexture(nil, 'BACKGROUND', nil, 1)
    border:SetPoint('TOPLEFT', 1, -1)
    border:SetPoint('BOTTOMRIGHT', -1, 1)
    border:SetColorTexture(1, 1, 1, 0.07)

    -- Filter chips row
    local chips = CreateFrame('Frame', nil, frame)
    chips:SetPoint('TOPLEFT', frame, 'TOPLEFT', 6, -6)
    chips:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -6, -6)
    chips:SetHeight(22)
    -- cleaner look: no heavy background, just a subtle bottom divider
    local chipsLine = frame:CreateTexture(nil, 'BACKGROUND', nil, 2)
    chipsLine:SetPoint('TOPLEFT', chips, 'BOTTOMLEFT', 0, -1)
    chipsLine:SetPoint('TOPRIGHT', chips, 'BOTTOMRIGHT', 0, -1)
    chipsLine:SetHeight(1)
    chipsLine:SetColorTexture(1, 1, 1, 0.08)

    local chipOrder = { 'WHISPER', 'GUILD', 'SYSTEM', 'SAY' }
    local chipButtons = {}
    -- Store messages for copy action (id -> text)
    local messageStore = {}
    local nextMsgId = 1

    -- Feed
    local feed = CreateFrame('ScrollingMessageFrame', nil, frame)
    feed:SetPoint('TOPLEFT', frame, 'TOPLEFT', 8, -30)
    feed:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -8, 32)
    feed:SetMaxLines(200)
    feed:SetFading(false)
    feed:SetFadeDuration(3)
    feed:SetTimeVisible(30)
    local fontObj = _G.GameFontNormal
    if fontObj and fontObj.GetFont then
        local fontPath, fontSize, fontFlags = fontObj:GetFont()
        local flags = tostring(fontFlags or "")
        if not flags:find("OUTLINE") then flags = (flags ~= "" and (flags .. ",OUTLINE") or "OUTLINE") end
        feed:SetFont(fontPath, fontSize, flags)
    end
    feed:SetHyperlinksEnabled(true)
    feed:SetJustifyH('LEFT')
    -- Slightly darker local background just for the feed area
    local feedBG = frame:CreateTexture(nil, 'BACKGROUND', nil, 0)
    feedBG:SetPoint('TOPLEFT', frame, 'TOPLEFT', 6, -28)
    feedBG:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -6, 34)
    feedBG:SetColorTexture(0, 0, 0, 0.70)
    -- Empty-state hint (hidden after first message)
    local emptyHint = feed:CreateFontString(nil, 'OVERLAY', 'GameFontDisable')
    emptyHint:SetText('No recent messages yet')
    emptyHint:SetPoint('CENTER', feed, 'CENTER', 0, 0)
    emptyHint:SetAlpha(0.85)

    -- Input
    local input = CreateFrame('EditBox', nil, frame)
    input:SetPoint('LEFT', frame, 'LEFT', 8, 0)
    input:SetPoint('RIGHT', frame, 'RIGHT', -8, 0)
    input:SetPoint('BOTTOM', frame, 'BOTTOM', 0, 6)
    input:SetAutoFocus(false)
    input:SetHeight(24)
    if fontObj and fontObj.GetFont then
        local fontPath, fontSize, fontFlags = fontObj:GetFont()
        input:SetFont(fontPath, fontSize, fontFlags)
    end
    input:SetTextInsets(6, 26, 4, 4)
    -- Input background to improve legibility
    local inputBG = frame:CreateTexture(nil, 'BACKGROUND', nil, 2)
    inputBG:SetPoint('LEFT', input, 'LEFT', -2, -2)
    inputBG:SetPoint('RIGHT', input, 'RIGHT', 2, 2)
    inputBG:SetHeight(24)
    inputBG:SetColorTexture(0, 0, 0, 0.55)

    local chat = Addon.Get and (Addon.Get('IChatFeed') or Addon.Get('ChatFeed'))
    if not chat and Addon.require then
        local ok, inst = pcall(Addon.require, 'ChatFeed')
        if ok then chat = inst end
    end

    -- Templates quick insert dropdown button
    local tplBtn = CreateFrame('Button', nil, frame)
    tplBtn:SetSize(22, 22)
    tplBtn:SetPoint('RIGHT', input, 'RIGHT', -2, 0)
    local ntex = tplBtn:CreateTexture(nil, 'ARTWORK')
    ntex:SetAllPoints(); ntex:SetTexture('Interface/Buttons/WHITE8x8'); ntex:SetVertexColor(1, 1, 1, 0.02)
    tplBtn:SetNormalTexture(ntex)
    local htex = tplBtn:CreateTexture(nil, 'ARTWORK')
    htex:SetAllPoints(); htex:SetTexture('Interface/Buttons/WHITE8x8'); htex:SetVertexColor(1, 1, 1, 0.08)
    tplBtn:SetHighlightTexture(htex)
    -- chevron icon from HUD atlases; fallback to dropdown arrow
    local ticon = tplBtn:CreateTexture(nil, 'OVERLAY')
    ticon:SetPoint('CENTER')
    ticon:SetSize(14, 14)
    if ticon.SetAtlas then ticon:SetAtlas('hud-MainMenuBar-dropdownarrow', true) else ticon:SetTexture(
        'Interface/Buttons/UI-MicroStream-Down') end

    local function getTemplates()
        local SV = Addon.Get and Addon.Get('SavedVarsService')
        local arr = (SV and SV.Get and SV:Get('ui', 'chatTemplates', nil)) or nil
        if type(arr) ~= 'table' then
            -- fallback to config messages
            local cfg = Addon.Get and Addon.Get('IConfiguration')
            local t = {}
            if cfg and cfg.Get then
                for _, k in ipairs({ 'customMessage1', 'customMessage2', 'customMessage3' }) do
                    local v = cfg:Get(k, '')
                    if type(v) == 'string' and v ~= '' then t[#t + 1] = v end
                end
            end
            return t
        end
        -- normalize (string array)
        local t = {}
        for _, v in ipairs(arr) do if type(v) == 'string' and v ~= '' then t[#t + 1] = v end end
        return t
    end

    -- Lightweight templates popover (ephemeral frame per open)
    local function openTemplatesMenu()
        local items = getTemplates()
        if not items or #items == 0 then return end
        local m = CreateFrame('Frame', nil, frame)
        m:SetFrameStrata('FULLSCREEN_DIALOG')
        m:SetSize(220, 10)
        local bg = m:CreateTexture(nil, 'BACKGROUND')
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.9)
        local br = m:CreateTexture(nil, 'BORDER')
        br:SetPoint('TOPLEFT', 1, -1); br:SetPoint('BOTTOMRIGHT', -1, 1); br:SetColorTexture(1, 1, 1, 0.08)
        local y = -6; local w = 220
        for _, txt in ipairs(items) do
            local b = CreateFrame('Button', nil, m)
            b:SetSize(w - 12, 20)
            b:SetPoint('TOPLEFT', 6, y)
            y = y - 22
            local nt = b:CreateTexture(nil, 'ARTWORK')
            nt:SetAllPoints(); nt:SetTexture('Interface/Buttons/WHITE8x8'); nt:SetVertexColor(1, 1, 1, 0.06)
            b:SetNormalTexture(nt)
            local ht = b:CreateTexture(nil, 'ARTWORK')
            ht:SetAllPoints(); ht:SetTexture('Interface/Buttons/WHITE8x8'); ht:SetVertexColor(1, 1, 1, 0.12)
            b:SetHighlightTexture(ht)
            local fs = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
            fs:SetPoint('LEFT', 6, 0); fs:SetJustifyH('LEFT')
            fs:SetText(txt)
            b:SetScript('OnClick', function()
                local cur = input:GetText() or ''
                if cur ~= '' then cur = cur .. ' ' end
                input:SetText(cur .. txt); input:SetFocus(); m:Hide(); m:SetParent(nil)
            end)
        end
        m:SetHeight(-y + 6)
        m:ClearAllPoints(); m:SetPoint('BOTTOMRIGHT', tplBtn, 'TOPRIGHT', 0, 2)
        m:Show()
    end
    tplBtn:SetScript('OnClick', openTemplatesMenu)

    -- Subscribe when shown; unsubscribe when hidden
    local unsubscribe = nil
    -- Ephemeral copy popup
    local function showCopyBox(text)
        if not text or text == '' then return end
        local box = CreateFrame('Frame', nil, frame)
        box:SetSize(480, 56)
        box:SetPoint('CENTER', frame, 'CENTER', 0, 0)
        local bg = box:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.92)
        local br = box:CreateTexture(nil, 'BORDER'); br:SetPoint('TOPLEFT', 1, -1); br:SetPoint('BOTTOMRIGHT', -1, 1); br
            :SetColorTexture(1, 1, 1, 0.10)
        local eb = CreateFrame('EditBox', nil, box)
        eb:SetPoint('TOPLEFT', box, 'TOPLEFT', 8, -8)
        eb:SetPoint('BOTTOMRIGHT', box, 'BOTTOMRIGHT', -28, 8)
        eb:SetAutoFocus(true)
        eb:SetFont((select(1, _G.GameFontNormal:GetFont())), (select(2, _G.GameFontNormal:GetFont())),
            (select(3, _G.GameFontNormal:GetFont())))
        eb:SetTextInsets(4, 4, 4, 4)
        eb:SetText(text)
        eb:HighlightText(0, #text)
        eb:SetFocus()
        local close = CreateFrame('Button', nil, box)
        close:SetPoint('TOPRIGHT', box, 'TOPRIGHT', -6, -6)
        close:SetSize(16, 16)
        local nt = close:CreateTexture(nil, 'ARTWORK')
        nt:SetAllPoints(); nt:SetTexture('Interface/Buttons/WHITE8x8'); nt:SetVertexColor(1, 1, 1, 0.10)
        close:SetNormalTexture(nt)
        local ht = close:CreateTexture(nil, 'ARTWORK')
        ht:SetAllPoints(); ht:SetTexture('Interface/Buttons/WHITE8x8'); ht:SetVertexColor(1, 1, 1, 0.18)
        close:SetHighlightTexture(ht)
        local xfs = close:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall'); xfs:SetPoint('CENTER'); xfs:SetText(
        'X')
        local function dispose()
            box:Hide(); box:SetParent(nil)
        end
        close:SetScript('OnClick', dispose)
        eb:SetScript('OnEscapePressed', dispose)
    end
    frame:SetScript('OnShow', function()
        if chat and type(chat.Subscribe) == 'function' and not unsubscribe then
            unsubscribe = chat:Subscribe(function(msg)
                -- Basic formatting: [HH:MM] [CHAN] Author: text
                local _time = rawget(_G, 'time')
                local _date = rawget(_G, 'date')
                local t = msg.time or (_time and _time()) or 0
                local hh, mm = 0, 0
                if type(t) == 'number' and t > 0 then
                    local d = _date and _date('*t', t)
                    if d then hh, mm = d.hour or 0, d.min or 0 end
                end
                local chan = tostring(msg.channel or '')
                local author = tostring(msg.author or '')
                local text = tostring(msg.text or '')
                local actions = ''
                if author ~= '' then
                    actions = string.format(
                    ' |cff99ddaa[|Hgr:invite:%s|hInvite|h]|r |cffff8899[|Hgr:blacklist:%s|hBlacklist|h]|r |cffddddaa[|Hgr:tpl:%s|hTemplates|h]|r',
                        author, author, author)
                end
                local formatted = string.format('[%02d:%02d] [%s] %s: %s', hh, mm, chan, author, text)
                local id = nextMsgId; nextMsgId = nextMsgId + 1; messageStore[id] = formatted
                actions = actions .. string.format(' |cffcccccc[|Hgr:copy:%d|hCopy|h]|r', id)
                feed:AddMessage(string.format('|cff88ccff[%02d:%02d]|r |cffaacc88[%s]|r %s: %s%s', hh, mm, chan, author,
                    text, actions))
                if emptyHint and emptyHint:IsShown() then emptyHint:Hide() end
            end)
            -- Initialize chip states from feed (guarded)
            local okf, f = pcall(function() return chat.GetFilters and chat:GetFilters() end)
            if okf and type(f) == 'table' then
                for _, k in ipairs(chipOrder) do
                    local b = chipButtons[k]; b:SetChecked(f[k] ~= false)
                end
            end
        end
        -- Show empty hint if there are no messages yet
        if emptyHint and type(feed.GetNumMessages) == 'function' and (feed:GetNumMessages() or 0) == 0 then emptyHint
                :Show() end
    end)
    frame:SetScript('OnHide', function()
        if type(unsubscribe) == 'function' then
            unsubscribe(); unsubscribe = nil
        end
    end)

    -- Hyperlink click handler
    feed:SetScript('OnHyperlinkClick', function(_, link, text, button)
        local ltype, rest = tostring(link):match('^gr:([^:]+):(.+)$')
        if not ltype then return end
        local who = rest
        if ltype == 'invite' then
            local svc = Addon.Get and Addon.Get('InviteService') or (Addon.require and Addon.require('InviteService'))
            if svc and svc.InviteName then svc:InviteName(who, nil, { whisper = true }) end
        elseif ltype == 'blacklist' then
            local pm = (Addon.Get and (Addon.Get('IProspectManager') or Addon.Get('ProspectsManager'))) or
            (Addon.require and Addon.require('ProspectsManager'))
            local feedSvc = Addon.Get and (Addon.Get('IChatFeed') or Addon.Get('ChatFeed'))
            local guidMatch = nil
            -- Try ChatFeed mapping first (from event meta)
            pcall(function() if feedSvc and feedSvc.GetGuidForName then guidMatch = feedSvc:GetGuidForName(tostring(who)) end end)
            -- Fallback: search prospects by name
            if not guidMatch then
                pcall(function()
                    if pm and pm.GetAllGuids and pm.GetProspect then
                        for _, pg in ipairs(pm:GetAllGuids() or {}) do
                            local p = pm:GetProspect(pg)
                            if p and p.name and p.name:lower() == tostring(who):lower() then
                                guidMatch = pg; break
                            end
                        end
                    end
                end)
            end
            local matched = (guidMatch ~= nil) and 1 or 0
            if matched == 1 then
                pcall(function() if pm and pm.Blacklist then pm:Blacklist(guidMatch, 'chat') end end)
                local Main = Addon.Get and Addon.Get('UI.Main') or (Addon.require and Addon.require('UI.Main'))
                if Main and Main.ShowToast then Main:ShowToast('Blacklisted ' .. tostring(who), 3) end
            else
                local Main = Addon.Get and Addon.Get('UI.Main') or (Addon.require and Addon.require('UI.Main'))
                if Main and Main.Show then Main:Show() end
                if Main and Main.SelectCategoryByKey then Main:SelectCategoryByKey('blacklist') end
                if Main and Main.ShowToast then Main:ShowToast('Open Blacklist to add: ' .. tostring(who), 3) end
            end
        elseif ltype == 'tpl' then
            openTemplatesMenu()
        elseif ltype == 'copy' then
            local id = tonumber(who)
            local textToCopy = id and messageStore[id] or ''
            showCopyBox(textToCopy)
        end
    end)

    -- Context menu support (right-click)
    local function getGuidByName(name)
        local nm = tostring(name or '')
        if nm == '' then return nil end
        -- ChatFeed mapping first
        local feedSvc = Addon.Get and (Addon.Get('IChatFeed') or Addon.Get('ChatFeed'))
        local g = nil
        pcall(function() if feedSvc and feedSvc.GetGuidForName then g = feedSvc:GetGuidForName(nm) end end)
        local has1 = (g ~= nil) and 1 or 0
        if has1 == 1 then return g end
        -- Prospects fallback
        local pm = (Addon.Get and (Addon.Get('IProspectManager') or Addon.Get('ProspectsManager'))) or
        (Addon.require and Addon.require('ProspectsManager'))
        local needProspects = (g == nil) and 1 or 0
        if needProspects == 1 then
            pcall(function()
                if pm and pm.GetAllGuids and pm.GetProspect then
                    for _, pg in ipairs(pm:GetAllGuids() or {}) do
                        local p = pm:GetProspect(pg); if p and p.name and p.name:lower() == nm:lower() then
                            g = pg; break
                        end
                    end
                end
            end)
        end
        local has2 = (g ~= nil) and 1 or 0
        if has2 == 1 then return g end
        -- Guild roster fallback (same guild only)
        pcall(function()
            if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
                local n = GetNumGuildMembers()
                for i = 1, (n or 0) do
                    local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17 = GetGuildRosterInfo(
                    i)
                    local nname = r1 -- name
                    local gguid = r17 -- guid (retail often at 17)
                    if type(nname) == 'string' and nname:match('^([^%-]+)') and (nname:match('^([^%-]+)') == nm or nname == nm) and type(gguid) == 'string' and gguid ~= '' then
                        g = gguid; break
                    end
                end
            end
        end)
        return g
    end

    local lastCtxWho, lastCtxCopyId = nil, nil
    feed:SetScript('OnHyperlinkEnter', function(_, link, text)
        local ltype, rest = tostring(link):match('^gr:([^:]+):(.+)$')
        if not ltype then
            lastCtxWho = nil; lastCtxCopyId = nil; return
        end
        if ltype == 'invite' or ltype == 'blacklist' or ltype == 'tpl' then lastCtxWho = rest end
        if ltype == 'copy' then lastCtxCopyId = tonumber(rest) end
    end)
    feed:SetScript('OnHyperlinkLeave', function()
        lastCtxWho = nil; lastCtxCopyId = nil
    end)

    local function openContextMenuAtCursor()
        local m = CreateFrame('Frame', nil, frame)
        m:SetFrameStrata('FULLSCREEN_DIALOG')
        m:SetSize(180, 10)
        local bg = m:CreateTexture(nil, 'BACKGROUND')
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.9)
        local br = m:CreateTexture(nil, 'BORDER')
        br:SetPoint('TOPLEFT', 1, -1); br:SetPoint('BOTTOMRIGHT', -1, 1); br:SetColorTexture(1, 1, 1, 0.10)
        local y = -6
        local function addItem(label, cb)
            local b = CreateFrame('Button', nil, m)
            b:SetSize(168, 20)
            b:SetPoint('TOPLEFT', 6, y)
            y = y - 22
            local nt = b:CreateTexture(nil, 'ARTWORK')
            nt:SetAllPoints(); nt:SetTexture('Interface/Buttons/WHITE8x8'); nt:SetVertexColor(1, 1, 1, 0.06)
            b:SetNormalTexture(nt)
            local ht = b:CreateTexture(nil, 'ARTWORK')
            ht:SetAllPoints(); ht:SetTexture('Interface/Buttons/WHITE8x8'); ht:SetVertexColor(1, 1, 1, 0.12)
            b:SetHighlightTexture(ht)
            local fs = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
            fs:SetPoint('LEFT', 6, 0); fs:SetText(label)
            b:SetScript('OnClick', function()
                m:Hide(); m:SetParent(nil); cb()
            end)
        end
        local hasWho = (type(lastCtxWho) == 'string' and lastCtxWho ~= '') and 1 or 0
        if hasWho == 1 then
            addItem('Invite ' .. lastCtxWho, function()
                local svc = Addon.Get and Addon.Get('InviteService') or
                (Addon.require and Addon.require('InviteService'))
                if svc and svc.InviteName then svc:InviteName(lastCtxWho, nil, { whisper = true }) end
            end)
            addItem('Blacklist ' .. lastCtxWho, function()
                local pm = (Addon.Get and (Addon.Get('IProspectManager') or Addon.Get('ProspectsManager'))) or
                (Addon.require and Addon.require('ProspectsManager'))
                local guid = getGuidByName(lastCtxWho)
                local matched = (guid ~= nil) and 1 or 0
                if matched == 1 then
                    pcall(function() if pm and pm.Blacklist then pm:Blacklist(guid, 'chat') end end)
                else
                    local Main = Addon.Get and Addon.Get('UI.Main') or (Addon.require and Addon.require('UI.Main')); if Main and Main.Show then
                        Main:Show() end; if Main and Main.SelectCategoryByKey then Main:SelectCategoryByKey('blacklist') end
                end
            end)
            addItem('Templates...', function() openTemplatesMenu() end)
        end
        local hasCopy = (lastCtxCopyId ~= nil) and 1 or 0
        if hasCopy == 1 then
            addItem('Copy message', function()
                local txt = messageStore[lastCtxCopyId] or ''
                showCopyBox(txt)
            end)
        end
        m:SetHeight(-y + 6)
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        m:ClearAllPoints(); m:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', cx / scale, cy / scale)
        m:Show()
    end
    feed:SetScript('OnMouseUp', function(_, btn)
        if btn == 'RightButton' then openContextMenuAtCursor() end
    end)

    input:SetScript('OnEnterPressed', function(self)
        local txt = self:GetText() or ''
        if txt ~= '' and chat and type(chat.Send) == 'function' then
            -- If prefixed with /w Name message, route as WHISPER.
            local target, body = nil, txt
            local mName, mBody = txt:match('^/w%s+([^%s]+)%s+(.+)$')
            if mName and mBody then target, body = mName, mBody end
            chat:Send(target, body, { chatType = target and 'WHISPER' or 'SAY' })
        end
        self:SetText('')
        self:ClearFocus()
    end)

    -- Simple border line for the input
    local line = frame:CreateTexture(nil, 'BORDER')
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetPoint('LEFT', input, 'TOPLEFT', 0, 2)
    line:SetPoint('RIGHT', input, 'TOPRIGHT', 0, 2)
    line:SetHeight(1)

    -- Build filter chips (flat tabs with underline selection)
    local function pushFilters()
        local f = {}
        for _, k in ipairs(chipOrder) do
            local b = chipButtons[k]
            f[k] = b and b:GetChecked() and true or false
        end
        pcall(function() return chat.SetFilters and chat:SetFilters(f) end)
    end
    do
        local x = 0
        for _, k in ipairs(chipOrder) do
            local btn = CreateFrame('CheckButton', nil, chips)
            btn:SetSize(72, 20)
            btn:SetPoint('LEFT', chips, 'LEFT', x, 0)
            x = x + 76
            -- no opaque plate; just text and an underline when selected
            local fs = btn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
            fs:SetPoint('CENTER')
            fs:SetText(k)
            fs:SetTextColor(0.85, 0.85, 0.85, 0.9)
            local ul = btn:CreateTexture(nil, 'OVERLAY')
            ul:SetPoint('BOTTOMLEFT', btn, 'BOTTOMLEFT', 8, -1)
            ul:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', -8, -1)
            ul:SetHeight(2)
            ul:SetColorTexture(1, 1, 1, 0.0) -- hidden by default
            btn:SetHighlightTexture('Interface/Buttons/WHITE8x8')
            btn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
            local function refresh()
                local on = btn:GetChecked()
                fs:SetTextColor(on and 1 or 0.8, on and 0.95 or 0.8, on and 0.6 or 0.8, 1)
                ul:SetColorTexture(1, 0.82, 0.2, on and 0.9 or 0)
            end
            btn.refresh = refresh
            btn:SetScript('OnShow', refresh)
            btn:HookScript('OnClick', function(self)
                refresh(); pushFilters()
            end)
            local chk = btn:CreateTexture(nil, 'BACKGROUND') -- invisible checked placeholder for API
            chk:SetAllPoints(); chk:SetColorTexture(0, 0, 0, 0)
            btn:SetCheckedTexture(chk)
            btn:SetNormalTexture('')
            btn:SetChecked(true)
            chipButtons[k] = btn
        end
    end
    -- Initial filter push with defaults (all enabled)
    pcall(pushFilters)

    return { Frame = frame, Feed = feed, Input = input, Chips = chipButtons, TemplatesButton = tplBtn }
end

-- Accept both ChatPanel.Attach(parent) and ChatPanel:Attach(parent)
function UI.Attach(selfOrParent, maybeParent)
    local parent = maybeParent or selfOrParent
    if not _instance then
        _instance = CreateChatPanel(parent)
    else
        -- Re-parent existing frame; callers will handle anchoring
        local f = _instance and _instance.Frame
        if f and f.SetParent then f:SetParent(parent) end
    end
    return _instance
end

if Addon.provide then
    Addon.provide('UI.ChatPanel', UI, { lifetime = 'SingleInstance', meta = { area = 'chat', role = 'ui' } })
end

return UI
-- luacheck: pop
