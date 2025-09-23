--[[
  chungusmod
  
  A module to trigger player query service  
]]--

local http = require("socket.http")
local ltn12 = require("ltn12")

local QUERY_SERVICE_URL = os.getenv("QUERY_SERVICE_URL") or "http://server:8080/intermission"
local stored_jwt = nil

local function setJWT(jwt)
  stored_jwt = jwt
end

spaghetti.addhook("intermission", function(info)
  print("Intermission hook triggered - sending query to service at " .. QUERY_SERVICE_URL)
  if http then
    local response_body = {}
    local res, code, response_headers, status = http.request{
      url = QUERY_SERVICE_URL,
      method = "GET",
      headers = {
        ["User-Agent"] = "ChungusMod/1.0",
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. stored_jwt
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

return {
  setJWT = setJWT
}
