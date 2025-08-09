-- UI/Theme_Dragonfly.lua — simple background theme hook
local _, Addon = ...

local Theme = {}
Addon.Theme = Theme

-- Optional gradient colors other modules can read
Theme.gradient = {
    -- Further lighten so the artwork is more visible
    top    = CreateColor(0.11, 0.12, 0.14, 0.12),
    bottom = CreateColor(0.07, 0.08, 0.09, 0.18),
}

-- Apply a soft background image to any frame
function Theme.ApplyBackground(self, frame)
    if not frame or frame._GR_BG then return end
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    tex:SetAllPoints()
    tex:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
    -- Swap in addon media; fall back gracefully if missing
    local ok = pcall(function()
        tex:SetTexture("Interface\\AddOns\\GuildRecruiter\\Media\\dragonflies.jpg")
    end)
    if not ok then
        -- leave default
    end
    tex:SetHorizTile(false); tex:SetVertTile(false)
    -- Make the artwork more visible (raised alpha)
    tex:SetAlpha(0.55)
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true) end

    -- subtle vignette overlay
    local v = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    v:SetAllPoints()
    -- Ultra subtle vignette; nearly transparent so image stays crisp
    v:SetColorTexture(0, 0, 0, 0.02)

    frame._GR_BG = tex
end

-- Provide for DI/SLP users
Addon.provide("Theme_Dragonfly", Theme)
return Theme
