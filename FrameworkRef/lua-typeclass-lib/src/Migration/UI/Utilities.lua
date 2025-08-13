-- UI/Utilities.lua
local M = {}

function M.BringFrameToFront(frame)
    if not frame then return end
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(200)
    frame:Raise()
end

return M
