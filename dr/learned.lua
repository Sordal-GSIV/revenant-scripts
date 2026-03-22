--- @revenant-script
--- name: learned
--- version: 1.0
--- author: dr-scripts contributors
--- game: dr
--- description: Show experience gained in skills since last reset or session start.
---   Optionally filter by skill group (combat, survival, magic, armor, weapons,
---   lore, guild). Use 'reset' to reset baselines, 'zero' to include skills with
---   no gain. Displays per-skill gain, hourly/daily rates, and totals with TDPS.
--- tags: exp, experience, skills, tracking
--- source: https://elanthipedia.play.net/Lich_script_repository#learned
--- @lic-certified: complete 2026-03-19
---
--- Converted from learned.lic
--- Original authors: dr-scripts contributors
---
--- Changelog vs Lich5:
---   v1.0 - Initial conversion
---   * parse_args replaced with Script.vars table and Lua pattern matching
---   * DRSkill.start_time() added to lib/dr/skills.lua (new API, mirrors Lich5)
---   * center() helper replaces Ruby String#center
---   * string.format replaces Ruby Kernel#format
---   * settings.learned_column_count defaults to 2 if not configured

-- Skill group definitions (verbatim from learned.lic)
local survival_skills = {
  "Evasion", "Athletics", "Perception", "Stealth", "Locksmithing",
  "Thievery", "First Aid", "Outdoorsmanship", "Skinning",
}
local lore_skills = {
  "Alchemy", "Appraisal", "Enchanting", "Forging", "Mechanical Lore",
  "Performance", "Scholarship", "Tactics", "Outfitting", "Engineering",
}
local armor_skills = {
  "Shield Usage", "Chain Armor", "Plate Armor", "Light Armor", "Brigandine", "Defending",
}
local weapon_skills = {
  "Parry Ability", "Small Edged", "Large Edged", "Twohanded Edged", "Small Blunt",
  "Large Blunt", "Twohanded Blunt", "Slings", "Bow", "Crossbow", "Staves", "Polearms",
  "Light Thrown", "Heavy Thrown", "Brawling", "Offhand Weapon", "Melee Mastery",
  "Missile Mastery",
}
local magic_skills = {
  "Arcane Magic", "Holy Magic", "Life Magic", "Elemental Magic", "Lunar Magic",
  "Attunement", "Arcana", "Targeted Magic", "Inner Fire", "Inner Magic",
  "Augmentation", "Debilitation", "Utility", "Warding", "Sorcery",
}
local guild_skills = {
  "Empathy", "Astrology", "Expertise", "Instinct", "Backstab", "Summoning",
  "Bardic Lore", "Conviction", "Theurgy", "Thanatology", "Trading",
}

-- Parse arg
local arg1 = (Script.vars[1] or ""):lower()

-- Handle reset
if arg1:match("reset") then
  DRSkill.reset()
end

local show_zero = arg1:match("^zero") ~= nil

-- Build skills_to_show
local skills_to_show = {}
local function extend(t, src)
  for _, v in ipairs(src) do t[#t + 1] = v end
end

if arg1:match("survival") or arg1:match("surv") then
  extend(skills_to_show, survival_skills)
elseif arg1:match("combat") or arg1:match("comb") then
  extend(skills_to_show, armor_skills)
  extend(skills_to_show, weapon_skills)
  skills_to_show[#skills_to_show + 1] = "Targeted Magic"
  skills_to_show[#skills_to_show + 1] = "Debilitation"
  skills_to_show[#skills_to_show + 1] = "Evasion"
  skills_to_show[#skills_to_show + 1] = "Tactics"
elseif arg1:match("magic") then
  extend(skills_to_show, magic_skills)
elseif arg1:match("armor") then
  extend(skills_to_show, armor_skills)
elseif arg1:match("weapons") or arg1:match("weap") then
  extend(skills_to_show, weapon_skills)
elseif arg1:match("lore") then
  extend(skills_to_show, lore_skills)
elseif arg1:match("guild") then
  extend(skills_to_show, guild_skills)
else
  extend(skills_to_show, survival_skills)
  extend(skills_to_show, lore_skills)
  extend(skills_to_show, armor_skills)
  extend(skills_to_show, weapon_skills)
  extend(skills_to_show, magic_skills)
  extend(skills_to_show, guild_skills)
end

-- Build a set for fast membership testing
local show_set = {}
for _, name in ipairs(skills_to_show) do
  show_set[name] = true
end

-- Pause to let game state settle (mirrors the bare `pause` in learned.lic class body)
pause(1)

-- Load settings
local settings = get_settings()
local columns = (settings and settings.learned_column_count) or 2

-- Learning time in hours; guard against zero (e.g. called immediately after reset)
local learning_time = (os.time() - DRSkill.start_time()) / 3600.0
if learning_time < 0.0001 then learning_time = 0.0001 end

-- Center a string in a field of width w
local function center(s, w)
  local len = #s
  if len >= w then return s end
  local left = math.floor((w - len) / 2)
  return string.rep(" ", left) .. s .. string.rep(" ", w - len - left)
end

local function format_skill_data(name)
  local gain = DRSkill.gained_exp(name)
  return string.format("%s %s (%0.2f/hr, %0.2f/day)",
    center(name, 18),
    center(string.format("%.2f", gain), 6),
    gain / learning_time,
    gain / learning_time * 24
  )
end

-- Collect and filter skills
local all_skills = DRSkill.list()
local filtered = {}
for _, s in ipairs(all_skills) do
  if show_set[s.name] then
    if show_zero or DRSkill.gained_exp(s.name) > 0 then
      filtered[#filtered + 1] = s
    end
  end
end

-- Sort by gained_exp descending
table.sort(filtered, function(a, b)
  return DRSkill.gained_exp(a.name) > DRSkill.gained_exp(b.name)
end)

-- Print rows of `columns` skills each
for i = 1, #filtered, columns do
  local parts = {}
  for j = i, math.min(i + columns - 1, #filtered) do
    parts[#parts + 1] = format_skill_data(filtered[j].name)
  end
  respond(table.concat(parts))
end

-- Compute totals (only skills with positive gain contribute)
local total = 0
local tdps  = 0
for _, s in ipairs(filtered) do
  local gain = DRSkill.gained_exp(s.name)
  if gain > 0 then
    total = total + gain
    tdps  = tdps + (gain * DRSkill.getrank(s.name)) / 200
  end
end
total = math.floor(total * 100 + 0.5) / 100
tdps  = math.floor(tdps  * 100 + 0.5) / 100

local per_hour    = total / learning_time
local per_day     = per_hour * 24
local hourly_tdps = tdps / learning_time
local daily_tdps  = tdps / learning_time * 24

respond(string.format("   TOTAL RANKS: %.2f  HOURLY: %.2f  DAILY: %.2f", total, per_hour, per_day))
respond(string.format("   TOTAL TDPS: %.2f  HOURLY: %.2f  DAILY: %.2f", tdps, hourly_tdps, daily_tdps))
respond(string.format("   Learning For: %.1f hours", learning_time))
