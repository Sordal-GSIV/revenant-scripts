# revenant-scripts

Default Lua scripts for [Revenant](https://github.com/Sordal-GSIV/revenant) — the Rust+Lua scripting proxy for GemStone IV.

Scripts run in a Lua 5.4 coroutine environment with full access to the Revenant API. Drop any `.lua` file here and launch it with `Script.run("scriptname")`.

## Default scripts

| Script | Purpose |
|--------|---------|
| `autostart.lua` | Launch scripts on login from `CharSettings["autostart"]` |
| `alias.lua` | Command aliases via `CharSettings["aliases"]` |
| `go2.lua` | Navigate to a room by ID or name (requires map data) |
| `vars.lua` | Display CharSettings / UserVars usage help |
| `version.lua` | Print Revenant version info |

## Quick start

```lua
-- In-game, once Revenant is running:
Script.run("vars")       -- see how settings work
Script.run("alias")      -- load your command aliases
Script.run("version")    -- version info
```

Set up auto-start:
```lua
CharSettings["autostart"] = "alias"   -- runs alias.lua on every login
```

## Writing scripts

Scripts are Lua 5.4 coroutines. Any `pause()` or `waitfor()` call yields the coroutine — other scripts and hooks continue running.

```lua
-- example: drink a healing potion when HP < 50%
DownstreamHook.add("auto_heal", function(line)
    if GameState.health < GameState.max_health * 0.5 then
        put("drink my potion")
    end
    return line
end)
```

```lua
-- example: walk to the bank, wait for room, walk back
put("go north")
waitfor("First Bank of Wehnimer")
put("withdraw 500")
pause(2)
put("go out")
```

## API reference

### Commands
| Function | Description |
|----------|-------------|
| `put(cmd)` | Send command to game server (appends `\n`) |
| `fput(cmd)` | Like put, waits for prompt (v0.1: same as put) |
| `pause(secs)` | Sleep for N seconds (yields coroutine) |
| `waitfor(pattern [, timeout])` | Block until pattern appears in game stream |
| `respond(text)` | Echo text to your client |

### Game state
| Field | Type | Description |
|-------|------|-------------|
| `GameState.health` | integer | Current HP |
| `GameState.max_health` | integer | Maximum HP |
| `GameState.mana` | integer | Current mana |
| `GameState.max_mana` | integer | Maximum mana |
| `GameState.spirit` | integer | Current spirit |
| `GameState.stamina` | integer | Current stamina |
| `GameState.bleeding` | boolean | Bleeding status |
| `GameState.stunned` | boolean | Stunned status |
| `GameState.dead` | boolean | Dead status |
| `GameState.room_name` | string | Current room name |
| `GameState.level` | integer | Character level |
| `GameState.roundtime()` | function | Seconds of RT remaining |
| `GameState.cast_roundtime()` | function | Seconds of cast RT remaining |

### Hooks
```lua
-- Downstream: intercept lines from the game server
DownstreamHook.add("name", function(line)
    -- return modified line, or nil to suppress
    return line
end)
DownstreamHook.remove("name")

-- Upstream: intercept commands you send
UpstreamHook.add("name", function(cmd)
    return cmd  -- or return modified command
end)
UpstreamHook.remove("name")
```

### Settings
```lua
-- Per-character, stored in SQLite
CharSettings["key"] = value        -- write (any type coerced to string)
local v = CharSettings["key"]      -- read (returns nil if not set)

-- Game-wide vars
UserVars["threshold"] = "500"
local t = tonumber(UserVars["threshold"])
```

### Script management
```lua
Script.run("scriptname")           -- launch script from scripts dir (TODO: wiring)
Script.kill("scriptname")          -- abort a running script
local list = Script.list()         -- array of running script names
Script.args                        -- args string passed at launch
```

## Setting up aliases (alias.lua)

Store as semicolon-separated `alias=expansion` pairs:

```lua
CharSettings["aliases"] = "e=go east;w=go west;n=go north;s=go south;ht=stow right"
```

Then run `alias.lua` (or add it to autostart) — it registers an upstream hook that expands single-word commands before they reach the server.

## Related

- [revenant](https://github.com/Sordal-GSIV/revenant) — the Rust engine
- [Lich5](https://github.com/lich-developer/lich5) — the Ruby proxy this replaces
