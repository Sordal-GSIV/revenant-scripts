--- @revenant-script
--- name: buff
--- version: 1.0.0
--- author: Ondreian (original buff.lic)
--- original-authors: Ondreian, dr-scripts community contributors
--- game: dr
--- description: Cast waggle_sets buff spells for your character. Supports barbarian meditations, thief khris, and standard spellcasters.
--- tags: magic,buff,waggle,spell,utility
--- source: https://elanthipedia.play.net/Lich_script_development#buff
--- @lic-certified: complete 2026-03-18
---
--- Conversion notes vs Lich5:
---   * parse_args uses Lua patterns instead of Ruby Regexp (semantics identical).
---   * DRSpells.active_spells() now returns a hash {[name]=duration} — same API as Lich5.
---   * DRCA.do_buffs() fully implemented with barbarian/thief/spellcaster dispatch.
---   * Day/night filtering reads UserVars.sun as JSON (set by sunwatch script).
---   * Strict mode set-difference uses pairs() iteration over active_spells hash.
---   * get_settings() / parse_args() provided by dependency.lua (must be running).

-- ============================================================================
-- Argument parsing
-- ============================================================================

local arg_definitions = {
  {
    { name = "set",    regex = "set=%w+",  optional = true, description = "Show spells under a specific waggle set (e.g. set=prehunt)" },
    { name = "list",   regex = "^list$",   optional = true, description = "List all defined waggle set names" },
    { name = "spells", regex = "%w+",      optional = true, description = "Spell list to use (default: 'default')" },
    { name = "force",  regex = "^force$",  optional = true, description = "Recast spells even if currently active" },
    { name = "strict", regex = "^strict$", optional = true, description = "Keep recasting until all spells are active (BE CAREFUL)" },
  }
}

local args = parse_args(arg_definitions)
local settings = get_settings()

-- ============================================================================
-- set=<name> — list spells in a named waggle set
-- ============================================================================

if args.set then
  local set = args.set:match("set=(%w+)")
  if not set then
    DRC.message("buff: invalid set argument (use set=<name>)")
    return
  end
  if not (settings.waggle_sets and settings.waggle_sets[set]) then
    DRC.message("buff: no waggle set found for name: " .. set)
    return
  end
  DRC.message("Spells under Waggle set \"" .. set .. "\"")
  for key, _ in pairs(settings.waggle_sets[set]) do
    DRC.message(" - " .. tostring(key))
  end
  return
end

-- ============================================================================
-- list — list all waggle set names
-- ============================================================================

if args.list then
  if not settings.waggle_sets then
    DRC.message("buff: no waggle_sets found in settings.")
    return
  end
  DRC.message("Waggle Sets Available")
  for key, _ in pairs(settings.waggle_sets) do
    DRC.message(" - " .. tostring(key))
  end
  return
end

-- ============================================================================
-- Resolve waggle set name (from args or default)
-- ============================================================================

local setname = (args.spells and args.spells ~= "") and args.spells or "default"

if not (settings.waggle_sets and settings.waggle_sets[setname]) then
  DRC.message("buff: no waggle set found for name: " .. setname)
  return
end

-- ============================================================================
-- force — mark all spells to be recast regardless of remaining duration
-- ============================================================================

if args.force then
  for _, spell_data in pairs(settings.waggle_sets[setname]) do
    spell_data.recast = 99
    spell_data["recast"] = 99
  end
end

-- ============================================================================
-- Cast buffs
-- ============================================================================

if args.strict then
  -- strict mode: keep recasting until every spell in the set is active
  while true do
    local active = DRSpells.active_spells()
    local all_active = true
    for name, _ in pairs(settings.waggle_sets[setname]) do
      if not active[name] then
        all_active = false
        break
      end
    end
    if all_active then break end
    DRCA.do_buffs(settings, setname)
  end
else
  DRCA.do_buffs(settings, setname)
end
