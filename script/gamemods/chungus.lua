--[[
--
-- Chungus xi
--
-- ]]


local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("dkjson")
local settime, intermission = require"std.settime", require"std.intermission"
local commands, playermsg = require"std.commands", require"std.playermsg"
local hooks = {}

local module = {
  config = {
    gamelength = 12, -- minutes
    auth_url = os.getenv("AUTH_URL") or "http://localhost:8081/auth"
  },
  game = {
    mode = "warmup",
    players = {},
    votes = {},
  },
  jwt = nil
}

local function fetchJWT()
  local response_body = {}
  local res, code, headers, status = http.request{
    url = module.config.auth_url,
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


commands.add("rules", function(info) 
  playermsg("\n\f2Rules\f6:\t\t\f2Prop Hunt is like Hide & Seek, but you will hide as a random object on the map!", info.ci)
  playermsg("\f2As a prop\f6:\tYou can \f0SCROLL \f6through the available models, and \f0LEFT CLICK \f6to place it down!", info.ci)
  playermsg("\f6\t\t\tYour player is invisible, but your prop is not! Your prop sometimes makes noises! \f3Don't get caught!", info.ci)
  playermsg("\f2As a hunter\f6:\tSpot the enemy props and gun them down! But be efficient, your \f2ammo only slowly regenerates\f6!", info.ci)
end)

function showplayers()
  print("Players connected: ")
  if next(module.game.players) then
    for client_id, value in pairs(module.game.players) do
      print(client_id)
    end
  else
    print("No players found in module")
  end
end

function startmatch()
  module.on()
end

function readycheck()
  -- module.players
end

spaghetti.addhook("clientconnect", function(info)
  local client_id = info.ci.extra.uuid
  print(client_id .. " has connected")
  module.game.players[client_id] = true
  showplayers()
end)

spaghetti.addhook("clientdisconnect", function(info)
  local client_id = info.ci.extra.uuid
  print("HE CANT USE A STUN " .. client_id .. " HE DISCONNCETED")
  module.game.players[client_id] = nil
  showplayers()
end)

commands.add("ready", function(info)
  server.sendservmsg(info.ci.name .. " has readied up")
  module.on({
    gamelength = 1,
  })
  playermsg("hi bro", info.ci)
  server.rotatemap(true)
end)

commands.add("ready2", function(info)
  server.sendservmsg(info.ci.name .. " has readied up")
  playermsg("hi bro", info.ci)
end)

function module.on(config)
  hooks = {}
  
  print("hello bro")
  module.jwt = fetchJWT()
  intermission.setJWT(module.jwt)

  -- hooks 
  spaghetti.addhook("changemap", function(info)
    print("hello bro 2")
    settime.set(config.gamelength * 60 * 1000)
  end)

end

return module
