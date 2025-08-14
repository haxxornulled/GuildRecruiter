-- Root Config.lua (NOT the infrastructure config service) – registers an Options/Settings panel
-- This file was previously empty; we now use it only to integrate with Blizzard's Settings (Dragonflight)
-- or legacy Interface Options (pre-DF / Classic) so that /gr settings works and users can discover the UI.

local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

-- Analyzer friendly WoW API guards
local _G = _G or {}
local CreateFrame = rawget(_G, 'CreateFrame') or function(...) return { Hide=function() end, Show=function() end } end
local InterfaceOptions_AddCategory = rawget(_G, 'InterfaceOptions_AddCategory')
local InterfaceOptionsFrame_OpenToCategory = rawget(_G, 'InterfaceOptionsFrame_OpenToCategory')
local InterfaceOptionsFramePanelContainer = rawget(_G, 'InterfaceOptionsFramePanelContainer')
local Settings = rawget(_G, 'Settings')
local UIParent = rawget(_G, 'UIParent') or {}
local C_Timer = (rawget(_G, 'C_Timer')) or { After = function(_, fn) if type(fn)=='function' then fn() end end }
local C_AddOns = rawget(_G, 'C_AddOns')

-- Forward reference to our internal settings page (rich UI) so we can open it from a button
local function OpenFullUI(selectSettingsTab)
	local ui = Addon.UI and Addon.UI.Main
	if ui and ui.Show then ui:Show() end
	if selectSettingsTab and ui and ui.SelectCategoryByKey then pcall(ui.SelectCategoryByKey, ui, 'settings') end
end

-- Simple helper to create a frame containing descriptive text + button
local function BuildOptionsFrame()
	local f = CreateFrame('Frame', 'GuildRecruiterOptionsFrame', InterfaceOptionsFramePanelContainer or UIParent)
	-- Some analyzers complain about adding fields; keep a local
	local title = (Addon.TITLE) or 'Guild Prospector'
	f:Hide()

	local header = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	header:SetPoint('TOPLEFT', 16, -16)
	if header.SetText then header:SetText(title .. ' Settings') end

	local desc = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	desc:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 0, -12)
	desc:SetWidth(560)
	desc:SetJustifyH('LEFT')
	desc:SetText('This addon uses an integrated Settings panel with richer controls (message rotation editors, sliders, etc). Click the button below to open the full UI. You can also type /gr ui or /gr settings.')

	local btn = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
	btn:SetPoint('TOPLEFT', desc, 'BOTTOMLEFT', 0, -16)
	btn:SetSize(200, 24)
	btn:SetText('Open Full Settings UI')
	btn:SetScript('OnClick', function() OpenFullUI(true) end)

	local hints = f:CreateFontString(nil, 'OVERLAY', 'GameFontDisable')
	hints:SetPoint('TOPLEFT', btn, 'BOTTOMLEFT', 0, -12)
	hints:SetJustifyH('LEFT')
	hints:SetWidth(540)
	hints:SetText('Shortcuts:\n  /gr ui   – Open main UI\n  /gr settings  – Open Blizzard Settings entry\n  /gr help  – Command reference')

	return f, title
end

-- Dragonflight+ Settings API registration (retail modern)
local function RegisterModernSettings()
	if not Settings or not Settings.RegisterCanvasLayoutCategory then return false end
	local frame = CreateFrame('Frame')
	frame:Hide()
	local title = (Addon.TITLE) or 'Guild Prospector'

	-- Build the rich internal settings panel lazily inside the Settings UI canvas
	frame:SetScript('OnShow', function(self)
		if self._built then return end
		self._built = true
	local inner = BuildOptionsFrame()
		inner:SetParent(self)
		inner:ClearAllPoints()
		inner:SetPoint('TOPLEFT')
		inner:SetPoint('BOTTOMRIGHT')
		inner:Show()
	end)

	local category, layout
	local ok, err = pcall(function()
	layout = Settings.RegisterCanvasLayoutCategory(frame, title)
		category = layout
		Settings.RegisterAddOnCategory(category)
	end)
	if not ok then
		if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffff5555['..ADDON_NAME..'] Settings registration failed: '..tostring(err)) end
		return false
	end
	Addon._OptionsCategoryID = category and category.ID or title
	return true
end

-- Legacy Interface Options registration fallback
local function RegisterLegacyOptions()
	if not InterfaceOptions_AddCategory then return false end
	local frame, title = BuildOptionsFrame()
	if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(frame) end
	Addon._OptionsCategoryID = title
	return true
end

local function TryRegister()
	if RegisterModernSettings() then return end
	RegisterLegacyOptions()
end

-- Attempt immediately (if Settings already loaded) otherwise wait on events
local loader = CreateFrame('Frame')
loader:RegisterEvent('PLAYER_LOGIN')
loader:RegisterEvent('ADDON_LOADED')
loader:RegisterEvent('PLAYER_ENTERING_WORLD')
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('Blizzard_Settings') then
	TryRegister()
end
loader:SetScript('OnEvent', function(self, evt, arg1)
	if evt == 'ADDON_LOADED' and arg1 ~= 'Blizzard_Settings' and arg1 ~= ADDON_NAME then return end
	-- Defer slightly so Blizzard creates root categories
	C_Timer.After(0.25, function()
		if not Addon._OptionsCategoryID then TryRegister() end
	end)
end)

-- Public helper for other modules to open
function Addon.OpenSettings()
	if Settings and Settings.OpenToCategory and Addon._OptionsCategoryID then
		Settings.OpenToCategory(Addon._OptionsCategoryID)
	elseif InterfaceOptionsFrame_OpenToCategory and Addon._OptionsCategoryID then
		InterfaceOptionsFrame_OpenToCategory(Addon._OptionsCategoryID)
		InterfaceOptionsFrame_OpenToCategory(Addon._OptionsCategoryID) -- call twice to work around Blizzard bug
	else
		OpenFullUI(true)
	end
end

return true

