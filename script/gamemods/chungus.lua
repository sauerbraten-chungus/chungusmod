--[[
--
-- Chungus xi
--
-- ]]

local putf, iterators = require"std.putf", require"std.iterators"
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("dkjson")
local settime, intermission = require "std.settime", require "std.intermission"
local commands, playermsg = require "std.commands", require "std.playermsg"
local hooks = {}

local module = {
    config = {
        game_length = 1, -- minutes
        auth_url = os.getenv("AUTH_URL") or "http://localhost:8081/auth",
        hostname = os.getenv("HOSTNAME") or "unknown"
    },
    game = {
        is_competitive = false,
        players = {},
        votes = {},
        ready_count = 0
    },
    chunguses = {},
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

local function startmatch()
    module.on()
    server.rotatemap(true)
end

local function readycheck()
    local player_count = server.numclients(-1, true, true)
    if player_count == module.game.ready_count then
        print("READY CHECK = TRUE")
        return true
    else
        print("READY CHECK = FALSE")
        return false
    end
end

local function get_max_bots()
    local player_count = server.numclients(-1, true, true)
    -- local max_players = cs.maxclients
    local max_players = 8
    return max_players - player_count
end

local function is_spectator(ci)
    return ci.state.state == engine.CS_SPECTATOR
end

spaghetti.addhook("clientconnect", function(info)
    local client_id = info.ci.extra.uuid
    print(client_id .. " has connected")
    module.game.players[client_id] = {
        chungid = ""
    }
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
        local chungid, verification_code = pair:match("([^:]+):(.+)")
        module.chunguses[chungid] = {
            verification_code = verification_code,
            uuid = ""
        }
        print(chungid, verification_code)
    end
end)

spaghetti.addhook("clientdisconnect", function(info)
    local client_id = info.ci.extra.uuid
    local client_chungid = module.game.players[client_id].chungid
    if module.chunguses[client_chungid] then
        module.chunguses[client_chungid].uuid = ""
    end
    if not module.game.is_competitive and module.game.votes[client_id] then
        module.game.ready_count = module.game.ready_count - 1
        module.game.votes[client_id] = nil
        if module.game.ready_count >= 1 then
            server.sendservmsg(info.ci.name .. " has disconnected while readied up")
            server.sendservmsg("All players must re-ready up for match integrity")
            module.game.votes = {}
            module.game.ready_count = 0
        end
    end
    module.game.players[client_id] = nil
    print("HE CANT USE A STUN " .. client_id .. " HE DISCONNCETED")
end)

spaghetti.addhook("intermission", function(info)    
    if not engine.chunguspeer then
        print("no chunguspeer braaaaah")
        return
    else
        print("workr brah")        
        -- CHUNGUS_PLAYERINFO_ALL
        -- packet { 1, HOSTNAME, NUMCLIENTS, CHUNGID_N, ... }
        local p_all = {100, r = 1}
        p_all = putf(p_all, engine.CHUNGUS_PLAYERINFO_ALL, module.config.hostname, server.numclients(-1, true, true))
        for chungid, _ in pairs(module.chunguses) do
            p_all = putf(p_all, chungid)
        end
        engine.enet_peer_send(engine.chunguspeer, 0, p_all:finalize())
        -- CHUNGUS_PLAYERINFO
        -- packet { 2, HOSTNAME, CHUNGID, STAT_N, ... }
        for ci in iterators.clients() do
            local chungid = module.game.players[ci.extra.uuid].chungid
            local p = {100, r = 1}
            p = putf(p, engine.CHUNGUS_PLAYERINFO, module.config.hostname, chungid, ci.name, ci.state.health)
            print(ci.state.health)
            engine.enet_peer_send(engine.chunguspeer, 0, p:finalize())
        end
    end
end)



commands.add("code", function(info)
    print(info.args)
    local client_id = info.ci.extra.uuid
    if not is_spectator(info.ci) or module.game.is_competitive or module.game.players[client_id].chungid ~= "" then return end
    for chungid, _ in pairs(module.chunguses) do
        if info.args == module.chunguses[chungid].verification_code and module.chunguses[chungid].uuid == "" then
            module.chunguses[chungid].uuid = client_id
            module.game.players[client_id].chungid = chungid
            server.unspectate(info.ci)
        end
    end
end)

commands.add("devcode", function(info)
    local client_id = info.ci.extra.uuid
    local debug_chungid = 67
    module.chunguses[debug_chungid] = {
        verification_code = 123456,
        uuid = client_id
    }
    module.game.players[client_id].chungid = debug_chungid
    server.unspectate(info.ci)
end)

commands.add("devready", function(info)
    startmatch()
end)

commands.add("ready", function(info)
    if module.game.is_competitive or is_spectator(info.ci) then return end
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
    if module.game.is_competitive or is_spectator(info.ci) then return end
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
    if module.game.is_competitive or is_spectator(info.ci) then return end
    local total_combatants = server.numclients(-1, true, false, false)
    if total_combatants < cs.maxclients then
        server.aiman.addai(-1, -1)
    else
        playermsg("Cant add anymore bots", info.ci)
    end
end)

commands.add("delbot", function(info)
    if module.game.is_competitive or is_spectator(info.ci) then return end
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
