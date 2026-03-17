--- @revenant-script
--- name: ewaggle
--- version: 2.1.5
--- author: elanthia-online
--- contributors: Tillmen, Tysong, Deysh
--- game: gs
--- description: Spellup script for yourself and others
--- tags: magic,utility,spell,waggle
---
--- Changelog (from Lich5):
---   v2.1.5 - Add disk casting support
---   v2.1.4 - Bugfix in logic bad target/spell
---   v2.1.3 - Bugfix in --cast-list regex
---   v2.1.2 - Bugfix for info sharing
---   v2.1.1 - Remove additional deprecated Lich calls
---   v2.1.0 - Added option to skip characters not sharing spell info
---   v2.0.0 - Major refactor, yaml profiles, armor buffs, sonic gear
---
--- Usage:
---   ;ewaggle               -- spell yourself up
---   ;ewaggle help          -- show help
---   ;ewaggle setup         -- show/edit settings
---   ;ewaggle list          -- show current settings
---   ;ewaggle info          -- show what will be cast
---   ;ewaggle <name> ...    -- spell up given people

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SCRIPT_NAME = "ewaggle"

local function load_json(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

local function save_json(key, val)
    CharSettings[key] = Json.encode(val)
end

local function load_setting(key, default)
    local raw = CharSettings[SCRIPT_NAME .. "_" .. key]
    if raw == nil or raw == "" then return default end
    if raw == "true" then return true end
    if raw == "false" then return false end
    local num = tonumber(raw)
    if num then return num end
    return raw
end

local function save_setting(key, value)
    CharSettings[SCRIPT_NAME .. "_" .. key] = tostring(value)
end

-- Default spell list by circle
local DEFAULT_CAST_LIST = {
    101, 102, 103, 107, 115, 120,
    202, 211, 215, 219,
    303, 307, 310, 313, 314, 319, 320,
    401, 406, 414, 425, 430,
    503, 507, 508, 509, 513, 520, 535,
    601, 602, 604, 605, 606, 612, 613, 617, 618, 620, 625, 640,
    704, 712, 716,
    905, 911, 913, 920,
    1003, 1006, 1007, 1010, 1019,
    1109, 1119, 1125, 1130,
    1202, 1204, 1208, 1214, 1215, 1220,
    1601, 1603, 1606, 1610, 1611, 1612, 1616,
}

local settings = {
    cast_list       = load_json(SCRIPT_NAME .. "_cast_list", DEFAULT_CAST_LIST),
    start_at        = load_setting("start_at", 180),
    stop_at         = load_setting("stop_at", 180),
    refreshable_min = load_setting("refreshable_min", 15),
    use_multicast   = load_setting("use_multicast", true),
    use_wracking    = load_setting("use_wracking", false),
    wander_to_wrack = load_setting("wander_to_wrack", false),
    use_power       = load_setting("use_power", false),
    use_mana        = load_setting("use_mana", false),
    use_concentration = load_setting("use_concentration", false),
    skip_short_spells = load_setting("skip_short_spells", false),
    skip_not_sharing  = load_setting("skip_not_sharing", false),
    bail_no_mana    = load_setting("bail_no_mana", false),
    reserve_mana    = load_setting("reserve_mana", 0),
    retribution_spell = load_setting("retribution_spell", ""),
    use_203         = load_setting("use_203", false),
    use_515         = load_setting("use_515", false),
    sonic_weapon    = load_setting("sonic_weapon", ""),
    sonic_shield    = load_setting("sonic_shield", ""),
    sonic_armor     = load_setting("sonic_armor", ""),
}

local SHORT_SPELL_TIME = 3
local skip_spells = {}
local skip_targets = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

local function is_known_spell(num)
    local spell = Spell[num]
    return spell and spell:known() and spell:time_per() > 0
end

local function get_cast_list()
    local list = {}
    for _, num in ipairs(settings.cast_list) do
        if type(num) == "number" and is_known_spell(num) then
            table.insert(list, num)
        end
    end
    return list
end

local function fix_spell(spell)
    if type(spell) == "number" or (type(spell) == "string" and spell:match("^%d+$")) then
        return Spell[tonumber(spell)]
    end
    return spell
end

local function save_all_settings()
    save_json(SCRIPT_NAME .. "_cast_list", settings.cast_list)
    for _, key in ipairs({"start_at", "stop_at", "refreshable_min", "use_multicast",
                          "use_wracking", "wander_to_wrack", "use_power", "use_mana",
                          "use_concentration", "skip_short_spells", "skip_not_sharing",
                          "bail_no_mana", "reserve_mana", "retribution_spell",
                          "use_203", "use_515", "sonic_weapon", "sonic_shield", "sonic_armor"}) do
        save_setting(key, settings[key])
    end
end

--------------------------------------------------------------------------------
-- Mana Management
--------------------------------------------------------------------------------

local function check_mana(spell, num_multicast)
    num_multicast = num_multicast or 1
    local spell_cost = spell:mana_cost() * num_multicast + settings.reserve_mana

    if spell:affordable() and (spell:mana_cost() == 0 or GameState.mana >= spell_cost) then
        return true
    end

    if spell:mana_cost() <= 0 then return true end

    -- Try society abilities for mana
    if settings.use_wracking and Spell[9918] and Spell[9918]:affordable() then
        Spell[9918]:cast()
        return spell:affordable()
    elseif settings.use_power and Spell[9718] and Spell[9718]:affordable() then
        Spell[9718]:cast()
        pause(0.2)
        return spell:affordable()
    elseif settings.use_mana and Spell[9813] then
        local result = Spell[9813]:cast()
        if result and string.find(tostring(result), "strain to perform") then
            echo("Out of favor! Disabling symbol of mana.")
            settings.use_mana = false
        end
        pause(0.2)
        return spell:affordable()
    end

    -- Wait for mana or bail
    if settings.bail_no_mana then
        echo("Out of mana/resources, bailing out!")
        return false
    end

    echo("Waiting for mana...")
    while not spell:affordable() or (spell:mana_cost() > 0 and GameState.mana < spell_cost) do
        pause(1)
    end
    return true
end

--------------------------------------------------------------------------------
-- Casting Support
--------------------------------------------------------------------------------

local function cast_support()
    if settings.use_concentration and Spell[9714] and Spell[9714]:affordable() and not Spell[9714]:active() then
        Spell[9714]:cast()
    end

    if settings.use_203 and Spell[203] and Spell[203]:affordable() then
        -- Eat mana bread
        if not Spell[203]:active() or Spell[203]:timeleft() < 10 then
            Spell[203]:cast()
            -- Gobble the bread
            local right = GameObj.right_hand
            local left = GameObj.left_hand
            for _, hand in ipairs({right, left}) do
                if hand and hand.noun and Regex.test(hand.noun, "flatbread|teacake|cake|waybread|biscuit|oatcake|loaf|bread|tart|dough") then
                    fput("gobble #" .. hand.id)
                    break
                end
            end
        end
    end

    if settings.use_515 and Spell[515] and Spell[515]:affordable() and not Spell[515]:active() then
        Spell[515]:cast()
    end
end

local function max_multicast(spell)
    local ranks = 0
    local prof = Stats.prof

    if prof == "Wizard" then
        ranks = Skills.emc or 0
    elseif Regex.test(prof, "Cleric|Ranger|Paladin") then
        ranks = Skills.smc or 0
    elseif Regex.test(prof, "Empath|Monk|Bard") then
        ranks = math.max(Skills.mmc or 0, Skills.smc or 0) + (math.min(Skills.mmc or 0, Skills.smc or 0) / 2)
    elseif Regex.test(prof, "Sorcerer|Warrior|Rogue") then
        ranks = math.max(Skills.emc or 0, Skills.smc or 0) + (math.min(Skills.emc or 0, Skills.smc or 0) / 2)
    end

    return math.floor(ranks / 25) + 1
end

local function cast_spell(spell, target, num_multicast)
    num_multicast = num_multicast or 1

    if not spell or not spell:known() then return "bad_spell" end
    if not check_mana(spell, num_multicast) then return "bail" end

    local cast_result
    if target == GameState.char_name then
        if spell:num() == 1009 and settings.sonic_shield ~= "" then
            cast_result = spell:cast(settings.sonic_shield)
        elseif spell:num() == 1012 and settings.sonic_weapon ~= "" then
            cast_result = spell:cast(settings.sonic_weapon)
        elseif spell:num() == 1014 and settings.sonic_armor ~= "" then
            cast_result = spell:cast(settings.sonic_armor)
        elseif num_multicast > 1 then
            cast_result = spell:cast(tostring(num_multicast))
        else
            cast_result = spell:cast()
        end
    else
        if num_multicast > 1 then
            cast_result = spell:cast("at " .. target .. " " .. num_multicast)
        else
            cast_result = spell:cast("at " .. target)
        end
    end

    local result_str = tostring(cast_result or "")
    if string.find(result_str, "no need for spells of war") or string.find(result_str, "Spells of War cannot be cast") then
        return "bad_spell"
    elseif result_str == "Cast at what?" then
        return "bad_target"
    elseif string.find(result_str, "Spell Hindrance") then
        return cast_spell(spell, target, num_multicast)  -- retry
    end

    return "success"
end

--------------------------------------------------------------------------------
-- Target Info
--------------------------------------------------------------------------------

local function get_self_info()
    local info = {}
    if Spell.active then
        for _, spell in ipairs(Spell.active()) do
            info[tostring(spell:num())] = spell:timeleft()
        end
    end
    info.sharing = true
    return info
end

local function get_target_info(target)
    if target == GameState.char_name then
        return get_self_info()
    end

    -- For other targets, we'd need SPELL ACTIVE, simplified here
    local info = { sharing = true }
    return info
end

--------------------------------------------------------------------------------
-- Casting Phases
--------------------------------------------------------------------------------

local function cast_stackable(target, info)
    local cast_list = get_cast_list()

    -- Sort 625 first
    table.sort(cast_list, function(a, b)
        if a == 625 then return true end
        if b == 625 then return false end
        return a < b
    end)

    for _, spell_num in ipairs(cast_list) do
        local spell = fix_spell(spell_num)
        if not spell then goto continue end

        if not spell:stackable() then goto continue end
        if not spell:available() then goto continue end
        if spell:time_per() <= SHORT_SPELL_TIME and target ~= GameState.char_name and settings.skip_short_spells then goto continue end
        if table_contains(skip_spells, spell:num()) or table_contains(skip_targets, target) then goto continue end

        local existing = info[tostring(spell:num())] or 0
        if existing > settings.start_at then goto continue end

        cast_support()

        local mc = max_multicast(spell)

        while (info[tostring(spell:num())] or 0) < settings.stop_at do
            if table_contains(skip_targets, target) or table_contains(skip_spells, spell:num()) then break end

            local remaining = settings.stop_at - (info[tostring(spell:num())] or 0)
            local needed = math.ceil(remaining / spell:time_per())
            local casts = math.min(needed, mc)
            if casts <= 0 then break end

            if not settings.use_multicast then casts = 1 end

            local result = cast_spell(spell, target, casts)
            if result == "bad_spell" then
                table.insert(skip_spells, spell:num())
                break
            elseif result == "bad_target" then
                table.insert(skip_targets, target)
                break
            elseif result == "bail" then
                return false
            else
                info[tostring(spell:num())] = (info[tostring(spell:num())] or 0) + spell:time_per() * casts
            end

            if not info.sharing then break end
        end

        -- Retribution for Cloak of Shadows
        if spell:num() == 712 and target == GameState.char_name and settings.retribution_spell ~= "" then
            fput("chant retribution " .. settings.retribution_spell)
        end

        ::continue::
    end
    return true
end

local function cast_refreshable(target, info)
    local cast_list = get_cast_list()

    for _, spell_num in ipairs(cast_list) do
        local spell = fix_spell(spell_num)
        if not spell then goto continue end

        if spell:stackable() then goto continue end
        if not spell:available() then goto continue end
        if not spell:refreshable() then goto continue end
        if spell:time_per() <= SHORT_SPELL_TIME and target ~= GameState.char_name and settings.skip_short_spells then goto continue end
        if table_contains(skip_spells, spell:num()) or table_contains(skip_targets, target) then goto continue end

        local existing = info[tostring(spell:num())] or 0
        if existing > settings.refreshable_min then goto continue end

        cast_support()

        local result = cast_spell(spell, target)
        if result == "bad_spell" then
            table.insert(skip_spells, spell:num())
        elseif result == "bad_target" then
            table.insert(skip_targets, target)
        elseif result == "bail" then
            return false
        end

        ::continue::
    end
    return true
end

local function cast_solid(target, info)
    local cast_list = get_cast_list()

    for _, spell_num in ipairs(cast_list) do
        local spell = fix_spell(spell_num)
        if not spell then goto continue end

        if spell:stackable() or spell:refreshable() then goto continue end
        if not spell:available() then goto continue end
        if spell:time_per() <= SHORT_SPELL_TIME and target ~= GameState.char_name and settings.skip_short_spells then goto continue end
        if table_contains(skip_spells, spell:num()) or table_contains(skip_targets, target) then goto continue end

        local existing = info[tostring(spell:num())] or 0
        if existing > 0 then goto continue end

        cast_support()

        local result = cast_spell(spell, target)
        if result == "bad_spell" then
            table.insert(skip_spells, spell:num())
        elseif result == "bad_target" then
            table.insert(skip_targets, target)
        elseif result == "bail" then
            return false
        end

        ::continue::
    end
    return true
end

local function cast_disk(target)
    if not table_contains(get_cast_list(), 511) then return true end

    local spell = fix_spell(511)
    if not spell then return true end

    -- Check if disk already exists
    local disk_pattern = target .. " disk"
    for _, loot in ipairs(GameObj.loot or {}) do
        if loot.name and string.find(loot.name:lower(), disk_pattern:lower()) then
            return true
        end
    end

    local result = cast_spell(spell, target)
    if result == "bad_spell" then
        table.insert(skip_spells, spell:num())
    elseif result == "bad_target" then
        table.insert(skip_targets, target)
    end
    return true
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("=== Ewaggle Help ===")
    respond("  ;ewaggle               -- spell yourself up")
    respond("  ;ewaggle help          -- this message")
    respond("  ;ewaggle setup         -- configure settings")
    respond("  ;ewaggle list          -- show current settings")
    respond("  ;ewaggle info          -- show spell info for yourself")
    respond("  ;ewaggle info <name>   -- show spell info for target")
    respond("  ;ewaggle add <spell#>  -- add spell to cast list")
    respond("  ;ewaggle delete <spell#> -- remove spell from cast list")
    respond("  ;ewaggle <name1> <name2> -- spell up given people")
    respond("")
    respond("  CLI overrides (not saved):")
    respond("    --start-at=N  --stop-at=N  --refreshable-min=N")
    respond("    --cast-list=401,406,503  --reserve-mana=N")
    respond("    --multicast=on/off  --wracking=on/off  --bail=on/off")
    respond("    --use203=on/off  --use515=on/off  --save")
    respond("====================")
    respond("")
end

local function show_list()
    respond("")
    respond("=== Ewaggle Settings ===")
    respond(string.format("  %-25s %s", "start at:", tostring(settings.start_at)))
    respond(string.format("  %-25s %s", "stop at:", tostring(settings.stop_at)))
    respond(string.format("  %-25s %s", "refreshable min:", tostring(settings.refreshable_min)))
    respond(string.format("  %-25s %s", "multicast:", tostring(settings.use_multicast)))
    respond(string.format("  %-25s %s", "sign of wracking:", tostring(settings.use_wracking)))
    respond(string.format("  %-25s %s", "wander to wrack:", tostring(settings.wander_to_wrack)))
    respond(string.format("  %-25s %s", "sigil of power:", tostring(settings.use_power)))
    respond(string.format("  %-25s %s", "sigil of concentration:", tostring(settings.use_concentration)))
    respond(string.format("  %-25s %s", "symbol of mana:", tostring(settings.use_mana)))
    respond(string.format("  %-25s %s", "skip short spells:", tostring(settings.skip_short_spells)))
    respond(string.format("  %-25s %s", "skip not sharing:", tostring(settings.skip_not_sharing)))
    respond(string.format("  %-25s %s", "reserve mana:", tostring(settings.reserve_mana)))
    respond(string.format("  %-25s %s", "bail no resources:", tostring(settings.bail_no_mana)))
    respond(string.format("  %-25s %s", "use mana bread (203):", tostring(settings.use_203)))
    respond(string.format("  %-25s %s", "use rapid fire (515):", tostring(settings.use_515)))
    respond(string.format("  %-25s %s", "retribution spell:", settings.retribution_spell ~= "" and settings.retribution_spell or "none"))

    local cast_nums = {}
    for _, n in ipairs(get_cast_list()) do
        table.insert(cast_nums, tostring(n))
    end
    respond(string.format("  %-25s %s", "cast list:", table.concat(cast_nums, ", ")))
    respond("========================")
    respond("")
end

local function show_info(targets)
    for _, target in ipairs(targets) do
        local info = get_target_info(target)
        local cast_list = get_cast_list()
        local total_casts = 0
        local total_mana = 0

        respond("")
        respond(string.format("=== Ewaggle Info: %s ===", target))

        for _, spell_num in ipairs(cast_list) do
            local spell = fix_spell(spell_num)
            if not spell then goto continue end
            if not spell:available() then goto continue end

            local existing = info[tostring(spell:num())] or 0
            local casts = 0

            if spell:stackable() then
                if existing < settings.start_at then
                    casts = math.ceil((settings.stop_at - existing) / spell:time_per())
                end
            elseif spell:refreshable() then
                if existing < settings.refreshable_min then casts = 1 end
            else
                if existing <= 0 then casts = 1 end
            end

            if casts > 0 then
                total_casts = total_casts + casts
                total_mana = total_mana + casts * spell:mana_cost()
                respond(string.format("  %d %-30s x%d (%d mana)",
                    spell:num(), spell:name(), casts, casts * spell:mana_cost()))
            end

            ::continue::
        end

        respond(string.format("  Total: %d casts, %d mana", total_casts, total_mana))
        respond("========================")
    end
end

local function cmd_add(spell_num)
    spell_num = tonumber(spell_num)
    if not spell_num then
        respond("[ewaggle] Please specify a spell number.")
        return
    end
    if table_contains(settings.cast_list, spell_num) then
        respond(string.format("[ewaggle] %d is already in the cast list.", spell_num))
        return
    end
    table.insert(settings.cast_list, spell_num)
    table.sort(settings.cast_list)
    save_all_settings()
    respond(string.format("[ewaggle] Added %d to cast list.", spell_num))
end

local function cmd_delete(spell_num)
    spell_num = tonumber(spell_num)
    if not spell_num then
        respond("[ewaggle] Please specify a spell number.")
        return
    end
    for i = #settings.cast_list, 1, -1 do
        if settings.cast_list[i] == spell_num then
            table.remove(settings.cast_list, i)
        end
    end
    save_all_settings()
    respond(string.format("[ewaggle] Removed %d from cast list.", spell_num))
end

--------------------------------------------------------------------------------
-- Process CLI Options
--------------------------------------------------------------------------------

local function process_cli()
    local args = Script.args or {}
    for _, arg in ipairs(args) do
        local key, val = arg:match("^%-%-(.+)=(.+)$")
        if key and val then
            key = key:gsub("%-", "_")
            if key == "start_at" then settings.start_at = tonumber(val) or settings.start_at
            elseif key == "stop_at" then settings.stop_at = tonumber(val) or settings.stop_at
            elseif key == "refreshable_min" then settings.refreshable_min = tonumber(val) or settings.refreshable_min
            elseif key == "reserve_mana" then settings.reserve_mana = tonumber(val) or settings.reserve_mana
            elseif key == "multicast" or key == "use_multicast" then settings.use_multicast = (val == "on" or val == "true")
            elseif key == "wracking" or key == "use_wracking" then settings.use_wracking = (val == "on" or val == "true")
            elseif key == "bail" or key == "bail_no_mana" then settings.bail_no_mana = (val == "on" or val == "true")
            elseif key == "use_203" or key == "use203" then settings.use_203 = (val == "on" or val == "true")
            elseif key == "use_515" or key == "use515" then settings.use_515 = (val == "on" or val == "true")
            elseif key == "cast_list" then
                settings.cast_list = {}
                for n in val:gmatch("%d+") do
                    table.insert(settings.cast_list, tonumber(n))
                end
            end
        elseif arg == "--save" then
            save_all_settings()
            respond("[ewaggle] Settings saved.")
        end
    end
end

--------------------------------------------------------------------------------
-- Build Target List
--------------------------------------------------------------------------------

local function build_targets(args)
    local targets = {}

    -- Filter out CLI flags
    local names = {}
    for _, arg in ipairs(args) do
        if not arg:match("^%-%-") then
            table.insert(names, arg)
        end
    end

    if #names == 0 then
        return { GameState.char_name }
    end

    for _, name in ipairs(names) do
        if name:lower() == "self" or name:lower() == GameState.char_name:lower() then
            table.insert(targets, GameState.char_name)
        else
            -- Try to find PC in room
            local found = false
            for _, pc in ipairs(GameObj.pcs or {}) do
                if pc.noun and pc.noun:lower():find(name:lower(), 1, true) == 1 then
                    table.insert(targets, pc.noun)
                    found = true
                    break
                end
            end
            if not found then
                respond(string.format("[ewaggle] Bad target: %s", name))
            end
        end
    end

    return targets
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

process_cli()

local args = Script.args or {}
local cmd = args[1] or ""

if cmd:lower() == "help" then
    show_help()
    return
elseif cmd:lower() == "setup" then
    show_list()
    respond("[ewaggle] To change settings, use CLI or set CharSettings directly.")
    respond("[ewaggle] Example: CharSettings['ewaggle_start_at'] = '120'")
    return
elseif cmd:lower() == "list" or cmd:lower() == "show" then
    show_list()
    return
elseif cmd:lower() == "info" then
    local targets = build_targets({ table.unpack(args, 2) })
    if #targets == 0 then targets = { GameState.char_name } end
    show_info(targets)
    return
elseif Regex.test(cmd:lower(), "^add$") then
    for i = 2, #args do
        cmd_add(args[i])
    end
    return
elseif Regex.test(cmd:lower(), "^del|^rem|^delete|^remove") then
    for i = 2, #args do
        cmd_delete(args[i])
    end
    return
end

-- Default: cast spells on targets
skip_spells = {}
skip_targets = {}

local targets = build_targets(args)
if #targets == 0 then targets = { GameState.char_name } end

for _, target in ipairs(targets) do
    local info = get_target_info(target)

    if not cast_stackable(target, info) then return end
    if not cast_refreshable(target, info) then return end
    if not cast_solid(target, info) then return end
    cast_disk(target)
end

respond("[ewaggle] Done.")
