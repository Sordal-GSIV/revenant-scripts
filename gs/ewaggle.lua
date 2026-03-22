--- @revenant-script
--- @lic-certified: complete 2026-03-18
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
---   ;ewaggle setup         -- show settings GUI
---   ;ewaggle list          -- show current settings
---   ;ewaggle info          -- show what will be cast
---   ;ewaggle <name> ...    -- spell up given people

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SCRIPT_NAME = "ewaggle"
local SHORT_SPELL_TIME = 3
local BARD_CIRCLE = "12"  -- Bard Base circle in GemStone

-- Disk noun patterns
local DISK_NOUNS = "bassinet|cassone|chest|coffer|coffin|coffret|disk|hamper|saucer|sphere|trunk|tureen"

-- Valid retribution spells for Cloak of Shadows (712)
local VALID_RETRIBUTION_SPELLS = {
    ["701"]=true, ["702"]=true, ["703"]=true, ["705"]=true, ["706"]=true,
    ["708"]=true, ["711"]=true, ["713"]=true, ["715"]=true, ["716"]=true,
    ["717"]=true, ["718"]=true, ["719"]=true, ["740"]=true,
    ["102"]=true, ["106"]=true, ["110"]=true, ["111"]=true, ["118"]=true,
    ["119"]=true, ["130"]=true,
    ["409"]=true, ["412"]=true, ["413"]=true, ["415"]=true, ["417"]=true,
}

-- Armor buff spells (number/name pairs)
local ARMOR_SPELLS = {
    { name = "Armor Blessing",      num = 9510 },
    { name = "Armored Casting",     num = 9506 },
    { name = "Armored Evasion",     num = 9505 },
    { name = "Armored Fluidity",    num = 9507 },
    { name = "Armor Reinforcement", num = 9509 },
    { name = "Armored Stealth",     num = 9508 },
    { name = "Armor Support",       num = 9504 },
}

local BREAD_NOUNS = "flatbread|teacake|crisps|cake|waybread|biscuit|oatcake|fritter|loaf|ball|cornmeal|wheatberries|cracker|dumpling|bread|tart|dough|seeds"

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
    cast_list         = load_json(SCRIPT_NAME .. "_cast_list", DEFAULT_CAST_LIST),
    start_at          = load_setting("start_at", 180),
    stop_at           = load_setting("stop_at", 180),
    refreshable_min   = load_setting("refreshable_min", 15),
    use_multicast     = load_setting("use_multicast", true),
    use_wracking      = load_setting("use_wracking", false),
    wander_to_wrack   = load_setting("wander_to_wrack", false),
    use_power         = load_setting("use_power", false),
    use_mana          = load_setting("use_mana", false),
    use_concentration = load_setting("use_concentration", false),
    skip_short_spells = load_setting("skip_short_spells", false),
    skip_not_sharing  = load_setting("skip_not_sharing", false),
    bail_no_mana      = load_setting("bail_no_mana", false),
    reserve_mana      = load_setting("reserve_mana", 0),
    retribution_spell = load_setting("retribution_spell", ""),
    use_203           = load_setting("use_203", false),
    use_515           = load_setting("use_515", false),
    sonic_weapon      = load_setting("sonic_weapon", ""),
    sonic_shield      = load_setting("sonic_shield", ""),
    sonic_armor       = load_setting("sonic_armor", ""),
    armor_min         = load_setting("armor_min", 15),
    skip_armor        = false,  -- CLI-only, not persisted
}

-- Validate retribution spell
if settings.retribution_spell ~= "" and not VALID_RETRIBUTION_SPELLS[tostring(settings.retribution_spell)] then
    respond(string.format(" %s is not a valid retribution spell.", settings.retribution_spell))
    respond(" Please visit https://gswiki.play.net/Cloak_of_Shadows_(712) for a complete list")
    settings.retribution_spell = ""
end

-- Build armor list from known armor spells
local armor_list = {}
local function build_armor_list()
    armor_list = {}
    for _, asp in ipairs(ARMOR_SPELLS) do
        if Armor and Armor.known and Armor.known(asp.name) then
            table.insert(armor_list, { name = asp.name, num = asp.num })
        end
    end
end
build_armor_list()

local skip_spells = {}
local skip_targets = {}

--------------------------------------------------------------------------------
-- Spell API Helpers
--
-- Revenant exposes spell data as TABLE FIELDS (boolean/integer/string),
-- not as method calls. spell:affordable() and spell:time_per() ARE methods
-- (defined in lib/gs/spell_casting.lua), but fields like known, active,
-- stackable, refreshable, multicastable, num, name, circle, circle_name
-- are plain table fields and must NOT be called with ().
--------------------------------------------------------------------------------

--- Returns evaluated mana cost for a spell (integer).
local function spell_mana_cost(spell)
    local costs = spell:cost()
    return costs and costs.mana or 0
end

--- Returns true if the spell can be cast at the given target.
--- Approximates Lich5's spell.available?(:target => name).
local function spell_available(spell, target)
    if not spell.known then return false end
    -- Self-cast only spells cannot be cast on others
    if spell.availability == "self-cast" and target ~= GameState.name then
        return false
    end
    return true
end

--- Returns true if the spell is in the known cast list.
local function is_known_spell(num)
    local spell = Spell[num]
    if not spell then return false end
    if num == 511 then return spell.known end  -- disk: always include if known
    return spell.known and spell:time_per() > 0
end

--- Coerce a spell number or table to a spell table.
local function fix_spell(spell)
    if type(spell) == "number" or (type(spell) == "string" and spell:match("^%d+$")) then
        return Spell[tonumber(spell)]
    end
    return spell
end

--- Returns the filtered list of spells the character actually knows.
local function get_cast_list()
    local list = {}
    for _, num in ipairs(settings.cast_list) do
        if type(num) == "number" and is_known_spell(num) then
            table.insert(list, num)
        end
    end
    return list
end

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

local function save_all_settings()
    save_json(SCRIPT_NAME .. "_cast_list", settings.cast_list)
    for _, key in ipairs({"start_at", "stop_at", "refreshable_min", "armor_min",
                          "use_multicast", "use_wracking", "wander_to_wrack", "use_power",
                          "use_mana", "use_concentration", "skip_short_spells", "skip_not_sharing",
                          "bail_no_mana", "reserve_mana", "retribution_spell",
                          "use_203", "use_515", "sonic_weapon", "sonic_shield", "sonic_armor"}) do
        save_setting(key, settings[key])
    end
end

--------------------------------------------------------------------------------
-- Mana Management
--------------------------------------------------------------------------------

local function check_stamina(spell, num_multicast)
    num_multicast = num_multicast or 1
    local mana_per_cast = spell_mana_cost(spell)
    local stamina_cost = (mana_per_cast * num_multicast * 2) + settings.reserve_mana
    if spell:affordable() and (mana_per_cast == 0 or GameState.stamina >= stamina_cost) then
        return true
    end
    if settings.bail_no_mana then
        echo("Out of stamina, bailing out!")
        return false
    end
    echo("Waiting for stamina...")
    while not (spell:affordable() and (mana_per_cast == 0 or GameState.stamina >= stamina_cost)) do
        pause(1)
    end
    return true
end

local function safe_to_wrack()
    local pcs = GameObj.pcs() or {}
    if #pcs == 0 then return true end
    fput("sign of recognition")
    pause(1)
    local recent = reget(20) or {}
    local acknowledgers = 0
    for _, line in ipairs(recent) do
        if string.find(line, "acknowledges your sign") then
            acknowledgers = acknowledgers + 1
        end
    end
    return acknowledgers >= #pcs
end

local function wander_for_wrack()
    if not settings.wander_to_wrack then return false end
    local start_room = GameState.room_id
    local visited = {}
    local found = false
    for _ = 1, 20 do
        if safe_to_wrack() then
            found = true
            break
        end
        local room = Room.current()
        if room and room.wayto then
            local options = {}
            for dest_id, cmd in pairs(room.wayto) do
                if type(cmd) == "string" and not visited[dest_id] then
                    table.insert(options, { id = dest_id, cmd = cmd })
                end
            end
            if #options == 0 then break end
            local choice = options[math.random(#options)]
            visited[choice.id] = true
            move(choice.cmd)
        else
            break
        end
    end
    return found, start_room
end

local function check_mana(spell, num_multicast)
    num_multicast = num_multicast or 1

    -- Monk mental acuity: use stamina path instead
    if Feat and Feat.known and Feat.known("mental_acuity") then
        return check_stamina(spell, num_multicast)
    end

    local mana_per_cast = spell_mana_cost(spell)
    local spell_cost = mana_per_cast * num_multicast + settings.reserve_mana

    if spell:affordable() and (mana_per_cast == 0 or GameState.mana >= spell_cost) then
        return true
    end
    if mana_per_cast <= 0 then return true end

    -- Society abilities
    if settings.use_wracking then
        -- Council of Light: Sign of Wracking (9918)
        local sign_of_wracking = Spell[9918]
        local punishment = Spell[9012]
        if sign_of_wracking and sign_of_wracking:affordable() and
           (not punishment or not punishment.active) then
            local can_wrack = (GameState.hidden or GameState.invisible or
                               not GameObj.pcs() or #(GameObj.pcs() or {}) == 0 or
                               safe_to_wrack())
            if can_wrack then
                sign_of_wracking:cast()
                if spell:affordable() and GameState.mana >= spell_cost then return true end
            elseif settings.wander_to_wrack then
                local found, start_room = wander_for_wrack()
                if found then
                    sign_of_wracking = Spell[9918]
                    punishment = Spell[9012]
                    if sign_of_wracking and sign_of_wracking:affordable() and
                       (not punishment or not punishment.active) then
                        sign_of_wracking:cast()
                    end
                end
                if start_room and GameState.room_id ~= start_room then
                    Script.run("go2", tostring(start_room) .. " --disable-confirm")
                end
                if spell:affordable() and GameState.mana >= spell_cost then return true end
            end
        end
    elseif settings.use_power then
        -- Guardians of Sunfist: Sigil of Power (9718)
        local sigil = Spell[9718]
        if sigil and sigil:affordable() then
            sigil:cast()
            pause(0.2)
            if spell:affordable() and GameState.mana >= spell_cost then return true end
        end
    elseif settings.use_mana then
        -- Order of Voln: Symbol of Mana (9813)
        -- Only cast if not on cooldown
        if not Effects.Cooldowns.active("Symbol of Mana") then
            local sym = Spell[9813]
            if sym then
                local result = sym:cast()
                local rs = tostring(result or "")
                if string.find(rs, "strain to perform") then
                    echo("Out of favor! Disabling symbol of mana.")
                    settings.use_mana = false
                end
                pause(0.2)
                if spell:affordable() and GameState.mana >= spell_cost then return true end
            end
        end
    end

    -- Wait for mana
    if settings.bail_no_mana then
        echo("Out of mana/resources, bailing out!")
        return false
    end

    -- Release any prepared spell before waiting
    if GameState.prepared_spell then
        fput("release")
    end

    echo("Waiting for mana...")
    while not spell:affordable() or (mana_per_cast > 0 and GameState.mana < spell_cost) do
        waitrt()
        waitcastrt()
        pause(1)
    end
    return true
end

--------------------------------------------------------------------------------
-- Casting Support
--------------------------------------------------------------------------------

local function eat_bread(bypass_check)
    if not bypass_check and not settings.use_203 then return end
    -- Check if Manna (203) effect has enough time left
    if Effects.Spells.time_left("Manna") > 10 then return end

    if empty_hand then empty_hand() end

    local manna_spell = Spell[203]
    if manna_spell then manna_spell:cast() end

    -- Find bread in hands
    local bread = nil
    for _, hand in ipairs({GameObj.right_hand(), GameObj.left_hand()}) do
        if hand and hand.noun and Regex.test("^(?:" .. BREAD_NOUNS .. ")$", hand.noun) then
            bread = hand
            break
        end
    end

    if bread then
        for _ = 1, 20 do
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            local still_held = (rh and rh.id == bread.id) or (lh and lh.id == bread.id)
            if not still_held then break end
            fput("gobble #" .. bread.id)
            pause(0.2)
        end
    end

    -- Wait briefly for Manna effect to register
    for _ = 1, 20 do
        if Effects.Spells.time_left("Manna") > 0 then break end
        pause(0.1)
    end

    if fill_hand then fill_hand() end
end

local function mana_bread_for_target(target)
    if target == GameState.name then
        eat_bread(true)
    else
        if empty_hand then empty_hand() end
        local manna_spell = Spell[203]
        if manna_spell then manna_spell:cast() end

        local bread = nil
        for _, hand in ipairs({GameObj.right_hand(), GameObj.left_hand()}) do
            if hand and hand.noun and Regex.test("^(?:" .. BREAD_NOUNS .. ")$", hand.noun) then
                bread = hand
                break
            end
        end

        if bread then
            for _ = 1, 20 do
                local rh = GameObj.right_hand()
                local lh = GameObj.left_hand()
                local still_held = (rh and rh.id == bread.id) or (lh and lh.id == bread.id)
                if not still_held then break end
                fput("drop #" .. bread.id)
                pause(0.2)
            end
        end

        if fill_hand then fill_hand() end
    end
end

local function cast_support()
    -- Sigil of Concentration (9714)
    local conc = Spell[9714]
    if settings.use_concentration and conc and conc:affordable() and not conc.active then
        conc:cast()
    end

    -- Manna bread (203)
    if settings.use_203 then
        local manna = Spell[203]
        if manna and manna:affordable() then
            eat_bread()
        end
    end

    -- Rapid Fire (515)
    local rf = Spell[515]
    if settings.use_515 and rf and rf:affordable() and not rf.active then
        rf:cast()
    end
end

--- Compute max multicast count based on profession and mana control skills.
local function max_multicast(spell)
    local ranks = 0
    local prof = Stats.prof
    local emc = Skills.emc or 0
    local smc = Skills.smc or 0
    local mmc = Skills.mmc or 0
    local circle = tonumber(spell.circle) or 0

    if prof == "Wizard" then
        ranks = emc
    elseif prof == "Cleric" or prof == "Ranger" or prof == "Paladin" then
        ranks = smc
    elseif prof == "Empath" or prof == "Monk" or prof == "Bard" then
        if circle == 1 or circle == 2 then
            ranks = smc + math.floor(mmc / 2)
        elseif circle == 11 then
            ranks = math.max(mmc, smc) + math.floor(math.min(mmc, smc) / 2)
        elseif circle == 12 then
            ranks = mmc + math.floor(smc / 2)
        elseif circle == 4 then
            ranks = emc + math.floor(mmc / 2)
        end
    elseif prof == "Sorcerer" or prof == "Warrior" or prof == "Rogue" then
        if circle == 4 then
            ranks = emc + math.floor(smc / 2)
        elseif circle == 1 then
            ranks = smc + math.floor(emc / 2)
        elseif circle == 7 then
            ranks = math.max(emc, smc) + math.floor(math.min(emc, smc) / 2)
        end
    end

    return math.floor(ranks / 25) + 1
end

local function cast_spell(spell, target, num_multicast)
    num_multicast = num_multicast or 1

    if not spell or not spell.known then return "bad_spell" end
    if not check_mana(spell, num_multicast) then return "bail" end

    local cast_result
    if target == GameState.name then
        if spell.num == 1009 and settings.sonic_shield ~= "" then
            cast_result = spell:cast(settings.sonic_shield)
        elseif spell.num == 1012 and settings.sonic_weapon ~= "" then
            cast_result = spell:cast(settings.sonic_weapon)
        elseif spell.num == 1014 and settings.sonic_armor ~= "" then
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
    if string.find(result_str, "no need for spells of war") or
       string.find(result_str, "Spells of War cannot be cast") then
        return "bad_spell"
    elseif string.find(result_str, "Cast at what") then
        return "bad_target"
    elseif string.find(result_str, "%[Spell Hindrance") then
        return cast_spell(spell, target, num_multicast)  -- retry on hindrance
    end

    return "success"
end

--------------------------------------------------------------------------------
-- Target Info
--------------------------------------------------------------------------------

local function get_self_info()
    local info = {}
    local active = Spell.active and Spell.active() or {}
    for _, spell in ipairs(active) do
        if spell.num then
            info[tostring(spell.num)] = spell.timeleft
        end
    end
    info.sharing = true
    return info
end

local function get_target_info(target)
    if target == GameState.name then
        return get_self_info()
    end

    local info = {}
    clear()
    put("spell active " .. target)

    local timeout_at = os.time() + 5
    local found_header = false
    local privacy = false

    while os.time() < timeout_at do
        local line = get_noblock()
        if not line then
            pause(0.1)
        else
            if string.find(line, "has spell sharing disabled") then
                privacy = true
                break
            end
            if string.find(line, "currently has the following active effects") then
                found_header = true
            end
            if found_header then
                -- Parse spell lines: "  Spirit Warding I ...... 3:42:15" or "Indefinite"
                local spell_name, time_str = line:match("^%s+(.-)%s+%.+%s+(%d+:%d+:%d+)$")
                if not spell_name then
                    local sn = line:match("^%s+(.-)%s+%.+%s+(Indefinite)$")
                    if sn then spell_name, time_str = sn, "Indefinite" end
                end
                if spell_name then
                    spell_name = spell_name:match("^%s*(.-)%s*$")
                    local spell_time = 599.0
                    if time_str ~= "Indefinite" then
                        local h, m, s = time_str:match("(%d+):(%d+):(%d+)")
                        spell_time = tonumber(h)*60 + tonumber(m) + tonumber(s)/60.0
                    end
                    -- Normalize special names
                    if spell_name == "Raise Dead Recovery" then
                        spell_name = "Raise Dead Cooldown"
                    elseif spell_name:find("Mage Armor %- ") then
                        spell_name = "Mage Armor"
                    elseif spell_name:find("Cloak of Shadows %- ") then
                        spell_name = "Cloak of Shadows"
                    end
                    local sp = Spell[spell_name]
                    if sp then
                        info[tostring(sp.num)] = spell_time
                    end
                end
                -- End of spell list: blank line after header
                if line == "" and found_header then break end
            end
        end
    end

    if privacy then
        info.sharing = false
        if settings.skip_not_sharing then
            return nil
        else
            respond("")
            respond(string.format(" %s is not sharing spell information using SPELL PRIVACY", target))
            respond(" A single cast of each spell will be used instead.")
            respond(" To skip characters that don't share, toggle 'skip not sharing' in settings.")
            respond("")
            return info
        end
    end

    info.sharing = true
    return info
end

--------------------------------------------------------------------------------
-- Casting Phases
--------------------------------------------------------------------------------

local function cast_stackable(target, info)
    local cast_list = get_cast_list()

    -- Sort 625 (Protection from Evil) first so the DS bonus applies immediately
    table.sort(cast_list, function(a, b)
        if a == 625 then return true end
        if b == 625 then return false end
        return a < b
    end)

    for _, spell_num in ipairs(cast_list) do
        local spell = fix_spell(spell_num)
        if not spell then goto continue end

        if not spell.stackable then goto continue end
        if not spell_available(spell, target) and spell.num ~= 203 then goto continue end
        if spell:time_per() <= SHORT_SPELL_TIME and spell.num ~= 203 and
           target ~= GameState.name and settings.skip_short_spells then goto continue end
        if table_contains(skip_spells, spell.num) or table_contains(skip_targets, target) then
            goto continue
        end
        -- Skip active Bard songs when casting on self
        if target == GameState.name and spell.circle == BARD_CIRCLE and spell.active then
            goto continue
        end

        local existing = info[tostring(spell.num)] or 0
        if existing > settings.start_at and spell.num ~= 203 then goto continue end

        cast_support()

        -- Special handling for 203 mana bread
        if spell.num == 203 then
            mana_bread_for_target(target)
            goto continue
        end

        local mc = max_multicast(spell)

        while (info[tostring(spell.num)] or 0) < settings.stop_at do
            if table_contains(skip_targets, target) or table_contains(skip_spells, spell.num) then
                break
            end

            local remaining = settings.stop_at - (info[tostring(spell.num)] or 0)
            local needed = math.ceil(remaining / spell:time_per())
            local casts = math.min(needed, mc)
            if casts <= 0 then break end

            -- Only multicast if setting is on, spell supports it, and target is sharing
            if not settings.use_multicast or not spell.multicastable or
               (not info.sharing and target ~= GameState.name) then
                casts = 1
            end

            local result = cast_spell(spell, target, casts)
            if result == "bad_spell" then
                table.insert(skip_spells, spell.num)
                break
            elseif result == "bad_target" then
                table.insert(skip_targets, target)
                break
            elseif result == "bail" then
                return false
            else
                info[tostring(spell.num)] = (info[tostring(spell.num)] or 0) +
                                             spell:time_per() * casts
            end

            if not info.sharing then break end
        end

        -- Retribution chant after Cloak of Shadows (712)
        if spell.num == 712 and target == GameState.name and settings.retribution_spell ~= "" then
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

        if spell.stackable then goto continue end
        if not spell_available(spell, target) then goto continue end
        if spell:time_per() <= SHORT_SPELL_TIME and target ~= GameState.name and
           settings.skip_short_spells then goto continue end
        if table_contains(skip_spells, spell.num) or table_contains(skip_targets, target) then
            goto continue
        end
        -- Skip active Bard songs on self
        if target == GameState.name and spell.circle == BARD_CIRCLE and spell.active then
            goto continue
        end

        local existing = info[tostring(spell.num)] or 0
        if existing > settings.refreshable_min then goto continue end

        cast_support()

        local result = cast_spell(spell, target)
        if result == "bad_spell" then
            table.insert(skip_spells, spell.num)
        elseif result == "bad_target" then
            table.insert(skip_targets, target)
        elseif result == "bail" then
            return false
        end

        ::continue::
    end

    -- Armor buff support
    if not settings.skip_armor and Armor and Armor.use then
        for _, buff in ipairs(armor_list) do
            local spell = Spell[buff.num]
            if spell then
                local existing = info[tostring(buff.num)] or 0
                if existing <= settings.armor_min then
                    -- Armor buffs use stamina; always check regardless of class
                    check_stamina(spell, 1)
                    Armor.use(buff.name, target)
                end
            end
        end
    end

    return true
end

local function cast_solid(target, info)
    local cast_list = get_cast_list()

    for _, spell_num in ipairs(cast_list) do
        local spell = fix_spell(spell_num)
        if not spell then goto continue end

        if spell.stackable or spell.refreshable then goto continue end
        if not spell_available(spell, target) then goto continue end
        if spell:time_per() <= SHORT_SPELL_TIME and target ~= GameState.name and
           settings.skip_short_spells then goto continue end
        if table_contains(skip_spells, spell.num) or table_contains(skip_targets, target) then
            goto continue
        end
        -- Skip active Bard songs on self
        if target == GameState.name and spell.circle == BARD_CIRCLE and spell.active then
            goto continue
        end

        local existing = info[tostring(spell.num)] or 0
        if existing > 0 then goto continue end

        cast_support()

        local result = cast_spell(spell, target)
        if result == "bad_spell" then
            table.insert(skip_spells, spell.num)
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

    -- Check if disk already exists in room
    for _, loot in ipairs(GameObj.loot() or {}) do
        if loot.name then
            local name_lower = loot.name:lower()
            local target_lower = target:lower()
            if string.find(name_lower, target_lower, 1, true) and
               Regex.test(DISK_NOUNS, name_lower) then
                return true
            end
        end
    end

    local result = cast_spell(spell, target)
    if result == "bad_spell" then
        table.insert(skip_spells, spell.num)
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
    respond("=== Ewaggle v2.1.5 Help ===")
    respond("  ;ewaggle               -- spell yourself up")
    respond("  ;ewaggle help          -- this message")
    respond("  ;ewaggle setup         -- configure settings (GUI)")
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
    respond("    --skip-armor  (skip armor buffs this run)")
    respond("    Sonic gear: --cast-list=1009(\"tower shield\")")
    respond("===========================")
    respond("")
end

local function show_list()
    respond("")
    respond("=== Ewaggle v2.1.5 Settings ===")
    respond(string.format("  %-28s %s", "start at:",            tostring(settings.start_at)))
    respond(string.format("  %-28s %s", "stop at:",             tostring(settings.stop_at)))
    respond(string.format("  %-28s %s", "refreshable min:",     tostring(settings.refreshable_min)))
    respond(string.format("  %-28s %s", "armor min:",           tostring(settings.armor_min)))
    respond(string.format("  %-28s %s", "multicast:",           tostring(settings.use_multicast)))
    respond(string.format("  %-28s %s", "sign of wracking:",    tostring(settings.use_wracking)))
    respond(string.format("  %-28s %s", "wander to wrack:",     tostring(settings.wander_to_wrack)))
    respond(string.format("  %-28s %s", "sigil of power:",      tostring(settings.use_power)))
    respond(string.format("  %-28s %s", "sigil of concentration:", tostring(settings.use_concentration)))
    respond(string.format("  %-28s %s", "symbol of mana:",      tostring(settings.use_mana)))
    respond(string.format("  %-28s %s", "skip short spells:",   tostring(settings.skip_short_spells)))
    respond(string.format("  %-28s %s", "skip not sharing:",    tostring(settings.skip_not_sharing)))
    respond(string.format("  %-28s %s", "reserve mana:",        tostring(settings.reserve_mana)))
    respond(string.format("  %-28s %s", "bail no resources:",   tostring(settings.bail_no_mana)))
    respond(string.format("  %-28s %s", "use mana bread (203):", tostring(settings.use_203)))
    respond(string.format("  %-28s %s", "use rapid fire (515):", tostring(settings.use_515)))
    local ret = settings.retribution_spell ~= "" and settings.retribution_spell or "none"
    respond(string.format("  %-28s %s", "retribution spell:",   ret))
    if settings.sonic_shield ~= "" then
        respond(string.format("  %-28s %s", "sonic shield (1009):", settings.sonic_shield))
    end
    if settings.sonic_weapon ~= "" then
        respond(string.format("  %-28s %s", "sonic weapon (1012):", settings.sonic_weapon))
    end
    if settings.sonic_armor ~= "" then
        respond(string.format("  %-28s %s", "sonic armor (1014):",  settings.sonic_armor))
    end

    local cast_nums = {}
    for _, n in ipairs(get_cast_list()) do
        table.insert(cast_nums, tostring(n))
    end
    respond(string.format("  %-28s %s", "cast list:", table.concat(cast_nums, ", ")))
    respond("================================")
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
        respond(string.format("  %-6s %-30s %5s %6s", "Spell", "Name", "Casts", "Mana"))
        respond(string.rep("-", 55))

        for _, spell_num in ipairs(cast_list) do
            local spell = fix_spell(spell_num)
            if not spell then goto continue end
            if not spell_available(spell, target) then goto continue end

            local existing = info[tostring(spell.num)] or 0
            local casts = 0

            if spell.stackable then
                if existing < settings.start_at then
                    local tper = spell:time_per()
                    if tper > 0 then
                        casts = math.ceil((settings.stop_at - existing) / tper)
                    end
                end
            elseif spell.refreshable then
                if existing < settings.refreshable_min then casts = 1 end
            else
                if existing <= 0 then casts = 1 end
            end

            if casts > 0 then
                local mc = spell_mana_cost(spell) * casts
                total_casts = total_casts + casts
                total_mana = total_mana + mc
                respond(string.format("  %-6d %-30s %5d %6d",
                    spell.num, spell.name, casts, mc))
            end
            ::continue::
        end

        respond(string.rep("-", 55))
        respond(string.format("  %-37s %5d %6d", "Total:", total_casts, total_mana))
        respond("========================")
    end
end

local function cmd_add(spell_num_str)
    local spell_num = tonumber(spell_num_str)
    if not spell_num then
        respond("[ewaggle] Please specify a spell number.")
        return
    end
    if table_contains(settings.cast_list, spell_num) then
        respond(string.format("[ewaggle] %d is already in the cast list.", spell_num))
        return
    end
    local spell = Spell[spell_num]
    if spell then
        respond(string.format("[ewaggle] Adding %d %s to cast list.", spell_num, spell.name))
    end
    table.insert(settings.cast_list, spell_num)
    table.sort(settings.cast_list)
    save_all_settings()
    respond(string.format("[ewaggle] Added %d to cast list.", spell_num))
end

local function cmd_delete(spell_num_str)
    local spell_num = tonumber(spell_num_str)
    if not spell_num then
        respond("[ewaggle] Please specify a spell number.")
        return
    end
    local removed = false
    for i = #settings.cast_list, 1, -1 do
        if settings.cast_list[i] == spell_num then
            table.remove(settings.cast_list, i)
            removed = true
        end
    end
    if removed then
        save_all_settings()
        respond(string.format("[ewaggle] Removed %d from cast list.", spell_num))
    else
        respond(string.format("[ewaggle] %d was not in the cast list.", spell_num))
    end
end

--------------------------------------------------------------------------------
-- GUI Setup Window
--------------------------------------------------------------------------------

local function show_setup_gui()
    -- Build two spell sets: those in cast list and those not
    -- Format: "NNNN  Name"
    local function spell_entry(num)
        local sp = Spell[num]
        if sp then
            return string.format("%d  %s", num, sp.name)
        end
        return tostring(num)
    end

    -- All known buff spells for "not to cast" pool
    local all_buff_nums = {}
    local in_cast = {}
    for _, num in ipairs(settings.cast_list) do
        in_cast[num] = true
    end

    -- Collect all known spells with duration (plus disk 511)
    for num = 1, 2000 do
        local sp = Spell[num]
        if sp and sp.known and (sp:time_per() > 0 or num == 511) and not in_cast[num] then
            table.insert(all_buff_nums, num)
        end
    end
    table.sort(all_buff_nums)

    -- Working copies for the two lists
    local cast_nums = {}
    for _, n in ipairs(settings.cast_list) do
        table.insert(cast_nums, n)
    end
    table.sort(cast_nums)

    local not_cast_nums = all_buff_nums

    -- Build row tables for tree_view
    local function make_rows(nums)
        local rows = {}
        for _, n in ipairs(nums) do
            table.insert(rows, { spell_entry(n) })
        end
        return rows
    end

    local win = Gui.window("Ewaggle Setup v2.1.5", { width = 850, height = 700, resizable = true })
    local root_vbox = Gui.vbox()

    -- Tabs: Spell Lists | Options
    local tabs = Gui.tab_bar({ "Spell Lists", "Options" })

    ---- Tab 1: Spell Lists ----
    local split = Gui.split_view({ direction = "horizontal", fraction = 0.5 })

    local left_vbox = Gui.vbox()
    left_vbox:add(Gui.section_header("Spells Not to Cast  (double-click to add)"))
    local not_cast_tv = Gui.tree_view({ columns = { "Spell" }, rows = make_rows(not_cast_nums) })
    left_vbox:add(Gui.scroll(not_cast_tv))

    local right_vbox = Gui.vbox()
    right_vbox:add(Gui.section_header("Spells to Cast  (double-click to remove)"))
    local cast_tv = Gui.tree_view({ columns = { "Spell" }, rows = make_rows(cast_nums) })
    right_vbox:add(Gui.scroll(cast_tv))

    split:set_first(left_vbox)
    split:set_second(right_vbox)
    tabs:set_tab_content(1, split)

    -- Helper to refresh both tree_views
    local function refresh_lists()
        table.sort(cast_nums)
        table.sort(not_cast_nums)
        not_cast_tv:set_rows(make_rows(not_cast_nums))
        cast_tv:set_rows(make_rows(cast_nums))
    end

    -- Double-click: move from not-cast → cast
    not_cast_tv:on_double_click(function()
        local sel = not_cast_tv:get_selected()
        if not sel then return end
        -- sel is the row data: sel[1] = "NNNN  Name"
        local entry = type(sel) == "table" and sel[1] or tostring(sel)
        local num = tonumber(entry:match("^(%d+)"))
        if not num then return end
        -- Move num from not_cast_nums to cast_nums
        for i = #not_cast_nums, 1, -1 do
            if not_cast_nums[i] == num then
                table.remove(not_cast_nums, i)
                break
            end
        end
        if not table_contains(cast_nums, num) then
            table.insert(cast_nums, num)
        end
        refresh_lists()
    end)

    -- Double-click: move from cast → not-cast
    cast_tv:on_double_click(function()
        local sel = cast_tv:get_selected()
        if not sel then return end
        local entry = type(sel) == "table" and sel[1] or tostring(sel)
        local num = tonumber(entry:match("^(%d+)"))
        if not num then return end
        -- Move num from cast_nums to not_cast_nums
        for i = #cast_nums, 1, -1 do
            if cast_nums[i] == num then
                table.remove(cast_nums, i)
                break
            end
        end
        if not table_contains(not_cast_nums, num) then
            table.insert(not_cast_nums, num)
        end
        refresh_lists()
    end)

    ---- Tab 2: Options ----
    local opts_scroll = Gui.scroll(Gui.vbox())
    local opts_vbox = Gui.vbox()

    -- Stackable thresholds
    opts_vbox:add(Gui.section_header("Stackable Spell Thresholds"))
    local function labeled_input(label_text, value_str)
        local row = Gui.hbox()
        row:add(Gui.label(string.format("%-30s", label_text)))
        local inp = Gui.input({ text = value_str })
        row:add(inp)
        return row, inp
    end

    local row_start, inp_start = labeled_input("Start casting below (min):", tostring(settings.start_at))
    opts_vbox:add(row_start)
    inp_start:on_change(function()
        local v = tonumber(inp_start:get_text())
        if v then settings.start_at = v end
    end)

    local row_stop, inp_stop = labeled_input("Stop casting at (min):", tostring(settings.stop_at))
    opts_vbox:add(row_stop)
    inp_stop:on_change(function()
        local v = tonumber(inp_stop:get_text())
        if v then settings.stop_at = v end
    end)

    local row_ref, inp_ref = labeled_input("Refreshable min (min):", tostring(settings.refreshable_min))
    opts_vbox:add(row_ref)
    inp_ref:on_change(function()
        local v = tonumber(inp_ref:get_text())
        if v then settings.refreshable_min = v end
    end)

    local row_arm, inp_arm = labeled_input("Armor buff min (min):", tostring(settings.armor_min))
    opts_vbox:add(row_arm)
    inp_arm:on_change(function()
        local v = tonumber(inp_arm:get_text())
        if v then settings.armor_min = v end
    end)

    local row_res, inp_res = labeled_input("Reserve mana:", tostring(settings.reserve_mana))
    opts_vbox:add(row_res)
    inp_res:on_change(function()
        local v = tonumber(inp_res:get_text())
        if v then settings.reserve_mana = v end
    end)

    opts_vbox:add(Gui.separator())
    opts_vbox:add(Gui.section_header("General Options"))

    local function add_checkbox(label_text, setting_key)
        local cb = Gui.checkbox(label_text, settings[setting_key])
        cb:on_change(function()
            settings[setting_key] = cb:get_checked()
        end)
        opts_vbox:add(cb)
        return cb
    end

    add_checkbox("Use multicast", "use_multicast")
    add_checkbox("Skip short spells (< 3 min) on others", "skip_short_spells")
    add_checkbox("Skip targets not sharing spell info", "skip_not_sharing")
    add_checkbox("Bail out if out of mana/resources", "bail_no_mana")

    -- Conditional: use_203
    if Spell[203] and Spell[203].known then
        add_checkbox("Cast/eat mana bread (203)", "use_203")
    end

    -- Conditional: use_515
    if Spell[515] and Spell[515].known then
        add_checkbox("Use Rapid Fire (515) before casting", "use_515")
    end

    opts_vbox:add(Gui.separator())
    opts_vbox:add(Gui.section_header("Society Options"))

    -- Society-specific options
    local society = Society and Society.member or ""
    if society == "Council of Light" then
        add_checkbox("Use Sign of Wracking (COL)", "use_wracking")
        add_checkbox("Wander to find safe room to wrack", "wander_to_wrack")
    elseif society == "Guardians of Sunfist" then
        add_checkbox("Use Sigil of Power (GOS)", "use_power")
        add_checkbox("Use Sigil of Concentration (GOS)", "use_concentration")
    elseif society == "Order of Voln" then
        add_checkbox("Use Symbol of Mana (Voln)", "use_mana")
    else
        opts_vbox:add(Gui.label("(No society options available)"))
    end

    -- Conditional: retribution spell (712 known)
    if Spell[712] and Spell[712].known then
        opts_vbox:add(Gui.separator())
        opts_vbox:add(Gui.section_header("Cloak of Shadows (712)"))
        local row_ret, inp_ret = labeled_input("Retribution spell #:", settings.retribution_spell)
        opts_vbox:add(row_ret)
        inp_ret:on_change(function()
            local v = inp_ret:get_text():match("^%s*(.-)%s*$")
            if v == "" or v == "none" or v == "0" then
                settings.retribution_spell = ""
            elseif VALID_RETRIBUTION_SPELLS[v] then
                settings.retribution_spell = v
            else
                respond(string.format("[ewaggle] %s is not a valid retribution spell.", v))
            end
        end)
    end

    -- Sonic gear
    local has_sonic = (Spell[1009] and Spell[1009].known) or
                      (Spell[1012] and Spell[1012].known) or
                      (Spell[1014] and Spell[1014].known)
    if has_sonic then
        opts_vbox:add(Gui.separator())
        opts_vbox:add(Gui.section_header("Sonic Gear"))
        if Spell[1009] and Spell[1009].known then
            local row_ss, inp_ss = labeled_input("Sonic Shield type (1009):", settings.sonic_shield)
            opts_vbox:add(row_ss)
            inp_ss:on_change(function() settings.sonic_shield = inp_ss:get_text() end)
        end
        if Spell[1012] and Spell[1012].known then
            local row_sw, inp_sw = labeled_input("Sonic Weapon type (1012):", settings.sonic_weapon)
            opts_vbox:add(row_sw)
            inp_sw:on_change(function() settings.sonic_weapon = inp_sw:get_text() end)
        end
        if Spell[1014] and Spell[1014].known then
            local row_sa, inp_sa = labeled_input("Sonic Armor type (1014):", settings.sonic_armor)
            opts_vbox:add(row_sa)
            inp_sa:on_change(function() settings.sonic_armor = inp_sa:get_text() end)
        end
    end

    tabs:set_tab_content(2, Gui.scroll(opts_vbox))

    root_vbox:add(tabs)
    root_vbox:add(Gui.separator())

    -- Save & Close button
    local btn_row = Gui.hbox()
    local save_btn = Gui.button("Save & Close")
    save_btn:on_click(function()
        -- Apply spell list changes
        settings.cast_list = {}
        for _, n in ipairs(cast_nums) do
            table.insert(settings.cast_list, n)
        end
        table.sort(settings.cast_list)
        save_all_settings()
        respond("[ewaggle] Settings saved.")
        win:close()
    end)
    local cancel_btn = Gui.button("Cancel")
    cancel_btn:on_click(function()
        respond("[ewaggle] Setup closed without saving.")
        win:close()
    end)
    btn_row:add(save_btn)
    btn_row:add(cancel_btn)
    root_vbox:add(btn_row)

    win:set_root(root_vbox)
    win:show()
    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- Process CLI Options
--------------------------------------------------------------------------------

local function process_cli()
    local args = Script.args or {}
    for _, arg in ipairs(args) do
        -- Handle --key=value flags
        local key, val = arg:match("^%-%-(.+)=(.+)$")
        if key and val then
            key = key:gsub("%-", "_")
            if key == "start_at" then
                settings.start_at = tonumber(val) or settings.start_at
            elseif key == "stop_at" then
                settings.stop_at = tonumber(val) or settings.stop_at
            elseif key == "refreshable_min" or key == "unstackable_min" then
                settings.refreshable_min = tonumber(val) or settings.refreshable_min
            elseif key == "reserve_mana" then
                settings.reserve_mana = tonumber(val) or settings.reserve_mana
            elseif key == "multicast" or key == "use_multicast" then
                settings.use_multicast = (val == "on" or val == "true")
            elseif key == "wracking" or key == "use_wracking" then
                settings.use_wracking = (val == "on" or val == "true")
            elseif key == "wander_to_wrack" then
                settings.wander_to_wrack = (val == "on" or val == "true")
            elseif key == "power" or key == "use_power" then
                settings.use_power = (val == "on" or val == "true")
            elseif key == "mana" or key == "use_mana" then
                settings.use_mana = (val == "on" or val == "true")
            elseif key == "concentration" or key == "use_concentration" then
                settings.use_concentration = (val == "on" or val == "true")
            elseif key == "bail" or key == "bail_no_mana" then
                settings.bail_no_mana = (val == "on" or val == "true")
            elseif key == "skip_short_spells" or key == "skip_short" then
                settings.skip_short_spells = (val == "on" or val == "true")
            elseif key == "skip_not_sharing" then
                settings.skip_not_sharing = (val == "on" or val == "true")
            elseif key == "use_203" or key == "use203" then
                settings.use_203 = (val == "on" or val == "true")
            elseif key == "use_515" or key == "use515" then
                settings.use_515 = (val == "on" or val == "true")
            elseif key == "retribution_spell" then
                if val == "none" or val == "off" or val == "false" then
                    settings.retribution_spell = ""
                elseif VALID_RETRIBUTION_SPELLS[val] then
                    settings.retribution_spell = val
                end
            elseif key == "cast_list" then
                settings.cast_list = {}
                -- Support both plain numbers and sonic-gear notation like 1009("tower shield")
                for item in val:gmatch("[^,]+") do
                    item = item:match("^%s*(.-)%s*$")
                    local num_str, sonic_arg = item:match('^(%d+)%("([^"]+)"%)')
                    if not num_str then
                        num_str, sonic_arg = item:match("^(%d+)%(([^)]+)%)")
                    end
                    if num_str and sonic_arg then
                        local num = tonumber(num_str)
                        if num == 1009 then settings.sonic_shield = sonic_arg
                        elseif num == 1012 then settings.sonic_weapon = sonic_arg
                        elseif num == 1014 then settings.sonic_armor = sonic_arg
                        end
                        if num then table.insert(settings.cast_list, num) end
                    else
                        local n = tonumber(item:match("%d+"))
                        if n then table.insert(settings.cast_list, n) end
                    end
                end
            end
        elseif arg == "--save" then
            save_all_settings()
            respond("[ewaggle] Settings saved.")
        elseif arg == "--skip-armor" then
            settings.skip_armor = true
        end
    end
end

--------------------------------------------------------------------------------
-- Build Target List
--------------------------------------------------------------------------------

local function build_targets(args)
    -- Filter out CLI flags (start with --)
    local names = {}
    for _, arg in ipairs(args) do
        if not arg:match("^%-%-") then
            table.insert(names, arg)
        end
    end

    if #names == 0 then
        return { GameState.name }
    end

    local targets = {}
    for _, name in ipairs(names) do
        if name:lower() == "self" or name:lower() == GameState.name:lower() then
            table.insert(targets, GameState.name)
        else
            local found = false
            for _, pc in ipairs(GameObj.pcs() or {}) do
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

before_dying(function()
    -- Settings reload on next run from storage
end)

local args = Script.args or {}
local cmd = (args[1] or ""):lower()

if cmd == "help" then
    show_help()
    return
elseif cmd == "setup" then
    show_setup_gui()
    return
elseif cmd == "list" or cmd == "show" then
    show_list()
    return
elseif cmd == "info" then
    local info_targets = build_targets({ table.unpack(args, 2) })
    if #info_targets == 0 then info_targets = { GameState.name } end
    show_info(info_targets)
    return
elseif cmd == "add" then
    for i = 2, #args do
        cmd_add(args[i])
    end
    return
elseif cmd:match("^del") or cmd:match("^rem") then
    for i = 2, #args do
        cmd_delete(args[i])
    end
    return
end

-- Default: spell up targets
skip_spells = {}
skip_targets = {}

local targets = build_targets(args)
if #targets == 0 then targets = { GameState.name } end

for _, target in ipairs(targets) do
    local info = get_target_info(target)

    if info then
        if not cast_stackable(target, info) then return end
        if not cast_refreshable(target, info) then return end
        if not cast_solid(target, info) then return end
        cast_disk(target)
    end
end

respond("[ewaggle] Done.")
