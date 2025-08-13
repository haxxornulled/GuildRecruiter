-- ExampleTryCatch.lua
local try = require(\"src.TryCatch\")
try{
    function()
        error(\"Try/catch/finally test error\")
    end,
    catch = function(err)
        print(\"Caught error:\", err)
    end,
    finally = function()
        print(\"Finally block runs!\")
    end
}
