# revenant-scripts

Default Lua scripts for [Revenant](https://github.com/Sordal-GSIV/revenant).

## Scripts

| Script | Description |
|--------|-------------|
| `go2.lua` | Navigate to any room by ID or name |
| `autostart.lua` | Auto-launch scripts on login |
| `alias.lua` | Command aliases via upstream hooks |
| `vars.lua` | Variable management |

## API surface

- `put(cmd)` / `fput(cmd)` — send commands to server
- `waitfor(text [, timeout])` / `wait_until(fn)` — block until text/condition
- `pause(seconds)` — sleep
- `respond(text)` — echo to client only
- `GameState` — HP, mana, room, roundtime, etc.
- `GameObj` — items, NPCs, players in room
- `DownstreamHook.add(name, fn)` / `UpstreamHook.add(name, fn)`
- `CharSettings["key"]` / `UserVars.key` — persistent storage
- `Script.run(name)` / `Script.kill(name)` / `Script.args`
