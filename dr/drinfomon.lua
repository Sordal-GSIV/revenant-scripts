--- @revenant-script
--- name: drinfomon
--- version: 1.0.0
--- author: rpherbig
--- game: dr
--- description: DR info monitor - tracks skills, stats, vitals, encumbrance, and more
--- tags: monitoring, skills, stats, drinfomon, core
---
--- Ported from drinfomon.lic (Lich5) to Revenant Lua
---
--- Core background script that tracks character information for other scripts.
--- Provides DRStats, DRSkill, DRSpells, DRRoom modules.
---
--- Usage:
---   ;drinfomon   - Run in background (required by most DR scripts)
---   ;banks       - Show tracked bank balances
---   ;vault       - Show tracked vault contents

no_kill_all()
no_pause_all()

-- DRStats module
if not DRStats then DRStats = {} end
DRStats.race = DRStats.race or "unknown"
DRStats.guild = DRStats.guild or "unknown"
DRStats.gender = DRStats.gender or "unknown"
DRStats.age = DRStats.age or 0
DRStats.circle = DRStats.circle or 0
DRStats.strength = DRStats.strength or 0
DRStats.stamina = DRStats.stamina or 0
DRStats.reflex = DRStats.reflex or 0
DRStats.agility = DRStats.agility or 0
DRStats.intelligence = DRStats.intelligence or 0
DRStats.wisdom = DRStats.wisdom or 0
DRStats.discipline = DRStats.discipline or 0
DRStats.charisma = DRStats.charisma or 0
DRStats.concentration = DRStats.concentration or 0
DRStats.favors = DRStats.favors or 0
DRStats.tdps = DRStats.tdps or 0
DRStats.encumbrance = DRStats.encumbrance or "unknown"
DRStats.health = DRStats.health or 100
DRStats.mana = DRStats.mana or 100
DRStats.fatigue = DRStats.fatigue or 100
DRStats.spirit = DRStats.spirit or 100

function DRStats.empath()
    return DRStats.guild == "Empath"
end

-- DRSkill module
if not DRSkill then DRSkill = {} end
local skill_data = {}

function DRSkill.getrank(name)
    if skill_data[name] then return skill_data[name].rank end
    return 0
end

function DRSkill.getxp(name)
    if skill_data[name] then return skill_data[name].xp end
    return 0
end

-- DRSpells module
if not DRSpells then DRSpells = {} end
DRSpells.active_spells = DRSpells.active_spells or {}

-- DRRoom module
if not DRRoom then DRRoom = {} end
DRRoom.room_objs = DRRoom.room_objs or {}

-- Parse info command
local function parse_info(line)
    local guild = line:match("Guild:%s+(.+)")
    if guild then DRStats.guild = guild:gsub("%s+$", "") end
    local race = line:match("Race:%s+(.+)")
    if race then DRStats.race = race:gsub("%s+$", "") end
    local circle = line:match("Circle:%s+(%d+)")
    if circle then DRStats.circle = tonumber(circle) end
    local gender = line:match("Gender:%s+(.+)")
    if gender then DRStats.gender = gender:gsub("%s+$", "") end
    local age = line:match("Age:%s+(%d+)")
    if age then DRStats.age = tonumber(age) end
    local favors = line:match("Favors:%s+(%d+)")
    if favors then DRStats.favors = tonumber(favors) end
    local tdps = line:match("TDPs:%s+(%d+)")
    if tdps then DRStats.tdps = tonumber(tdps) end
end

-- Parse experience line
local function parse_exp(line)
    -- Format: "  Skill Name:  123 45% learning"
    local name, rank, xp = line:match("^%s+(.-):%s+(%d+)%s+(%d+)")
    if name and rank and xp then
        name = name:gsub("%s+$", "")
        skill_data[name] = { rank = tonumber(rank), xp = tonumber(xp) }
    end
end

echo("DRInfomon loaded. Monitoring character state...")

-- Main monitoring loop
while true do
    local line = get()
    if line then
        parse_info(line)
        parse_exp(line)
    end
end
