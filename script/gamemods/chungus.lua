--[[
--
-- Chungus xi
--
-- ]]


local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("dkjson")
local settime, intermission = require "std.settime", require "std.intermission"
local commands, playermsg = require "std.commands", require "std.playermsg"
local hooks = {}

local module = {
    config = {
        game_length = 5, -- minutes
        auth_url = os.getenv("AUTH_URL") or "http://localhost:8081/auth"
    },
    game = {
        is_competitive = false,
        players = {},
        votes = {},
        ready_count = 0
    },
    verification_codes = {},
    jwt = nil
}

local function fetchJWT()
    local response_body = {}
    local res, code, headers, status = http.request {
        url = module.config.auth_url,
        method = "GET",
        headers = {
            ["CHUNGUS-KEY"] = "chungus_game",
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
    playermsg("\n\f2Rules\f6:\t\t\f2Prop Hunt is like Hide & Seek, but you will hide as a random object on the map!",
        info.ci)
    playermsg(
        "\f2As a prop\f6:\tYou can \f0SCROLL \f6through the available models, and \f0LEFT CLICK \f6to place it down!",
        info.ci)
    playermsg(
        "\f6\t\t\tYour player is invisible, but your prop is not! Your prop sometimes makes noises! \f3Don't get caught!",
        info.ci)
    playermsg(
        "\f2As a hunter\f6:\tSpot the enemy props and gun them down! But be efficient, your \f2ammo only slowly regenerates\f6!",
        info.ci)
end)



local function showplayers()
    print("Players connected: ")
    if next(module.game.players) then
        for client_id, value in pairs(module.game.players) do
            print(client_id)
        end
    else
        print("No players found in module")
    end
end

local function startmatch()
    module.on()
    server.rotatemap(true)
end

local function readycheck()
    local player_count = server.numclients(-1, true, true)
    if player_count == module.game.ready_count then
        return true
    else
        return false
    end
end

local function get_max_bots()
    local player_count = server.numclients(-1, true, true)
    -- local max_players = cs.maxclients
    local max_players = 8
    return max_players - player_count
end

spaghetti.addhook("clientconnect", function(info)
    local client_id = info.ci.extra.uuid
    print(client_id .. " has connected")
    module.game.players[client_id] = true
    showplayers()
    if not module.game.is_competitive then
        local total_combatants = server.numclients(-1, true, true)
        local total_players = server.numclients(-1, true, false)
        if total_combatants > total_players then
            server.aiman.deleteai()
        end
    end
end)

spaghetti.addhook("chungustrator", function(info)
    print("CHUNGUSTRATOR DEBUG")
    for pair in string.gmatch(info.text, "([^,]+)") do
        local key, value = pair:match("([^:]+):(.+)")
        module.verification_codes[key] = value
        print(key, value)
    end
end)

spaghetti.addhook("clientdisconnect", function(info)
    local client_id = info.ci.extra.uuid
    print("HE CANT USE A STUN " .. client_id .. " HE DISCONNCETED")
    module.game.players[client_id] = nil
    showplayers()
end)

commands.add("code", function(info)
    print(info.args)
    for id, code in module.verification_codes do
        if info.args == code and info.ci.state.state == engine.CS_SPECTATOR then
            print("spectator spotted")
        end
    end
end)

commands.add("ready", function(info)
    if module.game.is_competitive == true then return end
    local client_id = info.ci.extra.uuid
    if module.game.votes[client_id] == nil then
        module.game.votes[client_id] = true
        module.game.ready_count = module.game.ready_count + 1
        playermsg("You are readied-up", info.ci)
        if readycheck() == true then
            startmatch()
        end
    else
        playermsg("You are already readied-up, use \"#unready\" to unready-up", info.ci)
    end
    server.sendservmsg(info.ci.name .. " has readied up")
end)

commands.add("unready", function(info)
    if module.game.is_competitive == true then return end
    local client_id = info.ci.extra.uuid
    if module.game.votes[client_id] == nil then
        playermsg("You are already unreadied-up, use #\"ready\" to ready-up", info.ci)
    else
        module.game.votes[client_id] = nil
        module.game.ready_count = module.game.ready_count - 1
        playermsg("You have unreadied-up", info.ci)
    end
end)

commands.add("addbot", function(info)
    if module.game.is_competitive == true then return end
    local total_combatants = server.numclients(-1, true, false, false)
    if total_combatants < cs.maxclients then
        server.aiman.addai(-1, -1)
    else
        playermsg("Cant add anymore bots", info.ci)
    end
end)

commands.add("delbot", function(info)
    if module.game.is_competitive == true then return end
    server.aiman.deleteai()
end)

function module.on(config)
    module.game.is_competitive = true
    hooks = {}

    print("hello bro")
    module.jwt = fetchJWT()
    intermission.setJWT(module.jwt)

    -- hooks
    hooks.changemap = spaghetti.addhook("changemap", function(info)
        print("hello bro 2")
        settime.set(module.config.game_length * 60 * 1000)
        local num_bots = get_max_bots()
        -- for _ = 1, num_bots do
        --   server.aiman.addai(1, -1)
        -- end
    end)

    spaghetti.addhook("servmodesetup", function(info)
        print("HELLO KEK")
    end)

    -- log hook
    spaghetti.addhook(server.N_ADDBOT, function(info)
        -- if info.skip then return end
        -- info.skip = true
        -- if info.ci.privilege < server.PRIV_ADMIN then playermsg("Only admins can add zombies", info.ci) return end
        print("adding bot")
        server.aiman.addai(1, -1)
    end)
end

return module
