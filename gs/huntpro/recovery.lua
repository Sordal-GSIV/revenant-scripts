-- huntpro/recovery.lua — Healing, herb use, death recovery, fog return, status checks
-- @revenant-script
-- @lic-certified: complete 2026-03-18
-- Original: huntpro.lic by Jara — huntpro_status_check, empath_self_heal,
-- combat_use_herbs, fog logic, death handling (lines ~6822-6857, 15302-15500+)

local Recovery = {}

---------------------------------------------------------------------------
-- Status check — run every hunt loop iteration
-- Returns: nil if ok, or sets hp.action = 99 with hp.return_why for retreat
---------------------------------------------------------------------------
function Recovery.status_check(hp)
    -- Death check
    if GameState.dead then
        respond(Char.name .. ", you died. If huntpro caused this, please report it.")
        return "dead"
    end

    -- Mind saturation check
    local mind = GameState.mind or ""
    if mind:find("must rest") or mind:find("saturated") then
        if not hp.hunt_while_fried then
            hp.extra_fried = (hp.extra_fried or 0) + 1
            if hp.extra_fried >= 61 then
                hp.return_why = "Your mind is full and you must rest."
                hp.action = 99
                return "retreat"
            end
        end
    end

    -- Mana check (casters)
    local mana_pct = Char.percent_mana or 100
    if not hp.use_wands then
        if hp.fog_130 and Stats.level >= 30 and GameState.mana and
           GameState.mana >= 30 and GameState.mana <= 41 then
            if not hp.disable_mana then
                hp.return_why = "You have low mana."
                hp.action = 99
                return "retreat"
            end
        elseif not hp.style9_arcaneblast and mana_pct <= 13 then
            if not hp.disable_mana then
                hp.return_why = "You have low mana."
                hp.action = 99
                return "retreat"
            end
        elseif hp.style9_arcaneblast then
            if Stats.level <= 2 and mana_pct <= 25 then
                hp.style9_blastround = true
            elseif Stats.level >= 3 and mana_pct <= 13 then
                hp.style9_blastround = true
            else
                hp.style9_blastround = false
            end
        end
    else
        -- Wand mode: switch to wands at low mana
        if mana_pct <= 30 then
            hp.combat_wands = true
        elseif mana_pct >= 31 then
            hp.combat_wands = false
        end
    end

    -- Deed mana check (Voln)
    if hp.deedmana and hp.my_society == "Voln" then
        local SpellMod = require("gs.huntpro.spells")
        SpellMod.deed_mana(hp)
    end

    -- Wrack check (Council of Light)
    if hp.my_society == "Col" and mana_pct <= 24 then
        local SpellMod = require("gs.huntpro.spells")
        SpellMod.wrack_check(hp)
    end

    -- Health check
    local health_pct = Char.percent_health or 100
    if health_pct <= 50 then
        if Stats.prof == "Empath" and (GameState.mana or 0) >= 10 and
           Spell[1101] and Spell[1101].known then
            fput("cure")
        elseif hp.use_herbs then
            Recovery.combat_use_herbs(hp)
        else
            hp.return_why = "You have low health."
            hp.action = 99
            return "retreat"
        end
    end

    -- Stamina check
    local stamina_pct = Char.percent_stamina or 100
    local stamina_threshold = tonumber(hp.value_stamina) or 10
    if stamina_pct <= stamina_threshold then
        if not hp.disable_stamina then
            hp.return_why = "You have low stamina."
            hp.action = 99
            return "retreat"
        end
    end

    -- Encumbrance check
    local enc_pct = Char.encumbrance_value or 0
    local enc_threshold = tonumber(hp.value_encumbrance) or 50
    if enc_pct >= enc_threshold then
        if not hp.disable_encumbrance then
            hp.return_why = "You are too encumbered."
            hp.action = 99
            return "retreat"
        end
    end

    -- Spirit check
    local spirit = GameState.spirit or 0
    local max_spirit = GameState.max_spirit or 1
    if spirit > 0 and max_spirit > 0 and spirit <= 3 then
        hp.return_why = "You have dangerously low spirit."
        hp.action = 99
        return "retreat"
    end

    -- Bleeding check
    if GameState.bleeding then
        hp.return_why = "You are bleeding."
        hp.action = 99
        return "retreat"
    end

    return nil
end

---------------------------------------------------------------------------
-- Empath self-heal — cure wounds/scars
---------------------------------------------------------------------------
function Recovery.empath_self_heal(hp)
    if Stats.prof ~= "Empath" then return end
    if (GameState.mana or 0) < 30 then
        if not hp.use_herbs then
            hp.return_why = "Insufficient mana to self-heal. You are injured."
            hp.action = 99
        end
        return
    end

    local body_parts = {
        {wound = "head",      scar = "head",      cmd = "cure head"},
        {wound = "neck",      scar = "neck",      cmd = "cure neck"},
        {wound = "abdomen",   scar = "abdomen",   cmd = "cure abdomen"},
        {wound = "leftHand",  scar = "leftHand",  cmd = "cure left hand"},
        {wound = "rightHand", scar = "rightHand", cmd = "cure right hand"},
        {wound = "leftArm",   scar = "leftArm",   cmd = "cure left arm"},
        {wound = "rightArm",  scar = "rightArm",  cmd = "cure right arm"},
        {wound = "leftLeg",   scar = "leftLeg",   cmd = "cure left leg"},
        {wound = "rightLeg",  scar = "rightLeg",  cmd = "cure right leg"},
        {wound = "leftEye",   scar = "leftEye",   cmd = "cure left eye"},
        {wound = "rightEye",  scar = "rightEye",  cmd = "cure right eye"},
        {wound = "chest",     scar = "chest",      cmd = "cure chest"},
        {wound = "back",      scar = "back",       cmd = "cure back"},
        {wound = "nsys",      scar = "nsys",       cmd = "cure nerves"},
    }

    for _, part in ipairs(body_parts) do
        local wound_sev = Wounds[part.wound] or 0
        local scar_sev  = Scars[part.scar] or 0
        if wound_sev >= 1 or scar_sev >= 2 then
            fput(part.cmd)
            return
        end
    end
end

---------------------------------------------------------------------------
-- Combat herb usage — use eherbs in combat
---------------------------------------------------------------------------
function Recovery.combat_use_herbs(hp)
    if hp.no_herbs then return end
    if not Script.exists("eherbs") then return end

    Script.run("eherbs")
    wait_while(function() return Script.running("eherbs") end)
end

---------------------------------------------------------------------------
-- Fog return — use Voln fog, Spirit Guide (130), or Sign of Seeking (1020)
---------------------------------------------------------------------------
function Recovery.fog_return(hp)
    -- Voln Symbol of Return (9825)
    if hp.voln_fog and hp.my_society == "Voln" then
        if Spell[9825] and Spell[9825].known then
            fput("sym return")
            pause(2)
            return true
        end
    end

    -- Spirit Guide (130)
    if hp.fog_130 then
        if Spell[130] and Spell[130].known and Stats.level >= 30 and Spell[130].affordable then
            Spell[130]:cast()
            pause(2)
            return true
        end
    end

    -- Sign of Seeking (1020)
    if hp.fog_1020 then
        if Spell[1020] and Spell[1020].known and Spell[1020].affordable then
            Spell[1020]:cast()
            pause(2)
            return true
        end
    end

    return false
end

---------------------------------------------------------------------------
-- Wound/scar severity check — return true if character has serious injuries
---------------------------------------------------------------------------
function Recovery.has_serious_injuries()
    local body_parts = {
        "head", "neck", "chest", "abdomen", "back",
        "leftArm", "rightArm", "leftHand", "rightHand",
        "leftLeg", "rightLeg", "leftEye", "rightEye", "nsys"
    }

    for _, part in ipairs(body_parts) do
        if (Wounds[part] or 0) >= 2 or (Scars[part] or 0) >= 2 then
            return true
        end
    end
    return false
end

return Recovery
