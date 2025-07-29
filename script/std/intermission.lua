--[[
  chungusmod
  
  A module to trigger player query service  
]]--

-- Check if LuaSocket is available (common HTTP library for Lua)
local http = require("socket.http")
local ltn12 = require("ltn12")

-- Configuration
local QUERY_SERVICE_URL = "http://127.0.0.1:8080/intermission" -- Adjust to your server query client URL

spaghetti.addhook("intermission", function(info)
  print("Intermission hook triggered - sending query to service")
  
  -- Method 1: If LuaSocket is available
  if http then
    local response_body = {}
    local res, code, response_headers, status = http.request{
      url = QUERY_SERVICE_URL,
      method = "GET",
      headers = {
        ["User-Agent"] = "ChungusMod/1.0",
        ["Content-Type"] = "application/json"
      },
      sink = ltn12.sink.table(response_body)
    }
    
    if code == 200 then
      print("Successfully queried server: " .. table.concat(response_body))
    else
      print("Failed to query server. Status: " .. (status or "unknown"))
    end
  else
    print("HTTP library not available")
  end
  
end)
