-- osacrew/combat.lua
-- Combat subsystem for OSA Crew: stance management, stealth disablers,
-- enemy detection.
-- Ported from osacrew.lic v6.0.6 (Ganalon / original authors).
-- Lines 869-1002 and 3030-3040.

local M = {}

-- M.change_stance(new_stance, force)
-- Translates numeric stance values (10/20 → advance, 30/40 → forward,
-- 50/60 → neutral, 70/80 → guarded, 90/100 → defensive).
-- Returns immediately if Spell 216 (Martial Stance) is active or character
-- is dead.  Uses CMan Stance Perfection when force=true and a numeric stance
-- was provided.  Falls back to plain fput when force=false.
-- Source: change_stance, lines 869-893.
function M.change_stance(new_stance, force)
    if force == nil then force = true end

    -- Do not act when 216 is active or character is dead
    if Spell[216].active or dead() then
        return
    end

    -- Translate numeric values to named stances and remember the numeric form
    local perfect_stance = nil
    if new_stance:match("^%d+$") then
        local n = tonumber(new_stance)
        perfect_stance = new_stance
        if n == 10 or n == 20 then
            new_stance = "advance"
        elseif n == 30 or n == 40 then
            new_stance = "forward"
        elseif n == 50 or n == 60 then
            new_stance = "neutral"
        elseif n == 70 or n == 80 then
            new_stance = "guarded"
        elseif n == 90 or n == 100 then
            new_stance = "defensive"
        end
    end

    -- Already in the requested stance
    local current = GameState.stance or ""
    if current:lower():find(new_stance:lower(), 1, true) then
        return
    end

    -- If cast RT is running and we want defensive, guarded is acceptable
    if checkcastrt() > 0 and new_stance:find("def") then
        if current:lower() == "guarded" then
            return
        end
    end

    local response_pattern = "You are now|You move into|You fall back|Cast Roundtime|unable to change"

    if force and perfect_stance and CMan and CMan.known("Stance Perfection") then
        dothistimeout("cman stance " .. perfect_stance, 3, response_pattern)
    elseif force then
        dothistimeout("stance " .. new_stance, 3, response_pattern)
    else
        fput("stance " .. new_stance)
    end
end

-- M.wait_rt()
-- Brief pause, drain roundtime and cast roundtime, then another brief pause.
-- Source: wait_rt, lines 895-900.
function M.wait_rt()
    pause(0.1)
    waitrt()
    waitcastrt()
    pause(0.1)
end

-- M.stance_defensive()
-- Drain RT then move to defensive stance.
-- Source: stance_defensive, lines 902-905.
function M.stance_defensive()
    M.wait_rt()
    M.change_stance("defensive")
end

-- M.stance_offensive()
-- Drain RT then move to offensive stance.
-- Source: stance_offensive, lines 907-910.
function M.stance_offensive()
    M.wait_rt()
    M.change_stance("offensive")
end

-- M.cast_disabler(spell_name)
-- Checks if spell_name is known.  If not, echoes an error and falls back to
-- search + wait.  If known, preps and casts it, then also searches if the
-- spell is "Light".
-- Source: cast_disabler, lines 982-1002.
function M.cast_disabler(spell_name)
    if not Spell[spell_name].known then
        respond("")
        respond("You Have Selected A Stealth Disabling Spell You Do Not Know, Please Select One Known To Your Character. Defaulting To Search")
        respond("")
        fput("search")
        waitrt()
        waitcastrt()
        return
    end

    fput("prep " .. spell_name)
    fput("cast")
    waitrt()
    waitcastrt()

    if spell_name == "Light" then
        fput("search")
        waitrt()
        waitcastrt()
    end
end

-- M.stealth_disabler_routine(osa)
-- Executes one of 20 stealth-disabling options based on osa.stealth_disabler
-- (integer 0-19).
--   0  : defensive search
--   1  : Dispel Invisibility
--   2  : Searing Light
--   3  : Light (also searches afterward via cast_disabler)
--   4  : Censure
--   5  : Divine Wrath
--   6  : Elemental Wave
--   7  : Major Elemental Wave
--   8  : Cone of Elements
--   9  : Sun Burst
--   10 : Nature's Fury
--   11 : Grasp of the Grave
--   12 : Implosion
--   13 : Tremors
--   14 : Call Wind
--   15 : Aura of the Arkati
--   16 : Judgement
--   17 : offensive → cman eviscerate → defensive
--   18 : offensive → warcry Cry All → defensive
--   19 : defensive → symbol of sleep → wait RT
-- Source: stealth_disabler_routine, lines 912-980.
function M.stealth_disabler_routine(osa)
    local d = osa.stealth_disabler

    if d == 0 then
        M.stance_defensive()
        fput("search")
        waitrt()
        waitcastrt()

    elseif d == 1 then
        M.cast_disabler("Dispel Invisibility")
    elseif d == 2 then
        M.cast_disabler("Searing Light")
    elseif d == 3 then
        M.cast_disabler("Light")
    elseif d == 4 then
        M.cast_disabler("Censure")
    elseif d == 5 then
        M.cast_disabler("Divine Wrath")
    elseif d == 6 then
        M.cast_disabler("Elemental Wave")
    elseif d == 7 then
        M.cast_disabler("Major Elemental Wave")
    elseif d == 8 then
        M.cast_disabler("Cone of Elements")
    elseif d == 9 then
        M.cast_disabler("Sun Burst")
    elseif d == 10 then
        M.cast_disabler("Nature's Fury")
    elseif d == 11 then
        M.cast_disabler("Grasp of the Grave")
    elseif d == 12 then
        M.cast_disabler("Implosion")
    elseif d == 13 then
        M.cast_disabler("Tremors")
    elseif d == 14 then
        M.cast_disabler("Call Wind")
    elseif d == 15 then
        M.cast_disabler("Aura of the Arkati")
    elseif d == 16 then
        M.cast_disabler("Judgement")

    elseif d == 17 then
        M.stance_offensive()
        fput("cman eviscerate")
        M.stance_defensive()

    elseif d == 18 then
        M.stance_offensive()
        fput("warcry Cry All")
        M.stance_defensive()

    elseif d == 19 then
        M.stance_defensive()
        fput("symbol of sleep")
        waitrt()
        waitcastrt()
    end
end

-- M.checkforenemies()
-- Returns a table of live, targetable NPCs in the current room.
-- Filters out:
--   - dead/gone NPCs
--   - animated NPCs (except "animated slush")
--   - civilian nouns: child, traveller, scribe, merchant, dignitary,
--     official, magistrate (unless ethereal/celestial/unworldly)
--   - limb/appendage nouns: arm, appendage, claw, limb, pincer, tentacle,
--     palpus/palpi
-- Source: checkforenemies, lines 3030-3040.
-- Note: original also filters osa.exclusion list; osa.exclusion_list is
-- passed through if present on the osa table.
function M.checkforenemies()
    local all_npcs = GameObj.npcs()
    local enemies  = {}

    local limb_re     = Regex.new("^(?:arm|appendage|claw|limb|pincer|tentacle)s?$|^(?:palpus|palpi)$")
    local civilian_re = Regex.new("child|traveller|scribe|merchant|dignitary|official|magistrate")
    local special_re  = Regex.new("ethereal|celestial|unworldly")

    for _, npc in ipairs(all_npcs) do
        local status = npc.status or ""
        local name   = npc.name   or ""
        local noun   = npc.noun   or ""

        -- Skip dead or gone
        if status:find("dead") or status:find("gone") then
            goto continue
        end

        -- Skip animated (unless "animated slush")
        if name:find("animated") and not name:find("animated slush") then
            goto continue
        end

        -- Skip limb-like nouns
        if limb_re:test(noun) then
            goto continue
        end

        -- Skip civilians (unless ethereal/celestial/unworldly)
        if civilian_re:test(noun:lower()) and not special_re:test(name:lower()) then
            goto continue
        end

        table.insert(enemies, npc)

        ::continue::
    end

    return enemies
end

return M
