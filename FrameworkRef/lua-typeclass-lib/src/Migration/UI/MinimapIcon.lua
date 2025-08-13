-- GuildRecruiter Minimap Icon (uses LibDataBroker + LibDBIcon)
local ADDON_NAME = "GuildRecruiter"
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
if not LDB or not LDBIcon then
    print("[GuildRecruiter] LibDataBroker or LibDBIcon not found. Minimap icon will not be available.")
    return
end

local iconName = "GuildRecruiterMinimapIcon"
local db = _G.GuildRecruiterDB or {}
db.minimap = db.minimap or {}


-- Use default Blizzard icon if custom icon is missing
local iconPath = "Interface\\AddOns\\GuildRecruiter\\icon.tga"
local file = io and io.open and io.open(iconPath, "rb")
if not file then
    iconPath = "Interface\\Icons\\INV_Misc_GroupLooking" -- Blizzard LFG icon as placeholder
else
    file:close()
end

local launcher = LDB:NewDataObject(iconName, {
    type = "launcher",
    text = "GuildRecruiter",
    icon = iconPath,
    OnClick = function(self, button)
        if button == "RightButton" then
            if GuildRecruiter and GuildRecruiter.UI and GuildRecruiter.UI.ConfigWindow and GuildRecruiter.UI.ConfigWindow.OnShow then
                GuildRecruiter.UI.ConfigWindow.OnShow()
            else
                print("[GuildRecruiter] Config UI not available.")
            end
        else
            print("[GuildRecruiter] Left click detected. Implement as needed.")
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("GuildRecruiter")
        tooltip:AddLine("Right-click: Open Config UI", 1, 1, 1)
    end,
})

LDBIcon:Register(iconName, launcher, db.minimap)

-- Expose for other modules
_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.MinimapIcon = launcher
return launcher
