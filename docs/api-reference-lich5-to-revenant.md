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
| `fetchloot` | `fetchloot()` | **Implemented** (compat shim in builtins) |
| `take` | `take()` | **Implemented** (compat shim in builtins) |
| `respond_to_window(win, text)` | `respond_to_window(win, text)` | **Implemented** |
| `xml_encode(text)` | `xml_encode(text)` | **Implemented** |
| `parse_list(text)` | `parse_list(text)` | **Implemented** |
| `arrival_pcs()` | `arrival_pcs()` | **Implemented** |
| `_CLIENT_BUFFER` | `_CLIENT_BUFFER` | **Implemented** |

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
| `Script.start("name")` | `Script.run("name")` / `Script.start("name")` | **Implemented** (`start` is alias for `run`) |
| `Script.start("name", "args")` | `Script.run("name", "args")` | **Implemented** |
| `Script.kill("name")` | `Script.kill("name")` | **Implemented** |
| `stop_script("name")` | `Script.kill("name")` | **Implemented** |
| `Script.list` / `Script.running` | `Script.list()` | **Implemented** |
| `running?("name")` | `running("name")` / `Script.running("name")` | **Implemented** |
| `Script.exists?("name")` | `Script.exists("name")` | **Implemented** |
| `Script.current.name` | `Script.name` | **Implemented** |
| `Script.current.vars` | `Script.vars` | **Implemented** |
| `Script.current` | `Script.current()` | **Implemented** (returns `{name, paused}`) |
| `before_dying { }` | `before_dying(func)` | **Implemented** |
| `undo_before_dying` | `undo_before_dying()` | **Implemented** |
| `Script.at_exit { }` | `Script.at_exit(func)` | **Implemented** |
| `Script.clear_exit_procs` | `Script.clear_exit_procs()` | **Implemented** |
| `no_kill_all` | `no_kill_all()` | **Implemented** |
| `no_pause_all` | `no_pause_all()` | **Implemented** |
| `pause_script("name")` | `Script.pause("name")` | **Implemented** |
| `unpause_script("name")` | `Script.unpause("name")` | **Implemented** |
| — | `Script.pause_all()` | **Implemented** |
| — | `Script.unpause_all()` | **Implemented** |
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
| `survivepoison?` | `survivepoison()` | **Implemented** (compat shim in builtins) |
| `survivedisease?` | `survivedisease()` | **Implemented** (compat shim in builtins) |
| `dec2bin(n)` | `dec2bin(n)` | **Implemented** (compat shim in builtins) |
| `bin2dec(s)` | `bin2dec(s)` | **Implemented** (compat shim in builtins) |

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
| — | `GameObj.targets()` | **Implemented** (alive NPCs) |
| — | `GameObj.target()` | **Implemented** (first alive NPC) |
| — | `GameObj.hidden_targets()` | **Implemented** (hidden NPCs) |
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
| — | `DownstreamHook.sources()` | **Implemented** (list hook sources) |
| `UpstreamHook.add(name, proc)` | `UpstreamHook.add(name, func)` | **Implemented** |
| `UpstreamHook.remove(name)` | `UpstreamHook.remove(name)` | **Implemented** |
| `UpstreamHook.list` | `UpstreamHook.list()` | **Implemented** |
| — | `UpstreamHook.sources()` | **Implemented** (list hook sources) |

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
| — | `SessionVars.key = val` | **Implemented** (ephemeral, lost on disconnect) |

## Wounds / Scars / Injuries

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| Injury data (via XMLData) | `Wounds.bodypart` / `Scars.bodypart` | **Implemented** |
| — | `Injured.head`, `.neck`, etc. | **Implemented** (true if wound OR scar > 0) |

## GameState (Additional Fields)

| Lich5 Ruby | Revenant Lua | Status |
|-----------|-------------|--------|
| — | `GameState.login_time` | **Implemented** |
| — | `GameState.last_pulse` | **Implemented** |
| — | `GameState.wound_gsl` | **Implemented** |
| — | `GameState.scar_gsl` | **Implemented** |
| — | `GameState.stow_container_id` | **Implemented** |

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

## Direction Constants

| Revenant Lua | Description |
|-------------|-------------|
| `SHORTDIR` | Short direction names table (e.g., "n", "s", "e", "w") |
| `LONGDIR` | Long direction names table (e.g., "north", "south") |
| `DIRMAP` | Mapping between short and long direction names |
| `MINDMAP` | Mind state mapping constants |
| `ICONMAP` | Icon name mapping constants |

---

## GS-Specific Modules

These modules are auto-loaded as globals when the game is GemStone IV. Source files live in `lib/gs/`.

### Currency (`lib/gs/currency.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Currency.silver` | Current silver |
| `Currency.bloodscrip` | Bloodscrip count |
| Plus 11 additional currency types (13 total) | All tracked via infomon |

### SpellRanks (`lib/gs/spellranks.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `SpellRanks.minorspiritual` | Minor Spiritual spell ranks |
| `SpellRanks.majorspiritual` | Major Spiritual spell ranks |
| Same for all circles | All circle rank lookups |

### Experience (`lib/gs/experience.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Experience.fame` | Current fame |
| `Experience.total` | Total experience |
| Additional experience fields | All XP-related data |

### Creature (`lib/gs/creature.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Creature.find(name)` | Find creature by name |
| `Creature.new(gameobj)` | Create Creature from a GameObj |

### PSM Modules (`lib/gs/psm.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `CMan.known_p(name)` | Check if combat maneuver is known |
| `Feat.known_p(name)` | Check if feat is known |
| Additional PSM lookups | Shield, Armor, etc. |

### CombatTracker (`lib/gs/combat_tracker.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `CombatTracker.enable()` | Enable combat tracking |
| `CombatTracker.on_death(cb)` | Register death callback |

### Claim (`lib/gs/claim.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Claim.claim_room()` | Claim the current room |
| `Claim.mine()` | Your claim data |
| `Claim.others()` | Other claims in room |

### Overwatch (`lib/gs/overwatch.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Overwatch.enable()` | Enable overwatch tracking |
| `Overwatch.hiders()` | List of detected hidden entities |

### SK (`lib/gs/sk.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `SK.known()` | List of known SKs |
| `SK.add()` | Add to SK list |
| `SK.remove()` | Remove from SK list |

### Gift (`lib/gs/gift.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Gift.started()` | Whether gift is active |
| `Gift.pulse()` | Current gift pulse |
| `Gift.remaining()` | Remaining gift time |

### Enhancive (`lib/gs/enhancive.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Enhancive.refresh()` | Refresh enhancive data |
| `Enhancive.strength` | Enhancive strength bonus |
| Additional stat bonuses | All enhancive stat fields |

### Spellsong (`lib/gs/spellsong.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Spellsong` global | Bard spellsong tracking |

### ReadyList (`lib/gs/readylist.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `ReadyList.check()` | Check readied items |
| `ReadyList.shield` | Currently readied shield |
| `ReadyList.weapon` | Currently readied weapon |
| Additional slots | All readied equipment slots |

### StowList (`lib/gs/stowlist.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `StowList.check()` | Check stow targets |
| `StowList.box` | Box stow container |
| `StowList.gem` | Gem stow container |
| Additional stow types | All stow target types |

### Armaments (`lib/gs/armaments.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Armaments.find(name)` | Find armament by name |
| `Armaments.type_for(name)` | Get weapon type for a name |

### CritRanks (`lib/gs/critranks.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `CritRanks.parse(line)` | Parse a crit result line |
| `CritRanks.fetch(type, loc, rank)` | Fetch crit data by type/location/rank |

### Disk (`lib/gs/disk.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Disk.active()` | Whether disk is active |
| `Disk.noun()` | Disk noun |

### Cluster (`lib/gs/cluster.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Cluster.add()` | Add to cluster |
| `Cluster.members()` | List cluster members |
| `Cluster.is_member()` | Check cluster membership |

### Stash (`lib/gs/stash.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Stash.stash()` | Stash current item |
| `Stash.retrieve()` | Retrieve from stash |
| `Stash.stash_loot()` | Stash all loot |

---

## DR-Specific Modules

These modules are auto-loaded as globals when the game is DragonRealms. Source files live in `lib/dr/`.

### DRSkill (`lib/dr/skills.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `DRSkill.getrank(name)` | Get skill rank by name (e.g., `"Augmentation"`) |
| `DRSkill.getpercent(name)` | Get skill learning percent |
| `DRSkill.getlearning(name)` | Get skill learning rate string |

### DRStats (`lib/dr/stats.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `DRStats.race` | Character race |
| `DRStats.guild` | Character guild |
| `DRStats.strength` | Strength stat |
| Additional stats | All DR character stats |

### DRSpells (`lib/dr/spells.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `DRSpells.known_spells_list()` | List of known spells |
| `DRSpells.known_p(name)` | Check if spell is known |

### DRBanking (`lib/dr/banking.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `DRBanking.balance(currency)` | Check balance for a currency |
| `DRBanking.balances()` | All bank balances |

### DRRoom (`lib/dr/room.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `DRRoom.npcs` | NPCs in room |
| `DRRoom.pcs` | PCs in room |
| `DRRoom.dead_npcs` | Dead NPCs in room |

### DRExpMon (`lib/dr/expmonitor.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `DRExpMon.start()` | Start experience monitoring |
| `DRExpMon.stop()` | Stop experience monitoring |
| `DRExpMon.report()` | Get experience report |

### DR Commons

Helper modules that mirror the Lich5 DR community script commons. All auto-loaded as globals.

| Revenant Lua | Source | Description |
|-------------|--------|-------------|
| `DRC.bput()` | `lib/dr/common.lua` | Send command and wait for pattern |
| `DRCT.walk_to()` | `lib/dr/common_travel.lua` | Navigate to a room |
| `DRCM.check_wealth()` | `lib/dr/common_money.lua` | Check current wealth |
| `DRCI.get_item()` | `lib/dr/common_items.lua` | Get an item from container |
| `DRCH.check_health()` | `lib/dr/common_healing.lua` | Check health status |
| `DRCC.get_crafting_item()` | `lib/dr/common_crafting.lua` | Get a crafting item |
| `DRCA.cast()` | `lib/dr/common_arcana.lua` | Cast a spell |
| `DRCMM.visible_moons()` | `lib/dr/common_moonmage.lua` | Check visible moons |
| `DRCTH.commune_sense()` | `lib/dr/common_theurgy.lua` | Theurgy commune sense |
| `DRCS.summon_weapon()` | `lib/dr/common_summoning.lua` | Summon a weapon |
| `DRCEV.assert_exists()` | `lib/dr/common_validation.lua` | Assert setting exists |
| `DREMgr.wear_equipment_set()` | `lib/dr/equip_manager.lua` | Wear an equipment set |

---

## Game-Agnostic Modules

These modules work in both GemStone IV and DragonRealms. Source files live in `lib/`.

### Flags (`lib/flags.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Flags.add(key, ...)` | Register a flag with match patterns |
| `Flags[key]` | Check if flag has been triggered (truthy/falsy) |

### Watchfor (`lib/watchfor.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Watchfor.new(pattern, func)` | Register a pattern watcher with callback |
| `Watchfor.clear()` | Clear all watchers |

### Messaging (`lib/messaging.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Messaging.msg(type, text)` | Send typed message to client |
| `Messaging.monsterbold()` | Monster-bold formatted text |
| `Messaging.mono()` | Monospace formatted text |

### Webhooks (`lib/webhooks.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Webhooks.add()` | Register a webhook |
| `Webhooks.send()` | Send a webhook |
| `Webhooks.notify()` | Send notification via webhook |
| `Webhooks.on()` | Register webhook event handler |

### Watchable (`lib/watchable.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `Watchable.watch(key, cb)` | Watch a key for changes |
| `Watchable.check()` | Check watched values |

### FrontendFocus (`lib/frontend_focus.lua`)

| Revenant Lua | Description |
|-------------|-------------|
| `FrontendFocus.refocus()` | Refocus the frontend window |

### Frontend

| Revenant Lua | Description |
|-------------|-------------|
| `Frontend.name()` | Name of connected frontend |
| `Frontend.supports_xml()` | Whether frontend supports XML |

---

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
| `Crypto.md5(string)` | MD5 hash (hex) |
| `Crypto.sha256(string)` | SHA-256 hash |
| `Crypto.sha256_file(path)` | SHA-256 of file |
| `Version.parse(str)` | Parse semver string |
| `Version.compare(a, b)` | Compare two versions |
| `Version.satisfies(ver, constraint)` | Check semver constraint |
| `Version.engine_path()` | Engine binary path |

## GUI (Revenant-only, feature: monitor)

### Windows

| Revenant Lua | Description |
|-------------|-------------|
| `Gui.window(title, opts)` | Create window (`width`, `height`, `resizable`) |
| `window:show()` / `hide()` / `close()` | Window visibility |
| `window:set_title(title)` | Update title |
| `window:set_root(widget)` | Set root widget (entry point for layout) |
| `window:on_close(func)` | Close callback |

### Basic Widgets

| Revenant Lua | Description |
|-------------|-------------|
| `Gui.label(text)` | Text label (`:set_text()`) |
| `Gui.button(label)` | Button (`:set_text()`, `:on_click()`) |
| `Gui.checkbox(label, checked)` | Checkbox (`:set_checked()`, `:get_checked()`, `:on_change()`) |
| `Gui.input(opts)` | Text input with `placeholder`, `text` (`:set_text()`, `:get_text()`, `:on_change()`, `:on_submit()`) |
| `Gui.progress(value)` | Progress bar 0.0-1.0 (`:set_value()`) |
| `Gui.separator()` | Visual divider |
| `Gui.section_header(text)` | Styled section header |
| `Gui.metric(label, value, opts)` | Metric display with optional `unit`, `trend` (f32), `icon` (char) |
| `Gui.table(opts)` | Data table with `columns` array (`:add_row(cells)`, `:clear()`) |

### Layout Containers

| Revenant Lua | Description |
|-------------|-------------|
| `Gui.vbox()` / `Gui.hbox()` | Vertical/horizontal layout (`:add(child)`) |
| `Gui.scroll(child)` | Scrollable wrapper |
| `Gui.card(opts)` | Card container with optional `title` (`:add(child)`) |
| `Gui.split_view(opts)` | Resizable split pane -- `direction` ("horizontal"/"vertical"), `fraction`, `min`, `max` (`:set_first(w)`, `:set_second(w)`) |

### Advanced Widgets

| Revenant Lua | Description |
|-------------|-------------|
| `Gui.badge(text, opts)` | Badge/tag -- `color` ("success"/"error"/"warning"/"info"/"accent"), `outlined` (`:on_click()`) |
| `Gui.toggle(label, checked)` | Toggle switch (`:set_checked()`, `:get_checked()`, `:on_change()`) |
| `Gui.tab_bar(tabs)` | Tab bar from array of names (`:set_tab_content(index, widget)`, `:on_change()`) |
| `Gui.side_tab_bar(tabs, opts)` | Side-oriented tab bar -- optional `tab_width` (`:set_tab_content(index, widget)`, `:on_change()`) |
| `Gui.editable_combo(opts)` | Editable dropdown -- `text`, `hint`, `options` array (`:get_text()`, `:set_text()`, `:set_options()`, `:on_change()`) |
| `Gui.password_meter()` | Password strength meter (`:set_password(str)`) -- built-in strength rules |
| `Gui.tree_view(opts)` | Tree view -- `columns` (array of `{label, width, sortable}`), `rows` (recursive `{cells, children, expanded}`) (`:set_rows()`, `:get_selected()`, `:on_click()`, `:on_double_click()`) |

### Map Widget

| Revenant Lua | Description |
|-------------|-------------|
| `Gui.map_view(opts)` | Map display -- `width`, `height` (`:load_image(path)`, `:set_marker(room_id, opts)`, `:clear_markers()`, `:set_scale(f)`, `:set_scroll_offset(x,y)`, `:center_on(room_id)`, `:on_click()`) |

### Theming & Events

| Revenant Lua | Description |
|-------------|-------------|
| `Gui.palette()` | Returns current theme colors: `base`, `panel`, `surface`, `elevated`, `accent`, `accent_hover`, `success`, `error`, `warning`, `info`, `text_primary`, `text_secondary`, `text_muted`, `border`, `border_subtle` -- each `{r, g, b, a}` |
| `Gui.wait(target, event)` | Async event wait -- events: `"close"`, `"click"`, `"change"`, `"submit"` |

## Remaining: Not Yet Implemented

Features from Lich5 that have **no Revenant equivalent**:

### Out of Scope (deferred)
- **Map.get_location** -- location-based room lookup. Requires location data infrastructure.
- **ExecScript / WizardScript / goto/labels** -- not applicable to Lua runtime.
- **GameObj.new_npc / GameObj.clear_*** -- internal engine operations, not script-facing.

### Low Priority (deprecated or rarely used)
- `Lich.log` -- log file writing
- `walk` / `run` -- random movement
- `debug` -- conditional echo
- `setpriority` -- thread priority
- `timetest` -- benchmarking
