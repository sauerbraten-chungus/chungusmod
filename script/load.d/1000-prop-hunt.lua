--[[

  A server running Prop Hunt mode.

]]--

if not os.getenv("PROPHUNT") then return end
engine.writelog("Applying the Prop Hunt configuration.")

local servertag = require"utils.servertag"
servertag.tag = "prophunt"

local uuid = require"std.uuid"

local fp, L, vec3 = require"utils.fp", require"utils.lambda", require"utils.vec3"
local map, range, fold, last, pick, I, U = fp.map, fp.range, fp.fold, fp.last, fp.pick, fp.I, fp.U
local abuse, playermsg, commands, ents, hitpush = require"std.abuse", require"std.playermsg", require"std.commands", require"std.ents", require"std.hitpush"

cs.maxclients = 14
cs.serverport = 28785

cs.updatemaster = 1
spaghetti.later(10000, L'engine.requestmaster("\\n")', true)
spaghetti.addhook("masterin", L'if _.input:match("^failreg") then engine.lastupdatemaster = 0 end', true)

server.mastermask = server.MM_PUBSERV + server.MM_AUTOAPPROVE

--make sure you delete the next two lines, or I'll have admin on your server.
cs.serverauth = "prophunt"
local auth = require("std.auth")

cs.adduser("kappapenis", "prophunt", "-a2bdd998d6bf6927040f366cc699cd7fcf3231db0f92cf5b", "a")

table.insert(auth.preauths, "prophunt")

cs.serverdesc = "\f6Sauer \f3PROP HUNT!"

cs.lockmaprotation = 2
cs.maprotationreset()


-- TODO: fix mapmodelreset 186 for akimiski, tectonic, bklyn, monastery
local prophuntmaps = table.concat({ 
  "abbey access akroseum albatross alloy arabic arbana authentic bt_falls",
  "c_valley c_egypt c_lone campo capture_night casa catacombs core_transfer cwcastle", 
  "destiny divine dust2 earthsea earthstation", 
  "eris eternal_valley europium fc4 fc5 fire_keep flagstone", 
  "forgotten fortress fusion genesis ghetto gothic-df gubo hallo horus infamy", 
  "mbt12 meltdown2 metro nitro nmp4 nmp8 nucleus ow ogrosupply ph-capture reissen relic risk river_c", 
  "ruby ruebli sacrifice shipwreck snapper_rocks spcr suburb stadium stronghold toxicity twinforts urban_c valhalla warlock wdcd zamak" 
}, " ")

local excludemodels = {  -- these are too bulky or too hard to find:  
  "dcp/blade_x", "rpg/characters/rat", "mapmodels/makke/gutter_h_big/trak5", "dcp/ivy", "dcp/hanginlamp", "makke/strahler",
  "aftas/machina/machina2", "tentus/key", "mapmodels/yves_allaire/e6/e6fanblade/horizontal", "makke/tricky/sign3",
  "makke/spoon", "objects/sail01", "objects/lamp02", "makke/mugs/mug02", "makke/planet", "makke/fork", "makke/tricky/sign1",
  "aftas/arvores/arp", "aftas/lampada", "tentus/greenshield", "makke/moon", "tentus/books/flat", "makke/tricky/sign2",
  "dcp/blade_y", "crow", "aftas/machina/machina1", "objects/axe", "aftas/arvores/arg", "objects/med_chand", "mitaman/floorgrate1",
  "mapmodels/simonoc/effect/cyan_v", "mapmodels/simonoc/effect/red_v", "mapmodels/simonoc/effect/green_v", "makke/tricky/sign4",
  "mapmodels/simonoc/effect/blue_v", "mapmodels/simonoc/effect/yellow_v", "mapmodels/simonoc/effect/violet_v", "tentus/food-drink/appleslice",
  "mapmodels/nieb/waterfall/3", "mapmodels/nieb/waterfall/1", "mapmodels/nieb/waterfall/2", "mapmodels/nieb/waterfall/4", "mapmodels/justice/cc_screen",
  "dcp/switch1a", "shield/green", "dcp/insect", "mapmodels/yves_allaire/e7/e7wgrate/32x64_h", "debris/debris02", "gibs/gib01",
  "mapmodels/justice/console2", "mapmodels/gibc", "mapmodels/yves_allaire/e7/e7wgrate/64x32_v", "debris/debris01", "debris/debris03", "debris/debris04", 
  "gibs/gib03", "mapmodels/toca/industrialpipes/lright", "mapmodels/toca/signs/radioactive", "mapmodels/toca/industrialpipes/lleft",
  "mapmodels/toca/industrialpipes/horz", "mapmodels/toca/industrialpipes/ldwn", "mapmodels/toca/signs/restricted", "dcp/grate",
  "meister/grinder", "meister/coclea", "meister/gear", "meister/puleggia", "meister/silos", "mapmodels/yves_allaire/e6/e6fanblade/vertical",
  "razgriz/objects/gem_cap/red_v", "razgriz/rocks/set2/4", "razgriz/insects/butterfly/brown", "razgriz/rocks/set2/5",
  "razgriz/rocks/set2/3", "razgriz/rocks/set2/2", "razgriz/insects/butterfly/yellow", "razgriz/objects/gem_cap/blue_v",
  "razgriz/objects/gem_cap/red_h", "razgriz/flora/shroom3", "razgriz/objects/gem_cap/blue_h", "razgriz/insects/firefly",
  "razgriz/insects/butterfly/pink", "razgriz/rocks/set2/1", "razgriz/rocks/set2/1", "razgriz/insects/butterfly/pink",
  "razgriz/flora/shroom1", "razgriz/flora/shroom2", "tentus/chains/chain", "makke/mugs/mug01", "makke/mugs/mug03", "tentus/hammer",
  "razgriz/insects/butterfly/blue", "razgriz/insects/butterfly/green", "razgriz/insects/butterfly/red", "razgriz/insects/butterfly/orange",
  "tentus/food-drink/pieslice", "tentus/food-drink/mug", "switch2", "mitaman/woodboard", "dcp/blade_x/fast", "aftas/arvores/arm",
  "objects/lantern01", "steve_e/doors/trapdoor/trapdoor_200", "mitaman/plat01", "dcp/chandelier", "mitaman/floorgrate3",
  "razgriz/effects/magic/blue_h_large", "mapmodels/simonoc/effect/green", "ao1/metro/graffiti/necedemalis", "mapmodels/memoria/decals", 
  "mapmodels/nieb/clockhand/short", "mapmodels/nieb/clockhand/large", "mapmodels/yves_allaire/e7/e7wgrate/32x64_v", "razgriz/effects/magic/red_h_small", 
  "mapmodels/simonoc/effect/violet", "mapmodels/justice/decals/01", "mitaman/floorgrate1/crnsp1", "razgriz/effects/magic/blue_v_large", 
  "razgriz/effects/magic/blue_v", "mapmodels/simonoc/effect/blue", "ao1/e_station/horiz", "razgriz/effects/magic/red_h_large", "mapmodels/nieb/clockhand/long", 
  "checkpoint", "tentus/rope", "razgriz/effects/magic/red_h", "razgriz/effects/magic/blue_h", "tentus/ladder", "razgriz/effects/magic/blue_h_small", 
  "mapmodels/simonoc/effect/yellow", "dcp/bulb", "mapmodels/tubes/ladder", "mapmodels/ow/tarp", "mapmodels/simonoc/effect/red", "tentus/spear", "rpg/objects/coin", 
  "tentus/chains/curvechain", "objects/oillamp", "mapmodels/simonoc/effect/cyan", "mapmodels/nieb/ladder45", "pyccna/toxicity/tendril",
  "pyccna/toxicity/testtube", "pyccna/toxicity/testtube_mutated", "pyccna/toxicity/testtube_severe", "tree1"
}

prophuntmaps = map.f(I, prophuntmaps:gmatch("[^ ]+"))

for i = 2, #prophuntmaps do
  local j = math.random(i)
  local s = prophuntmaps[j]
  prophuntmaps[j] = prophuntmaps[i]
  prophuntmaps[i] = s
end

local spectators, emptypos, nullhitpush = {}, {buf = ('\0'):rep(13)}, engine.vec()

local sound = require"std.sound"
require"std.lastpos"
require"std.pm"

cs.maprotation("regencapture", table.concat(prophuntmaps, " "))

require"std.mmbattle".pool({
  modes = { 10 },
  maps = prophuntmaps,
  count = 3
})

require"gamemods.prophunt".on(true, {
  warmup = 40,     -- seconds
  gamelength = 6,  -- minutes
  hitbox = { x = 15, y = 15, z = 25 },
  excludemodels = excludemodels,
})

--[[

require"std.discordrelay".new({
  relayHost = "127.0.0.1", 
  relayPort = 57575, 
  discordChannelID = "my-discord-channel-id",
  scoreboardChannelID = "my-scoreboard-channel-id",
  voice = {
    good = "good-voice-channel",
    evil = "evil-voice-channel"
  }
})

]]

--gamemods
local ctf, putf, sound, iterators, n_client = server.ctfmode, require"std.putf", require"std.sound", require"std.iterators", require"std.n_client"
require"std.notalive"

local disappear

spaghetti.addhook("connected", L"_.ci.state.state ~= engine.CS_SPECTATOR and server.sendspawn(_.ci)") --fixup for spawn on connect

local jsonpersist, settime = require"utils.jsonpersist", require"std.settime"

local function createBarrels(axis, start, length, height)
  local barrels = {}
  length = length and length - 1 or 2
  height = height and height - 1 or 2
  for z = 0, height do
    local current = vec3(U(start))
    for i = 0, length do
      local newplane = i > 0 and current[axis] - 7 or current[axis]
      local newz = z > 0 and current.z + z * 11 or current.z
      current[axis] = newplane
      table.insert(barrels, vec3(current.x, current.y, newz))
    end
  end
  for i, barrel in ipairs(barrels) do
    ents.newent(server.MAPMODEL, barrel, math.random(360), 15)
  end
end

-- cut off the pitch black houses on ph-capture
spaghetti.addhook("entsloaded", function()
  if server.smapname == "ph-capture" then
    --house 1 front
    createBarrels('x', {968, 1150, 518}, 5, 2)
    createBarrels('x', {927, 1148, 511}, 3, 3)
    --house 1 back
    createBarrels('x', {1059, 1020, 511})
    createBarrels('x', {928, 1020, 511})

    --house 2 front
    createBarrels('x', {1096, 1150, 518}, 5, 2)
    createBarrels('x', {1055, 1148, 511}, 3, 3)
    --house 2 back
    createBarrels('x', {1105, 1020, 559})
    createBarrels('x', {977, 1020, 559})

    --hall front, long
    createBarrels('x', {908, 1311, 520}, 8, 2)
    createBarrels('x', {957, 1311, 561}, 15, 2)
    createBarrels('y', {959, 1305, 561}, 2, 2)
    --hall front, short
    createBarrels('x', {999, 1360, 520}, 3, 2)
    createBarrels('x', {887, 1360, 520}, 3, 2)
    -- hall back
    createBarrels('x', {998, 1281, 511}, 3, 3)
    createBarrels('x', {998, 1281, 560}, 3, 6)
  end
end)

-- ghost mode: force players to be in CS_SPAWN state, attach a prop to their position

--prevent accidental (?) damage
--spaghetti.addhook("dodamage", function(info) info.skip = info.target.team ~= "good" and info.target.clientnum ~= info.actor.clientnum end)
spaghetti.addhook("damageeffects", function(info)
  if info.target.clientnum == info.actor.clientnum then return end
  local push = info.hitpush
  push.x, push.y, push.z = 0, 0, 0
end)

disappear = function()
  local players = map.sf(L"_.state.state == engine.CS_ALIVE and _ or nil", iterators.players())
  for viewer in pairs(players) do for vanish in pairs(players) do if vanish.clientnum ~= viewer.clientnum and vanish.team == "prop" then
    local p = putf({ 30, r = 1}, server.N_SPAWN)
    server.sendstate(vanish.state, p)
    engine.sendpacket(viewer.clientnum, 1, n_client(p, vanish):finalize(), -1)
  end end end
end

spaghetti.later(900, disappear, true)

spaghetti.addhook("connected", function(info)
  if info.ci.state.state == engine.CS_SPECTATOR then spectators[info.ci.clientnum] = true return end
end)

spaghetti.addhook("specstate", function(info)
  if info.ci.state.state == engine.CS_SPECTATOR then spectators[info.ci.clientnum] = true return end
  spectators[info.ci.clientnum] = nil
  --clear the virtual position of players so sounds do not get played at random locations
  local p
  for ci in iterators.players() do if ci.clientnum ~= info.ci.clientnum then
    p = putf(p or {13, r = 1}, server.N_POS, {uint = ci.clientnum}, { ci.state.lifesequence % 2 * 8 }, emptypos)
  end end
  if not p then return end
  engine.sendpacket(info.ci.clientnum, 0, p:finalize(), -1)
end)

spaghetti.addhook("clientdisconnect", function(info) spectators[info.ci.clientnum] = nil end)

function limitedflushpos(info)
  if info.ci.team ~= "prop" then return end
  info.skip = true
  local wposition = info.ci.position.buf
  local p = engine.enet_packet_create(wposition, 0)
  for scn in pairs(spectators) do engine.sendpacket(scn, 0, p, -1) end
  server.recordpacket(0, wposition)
end

spaghetti.addhook("worldstate_pos", limitedflushpos)
spaghetti.addhook(server.N_TELEPORT, function(info)
  limitedflushpos(info)
  info.ci.position:setsize(0)
  local p = putf({r = 1}, server.N_TELEPORT, info.pcn, info.teleport, info.teledest)
  for scn in pairs(spectators) do engine.sendpacket(scn, 0, p:finalize(), info.cp.ownernum) end
end)
spaghetti.addhook(server.N_JUMPPAD, function (info)
  info.cp:setpushed()
  limitedflushpos(info)
  info.ci.position:setsize(0)
  local p = putf({r = 1}, server.N_JUMPPAD, info.pcn, info.jumppad)
  for scn in pairs(spectators) do engine.sendpacket(scn, 0, p:finalize(), info.cp.ownernum) end
end)


--moderation

--limit reconnects when banned, or to avoid spawn wait time
abuse.reconnectspam(1/60, 5)

--limit some message types
spaghetti.addhook(server.N_KICK, function(info)
  if info.skip or info.ci.privilege > server.PRIV_MASTER then return end
  info.skip = true
  playermsg("No. Use gauth.", info.ci)
end)
spaghetti.addhook(server.N_SOUND, function(info)
  if info.skip or abuse.clientsound(info.sound) then return end
  info.skip = true
  playermsg("I know I used to do that but... whatever.", info.ci)
end)
abuse.ratelimit({ server.N_TEXT, server.N_SAYTEAM }, 0.5, 10, L"nil, 'I don\\'t like spam.'")
abuse.ratelimit(server.N_SWITCHNAME, 1/30, 4, L"nil, 'You\\'re a pain.'")
abuse.ratelimit(server.N_MAPVOTE, 1/10, 3, L"nil, 'That map sucks anyway.'")
abuse.ratelimit(server.N_SPECTATOR, 1/30, 5, L"_.ci.clientnum ~= _.spectator, 'Can\\'t even describe you.'") --self spec
abuse.ratelimit(server.N_MASTERMODE, 1/30, 5, L"_.ci.privilege == server.PRIV_NONE, 'Can\\'t even describe you.'")
abuse.ratelimit({ server.N_AUTHTRY, server.N_AUTHKICK }, 1/60, 4, L"nil, 'Are you really trying to bruteforce a 192 bits number? Kudos to you!'")
abuse.ratelimit(server.N_CLIENTPING, 4.5) --no message as it could be cause of network jitter
abuse.ratelimit(server.N_SERVCMD, 0.5, 10, L"nil, 'Yes I\\'m filtering this too.'")
abuse.ratelimit(server.N_TRYDROPFLAG, 1/10, 10, L"nil, 'Baaaaahh'")
abuse.ratelimit(server.N_TAKEFLAG, 1/3, 10, L"nil, 'Beeeehh'")

--prevent masters from annoying players
local tb = require"utils.tokenbucket"
local function bullying(who, victim)
  local t = who.extra.bullying or {}
  local rate = t[victim.extra.uuid] or tb(1/30, 6)
  t[victim.extra.uuid] = rate
  who.extra.bullying = t
  return not rate()
end
spaghetti.addhook(server.N_SETTEAM, function(info)
  if info.skip or info.who == info.sender or not info.wi or info.ci.privilege == server.PRIV_NONE then return end
  local team = engine.filtertext(info.text):sub(1, engine.MAXTEAMLEN)
  if #team == 0 or team == info.wi.team then return end
  if bullying(info.ci, info.wi) then
    info.skip = true
    playermsg("...", info.ci)
  end
end)
spaghetti.addhook(server.N_SPECTATOR, function(info)
  if info.skip or info.spectator == info.sender or not info.spinfo or info.ci.privilege == server.PRIV_NONE or info.val == (info.spinfo.state.state == engine.CS_SPECTATOR and 1 or 0) then return end
  if bullying(info.ci, info.spinfo) then
    info.skip = true
    playermsg("...", info.ci)
  end
end)

--ratelimit just gobbles the packet. Use the selector to add a tag to the exceeding message, and append another hook to send the message
local function warnspam(packet)
  if not packet.ratelimited or type(packet.ratelimited) ~= "string" then return end
  playermsg(packet.ratelimited, packet.ci)
end
map.nv(function(type) spaghetti.addhook(type, warnspam) end,
  server.N_TEXT, server.N_SAYTEAM, server.N_SWITCHNAME, server.N_MAPVOTE, server.N_SPECTATOR, server.N_MASTERMODE, server.N_AUTHTRY, server.N_AUTHKICK, server.N_CLIENTPING, server.N_TRYDROPFLAG, server.N_TAKEFLAG
)


--simple banner
require"std.maploaded"

spaghetti.addhook("maploaded", function(info)
  local banner = "\n\f6Sauer \f3PROP HUNT!\f2 - Be a prop and hide, or hunt all enemy props before the time runs out!\nMake sure to read the \f0#rules \f2and have fun!"
  if info.ci.extra.bannershown then return end
  local ciuuid = info.ci.extra.uuid
  spaghetti.later(1000, function()
    local ci = uuid.find(ciuuid)
    if not ci then return end
    playermsg(banner, ci)
    info.ci.extra.bannershown = true
  end)
end)

local git = io.popen("echo `git rev-parse --short HEAD` `git show -s --format=%ci`")
local gitversion = git:read()
git = nil, git:close()
commands.add("info", function(info)
  playermsg("spaghettimod is a reboot of hopmod for programmers. Will be used for SDoS.\nKindly brought to you by pisto." .. (gitversion and "\nCommit " .. gitversion or ""), info.ci)
end)

local infos = {
  "\n\f6Tip: \f2You can always run away if you're discovered, but will take damage as long as your prop is not placed down.",
  "\n\f6Tip: \f2As a prop, scroll with mouse wheel to choose your disguise.",
  "\n\f6Tip: \f2As a hunter, watch your ammo! It will only slowly regenerate.",
  "\n\f6Tip: \f2Hunters will see moving props marked with a big flame.",
  "\n\f6Tip: \f2The playermodels of team \"prop\" are invisible to the hunters - they can only see the prop itself.",
  "\n\f6Tip: \f2The props will make a grunting sound every 15 seconds.",
  "\n\f6Tip: \f2As a prop, press \f3i \f2to grunt and confuse the hunters!",
}

spaghetti.addhook("changemap", function() spaghetti.latergame(3 * 60 * 1000, function()
    local item = infos[math.random(#infos)]
    server.sendservmsg(item)
  end, true)
end)
