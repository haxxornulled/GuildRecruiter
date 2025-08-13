---@diagnostic disable: lowercase-global
-- Annotation-only WoW API stubs for Lua language server. Avoids runtime definitions that could conflict in-game.
-- Extend minimally to keep completion noise low.

---@class Frame
---@field SetScript fun(self:Frame, event:string, handler:function)
---@field Hide fun(self:Frame)
---@field Show fun(self:Frame)
---@return Frame
function CreateFrame(frameType, name, parent)
	return { SetScript=function() end, Hide=function() end, Show=function() end }
end

---@return number
function GetTime() return 0 end

---@class C_TimerNamespace
---@field After fun(delay:number, cb:function)
---@field NewTicker fun(interval:number, iterations:number|nil, cb:function)
---@field NewTimer fun(delay:number, cb:function)
---@type C_TimerNamespace
C_Timer = C_Timer

---@param ... any
function print(...) end

-- Add more annotations only as needed.
