-- Modules/YourFeature.lua
local ADDON_NAME = "TaintedSin"
local Addon = _G[ADDON_NAME]

local Core = Addon.require("Core")
local Class = Addon.require("Class")
local Interface = Addon.require("Interface")
local TypeCheck = Addon.require("TypeCheck")
local TryCatch = Addon.require("TryCatch")

-- Define your interfaces
local IYourFeature = Interface("IYourFeature", {"DoSomething"})

-- Define your classes  
local YourFeatureClass = Class("YourFeatureClass", {
    init = function(self, config)
        self.config = config or {}
    end,
    
    DoSomething = function(self)
        print("YourFeature is doing something!")
    end
})

-- Register with DI container
Core.Register("YourFeatureService", function()
    local feature = YourFeatureClass({})
    assert(TypeCheck.Implements(feature, IYourFeature), "YourFeatureClass does not implement IYourFeature")
    return feature
end, { 
    singleton = true,
    -- deps = {"OtherService"}, -- Add dependencies here
    -- tags = {"defer-init"} -- Add tags if needed
})

-- Optionally expose for testing
Addon.provide("YourFeatureClass", YourFeatureClass)
