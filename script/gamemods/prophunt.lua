--[[

  PROP HUNT! Be a prop and hide, or hunt all enemy props before the time runs out!
  Players can choose their prop by scrolling with mousewheel. Hunters will have limited ammo that regenerates over time.
  Prop playermodels are invisible, only their mapmodels are visible to hunters. If you die as a prop, you will join the hunters.

  module.on() takes a config which overrides the default warmup/gamelength, and allows for excluded mapmodels.

  Made by benzomatic, with much appreciated help from Neko, crapimdead and Jed

]]


local playermsg, commands, ents, hitpush = require"std.playermsg", require"std.commands", require"std.ents", require"std.hitpush"
local putf, sound, iterators, n_client = require"std.putf", require"std.sound", require"std.iterators", require"std.n_client"
local trackent, setteam, setscore, settime = require"std.trackent", require"std.setteam", require"std.setscore", require"std.settime"
local fp, L, vec3, tb = require"utils.fp", require"utils.lambda", require"utils.vec3", require"utils.tokenbucket"
local map, range, fold, first, last, pick, I = fp.map, fp.range, fp.fold, fp.first, fp.last, fp.pick, fp.I

local module = {
  config = {
    warmup = 40,     -- seconds
    gamelength = 6,  -- minutes
    hitbox = { x = 15, y = 15, z = 25 }  -- uniform mapmodel hitbox
  },
  game = {}
}

local hooks, laters, ghostmodels, nullhitpush, gracetime, running, inform = {}, {}, {}, engine.vec()

-- prop hunt logic
local function killrecoil(ci, shot) -- eliminate x/y rifle recoil
  local from, to = vec3(shot.from), vec3(shot.to)
  to:sub(from):normalize():mul(server.guns[shot.gun].kickamount * 2.5)
  to.z = 0
  hitpush(ci, to)
end

local toofar = L"_:dist(_2) > 50"
local function hit(from, to, o, hitbox)                                             -- thanks to Neko for the hitbox math help
  local from, to, o, hitbox = vec3(from), vec3(to), vec3(o), vec3(hitbox) 
  local from2, to2, o2, o3, bottom = vec3(from), vec3(to), vec3(o), vec3(o), o.z    -- add and sub operations override the variable

  local dir, dist = to:sub(from), from:dist(o)
  local direction = dir:normalize()
  
  local ubound, lbound = o:add(hitbox), o2:sub(hitbox)    -- hitbox upper and lower bounds
  lbound.z = bottom - 5                                   -- snap to bottom but shift it down a bit
  local tolerance = lbound:dist(o3)
  local raydest = from:add(direction:mul(dist))

  return  ubound.x > raydest.x and raydest.x > lbound.x
      and ubound.y > raydest.y and raydest.y > lbound.y 
      and ubound.z > raydest.z and raydest.z > lbound.z
      and dist <= from2:dist(to2) + tolerance
end

local function crosshairsync(pitch, yaw, dist)  -- synchronize the prop with pitch/yaw of the crosshair
  local radianpitch, radianyaw = math.rad(1) * pitch, math.rad(1) * yaw
  local x = dist * math.cos(radianpitch) * math.sin(radianyaw) * - 1
  local y = dist * math.cos(radianpitch) * math.cos(radianyaw)
  local z = dist * math.sin(radianpitch)
  return x, y, z
end

local function limboprop(ci)  -- the mapmodel when it's not placed, no collision
  ci.extra.limboprop = ents.active() and trackent.add(ci, function(i, lastpos)
    local o = vec3(lastpos.pos)
    local x, y, z = crosshairsync(lastpos.pitch, lastpos.yaw, 35)                    
    o.x, o.y, o.z = o.x + x, o.y + y, math.max(o.z + z + 8, ci.extra.lastpos.pos.z)  -- snap to bottom
    local eid = ents.mapmodels[ci.extra.ghostmodel]
    if eid then ents.editent(i, server.MAPMODEL, o, lastpos.yaw, eid, 1)
    else ents.editent(i, server.CARROT, o, 0) end
    ci.extra.propo = o
  end, false, false) or nil

  ci.extra.limboflame = ents.active() and trackent.add(ci, function(i)
    if not ci.extra.propo then return end
    local o = vec3(ci.extra.propo)
    o.z = o.z + 15
    ents.editent(i, server.PARTICLES, o, 0, 150, 80, math.random(0, 0xF00))
  end, false, true) or nil
end

local function makeammo(ci, resethealth)
  local st, origselect = ci.state, ci.state.gunselect
  for i = 0, server.NUMGUNS - 1 do st.ammo[i] = 0 end
  st.ammo[server.GUN_FIST], st.armour = 1, 0
  if ci.team == "prop" then 
    if resethealth then st.health, st.maxhealth, st.armour = 150, 150, 0 end
    st.ammo[server.GUN_CG], st.ammo[server.GUN_RIFLE], st.ammo[server.GUN_PISTOL], st.gunselect = 1, 999, 1, server.GUN_RIFLE
  elseif ci.team == "hunt" then
    if resethealth then st.health, st.maxhealth, st.armourtype, st.armour = 200, 200, server.A_YELLOW, 200 end
    st.ammo[server.GUN_CG], st.gunselect = 15, server.GUN_CG
  end
  if ci.team == "prop" or origselect ~= server.GUN_FIST then
    engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = 1}, server.N_GUNSELECT, st.gunselect), ci):finalize(), -1)
  end
  
  if ci.state ~= engine.CS_ALIVE then return end
  setscore.syncammo(ci)
end

local function resetplayer(ci)
  if ci.extra.placedprop then ents.delent(ci.extra.placedprop) end
  if ci.extra.propzone then ents.delent(ci.extra.propzone) end
  if ci.extra.limboprop then trackent.remove(ci, ci.extra.limboprop) end
  if ci.extra.limboflame then trackent.remove(ci, ci.extra.limboflame) end
  if ci.extra.expedite then spaghetti.cancel(ci.extra.expedite) end
  if ci.extra.positionchecker then spaghetti.removehook(ci.extra.positionchecker) end
  ci.extra.placedprop, ci.extra.propzone, ci.extra.limboprop, ci.extra.limboflame, ci.extra.propo, ci.extra.scrollok, ci.extra.expedite, ci.extra.positionchecker = nil
end

local function initprop(ci)
  resetplayer(ci)
  if not running then return end
  makeammo(ci)
  local ind = math.random(#ghostmodels)
  ci.extra.ghostmodel, ci.extra.ghostmodelind, ci.extra.propscroll = ghostmodels[ind], ind, 1
  limboprop(ci)
  ci.extra.expedite = spaghetti.latergame(1500, function() 
    local st = ci.state
    if st.state == engine.CS_SPECTATOR or gracetime or ci.team ~= "prop" then return end
    if ci.extra.placedprop and st.health < 150 then
      st.health, st.state = math.min(st.health + 10, st.maxhealth), engine.CS_SPAWNING  -- need to send CS_SPAWNING to keep invisibility
      server.sendresume(ci)
      st.state = engine.CS_ALIVE
    elseif ci.extra.limboprop and st.health > 0 then
      server.dodamage(ci, ci, 10, server.GUN_FIST, nullhitpush)
      if st.health > 0 and st.health <= 75 then 
        playermsg("\n\f6Info:\t\f3Your HEALTH is running LOW!\n\t\f6Place a PROP to \f0regenerate!!", ci) 
        local pain = math.random(1, 6)
        sound(ci, server["S_PAIN" .. pain], true) sound(ci, server["S_PAIN" .. pain], true)
      end
    end
  end, true)
end

local function inithunter(ci)
  resetplayer(ci)
  if not running then return end
  makeammo(ci, true)
  ci.extra.expedite = spaghetti.latergame(2000, function() 
    local st = ci.state
    if ci.team ~= "hunt" or st.ammo[server.GUN_CG] >= 15 or st.state ~= engine.CS_ALIVE then return end
    local ammo = st.ammo[server.GUN_CG]
    st.ammo[server.GUN_CG] = math.min(ammo + 1, 15)
    setscore.syncammo(ci)
    --if st.gunselect ~= server.GUN_FIST or ammo > 0 then return else st.gunselect = server.GUN_CG end
    if st.gunselect == server.GUN_CG or ammo > 0 then return else st.gunselect = server.GUN_CG end
    engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = 1}, server.N_GUNSELECT, st.gunselect), ci):finalize(), -1)
  end, true)
end

local function removeprop(ci)
  if not ci.extra.placedprop then return end
  ents.delent(ci.extra.placedprop)
  if ci.extra.propzone then ents.delent(ci.extra.propzone) end
  if ci.extra.positionchecker then spaghetti.removehook(ci.extra.positionchecker) end
  ci.extra.placedprop, ci.extra.propzone, ci.extra.positionchecker  = nil
  sound(ci, server.S_HIT, true) sound(ci, server.S_HIT, true)
end

local function readjusting(ci, msg)
  if not ci.extra.placedprop then return false end
  makeammo(ci)
  removeprop(ci)
  local hmsg = gracetime and ", but \f6your health is deteriorating\f7" or ""
  playermsg(msg or "\n\f6Info:\t\f7You can now \f1readjust your prop \f7again" .. hmsg .. "!\n\t\f0LEFT CLICK \f7to \f0PLACE!", ci)
  limboprop(ci)
  return true
end

local function placeprop(ci, o)  -- the mapmodel when it's placed
  if not ci.extra.limboprop then return end
  trackent.remove(ci, ci.extra.limboprop) trackent.remove(ci, ci.extra.limboflame)
  ci.extra.limboprop, ci.extra.limboflame = nil
  local propid, lastpos = ents.mapmodels[ci.extra.ghostmodel], ci.extra.lastpos
  local mapmodelo = vec3(o)
  ci.extra.placedprop, ci.extra.propo = ents.newent(server.MAPMODEL, mapmodelo, lastpos.yaw, propid), mapmodelo
  local cio = ci.extra.lastpos.pos
  o.z = cio.z - 5 
  ci.extra.propzone = ents.newent(server.PARTICLES, o, 4, 291, 50, 0xF00, 0, function (i)  -- show a private prop zone visual
    local _, _, ment = ents.getent(i)
    local p = n_client(putf({ 20, r = reliable or who}, server.N_EDITENT, i, ment.o.x * server.DMF, ment.o.y * server.DMF, ment.o.z * server.DMF, ment.type, ment.attr1, ment.attr2, ment.attr3, ment.attr4, ment.attr5), ci)
    engine.sendpacket(ci.clientnum, 1, p:finalize(), -1)
  end)  

  ci.extra.positionchecker = spaghetti.addhook("positionupdate", function(info) 
    if info.cp.clientnum ~= ci.clientnum or not ci.extra.placedprop then return end
    local cio = ci.extra.propo
    if not toofar(info.lastpos.pos, cio) then return end
    readjusting(ci, "\n\t\f6Info: \f3You have LEFT the prop zone! \f6Hunters can see your prop move!\n\t\f0LEFT CLICK \f7to \f0PLACE YOUR PROP again!")
  end)

  sound(ci, server.S_HIT, true) sound(ci, server.S_HIT, true)
  playermsg("\n\f6Info:\t\f7You have \f1placed your prop\f7! You are invisible, the prop isn't.\n\tUse \f0SCROLL WHEEL \f7to \f0readjust! \f8Don't move out of your \f3PROP ZONE \f8(marked \f3red\f8).", ci)
end

local function cleanteams(info)
  if info.skip or info.ci.privilege >= server.PRIV_ADMIN then 
    if info.text == "hunt" then inithunter(info.ci) else initprop(info.ci) end
    return
  end
  info.skip = true
  playermsg("Only admins can change teams in prop hunt.", info.ci)
end

local grunts = { server.S_GRUNT1, server.S_GRUNT2, server.S_PIGR1, server.S_PIGGR2 }
local function emitgrunt(p)
  local grunting = grunts[math.random(#grunts)]
  sound(p, grunting, true)
  for h in iterators.inteam("hunt") do
    local huntpos, proppos = h.extra.lastpos.pos, p.extra.propo
    if p.extra.propo then
      if huntpos:dist(proppos) <= 200 then sound(h, grunting, true) end
      if huntpos:dist(proppos) <= 100 then sound(h, grunting, true) sound(h, grunting, true) end
    end
  end
end
local function grunt(ci)
  if ci then emitgrunt(ci) else for p in iterators.inteam("prop") do emitgrunt(p) end end
end

-- hide and seek logic
local function respawn(ci)
  ci.state:respawn()
  server.sendspawn(ci)
end

local function countteam(team)
  local num = 0
  for p in iterators.inteam(team) do if (p.state.state ~= engine.CS_SPECTATOR) then num = num + 1 end end
  return num, num ~= 1
end

local function checkgame(starting)
  if starting then return not (server.numclients(-1, true, true) < 2) end
  return not (countteam("prop") == 0 or countteam("hunt") == 0)
end

local function playerout(ci)
  if module.game.nextseeker == ci.clientnum then module.game.nextseeker = nil end
  ci.extra.nextseeker = nil
  if not checkgame() then server.startintermission() end
end

local function caught(ci, loser)
  if ci.team ~= "prop" then return end
  setteam.set(ci, "hunt", -1)
  inithunter(ci)
  ci.extra.nextseeker, module.game.nextseeker = loser, module.game.nextseeker and module.game.nextseeker or loser and ci.clientnum or nil
  server.sendservmsg("\f6Info: \f0" .. ci.name .. " \f6has been killed!" .. (loser and " They will start hunting in the next round!" or ""))
  if countteam("prop") == 0 then return server.startintermission() end
  playermsg("\f6Info\f7: \f6You have died and became a prop hunter! \f3Find and kill all fake props \f6before the time runs out!!", ci)
  local count, plural = countteam("prop")
  server.sendservmsg("\f6Info: " .. count .. " prop" .. (plural and "s" or "") .. " to go!")
end

local function cleanup()
  module.game.winners = nil
  for ci in iterators.clients() do
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
  setteam.set(ci, "hunt", -1, true)
  inithunter(ci)
  engine.sendpacket(ci.clientnum, 1, putf({ 2, r = 1}, server.N_PAUSEGAME, 1):finalize(), -1)
  if server.interm ~= 0 then return end
  engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = true}, server.N_EDITVAR, engine.ID_VAR, "fog", 1), ci):finalize(), -1)
  engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = true}, server.N_EDITVAR, engine.ID_VAR, "fogcolour", 0), ci):finalize(), -1)
  playermsg("\n\n\f6#####################################################################", ci)
  playermsg("\f3\tYOU are a prop hunter! \f6You are now frozen. The props have \f0" .. config.warmup .. "s \f6to prepare..", ci)
  playermsg("\f6#####################################################################", ci)
end

local function freeseekers(config)
  for ci in iterators.select(L'_.team == "hunt" and _.state.state ~= engine.CS_SPECTATOR') do
    engine.sendpacket(ci.clientnum, 1, putf({ r = 1 }, server.N_PAUSEGAME, 0):finalize(), -1)
    if server.interm == 0 then 
      engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = true}, server.N_EDITVAR, engine.ID_VAR, "fog", 999999), ci):finalize(), -1)
      engine.sendpacket(ci.clientnum, 1, n_client(putf({ 20, r = true}, server.N_EDITVAR, engine.ID_VAR, "fogcolour", 0), ci):finalize(), -1)
      playermsg("\n\f6###############################################################", ci)
      playermsg("\f0\tThe hunt has begun! FIND AND KILL THE PROPS! You have " .. config.gamelength .. " minutes!", ci)
      playermsg("\f2\tThe hidden props will \f3grunt \f2every 15 seconds, so sharpen your ears! \f0Good Luck!", ci)
      playermsg("\f6###############################################################", ci)
      server.sendspawn(ci)
    end
  end
end

local function launchprophunt()
  if running then return end
  if checkgame(true) then
    server.sendservmsg("\n\f6Info:\tProp Hunt \f0activated\f6! Switching map...")
    spaghetti.later(3000, function()
      module.on(true, module.config)
      server.rotatemap(true)
    end)
  else
    server.sendservmsg("\f6Info:\tProp Hunt needs at least \f0two players\f6! Please invite more players to the server, then \f0#start \f6the game!")
  end
end
spaghetti.addhook("changemap", launchprophunt)
commands.add("start", launchprophunt)

commands.add("rules", function(info) 
  playermsg("\n\f2Rules\f6:\t\t\f2Prop Hunt is like Hide & Seek, but you will hide as a random object on the map!", info.ci)
  playermsg("\f2As a prop\f6:\tYou can \f0SCROLL \f6through the available models, and \f0LEFT CLICK \f6to place it down!", info.ci)
  playermsg("\f6\t\t\tYour player is invisible, but your prop is not! Your prop sometimes makes noises! \f3Don't get caught!", info.ci)
  playermsg("\f2As a hunter\f6:\tSpot the enemy props and gun them down! But be efficient, your \f2ammo only slowly regenerates\f6!", info.ci)
end)

commands.add("join", function(info) 
  if info.ci.state.state ~= engine.CS_SPECTATOR or info.ci.extra.queue then return end
  playermsg("\f0You will be unspectated during the next map!", info.ci)
  info.ci.extra.queue = true
end)

local function setprop(ci, newprop)
  local ghostmodelind, ghostmodel
  if type(newprop) == "number" then 
    ghostmodelind, ghostmodel = newprop, ghostmodels[newprop]
  else
    local ghostmodelmap = map.mi(L"_2, _", ghostmodels) 
    ghostmodelind, ghostmodel = ghostmodelmap[newprop], newprop
  end
  if not ghostmodelind or not ghostmodel then return playermsg("\f3Error: \f6This model is not available.", ci) end
  sound(ci, server.S_ITEMARMOUR, true) sound(ci, server.S_ITEMARMOUR, true)
  ci.extra.ghostmodelind, ci.extra.ghostmodel = ghostmodelind, ghostmodel
end

commands.add("prop", function(info) 
  if info.ci.team ~= "prop" then return end
  local newprop = info.args
  if info.ci.extra.ghostmodel and (not newprop or newprop == "") then 
    return playermsg("\n\f6Info\f7:\tYour prop is \"\f6" .. info.ci.extra.ghostmodel .. "\f7\"!", info.ci) 
  end
  readjusting(info.ci)
  setprop(info.ci, newprop)
end)

spaghetti.later(30000, function()
  if running then return end
  playermsg("\f6Info:\tProp Hunt needs at least \f0two players\f6! Please invite more players to the server, then \f0#start \f6the game!", iterators.clients())
end, true)

-- module init
function module.on(state, config)
  map.np(L"spaghetti.removehook(_2)", hooks)
  if inform then spaghetti.cancel(inform) end
  hooks, killbasesp = {}
  if not state then
    server.mastermode, running = server.MM_OPEN
    engine.sendpacket(-1, 1, putf({ r = true }, server.N_MASTERMODE, server.mastermode):finalize(), -1)
    return
  end
  if not config then config = module.config end
  module.config = config
  server.mastermode = server.MM_LOCKED
  engine.sendpacket(-1, 1, putf({ r = true }, server.N_MASTERMODE, server.mastermode):finalize(), -1)

  inform = spaghetti.later(30000, function()
    for ci in iterators.spectators() do
      if not ci.extra.queue then 
        playermsg("\f6An active Prop Hunt game is running, but you're a spectator. Type \f0#join \f6to join back in on the next map!", ci)
        return 
      end
      playermsg("\f6An active Prop Hunt game is running. \f0You will be added on the next map. \f6In the meantime, read the \f0#rules\f6!", ci)
    end
  end, true)

  -- game status hooks
  hooks.prechangemap = spaghetti.addhook("prechangemap", cleanup)
  hooks.autoteam = spaghetti.addhook("autoteam", function(info)
    if info.skip then return end
    info.skip = true
    if info.ci then info.ci.team = "prop" return end
    for ci in iterators.clients() do setteam(ci, "prop", -1, true) end
  end)
  hooks.servmodesetup = spaghetti.addhook("servmodesetup", function(info)
    killbasesp = nil
    for ci in iterators.clients() do resetplayer(ci) end
    if not checkgame(true) or not ents.active() or not server.m_capture then
      server.sendservmsg("\f6Info:\tProp Hunt needs at least \f0two players\f6! Please invite more players to the server!")
      module.on(false)
      return
    end
    info.skip, gracetime, running = true, true, true
    map.nf(ents.delent, ents.enum(server.I_HEALTH))
    map.nf(L"_.extra.queue and server.unspectate(_)", iterators.spectators())
    local seeker = getseeker()
    --if not seeker then return end
    clearnextseekers()
    local delay, add = 3000, config.warmup * 1000
    laters[1] = spaghetti.latergame(delay, function()
    prepseeker(seeker, config)
    for ci in iterators.select(L"_.team == 'prop' and _.state.state ~= engine.CS_SPECTATOR") do
      initprop(ci)
      playermsg("\n\f6Info:\t\f6You are invisible. \f1Your PROP is not! \f3Hide as fast as possible!!", ci)
      playermsg("\t\f7Use \f0SCROLL WHEEL \f7to cycle through props, and \f0LEFT CLICK \f7to place the prop.", ci)
    end
    for ci in iterators.spectators() do setteam(ci, "hunt", -1) end
    end)
    laters[2] = spaghetti.latergame(delay + add - 5000, L"server.sendservmsg('\f4> \f6Starting in \f35\f4...')")
    laters[3] = spaghetti.latergame(delay + add - 4000, L"server.sendservmsg('\f4> \f34\f4...')")
    laters[4] = spaghetti.latergame(delay + add - 3000, L"server.sendservmsg('\f4> \f33\f4...')")
    laters[5] = spaghetti.latergame(delay + add - 2000, L"server.sendservmsg('\f4> \f32\f4...')")
    laters[6] = spaghetti.latergame(delay + add - 1000, L"server.sendservmsg('\f4> \f31\f4...')")
    spaghetti.latergame(delay + add, function()
      gracetime = nil
      map.nf(L"_.state.state == engine.CS_DEAD and server.sendspawn(_)", iterators.clients())
      if server.interm ~= 0 then freeseekers(config) return end
      settime.set(config.gamelength * 60 * 1000)
      server.sendservmsg('\n\f6PROP HUNT has STARTED! \f0GOOD LUCK!')
      freeseekers(config)
      laters[7] = spaghetti.latergame(15000, grunt, true)
    end)
    local numbases = 0
    for _ in ents.enum(server.BASE) do numbases = numbases + 1 end
    if numbases == 0 then return end
    local p = putf({ 30, r = 1}, server.N_BASES, numbases)
    for _ = 1, numbases do p = putf(p, 0, "", "", 0, 0) end
    killbasesp = p:finalize()
    engine.sendpacket(-1, 1, killbasesp, -1)
  end)
  hooks.entsloaded = spaghetti.addhook("entsloaded", function()
    local excludemodels = config.excludemodels
    local excluded = excludemodels and next(excludemodels) and map.si(L"_2", excludemodels) or {}
    ghostmodels = map.lf(L"_2", pick.zi(function(i, n) return not excluded[n] end, ents.mapmodels))
    for ci in iterators.clients() do ci.extra.ghostmodelind = math.random(#ghostmodels) end
  end)
  hooks.intermission = spaghetti.addhook("intermission", function(info)
    for _, later in ipairs(laters) do spaghetti.cancel(later) end
    if countteam("prop") > 0 and countteam("hunt") > 0 then
      local winners, winnerstr = {}, ""
      for p in iterators.inteam("prop") do if p.state.state ~= engine.CS_SPECTATOR then table.insert(winners, p.name) end end
      local last = table.remove(winners)
      if countteam("prop") > 1 then winnerstr = table.concat(winners, "\f6, \f0") .. " \f6and \f0" .. last else winnerstr = last end
      server.sendservmsg("\n\n\t \f6Props \f6WIN - \f0" .. winnerstr .. " \f6survived! GG!")
    elseif countteam("prop") == 0 and countteam("hunt") > 0 then
      server.sendservmsg("\n\n\t \f6Hunters WIN - \f3Nobody survived! \f6GG!")
    elseif countteam("hunt") == 0 then
      server.sendservmsg("\n\n\t \f3Hunters have left the game - \f6The game has ended! GG!")
    end
    local winnerfrags, winner = -1
    for ci in iterators.select(L"_.extra.found and _.extra.found > 0") do if ci.extra.found > winnerfrags then winnerfrags, winner = ci.extra.found, ci.name end end
    if winnerfrags == -1 then return end
    server.sendservmsg("\n\ft \f6Best hunter: \f0" .. winner .. "\f6 found \f0" .. winnerfrags .. " prop" .. (winnerfrags ~= 1 and "s" or "") .. "\f6!")
  end)

  -- no bots/bases, restrict teams
  hooks.preannounce = spaghetti.addhook("preannounce", L"_.skip = true")
  hooks.clientbases = spaghetti.addhook(server.N_BASES, L"_.skip = true")
  hooks.addbot = spaghetti.addhook(server.N_ADDBOT, L"_.skip = true")
  hooks.setteam = spaghetti.addhook(server.N_SETTEAM, cleanteams)
  hooks.switchteam = spaghetti.addhook(server.N_SWITCHTEAM, cleanteams)

  -- damage and shot override
  hooks.shoot = spaghetti.addhook(server.N_SHOOT, function(info)
    if info.skip then return end
    if info.ci.team == "prop" and info.shot.gun == server.GUN_RIFLE then
      info.skip = true
      if info.cq then info.cq:setpushed() end
      if readjusting(info.ci) then return end
      if not toofar(vec3(info.shot.to), info.ci.extra.lastpos.pos) then killrecoil(info.ci, info.shot) placeprop(info.ci, info.shot.to) 
      else playermsg("\n\f6Info\f7:\t\f3TOO FAR WAY!\n\t\f0LEFT CLICK \f7and place your prop \f0CLOSER TO YOU \f7or even below you!", info.ci) end
    elseif info.ci.team ~= "prop" then
      for propper in iterators.select(L"_.extra.propo and _.team == 'prop'") do
        if hit(info.shot.from, info.shot.to, propper.extra.propo, config.hitbox) then
          playermsg("\t\f6You hit \f0" .. propper.name, info.ci)
          server.dodamage(propper, info.ci, 20, server.GUN_CG, nullhitpush)
          sound(info.ci, server.S_HIT, true) sound(info.ci, server.S_HIT, true)
          if info.ci.state.ammo[server.GUN_CG] >= 20 then return end
          local ammo = info.ci.state.ammo[server.GUN_CG]
          info.ci.state.ammo[server.GUN_CG] = math.min(ammo + math.random(0, 2), 15)
          setscore.syncammo(info.ci)
        end
      end
    end
  end)
  hooks.dodamage = spaghetti.addhook("dodamage", function(info) 
    if info.skip or info.target.team == "prop" or info.target.clientnum == info.actor.clientnum then return end
    local hitpush = info.hitpush
    hitpush.x, hitpush.y, hitpush.z = 0, 0, 0
    if info.actor.team == info.target.team then info.skip = true end
  end)
  hooks.damaged = spaghetti.addhook("damaged", function(info)
    local actor, target, loser = info.actor, info.target, not module.game.nextseeker
    if target.state.health > 0 or info.target.team ~= "prop" then return end
    if actor.clientnum ~= target.clientnum then actor.extra.found = (actor.extra.found or 0) + 1 end
    caught(target, loser)
  end)
  hooks.taunt = spaghetti.addhook(server.N_TAUNT, function(info) 
    if info.ci.team ~= "prop" then return end
    local gruntok = info.ci.extra.gruntok or tb(1/9, 4)
    info.skip, info.ci.extra.gruntok = true, gruntok
    if not info.ci.extra.gruntok() then return playermsg("\n\f6Info\f7:\tYou are \f2grunting too much!", info.ci) end
    emitgrunt(info.ci)
    playermsg("\n\f6Info\f7:\tYou \f0grunted!", info.ci)
  end)

  -- intercept N_GUNSELECT to allow the player to scroll through list of mapmodels
  hooks.gunselect = spaghetti.addhook(server.N_GUNSELECT, function(info)
    if info.skip or info.ci.team ~= "prop" then return end
    info.skip = true
    if readjusting(info.ci) then return end
    makeammo(info.ci)
    local oid, scroll = info.ci.extra.ghostmodelind, info.ci.extra.propscroll
    scroll = info.gunselect == server.GUN_CG and -1 or info.gunselect == server.GUN_PISTOL and 1 or scroll
    local newindex = oid + scroll
    local nid = newindex < 1 and #ghostmodels or newindex > #ghostmodels and 1 or newindex
    info.ci.extra.propscroll = scroll
    setprop(info.ci, nid)
  end)

  --client join/leave/spawn/spec
  hooks.connected = spaghetti.addhook("connected", function(info)
    info.ci.extra.found, info.ci.extra.queue = 0, true
    return killbasesp and engine.sendpacket(info.ci.clientnum, 1, killbasesp, -1)
  end)
  hooks.disconnect = spaghetti.addhook("clientdisconnect", function(info) 
    resetplayer(info.ci) 
    return spaghetti.latergame(50, function()
      if not checkgame() then server.startintermission() end
    end)
  end)
  hooks.spawnstate = spaghetti.addhook("spawnstate", function(info)
    if info.skip then return end
    info.skip = true
    makeammo(info.ci, true)
    info.ci.state.lifesequence = (info.ci.state.lifesequence + 1) % 0x80
  end)
  hooks.specstate = spaghetti.addhook("specstate", function(info)
    if info.ci.state.state == engine.CS_SPECTATOR then
      playerout(info.ci)
      resetplayer(info.ci)
      return
    end
    respawn(info.ci)
    if info.ci.extra.queue or not running then info.ci.extra.queue = nil return end
    setteam.set(info.ci, "prop", -1)
    initprop(info.ci)
    playermsg("\n\f6You joined the game and need to \f0HIDE QUICKLY!! \f6Seekers are on the way!", info.ci)
  end)
  hooks.suicide = spaghetti.addhook(server.N_SUICIDE, function(info)
    if info.skip or info.ci.state.state == engine.CS_SPECTATOR then return end
    info.skip = true
    if info.ci.team == "hunt" or gracetime then respawn(info.ci) return end
    caught(info.ci, not module.game.nextseeker)
    if not checkgame() then server.startintermission() return end
  end)

  -- keep server locked until no clients
  hooks.mastermode = spaghetti.addhook(server.N_MASTERMODE, function(info)
    if info.skip or not running then return end
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
    server.mastermode, running = server.MM_OPEN
    return not spaghetti.quit and server.checkvotes(true)
  end)
end

return module
