--[[

  Hide & Seek: Spaghettimod implementation of the classic H&S, with teams "hide" and "seek". If a hider is caught, he will join the seekers and
  fight against a time limit to expose the rest of the hiding players.
  Uses an extra.found field because number of frags are not equivalent to number of found players if the seeker suicides.

]]

local playermsg, commands, setteam, settime = require"std.playermsg",  require"std.commands", require"std.setteam", require"std.settime"
local iterators, spawn, putf, n_client, vars = require"std.iterators", require"std.spawn", require"std.putf", require"std.n_client", require"std.vars"
local fp, L = require"utils.fp", require"utils.lambda"
local map = fp.map

local hooks, laters, inform = {}, {}

local module = {
  config = {
    warmup = 30,     -- seconds
    gamelength = 5,  -- minutes
    fog = true,
    fogcolour = 0x111111,
    fogdistance = 420
  },
  game = {
    has = false
  }
}

--utils
local function fogsync(var, value, who)
  local sender = who or fp.first(iterators.all())
  if not sender then return end
  local p = n_client(putf({ 20, r = 1}, server.N_EDITVAR, engine.ID_VAR, var, value), sender)
  for ci in iterators.all() do
    if ci.team == "hide" or ci.state.state == engine.CS_SPECTATOR or (ci.team == "seek" and not module.game.warmup) then 
      engine.sendpacket(ci.clientnum, 1, p:finalize(), -1)
    end
  end
end

local function respawn(ci)
  ci.state:respawn()
  server.sendspawn(ci)
end

local function blockteams(info)
  if info.skip then return end
  info.skip = true
  playermsg("\f3You cannot switch teams in Hide & Seek", info.ci)
end

local function countteam(team)
  local num = 0
  for p in iterators.inteam(team) do if (p.state.state ~= engine.CS_SPECTATOR) then num = num + 1 end end
  return num, num ~= 1
end

local function checkgame(starting)
  if starting then return not (server.numclients(-1, true, true) < 2), "\f6Hide & Seek mode needs at least \f0two players\f6! Please invite or \f0#add \f6more players to the server!" end
  return not (countteam("hide") == 0 or countteam("seek") == 0), "\f6Hide & Seek mode needs at least \f0two players\f6! Please invite or \f0#add \f6more players to the server!"
end

local function playerout(ci)
  if module.game.nextseeker == ci.clientnum then module.game.nextseeker = nil end
  ci.extra.nextseeker = nil
  if not checkgame() then server.startintermission() end
end

local function caught(ci, loser)
  if ci.team ~= "hide" then return end
  setteam.set(ci, "seek", -1)
  ci.extra.nextseeker, module.game.nextseeker = loser, module.game.nextseeker and module.game.nextseeker or loser and ci.clientnum or nil
  server.sendservmsg("\f4> \f0" .. ci.name .. " \f6has been killed!" .. (loser and " They will start seeking in the next round!" or ""))
  playermsg("\f6You have died and became a seeker! \f3Kill the hiders \f6before the time runs out!!", ci)
  if countteam("hide") == 0 then return server.startintermission() end
  local count, plural = countteam("hide")
  server.sendservmsg("\f4> \f6" .. count .. " hider" .. (plural and "s" or "") .. " to go!")
end

local function cleanup()
  module.game.winners = nil
  for ci in iterators.all() do
    ci.extra.found = 0
    if ci.extra.seeker or ci.clientnum == module.game.seeker then
      ci.extra.seeker = nil
      engine.sendpacket(ci.clientnum, 1, putf({ r = 1 }, server.N_PAUSEGAME, 0):finalize(), -1)
    end
  end
end

local function clearnextseekers()
  for ci in iterators.all() do if ci.extra.nextseeker then ci.extra.nextseeker = nil end end
  module.game.nextseeker = nil
end

-- seekers
local function getseeker()
  local cns, seeker = {}
  for ci in iterators.select(L"_.extra.nextseeker == true") do if ci.extra.nextseeker then seeker = ci end end
  if not seeker then
    for ci in iterators.players() do table.insert(cns, ci.clientnum) end
    seeker = engine.getclientinfo(cns[math.random(#cns)])
  end
  module.game.seeker = seeker.clientnum
  seeker.extra.seeker = true
  return seeker
end

local function prepseeker(ci, config)
  setteam.set(ci, "seek", -1, true)
  engine.sendpacket(ci.clientnum, 1, putf({ 2, r = 1}, server.N_PAUSEGAME, 1):finalize(), -1)
  if server.interm ~= 0 then return end
  engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = true}, server.N_EDITVAR, engine.ID_VAR, "fog", 1), ci):finalize(), -1)
  engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = true}, server.N_EDITVAR, engine.ID_VAR, "fogcolour", 0), ci):finalize(), -1)
  playermsg("\n", ci)
  playermsg("\n", ci)
  playermsg("\f6#####################################################################", ci)
  playermsg("\f3YOU are seeker! \f6You are now freezed. The others have \f0" .. config.warmup .. "s \f6to prepare..", ci)
  playermsg("\f6#####################################################################", ci)
end

local function freeseekers(config)
  for ci in iterators.select(L'_.team == "seek" and _.state.state ~= engine.CS_SPECTATOR') do
    engine.sendpacket(ci.clientnum, 1, putf({ r = 1 }, server.N_PAUSEGAME, 0):finalize(), -1)
    if server.interm ~= 0 then return end
    engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = true}, server.N_EDITVAR, engine.ID_VAR, "fog", config.fog and config.fogdistance or 999999), ci):finalize(), -1)
    engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = true}, server.N_EDITVAR, engine.ID_VAR, "fogcolour", config.fogcolour), ci):finalize(), -1)
    playermsg("\f6########################################################", ci)
    playermsg("\f0The hunt has begun! FIND AND KILL THEM ALL! You have " .. config.gamelength .. " minutes!", ci)
    playermsg("\f6########################################################", ci)
    playermsg(" ", ci)
    server.sendspawn(ci)
  end
end

local function addqueue()
  for ci in iterators.spectators() do
    if not ci.extra.queue then return end
    server.unspectate(ci)  -- queue field will be reset in the specstate hook below
  end
end

local specialmaps = {
  hidden = { fogdistance = 800 },
  asgard = { fogdistance = 750 },
  xenon = { fogdistance = 750 },
  valhalla = { fogdistance = 700 },
  spcr = { fogdistance = 700 },
  berlin_wall = { fogdistance = 600 },
  caribbean = { fogdistance = 600 },
  sacrifice = { fogdistance = 600 },
  urban_c = { fogdistance = 600 },
  europium = { fogdistance = 550 },
  flagstone = { fogdistance = 550 },
  infamy = { fogdistance = 550 },
  arabic = { fogdistance = 400 },
  arbana = { fogdistance = 350 },
  c_egypt = { fogdistance = 300 },
  ruby = { fogdistance = 300 },
  cwcastle = { fogdistance = 250 },
  alloy = { fogdistance = 250 },
  castle_trap = { fogdistance = 250 },
  depot = { fogdistance = 250 },
  guacamole = { fogdistance = 250 },
  DM_BS1 = { fogdistance = 250 },
  frostbyte = { fogdistance = 250 },
  nmp8 = { fogdistance = 250 }
}

local function getconfig(map)
  local config, newconfig = module.config, {}
  for map, mapcfg in pairs(specialmaps) do if map == server.smapname then
    newconfig.fogdistance = mapcfg.fogdistance or config.fogdistance
    newconfig.fogcolour = mapcfg.fogcolour or config.fogcolour
  end end
  return next(newconfig) and newconfig or config
end

local function startgame(config)
    module.game.warmup = true
    local ok, msg = checkgame(true)
    if not ok then
      server.sendservmsg("\f4> \f6" .. msg)
      module.on(false)
      return
    end
    addqueue()
    local seeker = getseeker()
    if not seeker then return end
    clearnextseekers()
    if config.warmup <= 10 then
       engine.writelog("Hide & Seek warmup too quick. Changed to 10 seconds.")
       config.warmup = 10
    end
    local delay, add = 3000, config.warmup * 1000
    laters[1] = spaghetti.latergame(delay, function()
      if module.config.fog then
        local cfg = getconfig(server.smapname)
        vars.editvar("fog", cfg.fogdistance, fogsync)
        vars.editvar("fogcolour", cfg.fogcolour, fogsync)
      end
      server.sendservmsg("\n\n\n\n\f4> \f6HIDE & SEEK WILL START IN " .. config.warmup .. " SECONDS! \f0Take cover!!")
      for ci in iterators.spectators() do setteam(ci, "seek", -1) end
      prepseeker(seeker, config)
    end)
    laters[2] = spaghetti.latergame(3000 + add - 5000, L"server.sendservmsg('\f4> \f6Starting in \f35\f4...')")
    laters[3] = spaghetti.latergame(3000 + add - 4000, L"server.sendservmsg('\f4> \f34\f4...')")
    laters[4] = spaghetti.latergame(3000 + add - 3000, L"server.sendservmsg('\f4> \f33\f4...')")
    laters[5] = spaghetti.latergame(3000 + add - 2000, L"server.sendservmsg('\f4> \f32\f4...')")
    laters[6] = spaghetti.latergame(3000 + add - 1000, L"server.sendservmsg('\f4> \f31\f4...')")
    spaghetti.latergame(delay + add, function()
      gracetime = nil
      map.nf(L"_.state.state == engine.CS_DEAD and server.sendspawn(_)", iterators.clients())
      freeseekers(config)
      if server.interm ~= 0 then return end
      settime.set(config.gamelength * 60 * 1000)
      spaghetti.latergame(1, L"server.sendservmsg('\f4> \f6HIDE & SEEK has STARTED! \f0GOOD LUCK!')")
    end)
end

-- commands

commands.add("has", function(info)
  if module.game.has then return playermsg("\f6Hide & Seek already activated!", info.ci) end
  local ok, msg = checkgame(true)
  if not ok then return playermsg(msg, info.ci) end
  if info.ci.privilege < server.PRIV_MASTER then server.setmaster(info.ci, true, "", nil, nil, server.PRIV_MASTER, true) end
  module.game.has = true
  module.on(true, config)
  server.sendservmsg("\n\f4> \f6Hide & Seek \f0activated\f6! Switching map...")
  spaghetti.later(3000, L'server.rotatemap(true)')
end, "Activate Hide & Seek mode!")

commands.add("add", function(info)
  if info.ci.privilege < server.PRIV_MASTER then playermsg("\f3Only masters and admins can add people to the game.", info.ci) return end           
  if not info.args or info.args == "" or not tonumber(info.args) then playermsg("\f6Please enter the cn of a player to be added to the game.", info.ci) return end
  local who = engine.getclientinfo(tonumber(info.args))
  if not who then playermsg("\f3Cannot find specified client", info.ci) return end
  if not module.game.has then
    server.unspectate(who)
    playermsg("\f6Hide & Seek mode is not active, so the player was only unspecced! Activate the mode with \f0#has", info.ci)
    return  
  end
  who.extra.queue = true
  playermsg("\f6Successfully added \f0" .. who.name .. " \f6to the game, starting on next map.", info.ci)
  playermsg("\f6########################################################", who)
  playermsg("\f0You have been added to the Hide & Seek queue and will join on the next map!", who)
  playermsg("\f6########################################################", who)
end, "#add <cn>: Add a spectator to the Hide & Seek queue")

-- always preserve teams
spaghetti.addhook("autoteam", function(info)
  if info.skip or not module.game.has or not info.ci then return end
  info.skip = true
  setteam(info.ci, "hide", -1, true)
end)
spaghetti.addhook(server.N_SETTEAM, blockteams)
spaghetti.addhook(server.N_SWITCHTEAM, blockteams)
spaghetti.addhook("connected", function(info) if module.game.has then setteam(info.ci, "hide", -1, true) end end)

-- main module
function module.on(state, config)
  map.np(L"spaghetti.removehook(_2)", hooks)
  if inform then spaghetti.cancel(inform) end
  commands.remove("rules")
  commands.remove("fog")
  if not state then
    module.game.has, server.mastermode = false, server.MM_OPEN
    engine.sendpacket(-1, 1, putf({ r = true }, server.N_MASTERMODE, server.mastermode):finalize(), -1)
    return
  end
  if not config then config = module.config end
  module.config = config
  server.mastermode = server.MM_LOCKED
  engine.sendpacket(-1, 1, putf({ r = true }, server.N_MASTERMODE, server.mastermode):finalize(), -1)
  
  inform = spaghetti.later(30000, function()
    for ci in iterators.spectators() do
      if not ci.extra.queue then return end
      playermsg("\f6An active Hide & Seek game is running. \f0You will be added on the next map. \f6In the meantime, read the \f0#rules\f6!", ci)
    end
  end, true)
  
  commands.add("rules", function(info)
    playermsg("\f6One player starts off as the seeker, everyone else has to hide within \f0" .. config.warmup .. " seconds\f6.", info.ci)
    playermsg("\f6If the seeking team manages to catch everyone before time is up, the seekers win. If not, the hiders have won.", info.ci)
    playermsg("\f6If you are caught, you will turn into a seeker as well. Masters can add new players to the game with \f0#add <cn>\f6.", info.ci)  
  end)
  
  commands.add("fog", function(info)
    if info.ci.privilege < server.PRIV_MASTER then playermsg("\f3Only masters and admins can toggle the fog.", info.ci) return end           
    if config.fog then
      local cfg = getconfig(server.smapname)
      vars.editvar("fog", 999999, fogsync)
      vars.editvar("fogcolour", cfg.fogcolour, fogsync)
    else
      local cfg = getconfig(server.smapname)
      vars.editvar("fog", cfg.fogdistance, fogsync)
      vars.editvar("fogcolour", cfg.fogcolour, fogsync)
    end
    module.config.fog = not module.config.fog
    config.fog = module.config.fog
    server.sendservmsg("\f4> \f6Fog has been " .. (module.config.fog and "\f0enabled" or "\f4disabled") .. "\f6!")
  end, "#fog: Toggle on/off the fog")
  
  hooks = {}
  
  -- damage hooks
  hooks.dodamage = spaghetti.addhook("dodamage", function(info)
    if info.skip then return end
    if (info.actor.team == "hide" and info.target.team == "seek") or (info.actor.team == info.target.team) then 
      info.skip = true
      playermsg("\f6You \f3cannot \f6attack your teammates or the seeker.", info.actor)
    end
  end)
  hooks.damageeffects = spaghetti.addhook("damageeffects", function(info)
    if info.skip then return end
    if (info.actor.team == "hide" and info.target.team == "seek") or (info.actor.team == info.target.team) then
      info.skip = true 
      local push = info.hitpush
      push.x, push.y, push.z = 0, 0, 0
    end
  end)
  hooks.damaged = spaghetti.addhook("damaged", function(info)
    if info.target.state.state ~= engine.CS_DEAD and info.target.team ~= "hide" then return end
    local actor, target, loser = info.actor, info.target, not module.game.nextseeker
    actor.extra.found = (actor.extra.found or 0) + 1
    caught(target, loser)
  end)
  hooks.suicide = spaghetti.addhook(server.N_SUICIDE, function(info)
    if info.skip or info.ci.state.state == engine.CS_SPECTATOR then return end
    info.skip = true
    respawn(info.ci)
    if module.game.warmup then return end
    caught(info.ci, not module.game.nextseeker)
    if not checkgame() then server.startintermission() return end
  end)
  
  -- game status hooks
  hooks.prechangemap = spaghetti.addhook("prechangemap", cleanup)
  hooks.changemap = spaghetti.addhook("changemap", function(info)
    startgame(config)
    for p in iterators.all() do setteam(p, "hide", -1, true) end
  end)
  hooks.intermission = spaghetti.addhook("intermission", function(info)
    for _, later in ipairs(laters) do spaghetti.cancel(later) end
    if countteam("hide") > 0 and countteam("seek") > 0 then
      local winners, winnerstr = {}, ""
      for p in iterators.inteam("hide") do if p.state.state ~= engine.CS_SPECTATOR then table.insert(winners, p.name) end end
      local last = table.remove(winners)
      if countteam("hide") > 1 then winnerstr = table.concat(winners, "\f0, \f6") .. " \f0and \f6" .. last else winnerstr = last end
      server.sendservmsg("\n\n\f4> \f0Hiders WIN - \f6" .. winnerstr .. " \f0survived! GG!")
    elseif countteam("hide") == 0 and countteam("seek") > 0 then
      server.sendservmsg("\n\n\f4> \f6Seekers WIN - \f3Nobody survived! \f6GG!")
    elseif countteam("seek") == 0 then
      server.sendservmsg("\n\n\f4> \f6Seekers have left the building - Game has ended! \f6GG!")
    end
    local winnerfrags, winner = -1, nil
    for ci in iterators.select(L"_.extra.found and _.extra.found > 0") do if ci.extra.found > winnerfrags then winnerfrags, winner = ci.extra.found, ci.name end end
    if winnerfrags == -1 then return end
    server.sendservmsg("\f4> \f6Best seeker: \f0" .. winner .. "\f6 found \f0" .. winnerfrags .. " player" .. (winnerfrags ~= 1 and "s" or "") .. "\f6!")
  end)
  hooks.mapvote = spaghetti.addhook(server.N_MAPVOTE, function(info)
   if info.skip or info.ci.privilege >= server.PRIV_ADMIN or info.reqmode == 4 or info.reqmode == 6 then return end
   info.skip = true
   playermsg("\f3Only insta-team and effic-team are supported in Hide & Seek mode.", info.ci)
 end)

  -- player connection hooks
  hooks.connected = spaghetti.addhook("connected", function(info)
    info.ci.extra.found, info.ci.extra.queue = 0, true
  end)  
  hooks.specstate = spaghetti.addhook("specstate", function(info)
    if info.ci.state.state == engine.CS_SPECTATOR then
      playerout(info.ci)
      return
    end
    respawn(info.ci)
    if info.ci.extra.queue then info.ci.extra.queue = nil return end
    setteam.set(info.ci, "hide", -1)
    playermsg("\n", info.ci)
    playermsg("\f6You joined the game and need to \f0HIDE QUICKLY!! \f6Seekers are on the way!", info.ci)
  end)
  hooks.clientdisconnect = spaghetti.addhook("clientdisconnect", function()
    return spaghetti.later(50, function()
      if not checkgame() then server.startintermission() end
    end)
  end)
  
  -- keep it locked until no clients
  hooks.mastermode = spaghetti.addhook(server.N_MASTERMODE, function(info)
    if info.skip or not module.game.has then return end
    if info.mm ~= server.MM_LOCKED and info.ci.privilege < server.PRIV_ADMIN then
      info.skip = true
      playermsg("\f3Only admins can change the mastermode.", info.ci)
    end
  end)
  hooks.checkmastermode = spaghetti.addhook("checkmastermode", function(info)
    info.skip = true
    server.mastermode = server.MM_LOCKED
  end)
  hooks.noclients = spaghetti.addhook("noclients", function()
    module.game.has = false
    server.mastermode = server.MM_OPEN
    server.checkvotes(true)
  end)
end

return module
