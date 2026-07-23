# AGENTS.md — chungusmod

## Overview

Cube 2: Sauerbraten game server fork with Lua scripting via spaghettimod. Integrates with the chungus platform for matchmaking, verification codes, and stats reporting.

- **Language**: C++ (engine) + Lua (game logic/config)
- **Build**: Make → produces `sauer_server` binary
- **Status**: Active

## Build

```bash
make                          # auto-detects LuaJIT/Lua version
make clean
SPAGHETTI=1 ./sauer_server    # run with spaghettimod scripts
```

**Note**: Lua binding templates consume ~700MB RAM during compilation. Use clang + `DEBUG=""` to mitigate.

## Project Structure

```
chungusmod/
├── engine/          # Core Cube 2 engine (C++)
│   └── server.cpp   # ENet host, chungus peer connection, packet handling
├── fpsgame/         # Game logic (C++)
│   └── server.cpp   # Game modes, player state (189KB)
├── shared/          # Shared utilities, crypto
├── spaghetti/       # C++↔Lua bridge (spaghetti.cpp, later.cpp)
├── enet/            # Bundled ENet library
├── include/         # LuaBridge headers
├── script/
│   ├── bootstrap.lua     # Entry point, hook multiplexer
│   ├── load.d/           # Auto-loaded modules (priority-based: NN-name.lua)
│   ├── std/              # Standard library (~45 modules)
│   ├── gamemods/         # Game mode implementations
│   └── utils/            # Utility libraries
├── packages/base/   # Map configs
├── discord/         # Discord bot (Node.js)
├── Makefile
└── Dockerfile
```

## Lua Scripting Layer

### Auto-Loaded Modules (`script/load.d/`)

Priority-based naming (lower number = loaded first):

| Module | Purpose |
|--------|---------|
| `100-connetcookies.lua` | ENet SYN cookie DDoS protection |
| `100-extinfo-noip.lua` | Mask player IPs in extinfo |
| `100-geoip.lua` | GeoIP country lookup |
| `500-auth-providers.lua` | Authentication providers |
| `1000-chungus.lua` | Main chungus platform integration |
| `1000-hideandseek.lua` | Hide & Seek mode config |
| `1000-prop-hunt.lua` | Prop Hunt mode config |
| `1000-zombies-server.lua` | Zombie Outbreak config |
| `2000-demorecord.lua` | Demo recording |
| `2000-serverexec.lua` | Interactive Lua shell via Unix socket |
| `2000-stdban.lua` | Advanced banning system |

### Game Modes (`script/gamemods/`)

- `chungus.lua` — Platform integration (verification, stats)
- `prophunt.lua` — Prop Hunt
- `hideandseek.lua` — Hide & Seek
- `zombieoutbreak.lua` — Zombie Outbreak
- `rugby.lua`, `realrugby.lua` — Rugby variants

### Key Standard Library (`script/std/`)

- `auth.lua` — Multi-domain authentication framework
- `intermission.lua` — HTTP webhook at match end
- `uuid.lua` — Client UUID tracking
- `commands.lua` — Custom command registration
- `ban.lua` — Ban management with IP ranges
- `discordrelay.lua` — Discord integration

## Chungus Integration

### Verification Flow
1. Player connects → UUID assigned
2. Chungustrator sends verification codes via ENet → chungusway → game server
3. Player enters `#code <verification_code>`
4. Player mapped to chungid for stats tracking

### Stats Reporting (Intermission)
At intermission, `chungus.lua` builds one roster — connected AND verified players (`chungid ~= ""`) — and derives the whole report from it, so chungusway's expected set always matches the arriving stats. Unverified spectators are skipped (no identity to credit). If the roster is empty, no report is sent. Packets to chungusway (via `CHUNGUS_PEER`):
- `CHUNGUS_PLAYERINFO_ALL` — container ID + roster size + roster chungids
- `CHUNGUS_PLAYERINFO` — per roster entry: chungid, name, frags, deaths, accuracy, ELO
- `CHUNGUS_INTERMISSION` — lifecycle signal with container ID

### Logging
Chungus platform events go through `engine.writelog` and use `[chungusmod][LEVEL] event=<name> key=value...`; the engine supplies the timestamp. `LOG_LEVEL` defaults to `INFO`, with `DEBUG` enabling per-player/code-registration detail. Lifecycle and stats events carry `container_id`, and player events add `chungid` when verification has established it. JWTs, verification codes, and auth response bodies are never logged.

### ENet Protocol Flags (`shared/iengine.h`)
```
0 = CHUNGUS_INTERMISSION
1 = CHUNGUS_PLAYERINFO_ALL
2 = CHUNGUS_PLAYERINFO
3 = CHUNGUS_PLAYERCOUNT
```

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `CHUNGUS` | Enable chungus mode | — |
| `CHUNGUS_PEER_ADDRESS` | Chungusway address | `host.docker.internal` |
| `CHUNGUS_PEER_PORT` | Chungusway ENet port | `30000` |
| `GAME_SERVER_PORT` | Game server port | `28785` |
| `QUERY_SERVICE_URL` | SQC intermission endpoint | `http://localhost:8080/intermission` (SQC shares the container's network namespace) |
| `AUTH_URL` | Auth service endpoint | `http://host.docker.internal:8081/auth` in the image; `http://localhost:8081/auth` in code |
| `ADMIN_NAME`, `ADMIN_DOMAIN`, `ADMIN_PUBLIC_KEY` | Admin auth config | — |

## Docker

The image builds the **local checkout** (`COPY . /app`, see `.dockerignore`) — it used to `git clone` from GitHub, which silently shipped stale upstream code instead of your working tree. Rebuild with `just images` from `chungusroot/` (tags `chungusmod:latest`, which chungustrator spawns per match).

```dockerfile
FROM ubuntu:22.04
# Lua 5.2, luarocks (dkjson, luasocket, struct, uuid, mmdblua)
COPY . /app
RUN make
ENV CHUNGUS=1
CMD ["./sauer_server"]
```

## Performance Notes

- ~13-30 MB memory baseline (jemalloc recommended over glibc)
- 10-15% CPU with 20 players + 60 bots
- GC triggered after map loads
