---@diagnostic disable: lowercase-global
-- Annotation-only WoW API stubs for Lua language server. Avoids runtime definitions that could conflict in-game.
-- Extend minimally to keep completion noise low.

---@class Frame
---@field SetScript fun(self:Frame, event:string, handler:function)
---@field Hide fun(self:Frame)
---@field Show fun(self:Frame)
---@field SetSize fun(self:Frame, w:number, h:number)
---@field SetPoint fun(self:Frame, point:string, ...:any)
---@field SetFrameStrata fun(self:Frame, strata:string)
---@field EnableMouse fun(self:Frame, enable:boolean)
---@field SetMovable fun(self:Frame, movable:boolean)
---@field RegisterForDrag fun(self:Frame, ...:string)
---@field StartMoving fun(self:Frame)
---@field StopMovingOrSizing fun(self:Frame)
---@field CreateTexture fun(self:Frame, name:string|nil, layer:string, template:string|nil, subLevel:number|nil):Texture
---@field ClearAllPoints fun(self:Frame)
---@field SetTitle fun(self:Frame, title:string)
---@field GetWidth fun(self:Frame):number
---@field GetHeight fun(self:Frame):number
---@field GetLeft fun(self:Frame):number|nil
---@field GetTop fun(self:Frame):number|nil
---@field _grStrataHooked boolean|nil
---@field RegisterEvent fun(self:Frame, event:string)
---@field UnregisterEvent fun(self:Frame, event:string)
---@field HookScript fun(self:Frame, script:string, handler:function)
---@field IsShown fun(self:Frame):boolean
---@field GetName fun(self:Frame):string|nil

---@class Texture
---@field SetSize fun(self:Texture, w:number, h:number)
---@field SetPoint fun(self:Texture, point:string, ...:any)
---@field SetMask fun(self:Texture, path:string)
---@field ClearMask fun(self:Texture)
---@field Hide fun(self:Texture)
---@field Show fun(self:Texture)
---@field SetTexture fun(self:Texture, path:string)
---@field SetTexCoord fun(self:Texture, ...:number)
---@field GetTexture fun(self:Texture):any

---@return Frame
function CreateFrame(frameType, name, parent, template)
	return {
		SetScript=function() end,
		Hide=function() end,
		Show=function() end,
		SetSize=function() end,
		SetPoint=function() end,
		SetFrameStrata=function() end,
		EnableMouse=function() end,
		SetMovable=function() end,
		RegisterForDrag=function() end,
		StartMoving=function() end,
		StopMovingOrSizing=function() end,
		CreateTexture=function()
			return {
				SetSize=function() end,
				SetPoint=function() end,
				SetMask=function() end,
				ClearMask=function() end,
				Hide=function() end,
				Show=function() end,
				SetTexture=function() end,
				SetTexCoord=function() end,
				GetTexture=function() return nil end,
			}
		end,
		ClearAllPoints=function() end,
		SetTitle=function() end,
		GetWidth=function() return 0 end,
		GetHeight=function() return 0 end,
		GetLeft=function() return 0 end,
		GetTop=function() return 0 end,
	}
end

---@type Frame
UIParent = UIParent

---@class WorldMapFrameClass: Frame
---@field IsShown fun(self:WorldMapFrameClass):boolean
---@field HookScript fun(self:WorldMapFrameClass, script:string, handler:function)
---@type WorldMapFrameClass
WorldMapFrame = WorldMapFrame

function InCombatLockdown() return false end

---@type table<string, number[]>
CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS

---@class GRAddon
---@field Get fun(key:string):any
---@field require fun(key:string):any
---@field safeProvide fun(key:string, factory:function, opts:table)
---@field provide fun(key:string, factory:function, opts:table)
---@field IsProvided fun(key:string):boolean
---@field Logger table
---@field Config table
---@field EventBus table

---@type GRAddon
GuildRecruiter = GuildRecruiter

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
