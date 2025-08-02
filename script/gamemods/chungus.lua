--[[
--
-- Chungus xi
--
-- ]]


local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("dkjson")
local settime, intermission = require"std.settime", require"std.intermission"
local hooks = {}

local module = {
  config = {
    gamelength = 12, -- minutes
  },
  jwt = nil
}

local function fetchJWT()
  -- Your authentication logic here
  local response_body = {}
  local res, code, headers, status = http.request{
    url = "http://127.0.0.1:8081/auth",
    method = "GET",
    headers = {
      ["CHUNGUS-KEY"] =  "chungus_game",
    },
    sink = ltn12.sink.table(response_body)
  }
  if code == 200 then
    local response_text = table.concat(response_body)
    local success, response_data = pcall(json.decode, response_text)

    if success and response_data.token then
      local jwt = response_data.token
      print("JWT Obtained " .. jwt:sub(1, 20) .. "...")
      return jwt
    else
      print("Failed to parse JWT response: " .. response_text)
      return nil
    end

  else
    print("Failed to get JWT: " .. table.concat(response_body))
    return nil
  end
end

function module.on(config)
  print("hello bro")
  module.jwt = fetchJWT()
  intermission.setJWT(module.jwt)

  spaghetti.addhook("servmodesetup", function(info)
    print("hello bro 2")
    settime.set(config.gamelength * 60 * 1000)
  end)
end

return module
