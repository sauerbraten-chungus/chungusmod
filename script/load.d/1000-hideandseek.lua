--[[

  Hide & Seek configuration

]]

if not os.getenv("HAS") then return end
engine.writelog("Applying the Hide & Seek configuration.")

local servertag = require"utils.servertag"
servertag.tag = "has"

local uuid = require"std.uuid"

local fp, L = require"utils.fp", require"utils.lambda"
local map, I = fp.map, fp.I
local abuse, playermsg = require"std.abuse", require"std.playermsg"

cs.maxclients = 12
cs.serverport = 1000

spaghetti.later(10000, L'engine.requestmaster("\\n")', true)
spaghetti.addhook("masterin", L'if _.input:match("^failreg") then engine.lastupdatemaster = 0 end', true)

cs.serverauth = "hideandseek"
local auth = require"std.auth"

-- ########## AUTHKEYS #########
cs.adduser("benzomatic", "hideandseek", "+a26e607b5554fd5b316a4bdd1bfc4734587aa82480fb081f", "a")
cs.adduser("Pointblank", "hideandseek", "-2e93b2f4538281922b277e74ba7195697988749bebde657a", "m")
cs.adduser("Plata", "hideandseek", "-36a10e3e2b87fa6a93d4f46f232bf1be6a8e4b899eaa342d", "m")
cs.adduser("Josh22", "hideandseek", "+3a2aed3f6c9574c5dead1160db72333a4263742cd81194fa", "m")
cs.adduser("Master", "hideandseek", "-9557093a832b82287c15d0ffce164fd86714a9f00a5110ee", "m")
cs.adduser("Tay|Z", "hideandseek", "-7c8b67a1c74772b58d11348f4222df3e7bcd98d97df705eb", "m")
cs.adduser("BigBuffyBoy85", "hideandseek", "+9c6200a1351583535ee6800d6ae2784720a27b23b23960f6", "m")
cs.adduser("scope", "hideandseek", "-d1afe97a71766c1291dd6b9d56d1dbb261c4acc8348a101c", "m")

table.insert(auth.preauths, "hideandseek")
table.insert(auth.preauths, "spaghettimod")

cs.serverdesc = "\f4- \f6Hide & Seek \f4-"

cs.lockmaprotation = 0  -- everyone can vote every map
cs.ctftkpenalty = 0

local smallhasmaps, largehasmaps = table.concat({
  "abbey akaritori akroseum alithia alloy aqueducts arabic arbana asteroids authentic bad_moon bt_falls c_egypt",
  "campo capture_night castle_trap collusion core_transfer corruption curvedm cwcastle damnation darkdeath depot",
  "dirtndust DM_BS1 dust2 evilness face-capture fb_capture fc3 fc4 fc5 flagstone forge forgotten",
  "garden guacamole hades hallo haste hog2 injustice katrez_d killcore3 killfactory kmap5 lostinspace",
  "mbt1 mbt4 mercury mill monastery moonlite nevil_c nitro nmp4 nmp8 nmp9 nucleus ogrosupply orbe paradigm ph-capture phosgene pitch_black powerplant",
  "redemption reissen relic river_c roughinery ruby ruine serenity shipwreck snapper_rocks spcr subterra suburb",
  "tejen tempest thetowers thor turbulence twinforts urban_c"
}, " "), table.concat({
  "abbey akaritori akroseum aqueducts arabic arbana asgard autumn berlin_wall bt_falls c_egypt c_valley",
  "campo caribbean catch22 core_refuge core_transfer damnation darkdeath desecration",
  "dirtndust donya duomo dust2 eternal_valley europium evilness fb_capture fc4 fc5 flagstone forge forgotten frostbyte",
  "garden hallo hidden hog2 infamy killcore3 killfactory kmap5 konkuri-to kopenhagen lostinspace",
  "mach2 mbt1 mbt4 mbt12 mercury mill monastery nevil_c nmp4 nmp8 nucleus ogrosupply orbe ph-capture",
  "recovery reissen relic river_c roughinery ruby ruine sacrifice serenity shipwreck siberia snapper_rocks spcr subterra suburb",
  "tejen tempest thetowers thor tortuga turbulence urban_c valhalla venice xenon"
}, " ")

smallhasmaps, largehasmaps = map.uv(function(maps)
  local t = map.f(I, maps:gmatch("[^ ]+"))
  for i = 2, #t do
    local j = math.random(i)
    local s = t[j]
    t[j] = t[i]
    t[i] = s
  end
  return table.concat(t, " ")
end, smallhasmaps, largehasmaps)

cs.maprotationreset()
cs.maprotation("instateam efficteam", smallhasmaps)

--spaghetti.addhook("intermission", L'cs.maprotationreset(), cs.maprotation("instateam", server.numclients(-1, true, true) <= 5 and smallhasmaps or largehasmaps)')

local smallmaps = true
spaghetti.addhook("intermission", function(info)
  if server.numclients(-1, true, true) <= 6 then
    if not smallmaps then
     cs.maprotationreset()
     cs.maprotation("instateam efficteam", smallhasmaps)
     smallmaps = true
    end
  else
    if smallmaps then
      cs.maprotationreset() 
      cs.maprotation("instateam efficteam", largehasmaps)
      smallmaps = false
    end
  end
end)

spaghetti.addhook("noclients", function()
  cs.maprotationreset()
  cs.maprotation("instateam efficteam", smallhasmaps)
end)

local has = require"gamemods.hideandseek"

cs.publicserver = 3

local fp, L, ents = require"utils.fp", require"utils.lambda", require"std.ents"
local vec3 = require("utils.vec3");
local map = fp.map
local commands, putf = require"std.commands", require"std.putf"


local ents = require"std.ents", require"std.maploaded"
require"std.pm"
--require"std.getip"
require"std.specban"

--[[

require"std.discordrelay".new({
  relayHost = "127.0.0.1", 
  relayPort = 57575, 
  discordChannelID = "my-discord-channel-id",
  scoreboardChannelID = "my-scoreboard-channel-id",
  voice = {
    hide = "hide-voice-channel",
    seek = "seek-voice-channel"
  }
})

]]

spaghetti.addhook("entsloaded", function()
  if server.smapname == "core_refuge" then
    ents.newent(server.MAPMODEL, {x = 495, y = 910, z = 509}, 60, "tentus/fattree")
    ents.newent(server.MAPMODEL, {x = 400, y = 910, z = 511}, 60, "tentus/fattree")
  elseif server.smapname == "fb_capture" then
    ents.newent(server.MAPMODEL, {x = 986, y = 572.5, z = 182}, 266, "vegetation/tree03")
  elseif server.smapname == "thetowers" then 
    for i, _, ment in ents.enum(server.JUMPPAD) do if ment.attr4 == 40 then
      ents.editent(i, server.JUMPPAD, ment.o, ment.attr1, ment.attr2, ment.attr3)
      break
    end end
  end
end)

--moderation
cs.teamkillkick("*", 7, 30)

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
abuse.ratelimit(server.N_SERVCMD, 0.5, 10, L"nil, 'Yes I\\'m filtering this too.'")
abuse.ratelimit(server.N_JUMPPAD, 1, 10, L"nil, 'I know I used to do that but... whatever.'")
abuse.ratelimit(server.N_TELEPORT, 1, 10, L"nil, 'I know I used to do that but... whatever.'")

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
  server.N_TEXT, server.N_SAYTEAM, server.N_SWITCHNAME, server.N_MAPVOTE, server.N_SPECTATOR, server.N_MASTERMODE, server.N_AUTHTRY, server.N_AUTHKICK, server.N_CLIENTPING
)

local sound = require"std.sound"
spaghetti.addhook(server.N_TEXT, function(info)
  if info.skip then return end
  local low = info.text:lower()
  if not low:match"cheat" and not low:match"hack" and not low:match"auth" and not low:match"kick" then return end
  local tellcheatcmd = info.ci.extra.tellcheatcmd or tb(1/30000, 1)
  info.ci.extra.tellcheatcmd = tellcheatcmd
  if not tellcheatcmd() then return end
  playermsg("\f2Problems with a cheater? Please use \f3#cheater [cn|name]\f2, and operators will look into the situation!", info.ci)
  sound(info.ci, server.S_HIT, true) sound(info.ci, server.S_HIT, true)
end)

require"std.enetping"

local parsepacket = require"std.parsepacket"
spaghetti.addhook("martian", function(info)
  if info.skip or info.type ~= server.N_TEXT or info.ci.connected or parsepacket(info) then return end
  local text = engine.filtertext(info.text, true, true)
  engine.writelog(("limbotext: (%d) %s"):format(info.ci.clientnum, text))
  info.skip = true
end, true)

--simple banner
spaghetti.addhook("maploaded", function(info)
  if info.ci.extra.bannershown then return end
  local banner = "Welcome to \f4- \f6Hide & Seek \f4-\n"
  if require"gamemods.hideandseek".game.has then
    banner = banner .. "An active Hide & Seek game is running. \f0You will be added on the next map. \f6In the meantime, read the \f0#rules\f6!"
  else
    banner = banner .. "Type \f0#has \f6to launch a game of Hide & Seek!"
  end
  info.ci.extra.bannershown = true
  local ciuuid = info.ci.extra.uuid
  spaghetti.later(1000, function()
    local ci = uuid.find(ciuuid)
    if not ci then return end
    playermsg("\n", ci)
    playermsg(banner, ci)
  end)
end)

spaghetti.later(60000, function()
  local activehas = require"gamemods.hideandseek".game.has
  if activehas then return end
  return server.m_teammode and server.sendservmsg("\n\f4> \f6Tip: Type \f0#has \f6to launch a game of Hide & Seek!")
end, true)

local git = io.popen("echo `git rev-parse --short HEAD` `git show -s --format=%ci`")
local gitversion = git:read()
git = nil, git:close()
commands.add("info", function(info)
  playermsg("spaghettimod is a reboot of hopmod for programmers. Will be used for SDoS.\nKindly brought to you by pisto." .. (gitversion and "\nCommit " .. gitversion or ""), info.ci)
end)

--lazy fix all bugs.

spaghetti.addhook("noclients", function()
  if engine.totalmillis >= 24 * 60 * 60 * 1000 then reboot, spaghetti.quit = true, true end
end)
