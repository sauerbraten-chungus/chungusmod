--[[
--
-- Chungus xi
--
-- ]]

local settime = require"std.settime"
local hooks = {}

local module = {
  config = {
    gamelength = 12, -- minutes
  }
}

function module.on(config)
  print("hello bro")
  spaghetti.addhook("servmodesetup", function(info)
    print("hello bro 2")
    settime.set(config.gamelength * 60 * 1000)
  end)
end

return module
