# Lich5 .lic → Revenant .lua Conversion Guide

This document is for AI/LLM ingestion when converting Lich5 Ruby scripts (.lic) to Revenant Lua scripts (.lua). It provides exact API mappings, pattern translations, and semantic differences.

## Core Philosophy Differences

| Aspect | Lich5 (Ruby) | Revenant (Lua) |
|--------|-------------|----------------|
| Runtime | Ruby threads with shared global state | Lua coroutines on tokio async runtime |
| Game lines | `get` returns stripped text from per-thread buffer | `get()` returns stripped text from per-script MPSC channel |
| Hooks | Procs that return modified string (or nil to squelch) | Lua functions registered by name |
| Settings | `Settings[]`, `CharSettings[]`, `Vars[]`, `UserVars[]` | `Settings.key`, `CharSettings.key`, `UserVars.key` (metatable-based) |
| Error model | Exceptions (begin/rescue/ensure) | pcall/xpcall |
| Regex | Ruby Regexp (`=~`, `.match`, `Regexp.new`) | Lua patterns (`string.find`, `string.match`) or PCRE via future lib |
| Nil semantics | `nil` is falsy; `false` is also falsy | `nil` is falsy; `false` is also falsy (same) |
| String interpolation | `"hello #{name}"` | `"hello " .. name` or `string.format("hello %s", name)` |

---

## 1. Global Functions

### Sending Commands

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `put "cmd"` | `put("cmd")` | Sends command to game server |
| `fput "cmd"` | `fput("cmd")` | Send + wait for prompt (RT/stun aware) |
| `fput "cmd", "pattern"` | `fput("cmd", "pattern")` | Send + wait for pattern match (retries on prompt without match) |
| `multifput("cmd1", "cmd2")` | `multifput("cmd1", "cmd2")` | Sequential fput calls |

### Reading Game Output

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `get` | `get()` | Block until next game line |
| `get?` | `get_noblock()` or `nget()` | Non-blocking; returns nil if no line |
| `wait` | `wait()` | `clear() + get()` |
| `clear` | `clear()` | Drain line buffer, return all pending lines |
| `reget(n)` | `reget(n)` | Last N lines from game log |

### Output to Client

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `respond "text"` | `respond("text")` | Echo text to client window |
| `echo "text"` | `echo("text")` | Echo with `[scriptname]:` prefix |
| `_respond "text"` | `respond("text")` | No distinction in Revenant |

### Pattern Matching / Waiting

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `waitfor "pattern"` | `waitfor("pattern")` | Block until pattern in downstream |
| `waitfor "pattern", timeout` | `waitfor("pattern", timeout)` | With timeout |
| `waitforre /regex/` | `waitforre("lua_pattern")` | Wait for Lua pattern match; returns line + captures table |
| `matchfind "pat1", "pat2"` | `matchfind("pat1", "pat2")` | Search last 100 lines for patterns |
| `matchwait "pat1", "pat2"` | `matchwait("pat1", "pat2")` | Block until any pattern matches |
| `matchtimeout secs, "p1", "p2"` | `matchtimeout(secs, "p1", "p2")` | matchwait with timeout |

### Roundtime

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `waitrt` | `waitrt()` | Sleep until roundtime expires |
| `waitrt?` | `waitrt()` | Same behavior |
| `waitcastrt` | `waitcastrt()` | Sleep until cast roundtime expires |
| `checkrt` | `checkrt()` | Returns remaining RT seconds |
| `checkcastrt` | `checkcastrt()` | Returns remaining cast RT seconds |

### Movement

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `move "north"` | `move("north")` | RT/stun aware movement with retry |
| `n` / `s` / `e` / `w` / etc. | `n()` / `s()` / `e()` / `w()` / etc. | Direction shortcuts (call `move()`) |
| `ne` / `se` / `sw` / `nw` | `ne()` / `se()` / `sw()` / `nw()` | Diagonal shortcuts |
| `u` / `d` / `out` | `u()` / `d()` / `out()` | Up/down/out |
| `multimove("n","e","n")` | Sequential `move()` calls | Not a built-in; use a loop |

### Flow Control

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `pause secs` | `pause(secs)` | Async sleep (pause-aware) |
| `pause_script "name"` | `Script.pause("name")` | Pause a running script |
| `unpause_script "name"` | `Script.unpause("name")` | Unpause a script |
| `wait_until { condition }` | `wait_until(function() return condition end)` | Poll until truthy |
| `wait_while { condition }` | `wait_while(function() return condition end)` | Poll while truthy |
| `sleep secs` | `pause(secs)` | Ruby `sleep` → Lua `pause` |

### Script Lifecycle

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `Script.start("name")` | `Script.run("name")` | Launch a script |
| `Script.start("name", "args")` | `Script.run("name", "args")` | Launch with args string |
| `stop_script("name")` / `Script.kill("name")` | `Script.kill("name")` | Kill a script |
| `Script.list` | `Script.list()` | List running scripts (returns table) |
| `Script.running` | `Script.list()` | Same as list |
| `running?("name")` | `running("name")` or `Script.running("name")` | Check if script is running |
| `Script.current.name` | `Script.name` | Current script name |
| `Script.current.vars` | `Script.vars` | Current script args table |
| `script.vars[0]` | `Script.vars[0]` | Full args string |
| `script.vars[1]` | `Script.vars[1]` | First whitespace-split arg |
| `before_dying { code }` | `before_dying(function() code end)` | Register at-exit hook |
| `undo_before_dying` | `undo_before_dying()` | Clear at-exit hooks |
| `Script.at_exit { code }` | `Script.at_exit(function() code end)` | Alias for before_dying |
| `Script.clear_exit_procs` | `Script.clear_exit_procs()` | Alias for undo_before_dying |
| `Script.exists?("name")` | `Script.exists("name")` | Check if script file exists |
| `no_kill_all` | `no_kill_all()` | Toggle kill protection |
| `no_pause_all` | `no_pause_all()` | Toggle pause protection |
| `die_with_me("name")` | `die_with_me("name")` | Kill target when this script dies |

---

## 2. Game State (XMLData → GameState)

In Lich5, game state is accessed via `XMLData.field_name`. In Revenant, use `GameState.field_name`.

### Vitals

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `XMLData.health` | `GameState.health` | Also: `health()` global alias |
| `XMLData.max_health` | `GameState.max_health` | Also: `max_health()` |
| `XMLData.mana` | `GameState.mana` | Also: `mana()` |
| `XMLData.max_mana` | `GameState.max_mana` | Also: `max_mana()` |
| `XMLData.spirit` | `GameState.spirit` | Also: `spirit()` |
| `XMLData.max_spirit` | `GameState.max_spirit` | Also: `max_spirit()` |
| `XMLData.stamina` | `GameState.stamina` | Also: `stamina()` |
| `XMLData.max_stamina` | `GameState.max_stamina` | Also: `max_stamina()` |
| `XMLData.concentration` | `GameState.concentration` | Also: `concentration()` |
| `XMLData.max_concentration` | `GameState.max_concentration` | Also: `max_concentration()` |

### Status Booleans

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `checkstunned` | `GameState.stunned` or `stunned()` | |
| `checkdead` | `GameState.dead` or `dead()` | |
| `checkbleeding` | `GameState.bleeding` or `bleeding()` | |
| `checksleeping` / `sleeping?` | `GameState.sleeping` or `sleeping()` | |
| `checkprone` | `GameState.prone` or `prone()` | |
| `checksitting` | `GameState.sitting` or `sitting()` | |
| `checkkneeling` | `GameState.kneeling` or `kneeling()` | |
| `checkstanding` | `GameState.standing` or `standing()` | |
| `checkpoison` | `GameState.poisoned` or `poisoned()` | |
| `checkdisease` | `GameState.diseased` or `diseased()` | |
| `checkhidden` | `GameState.hidden` or `hidden()` | |
| `checkinvisible` | `GameState.invisible` or `invisible()` | |
| `checkwebbed` | `GameState.webbed` or `webbed()` | |
| `checkgrouped` | `GameState.joined` or `joined()` or `grouped()` | |
| `Status.calmed?` | `GameState.calmed` or `calmed()` | |
| `Status.cutthroat?` | `GameState.cutthroat` or `cutthroat()` | |
| `Status.silenced?` / `checksilenced` | `GameState.silenced` or `silenced()` | |
| `checkbound` / `bound?` | `GameState.bound` or `bound()` | |

### Room Info

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `XMLData.room_title` / `checkroom` | `GameState.room_name` or `Room.title` or `room_name()` | |
| `XMLData.room_description` / `checkroomdescrip` | `GameState.room_description` or `Room.description` or `room_description()` | |
| `XMLData.room_exits` / `checkpaths` | `GameState.room_exits` or `Room.exits` | Returns Lua table |
| `XMLData.room_count` | `GameState.room_count` or `Room.count` | |
| `Room.current.id` | `GameState.room_id` or `Room.id` | nil if unknown |

### Other State

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `XMLData.prepared_spell` / `checkprep` | `GameState.prepared_spell` | nil if none |
| `Spell.active` | `GameState.active_spells` or `Spell.active()` | Table of active spells |
| `XMLData.stance_text` / `checkstance` | `GameState.stance` | String or nil |
| `XMLData.stance_value` / `percentstance` | `GameState.stance_value` | Integer or nil |
| `XMLData.mind_text` / `checkmind` | `GameState.mind` | String |
| `XMLData.mind_value` / `percentmind` | `GameState.mind_value` | Integer |
| `XMLData.encumbrance_text` / `checkencumbrance` | `GameState.encumbrance` | String |
| `XMLData.encumbrance_value` / `percentencumbrance` | `GameState.encumbrance_value` | Integer |
| `XMLData.server_time` | `GameState.server_time` | Unix timestamp |
| `XMLData.name` / `checkname` | `GameState.name` | Character name |
| `XMLData.game` | `GameState.game` | Game code (e.g., "GS3") |
| `XMLData.level` | `GameState.level` | Character level |
| `XMLData.bounty_task` / `checkbounty` | `Bounty.task` | Bounty task string |
| `XMLData.society_task` | `Society.task` | Society task string |

### Wounds and Scars

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `Wounds["head"]` (via XMLData injuries) | `Wounds.head` | 0-3 severity (metatable lookup) |
| `Scars["head"]` (via XMLData injuries) | `Scars.head` | 0-3 severity |
| Body parts: `head`, `neck`, `chest`, `abdomen`, `back`, `leftArm`, `rightArm`, `leftHand`, `rightHand`, `leftLeg`, `rightLeg`, `leftFoot`, `rightFoot`, `leftEye`, `rightEye`, `nsys` | Same keys | |

---

## 3. GameObj

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `GameObj.npcs` | `GameObj.npcs()` | Returns table of LuaGameObj userdata |
| `GameObj.loot` | `GameObj.loot()` | |
| `GameObj.pcs` | `GameObj.pcs()` | |
| `GameObj.inv` | `GameObj.inv()` | |
| `GameObj.room_desc` | `GameObj.room_desc()` | |
| `GameObj.right_hand` | `GameObj.right_hand()` | Returns single LuaGameObj or nil |
| `GameObj.left_hand` | `GameObj.left_hand()` | |
| `GameObj.dead` | `GameObj.dead()` | Dead NPCs only |
| `GameObj.fam_npcs` | `GameObj.fam_npcs()` | Familiar window objects |
| `GameObj.fam_loot` | `GameObj.fam_loot()` | |
| `GameObj.fam_pcs` | `GameObj.fam_pcs()` | |
| `GameObj.fam_room_desc` | `GameObj.fam_room_desc()` | |
| `GameObj["sword"]` | `GameObj["sword"]` | Lookup by ID/noun/name substring |
| `obj.id` | `obj.id` | String ID |
| `obj.noun` | `obj.noun` | Noun (e.g., "goblin") |
| `obj.name` | `obj.name` | Full name |
| `obj.full_name` | `obj.full_name` | before_name + name + after_name |
| `obj.status` | `obj.status` | Live status string (read/write) |
| `obj.contents` | `obj.contents` | Table of contained items or nil |
| `obj.type` | `obj.type` | Type classification or nil |
| `obj.type =~ /gem/` | `obj:type_p("gem")` | Type predicate check |
| `obj.sellable` | `obj.sellable` | Sellable classification or nil |

### Common check* → GameObj Conversions

| Lich5 Ruby | Revenant Lua |
|-----------|-------------|
| `checknpcs` | `local npcs = GameObj.npcs(); if #npcs > 0 then ... end` |
| `checknpcs("troll")` | See pattern below |
| `checkloot` | `local loot = GameObj.loot()` |
| `checkright` | `local rh = GameObj.right_hand(); if rh then rh.noun end` |
| `checkleft` | `local lh = GameObj.left_hand(); if lh then lh.noun end` |
| `righthand?` | `GameObj.right_hand() ~= nil` |
| `lefthand?` | `GameObj.left_hand() ~= nil` |

#### Pattern: checknpcs with filter
```ruby
# Ruby
if checknpcs("troll", "goblin")
  target = GameObj.npcs.find { |n| n.noun =~ /troll|goblin/ }
```
```lua
-- Lua
local npcs = GameObj.npcs()
local target = nil
for _, npc in ipairs(npcs) do
    if npc.noun:match("troll") or npc.noun:match("goblin") then
        target = npc
        break
    end
end
```

---

## 4. Char Module

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `Char.health` | `Char.health` | Same as GameState.health |
| `Char.max_health` | `Char.max_health` | |
| `Char.percent_health` | `Char.percent_health` | Computed percentage |
| `Char.mana` | `Char.mana` | |
| `Char.max_mana` | `Char.max_mana` | |
| `Char.percent_mana` | `Char.percent_mana` | |
| `Char.spirit` | `Char.spirit` | |
| `Char.max_spirit` | `Char.max_spirit` | |
| `Char.percent_spirit` | `Char.percent_spirit` | |
| `Char.stamina` | `Char.stamina` | |
| `Char.max_stamina` | `Char.max_stamina` | |
| `Char.percent_stamina` | `Char.percent_stamina` | |
| `Char.stance` | `Char.stance` | String |
| `Char.percent_stance` | `Char.stance_value` | Integer |
| `Char.encumbrance` | `Char.encumbrance` | String |
| `Char.percent_encumbrance` | `Char.encumbrance_value` | Integer |
| `Char.name` | `Char.name` | |
| `Char.level` | `Char.level` | |

---

## 5. Stats

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `Stats.race` | `Stats.race` | |
| `Stats.profession` / `Stats.prof` | `Stats.profession` / `Stats.prof` | |
| `Stats.gender` | `Stats.gender` | |
| `Stats.age` | `Stats.age` | |
| `Stats.level` | `Stats.level` | |
| `Stats.exp` / `Stats.experience` | `Stats.experience` / `Stats.exp` | |
| `Stats.strength` | `Stats.strength` | Returns table: `{value, bonus, base={value,bonus}, enhanced={value,bonus}}` |
| `Stats.str` | `Stats.str` | Returns `{value, bonus}` (1-indexed) |
| `Stats.base_str` | `Stats.base_str` | Returns `{value, bonus}` |
| `Stats.enhanced_str` | `Stats.enhanced_str` | Returns `{value, bonus}` |
| Same pattern for: `con`, `dex`, `agi`, `dis`, `aur`, `log`, `int`, `wis`, `inf` | Same | |

### Pattern: Stat Access
```ruby
# Ruby
value, bonus = Stats.str
stat = Stats.strength
puts stat.value, stat.bonus, stat.base.value
```
```lua
-- Lua
local short = Stats.str
local value, bonus = short[1], short[2]
local stat = Stats.strength
print(stat.value, stat.bonus, stat.base.value)
```

---

## 6. Skills

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `Skills.edged_weapons` | `Skills.edged_weapons` | Returns ranks (integer) |
| `Skills.edgedweapons` | `Skills.edgedweapons` | Legacy alias works |
| `Skills.to_bonus(ranks)` | `Skills.to_bonus(ranks)` | Compute bonus from rank count |
| `Skills.to_bonus(:edged_weapons)` | `Skills.to_bonus("edged_weapons")` | Look up bonus from infomon |

Full skill list: `two_weapon_combat`, `armor_use`, `shield_use`, `combat_maneuvers`, `edged_weapons`, `blunt_weapons`, `two_handed_weapons`, `ranged_weapons`, `thrown_weapons`, `polearm_weapons`, `brawling`, `ambush`, `multi_opponent_combat`, `physical_fitness`, `dodging`, `arcane_symbols`, `magic_item_use`, `spell_aiming`, `harness_power`, `elemental_mana_control`, `mental_mana_control`, `spirit_mana_control`, `elemental_lore_air`, `elemental_lore_earth`, `elemental_lore_fire`, `elemental_lore_water`, `spiritual_lore_blessings`, `spiritual_lore_religion`, `spiritual_lore_summoning`, `sorcerous_lore_demonology`, `sorcerous_lore_necromancy`, `mental_lore_divination`, `mental_lore_manipulation`, `mental_lore_telepathy`, `mental_lore_transference`, `mental_lore_transformation`, `survival`, `disarming_traps`, `picking_locks`, `stalking_and_hiding`, `perception`, `climbing`, `swimming`, `first_aid`, `trading`, `pickpocketing`

---

## 7. Spells (Circle Ranks)

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `Spells.minor_elemental` | `Spells.minor_elemental` | Ranks in circle |
| `Spells.minorelemental` | `Spells.minorelemental` | Legacy alias |
| Same for: `major_elemental`, `minor_spiritual`, `major_spiritual`, `minor_mental`, `major_mental`, `wizard`, `sorcerer`, `ranger`, `paladin`, `empath`, `cleric`, `bard` | Same | |

---

## 8. Spell

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `Spell[101]` | `Spell[101]` | Lookup by number → table |
| `Spell["Spirit Warding I"]` | `Spell["Spirit Warding I"]` | Lookup by name |
| `Spell[101].active?` | `Spell[101].active` | Boolean |
| `Spell[101].known?` | `Spell[101].known` | Boolean |
| `Spell[101].timeleft` | `Spell[101].timeleft` | Minutes remaining |
| `Spell[101].secsleft` | `Spell[101].secsleft` | Seconds remaining |
| `Spell[101].name` | `Spell[101].name` | |
| `Spell[101].num` | `Spell[101].num` | |
| `Spell[101].type` | `Spell[101].type` | |
| `Spell[101].circle` | `Spell[101].circle` | |
| `Spell[101].availability` | `Spell[101].availability` | |
| `Spell.active` | `Spell.active()` | Array of active spell tables |
| `Spell[101].active_p` (num) | `Spell.active_p(101)` | Is spell num active? |
| `Spell[101].known_p` (num) | `Spell.known_p(101)` | Is spell num known? |

### Pattern: checkspell
```ruby
# Ruby
if checkspell(101, 401)
```
```lua
-- Lua
if Spell.active_p(101) and Spell.active_p(401) then
```

---

## 9. Hooks

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `DownstreamHook.add("name", proc { \|s\| ... })` | `DownstreamHook.add("name", function(s) ... end)` | Function receives line string |
| `DownstreamHook.remove("name")` | `DownstreamHook.remove("name")` | |
| `UpstreamHook.add("name", proc { \|s\| ... })` | `UpstreamHook.add("name", function(s) ... end)` | |
| `UpstreamHook.remove("name")` | `UpstreamHook.remove("name")` | |

**Key difference:** In Lich5, hook procs return the (possibly modified) string, or `nil` to squelch. In Revenant, hook functions work the same way — return the string to pass through, or return nil to squelch.

---

## 10. Map / Navigation

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `Room.current.id` | `Map.current_room()` | Returns room ID or nil |
| `Map[id]` / `Room[id]` | `Map.find_room(id)` | Returns room table or nil |
| `Map.find_room("name")` | `Map.find_room("name")` | Search by name |
| `Map.findpath(from, to)` | `Map.find_path(from, to)` | Returns table of command strings or nil |
| `Room.current` | `Room.current()` | Returns full room table with wayto/timeto |
| `Room.current.wayto` | `Room.current().wayto` | `{["dest_id"] = "command"}` |
| `go2("destination")` | `Map.go2("destination")` | Async: navigate to destination |
| `Map.load("path")` | `Map.load("path")` | Reload map data |
| `Map.list` | `Map.list()` | Table of all room IDs |
| `Map.tags(tag)` | `Map.tags(tag)` | Room IDs with the given tag |
| `Map.room_count` | `Map.room_count()` | Total number of rooms |
| `Room.find_nearest_by_tag(tag)` | `Room.find_nearest_by_tag(tag)` | `{id=N, path={cmds}}` or nil |
| `Room.path_to(dest)` | `Room.path_to(dest)` | Path from current room |

### Room table fields (from Map.find_room / Room.current):
- `id` — integer
- `title` — string
- `description` — string
- `tags` — table of tag strings
- `wayto` — table `{["dest_id"] = "command"}`
- `timeto` — table `{["dest_id"] = seconds_or_nil}`
- `paths` — table of exit strings
- `location` — string or nil
- `terrain` — string or nil
- `uid` — string/table or nil

---

## 11. Settings / Persistence

| Lich5 Ruby | Revenant Lua | Notes |
|-----------|-------------|-------|
| `CharSettings["key"]` | `CharSettings.key` | Per-character per-game |
| `CharSettings["key"] = "val"` | `CharSettings.key = "val"` | Set value (coerced to string) |
| `CharSettings["key"] = nil` | `CharSettings.key = nil` | Delete key |
| `UserVars["key"]` / `UserVars.key` | `UserVars.key` | Per-game variable |
| `UserVars["key"] = "val"` | `UserVars.key = "val"` | |
| `Vars["key"]` / `Vars.key` | `Vars["key"]` / `Vars.key` | Via `lib/lich_vars` — JSON-serialized in CharSettings |
| `Settings["key"]` | `Settings.key` | Global (cross-character) settings |
| `GameSettings["key"]` | `Settings.key` | Same as Settings |

**Note:** Revenant settings store strings only. For complex data, serialize to JSON:
```lua
-- Store a table
CharSettings.my_data = Json.encode({foo = "bar", count = 42})
-- Read it back
local data = Json.decode(CharSettings.my_data)
```

---

## 12. Familiar

| Lich5 Ruby | Revenant Lua |
|-----------|-------------|
| `XMLData.familiar_room_title` / `checkfamroom` | `Familiar.room_title` / `checkfamroom(...)` |
| `XMLData.familiar_room_description` / `checkfamroomdescrip` | `Familiar.room_description` / `checkfamroomdescrip(...)` |
| `XMLData.familiar_room_exits` / `checkfampaths` | `Familiar.room_exits` / `checkfampaths(dir)` |

---

## 13. Group

| Lich5 Ruby | Revenant Lua |
|-----------|-------------|
| `checkgrouped` | `Group.joined` |
| `Group.members` | `Group.members` (managed by group.lua) |
| `Group.leader` | `Group.leader` (managed by group.lua) |

---

## 14. Bounty / Society

| Lich5 Ruby | Revenant Lua |
|-----------|-------------|
| `checkbounty` / `XMLData.bounty_task` | `checkbounty()` / `Bounty.task` |
| `XMLData.society_task` | `Society.task` |

---

## 15. Utilities (Revenant-only)

These have no Lich5 equivalent:

| Revenant Lua | Description |
|-------------|-------------|
| `Http.get(url)` | HTTP GET → `{status, body, headers}` |
| `Http.get_json(url)` | HTTP GET + JSON parse → Lua table |
| `Json.encode(table)` | Lua table → JSON string |
| `Json.decode(string)` | JSON string → Lua table |
| `File.read("path")` | Read file (sandboxed to scripts dir) |
| `File.write("path", content)` | Write file (sandboxed) |
| `File.exists("path")` | Check file exists |
| `File.list("path")` | List directory |
| `File.mkdir("path")` | Create directory |
| `File.remove("path")` | Delete file/dir |
| `File.is_dir("path")` | Check if directory |
| `File.mtime("path")` | File modification time (unix) |
| `File.replace(src, dst)` | Rename/move file |
| `Crypto.sha256(string)` | SHA-256 hash |
| `Crypto.sha256_file(path)` | SHA-256 of file contents |
| `Version.parse("1.2.3")` | Parse semver → table |
| `Version.compare(a, b)` | Compare versions: -1/0/1 |
| `Version.satisfies(ver, constraint)` | Check semver constraint |
| `Version.engine_path()` | Path to engine binary |
| `send_to_script("name", "msg")` | Inject line into another script's buffer |

---

## 16. GUI (Feature: monitor)

Revenant includes a widget-based GUI system (compiled with `--features monitor`). No Lich5 equivalent exists.

| Revenant Lua | Description |
|-------------|-------------|
| `Gui.window(title, opts)` | Create window (`width`, `height`, `resizable`) |
| `Gui.label(text)` | Text label widget |
| `Gui.button(label)` | Clickable button |
| `Gui.checkbox(label, checked)` | Toggle checkbox |
| `Gui.input(opts)` | Text input field (`placeholder`, `text`) |
| `Gui.progress(value)` | Progress bar (0.0–1.0) |
| `Gui.separator()` | Visual separator |
| `Gui.table(opts)` | Data table (`columns` array) |
| `Gui.vbox()` / `Gui.hbox()` | Vertical/horizontal container |
| `Gui.scroll(child)` | Scrollable wrapper |
| `Gui.map_view(opts)` | Map visualization widget |
| `Gui.wait(target, event)` | Async wait for GUI event |

---

## 17. Ruby → Lua Syntax Translation Patterns

### String Operations
```ruby
# Ruby
str =~ /pattern/           → string.find(str, "pattern")
str.include?("sub")        → string.find(str, "sub", 1, true)  -- plain match
str.gsub(/pat/, "rep")     → string.gsub(str, "pat", "rep")
str.sub(/pat/, "rep")      → (string.gsub(str, "pat", "rep", 1))
str.split(",")             → (manual split or use helper)
str.strip                  → str:match("^%s*(.-)%s*$")
str.downcase               → string.lower(str)
str.upcase                 → string.upper(str)
"#{var} text"              → var .. " text"
str.start_with?("x")       → str:sub(1,1) == "x"
str.length                 → #str
str.empty?                 → str == "" or str == nil
```

### Array/Table Operations
```ruby
# Ruby
arr.each { |x| ... }      → for _, x in ipairs(t) do ... end
arr.find { |x| cond }     → (loop with break)
arr.select { |x| cond }   → (loop with table.insert)
arr.collect / arr.map      → (loop with table.insert)
arr.empty?                 → #t == 0
arr.length                 → #t
arr.push(val)              → table.insert(t, val)
arr.include?(val)          → (loop check or helper)
arr.join(", ")             → table.concat(t, ", ")
```

### Control Flow
```ruby
# Ruby
if condition               → if condition then
elsif other                → elseif other then
end                        → end
unless condition           → if not condition then
condition ? a : b          → condition and a or b  (careful with falsy a)
begin/rescue/ensure        → local ok, err = pcall(function() ... end)
loop { ... }               → while true do ... end
5.times { ... }            → for i = 1, 5 do ... end
1.upto(10) { |i| ... }    → for i = 1, 10 do ... end
break if cond              → if cond then break end
next if cond               → (use goto in Lua 5.2+ or restructure)
return if cond             → if cond then return end
```

### Hash/Table
```ruby
# Ruby
hash = {}                  → local t = {}
hash["key"] = val          → t["key"] = val  -- or t.key = val
hash.key?("k")             → t["k"] ~= nil
hash.each { |k,v| ... }   → for k, v in pairs(t) do ... end
hash.merge(other)          → (manual merge loop)
```

### Nil / Boolean
```ruby
# Ruby
val.nil?                   → val == nil
val || default             → val or default
val && other               → val and other
!val                       → not val
val != other               → val ~= other
```

---

## 18. Remaining Gaps

Most Lich5 features are now implemented. The following have no Revenant equivalent and are explicitly deferred:

| Feature | Lich5 | Status |
|---------|-------|--------|
| **Enhancive / Resources** | Equipment enhancive tracking | Deferred — low community usage |
| **Spellsong** | Bard spellsong tracking | Deferred — bard-specific |
| **Map.get_location** | Location-based room lookup | Deferred — requires location data infrastructure |
| **ExecScript** | Run arbitrary Ruby code as a script | Not applicable (use `Script.run`) |
| **WizardScript / goto / labels** | Wizard script support | Not applicable to Lua runtime |
| **fetchloot / take** | Auto-loot helpers | Trivial to write in Lua |
| **Lich.log** | Write to Lich log file | Not implemented |
| **SharedBuffer / Buffer** | `Buffer.gets`, `Buffer.gets?` | Use `get()`/`get_noblock()` |

---

## 19. Common Conversion Patterns

### Hunting Script Pattern
```ruby
# Ruby (Lich5)
loop {
  waitrt?
  fput "hunt"
  line = matchwait("You notice", "You don't find", "Roundtime")
  if line =~ /You notice/
    target = GameObj.npcs.find { |n| n.status !~ /dead/ }
    fput "attack #{target.noun}" if target
  end
  pause 1
}
```
```lua
-- Lua (Revenant)
while true do
    waitrt()
    fput("hunt")
    local line = matchwait("You notice", "You don't find", "Roundtime")
    if string.find(line, "You notice") then
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if npc.status ~= "dead" then
                fput("attack " .. npc.noun)
                break
            end
        end
    end
    pause(1)
end
```

### Hook Pattern
```ruby
# Ruby (Lich5)
DownstreamHook.add("my_filter", proc { |line|
  if line =~ /INVENTORY/
    nil  # squelch
  else
    line
  end
})
before_dying { DownstreamHook.remove("my_filter") }
```
```lua
-- Lua (Revenant)
DownstreamHook.add("my_filter", function(line)
    if string.find(line, "INVENTORY") then
        return nil  -- squelch
    end
    return line
end)
before_dying(function()
    DownstreamHook.remove("my_filter")
end)
```

### Settings Pattern
```ruby
# Ruby (Lich5)
CharSettings['target'] ||= 'troll'
target = CharSettings['target']
```
```lua
-- Lua (Revenant)
if not CharSettings.target then
    CharSettings.target = "troll"
end
local target = CharSettings.target
```
