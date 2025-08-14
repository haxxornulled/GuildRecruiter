-- UI/ToastService.lua
-- Minimal toast / notification queue service.
---@diagnostic disable: undefined-global, undefined-field
local ADDON_NAME = 'GuildRecruiter'
local Addon = _G[ADDON_NAME] or {}

local ToastService = {}
ToastService.__index = ToastService

local MAX_QUEUE = 5
local FADE_IN, HOLD, FADE_OUT = 0.18, 2.5, 0.35

function ToastService:CreateFrame()
    if self.frame then return end
    local anchorParent = UIParent
    local f = CreateFrame('Frame', nil, anchorParent)
    f:SetSize(10,10)
    f:SetPoint('TOP', anchorParent, 'TOP', 0, -120)
    f:SetFrameStrata('TOOLTIP')
    f:Hide()
    local bg = f:CreateTexture(nil,'BACKGROUND')
    bg:SetAllPoints()
    bg:SetColorTexture(0,0,0,0.72)
    local border = f:CreateTexture(nil,'BORDER')
    border:SetPoint('TOPLEFT',1,-1)
    border:SetPoint('BOTTOMRIGHT',-1,1)
    border:SetColorTexture(0.85,0.7,0.18,0.9)
    local text = f:CreateFontString(nil,'OVERLAY','GameFontHighlight')
    text:SetPoint('CENTER')
    text:SetJustifyH('CENTER')
    text:SetJustifyV('MIDDLE')
    text:SetText('')
    f.text = text
    self.frame = f
end

function ToastService:Enqueue(msg, opts)
    if not msg or msg == '' then return end
    self.queue = self.queue or {}
    while #self.queue >= MAX_QUEUE do table.remove(self.queue,1) end
    table.insert(self.queue, { text = msg, dur = (opts and opts.hold) or HOLD })
    self:Pump()
end

function ToastService:Pump()
    if self.running then return end
    if not self.queue or #self.queue == 0 then return end
    self.running = true
    self:CreateFrame()
    local entry = table.remove(self.queue,1)
    local f = self.frame
    f.text:SetText(entry.text)
    f:SetWidth(math.max(140, f.text:GetStringWidth()+40))
    f:SetHeight(f.text:GetStringHeight()+22)
    f:SetAlpha(0)
    f:Show()
    local start = GetTime()
    local total = FADE_IN + entry.dur + FADE_OUT
    local function step()
        local elapsed = GetTime() - start
        if elapsed < FADE_IN then
            f:SetAlpha(elapsed / FADE_IN)
        elseif elapsed < FADE_IN + entry.dur then
            f:SetAlpha(1)
        elseif elapsed < total then
            local p = (elapsed - FADE_IN - entry.dur) / FADE_OUT
            f:SetAlpha(1 - p)
        else
            f:Hide(); self.running = false
            if self.queue and #self.queue > 0 then self:Pump() end
            return
        end
        C_Timer.After(0.016, step)
    end
    step()
end

function ToastService:Show(msg, hold)
    self:Enqueue(msg, { hold = hold })
end

if Addon.provide then
    Addon.provide('ToastService', function() return ToastService end, { lifetime = 'SingleInstance', meta={ layer='UI', area='toast' } })
    -- Alias interface to concrete instance
    Addon.provide('IToastService', function(scope) return scope:Resolve('ToastService') end, { lifetime = 'Alias' })
end

return ToastService
