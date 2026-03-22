-- osacombat/spells.lua — Spell casting, buff management, and spell openers
-- Original: osacombat.lic by OSA (GemStone IV automated combat)
-- Handles combat spells, society abilities, group buffs, warcries,
-- combat techniques, and gemstone activations.

local M = {}

---------------------------------------------------------------------------
-- Module-level timers (os.time based) for timed buffs
---------------------------------------------------------------------------
local timers = {
    bravery           = 0,
    group_celerity    = 0,
    group_barkskin    = 0,
    heroism           = 0,
}

---------------------------------------------------------------------------
-- Tracked empathic link targets (for opener spells 1117/1614/217/512/611/603)
---------------------------------------------------------------------------
local empathic_link_targets = {}

---------------------------------------------------------------------------
-- Helper: check if character can act (not stunned/webbed/bound/dead)
---------------------------------------------------------------------------
local function can_act()
    return not stunned()
        and not webbed()
        and not bound()
        and not dead()
        and standing()
end

---------------------------------------------------------------------------
-- Helper: count enemies in room
---------------------------------------------------------------------------
local function enemy_count()
    local targets = GameObj.targets and GameObj.targets() or {}
    return #targets
end

---------------------------------------------------------------------------
-- Helper: get first target
---------------------------------------------------------------------------
local function get_target()
    return GameObj.target and GameObj.target() or nil
end

---------------------------------------------------------------------------
-- 1. Symbol of Mana
---------------------------------------------------------------------------
function M.symbol_of_mana(cfg)
    if not cfg.get_bool("symbol_of_mana") then return end
    if not Spell[9813] or not Spell[9813].known then return end
    if not Spell[9813]:affordable() then return end
    if Effects.Cooldowns.active("Symbol of Mana") then return end

    waitrt()
    waitcastrt()
    fput("symbol of mana confirm")
    pause(0.5)
end

---------------------------------------------------------------------------
-- 2. Mana Leech (516)
---------------------------------------------------------------------------
function M.mana_leech(cfg)
    if not cfg.get_bool("use_mana_leech") then return end
    if not Spell[516] or not Spell[516].known then return end
    if not Spell[516]:affordable() then return end

    local threshold = cfg.get_num("percentleech")
    if threshold <= 0 then threshold = 50 end
    if percentmana() >= threshold then return end
    if enemy_count() < 1 then return end

    waitrt()
    waitcastrt()
    fput("incant 516")
    pause(0.5)
end

---------------------------------------------------------------------------
-- 3. Sigil of Power
---------------------------------------------------------------------------
function M.sigil_of_power(cfg)
    if not cfg.get_bool("sigil_of_power") then return end
    if not Spell[9907] or not Spell[9907].known then return end
    if not Spell[9907]:affordable() then return end
    if Spell[9907].active then return end

    waitrt()
    waitcastrt()
    fput("sigil of power")
    pause(0.5)
end

---------------------------------------------------------------------------
-- 4. Mana Share — determine mana types and build request message
---------------------------------------------------------------------------
function M.mana_share(cfg)
    local mana_types = {}

    if Skills.smc and Skills.smc >= 24 then
        table.insert(mana_types, "Spiritual")
    end
    if Skills.mmc and Skills.mmc >= 24 then
        table.insert(mana_types, "Mental")
    end
    if Skills.emc and Skills.emc >= 24 then
        table.insert(mana_types, "Elemental")
    end

    local n = #mana_types
    local message

    if n == 0 then
        message = "I Need Mana!"
    elseif n == 1 then
        message = "I Need " .. mana_types[1] .. " Mana!"
    elseif n == 2 then
        message = "I Need " .. mana_types[1] .. " or " .. mana_types[2] .. " Mana!"
    else
        local last = mana_types[n]
        local rest = {}
        for i = 1, n - 1 do
            table.insert(rest, mana_types[i])
        end
        message = "I Need " .. table.concat(rest, ", ") .. " or " .. last .. " Mana!"
    end

    return message, mana_types
end

---------------------------------------------------------------------------
-- 5. Infuse Weapon — prep configured spell and infuse right hand
---------------------------------------------------------------------------
function M.infuse_weapon(cfg)
    local spell_str = cfg.get("infusespell")
    if not spell_str or spell_str == "" then return end

    local spell_num = tonumber(spell_str)
    if not spell_num then return end
    if not Spell[spell_num] or not Spell[spell_num].known then return end
    if not Spell[spell_num]:affordable() then return end

    waitrt()
    waitcastrt()
    fput("prep " .. spell_num)
    pause(0.3)
    local rh = checkright()
    if rh and rh ~= "" then
        fput("infuse my " .. rh)
    else
        fput("infuse right")
    end
    waitrt()
    waitcastrt()
end

---------------------------------------------------------------------------
-- 6. Infuse Shield — prep 1604 and evoke on left hand
---------------------------------------------------------------------------
function M.infuse_shield(cfg)
    if not cfg.get_bool("sanctlefthand") then return end
    if not Spell[1604] or not Spell[1604].known then return end
    if not Spell[1604]:affordable() then return end

    waitrt()
    waitcastrt()
    fput("prep 1604")
    pause(0.3)
    local lh = checkleft()
    if lh and lh ~= "" then
        fput("evoke my " .. lh)
    else
        fput("evoke left")
    end
    waitrt()
    waitcastrt()
end

---------------------------------------------------------------------------
-- 7. Combat Spellup — cast a buff spell with retry on wait/hindrance
---------------------------------------------------------------------------
function M.combat_spellup(spell_num, cast_type)
    if not Spell[spell_num] or not Spell[spell_num].known then return end
    if not Spell[spell_num]:affordable() then return end
    if Spell[spell_num].active then return end

    local cmd
    if cast_type and cast_type ~= "" then
        cmd = "incant " .. spell_num .. " " .. cast_type
    else
        cmd = "incant " .. spell_num
    end

    local max_retries = 5
    for _ = 1, max_retries do
        waitrt()
        waitcastrt()

        local result = dothistimeout(cmd, 30,
            "Cast Roundtime", "Sing Roundtime",
            "Wait", "Spell Hindrance",
            "You don't have a spell prepared",
            "You can't do that")

        if not result then
            return
        end

        if result:find("Cast Roundtime") or result:find("Sing Roundtime") then
            return
        end

        if result:find("Wait") or result:find("Spell Hindrance") then
            pause(1)
            -- retry
        else
            return
        end
    end
end

---------------------------------------------------------------------------
-- 8. Can Cast — generic attack spell function (attack spells 1-5)
---------------------------------------------------------------------------
function M.can_cast(cfg, cc, spell_idx)
    -- Build key suffix: "" for 1, "2" for 2, etc.
    local sfx = spell_idx == 1 and "" or tostring(spell_idx)
    local key = "attack_spell" .. sfx

    -- Read spell number from creature config
    local spell_str = cc[key]
    if not spell_str or spell_str == "" then return end
    local spell_num = tonumber(spell_str)
    if not spell_num or spell_num == 0 then return end

    -- Check spell known
    if not Spell[spell_num] or not Spell[spell_num].known then return end

    -- Check debuffs
    if Effects.Debuffs.active("Mystic Impedance") then return end
    if Effects.Debuffs.active("Silenced") then return end

    -- Check can act
    if not can_act() then return end

    -- Check stamina/mana/enemy thresholds
    local stam_min  = cc[key .. "_stam_min"]  or 0
    local mana_min  = cc[key .. "_man_min"]    or 0
    local enemy_min = cc[key .. "_enemy_min"]  or 1
    local enemy_max = cc[key .. "_enemy_max"]  or 10

    local enemies = enemy_count()
    if enemies < enemy_min or enemies > enemy_max then return end
    if percentstamina() < stam_min then return end

    -- Check affordability; if not, attempt mana recovery
    if not Spell[spell_num]:affordable() then
        if percentmana() < mana_min then
            M.mana_leech(cfg)
            M.symbol_of_mana(cfg)
            M.sigil_of_power(cfg)
        end
        -- Recheck after recovery attempt
        if not Spell[spell_num]:affordable() then return end
    end

    if percentmana() < mana_min then return end

    -- Get target
    local target = get_target()

    -- Determine cast type
    local cast_type_key = "cast_type" .. tostring(spell_idx)
    local cast_type = cc[cast_type_key] or ""

    -- Determine warding flag
    local warding = cc[key .. "_warding"]

    -- Stance offensive if not warding
    if not warding then
        waitrt()
        waitcastrt()
        fput("stance offensive")
    end

    -- Build incant command
    local open_cast = cc[key .. "_open_cast"]
    local cmd
    if cast_type ~= "" then
        if open_cast then
            cmd = "incant " .. spell_num .. " " .. cast_type .. " open"
        elseif target then
            cmd = "incant " .. spell_num .. " " .. cast_type .. " target"
        else
            cmd = "incant " .. spell_num .. " " .. cast_type .. " open"
        end
    else
        if open_cast then
            cmd = "incant " .. spell_num .. " open"
        elseif target then
            cmd = "incant " .. spell_num .. " target"
        else
            cmd = "incant " .. spell_num .. " open"
        end
    end

    fput(cmd)

    -- Post-cast: stance guarded, wait, stance defensive
    waitrt()
    fput("stance guarded")
    waitcastrt()
    fput("stance defensive")
end

---------------------------------------------------------------------------
-- 9. Can Cast Opener — generic opener spell function (openers 1-2)
---------------------------------------------------------------------------
function M.can_cast_opener(cfg, cc, opener_idx)
    local sfx = opener_idx == 1 and "" or tostring(opener_idx)
    local key = "spell_opener" .. sfx

    local spell_str = cc[key]
    if not spell_str or spell_str == "" then return end
    local spell_num = tonumber(spell_str)
    if not spell_num or spell_num == 0 then return end

    -- Check spell known
    if not Spell[spell_num] or not Spell[spell_num].known then return end

    -- Check debuffs
    if Effects.Debuffs.active("Mystic Impedance") then return end
    if Effects.Debuffs.active("Silenced") then return end

    -- Check can act
    if not can_act() then return end

    -- Check thresholds
    local stam_min  = cc[key .. "_stam_min"]  or 0
    local mana_min  = cc[key .. "_man_min"]    or 0
    local enemy_min = cc[key .. "_enemy_min"]  or 1
    local enemy_max = cc[key .. "_enemy_max"]  or 10

    local enemies = enemy_count()
    if enemies < enemy_min or enemies > enemy_max then return end
    if percentstamina() < stam_min then return end
    if percentmana() < mana_min then return end

    -- Check affordability
    if not Spell[spell_num]:affordable() then return end

    -- Check if room already has the effect (via GameObj.loot for environmental objects)
    local loot_items = GameObj.loot and GameObj.loot() or {}
    local effect_nouns = {
        [335]  = "snowflakes",   -- Cold Snap
        [610]  = "tangleweed",   -- Tangleweed
        [709]  = { "arms", "tentacles" }, -- Grasp of the Grave
        [710]  = "tempest",      -- Tempest
        [720]  = "void",         -- Implosion/Void
        [118]  = "web",          -- Web
    }

    local nouns_to_check = effect_nouns[spell_num]
    if nouns_to_check then
        if type(nouns_to_check) == "string" then
            nouns_to_check = { nouns_to_check }
        end
        for _, item in ipairs(loot_items) do
            local item_noun = (item.noun or ""):lower()
            for _, noun in ipairs(nouns_to_check) do
                if item_noun == noun then
                    return -- effect already in room
                end
            end
        end
    end

    -- Special handling: empathic link spells (1117/1614/217/512/611/603)
    local link_spells = { [1117]=true, [1614]=true, [217]=true, [512]=true, [611]=true, [603]=true }
    if link_spells[spell_num] then
        local targets = GameObj.targets and GameObj.targets() or {}
        local all_linked = true
        for _, npc in ipairs(targets) do
            local npc_id = npc.id or npc.name
            if not empathic_link_targets[npc_id] then
                all_linked = false
                break
            end
        end
        if #targets > 0 and all_linked then
            return -- all targets already affected
        end
        -- Track newly affected targets
        for _, npc in ipairs(targets) do
            local npc_id = npc.id or npc.name
            empathic_link_targets[npc_id] = true
        end
    end

    -- Special handling: spell 909 (Tremors)
    if spell_num == 909 then
        local targets = GameObj.targets and GameObj.targets() or {}
        local has_standing = false
        for _, npc in ipairs(targets) do
            local status = (npc.status or ""):lower()
            if not status:find("lying") and not status:find("prone") then
                has_standing = true
                break
            end
        end
        if not has_standing then return end

        waitrt()
        waitcastrt()
        fput("stance offensive")
        fput("incant 909 channel")
        waitrt()
        waitcastrt()
        fput("stance guarded")

        -- Post-tremor follow-ups
        if cfg.get_bool("stomp") then
            waitrt()
            fput("stomp")
            waitrt()
        end
        if cfg.get_bool("pound") then
            waitrt()
            fput("pound")
            waitrt()
        end
        if cfg.get_bool("tap") then
            waitrt()
            fput("tap")
            waitrt()
        end

        fput("stance defensive")
        return
    end

    -- Default: build incant command with targeting
    local cast_type = ""
    local evoke   = cc[key .. "_evoke"]
    local channel = cc[key .. "_channel"]
    if evoke and channel then
        cast_type = "evoke channel"
    elseif evoke then
        cast_type = "evoke"
    elseif channel then
        cast_type = "channel"
    end

    local warding   = cc[key .. "_warding"]
    local open_cast = cc[key .. "_open_cast"]

    if not warding then
        waitrt()
        waitcastrt()
        fput("stance offensive")
    end

    local cmd
    if cast_type ~= "" then
        if open_cast then
            cmd = "incant " .. spell_num .. " " .. cast_type .. " open"
        else
            cmd = "incant " .. spell_num .. " " .. cast_type .. " target"
        end
    else
        if open_cast then
            cmd = "incant " .. spell_num .. " open"
        else
            cmd = "incant " .. spell_num .. " target"
        end
    end

    fput(cmd)

    waitrt()
    fput("stance guarded")
    waitcastrt()
    fput("stance defensive")
end

---------------------------------------------------------------------------
-- 10. Society Spell Casters
---------------------------------------------------------------------------
function M.cast_spell_society(cfg)
    -- Council of Light Signs
    local signs = {
        { key = "sign_of_warding",    cmd = "sign warding",    spell = 9912 },
        { key = "sign_of_defending",  cmd = "sign defending",  spell = 9913 },
        { key = "sign_of_shields",    cmd = "sign shields",    spell = 9914 },
        { key = "sign_of_striking",   cmd = "sign striking",  spell = 9916 },
        { key = "sign_of_smiting",    cmd = "sign smiting",   spell = 9918 },
        { key = "sign_of_swords",     cmd = "sign swords",    spell = 9920 },
    }

    for _, s in ipairs(signs) do
        if cfg.get_bool(s.key) then
            if Spell[s.spell] and Spell[s.spell].known
                and Spell[s.spell]:affordable()
                and not Spell[s.spell].active then
                waitrt()
                waitcastrt()
                fput(s.cmd)
                pause(0.5)
            end
        end
    end

    -- Guardians of Sunfist Sigils
    local sigils = {
        { key = "sigil_of_minor_bane",       cmd = "sigil minor bane",       spell = 9903 },
        { key = "sigil_of_offense",          cmd = "sigil offense",          spell = 9904 },
        { key = "sigil_of_major_bane",       cmd = "sigil major bane",       spell = 9905 },
        { key = "sigil_of_minor_protection", cmd = "sigil minor protection", spell = 9906 },
        { key = "sigil_of_defense",          cmd = "sigil defense",          spell = 9901 },
        { key = "sigil_of_major_protection", cmd = "sigil major protection", spell = 9908 },
        { key = "sigil_of_concentration",    cmd = "sigil concentration",    spell = 9909 },
    }

    for _, s in ipairs(sigils) do
        if cfg.get_bool(s.key) then
            if Spell[s.spell] and Spell[s.spell].known
                and Spell[s.spell]:affordable()
                and not Spell[s.spell].active then
                waitrt()
                waitcastrt()
                fput(s.cmd)
                pause(0.5)
            end
        end
    end

    -- Voln Symbols
    local symbols = {
        { key = "symbol_of_courage",     cmd = "symbol courage",     spell = 9805 },
        { key = "symbol_of_protection",  cmd = "symbol protection",  spell = 9806 },
    }

    for _, s in ipairs(symbols) do
        if cfg.get_bool(s.key) then
            if Spell[s.spell] and Spell[s.spell].known
                and Spell[s.spell]:affordable()
                and not Spell[s.spell].active then
                waitrt()
                waitcastrt()
                fput(s.cmd)
                pause(0.5)
            end
        end
    end

    -- Undead-only symbols (retribution and supremacy)
    local targets = GameObj.targets and GameObj.targets() or {}
    local has_undead = false
    for _, npc in ipairs(targets) do
        local npc_type = (npc.type or ""):lower()
        if npc_type:find("undead") then
            has_undead = true
            break
        end
    end

    local undead_symbols = {
        { key = "symbol_of_retribution", cmd = "symbol retribution", spell = 9815 },
        { key = "symbol_of_supremacy",   cmd = "symbol supremacy",   spell = 9816 },
    }

    for _, s in ipairs(undead_symbols) do
        if cfg.get_bool(s.key) and has_undead then
            if Spell[s.spell] and Spell[s.spell].known
                and Spell[s.spell]:affordable()
                and not Spell[s.spell].active then
                waitrt()
                waitcastrt()
                fput(s.cmd)
                pause(0.5)
            end
        end
    end

    -- Spell 1607 (Rejuvenation) — if available and stamina low
    if Spell[1607] and Spell[1607].known
        and Spell[1607]:affordable()
        and not Spell[1607].active
        and percentstamina() <= 50 then
        waitrt()
        waitcastrt()
        Spell[1607]:cast()
        pause(0.5)
    end
end

---------------------------------------------------------------------------
-- 11. Group Buff Casters
---------------------------------------------------------------------------

function M.cast_spell_bravery(cfg)
    if not cfg.get_bool("groupbravery") then return end
    if not Spell[211] or not Spell[211].known then return end
    if not Spell[211]:affordable() then return end
    if os.time() < timers.bravery then return end

    waitrt()
    waitcastrt()
    fput("incant 211 evoke")
    timers.bravery = os.time() + 180
    pause(0.5)
end

function M.cast_spell_group_celerity(cfg)
    if not cfg.get_bool("cast_spell_group_celerity") then return end
    if not Spell[506] or not Spell[506].known then return end
    if not Spell[506]:affordable() then return end
    if os.time() < timers.group_celerity then return end

    waitrt()
    waitcastrt()
    fput("incant 506 evoke")
    timers.group_celerity = os.time() + 180
    pause(0.5)
end

function M.cast_spell_celerity(cfg)
    if not cfg.get_bool("cast_spell_self_celerity") then return end
    if not Spell[506] or not Spell[506].known then return end
    if not Spell[506]:affordable() then return end
    if Spell[506].active then return end

    waitrt()
    waitcastrt()
    fput("incant 506")
    pause(0.5)
end

function M.cast_spell_rapid_fire(cfg)
    if not cfg.get_bool("spell_rapid_fire") then return end
    if not Spell[515] or not Spell[515].known then return end
    if not Spell[515]:affordable() then return end
    if Spell[515].active then return end

    waitrt()
    waitcastrt()
    fput("incant 515")
    pause(0.5)
end

function M.cast_spell_barkskin(cfg)
    if not cfg.get_bool("barkskin_spell") then return end
    if not Spell[605] or not Spell[605].known then return end
    if not Spell[605]:affordable() then return end
    if Spell[605].active then return end
    if Effects.Cooldowns.active("Barkskin") then return end

    waitrt()
    waitcastrt()
    fput("incant 605")
    pause(0.5)
end

function M.cast_spell_group_barkskin(cfg)
    if not cfg.get_bool("barkskin_spell_group") then return end
    if not Spell[605] or not Spell[605].known then return end
    if not Spell[605]:affordable() then return end
    if os.time() < timers.group_barkskin then return end

    waitrt()
    waitcastrt()
    fput("incant 605 evoke")
    timers.group_barkskin = os.time() + 60
    pause(0.5)
end

function M.cast_spell_zealot(cfg)
    if not cfg.get_bool("cast_spell_di_zeal") then return end
    if not Spell[1617] or not Spell[1617].known then return end
    if not Spell[1617]:affordable() then return end
    if Spell[1617].active then return end

    waitrt()
    waitcastrt()
    fput("incant 1617")
    pause(0.5)
end

function M.cast_spell_heroism(cfg)
    if not cfg.get_bool("spell_heroism") then return end
    if not Spell[215] or not Spell[215].known then return end
    if not Spell[215]:affordable() then return end
    if os.time() < timers.heroism then return end

    waitrt()
    waitcastrt()
    fput("incant 215 evoke")
    timers.heroism = os.time() + 180
    pause(0.5)
end

function M.cast_spell_faith_shield(cfg)
    if not cfg.get_bool("spell_shield_faith") then return end
    if not Spell[1619] or not Spell[1619].known then return end
    if not Spell[1619]:affordable() then return end
    if Spell[1619].active then return end

    waitrt()
    waitcastrt()
    fput("incant 1619")
    pause(0.5)
end

function M.cast_spell_wall_of_force(cfg)
    if not cfg.get_bool("spell_wall_of_force") then return end
    if not Spell[140] or not Spell[140].known then return end
    if not Spell[140]:affordable() then return end
    if Spell[140].active then return end

    waitrt()
    waitcastrt()
    fput("incant 140")
    pause(0.5)
end

function M.cast_spell_beacon_of_courage(cfg)
    if not cfg.get_bool("spell_beacon_of_courage") then return end
    if not Spell[1608] or not Spell[1608].known then return end
    if not Spell[1608]:affordable() then return end
    if Spell[1608].active then return end

    waitrt()
    waitcastrt()
    fput("incant 1608")
    pause(0.5)
end

function M.sing_song_song_of_tonis(cfg)
    if not cfg.get_bool("song_song_of_tonis") then return end
    if not Spell[1035] or not Spell[1035].known then return end
    if not Spell[1035]:affordable() then return end
    if Spell[1035].active then return end

    waitrt()
    waitcastrt()
    fput("incant 1035")
    pause(0.5)
end

---------------------------------------------------------------------------
-- 12. Warcry Functions
---------------------------------------------------------------------------

function M.cry_warcry_shout(cfg)
    if not cfg.get_bool("warcry_shout") then return end
    if Effects.Buffs.active("Empowered (+20)") then return end
    if percentstamina() < 20 then return end

    waitrt()
    fput("warcry shout")
    pause(0.5)
end

function M.cry_warcry_holler(cfg)
    if not cfg.get_bool("warcry_holler") then return end
    if Effects.Buffs.active("Enh. Health (+20)") then return end
    if percentstamina() < 20 then return end

    waitrt()
    fput("warcry holler")
    pause(0.5)
end

---------------------------------------------------------------------------
-- 13. Combat Technique Buffs
---------------------------------------------------------------------------

function M.use_shield_steely(cfg)
    if not cfg.get_bool("shield_steely") then return end
    if Effects.Buffs.active("Steely Resolve") then return end
    if enemy_count() < 1 then return end

    waitrt()
    fput("shield steely")
    pause(0.5)
end

function M.use_cman_surge_of_strength(cfg, use_cooldown)
    local key = use_cooldown and "cman_surge_of_strength_cooldown" or "cman_surge_of_strength_no_cooldown"
    if not cfg.get_bool(key) then return end

    -- Check for existing strength buffs
    if Effects.Buffs.active("Enh. Strength (+5)") then return end
    if Effects.Buffs.active("Enh. Strength (+10)") then return end
    if Effects.Buffs.active("Enh. Strength (+15)") then return end
    if Effects.Buffs.active("Enh. Strength (+20)") then return end
    if Effects.Buffs.active("Enh. Strength (+25)") then return end
    if Effects.Buffs.active("Enh. Strength (+30)") then return end

    if percentstamina() < 20 then return end

    waitrt()
    fput("cman surge")
    pause(0.5)
end

---------------------------------------------------------------------------
-- 14. Gemstone Activation Functions
---------------------------------------------------------------------------

--- Generic gemstone activator
--- @param cfg     config module
--- @param name    string  cooldown name for Effects.Cooldowns.active check
--- @param short_cmd string  command suffix for "gemstone activate {short_cmd}"
--- @param conditions_fn function  returns true if activation conditions met
function M.activate_gemstone(cfg, name, short_cmd, conditions_fn)
    if Effects.Cooldowns.active(name) then return end
    if conditions_fn and not conditions_fn() then return end

    waitrt()
    fput("gemstone activate " .. short_cmd)
    pause(0.5)
end

-- Arcane Aegis: mana > threshold
function M.activate_arcane_aegis(cfg)
    if not cfg.get_bool("gemstone_arcane_aegis") then return end
    local threshold = cfg.get_num("activate_arcane_aegis_mana_if")
    M.activate_gemstone(cfg, "Arcane Aegis", "arcaneaegis", function()
        return Char.mana > threshold
    end)
end

-- Arcanist's Ascendancy: enemies > threshold
function M.activate_arcanists_ascendancy(cfg)
    if not cfg.get_bool("gemstone_arcanists_ascendancy") then return end
    local threshold = cfg.get_num("activate_arcanists_ascendancy_enemy_if")
    M.activate_gemstone(cfg, "Arcanist's Ascendancy", "arcascend", function()
        return enemy_count() > threshold
    end)
end

-- Arcanist's Blade: enemies > threshold AND mana > threshold AND stamina > threshold
function M.activate_arcanists_blade(cfg)
    if not cfg.get_bool("gemstone_arcanists_blade") then return end
    local enemy_thresh   = cfg.get_num("activate_arcanists_blade_enemy_if")
    local mana_thresh    = cfg.get_num("activate_arcanists_blade_mana_if")
    local stamina_thresh = cfg.get_num("activate_arcanists_blade_stamina_if")
    M.activate_gemstone(cfg, "Arcanist's Blade", "arcblade", function()
        return enemy_count() > enemy_thresh
            and Char.mana > mana_thresh
            and Char.stamina > stamina_thresh
    end)
end

-- Arcanist's Will: enemies > threshold AND mana > threshold AND stamina > threshold
function M.activate_arcanists_will(cfg)
    if not cfg.get_bool("gemstone_arcanists_will") then return end
    local enemy_thresh   = cfg.get_num("activate_arcanists_will_enemy_if")
    local mana_thresh    = cfg.get_num("activate_arcanists_will_mana_if")
    local stamina_thresh = cfg.get_num("activate_arcanists_will_stamina_if")
    M.activate_gemstone(cfg, "Arcanist's Will", "arcwill", function()
        return enemy_count() > enemy_thresh
            and Char.mana > mana_thresh
            and Char.stamina > stamina_thresh
    end)
end

-- Blood Boil: enemies > threshold
function M.activate_blood_boil(cfg)
    if not cfg.get_bool("gemstone_blood_boil") then return end
    local threshold = cfg.get_num("activate_blood_boil_enemy_if")
    M.activate_gemstone(cfg, "Blood Boil", "bloodboil", function()
        return enemy_count() > threshold
    end)
end

-- Blood Siphon: enemies > threshold
function M.activate_blood_siphon(cfg)
    if not cfg.get_bool("gemstone_blood_siphon") then return end
    local threshold = cfg.get_num("activate_blood_siphon_enemy_if")
    M.activate_gemstone(cfg, "Blood Siphon", "bloodsiphon", function()
        return enemy_count() > threshold
    end)
end

-- Blood Wellspring: health < threshold (inverted!)
function M.activate_blood_wellspring(cfg)
    if not cfg.get_bool("gemstone_blood_wellspring") then return end
    local threshold = cfg.get_num("activate_blood_wellspring_health_if")
    M.activate_gemstone(cfg, "Blood Wellspring", "bloodwell", function()
        return percenthealth() < threshold
    end)
end

-- Evanescent Possession: enemies > threshold, target next
function M.activate_evanescent_possession(cfg)
    if not cfg.get_bool("gemstone_evanescent_possession") then return end
    local threshold = cfg.get_num("activate_evanescent_possession_enemy_if")
    if Effects.Cooldowns.active("Evanescent Possession") then return end
    if enemy_count() <= threshold then return end

    waitrt()
    fput("gemstone activate epossess")
    pause(0.3)
    fput("target next")
    pause(0.5)
end

-- Force of Will: no threshold
function M.activate_force_of_will(cfg)
    if not cfg.get_bool("gemstone_force_of_will") then return end
    M.activate_gemstone(cfg, "Force of Will", "forceofwill", nil)
end

-- Geomancer's Spite: enemies > threshold
function M.activate_geomancers_spite(cfg)
    if not cfg.get_bool("gemstone_geomancers_spite") then return end
    local threshold = cfg.get_num("activate_geomancers_spite_enemy_if")
    M.activate_gemstone(cfg, "Geomancer's Spite", "geospite", function()
        return enemy_count() > threshold
    end)
end

-- Mana Shield: mana > threshold
function M.activate_mana_shield(cfg)
    if not cfg.get_bool("gemstone_mana_shield") then return end
    local threshold = cfg.get_num("activate_mana_shield_mana_if")
    M.activate_gemstone(cfg, "Mana Shield", "manashield", function()
        return Char.mana > threshold
    end)
end

-- Mana Wellspring: mana < threshold (inverted!)
function M.activate_mana_wellspring(cfg)
    if not cfg.get_bool("gemstone_mana_wellspring") then return end
    local threshold = cfg.get_num("activate_mana_wellspring_mana_if")
    M.activate_gemstone(cfg, "Mana Wellspring", "manawellspring", function()
        return Char.mana < threshold
    end)
end

-- Reckless Precision: enemies < threshold (inverted!) AND > 0
function M.activate_reckless_precision(cfg)
    if not cfg.get_bool("gemstone_reckless_precision") then return end
    local threshold = cfg.get_num("activate_reckless_precision_enemy_if")
    M.activate_gemstone(cfg, "Reckless Precision", "reckless", function()
        local count = enemy_count()
        return count > 0 and count < threshold
    end)
end

-- Spellblade's Fury: enemies > threshold AND mana > threshold
function M.activate_spellblades_fury(cfg)
    if not cfg.get_bool("gemstone_spellblades_fury") then return end
    local enemy_thresh = cfg.get_num("activate_spellblades_fury_enemy_if")
    local mana_thresh  = cfg.get_num("activate_spellblades_fury_mana_if")
    M.activate_gemstone(cfg, "Spellblade's Fury", "spellblade", function()
        return enemy_count() > enemy_thresh and Char.mana > mana_thresh
    end)
end

-- Spirit Wellspring: spirit < threshold (inverted!)
function M.activate_spirit_wellspring(cfg)
    if not cfg.get_bool("gemstone_spirit_wellspring") then return end
    local threshold = cfg.get_num("activate_spirit_wellspring_spirit_if")
    M.activate_gemstone(cfg, "Spirit Wellspring", "spiritwell", function()
        return Char.spirit < threshold
    end)
end

-- Unearthly Chains: enemies > threshold
function M.activate_unearthly_chains(cfg)
    if not cfg.get_bool("gemstone_unearthly_chains") then return end
    local threshold = cfg.get_num("activate_unearthly_chains_enemy_if")
    M.activate_gemstone(cfg, "Unearthly Chains", "unearthchains", function()
        return enemy_count() > threshold
    end)
end

-- Witchhunter's Ascendancy: enemies > threshold
function M.activate_witchhunters_ascendancy(cfg)
    if not cfg.get_bool("gemstone_witchhunters_ascendancy") then return end
    local threshold = cfg.get_num("activate_witchhunters_ascendancy_enemy_if")
    M.activate_gemstone(cfg, "Witchhunter's Ascendancy", "witchhunt", function()
        return enemy_count() > threshold
    end)
end

---------------------------------------------------------------------------
-- 15. Group Effects — run all enabled group buffs
---------------------------------------------------------------------------
function M.groupeffects(cfg)
    M.cast_spell_society(cfg)
    M.cast_spell_bravery(cfg)
    M.cast_spell_group_celerity(cfg)
    M.cast_spell_celerity(cfg)
    M.cast_spell_rapid_fire(cfg)
    M.cast_spell_barkskin(cfg)
    M.cast_spell_group_barkskin(cfg)
    M.cast_spell_zealot(cfg)
    M.cast_spell_heroism(cfg)
    M.cast_spell_faith_shield(cfg)
    M.cast_spell_wall_of_force(cfg)
    M.cast_spell_beacon_of_courage(cfg)
    M.sing_song_song_of_tonis(cfg)
    M.cry_warcry_shout(cfg)
    M.cry_warcry_holler(cfg)
    M.use_shield_steely(cfg)
    M.use_cman_surge_of_strength(cfg, true)
    M.use_cman_surge_of_strength(cfg, false)
end

---------------------------------------------------------------------------
-- 16. Gemstone Effects — run all enabled gemstone activations
---------------------------------------------------------------------------
function M.gemstone_effects(cfg)
    M.activate_arcane_aegis(cfg)
    M.activate_arcanists_ascendancy(cfg)
    M.activate_arcanists_blade(cfg)
    M.activate_arcanists_will(cfg)
    M.activate_blood_boil(cfg)
    M.activate_blood_siphon(cfg)
    M.activate_blood_wellspring(cfg)
    M.activate_evanescent_possession(cfg)
    M.activate_force_of_will(cfg)
    M.activate_geomancers_spite(cfg)
    M.activate_mana_shield(cfg)
    M.activate_mana_wellspring(cfg)
    M.activate_reckless_precision(cfg)
    M.activate_spellblades_fury(cfg)
    M.activate_spirit_wellspring(cfg)
    M.activate_unearthly_chains(cfg)
    M.activate_witchhunters_ascendancy(cfg)
end

return M
