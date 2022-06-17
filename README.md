# What is this?

A fork of [spaghettimod](https://github.com/pisto/spaghettimod) by [pisto](https://github.com/pisto), updated to the [Sauerbraten 2020 Edition](http://sauerbraten.org), and featuring some additional scripts.

## Table of contents:
* [About spaghettimod](#about-spaghettimod)
* [Setup Tutorial](#setup-tutorial)
	* [Setting up the build environment](#setting-up-the-build-environment)
	* [Configuration and Running](#configuration-and-running)
* [Discord Bot](#discord-bot)
	* [Installing node modules](#installing-node-modules)
	* [Necessary configuration](#necessary-configuration)
	* [Running the bot](#running-the-bot)

# About spaghettimod

**spaghettimod** is a Cube 2: Sauerbraten server mod with Lua scripting. It is completely different from Hopmod (the other Lua server mod around). It is for modders who already have a good knowledge of the Sauerbraten server codebase, and just want tools to easily extend that with Lua. It is *not* for clan leaders who just want a personalized (read, custom message color or little more) server.

For this reason, the principles are mostly coding principles.

* minimize impact on the C++ codebase, for easier merging and predictable behavior
* expose the C++ engine as-is to Lua, making it easier to write Lua code as if it was C++ inlined into the vanilla implementation
* no bloat, and use external libraries as much as possible (fight the NIH syndrome)
* provide modular standard libraries for most wanted stuff, but configuration is done through a Lua script, not configuration variables
* no cubescript (`VAR` and `COMMAND` are mirrored to Lua)
* ease of debugging

I am available in Gamesurge as pisto. It is called **spaghettimod** because I'm italian.

## Performance

Performance is deemed to be "very good". I run the ZOMBIE OUTBREAK! server and even in crowded situations (~20 players, ~60 bots) it still takes only 10%-15% of cpu and 25-30 MB of memory, and since Lua is called for at least every N_POS message, performance in general should not be a concern.

In my experience, Lua generates a lot of memory fragmentation together with the glibc implementation of `malloc()`, which means that memory may be deallocated but never returned to the system, and the server process will result to use much more memory than what is reported by `collectgarbage"count"`. This is particularly noticeable when the `100-extinfo-noip.lua` script finds the GeoIP cvs databases and generates a fake geolocalized ip: a lot of tables are allocated, then freed, but the server still takes 60 MB. I solved the problem by using a low fragmentation implementation of `malloc()`, [jemalloc](http://www.canonware.com/jemalloc/): the memory usage at boot is now ~13 MB.

## Compilation
[Jump to the setup tutorial](#setup-tutorial)

Compilation has been tested with luajit, lua 5.2, lua 5.1, on Mac OS X, Windows and Linux. The default scripts are written with a Unix environment in mind, so most probably they won't work under Windows. The only other dependency is libz.

The Makefile is different from vanilla but acts the same. `make` generally should suffice to create the executable in the top folder.

The Lua version is determined automatically with `pkg-config`, preferring in order luajit, lua5.2, lua, lua5.1. If you wish to select a version manually, pass `LUAVERSION` to `make`, e.g. `make LUAVERSION=5.3`. You can override the `pkg-config` detection with `LUACFLAGS` and `LUALDFLAGS`.

If you want to cross compile, pass the host triplet on the command line with `PLATFORM`, e.g. `make PLATFORM=x86_64-w64-mingw32`.

To change the optimization settings, you sould use the `OPTFLAGS` variable instead of `CXXFLAGS` directly.

### RAM usage during compilation

Compilation of *{engine,fpsgame}/server.cpp* take an enormous amount of RAM (~ 700MB) because of heavy template instantiation in the Lua binding code. This can be a problem on a resource limited VPS. If you hit this problem, try this:

```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

`clang` is known to use around one fourth less memory. Additionally, you can disable debug symbols generation with `DEBUG=""`: this will save one fourth of memory in `g++`, roughly half in `clang` (it will also make compilation around one third faster). If you have a crash and find yourself without debugging symbols you can try to rebuild spaghettimod without the `DEBUG` modifier and hope that the output executable is the same as the old one at binary level, which is generally the case but not guaranteed. `gdb` will also spit out the warning "exec file is newer than core file.", but you can ignore that. With these hints (`clang` and `DEBUG=""`) you can get down to ~ 300MB memory usage.

### Debugging

You can debug the server and client code, C++ and Lua, without network timeouts, thanks to the patch [enetnotimeouts.diff](https://raw.github.com/pisto/spaghettimod/master/enetnotimeouts.diff). Follow this procedure:

1. download and install the [SDoS test client](https://github.com/pisto/sdos-test), or apply the patch to your client
2. start the server, optionally under a C++ debugger
  * the standard bootstrap file tries to run either the [ZeroBrane Studio](http://studio.zerobrane.com/doc-remote-debugging) or [Eclipse LDT](https://wiki.eclipse.org/Koneki/LDT/Developer_Area/User_Guides/User_Guide_1.1#Attach_Debug) remote debuggers
3. start the client, optionally under a debugger, and connect to the server
4. issue `/enetnotimeouts 1` on the client, and `engine.serverhost.noTimeouts = 1` on the server

With these steps, you can stop the execution with any of the three debuggers involved, and resume at will without timeouts.

#### Stack traces

The C++ code takes care to call all Lua code with `xpcall` and a stack dumper, so in general you always get meaningful stacktraces. Unfortunately, the LDT debugger does not support break on error (and I suppose it is not possible to fully implement that without C source modding): however, you can place a breakpoint on [this line](https://github.com/pisto/spaghettimod/blob/master/script/bootstrap.lua#L6) to break at least on error thrown by hooks.

If you are using a C debugger and spaghettimod crashes or halts while executing Lua code, you get a rather useless C stack trace of the Lua VM. If you are using gdb and Lua 5.2, you may use these [gdb scripts](https://github.com/pisto/lua-gdb-helper): just type `luatrace spaghetti::L`, and you hopefully will get a Lua stack trace (for Lua 5.1 or luajit, you may need to edit the script and use `lua_pcall` instead of `lua_pcallk`).

## Advanced networking

The in-tree ENet source comes with two additional features, besides the aforementioned debugging switch: multihoming and a connection flood protection, akin to [TCP syn cookies](http://en.wikipedia.org/wiki/SYN_cookies). Multihoming is hardcoded and cannot be turned off (without dirty hacks), while the connection flood protection needs to be explicitly activated. This is done in the default configuration script *100-connetcookies.lua*.

### Multihoming

This patch allows the server to run correctly on servers attached to multiple networks on unix hosts, which boils down to sending reply packets from the same interface that received the request. There are two extra functions that ENet exports:

* `ENET_SOCKOPT_PKTINFO`: option value to enable local interface address information on a socket, needs to be set on sockets that use the two following functions.
* `int enet_socket_receive_local (ENetSocket, ENetAddress *, ENetBuffer *, size_t, ENetAddress * localAddress)`: same as `enet_socket_send_local`, but if `localAddress` is non null the address of the receiving interface is stored in `localAddress.host` (the `port` field is undefined).
* `int enet_socket_send_local (ENetSocket, const ENetAddress *, const ENetBuffer *, size_t, ENetAddress * localAddress)`: similarly, same as `enet_socket_send` but reads the interface from which the packet need to be sent in `localAddress`, if non null.

At the moment, Windows is not supported because the required functions [need to be loaded at runtime](http://msdn.microsoft.com/en-us/library/windows/desktop/ms741692%28v=vs.85%29.aspx), and would need to be attached to each socket (but this is not so clear from the MSDN documentation).

This patch enables also creating a single connected socket for each peer if the system supports `SO_REUSEPORT`. This helps because traffic to a connected socket is implicitly prioritized from traffic from not-yet-connected peers (see the next paragraph for an exmplanation of why this is necessary) as one buffer is allocated specifically for that peer, and shuffling packet requires less ancillary data to be communicated with the kernel. The TOS field of the IP header for packets from these sockets is set to 4, to help in setups with iptables, where you want to do certain actions if the server acknowledges a connection.

### ENet cookies

Upstream ENet is particularly vulnerable to connection slots exhaustion if an attacker can spoof the source IP, because for each new connection request a new peer is setup in a state almost equal to that of an established connection. An established connection takes quite a long time to timeout. Furthemore, processing the connection packet is not optimized to the bone.

This patch "hacks" the protocol to send a cookie with 2^16\*`peerCount` different possible values on each connection request, and only stores a lightweight object to restore the complete peer state once an ack is received with such cookie. The cookie is sent only once, contrary to vanilla ENet which treats the connection verification packet as a normal one, and so is affected by normal timeouts and retry attempts. Once a valid ack is received, the peer is effectively setup for communication. It's important to note that all the other connection attempts to the same `peerID` are discarded, so you should create your `ENetHost` with the maximum available number of peers (`ENET_PROTOCOL_MAXIMUM_PEER_ID = 0xFFF`), to maximize entropy in the cookie and minimize erroneously discarded connection attempts (and **spaghettimod** does that).

The implementation is optional and needs to be activated explicitly. It is highly optimized to process connection requests and connection verification acknowledgements. The tradeoff between CPU (and so performance and packet drop) and memory can be tuned linearly with a parameter, and so the timeout for each connection request. A good random number generator is needed, and it is responsibility of the user to provide it through a callback, because there is no good cross platform PRNG.

Cookies can be activated with a call to `int enet_host_connect_cookies(ENetHost * host, const ENetRandom * randomFunction, enet_uint32 connectingPeerTimeout, enet_uint8 windowRatio)`:

* `randomFunction`: a callback which provides entropy to ENet (if null, deactivates cookies). Fields are
  * `void * context`: a context to pass to the function
  * `enet_uint32 (ENET_CALLBACK * generate) (void * context)`: the actual function pointer, which needs to provide 32 bits of entropy at each call
  * `void (ENET_CALLBACK * destroy) (void * context)`: a function called once `enet_host_connect_cookies` is called on the same `host` again, for the purpose of finalizing the context. Can be null.
* `connectingPeerTimeout`: timeout for each connection request, if zero it is set to `ENET_HOST_DEFAULT_CONNECTING_PEER_TIMEOUT = 2000`.
* `windowRatio`: a percentage parameter that controls tradeoff between CPU and memory, if zero it is set to `ENET_HOST_DEFAULT_CONNECTS_WINDOW_RATIO = 10`.

Memory usage roughly follows this formula (size\_of\_cookie = 60): attack\_pps * (`connectingPeerTimeout` / 1000) * (100 / `ENET_HOST_DEFAULT_CONNECTS_WINDOW_RATIO`) * size\_of\_cookie. With the default parameters, a 10k pps attack can be stopped without problems with 12 MB of memory, and in informal tests it has been found that this scales well at least up to the range of 150k pps (you may need to enlarge the socket receive and send buffers with the normal ENet API).

## Information for Lua modders

The Lua API tries to be as much as similar to the C++ code. Generally you can write basically the same stuff in Lua and C++ (replacing `->` with `.` maybe). This also means that there is no handholding: very little is being checked for sanity (like in C++), your lua script *can* crash the server, and don't even think to run Lua script sent by the client, exploits are possible.

Things that are accessible in the C++ global namespace `::` are bound to Lua in the table `engine`, and things that are in `server::` are bound in `server`. This means that the crypto functions are in `engine`. There is an extra predefined table, `spaghetti`, which holds user defined events (see later) and a field, `spaghetti.quit`: once this is set to true, it cannot be unset, and the server will shutdown as soon as possible. This way to shutdown the server is preferred to just terminate the program from lua, or even from calling the sauerbraten shutdown functions from Lua.

Cubescript has been totally stripped. variables and commands are exported to Lua in the table `cs` as variables that you can read/write and functions that you can call.

**spaghettimod** tries to minimize the modifications to the vanilla code. This is reflected also in the way that C++ and Lua interact. Whereas Lua can access almost all the internals of the sauerbraten server, the interaction C++ -> Lua happens through
* binding
* calling *script/bootstrap.lua* at boot
* issuing events

The default bootstrap file just export two event related helpers (see next section), and calls the files in *script/load.d/*, which have to follow the naming scheme *# # -somename.lua*, where *# # * determines the relative order in calling the files (from lower to higher).

### Events

Events are calls that the C++ code makes to Lua. When a specific even occurs, the engine runs this code:

```lua
local argument_table = {
    -- event specific named arguments
}
local listener = spaghetti[event_type]
if listener then listener(argument_table) end
```

The arguments are usually linked directly to C++ function variables, and the modifications you do in Lua are reflected in C++. Some arguments might be read only.

If the event is cancellable (with semantics specific to the event), the argument table contains a field `skip`, which if set to true, once the listener returns, causes the event to be cancelled. Cancellable events are issued before "side effects" take place, and non cancellable events after.

The number and kind of events is in flux, the arguments passed correspond, most of the time, to the C++ function variables, and the exact meaning of cancellation depends on the kind of event. Hence it's rather pointless to write down a list here, since it would need to constantly refer to code lines. You can work out a list of event with some `grep` commands.
* cancellable events: `grep -REho "spaghetti::simple(const)?hook.*\)" engine/ fpsgame/ shared/ spaghetti/spaghetti.cpp | sort | uniq`
* non cancellable events: `grep -REho "spaghetti::simple(const)?event.*\)" engine/ fpsgame/ shared/ spaghetti/spaghetti.cpp | sort | uniq`
The results are in the form `spaghettimod::issueevent(event_type, args...)`, where issueevent is one of simplehook, simpleevent, simpleconstevent. The `event_type` is either a `N_*` enum which correspond to `server.N_*` in Lua, or `spaghetti::hotstring::event_type`, which means `"event_type"` in Lua.

So far this is the only hardcoded behavior, but the *script/bootstrap.lua* that comes with upstream adds two functions: `spaghetti.addhook(event_type, your_callback, do_prepend)` and `spaghetti.removehook(token)`. They implement a simple event listeners multiplexer: you add a listener with `local hook_token = spaghetti.addhook(event_type, your_callback)`, and you remove it with `spaghetti.removehook(hook_token)`. Hooks are called in the order that they are installed, and you can force a hook to be put first in the list with `do_prepend = true`.

### Caveats on bindings (important!)

`ENetPacket` structures are transparently wrapped to use the native reference counting. This renders `enet_packet_destroy` impossible to use directly without introducing a double-free bug. For this reason, enet_packet_destroy is not bound to Lua. Furthermore, `packetbuf` uses reference counting *always*, regardless of the growth value.

In C++ the cryptographic functions return generally pointers to `void*` and have to be freed. Lua returns and takes strings with literal or binary hashes (`grep -F addFunction shared/crypto.cpp`).

The original sauer implementation of hash swaps the nibbles (e.g. byte 0x4F is written as 0xF4). This is kept for compatibility, but if you want to get a correct tigersum use `engine.hashstring(yourdata, true)`.

`ucharbuf`, `vector<uchar>`, `packetbuf` now have method versions for `sendstring` `putint` `putuint` `putfloat` (they return the object itself so you can make a dot chain), `getstring` `getint` `getuint` `getfloat`.

Some C++ structures that represent binary buffers map to Lua strings by accessing the `char*` (or `void*`) pointer: `ENetPacket` (read only), `ENetBuffer` (read-write), `ucharbuf` (read only) (`grep -F lua_buff_type engine/server.cpp fpsgame/server.cpp shared/crypto.cpp`).

Some functions that require a binary buffer are proxied by functions that take strings, or functions that require an output buffer just return a new string (along with the original return, if applicable): `enet_packet_create`, `decodeutf8`, `encodeutf8`, `filtertext`, `hashstring`, `genprivkey`, `processmasterinput`... (`grep -E '\.add.*\+\[\]' engine/server.cpp fpsgame/server.cpp shared/crypto.cpp`).

`luabridge`, the library I use to bind C++ stuff to Lua, allows only one constructor to be bound (find out which with `grep -FB 1 addConstructor engine/server.cpp fpsgame/server.cpp shared/crypto.cpp`).

The `static const` parameters in *fpsgame/{ctf,capture,collect}.h* are now modifiable, as well as some `const` arrays in *fpsgame/game.h* (`itemstat`, `guninfo`).

Not all fields of `ENetHost` and `ENetPeer` are exported. As a rule of thumb, those that are clearly meant for internal usage by enet (for example the lists of packet fragments) will be unavailable.

## The scripting environment

The default boostrap code adds *script/* to the `LUA_PATH`, to ease `require`.

*utils* contain some functional programming utilities, `ip` and `ipset` object that are already documented in [kidban](https://github.com/pisto/kidban/tree/master/maintaining-docs#modules), and other generic helpers.

*std* contains the standard modules. I am too lazy to write a documentation for these before someone actually shows interest in using my code. Feel free to contact me if you want to write your own modules.

# Setup Tutorial
As stated above, this server is primarily built with a linux environment in mind. You should therefore compile and run it on either a linux VPS or a virtual machine.


## Setting up the build environment
Install the common build tools, some libraries and LUA 5.2 (might have to be run as root):

``` 
apt install zip unzip rlwrap pkg-config git build-essential zlib1g-dev lua5.2 liblua5.2 liblua5.2-dev lua-posix
```     

You should also get luarocks and install some needed packages (may require root):
```
wget https://luarocks.github.io/luarocks/releases/luarocks-3.3.1.tar.gz && tar xzf luarocks-3.3.1.tar.gz; rm -fv luarocks-3.3.1.tar.gz; mv luarocks-3.3.1 luarocks
cd luarocks
./configure --lua-version=5.2
sudo make install
sudo luarocks install struct 
sudo luarocks install uuid 
sudo luarocks install luasocket 
sudo luarocks install dkjson
sudo luarocks install mmdblua
cd ..
```
Finally, you can get spaghettimod..

`git clone https://github.com/pisto/spaghettimod.git` (Collect Edition, the original by pisto)

or

`git clone https://github.com/benzomatic/spaghettimod.git` (2020 Edition + my mods, discord bot)
.. and run 
```
make
```
from the spaghettimod root directory.

## Configuration and Running

### The default configuration

If you start the server with the enviroment variable `SPAGHETTI` set (`SPAGHETTI=1 ./sauer_server`), you will spawn a server using the default configuration defined in *1000-sample-config.lua*, with a default map rotation, abuse protection, and some optional gamemods (quadarmours and flag switch).

Starting the server without an environment variable will create a vanilla-like Sauerbraten server.

### Custom configurations

The configuration files for the modes below can be found in the script/load.d directory. Check out which ports and master server settings they use in order to be able to connect and play with others.

**The ZOMBIEVPS configuration**

The ZOMBIE OUTBREAK! server can be started with `ZOMBIEVPS=1 ./sauer_server`. It is a heavily modded gamemode with up to 128 bots, and showcases a variety of event hooks.

**The RUGBY configuration**

A server running Rugby mode can be started with `RUGBY=1 ./sauer_server`. If players are carrying the flag in insta ctf, they can shoot a teammate to pass it to them. Four different flavors of Rugby are available, check out the config in *script/load.d/1000-rugby-config.lua* and *script/gamemods/* to see which ones.

**The Hide & Seek configuration**

A server running Hide & Seek can be started with `HAS=1 ./sauer_server`. Players in team "hide" have to hide from the seekers. If a hider is caught, he will join the seekers and fight against a time limit to expose the rest of the hiding players.

**The Prop Hunt configuration**

A server running Prop Hunt can be started with `PROPHUNT=1 ./sauer_server`. This is the Sauer adaption of prop hunt, a hide & seek mode where the hiders are disguised as objects on the map, as seen in Garry's Mod or CoD. Props hide across the map, and hunters will try to find them using their mg and chainsaw. The props will make a grunting sound periodically. A client interface to pick and choose from the available models can be found [here](https://github.com/benzomatic/prop-hunt-gui).

**Autoloaded modules**

As described above, scripts in *script/load.d* will automatically execute once on server launch. They introduce some sane default configuration. 
These modules are:

1. *10-logging.lua* : improved logging with date, renames, etc
2. *20-cleanshutdown.lua* : gracefully kick all clients on shutdown, remove the server from master quickly
3. *100-connetcookies.lua* : harden the server against (D)DoS attacks, see section [Advanced networking](# enet-cookies))
4. *100-extinfo-noip.lua* : do not expose the (partial) IP of players through extinfo (either send `0`, or a random IP from the same country if `GeoIPCountryWhois.csv` is available)
5. *100-geoip.lua* : show Geoip on client connect, and provide the `#geoip [cn]`
6. *2000-demorecord.lua* : record demos in `<servertag>.demos` (`std.servertag` is a module that returns either the port number or a user provided string to tag the server among various instances)
7. *2000-serverexec.lua* : create a unix socket for a Lua interactive shell, connect with `socat READLINE,history=.spaghetti_history UNIX-CLIENT:./28785.serverexec`
8. *2000-stdban.lua* : advanced ban and kicks support (IP ranges, access rules, bypass rules, listing and deletion...)
9. *2000-ASkidban.lua* : ban proxies with [ASkidban](https://github.com/pisto/ASkidban/)
10. *2100-mapswitch-gc.lua* : run a Lua garbage collection cycle after a map load
11. *off/3000-shelldetach.lua* (off by default unless you have the `luaposix` package and symlink it in the `script/load.d` folder): make the server fork to background and write logs to `<servertag>.log`, and execute a full restart on `SIGUSR1` (updating to the latest revision is as easy as `git pull && make && killall -s SIGUSR1 sauer_server`).

Additional assorted modules can be found in pisto's repo [spaghettimod-assorted](https://github.com/pisto/spaghettimod-assorted).

# Discord Bot
This repository also contains a discord bot written in JavaScript. It requires NodeJS (only tested until node version 13) and, depending on your preferences, also a process manager like [pm2](https://pm2.keymetrics.io) to run it in the background.
You also need a discord bot that is invited to your server, and its API token, both of which can be created  [here](https://discordapp.com/developers/applications/).

**Required bot permissions:**  Additionally to the standard Send/Read Messages, make sure to have Manage Messages and Read Message History enabled. Usually granted automatically (yet important) are permissions to send embeds and attach files (for thumbnails), and the ability to issue @here mentions if alerts are enabled. If auto-voice is used, it also needs Move Members permissions in the given voice channels.

### Installing node modules
```
curl -sL https://deb.nodesource.com/setup_13.x | bash -
apt install -y nodejs npm
```
Then
- cd into /spaghettimod/discord/
- run `npm install` to install all dependencies 

### Necessary configuration
#### 1) NodeJS: Open discord/config.json and configure the following

* `discordToken` is your discord API bot token
* `commandPrefix` is the bot command prefix
* `alerts` will activate #cheater alerts
* `alertChannelID` is an optional dedicated channelID for #cheater alerts
* `useEmbeds` to display the server broadcast in embeds; if disabled, will use classic text messages in the main channel
* `enableThumbnails` will show a fancy map preview on status messages
* `enableScoreboard` will show a scoreboard with every player's stats appended to a status message
* `alwaysScoreboard` will show a scoreboard on every status message if there is no seperate scoreboard channel
* `relayHost`  should stay 127.0.0.1
* `relayPort` can be any free port, but the port in the LUA config must be the same

#### 2) LUA: Open the main config of your server (1000-sample-config.lua in my case) and add (or uncomment) the following:
```
require"std.discordrelay".new({
  relayHost = "127.0.0.1", 
  relayPort = 57575, 
  discordChannelID = "my-discord-channel-id",
  scoreboardChannelID = "my-scoreboard-channel-id",
  voice = {
    good = "good-channel-ID",
    evil = "evil-channel-ID"
  }
})
```

* where `relayHost`  and `relayPort` **must** match what is configured in NodeJS and
* `discordChannelID` is the channel ID that this server will send messages to, and commands will be read from
* `scoreboardChannelID` is an optional channel for a dedicated scoreboard that will update by the minute
* `voice` is an optional table that maps team names to voice channels in discord. People that link themselves via #voice will be auto-synchronised with the respective team channel

#### Voice

If voice channels were linked, a new command `#voice` will be added. Users can:
* join a voice channel and type `#voice`: The bot will link the client if it finds a similar name in the voice channels
* type `#voice pw`: The user will be sent a code to pm to the discord bot; the user will log in after that
* type `#voice <code>`: The user provides a code that the bot had sent to them earlier, and they will log in as well.

### Running the bot

#### cd into `discord` and start the discord bot like this or through a process manager:

```
cd discord
node app
```
Please make sure to start the discord bot before starting spaghettimod. 
The discord bot is designed to handle multiple spaghettimod gameservers at the same time.

