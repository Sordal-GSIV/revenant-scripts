# Lich5 → Revenant API Reference

A human-readable reference mapping Lich5 Ruby API calls to their Revenant Lua equivalents. Organized by category with implementation status.

Legend: **Implemented**, ~~Not Implemented~~

---

## Commands & I/O

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `put "cmd"` | `put("cmd")` | **Implemented** |
| `fput "cmd"` | `fput("cmd")` | **Implemented** |
| `fput "cmd", "waitpat"` | `fput("cmd", "waitpat")` | **Implemented** |
| `multifput "a", "b"` | `multifput("a", "b")` | **Implemented** |
| `respond "text"` | `respond("text")` | **Implemented** |
| `echo "text"` | `echo("text")` | **Implemented** |
| `get` | `get()` | **Implemented** |
| `get?` | `get_noblock()` / `nget()` | **Implemented** |
| `wait` | `wait()` | **Implemented** |
| `clear` | `clear()` | **Implemented** |
| `reget(n)` | `reget(n)` | **Implemented** |
| `waitfor "pat"` | `waitfor("pat")` | **Implemented** |
| `waitfor "pat", timeout` | `waitfor("pat", timeout)` | **Implemented** |
| `waitforre /regex/` | `waitforre("lua_pattern")` | **Implemented** |
| `matchfind "p1", "p2"` | `matchfind("p1", "p2")` | **Implemented** |
| `matchwait "p1", "p2"` | `matchwait("p1", "p2")` | **Implemented** |
| `matchtimeout secs, "p1"` | `matchtimeout(secs, "p1")` | **Implemented** |
| `selectput "cmd", succ, fail` | `selectput("cmd", succ, fail, timeout)` | **Implemented** |
| `_respond "text"` | `respond("text")` | **Implemented** (no distinction) |

## Timing & Roundtime

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `pause secs` / `sleep secs` | `pause(secs)` | **Implemented** (async, pause-aware) |
| `waitrt` / `waitrt?` | `waitrt()` | **Implemented** |
| `waitcastrt` / `waitcastrt?` | `waitcastrt()` | **Implemented** |
| `checkrt` | `checkrt()` | **Implemented** |
| `checkcastrt` | `checkcastrt()` | **Implemented** |
| `roundtime` | `roundtime()` / `GameState.roundtime()` | **Implemented** |
| `cast_roundtime` | `cast_roundtime()` / `GameState.cast_roundtime()` | **Implemented** |
| `wait_until { cond }` | `wait_until(func)` | **Implemented** |
| `wait_while { cond }` | `wait_while(func)` | **Implemented** |

## Movement

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `move "dir"` | `move("dir")` | **Implemented** (RT/stun/web aware) |
| `n`, `s`, `e`, `w`, etc. | `n()`, `s()`, `e()`, `w()`, etc. | **Implemented** |
| `ne`, `se`, `sw`, `nw` | `ne()`, `se()`, `sw()`, `nw()` | **Implemented** |
| `u`, `d`, `out` | `u()`, `d()`, `out()` | **Implemented** |
| `multimove(*dirs)` | `multimove(...)` | **Implemented** |
| `go2("place")` | `Map.go2("place")` | **Implemented** |

## Script Management

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `Script.start("name")` | `Script.run("name")` | **Implemented** |
| `Script.start("name", "args")` | `Script.run("name", "args")` | **Implemented** |
| `Script.kill("name")` | `Script.kill("name")` | **Implemented** |
| `stop_script("name")` | `Script.kill("name")` | **Implemented** |
| `Script.list` / `Script.running` | `Script.list()` | **Implemented** |
| `running?("name")` | `running("name")` / `Script.running("name")` | **Implemented** |
| `Script.exists?("name")` | `Script.exists("name")` | **Implemented** |
| `Script.current.name` | `Script.name` | **Implemented** |
| `Script.current.vars` | `Script.vars` | **Implemented** |
| `before_dying { }` | `before_dying(func)` | **Implemented** |
| `undo_before_dying` | `undo_before_dying()` | **Implemented** |
| `Script.at_exit { }` | `Script.at_exit(func)` | **Implemented** |
| `Script.clear_exit_procs` | `Script.clear_exit_procs()` | **Implemented** |
| `no_kill_all` | `no_kill_all()` | **Implemented** |
| `no_pause_all` | `no_pause_all()` | **Implemented** |
| `pause_script("name")` | `Script.pause("name")` | **Implemented** |
| `unpause_script("name")` | `Script.unpause("name")` | **Implemented** |
| `die_with_me("name")` | `die_with_me("name")` | **Implemented** |
| `send_to_script("name", msg)` | `send_to_script("name", msg)` | **Implemented** |
| `start_script("name")` | `Script.run("name")` | **Implemented** |
| `force_start_script("name")` | `Script.run("name")` | **Implemented** (no force needed) |
| `hide_me` | `hide_me()` | **Implemented** |
| `silence_me` | `silence_me()` | **Implemented** |
| `toggle_echo` / `echo_on` / `echo_off` | `toggle_echo()` / `echo_on()` / `echo_off()` | **Implemented** |
| `toggle_upstream` / `upstream_get` | `toggle_upstream()` / `upstream_get()` | **Implemented** |
| `i_stand_alone` / `toggle_unique` | `i_stand_alone()` / `toggle_unique()` | **Implemented** |
| `unique_get` / `unique_get?` | `unique_get()` / `unique_get_noblock()` | **Implemented** |
| `unique_waitfor` | `unique_waitfor(...)` | **Implemented** |
| `ExecScript.start(code)` | — | ~~Not Applicable~~ |
| `goto "label"` | — | ~~Not Applicable~~ (Lua has no labels) |

## Vitals (GameState)

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `XMLData.health` / `checkhealth` | `GameState.health` / `health()` / `checkhealth(n)` | **Implemented** |
| `XMLData.max_health` / `maxhealth` | `GameState.max_health` / `max_health()` | **Implemented** |
| `XMLData.mana` / `checkmana` | `GameState.mana` / `mana()` / `checkmana(n)` | **Implemented** |
| `XMLData.max_mana` / `maxmana` | `GameState.max_mana` / `max_mana()` | **Implemented** |
| `XMLData.spirit` / `checkspirit` | `GameState.spirit` / `spirit()` / `checkspirit(n)` | **Implemented** |
| `XMLData.max_spirit` / `maxspirit` | `GameState.max_spirit` / `max_spirit()` | **Implemented** |
| `XMLData.stamina` / `checkstamina` | `GameState.stamina` / `stamina()` / `checkstamina(n)` | **Implemented** |
| `XMLData.max_stamina` / `maxstamina` | `GameState.max_stamina` / `max_stamina()` | **Implemented** |
| `XMLData.concentration` | `GameState.concentration` / `concentration()` | **Implemented** |
| `XMLData.max_concentration` / `maxconcentration` | `GameState.max_concentration` / `max_concentration()` | **Implemented** |
| `percenthealth(n)` | `percenthealth(n)` | **Implemented** |
| `percentmana(n)` | `percentmana(n)` | **Implemented** |
| `percentspirit(n)` | `percentspirit(n)` | **Implemented** |
| `percentstamina(n)` | `percentstamina(n)` | **Implemented** |
| `percentconcentration(n)` | `percentconcentration(n)` | **Implemented** |

## Status Checks

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `checkstunned` | `stunned()` / `GameState.stunned` | **Implemented** |
| `checkdead` | `dead()` / `GameState.dead` | **Implemented** |
| `checkbleeding` | `bleeding()` / `GameState.bleeding` | **Implemented** |
| `checksleeping` / `sleeping?` | `sleeping()` / `GameState.sleeping` | **Implemented** |
| `checkprone` | `prone()` / `GameState.prone` | **Implemented** |
| `checksitting` | `sitting()` / `GameState.sitting` | **Implemented** |
| `checkkneeling` | `kneeling()` / `GameState.kneeling` | **Implemented** |
| `checkstanding` | `standing()` / `GameState.standing` | **Implemented** |
| `checkpoison` | `poisoned()` / `GameState.poisoned` | **Implemented** |
| `checkdisease` | `diseased()` / `GameState.diseased` | **Implemented** |
| `checkhidden` | `hidden()` / `GameState.hidden` | **Implemented** |
| `checkinvisible` | `invisible()` / `GameState.invisible` | **Implemented** |
| `checkwebbed` | `webbed()` / `GameState.webbed` | **Implemented** |
| `checkgrouped` | `grouped()` / `joined()` / `GameState.joined` | **Implemented** |
| `checksilenced` / `Status.silenced?` | `silenced()` / `GameState.silenced` | **Implemented** |
| `checkbound` / `bound?` | `bound()` / `GameState.bound` | **Implemented** |
| `Status.calmed?` | `calmed()` / `GameState.calmed` | **Implemented** |
| `Status.cutthroat?` | `cutthroat()` / `GameState.cutthroat` | **Implemented** |
| `checkreallybleeding` | `checkreallybleeding()` | **Implemented** |
| `muckled?` | `muckled()` | **Implemented** |
| `checkfried` / `checksaturated` | `checkfried()` / `checksaturated()` | **Implemented** |
| `checkmind` / `percentmind` | `checkmind(s)` / `percentmind(n)` | **Implemented** |
| `idle?` | `idle_p(secs)` | **Implemented** |

## Room

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `XMLData.room_title` / `checkroom` | `Room.title` / `checkroom(...)` | **Implemented** |
| `XMLData.room_description` / `checkroomdescrip` | `Room.description` / `checkroomdescrip(...)` | **Implemented** |
| `XMLData.room_exits` / `checkpaths` | `Room.exits` / `GameState.room_exits` | **Implemented** |
| `Room.current.id` | `Room.id` / `GameState.room_id` / `Map.current_room()` | **Implemented** |
| `XMLData.room_count` | `Room.count` / `GameState.room_count` | **Implemented** |
| `checkarea` | `checkarea(...)` | **Implemented** |
| `outside?` | `outside()` | **Implemented** |
| `checknotstanding` | `not standing()` | **Implemented** (compose) |

## Char Module

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `Char.name` | `Char.name` | **Implemented** |
| `Char.health` / `Char.max_health` | `Char.health` / `Char.max_health` | **Implemented** |
| `Char.percent_health` | `Char.percent_health` | **Implemented** |
| `Char.mana` / `Char.max_mana` | `Char.mana` / `Char.max_mana` | **Implemented** |
| `Char.percent_mana` | `Char.percent_mana` | **Implemented** |
| `Char.spirit` / `Char.max_spirit` | `Char.spirit` / `Char.max_spirit` | **Implemented** |
| `Char.percent_spirit` | `Char.percent_spirit` | **Implemented** |
| `Char.stamina` / `Char.max_stamina` | `Char.stamina` / `Char.max_stamina` | **Implemented** |
| `Char.percent_stamina` | `Char.percent_stamina` | **Implemented** |
| `Char.stance` | `Char.stance` | **Implemented** |
| `Char.percent_stance` | `Char.stance_value` | **Implemented** |
| `Char.encumbrance` | `Char.encumbrance` | **Implemented** |
| `Char.percent_encumbrance` | `Char.encumbrance_value` | **Implemented** |
| `Char.level` | `Char.level` | **Implemented** |
| `Char.citizenship` | `Char.citizenship` | **Implemented** |
| `Char.che` | `Char.che` | **Implemented** |

## GameObj

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `GameObj.npcs` | `GameObj.npcs()` | **Implemented** |
| `GameObj.loot` | `GameObj.loot()` | **Implemented** |
| `GameObj.pcs` | `GameObj.pcs()` | **Implemented** |
| `GameObj.inv` | `GameObj.inv()` | **Implemented** |
| `GameObj.room_desc` | `GameObj.room_desc()` | **Implemented** |
| `GameObj.right_hand` | `GameObj.right_hand()` | **Implemented** |
| `GameObj.left_hand` | `GameObj.left_hand()` | **Implemented** |
| `GameObj.dead` | `GameObj.dead()` | **Implemented** |
| `GameObj.fam_npcs` | `GameObj.fam_npcs()` | **Implemented** |
| `GameObj.fam_loot` | `GameObj.fam_loot()` | **Implemented** |
| `GameObj.fam_pcs` | `GameObj.fam_pcs()` | **Implemented** |
| `GameObj.fam_room_desc` | `GameObj.fam_room_desc()` | **Implemented** |
| `GameObj["key"]` | `GameObj["key"]` | **Implemented** (ID/noun/name lookup) |
| `obj.id` | `obj.id` | **Implemented** |
| `obj.noun` | `obj.noun` | **Implemented** |
| `obj.name` | `obj.name` | **Implemented** |
| `obj.full_name` | `obj.full_name` | **Implemented** |
| `obj.before_name` | `obj.before_name` | **Implemented** |
| `obj.after_name` | `obj.after_name` | **Implemented** |
| `obj.status` | `obj.status` (read/write) | **Implemented** |
| `obj.contents` | `obj.contents` | **Implemented** |
| `obj.type` | `obj.type` | **Implemented** |
| `obj.type =~ /gem/` | `obj:type_p("gem")` | **Implemented** |
| `obj.sellable` | `obj.sellable` | **Implemented** |
| `checknpcs` | `checknpcs(...)` | **Implemented** |
| `checkloot` | `checkloot()` | **Implemented** |
| `checkright` / `checkleft` | `checkright(...)` / `checkleft(...)` | **Implemented** |
| `checkpcs` | `checkpcs(...)` | **Implemented** |
| `GameObj.new_npc(...)` | — | ~~Not Implemented~~ (managed by engine) |
| `GameObj.clear_*` | — | ~~Not Implemented~~ (managed by engine) |
| `GameObj.type_data` | — | ~~Not Implemented~~ (loaded via data XML) |

## Stats

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `Stats.race` | `Stats.race` | **Implemented** |
| `Stats.profession` / `Stats.prof` | `Stats.profession` / `Stats.prof` | **Implemented** |
| `Stats.gender` | `Stats.gender` | **Implemented** |
| `Stats.age` | `Stats.age` | **Implemented** |
| `Stats.level` | `Stats.level` | **Implemented** |
| `Stats.exp` / `Stats.experience` | `Stats.experience` / `Stats.exp` | **Implemented** |
| `Stats.strength` (→ OpenStruct) | `Stats.strength` (→ table) | **Implemented** |
| `Stats.str` (→ [val, bonus]) | `Stats.str` (→ {[1]=val, [2]=bonus}) | **Implemented** |
| `Stats.base_str` | `Stats.base_str` | **Implemented** |
| `Stats.enhanced_str` | `Stats.enhanced_str` | **Implemented** |
| Same for con/dex/agi/dis/aur/log/int/wis/inf | Same | **Implemented** |

## Skills

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `Skills.edged_weapons` | `Skills.edged_weapons` | **Implemented** (returns ranks) |
| `Skills.edgedweapons` | `Skills.edgedweapons` | **Implemented** (legacy alias) |
| `Skills.to_bonus(ranks)` | `Skills.to_bonus(ranks)` | **Implemented** |
| `Skills.to_bonus(:skill_name)` | `Skills.to_bonus("skill_name")` | **Implemented** |
| All 46 skill names + aliases | All 46 skill names + aliases | **Implemented** |

## Spells (Circle Ranks)

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `Spells.minor_elemental` | `Spells.minor_elemental` | **Implemented** |
| `Spells.minorelemental` | `Spells.minorelemental` | **Implemented** (alias) |
| All 12 circle names + aliases | All 12 circle names + aliases | **Implemented** |
| `Spells.active` | `Spells.active()` | **Implemented** |
| `Spells.known` | `Spells.known()` | **Implemented** |

## Spell (Individual)

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `Spell[101]` | `Spell[101]` | **Implemented** (→ table) |
| `Spell["Spirit Warding I"]` | `Spell["Spirit Warding I"]` | **Implemented** |
| `spell.active?` | `spell.active` | **Implemented** |
| `spell.known?` | `spell.known` | **Implemented** |
| `spell.timeleft` | `spell.timeleft` | **Implemented** (minutes) |
| `spell.secsleft` | `spell.secsleft` | **Implemented** (seconds) |
| `spell.name` | `spell.name` | **Implemented** |
| `spell.num` | `spell.num` | **Implemented** |
| `spell.type` | `spell.type` | **Implemented** |
| `spell.circle` | `spell.circle` | **Implemented** |
| `spell.circle_name` | `spell.circle_name` | **Implemented** |
| `spell.availability` | `spell.availability` | **Implemented** |
| `spell.stackable` | `spell.stackable` | **Implemented** |
| `spell.persist_on_death` | `spell.persist_on_death` | **Implemented** |
| `Spell.active` | `Spell.active()` | **Implemented** |
| `Spell.active_p(num)` | `Spell.active_p(num)` | **Implemented** |
| `Spell.known_p(num)` | `Spell.known_p(num)` | **Implemented** |
| `spell.putup` / `spell.putdown` | `spell:putup()` / `spell:putdown()` | **Implemented** (via `lib/spell_casting`) |
| `spell.cast` / `spell.channel` | `spell:cast(target, opts)` / `spell:channel(target, opts)` | **Implemented** (via `lib/spell_casting`) |
| `spell.cost` / `spell.affordable?` | `spell:cost(opts)` / `spell:affordable(opts)` | **Implemented** (via `lib/spell_casting`) |
| `spell.duration` | `spell:time_per(opts)` / `spell.duration_formula` | **Implemented** |
| `spell.bonus` | `spell.bonus_list` | **Implemented** (bonus type names) |
| `spell.msgup` / `spell.msgdn` | `spell.msgup` / `spell.msgdn` | **Implemented** |
| `spell.stance` / `spell.channel` (attr) | `spell.stance` / `spell.channel` | **Implemented** |
| `Spell.load` | — | ~~Not Needed~~ (auto-loaded) |
| `Spell.after_stance` | `Spell.after_stance` (read/write) | **Implemented** |
| `checkspell(101, 401)` | `checkspell(101, 401)` | **Implemented** |
| `checkprep` / `checkprep("spell")` | `checkprep()` / `checkprep("spell")` | **Implemented** |

## Hooks

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `DownstreamHook.add(name, proc)` | `DownstreamHook.add(name, func)` | **Implemented** |
| `DownstreamHook.remove(name)` | `DownstreamHook.remove(name)` | **Implemented** |
| `DownstreamHook.list` | `DownstreamHook.list()` | **Implemented** |
| `UpstreamHook.add(name, proc)` | `UpstreamHook.add(name, func)` | **Implemented** |
| `UpstreamHook.remove(name)` | `UpstreamHook.remove(name)` | **Implemented** |
| `UpstreamHook.list` | `UpstreamHook.list()` | **Implemented** |
| `Watchfor.new(/pat/) { }` | `Watchfor.new(pattern, func)` | **Implemented** (via `lib/watchfor`) |

## Map / Navigation

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `Room.current.id` | `Map.current_room()` | **Implemented** |
| `Map[id]` / `Room[id]` | `Map.find_room(id)` | **Implemented** |
| `Map.find_room("name")` | `Map.find_room("name")` | **Implemented** |
| `Map.findpath(from, to)` | `Map.find_path(from, to)` | **Implemented** |
| `go2("dest")` | `Map.go2("dest")` | **Implemented** |
| `Map.load("path")` | `Map.load("path")` | **Implemented** |
| `Map.list` | `Map.list()` | **Implemented** |
| `Room.current` (full object) | `Room.current()` | **Implemented** |
| `room.wayto` / `room.timeto` | `room.wayto` / `room.timeto` | **Implemented** |
| `room.tags` | `room.tags` | **Implemented** |
| `Map.tags` | `Map.tags(tag)` | **Implemented** |
| `Map.room_count` | `Map.room_count()` | **Implemented** |
| `Room.find_nearest_by_tag` | `Room.find_nearest_by_tag(tag)` / `Map.find_nearest_by_tag(tag)` | **Implemented** |
| `Room.path_to` | `Room.path_to(dest)` | **Implemented** |
| `Map.get_location` | — | ~~Not Implemented~~ |

## Settings / Persistence

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `CharSettings["key"]` | `CharSettings.key` | **Implemented** (string values) |
| `CharSettings["key"] = val` | `CharSettings.key = val` | **Implemented** |
| `UserVars["key"]` / `UserVars.key` | `UserVars.key` | **Implemented** |
| `Vars["key"]` / `Vars.key` | `Vars["key"]` / `Vars.key` | **Implemented** (via `lib/lich_vars`, JSON-serialized) |
| `Settings["key"]` | `Settings.key` | **Implemented** (global cross-char) |
| `GameSettings["key"]` | `Settings.key` | **Implemented** |

## Wounds / Scars

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| Injury data (via XMLData) | `Wounds.bodypart` / `Scars.bodypart` | **Implemented** |

## Familiar

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `XMLData.familiar_room_title` | `Familiar.room_title` | **Implemented** |
| `XMLData.familiar_room_description` | `Familiar.room_description` | **Implemented** |
| `XMLData.familiar_room_exits` | `Familiar.room_exits` | **Implemented** |
| `checkfamroom` / `checkfamarea` | `checkfamroom(...)` / `checkfamarea(...)` | **Implemented** |
| `checkfamnpcs` / `checkfampcs` | `checkfamnpcs(...)` / `checkfampcs(...)` | **Implemented** |
| `checkfampaths` | `checkfampaths(dir)` | **Implemented** |
| `checkfamroomdescrip` | `checkfamroomdescrip(...)` | **Implemented** |

## Group

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `checkgrouped` | `Group.joined` | **Implemented** |
| `Group.members` | `Group.members` | **Implemented** (via group.lua) |
| `Group.leader` | `Group.leader` | **Implemented** (via group.lua) |

## Bounty / Society

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| `checkbounty` | `checkbounty()` / `Bounty.task` | **Implemented** |
| `XMLData.society_task` | `Society.task` | **Implemented** |

## Utilities (Revenant-only, no Lich5 equivalent)

| Revenant Lua | Description |
|-------------|-------------|
| `Http.get(url)` | HTTP GET → `{status, body, headers}` or nil, error |
| `Http.get_json(url)` | HTTP GET + JSON parse |
| `Json.encode(table)` | Table → JSON string |
| `Json.decode(string)` | JSON string → table |
| `File.read(path)` | Read file (sandboxed to scripts/) |
| `File.write(path, content)` | Write file |
| `File.exists(path)` | File existence check |
| `File.list(path)` | List directory entries |
| `File.mkdir(path)` | Create directory |
| `File.remove(path)` | Delete file or directory |
| `File.is_dir(path)` | Directory check |
| `File.mtime(path)` | Modification time (unix timestamp) |
| `File.replace(src, dst)` | Rename/move file |
| `Crypto.sha256(string)` | SHA-256 hash |
| `Crypto.sha256_file(path)` | SHA-256 of file |
| `Version.parse(str)` | Parse semver string |
| `Version.compare(a, b)` | Compare two versions |
| `Version.satisfies(ver, constraint)` | Check semver constraint |
| `Version.engine_path()` | Engine binary path |

## GUI (Revenant-only, feature: monitor)

| Revenant Lua | Description |
|-------------|-------------|
| `Gui.window(title, opts)` | Create window (width, height, resizable) |
| `window:show()` / `hide()` / `close()` | Window visibility |
| `window:set_title(title)` | Update title |
| `window:set_root(widget)` | Set root widget |
| `window:on_close(func)` | Close callback |
| `Gui.label(text)` | Text label (`:set_text()`) |
| `Gui.button(label)` | Button (`:on_click()`) |
| `Gui.checkbox(label, checked)` | Checkbox (`:set_checked()`, `:get_checked()`, `:on_change()`) |
| `Gui.input(opts)` | Text input (`:set_text()`, `:get_text()`, `:on_change()`, `:on_submit()`) |
| `Gui.progress(value)` | Progress bar 0.0-1.0 (`:set_value()`) |
| `Gui.separator()` | Visual divider |
| `Gui.table(opts)` | Data table (`:add_row()`, `:clear()`) |
| `Gui.vbox()` / `Gui.hbox()` | Layout containers (`:add()`) |
| `Gui.scroll(child)` | Scrollable wrapper |
| `Gui.map_view(opts)` | Map widget (`:load_image()`, `:set_marker()`, `:center_on()`, etc.) |
| `Gui.wait(target, event)` | Async event wait (events: "close", "click", "change", "submit") |

## Remaining: Not Yet Implemented

Features from Lich5 that have **no Revenant equivalent**:

### Out of Scope (deferred)
- **Enhancive module** — equipment enhancive tracking. Low usage in community scripts.
- **Spellsong module** — bard spellsong tracking. Bard-specific, low priority.
- **Map.get_location** — location-based room lookup. Requires location data infrastructure.
- **ExecScript / WizardScript / goto/labels** — not applicable to Lua runtime.
- **fetchloot / take helpers** — trivial to write in Lua; not engine-level features.
- **GameObj.new_npc / GameObj.clear_*** — internal engine operations, not script-facing.

### Low Priority (deprecated or rarely used)
- `Lich.log` — log file writing
- `walk` / `run` — random movement
- `survivepoison?` / `survivedie?` — deprecated checks
- `debug` — conditional echo
- `setpriority` — thread priority
- `timetest` — benchmarking
- `dec2bin` / `bin2dec` — binary conversion
