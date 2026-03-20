-- huntpro/spells.lua — Spell upkeep, buff management, society abilities, style 9 casting
-- @revenant-script
-- @lic-certified: complete 2026-03-19
-- Original: huntpro.lic by Jara — spell_choice, spell_cast, waggle, society upkeep,
-- style_9_spell_overrides, force_spell, upkeep (lines ~3565-5300, 6785-6816, 8300-8408)

local Spells = {}

---------------------------------------------------------------------------
-- Profession default spells — mirrors Ruby spell_choice logic
---------------------------------------------------------------------------
local PROF_DEFAULT_SPELLS = {
    Empath   = 1700,
    Cleric   = 1700,
    Wizard   = 1700,
    Sorcerer = 1700,
    Ranger   = 1700,
    Bard     = 1700,
    Paladin  = 1700,
}

-- Known offensive spells by profession (priority order)
local PROF_SPELL_LISTS = {
    Empath   = {1115, 1110, 111, 1700},
    Cleric   = {317, 306, 302, 1700},
    Wizard   = {910, 901, 908, 907, 906, 905, 904, 903, 510, 505, 502, 1707, 519, 1700},
    Sorcerer = {719, 711, 705, 702, 1700},
    Ranger   = {603, 1700},
    Bard     = {1008, 1700},
    Paladin  = {1603, 1700},
}

---------------------------------------------------------------------------
-- Pick the best available offensive spell for the profession
---------------------------------------------------------------------------
function Spells.choose_spell(hp)
    local prof = Stats.prof
    local custom = hp.spell_default
    if custom and custom ~= "0" then
        local num = tonumber(custom)
        if num and Spell[num] and Spell[num].known and Spell[num]:affordable() then
            return num
        end
    end

    -- style9_arcanecs: force Arcane Blast (CS form) regardless of available spells
    if hp.style9_arcanecs then
        return 1700
    end

    -- immolate: Wizard-specific — prioritize Immolation (519) and Phase (502)
    if hp.immolate and prof == "Wizard" then
        local immolate_list = {519, 502}
        for _, num in ipairs(immolate_list) do
            if Spell[num] and Spell[num].known and Spell[num]:affordable() then
                return num
            end
        end
    end

    local list = PROF_SPELL_LISTS[prof]
    if not list then return 1700 end

    for _, num in ipairs(list) do
        if Spell[num] and Spell[num].known and Spell[num].affordable then
            return num
        end
    end

    return 1700
end

---------------------------------------------------------------------------
-- Cast chosen spell at target
---------------------------------------------------------------------------
function Spells.cast_at_target(hp, spell_num)
    if not spell_num then
        spell_num = Spells.choose_spell(hp)
    end

    waitrt()
    waitcastrt()

    if spell_num == 1700 then
        -- Arcane Blast (bolt)
        if hp.evoke_default then
            local Combat = require("gs.huntpro.combat")
            Combat.stance_offensive(hp)
            fput("incant 1700 evoke")
            waitrt()
            waitcastrt()
            Combat.stance_guarded(hp)
        else
            if Spell[1700] and Spell[1700].known and Spell[1700]:affordable() then
                Spell[1700]:cast()
            end
        end
    else
        -- For bolt spells, use evoke for SA characters
        local spell = Spell[spell_num]
        if spell and spell.known and spell:affordable() then
            -- Check if this is an evoke-type spell (bolt spells need stance)
            local bolt_spells = {
                [901] = true, [903] = true, [904] = true, [906] = true,
                [907] = true, [908] = true, [910] = true, [505] = true,
                [510] = true, [519] = true, [1707] = true,
            }

            if bolt_spells[spell_num] and hp.evoke_default then
                local Combat = require("gs.huntpro.combat")
                Combat.stance_offensive(hp)
                fput("incant " .. spell_num .. " evoke")
                waitrt()
                waitcastrt()
                Combat.stance_guarded(hp)
            else
                spell:cast()
            end
        end
    end

    -- Reset stance after casting
    local Combat = require("gs.huntpro.combat")
    Combat.stance_guarded(hp)
end

---------------------------------------------------------------------------
-- Style 9 spell override — check creature name for special spell needs
-- (Empaths need 1115 for non-corporeal, 1110 for constructs, etc.)
---------------------------------------------------------------------------
function Spells.get_creature_spell_override(hp, creature_name)
    if not creature_name then return nil end

    local prof = Stats.prof

    -- Non-corporeal creatures need 1115 (Wither) for empaths
    local noncorporeal = {
        "wraith", "spectre", "spirit", "phantom", "apparition", "shade",
        "ghostly", "ethereal", "wispy", "shadow", "banshee", "dirge",
        "moaning", "spectral", "fallen crusader", "lost soul",
        "nightmare steed", "shadow steed", "shadow mare",
        "roa'ter", "stone giant", "stone mastiff", "naisirc", "seraceris", "caedera",
        "rift crawler", "gorefrost golem",
    }

    local construct = {
        "golem", "gargoyle", "sentinel", "darkwoode", "crab",
        "spider", "arachnid", "scorpion", "beetle", "kiramon",
        "skayl", "fire guardian", "earth elemental", "cold guardian",
        "water wyrd", "magru", "worm", "ant", "carrion",
    }

    if prof == "Empath" then
        for _, pat in ipairs(noncorporeal) do
            if creature_name:lower():find(pat) then
                if Spell[1115] and Spell[1115].known and Spell[1115]:affordable() then
                    return 1115
                end
            end
        end
        for _, pat in ipairs(construct) do
            if creature_name:lower():find(pat) then
                if Spell[1110] and Spell[1110].known and Spell[1110]:affordable() then
                    return 1110
                elseif Spell[111] and Spell[111].known and Spell[111]:affordable() then
                    return 111
                end
            end
        end
    end

    -- Wizard zone override — no shock spells vs dirge/illoke elder
    if prof == "Wizard" then
        if creature_name:find("dirge") or creature_name:find("illoke elder") then
            local shock_spells = {910, 901}
            local current = hp.wizard_primary_spell
            for _, s in ipairs(shock_spells) do
                if current == s then
                    -- Switch to non-shock alternative
                    for _, alt in ipairs({510, 1707, 904, 903}) do
                        if Spell[alt] and Spell[alt].known and Spell[alt]:affordable() then
                            return alt
                        end
                    end
                    return 1700 -- fallback to arcane blast
                end
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- Upkeep quartz orb (1711 - Floating Disk)
---------------------------------------------------------------------------
function Spells.upkeep_quartz(hp)
    if hp.my_style ~= "9" then return end
    if hp.noquartz then return end

    if Spell.active_p(1711) then return end

    local result = dothistimeout("get my quartz orb", 5, "Get what", "You remove a")
    if result and result:find("Get what") then
        hp.noquartz = true
        respond(Char.name .. ", you don't have any quartz orbs. Disabling quartz feature.")
    else
        fput("rub my quartz orb")
        fput("stow my quartz orb")
        waitrt()
        waitcastrt()
        pause(1)
    end
end

---------------------------------------------------------------------------
-- Society upkeep — symbol/sign/sigil activation
---------------------------------------------------------------------------
function Spells.society_upkeep(hp)
    if hp.no_society then return end

    if hp.my_society == "Voln" then
        -- Symbol of Courage (9806), Protection (9810), etc.
        if Spell[9806] and Spell[9806].known and not Spell.active_p(9806) then
            fput("sym courage")
            pause(0.5)
        end
        if Spell[9810] and Spell[9810].known and not Spell.active_p(9810) then
            fput("sym protection")
            pause(0.5)
        end
        -- Symbol of Blessing for weapon (9814)
        if Spell[9814] and Spell[9814].known and not Spell.active_p(9814) then
            fput("sym blessing")
            pause(0.5)
        end

    elseif hp.my_society == "Col" then
        -- Council of Light signs
        if Spell[9912] and Spell[9912].known and not Spell.active_p(9912) then
            fput("sign defending")
            pause(0.5)
        end
        if Spell[9913] and Spell[9913].known and not Spell.active_p(9913) then
            fput("sign warding")
            pause(0.5)
        end
        if Spell[9914] and Spell[9914].known and not Spell.active_p(9914) then
            fput("sign swords")
            pause(0.5)
        end

    elseif hp.my_society == "Gos" then
        -- Guardians of Sunfist sigils
        if Spell[9805] and Spell[9805].known and not Spell.active_p(9805) then
            fput("sigil defense")
            pause(0.5)
        end
        if Spell[9806] and Spell[9806].known and not Spell.active_p(9806) then
            fput("sigil offense")
            pause(0.5)
        end
    end
end

---------------------------------------------------------------------------
-- Deed mana (Voln Symbol of Mana)
---------------------------------------------------------------------------
function Spells.deed_mana(hp)
    if not hp.deedmana then return end
    if hp.my_society ~= "Voln" then return end
    if hp.deedmana_zonk then return end

    local mana_pct = Char.percent_mana or 100
    if mana_pct < 50 then
        fput("symbol of mana confirm")
        pause(0.5)
    end
end

---------------------------------------------------------------------------
-- Wrack checker (Council of Light)
---------------------------------------------------------------------------
function Spells.wrack_check(hp)
    if not hp.wrack then return end
    if hp.wrack_cd and hp.wrack_cd > 0 then
        hp.wrack_cd = hp.wrack_cd - 1
        return
    end

    -- Calculate spirit safety
    local spirit_needed = 6
    if Spell.active_p(9912) then spirit_needed = spirit_needed + 1 end
    if Spell.active_p(9913) then spirit_needed = spirit_needed + 1 end
    if Spell.active_p(9914) then spirit_needed = spirit_needed + 1 end
    if Spell.active_p(9916) then spirit_needed = spirit_needed + 3 end

    local spirit = GameState.spirit or 0
    if spirit_needed <= spirit then
        respond(Char.name .. ", attempting wrack.")
        waitrt()
        waitcastrt()
        pause(0.1)
        Script.run("wrack")
        wait_while(function() return Script.running("wrack") end)
        hp.wrack_cd = 50
    else
        respond(Char.name .. ", wracking would be fatal with current spirit and active signs.")
        hp.wrack_cd = 50
    end
end

---------------------------------------------------------------------------
-- Boost management
---------------------------------------------------------------------------
function Spells.boost_long(hp)
    if not hp.boost_long then return end
    local mind = GameState.mind or ""
    if mind:find("saturated") or mind:find("must rest") or mind:find("numbed") then
        fput("boost long")
        pause(0.25)
    end
end

function Spells.boost_loot(hp)
    if not hp.boost_loot or hp.boost_loot == "0" then return end

    if hp.boost_loot == "minor" then
        if not Spell.active_p(9101) then
            waitrt()
            fput("boost loot minor")
        end
    elseif hp.boost_loot == "major" then
        if not Spell.active_p(9100) then
            waitrt()
            fput("boost loot major")
        end
    end
end

---------------------------------------------------------------------------
-- Spell upkeep — maintain defensive spells (140, 240, 515, 506, 919, 1035, 650)
---------------------------------------------------------------------------
function Spells.spell_upkeep(hp)
    local upkeep_spells = {
        {num = 140,  setting = "upkeep140"},
        {num = 240,  setting = "upkeep240"},
        {num = 515,  setting = "upkeep515"},
        {num = 506,  setting = "upkeep506"},
        {num = 919,  setting = "upkeep919"},
        {num = 1035, setting = "upkeep1035"},
        {num = 650,  setting = "upkeep650"},
    }

    for _, entry in ipairs(upkeep_spells) do
        if hp[entry.setting] and hp[entry.setting] ~= "0" then
            local spell = Spell[entry.num]
            if spell and spell.known and spell:affordable() and not Spell.active_p(entry.num) then
                -- Check disable flags
                local disable_key = "disable_" .. entry.num
                if not hp[disable_key] then
                    waitrt()
                    waitcastrt()
                    spell:cast()
                    pause(0.3)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Run external waggle script on cleanup
---------------------------------------------------------------------------
function Spells.end_combat_waggle(hp)
    if hp.no_waggle then return end

    if Script.exists("ewaggle") then
        Script.run("ewaggle")
    end
    wait_while(function() return Script.running("ewaggle") end)
end

return Spells
