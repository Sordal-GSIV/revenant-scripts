--- Bigshot Commands — combat command execution
-- Dispatches hunting commands to the appropriate handler based on command type.
-- Ported from bigshot.lic v5.12.1 (Elanthia-Online)
-- Original authors: SpiffyJr, Tillmen, Kalros, Hazado, Tysong, Athias, Falicor, Deysh, Nisugi

local command_check = require("command_check")

local M = {}

-- ==========================================================================
-- Module-level state (persists across calls within a hunting session)
-- ==========================================================================

local bigshot_aim = 0              -- ambush aim index
local bigshot_archery_aim = 0      -- ranged aim index
local bigshot_archery_stuck = {}   -- stuck arrow locations
local bigshot_archery_location = nil
local bigshot_unarmed_tier = 1     -- UAC tier: 1=decent, 2=good, 3=excellent
local bigshot_unarmed_followup = false
local bigshot_unarmed_followup_attack = ""
local bigshot_smite_list = {}      -- target IDs already smited
local bigshot_wand_index = 1       -- current wand index
local bigshot_bless = {}           -- weapon IDs needing blessing
local bigshot_mstrike_taken = false
local bigshot_rooted = false
local bigshot_bond_return = false
local bigshot_dislodge_target = nil
local bigshot_dislodge_location = {}
local bigshot_adrenal_surge_time = 0
local bigshot_703_list = {}
local bigshot_1614_list = {}
local bigshot_should_rest = false
local bigshot_rest_reason = ""
local COMMANDS_REGISTRY = {}       -- npc.id -> {command, ...} for once/room checks

-- ==========================================================================
-- Self-cast spell list (these spells do NOT target NPCs)
-- ==========================================================================

local SELFCAST_SPELLS = {
    [106]=true, [109]=true, [115]=true, [117]=true, [120]=true, [130]=true, [140]=true,
    [205]=true, [206]=true, [211]=true, [213]=true, [215]=true, [218]=true, [219]=true,
    [220]=true, [240]=true,
    [303]=true, [307]=true, [310]=true, [313]=true, [314]=true, [319]=true, [350]=true,
    [401]=true, [402]=true, [403]=true, [404]=true, [405]=true, [406]=true, [414]=true,
    [418]=true, [419]=true, [425]=true, [430]=true,
    [503]=true, [506]=true, [507]=true, [508]=true, [509]=true, [511]=true, [513]=true,
    [515]=true, [517]=true, [520]=true, [535]=true, [540]=true,
    [601]=true, [602]=true, [604]=true, [605]=true, [606]=true, [608]=true, [612]=true,
    [613]=true, [617]=true, [618]=true, [620]=true, [625]=true, [630]=true, [640]=true, [650]=true,
    [707]=true, [712]=true,
    [905]=true, [911]=true, [913]=true, [916]=true, [919]=true,
    [1003]=true, [1006]=true, [1007]=true, [1009]=true, [1010]=true, [1011]=true, [1012]=true,
    [1014]=true, [1017]=true, [1018]=true, [1019]=true, [1020]=true, [1025]=true, [1035]=true, [1040]=true,
    [1109]=true, [1119]=true, [1125]=true, [1130]=true, [1150]=true,
    [1202]=true, [1204]=true, [1208]=true, [1213]=true, [1214]=true, [1215]=true, [1216]=true,
    [1220]=true, [1235]=true,
    [1601]=true, [1605]=true, [1606]=true, [1607]=true, [1608]=true, [1609]=true, [1610]=true,
    [1611]=true, [1612]=true, [1613]=true, [1616]=true, [1617]=true, [1618]=true, [1619]=true, [1635]=true,
}

-- ==========================================================================
-- Utility: debug logger
-- ==========================================================================

local function debug_msg(bstate, msg)
    if bstate and bstate.debug_commands then
        respond("[bigshot:cmd] " .. msg)
    end
end

-- ==========================================================================
-- Utility: get live NPC count (excluding animated, appendages, untargetable)
-- ==========================================================================

local function npc_count(bstate)
    local npcs = GameObj.npcs()
    local count = 0
    for _, npc in ipairs(npcs or {}) do
        if not npc.status:find("dead") and not npc.status:find("gone") then
            local name_lower = (npc.name or ""):lower()
            -- skip animated (but not animated slush)
            if name_lower:find("^animated") and not name_lower:find("animated slush") then
                -- skip
            elseif npc.noun and npc.noun:match("^(?:arm|appendage|claw|limb|pincer|tentacle)s?$") then
                -- skip body parts
            else
                count = count + 1
            end
        end
    end
    return count
end

-- ==========================================================================
-- Utility: check if NPC is still a valid target in room
-- ==========================================================================

local function target_alive(npc)
    if not npc then return false end
    if npc.status and (npc.status:find("dead") or npc.status:find("gone")) then return false end
    -- Check NPC is still in room targets
    local targets = GameObj.npcs()
    for _, t in ipairs(targets or {}) do
        if t.id == npc.id then return true end
    end
    return false
end

-- ==========================================================================
-- once_commands_register — track commands executed per NPC
-- ==========================================================================

local function once_commands_register(npc, command)
    if not npc or not npc.id then return end
    if not COMMANDS_REGISTRY[npc.id] then
        COMMANDS_REGISTRY[npc.id] = {}
    end
    local reg = COMMANDS_REGISTRY[npc.id]
    for _, c in ipairs(reg) do
        if c == command then return end
    end
    reg[#reg + 1] = command
end

-- ==========================================================================
-- bs_put — enhanced fput with stun/web/prone/wait handling
-- ==========================================================================

function M.bs_put(command, bstate)
    debug_msg(bstate, "bs_put | " .. command)

    put(command)
    while true do
        local line = get()
        if not line then return nil end

        -- Handle "...wait N" / "Wait N"
        local wait_time = line:match("%.%.%.wait (%d+)") or line:match("Wait (%d+)")
        if wait_time then
            local hold = tonumber(wait_time) or 1
            if hold > 1 then pause(hold - 1) end
            put(command)

        -- Handle need to stand
        elseif line:find("struggle") and line:find("stand") then
            M.bs_put("stand", bstate)
            put(command)

        -- Handle stunned / webbed / can't do that
        elseif line:find("stunned") or line:find("can't do that while")
            or line:find("cannot seem") or line:find("can't seem")
            or line:find("don't seem") or line:find("Sorry, you may only type ahead") then
            if dead and dead() then
                return false
            end
            if stunned and stunned() then
                while stunned() do pause(0.25) end
            elseif Effects and Effects.Debuffs and Effects.Debuffs.active("Webbed") then
                while Effects.Debuffs.active("Webbed") do pause(0.25) end
            else
                pause(0.25)
            end
            put(command)
        else
            return line
        end
    end
end

-- ==========================================================================
-- change_stance — stance management with Stance Perfection support
-- ==========================================================================

function M.change_stance(new_stance, bstate)
    if not new_stance or new_stance == "" then return end
    debug_msg(bstate, "change_stance | " .. new_stance)

    -- Don't change stance while Spell 216 is active or dead
    if Spell and Spell[216] and Spell[216].active then return end
    if dead and dead() then return end

    new_stance = new_stance:lower()

    -- Handle numeric stance values (10-100) for Stance Perfection
    local perfect_stance = nil
    local num = tonumber(new_stance)
    if num then
        perfect_stance = new_stance
        if num <= 20 then new_stance = "advance"
        elseif num <= 40 then new_stance = "forward"
        elseif num <= 60 then new_stance = "neutral"
        elseif num <= 80 then new_stance = "guarded"
        else new_stance = "defensive" end
    end

    -- Already in this stance?
    if Char.stance and Char.stance:lower():find(new_stance) then
        return
    end

    -- If cast roundtime active and going defensive, settle for guarded
    if checkcastrt and checkcastrt() > 0 and new_stance:find("def") then
        if Char.stance == "guarded" then return end
    end

    waitrt()

    if perfect_stance and CMan and CMan.known and CMan.known("Stance Perfection") then
        local result = matchtimeout(3,
            "You are now in an?", "stance_ok",
            "You move into an?", "stance_ok",
            "You fall back into a", "stance_ok",
            "Cast Roundtime in effect", "cast_rt",
            "You are unable to change", "unable"
        )
        if not result then
            fput("cman stance " .. perfect_stance)
        else
            fput("cman stance " .. perfect_stance)
        end
    else
        fput("stance " .. new_stance)
    end
end

-- ==========================================================================
-- cmd_spell — Full spell casting via incant
-- ==========================================================================

function M.cmd_spell(args, target, bstate)
    -- Parse: [incant] <spell_id> [extra: open/closed/cast/channel/evoke] [element]
    local incant_prefix, spell_id_str, extra = args:match("^(incant%s+)?(%d+)%s*(.*)")
    if not spell_id_str then
        -- Fallback: just send as incant
        waitrt()
        waitcastrt()
        if target and target.id then
            fput("incant " .. args .. " at #" .. target.id)
        else
            fput("incant " .. args)
        end
        return true
    end

    local spell_id = tonumber(spell_id_str)
    local use_incant = (incant_prefix and incant_prefix ~= "")
    extra = (extra and extra ~= "") and extra:match("^%s*(.-)%s*$") or nil
    local selfcast = SELFCAST_SPELLS[spell_id] or false

    debug_msg(bstate, "cmd_spell | id=" .. spell_id .. " extra=" .. tostring(extra) .. " selfcast=" .. tostring(selfcast))

    -- Release existing prep if different spell
    if checkprep and checkprep() ~= "None" and Spell[spell_id] and checkprep() ~= Spell[spell_id].name then
        fput("release")
    end

    -- Rapid Fire (597/515) mana penalty check
    if Spell[597] and Spell[597].active and Spell[spell_id] then
        local cost = Spell[spell_id].mana_cost or 0
        if cost > 0 and (cost + 5) > (Char.mana or 0) then
            return false, "rapid fire mana penalty"
        end
    end

    -- Spell known check
    if Spell[spell_id] and Spell[spell_id].known ~= nil and not Spell[spell_id].known then
        return false, "spell not known"
    end

    -- Special cooldown/active checks
    if spell_id == 506 and Spell[506] and Spell[506].active then
        return false, "celerity already active"
    end
    if spell_id == 9605 and Effects and Effects.Cooldowns.active("Surge of Strength") then
        return false, "surge cooldown"
    end
    if spell_id == 9625 and Effects and Effects.Cooldowns.active("Burst of Swiftness") then
        return false, "burst cooldown"
    end
    if spell_id == 335 and Effects and Effects.Cooldowns.active("335") then
        return false, "divine wrath cooldown"
    end
    if spell_id == 608 and hidden and hidden() then
        return false, "hidden with 608"
    end
    if spell_id == 703 and target then
        for _, id in ipairs(bigshot_703_list) do
            if id == target.id then return false, "703 already on target" end
        end
    end
    if spell_id == 1614 and target then
        for _, id in ipairs(bigshot_1614_list) do
            if id == target.id then return false, "1614 already on target" end
        end
    end
    if spell_id == 720 and Effects and Effects.Cooldowns.active("Implosion") then
        return false, "implosion cooldown"
    end

    -- Short duration buff cooldown checks: 140,211,215,219,919,1619,1650
    local short_cd_spells = {[140]=true, [211]=true, [215]=true, [219]=true, [919]=true, [1619]=true, [1650]=true}
    if short_cd_spells[spell_id] and Spell[spell_id] and Effects and Effects.Cooldowns.active(Spell[spell_id].name) then
        return false, "short buff cooldown"
    end

    -- Target alive check (skip for 902 and 411 which are area spells)
    if spell_id ~= 902 and spell_id ~= 411 then
        if not selfcast and target and not target_alive(target) then
            return false, "target gone"
        end
    end

    -- Affordability check
    if Spell[spell_id] and not Spell[spell_id].affordable then
        -- Try wracking if configured
        if bstate and bstate.use_wracking then
            M.wrack(bstate)
        end
    end

    if Spell[spell_id] and not Spell[spell_id].affordable then
        if spell_id ~= 9605 and spell_id ~= 506 and spell_id ~= 902 and spell_id ~= 411 then
            bigshot_should_rest = true
            bigshot_rest_reason = "out of mana"
        end
        return false, "spell not affordable"
    end

    waitrt()
    waitcastrt()

    -- Casting logic
    if not use_incant then
        -- Non-incant path: use Spell[].cast / force_cast / force_channel / force_evoke
        if spell_id == 506 or spell_id == 902 then
            -- Self-only spells with no target
            if Spell[spell_id].cast then
                Spell[spell_id].cast()
            else
                fput("incant " .. spell_id_str)
            end
        elseif selfcast then
            if Spell[spell_id].cast then
                Spell[spell_id].cast(Char.name)
            else
                fput("incant " .. spell_id_str)
            end
        elseif extra and target then
            local target_str = "#" .. target.id
            if extra:find("cast") then
                local clean_extra = extra:gsub("cast", ""):match("^%s*(.-)%s*$")
                if Spell[spell_id].force_cast then
                    Spell[spell_id].force_cast(target_str, clean_extra)
                else
                    fput("incant " .. spell_id_str .. " " .. (extra or "") .. " at " .. target_str)
                end
            elseif extra:find("channel") then
                local clean_extra = extra:gsub("channel", ""):match("^%s*(.-)%s*$")
                if Spell[spell_id].force_channel then
                    Spell[spell_id].force_channel(target_str, clean_extra)
                else
                    fput("incant " .. spell_id_str .. " " .. (extra or "") .. " at " .. target_str)
                end
            elseif extra:find("evoke") then
                local clean_extra = extra:gsub("evoke", ""):match("^%s*(.-)%s*$")
                if Spell[spell_id].force_evoke then
                    Spell[spell_id].force_evoke(target_str, clean_extra)
                else
                    fput("incant " .. spell_id_str .. " " .. (extra or "") .. " at " .. target_str)
                end
            else
                if Spell[spell_id].cast then
                    Spell[spell_id].cast(target_str, extra)
                else
                    fput("incant " .. spell_id_str .. " " .. (extra or "") .. " at " .. target_str)
                end
            end
        elseif target then
            if Spell[spell_id].cast then
                Spell[spell_id].cast("#" .. target.id)
            else
                fput("incant " .. spell_id_str .. " at #" .. target.id)
            end
        else
            if Spell[spell_id].cast then
                Spell[spell_id].cast()
            else
                fput("incant " .. spell_id_str)
            end
        end
    else
        -- Incant path: use Spell[].force_incant
        if selfcast then
            M.bs_put("target clear", bstate)
        end

        -- Stance dance for incant spells
        local hunting_stance = (bstate and bstate.hunting_stance) or "offensive"
        if Spell[spell_id].stance or (tostring(spell_id):find("1700") and extra and extra:find("evoke")) then
            M.change_stance("offensive", bstate)
        end

        if Spell[spell_id].force_incant then
            Spell[spell_id].force_incant(extra)
        else
            if extra then
                fput("incant " .. spell_id_str .. " " .. extra)
            else
                fput("incant " .. spell_id_str)
            end
        end

        M.change_stance(hunting_stance, bstate)

        if selfcast and target then
            M.bs_put("target #" .. target.id, bstate)
        end
    end

    return true
end

-- ==========================================================================
-- cmd_spell_manual — Manual prep/cast/channel flow
-- ==========================================================================

function M.cmd_spell_manual(cmd_type, args, target, bstate)
    debug_msg(bstate, "cmd_spell_manual | " .. cmd_type .. " " .. args)

    waitrt()
    waitcastrt()

    if target and cmd_type == "cast" then
        fput(cmd_type .. " " .. args .. " at #" .. target.id)
    else
        fput(cmd_type .. " " .. args)
    end
    return true
end

-- ==========================================================================
-- cmd_assault — Combat assault maneuvers (Barrage, Flurry, Fury, etc.)
-- ==========================================================================

function M.cmd_assault(command, target, bstate)
    debug_msg(bstate, "cmd_assault | " .. command)

    local complete_patterns = {
        "Distracted, you hesitate",
        "glides to its inevitable end with one final twirl",
        "You feel a fair amount more durable",
        "With a final snap of your wrist",
        "You complete your assault",
        "to the ready, your assault complete",
        "Upon firing your last",
        "With a final, explosive breath",
        "recentering yourself for the fight",
        "You don't seem to be able to move your legs to do that",
        "too injured",
        "already dead",
        "little bit late",
        "could not find",
    }

    local error_patterns = {
        "Barrage can not be used with attack as the attack type",
        "may not be activated within 60 seconds of a Multi%-Strike",
        "%.%.%.wait",
        "is still in cooldown",
        "Your mind clouds with confusion and you glance around uncertainly",
        "You can't reach",
    }

    local commands_map = {
        barrage  = "Barrage",
        flurry   = "Flurry",
        fury     = "Fury",
        gthrusts = "Guardant Thrusts",
        pummel   = "Pummel",
        thrash   = "Thrash",
    }

    local cmd_clean = command:match("^(%S+)")
    local ability_name = commands_map[cmd_clean:lower()]
    if not ability_name then return false, "unknown assault" end

    -- Check availability and affordability
    if Weapon and Weapon.available and not Weapon.available(ability_name) then
        return false, "not available"
    end
    if Weapon and Weapon.affordable and not Weapon.affordable(ability_name) then
        return false, "not affordable"
    end

    -- Fury with tier3 override
    if ability_name == "Fury" and bigshot_unarmed_tier == 3 and bstate and bstate.tier3_attack then
        command = ability_name .. " " .. bstate.tier3_attack
    end

    waitrt()
    waitcastrt()

    local break_out = os.time() + 12
    while true do
        if target and target.id then
            fput("weapon " .. command .. " #" .. target.id)
        else
            fput("weapon " .. command)
        end

        local result = matchtimeout(10,
            "%.%.%.wait", "wait",
            "Barrage can not be used with attack as the attack type", "swap",
            "may not be activated within 60 seconds", "mstrike_cd",
            "is still in cooldown", "cooldown",
            "Your mind clouds with confusion", "confused",
            "Distracted, you hesitate", "complete",
            "glides to its inevitable end", "complete",
            "You feel a fair amount more durable", "complete",
            "With a final snap of your wrist", "complete",
            "You complete your assault", "complete",
            "to the ready, your assault complete", "complete",
            "Upon firing your last", "complete",
            "With a final, explosive breath", "complete",
            "recentering yourself for the fight", "complete",
            "don't seem to be able to move", "complete",
            "too injured", "complete",
            "already dead", "complete",
            "little bit late", "complete",
            "could not find", "complete",
            "You can't reach", "complete"
        )

        if result == "wait" then
            waitrt()
            if Weapon and Weapon.affordable and not Weapon.affordable(ability_name) then break end
        elseif result == "swap" then
            fput("swap")
        elseif result == "mstrike_cd" or result == "cooldown" or result == "confused" then
            break
        elseif result == "complete" or os.time() > break_out then
            break
        elseif not result then
            bigshot_should_rest = true
            bigshot_rest_reason = "Unknown result from assault"
            break
        end
        pause(0.25)
    end
    return true
end

-- ==========================================================================
-- cmd_weapons — Weapon techniques (Pin Down, Cripple, Charge, etc.)
-- ==========================================================================

function M.cmd_weapons(command, target, bstate)
    debug_msg(bstate, "cmd_weapons | " .. command)

    local commands_map = {
        charge        = "Charge",
        clash         = "Clash",
        cripple       = "Cripple",
        cyclone       = "Cyclone",
        dizzyingswing = "Dizzying Swing",
        pindown       = "Pin Down",
        pulverize     = "Pulverize",
        twinhammer    = "Twin Hammerfists",
        volley        = "Volley",
        wblade        = "Whirling Blade",
        whirlwind     = "Whirlwind",
    }

    local cmd_clean = command:match("^(%S+)"):lower()
    local ability_name = commands_map[cmd_clean]
    if not ability_name then return false, "unknown weapon technique" end

    if Weapon and Weapon.available and not Weapon.available(ability_name) then
        return false, "not available"
    end
    if Weapon and Weapon.affordable and not Weapon.affordable(ability_name) then
        return false, "not affordable"
    end

    -- Charge and Twin Hammer can't be used on prone targets
    if target and target.status and target.status:find("lying down") then
        if ability_name == "Charge" or ability_name == "Twin Hammerfists" then
            return false, "target prone"
        end
    end

    waitrt()
    waitcastrt()

    local break_out = os.time() + 2
    while true do
        if target and target.id then
            fput("weapon " .. command .. " #" .. target.id)
        else
            fput("weapon " .. command)
        end

        local result = matchtimeout(1,
            "%.%.%.wait", "wait",
            "You rush forward", "complete",
            "Steeling yourself for a brawl", "complete",
            "You reverse your grip", "complete",
            "a blurred cyclone", "complete",
            "lash out in a strike", "complete",
            "You take quick assessment", "complete",
            "pulverize your foes", "complete",
            "You raise your hands high", "complete",
            "filling the sky with a volley", "complete",
            "With a broad flourish", "complete",
            "Twisting and spinning", "complete",
            "awkward proposition", "complete",
            "is out of reach", "complete",
            "don't seem to be able to move", "complete",
            "too injured", "complete",
            "already dead", "complete",
            "little bit late", "complete",
            "could not find", "complete"
        )

        if result == "wait" then
            waitrt()
            if Weapon and Weapon.affordable and not Weapon.affordable(ability_name) then break end
        elseif result == "complete" or os.time() > break_out then
            break
        elseif not result then
            bigshot_should_rest = true
            bigshot_rest_reason = "Unknown result from weapon technique"
            break
        end
        pause(0.25)
    end
    return true
end

-- ==========================================================================
-- cmd_shields — Shield maneuvers (Bash, Charge, Pin, Push, etc.)
-- ==========================================================================

function M.cmd_shields(command, target, bstate)
    debug_msg(bstate, "cmd_shields | " .. command)

    local commands_map = {
        ["shield bash"]    = "Shield Bash",
        ["shield charge"]  = "Shield Charge",
        ["shield pin"]     = "Shield Pin",
        ["shield push"]    = "Shield Push",
        ["shield strike"]  = "Shield Strike",
        ["shield throw"]   = "Shield Throw",
        ["shield trample"] = "Shield Trample",
    }

    local ability_name = commands_map[command:lower()]
    if not ability_name then return false, "unknown shield maneuver" end

    -- Check if using CMan Shield Bash or Shield version
    local use_cman = false
    if command:lower():find("shield bash") and CMan and CMan.available and CMan.available("Shield Bash") then
        use_cman = true
        if not CMan.affordable("Shield Bash") then
            return false, "not affordable"
        end
        command = "cman sbash"
    else
        if Shield and Shield.available and not Shield.available(ability_name) then
            return false, "not available"
        end
        if Shield and Shield.affordable and not Shield.affordable(ability_name) then
            return false, "not affordable"
        end
    end

    waitrt()
    waitcastrt()

    local break_out = os.time() + 2
    while true do
        if target and target.id then
            fput(command .. " #" .. target.id)
        else
            fput(command)
        end

        local result = matchtimeout(1,
            "%.%.%.wait", "wait",
            "You snap your arm", "complete",
            "attempt a shield bash", "complete",
            "attempt a shield charge", "complete",
            "launch a quick bash", "complete",
            "diversionary shield bash", "complete",
            "charge headlong towards", "complete",
            "attempt to push", "complete",
            "awkward proposition", "complete",
            "little bit late", "complete",
            "still stunned", "complete",
            "too injured", "complete",
            "You cannot", "complete",
            "Could not find", "complete",
            "seconds", "complete"
        )

        if result == "wait" then
            waitrt()
            if use_cman then
                if CMan and CMan.affordable and not CMan.affordable("Shield Bash") then break end
            else
                if Shield and Shield.affordable and not Shield.affordable(ability_name) then break end
            end
        elseif result == "complete" or os.time() > break_out then
            break
        elseif not result then
            bigshot_should_rest = true
            bigshot_rest_reason = "Unknown result from shield maneuver"
            break
        end
        pause(0.25)
    end
    return true
end

-- ==========================================================================
-- cmd_cmans — Combat maneuvers (Bull Rush, Coup de Grace, etc.)
-- ==========================================================================

function M.cmd_cmans(command, target, bstate)
    debug_msg(bstate, "cmd_cmans | " .. command)

    local commands_map = {
        bullrush     = "Bull Rush",
        coupdegrace  = "Coup de Grace",
        cpress       = "Crowd Press",
        dirtkick     = "Dirtkick",
        disarm       = "Disarm Weapon",
        exsanguinate = "Exsanguinate",
        feint        = "Feint",
        gkick        = "Groin Kick",
        hamstring    = "Hamstring",
        haymaker     = "Haymaker",
        headbutt     = "Headbutt",
        kifocus      = "Ki Focus",
        leapattack   = "Leap Attack",
        mblow        = "Mighty Blow",
        sattack      = "Spin Attack",
        sbash        = "Shield Bash",
        sblow        = "Staggering Blow",
        scleave      = "Spell Cleave",
        sthieve      = "Spell Thieve",
        sunder       = "Sunder Shield",
        tackle       = "Tackle",
        trip         = "Trip",
        truestrike   = "True Strike",
        vaultkick    = "Vault Kick",
    }

    local cmd_clean = command:match("^(%S+)"):lower()
    local ability_name = commands_map[cmd_clean]
    if not ability_name then return false, "unknown cman" end

    if CMan and CMan.available and not CMan.available(ability_name) then
        return false, "not available"
    end
    if CMan and CMan.affordable and not CMan.affordable(ability_name) then
        return false, "not affordable"
    end

    -- Bull Rush can't be used on prone targets
    if cmd_clean == "bullrush" and target and target.status and target.status:find("lying down") then
        return false, "target prone"
    end

    -- Spell Cleave cooldown
    if cmd_clean == "scleave" and Effects and Effects.Cooldowns.active("Spell Cleave") then
        return false, "spell cleave cooldown"
    end
    -- Spell Thieve cooldown
    if cmd_clean == "sthieve" and Effects and Effects.Cooldowns.active("Spell Thieve") then
        return false, "spell thieve cooldown"
    end

    waitrt()
    waitcastrt()

    local break_out = os.time() + 2
    while true do
        if target and target.id then
            fput("cman " .. command .. " #" .. target.id)
        else
            fput("cman " .. command)
        end

        local result = matchtimeout(1,
            "%.%.%.wait", "wait",
            "awkward proposition", "complete",
            "You can't reach", "complete",
            "little bit late", "complete",
            "still stunned", "complete",
            "too injured", "complete",
            "You cannot", "complete",
            "Could not find", "complete",
            "seconds", "complete",
            "release your grip", "complete",
            "feat of strength empowers", "complete",
            "your grasp", "complete",
            "leaving you flailing", "complete",
            "completely miss", "complete",
            "unable to complete", "complete",
            "dip your shoulder and rush", "complete",
            "intending to finish", "complete",
            "isn't injured enough", "complete",
            "thwarts your attempt", "complete",
            "You approach", "complete",
            "You maneuver in close", "complete",
            "try to maneuver", "complete",
            "can't manage to do that right now", "complete",
            "rooted in place", "complete",
            "foot and let it fly", "complete",
            "clump of dust", "complete",
            "blur of steel", "complete",
            "slows to a trickle", "complete",
            "shrill yell and leap", "complete",
            "is not bleeding", "complete",
            "You feint", "complete",
            "deliver a kick", "complete",
            "out of reach", "complete",
            "try to hamstring", "complete",
            "roundhouse punch", "complete",
            "attempt to headbutt", "complete",
            "leap into the air", "complete",
            "low enough for you to attack", "complete",
            "isn't flying", "complete",
            "with all.* your might", "complete",
            "with staggering might", "complete",
            "concentrate on the magical wards", "complete",
            "anti%-magical equipment", "complete",
            "spinning leap towards", "complete",
            "split it asunder", "complete",
            "holding a shield", "complete",
            "You hurl yourself", "complete",
            "jerk the weapon sharply", "complete",
            "will strike true", "complete",
            "vaulting kick", "complete",
            "is lying down", "complete",
            "concentrate on the magic", "complete",
            "summon your inner ki", "complete",
            "you attempt to disarm", "complete",
            "haven't learned how to disarm", "complete",
            "You swing your", "complete",
            "is not holding a weapon", "complete"
        )

        if result == "wait" then
            waitrt()
            if CMan and CMan.affordable and not CMan.affordable(ability_name) then break end
        elseif result == "complete" or os.time() > break_out then
            break
        elseif not result then
            bigshot_should_rest = true
            bigshot_rest_reason = "Unknown result from cman"
            break
        end
        pause(0.25)
    end
    return true
end

-- ==========================================================================
-- cmd_rogue_cmans — Rogue combat maneuvers
-- ==========================================================================

function M.cmd_rogue_cmans(command, target, bstate)
    debug_msg(bstate, "cmd_rogue_cmans | " .. command)

    local commands_map = {
        cutthroat  = "Cutthroat",
        divert     = "Divert",
        shroud     = "Dust Shroud",
        eviscerate = "Eviscerate",
        eyepoke    = "Eyepoke",
        footstomp  = "Footstomp",
        garrote    = "Garrote",
        kneebash   = "Kneebash",
        mug        = "Mug",
        nosetweak  = "Nosetweak",
        subdue     = "Subdue",
        spunch     = "Sucker Punch",
        sweep      = "Sweep",
        swiftkick  = "Swiftkick",
        templeshot = "Templeshot",
        throatchop = "Throatchop",
    }

    local cmd_clean = command:match("^(%S+)"):lower()
    local ability_name = commands_map[cmd_clean]
    if not ability_name then return false, "unknown rogue cman" end

    if CMan and CMan.available and not CMan.available(ability_name) then
        return false, "not available"
    end
    if CMan and CMan.affordable and not CMan.affordable(ability_name) then
        return false, "not affordable"
    end

    waitrt()
    waitcastrt()

    local break_out = os.time() + 2
    while true do
        if target and target.id then
            fput("cman " .. command .. " #" .. target.id)
        else
            fput("cman " .. command)
        end

        local result = matchtimeout(1,
            "%.%.%.wait", "wait",
            "awkward proposition", "complete",
            "You can't reach", "complete",
            "little bit late", "complete",
            "still stunned", "complete",
            "too injured", "complete",
            "You cannot", "complete",
            "Could not find", "complete",
            "seconds", "complete",
            "attempt to slit", "complete",
            "Try hiding first", "complete",
            "kicking up as much dirt", "complete",
            "you're already out of sight", "complete",
            "prepare your diversion", "complete",
            "poised to eviscerate", "complete",
            "finger at the eye", "complete",
            "attempting to footstomp", "complete",
            "fling your wire around", "complete",
            "damage to yourself", "complete",
            "down at the knee", "complete",
            "boldly accost", "complete",
            "won't fall for that again", "complete",
            "reach out and grab", "complete",
            "stand up first", "complete",
            "spring from hiding", "complete",
            "You swing", "complete",
            "crouch and sweep", "complete",
            "attempting a swiftkick", "complete",
            "swing the blunt end", "complete",
            "You chop", "complete"
        )

        if result == "wait" then
            waitrt()
            if CMan and CMan.affordable and not CMan.affordable(ability_name) then break end
        elseif result == "complete" or os.time() > break_out then
            break
        elseif not result then
            bigshot_should_rest = true
            bigshot_rest_reason = "Unknown result from rogue cman"
            break
        end
        pause(0.25)
    end
    return true
end

-- ==========================================================================
-- cmd_feats — Chastise, Excoriate
-- ==========================================================================

function M.cmd_feats(command, target, bstate)
    debug_msg(bstate, "cmd_feats | " .. command)

    local commands_map = {
        chastise  = "Chastise",
        excoriate = "Excoriate",
    }

    local cmd_clean = command:match("^(%S+)"):lower()
    local ability_name = commands_map[cmd_clean]
    if not ability_name then return false, "unknown feat" end

    if Feat and Feat.available and not Feat.available(ability_name) then
        return false, "not available"
    end
    if Feat and Feat.affordable and not Feat.affordable(ability_name) then
        return false, "not affordable"
    end

    waitrt()
    waitcastrt()

    local break_out = os.time() + 2
    while true do
        if target and target.id then
            fput("feat " .. command .. " #" .. target.id)
        else
            fput("feat " .. command)
        end

        local result = matchtimeout(1,
            "%.%.%.wait", "wait",
            "as you lunge at", "complete",
            "call down the excoriating power", "complete",
            "awkward proposition", "complete",
            "You can't reach", "complete",
            "little bit late", "complete",
            "still stunned", "complete",
            "too injured", "complete",
            "You cannot", "complete",
            "Could not find", "complete",
            "seconds", "complete"
        )

        if result == "wait" then
            waitrt()
            if Feat and Feat.affordable and not Feat.affordable(ability_name) then break end
        elseif result == "complete" or os.time() > break_out then
            break
        elseif not result then
            bigshot_should_rest = true
            bigshot_rest_reason = "Unknown result from feat"
            break
        end
        pause(0.25)
    end
    return true
end

-- ==========================================================================
-- cmd_warrior_shouts — Warcry variants
-- ==========================================================================

function M.cmd_warrior_shouts(command, target, bstate)
    debug_msg(bstate, "cmd_warrior_shouts | " .. command)

    local cmd = command:lower()

    -- Overexerted debuff check
    if Effects and Effects.Debuffs.active("Overexerted") then
        return false, "overexerted"
    end

    -- Stamina requirements per shout type
    local stam = Char.stamina or 0
    if cmd == "shout"       and stam < 25 then return false, "not enough stamina" end
    if cmd == "yowlp"       and stam < 11 then return false, "not enough stamina" end
    if cmd == "holler"      and stam < 31 then return false, "not enough stamina" end
    if cmd == "bellow all"  and stam < 21 then return false, "not enough stamina" end
    if cmd == "bellow"      and stam < 11 then return false, "not enough stamina" end
    if cmd == "growl all"   and stam < 15 then return false, "not enough stamina" end
    if cmd == "growl"       and stam <  8 then return false, "not enough stamina" end
    if cmd == "cry all"     and stam < 31 then return false, "not enough stamina" end
    if cmd == "cry"         and stam < 16 then return false, "not enough stamina" end

    waitrt()
    waitcastrt()

    -- Targeted vs untargeted shouts
    if cmd:find("all") then
        fput("warcry " .. cmd)
    elseif cmd:find("bellow") or cmd:find("growl") or cmd:find("cry") then
        if target and target.id then
            fput("warcry " .. cmd .. " #" .. target.id)
        else
            fput("warcry " .. cmd)
        end
    else
        fput("warcry " .. cmd)
    end

    -- Wait for result
    local result = matchtimeout(2,
        "let loose an echoing shout", "ok",
        "resounding yowlp", "ok",
        "thundering holler", "ok",
        "fighting spirit is bolstered", "ok",
        "nerve%-shattering bellow", "ok",
        "eerie, modulating cry", "ok",
        "You must be an active member", "fail",
        "Roundtime", "ok",
        "seconds", "ok"
    )

    if not result then
        bigshot_should_rest = true
        bigshot_rest_reason = "Unknown result from warcry"
    end

    pause(0.5)
    return true
end

-- ==========================================================================
-- cmd_unarmed — UAC system with tier progression
-- ==========================================================================

function M.cmd_unarmed(command, target, bstate)
    if not command or command == "" then command = "punch" end
    local manual_aim = ""
    -- Parse "unarmed punch head" form
    local base_cmd, aim_part = command:match("^(%S+)%s*(.*)$")
    if aim_part and aim_part ~= "" then
        manual_aim = aim_part
    end
    command = base_cmd or command

    debug_msg(bstate, "cmd_unarmed | " .. command .. " aim=" .. manual_aim)

    if not target_alive(target) then return false, "target gone" end

    local aim_list = (bstate and bstate.aim_locations) or {"head", "right leg", "left leg", "chest"}
    local tier3_attack = bstate and bstate.tier3_attack or nil

    -- Reset aim index if manual aim
    if manual_aim ~= "" and bigshot_aim == 0 then bigshot_aim = -1 end
    bigshot_mstrike_taken = false

    -- Voln smite for noncorporeal undead at tier 3
    if target.type and target.type:find("noncorporeal") and bigshot_unarmed_tier == 3 then
        if Spell and Spell[9821] and Spell[9821].known and bstate and bstate.uac_smite then
            local found = false
            for _, id in ipairs(bigshot_smite_list) do
                if id == target.id then found = true; break end
            end
            if not found then
                M.cmd_volnsmite(target, bstate)
            end
        end
    end

    -- MStrike integration
    if not (bstate and bstate.uac_no_mstrike) then
        if tier3_attack and bigshot_unarmed_tier == 3 then
            M.cmd_mstrike("mstrike " .. tier3_attack, target, bstate)
        else
            M.cmd_mstrike("mstrike " .. command, target, bstate)
        end
        pause(0.3)
    end

    -- If mstrike was taken, skip the regular attack
    if not bigshot_mstrike_taken then
        -- Determine attack command based on tier and followup
        local attack_cmd
        if bigshot_unarmed_tier == 3 and not bigshot_unarmed_followup and tier3_attack then
            attack_cmd = tier3_attack
        elseif bigshot_unarmed_followup then
            attack_cmd = bigshot_unarmed_followup_attack
        else
            attack_cmd = command
        end

        -- Build full command with aim
        local full_cmd
        if manual_aim ~= "" then
            full_cmd = attack_cmd .. " #" .. target.id .. " " .. manual_aim
        elseif bigshot_aim >= 0 and bigshot_aim < #aim_list and aim_list[bigshot_aim + 1] then
            full_cmd = attack_cmd .. " #" .. target.id .. " " .. aim_list[bigshot_aim + 1]
        else
            full_cmd = attack_cmd .. " #" .. target.id
        end

        waitrt()
        fput(full_cmd)
    end

    -- Parse UAC result lines
    local time_out = os.time() + 5
    while true do
        local line = get()
        if not line then break end

        -- Tier detection
        if line:find("You have decent positioning") then
            bigshot_unarmed_tier = 1
        elseif line:find("You have good positioning") then
            bigshot_unarmed_tier = 2
        elseif line:find("You have excellent positioning") then
            bigshot_unarmed_tier = 3
        end

        -- Followup tracking
        if line:find("Strike leaves foe vulnerable to a followup") then
            bigshot_unarmed_followup = true
            bigshot_unarmed_followup_attack = line:match("followup (.+) attack") or command
        end

        -- Endroll check for followup end
        if bigshot_unarmed_followup and line:find("= .* d100: .* = ") then
            local endroll = line:match("= (-?%d+)$")
            if endroll and tonumber(endroll) > 100 then
                bigshot_unarmed_followup = false
            end
        end

        -- Aim advancement on miss
        if line:find("You fail to find an opening") then
            bigshot_aim = bigshot_aim + 1
        elseif line:find("You cannot aim that high") or line:find("is already missing that") then
            bigshot_aim = bigshot_aim + 1
            if aim_list[bigshot_aim + 1] then
                fput(command .. " #" .. target.id .. " " .. aim_list[bigshot_aim + 1])
            end
        elseif line:find("does not have") then
            bigshot_aim = bigshot_aim + 1
            if aim_list[bigshot_aim + 1] then
                fput(command .. " #" .. target.id .. " " .. aim_list[bigshot_aim + 1])
            end
        end

        -- Roundtime = attack complete, reset aim
        if line:find("Roundtime:") then
            bigshot_aim = 0
            break
        end

        -- Break conditions
        if line:find("Try standing up first") or line:find("[wW]ait %d+ sec")
            or line:find("Sorry,") or line:find("can't do that while entangled")
            or line:find("You are still stunned") or line:find("from here") then
            break
        end

        if line:find("don't seem to be able to move") then
            bigshot_rooted = true
            break
        end

        if line:find("unable to muster the will") or line:find("Your rage causes you") then
            -- Try Soothe (1201)
            if Spell and Spell[1201] and Spell[1201].known and Spell[1201].affordable then
                Spell[1201].cast()
            end
            break
        end

        -- Target dead or other terminal conditions
        if not target_alive(target) or line:find("currently have no valid target")
            or line:find("somebody already did the job") or line:find("What were you referring to") then
            bigshot_unarmed_tier = 1
            bigshot_unarmed_followup = false
            bigshot_unarmed_followup_attack = ""
            break
        end

        if os.time() > time_out then break end
    end

    bigshot_mstrike_taken = false
    return true
end

-- ==========================================================================
-- cmd_mstrike — Multi-strike with stamina checks
-- ==========================================================================

function M.cmd_mstrike(args, target, bstate)
    debug_msg(bstate, "cmd_mstrike | " .. (args or ""))

    -- MStrike spell support for Paladins/Empaths
    M.mstrike_spell_check(bstate)

    -- Overexerted check
    if Effects and Effects.Debuffs.active("Overexerted") then
        bigshot_mstrike_taken = false
        return false, "overexerted"
    end

    local moc_skill = (Skills and Skills.multiopponentcombat) or 0
    local mob_threshold = (bstate and bstate.mstrike_mob) or 2
    local stamina_cd = (bstate and bstate.mstrike_stamina_cooldown) or 40
    local stamina_qs = (bstate and bstate.mstrike_stamina_quickstrike) or 60
    local use_quickstrike = bstate and bstate.mstrike_quickstrike
    local use_cooldown = bstate and bstate.mstrike_cooldown
    local current_stam = Char.stamina or 0
    local alive_count = npc_count(bstate)

    -- Extract the base command (strip "mstrike " prefix)
    local base_cmd = args:match("^mstrike%s+(.+)$") or args

    if moc_skill >= 30 then
        local cd_active = Effects and Effects.Cooldowns.active("Multi-Strike")
        if not cd_active or (use_cooldown and current_stam >= stamina_cd) then
            if use_quickstrike and current_stam >= stamina_qs and not (Effects and Effects.Debuffs.active("Overexerted")) then
                if alive_count >= mob_threshold or not target then
                    M.bs_put("quickstrike 1 " .. base_cmd, bstate)
                else
                    M.bs_put("quickstrike 1 " .. base_cmd .. " #" .. target.id, bstate)
                end
            else
                if alive_count >= mob_threshold or not target then
                    M.bs_put(base_cmd, bstate)
                else
                    M.bs_put(base_cmd .. " #" .. target.id, bstate)
                end
            end
            bigshot_mstrike_taken = true
        end
    elseif moc_skill >= 5 and alive_count >= mob_threshold then
        local cd_active = Effects and Effects.Cooldowns.active("Multi-Strike")
        if not cd_active or (use_cooldown and current_stam >= stamina_cd) then
            if use_quickstrike and current_stam >= stamina_qs and not (Effects and Effects.Debuffs.active("Overexerted")) then
                M.bs_put("quickstrike 1 " .. base_cmd, bstate)
            else
                M.bs_put(base_cmd, bstate)
            end
            bigshot_mstrike_taken = true
        end
    end

    return bigshot_mstrike_taken
end

-- ==========================================================================
-- mstrike_spell_check — Rejuvenation (1607) and Adrenal Surge (1107)
-- ==========================================================================

function M.mstrike_spell_check(bstate)
    local stamina_req = (bstate and (bstate.mstrike_stamina_cooldown or bstate.mstrike_stamina_quickstrike)) or 40

    -- Rejuvenation (1607)
    if Spell and Spell[1607] and Spell[1607].known and not Spell[1607].active and Spell[1607].affordable then
        if (Char.stamina or 0) < stamina_req then
            waitcastrt()
            if Spell[1607].cast then Spell[1607].cast() end
        end
    end

    -- Adrenal Surge (1107)
    if Spell and Spell[1107] and Spell[1107].known and Spell[1107].affordable then
        if not (Spell[9010] and Spell[9010].active) and os.time() >= bigshot_adrenal_surge_time then
            if (Char.stamina or 0) < stamina_req then
                waitcastrt()
                if Spell[1107].cast then Spell[1107].cast() end
                bigshot_adrenal_surge_time = os.time() + 301
            end
        end
    end
end

-- ==========================================================================
-- cmd_volnsmite — Voln smite for noncorporeal undead
-- ==========================================================================

function M.cmd_volnsmite(target, bstate)
    debug_msg(bstate, "cmd_volnsmite | target=" .. (target and target.id or "nil"))

    -- Only smite undead/noncorporeal targets not already smited
    while true do
        -- Check if already smited
        local already = false
        for _, id in ipairs(bigshot_smite_list) do
            if id == target.id then already = true; break end
        end
        if already then break end

        if not target_alive(target) then break end

        -- Check type
        local is_undead = target.type and (target.type:find("undead") or target.type:find("noncorporeal"))
        if not is_undead then break end

        local result = matchtimeout(1,
            "Roundtime", "ok",
            "What were you referring to", "gone",
            "somebody already did the job", "done"
        )

        fput("smite #" .. target.id)

        result = matchtimeout(2,
            "Roundtime", "ok",
            "What were you referring to", "gone",
            "somebody already did the job", "done"
        )

        if result == "done" then
            bigshot_smite_list[#bigshot_smite_list + 1] = target.id
            break
        elseif result == "gone" then
            break
        end

        pause(1)
    end
    return true
end

-- ==========================================================================
-- cmd_bearhug — Extended grapple loop (up to 17 seconds)
-- ==========================================================================

function M.cmd_bearhug(target, bstate)
    debug_msg(bstate, "cmd_bearhug")

    if CMan and CMan.available and not CMan.available("Bearhug") then
        return false, "not available"
    end
    if CMan and CMan.affordable and not CMan.affordable("Bearhug") then
        return false, "not affordable"
    end

    waitrt()
    waitcastrt()

    local break_out = os.time() + 17
    while true do
        if target and target.id then
            fput("cman bearhug #" .. target.id)
        else
            fput("cman bearhug")
        end

        local result = matchtimeout(16,
            "%.%.%.wait", "wait",
            "You release your grip", "complete",
            "You feel a fair amount stronger", "complete",
            "avoids your grasp", "complete",
            "fend off your grasp", "complete",
            "leaving you flailing", "complete",
            "Your concentration lapses", "complete",
            "don't seem to be able to move", "complete",
            "too injured", "complete",
            "already dead", "complete",
            "little bit late", "complete",
            "could not find", "complete",
            "completely miss", "complete",
            "is out of reach", "complete",
            "You cannot bearhug", "complete"
        )

        if result == "wait" then
            waitrt()
            if CMan and CMan.affordable and not CMan.affordable("Bearhug") then break end
        elseif result == "complete" or os.time() > break_out then
            break
        elseif not result then
            bigshot_should_rest = true
            bigshot_rest_reason = "Unknown result from bearhug"
            break
        end
        pause(0.25)
    end
    return true
end

-- ==========================================================================
-- cmd_force — Force command until result >= goal threshold
-- ==========================================================================

function M.cmd_force(command, goal, target, bstate)
    debug_msg(bstate, "cmd_force | " .. command .. " until " .. goal)

    local start = os.time()
    while true do
        -- Execute the sub-command
        waitrt()
        waitcastrt()
        if target and target.id then
            local cmd_str = command:gsub("target", "#" .. target.id)
            fput(cmd_str)
        else
            fput(command)
        end

        pause(0.1)

        -- Scan reget buffer for roll results
        local buffer = reget(35)
        if buffer then
            local found_result = false
            for _, line in ipairs(buffer) do
                -- Check for failure conditions
                if line:find("vision swims with a swirling haze")
                    or line:find("do not have enough stamina")
                    or line:find("lying down .* awkward proposition")
                    or line:find("magic fizzles ineffectually")
                    or line:find("You are .* stunned") then
                    return false, "force failed"
                end

                -- Check for roll results
                local roll = line:match("%[Roll result: (%d+)") or line:match("%[SMR result: (%d+)")
                    or line:match("%[SSR result: (%d+)") or line:match("== %+(%d+)")
                if roll then
                    local roll_num = tonumber(roll)
                    if roll_num and roll_num >= goal then
                        return true, "goal reached"
                    end
                    found_result = true
                end
            end
        end

        -- Affordability check for spell-based force
        local spell_num = command:match("^(%d+)")
        if spell_num and Spell[tonumber(spell_num)] and not Spell[tonumber(spell_num)].affordable then
            respond("[bigshot] Force ran out of mana. Giving up.")
            return false, "out of mana"
        end

        -- Terminal conditions
        if not target_alive(target) then return false, "target gone" end
        if npc_count(bstate) == 0 then return false, "no npcs" end
        if (os.time() - start) > 30 then return false, "timeout" end
    end
end

-- ==========================================================================
-- cmd_ranged — Archery with progressive aim locations
-- ==========================================================================

function M.cmd_ranged(target, bstate)
    debug_msg(bstate, "cmd_ranged")

    if not target_alive(target) then
        bigshot_archery_aim = 0
        bigshot_archery_stuck = {}
        return false, "target gone"
    end

    local aim_list = (bstate and bstate.archery_aim) or {}

    -- Advance aim if stuck in current location
    if #aim_list > 0 and bigshot_archery_aim < #aim_list then
        for _, stuck_loc in ipairs(bigshot_archery_stuck) do
            if bigshot_archery_location and stuck_loc:lower() == bigshot_archery_location:lower() then
                bigshot_archery_aim = bigshot_archery_aim + 1
                break
            end
        end

        -- Reset if we've gone past the end
        if bigshot_archery_aim >= #aim_list then
            bigshot_archery_aim = 0
            bigshot_archery_stuck = {}
        end

        -- Set aim location
        local aim_loc = aim_list[bigshot_archery_aim + 1]
        if aim_loc and (aim_loc ~= bigshot_archery_location or bigshot_archery_location == nil) then
            fput("aim " .. aim_loc)
            bigshot_archery_location = aim_loc
        end
    end

    waitrt()
    waitcastrt()

    local result = matchtimeout(2,
        "Roundtime", "ok",
        "roundtime", "ok",
        "You cannot", "cannot",
        "Could not find", "notfound",
        "seconds", "ok",
        "Get what", "noammo",
        "but it has no effect", "noeffect"
    )

    if result == "cannot" then
        -- Stow whatever is in right hand
        if GameObj.right_hand and GameObj.right_hand().id then
            fput("stow #" .. GameObj.right_hand().id)
        end
    elseif result == "noeffect" then
        bigshot_should_rest = true
        bigshot_rest_reason = "Ammo had no effect (need blessed or magical)"
    elseif not result then
        bigshot_should_rest = true
        bigshot_rest_reason = "Unknown result from fire routine"
    elseif result == "ok" then
        bigshot_archery_aim = 0
        bigshot_archery_stuck = {}
    end

    return true
end

-- ==========================================================================
-- cmd_fire — Fire/shoot command variant (alias for ranged)
-- ==========================================================================

function M.cmd_fire(target, bstate)
    return M.cmd_ranged(target, bstate)
end

-- ==========================================================================
-- cmd_ambush — Ambush from hiding with body part targeting
-- ==========================================================================

function M.cmd_ambush(args, target, bstate)
    debug_msg(bstate, "cmd_ambush | " .. tostring(args))

    if not target_alive(target) then
        bigshot_aim = 0
        return false, "target gone"
    end

    -- Parse aim locations
    local aim_locations = {}
    if args and args ~= "" then
        aim_locations = {args}
    elseif bstate and bstate.ambush_locations and #bstate.ambush_locations > 0 then
        aim_locations = bstate.ambush_locations
    else
        aim_locations = {"head", "right leg", "left leg", "chest"}
    end

    -- Reset aim if past list
    if bigshot_aim >= #aim_locations then
        bigshot_aim = 0
        aim_locations = {"chest"}
    end

    local aim_loc = aim_locations[bigshot_aim + 1] or "chest"

    waitrt()

    -- Use ambush if hidden, else attack
    local verb = (hidden and hidden()) and "ambush" or "attack"
    local result = matchtimeout(2,
        "Roundtime", "ok",
        "roundtime", "ok",
        "You cannot aim that high", "advance_aim",
        "does not have a head", "advance_aim",
        "is already missing that", "advance_aim",
        "does not have a .* leg", "advance_aim",
        "does not have a .* arm", "advance_aim"
    )

    fput(verb .. " #" .. target.id .. " " .. aim_loc)

    result = matchtimeout(2,
        "Roundtime", "ok",
        "roundtime", "ok",
        "You cannot aim that high", "advance_aim",
        "does not have a head", "advance_aim",
        "is already missing that", "advance_aim",
        "does not have a", "advance_aim"
    )

    if result == "advance_aim" then
        bigshot_aim = bigshot_aim + 1
        return M.cmd_ambush(nil, target, bstate)
    elseif result == "ok" then
        bigshot_aim = 0
    end

    return true
end

-- ==========================================================================
-- cmd_attack — Direct attack with aiming and stance dancing
-- ==========================================================================

function M.cmd_attack(command, target, bstate)
    debug_msg(bstate, "cmd_attack | " .. (command or "attack"))

    if not target_alive(target) then
        bigshot_aim = 0
        return false, "target gone"
    end

    local aim_list = (bstate and bstate.aim_locations) or {}

    waitrt()
    waitcastrt()

    local aim_str = ""
    if #aim_list > 0 and bigshot_aim < #aim_list then
        aim_str = " " .. aim_list[bigshot_aim + 1]
    end

    fput((command or "attack") .. " #" .. target.id .. aim_str)

    local result = matchtimeout(2,
        "Roundtime", "ok",
        "roundtime", "ok",
        "does not have", "advance_aim",
        "You cannot aim that high", "advance_aim",
        "is already missing that", "advance_aim",
        "%.%.%.wait", "wait"
    )

    if result == "advance_aim" then
        bigshot_aim = bigshot_aim + 1
    elseif result == "ok" then
        bigshot_aim = 0
    elseif result == "wait" then
        waitrt()
    end

    return true
end

-- ==========================================================================
-- cmd_hide — Hide with retry and stance management
-- ==========================================================================

function M.cmd_hide(attempts, bstate)
    debug_msg(bstate, "cmd_hide | attempts=" .. tostring(attempts))

    local max_attempts = tonumber(attempts) or 3
    if max_attempts == 0 then max_attempts = 3 end

    local wander_stance = (bstate and bstate.defensive_stance) or "defensive"

    local tries = 0
    while not (hidden and hidden()) do
        if tries >= max_attempts then break end

        M.change_stance(wander_stance, bstate)
        waitrt()
        fput("hide")
        tries = tries + 1
        pause(0.3)
    end

    return hidden and hidden() or false
end

-- ==========================================================================
-- cmd_throw — Thrown weapon with recovery
-- ==========================================================================

function M.cmd_throw(target, bstate)
    debug_msg(bstate, "cmd_throw")

    if target and target.status and target.status:find("lying down") then
        return false, "target prone"
    end

    -- Empty hands for throw
    fput("store both")

    fput("throw #" .. target.id)
    local result = matchtimeout(1,
        "You attempt to throw", "ok",
        "Roundtime", "ok"
    )

    waitrt()

    -- Fill hands after throw
    fput("gird")

    return true
end

-- ==========================================================================
-- cmd_dhurl — Dagger hurl with recovery mechanics
-- ==========================================================================

function M.cmd_dhurl(target, command, bstate)
    debug_msg(bstate, "cmd_dhurl")

    if not target_alive(target) then
        bigshot_aim = 0
        return false, "target gone"
    end

    -- Parse aim locations from command or config
    local aim_locations = {}
    if command and command ~= "" then
        aim_locations = {command}
    elseif bstate and bstate.ambush_locations and #bstate.ambush_locations > 0 then
        aim_locations = bstate.ambush_locations
    else
        aim_locations = {"chest"}
    end

    if type(aim_locations) == "string" then
        aim_locations = {aim_locations}
    end

    if bigshot_aim >= #aim_locations then
        bigshot_aim = 0
        aim_locations = {"chest"}
    end

    local aim_loc = aim_locations[bigshot_aim + 1] or "chest"

    waitrt()
    waitcastrt()

    bigshot_bond_return = false

    local result = matchtimeout(2,
        "With a quick flick of your wrist", "thrown",
        "not going to do much", "fail",
        "You find nothing recoverable", "fail",
        "You throw", "thrown",
        "You take aim and throw", "thrown"
    )

    fput("hurl #" .. target.id .. " " .. aim_loc)

    result = matchtimeout(2,
        "With a quick flick of your wrist", "thrown",
        "not going to do much", "fail",
        "You find nothing recoverable", "fail",
        "You throw", "thrown",
        "You take aim and throw", "thrown"
    )

    if result == "thrown" then
        bigshot_aim = 0
        local hurled_room = Map and Map.current_room and Map.current_room() or nil
        -- Wait for roundtime then recover
        local hold = 6 - (checkrt and checkrt() or 0)
        if hold <= 0 then hold = 0 end
        waitrt()
        if hold > 0 then pause(hold) end
        -- Return to hurl room if we moved
        if hurled_room and Map and Map.current_room and Map.current_room() ~= hurled_room then
            if Script and Script.run then Script.run("go2", tostring(hurled_room)) end
        end
        M.cmd_recover(bstate)
    elseif result == "fail" then
        M.cmd_recover(bstate)
    end

    return true
end

-- ==========================================================================
-- cmd_recover — Recover hurled weapon
-- ==========================================================================

function M.cmd_recover(bstate)
    debug_msg(bstate, "cmd_recover")

    local weapon_lost = true
    while weapon_lost do
        if bigshot_bond_return then break end
        waitrt()

        fput("recover hurl")
        local result = matchtimeout(5,
            "is around here somewhere, but you don't see it", "almost",
            "You spy a .+ and recover it", "recovered",
            "rises out of the shadows and flies back", "recovered",
            "need to have a free hand", "nofree",
            "You find nothing recoverable", "nothing"
        )

        if result == "almost" then
            pause(0.5)
        elseif result == "recovered" then
            weapon_lost = false
        elseif result == "nofree" or result == "nothing" then
            weapon_lost = false
        elseif not result then
            weapon_lost = false
        end
    end
end

-- ==========================================================================
-- cmd_wand — Wand usage from container
-- ==========================================================================

function M.cmd_wand(target, bstate)
    debug_msg(bstate, "cmd_wand")

    local fresh_container = bstate and bstate.fresh_wand_container
    local dead_container = bstate and bstate.dead_wand_container
    local wand_list = bstate and bstate.wand_list or {"wand"}

    if not fresh_container then
        respond("[bigshot] ERROR: Wand command called but fresh wand container not defined.")
        return false, "no wand container"
    end

    -- Get wand from container
    local current_wand = wand_list[bigshot_wand_index] or "wand"
    local got_wand = false
    local max_tries = 5

    for _ = 1, max_tries do
        -- Check if already holding the wand
        local rh = GameObj.right_hand and GameObj.right_hand() or nil
        local lh = GameObj.left_hand and GameObj.left_hand() or nil
        local holding = false
        if rh and rh.name and rh.name:lower():find(current_wand:lower()) then holding = true end
        if lh and lh.name and lh.name:lower():find(current_wand:lower()) then holding = true end
        if holding then got_wand = true; break end

        local result = matchtimeout(3,
            "You remove", "ok",
            "You slip", "ok",
            "Get what", "empty"
        )

        fput("get " .. current_wand .. " from my " .. fresh_container)

        result = matchtimeout(3,
            "You remove", "ok",
            "You slip", "ok",
            "Get what", "empty"
        )

        if result == "empty" then
            bigshot_wand_index = bigshot_wand_index + 1
            if bigshot_wand_index > #wand_list then
                respond("[bigshot] ERROR: Couldn't find fresh wand. Gonna rest.")
                bigshot_should_rest = true
                bigshot_rest_reason = "No fresh wands!"
                return false, "no wands"
            end
            current_wand = wand_list[bigshot_wand_index]
        elseif result == "ok" then
            got_wand = true
            break
        elseif not result then
            return false, "wand timeout"
        end
    end

    if not got_wand then return false, "failed to get wand" end

    local hunting_stance = (bstate and bstate.hunting_stance) or "offensive"
    M.change_stance("offensive", bstate)

    -- Wave wand at target
    fput("wave my " .. current_wand .. " at #" .. target.id)

    local result = matchtimeout(3,
        "d100", "ok",
        "You hurl", "ok",
        "is already dead", "dead",
        "You do not see that here", "gone",
        "You are in no condition", "wounded",
        "I could not find", "gone"
    )

    M.change_stance(hunting_stance, bstate)

    if result == "wounded" then
        bigshot_should_rest = true
        bigshot_rest_reason = "Too injured to wave wands!"
        return false, "wounded"
    elseif not result then
        -- Wand might be dead, store it
        if dead_container then
            M.bs_put("put my " .. current_wand .. " in my " .. dead_container, bstate)
        else
            M.bs_put("drop my " .. current_wand, bstate)
        end
    end

    return true
end

-- ==========================================================================
-- cmd_wandolier — Wand sequence with stance change
-- ==========================================================================

function M.cmd_wandolier(target, stance, bstate)
    debug_msg(bstate, "cmd_wandolier")

    if not stance or stance == "" then stance = "offensive" end

    local fresh_container = bstate and bstate.fresh_wand_container
    local wand_list = bstate and bstate.wand_list or {"wand"}

    if not fresh_container then
        respond("[bigshot] ERROR: Wandolier command called but fresh wand container not defined.")
        return false, "no wand container"
    end

    local current_wand = wand_list[bigshot_wand_index] or "wand"

    -- Get wand
    local rh = GameObj.right_hand and GameObj.right_hand() or nil
    local lh = GameObj.left_hand and GameObj.left_hand() or nil
    local holding = false
    if rh and rh.name and rh.name:lower():find(current_wand:lower()) then holding = true end
    if lh and lh.name and lh.name:lower():find(current_wand:lower()) then holding = true end

    if not holding then
        local result = matchtimeout(3,
            "You remove", "ok",
            "You slip", "ok",
            "You slide", "ok",
            "Get what", "empty"
        )

        fput("get " .. current_wand .. " from my " .. fresh_container)

        result = matchtimeout(3,
            "You remove", "ok",
            "You slip", "ok",
            "You slide", "ok",
            "Get what", "empty"
        )

        if result == "empty" then
            fput("rub my " .. fresh_container)
        elseif not result then
            return false, "wand timeout"
        end
    end

    local hunting_stance = (bstate and bstate.hunting_stance) or "offensive"
    M.change_stance(stance, bstate)

    fput("wave my " .. current_wand)

    local result = matchtimeout(3,
        "d100", "ok",
        "You hurl", "ok",
        "is already dead", "dead",
        "You do not see that here", "gone",
        "You are in no condition", "wounded",
        "I could not find", "gone"
    )

    M.change_stance(hunting_stance, bstate)

    if result == "wounded" then
        bigshot_should_rest = true
        bigshot_rest_reason = "Too injured to wave wands!"
    end

    return true
end

-- ==========================================================================
-- cmd_rapid — Rapid Fire (515) toggle
-- ==========================================================================

function M.cmd_rapid(ignore, bstate)
    debug_msg(bstate, "cmd_rapid")

    if not Spell or not Spell[515] or not Spell[515].known then
        return false, "spell not known"
    end
    if not Spell[515].affordable then
        return false, "not affordable"
    end
    if Effects and Effects.Buffs.active("Rapid Fire") and Effects.Buffs.time_left("Rapid Fire") > 0.05 then
        return false, "already active"
    end
    if Effects and Effects.Cooldowns.active("Rapid Fire Recovery") and (not ignore or ignore == "") then
        return false, "recovery cooldown"
    end

    waitrt()
    waitcastrt()

    if Spell[515].cast then
        Spell[515].cast()
    else
        fput("incant 515")
    end

    return true
end

-- ==========================================================================
-- cmd_efury — Elemental Fury (917) incant loop until target dead
-- ==========================================================================

function M.cmd_efury(target, extra, bstate)
    debug_msg(bstate, "cmd_efury | extra=" .. tostring(extra))

    if not target_alive(target) then return false, "target gone" end
    if not Spell or not Spell[917] or not Spell[917].known then return false, "spell not known" end
    if not Spell[917].affordable then return false, "not affordable" end

    waitrt()
    waitcastrt()

    local time_out = os.time() + 12

    -- Force incant
    if Spell[917].force_incant then
        Spell[917].force_incant(extra or "")
    else
        fput("incant 917 " .. (extra or ""))
    end

    -- Wait for completion
    while true do
        if os.time() > time_out then break end
        if not target_alive(target) then break end

        local line = get()
        if line then
            -- Completion patterns
            if line:find("suddenly calms") or line:find("causing a brief swelter")
                or line:find("icy mist rises") or line:find("flares to life and absorbs") then
                break
            end
        end

        -- Stand up if knocked down
        if standing and not standing() then
            fput("stand")
        end

        pause(0.5)
    end

    return true
end

-- ==========================================================================
-- cmd_tether — Dark Pact Tether (706) DoT with transfer on death
-- ==========================================================================

function M.cmd_tether(target, recast, bstate)
    debug_msg(bstate, "cmd_tether | recast=" .. tostring(recast))

    if not target_alive(target) then return false, "target gone" end
    if not Spell or not Spell[706] or not Spell[706].known then return false, "spell not known" end
    if not Spell[706].affordable then return false, "not affordable" end

    waitrt()
    waitcastrt()

    local time_out = os.time() + 12

    -- Cast tether
    if Spell[706].force_incant then
        Spell[706].force_incant()
    else
        fput("incant 706")
    end

    local spell_complete = false
    local tether_transferred = false

    -- Monitor for completion
    while true do
        if os.time() > time_out then break end
        if not target_alive(target) then
            -- Check if tether transferred
            local buf = reget(10)
            if buf then
                for _, line in ipairs(buf) do
                    if line:find("tenebrous chains binding") and line:find("begin to vibrate") then
                        tether_transferred = true
                        break
                    end
                end
            end
            break
        end

        local line = get()
        if line then
            if line:find("dissolve into black mist") then
                spell_complete = true
                break
            elseif line:find("struggle to maintain control") or line:find("feel your connection.*fade away") then
                spell_complete = true
                break
            elseif line:find("tenebrous chains binding") and line:find("begin to vibrate") then
                tether_transferred = true
                break
            end
        end

        -- Stay standing
        if standing and not standing() then fput("stand") end
        pause(0.5)
    end

    -- Handle recast on transfer
    if recast and tether_transferred and not spell_complete then
        pause(0.5)
        -- Find the new target (the one the tether transferred to)
        local npcs = GameObj.npcs()
        local new_target = nil
        for _, npc in ipairs(npcs or {}) do
            if npc.status and not npc.status:find("dead") and not npc.status:find("gone") then
                new_target = npc
                break
            end
        end
        if new_target then
            M.cmd_tether(new_target, recast, bstate)
        end
    end

    return true
end

-- ==========================================================================
-- cmd_curse — Curse spell (715) with custom prep/curse logic
-- ==========================================================================

function M.cmd_curse(target, bstate)
    debug_msg(bstate, "cmd_curse")

    if not target_alive(target) then return false, "target gone" end

    -- Parse curse type from bstate or default
    local curse_type = "hex"
    if bstate and bstate._curse_type then curse_type = bstate._curse_type end

    -- Check for Star curse already active
    if curse_type == "star" and Effects and Effects.Spells.time_left and Effects.Spells.time_left("Curse of the Star (bonus)") > 0.5 then
        return false, "star already active"
    end

    if not Spell or not Spell[715] then return false, "no spell 715" end
    if not Spell[715].known then return false, "spell not known" end
    if not Spell[715].affordable then return false, "not affordable" end

    local timeout = os.time() + 10

    -- Prep loop
    while true do
        if checkprep and checkprep() == "Curse" then break end
        if not Spell[715].affordable then return false, "not affordable" end

        waitrt()
        waitcastrt()

        -- Release other preps
        if checkprep and checkprep() ~= "None" then
            fput("release")
        end

        fput("prep 715")
        local result = matchtimeout(2,
            "Your spell is ready", "ready"
        )
        if result == "ready" then break end

        if not target_alive(target) then return false, "target gone" end
        if os.time() > timeout then return false, "timeout" end
    end

    waitrt()
    waitcastrt()

    if target_alive(target) then
        fput("curse #" .. target.id .. " " .. curse_type)
    end

    return true
end

-- ==========================================================================
-- cmd_phase — Phase spell (704) for corporeal conversion
-- ==========================================================================

function M.cmd_phase(target, bstate)
    debug_msg(bstate, "cmd_phase")

    if not target_alive(target) then return false, "target gone" end
    if not Spell or not Spell[704] or not Spell[704].known then return false, "not known" end
    if not Spell[704].affordable then return false, "not affordable" end

    if Spell[704].force_cast then
        Spell[704].force_cast("#" .. target.id)
    else
        fput("incant 704 at #" .. target.id)
    end

    waitrt()
    waitcastrt()
    return true
end

-- ==========================================================================
-- cmd_depress — Song of Depression (1015) with room registry
-- ==========================================================================

function M.cmd_depress(target, bstate)
    debug_msg(bstate, "cmd_depress")

    if not target_alive(target) then return false, "target gone" end
    if not Spell or not Spell[1015] or not Spell[1015].known then return false, "not known" end
    if not Spell[1015].affordable then return false, "not affordable" end

    -- Check room registry — only cast once per room
    local original_command = bstate and bstate._current_command or "depress"
    for _, cmds in pairs(COMMANDS_REGISTRY) do
        for _, c in ipairs(cmds) do
            if c == original_command then
                respond("[bigshot] Room already affected!")
                return false, "room already affected"
            end
        end
    end

    waitrt()
    waitcastrt()

    -- Try renew first
    fput("renew 1015")
    local result = matchtimeout(3,
        'Renewing "Song of Depression"', "renewed",
        "But you are not singing that spellsong", "not_singing"
    )

    if result == "not_singing" then
        if Spell[1015].force_incant and Spell[1015].affordable then
            Spell[1015].force_incant()
        else
            fput("incant 1015")
        end
    end

    waitrt()
    waitcastrt()
    return true
end

-- ==========================================================================
-- cmd_unravel — Unravel/bard dispel with loop
-- ==========================================================================

function M.cmd_unravel(target, bstate)
    debug_msg(bstate, "cmd_unravel")

    local extra = bstate and bstate._unravel_extra or ""

    if not target_alive(target) then return false, "target gone" end
    if not Spell or not Spell[1013] or not Spell[1013].known then return false, "not known" end
    if not Spell[1013].affordable then return false, "not affordable" end

    while true do
        waitrt()
        waitcastrt()

        if Spell[1013].force_cast then
            Spell[1013].force_cast("#" .. target.id, extra)
        else
            fput("incant 1013 at #" .. target.id)
        end

        local result = matchtimeout(3,
            "You are already singing that spellsong", "already",
            "pulling at the threads of mana", "success",
            "You gain %d+ mana", "success",
            "silvery tendril continues", "stop",
            "concentration on unravelling.* is broken", "broken",
            "as if it had entered a vast empty chamber", "empty",
            "A little bit late", "late",
            "What were you referring to", "gone"
        )

        if result == "already" then
            fput("stop 1013")
        elseif result == "success" then
            waitrt()
            waitcastrt()
            fput("stop 1013")
            break
        elseif result == "stop" then
            fput("stop 1013")
        elseif result == "broken" or result == "empty" then
            break
        elseif result == "late" or result == "gone" then
            fput("release")
            break
        elseif not result then
            break
        end
    end

    return true
end

-- ==========================================================================
-- cmd_caststop — Stop casting on target
-- ==========================================================================

function M.cmd_caststop(target, bstate)
    debug_msg(bstate, "cmd_caststop")

    local spell_id = bstate and bstate._caststop_spell or nil
    local extra = bstate and bstate._caststop_extra or ""

    if not spell_id then return false, "no spell specified" end
    if not target_alive(target) then return false, "target gone" end
    if not Spell or not Spell[spell_id] then return false, "spell not found" end
    if not Spell[spell_id].known then return false, "not known" end
    if not Spell[spell_id].affordable then return false, "not affordable" end

    waitrt()
    waitcastrt()

    if Spell[spell_id].force_cast then
        Spell[spell_id].force_cast("#" .. target.id, extra)
    else
        fput("incant " .. spell_id .. " at #" .. target.id)
    end

    fput("stop " .. spell_id)
    return true
end

-- ==========================================================================
-- cmd_censer — Ethereal Censer (320) handling
-- ==========================================================================

function M.cmd_censer(target, bstate)
    debug_msg(bstate, "cmd_censer")

    if not Spell or not Spell[320] or not Spell[320].known then return false, "not known" end
    if Effects and Effects.Cooldowns.active("Ethereal Censer") then return false, "cooldown" end

    -- Calculate total cost (spell + censer)
    local base_cost = (Spell[320].cost and Spell[320].cost()) or 0
    local cmd = bstate and bstate._current_command or ""
    local spell_num = cmd:match("(%d+)")
    if spell_num and Spell[tonumber(spell_num)] then
        base_cost = base_cost + ((Spell[tonumber(spell_num)].cost and Spell[tonumber(spell_num)].cost()) or 0)
    end

    if (Char.mana or 0) >= base_cost then
        if Spell[320].cast then
            Spell[320].cast()
        else
            fput("incant 320")
        end
    end

    return false -- censer is a pre-cast modifier, not the main action
end

-- ==========================================================================
-- cmd_bless — Bless weapons (1604, 304, or voln symbol)
-- ==========================================================================

function M.cmd_bless(bstate)
    debug_msg(bstate, "cmd_bless")

    while #bigshot_bless > 0 do
        local weapon_id = bigshot_bless[#bigshot_bless]

        -- Try Holy Fire (1604) first
        if Spell and Spell[1604] and Spell[1604].known and Spell[1604].affordable then
            waitrt()
            waitcastrt()
            if Spell[1604].cast then
                local result = Spell[1604].cast("#" .. weapon_id)
                if result and tostring(result):find("violet tongue of flame") then
                    -- Still needs normal blessing
                else
                    table.remove(bigshot_bless)
                    goto continue
                end
            end
        end

        -- Try Bless (304)
        if Spell and Spell[304] and Spell[304].known and Spell[304].affordable then
            waitrt()
            waitcastrt()
            if Spell[304].cast then
                Spell[304].cast("#" .. weapon_id)
            else
                fput("incant 304 at #" .. weapon_id)
            end
            table.remove(bigshot_bless)
        -- Try Voln Symbol of Blessing (9802)
        elseif Spell and Spell[9802] and Spell[9802].known then
            waitrt()
            waitcastrt()
            fput("symbol bless #" .. weapon_id)
            table.remove(bigshot_bless)
        else
            bigshot_should_rest = true
            bigshot_rest_reason = "No blessing on weapon"
            bigshot_bless = {}
            return false, "no blessing available"
        end

        ::continue::
    end

    return true
end

-- ==========================================================================
-- cmd_assume — Druid aspect assumption (650)
-- ==========================================================================

function M.cmd_assume(aspect, extra, bstate)
    debug_msg(bstate, "cmd_assume | aspect=" .. tostring(aspect) .. " extra=" .. tostring(extra))

    if not Spell or not Spell[650] or not Spell[650].known then return false, "not known" end

    local valid_aspects = {
        jackal=true, wolf=true, lion=true, panther=true, hawk=true, owl=true,
        porcupine=true, rat=true, bear=true, burgee=true, mantis=true,
        serpent=true, spider=true, yierka=true
    }

    if not aspect or not valid_aspects[aspect:lower()] then
        respond("[bigshot] cmd_assume requires a valid aspect: jackal, wolf, lion, panther, hawk, owl, porcupine, rat, bear, burgee, mantis, serpent, spider, yierka")
        return false, "invalid aspect"
    end

    local aspect_cap = aspect:sub(1,1):upper() .. aspect:sub(2):lower()
    local extra_cap = extra and (extra:sub(1,1):upper() .. extra:sub(2):lower()) or ""

    -- Check cooldowns for both aspects
    if Effects and Effects.Cooldowns then
        local cd1 = Effects.Cooldowns.active("Aspect of the " .. aspect_cap .. " Cooldown")
        local cd2 = extra_cap ~= "" and extra_cap ~= "Evoke" and Effects.Cooldowns.active("Aspect of the " .. extra_cap .. " Cooldown")
        if cd1 and cd2 then return false, "both cooldowns active" end
    end

    -- Check if already buffed
    if Effects and Effects.Buffs then
        if Effects.Buffs.active("Aspect of the " .. aspect_cap) or
           (extra_cap ~= "" and extra_cap ~= "Evoke" and Effects.Buffs.active("Aspect of the " .. extra_cap)) then
            return true, "already buffed"
        end
    end

    -- Release current prep if needed
    if checkprep and checkprep() ~= "None" and checkprep() ~= "Assume Aspect" then
        fput("release")
    end

    waitrt()
    waitcastrt()

    -- Prep 650 if not already active
    local aspect_active = Effects and Effects.Buffs and (Effects.Buffs.active("Assume Aspect") or Effects.Buffs.active("650"))
    local already_prepped = checkprep and checkprep() == "Assume Aspect"

    if not aspect_active and not already_prepped then
        if extra and extra:lower() == "evoke" and Spell[650].affordable then
            if Spell[650].force_evoke then
                Spell[650].force_evoke()
            else
                fput("incant 650 evoke")
            end
            waitcastrt()
        elseif Spell[650].affordable then
            fput("prep 650")
        end
    end

    -- Check we have the prep
    local have_prep = (checkprep and checkprep() == "Assume Aspect")
        or (Effects and Effects.Buffs and (Effects.Buffs.active("Assume Aspect") or Effects.Buffs.active("650")))
    if not have_prep then return false, "prep failed" end

    -- Assume first aspect
    if not (Effects and Effects.Cooldowns and Effects.Cooldowns.active("Aspect of the " .. aspect_cap .. " Cooldown")) then
        if (Char.mana or 0) >= 25 then
            fput("assume " .. aspect)
            pause(1)
        end
    elseif extra and extra:lower() ~= "evoke" and extra_cap ~= "" then
        if not (Effects and Effects.Cooldowns and Effects.Cooldowns.active("Aspect of the " .. extra_cap .. " Cooldown")) then
            if (Char.mana or 0) >= 25 then
                fput("assume " .. extra)
                pause(1)
            end
        end
    elseif checkprep and checkprep() == "Assume Aspect" and Spell[650].affordable then
        fput("cast")
    end

    return true
end

-- ==========================================================================
-- cmd_briar — Briar/weapon readiness via MEASURE
-- ==========================================================================

function M.cmd_briar(weapon, bstate)
    debug_msg(bstate, "cmd_briar | weapon=" .. tostring(weapon))

    if not weapon then return false, "no weapon" end
    if Spell and Spell[9105] and Spell[9105].active then return false, "already active" end

    -- Find briar weapons in hands and inventory
    local briar_ids = {}
    local rh = GameObj.right_hand and GameObj.right_hand() or nil
    local lh = GameObj.left_hand and GameObj.left_hand() or nil
    if rh and rh.name and rh.name:find(weapon) then briar_ids[#briar_ids + 1] = rh.id end
    if lh and lh.name and lh.name:find(weapon) then briar_ids[#briar_ids + 1] = lh.id end

    if GameObj.inv then
        local inv = GameObj.inv()
        for _, item in ipairs(inv or {}) do
            if item.noun == weapon then
                briar_ids[#briar_ids + 1] = item.id
            end
        end
    end

    if #briar_ids == 0 then return false, "no briar weapons found" end

    for _, wid in ipairs(briar_ids) do
        fput("measure #" .. wid)
        local result = matchtimeout(2,
            "to be about (%d+) percent", "measured",
            "why are you trying to measure", "invalid"
        )

        if result == "measured" then
            -- Check reget for the percentage
            local buf = reget(5)
            if buf then
                for _, line in ipairs(buf) do
                    local pct = line:match("to be about (%d+) percent")
                    if pct and tonumber(pct) == 100 then
                        fput("raise #" .. wid)
                        break
                    end
                end
            end
        end
        pause(0.2)
    end

    return true
end

-- ==========================================================================
-- cmd_wield — Wield/unwield weapon
-- ==========================================================================

function M.cmd_wield(weapon, bstate)
    local hand = ""
    -- Parse "weapon hand" from args
    if weapon then
        local w, h = weapon:match("^(%S+)%s*(%S*)$")
        weapon = w or weapon
        hand = h or ""
    end

    debug_msg(bstate, "cmd_wield | weapon=" .. tostring(weapon) .. " hand=" .. hand)

    if not weapon then return false, "no weapon" end

    -- Already wielding?
    local rh = GameObj.right_hand and GameObj.right_hand() or nil
    local lh = GameObj.left_hand and GameObj.left_hand() or nil

    if (hand == "" or hand == "right") and rh and rh.noun == weapon then return true end
    if hand == "left" and lh and lh.noun == weapon then return true end

    -- Store current item in the target hand
    if hand == "" or hand == "right" then
        fput("store right")
    else
        fput("store left")
    end

    -- Check if weapon is worn (inventory) or loose
    -- Try remove first (worn item), fall back to get
    fput("remove my " .. weapon)
    pause(0.3)

    -- Verify we got it
    rh = GameObj.right_hand and GameObj.right_hand() or nil
    lh = GameObj.left_hand and GameObj.left_hand() or nil
    if not ((rh and rh.noun == weapon) or (lh and lh.noun == weapon)) then
        fput("get my " .. weapon)
    end

    return true
end

-- ==========================================================================
-- cmd_store — Store items from hand(s)
-- ==========================================================================

function M.cmd_store(hand, bstate)
    debug_msg(bstate, "cmd_store | hand=" .. tostring(hand))

    hand = hand or "both"

    local rh = GameObj.right_hand and GameObj.right_hand() or nil
    local lh = GameObj.left_hand and GameObj.left_hand() or nil

    if hand == "right" and (not rh or not rh.id) then return true end
    if hand == "left" and (not lh or not lh.id) then return true end
    if (hand == "both" or hand == "") and (not rh or not rh.id) and (not lh or not lh.id) then return true end

    if hand == "right" then
        fput("store right")
    elseif hand == "left" then
        fput("store left")
    else
        fput("store both")
    end

    return true
end

-- ==========================================================================
-- cmd_burst — Burst of Swiftness (stamina maneuver)
-- ==========================================================================

function M.cmd_burst(bstate)
    debug_msg(bstate, "cmd_burst")

    if CMan and CMan.known and not CMan.known("Burst of Swiftness") then
        return false, "not known"
    end

    -- Check if already have dexterity buff
    if Effects and Effects.Buffs then
        local buffs = Effects.Buffs.to_h and Effects.Buffs.to_h() or {}
        for name, _ in pairs(buffs) do
            if name:find("Enh%. Dexterity") then return false, "already buffed" end
        end
    end

    -- Stamina check: 30 if off cooldown, 60 if on cooldown
    local stam = Char.stamina or 0
    local on_cd = Effects and Effects.Cooldowns.active("Burst of Swiftness")
    if stam < 30 and not on_cd then return false, "not enough stamina" end
    if stam < 60 and on_cd then return false, "not enough stamina (cooldown)" end

    while true do
        waitrt()
        waitcastrt()

        fput("cman burst")

        local result = matchtimeout(1,
            "You feel .* more .* dextrous", "ok",
            "You feel .* more .* agile", "ok",
            "muscles ache much too badly", "fail",
            "Roundtime", "rt",
            "%.%.%.wait", "rt"
        )

        if result == "ok" or result == "fail" then break end
        if result ~= "rt" then break end
    end

    return true
end

-- ==========================================================================
-- cmd_surge — Surge of Strength (stamina maneuver)
-- ==========================================================================

function M.cmd_surge(bstate)
    debug_msg(bstate, "cmd_surge")

    if CMan and CMan.known and not CMan.known("Surge of Strength") then
        return false, "not known"
    end

    -- Check if already have strength buff
    if Effects and Effects.Buffs then
        local buffs = Effects.Buffs.to_h and Effects.Buffs.to_h() or {}
        for name, _ in pairs(buffs) do
            if name:find("Enh%. Strength") then return false, "already buffed" end
        end
    end

    local stam = Char.stamina or 0
    local on_cd = Effects and Effects.Cooldowns.active("Surge of Strength")
    if stam < 30 and not on_cd then return false, "not enough stamina" end
    if stam < 60 and on_cd then return false, "not enough stamina (cooldown)" end

    while true do
        waitrt()
        waitcastrt()

        fput("cman surge")

        local result = matchtimeout(1,
            "You feel a great deal stronger", "ok",
            "untapped sources of strength", "ok",
            "still recent prior attempt", "ok",
            "come from your muscles", "ok",
            "ache much too badly", "fail",
            "Roundtime", "rt",
            "%.%.%.wait", "rt"
        )

        if result == "ok" or result == "fail" then break end
        if result ~= "rt" then break end
    end

    return true
end

-- ==========================================================================
-- cmd_berserk — Berserking toggle
-- ==========================================================================

function M.cmd_berserk(bstate)
    debug_msg(bstate, "cmd_berserk")

    if (Char.stamina or 0) >= 20 then
        local wander_stance = (bstate and bstate.defensive_stance) or "defensive"
        M.change_stance(wander_stance, bstate)
        if Spell and Spell[9607] and Spell[9607].cast then
            Spell[9607].cast()
        else
            fput("berserk")
        end
        pause(5)
        -- Wait until berserk ends
        if Spell and Spell[9607] then
            while Spell[9607].active do pause(1) end
        end
    else
        M.bs_put("target random", bstate)
        M.bs_put("kill", bstate)
    end

    return true
end

-- ==========================================================================
-- cmd_leech — Mana leech (516) timing
-- ==========================================================================

function M.cmd_leech(bstate)
    debug_msg(bstate, "cmd_leech")

    if not Spell or not Spell[516] or not Spell[516].known then
        return false, "not known"
    end

    if Effects and Effects.Cooldowns.time_left and Effects.Cooldowns.time_left("Mana Leech") < 15 then
        if Spell[516].affordable then
            waitrt()
            waitcastrt()
            if Spell[516].cast then
                Spell[516].cast()
            else
                fput("incant 516")
            end
        end
    end

    return true
end

-- ==========================================================================
-- cmd_stomp — Stomp channeled ability (909)
-- ==========================================================================

function M.cmd_stomp(bstate)
    debug_msg(bstate, "cmd_stomp")

    if not Spell or not Spell[909] or not Spell[909].known then
        return false, "not known"
    end

    waitrt()
    waitcastrt()

    if Spell[909].active then
        if (Char.mana or 0) >= 5 then
            fput("stomp")
        end
    elseif Spell[909].affordable then
        if Spell[909].force_channel then
            Spell[909].force_channel()
        else
            fput("incant 909 channel")
        end
        waitcastrt()
        if (Char.mana or 0) >= 5 then
            fput("stomp")
        end
    end

    return true
end

-- ==========================================================================
-- cmd_sleep — Pause with break conditions
-- ==========================================================================

function M.cmd_sleep(time, nostance, target, bstate)
    debug_msg(bstate, "cmd_sleep | time=" .. tostring(time))

    local secs = tonumber(time) or 1
    local wander_stance = (bstate and bstate.defensive_stance) or "defensive"

    if not nostance then
        M.change_stance(wander_stance, bstate)
    end

    for _ = 1, secs do
        pause(1)
        -- Break if target dead
        if target and target.status and (target.status:find("dead") or target.status:find("gone")) then
            break
        end
        -- Break if should rest
        if bigshot_should_rest then break end
    end

    return true
end

-- ==========================================================================
-- cmd_run_script — Launch external script
-- ==========================================================================

function M.cmd_run_script(name, args, bstate)
    debug_msg(bstate, "cmd_run_script | " .. tostring(name) .. " " .. tostring(args))

    if not name or name == "" then return false, "no script name" end

    if Script and Script.run then
        if args and args ~= "" then
            Script.run(name, args)
        else
            Script.run(name)
        end
        pause(1)
    end

    return true
end

-- ==========================================================================
-- cmd_dislodge — Dislodge stuck weapons
-- ==========================================================================

function M.cmd_dislodge(target, location, bstate)
    debug_msg(bstate, "cmd_dislodge | loc=" .. tostring(location))

    if CMan and CMan.available and not CMan.available("Dislodge") then
        return false, "not available"
    end

    if not target or target.id ~= bigshot_dislodge_target then
        return false, "wrong target"
    end

    -- Parse priority location list
    local locations = {}
    if location then
        for loc in location:gmatch("%S+") do
            locations[#locations + 1] = loc
        end
    end

    -- Find first matching dislodge location
    local dislodge_loc = nil
    for _, loc in ipairs(locations) do
        for _, stuck_loc in ipairs(bigshot_dislodge_location) do
            if stuck_loc == loc then
                dislodge_loc = loc
                break
            end
        end
        if dislodge_loc then break end
    end

    if not dislodge_loc then return false, "no matching location" end

    waitrt()
    waitcastrt()

    fput("cman dislodge #" .. target.id .. " " .. dislodge_loc)

    local result = matchtimeout(2,
        "attempting to dislodge", "ok",
        "suitable weapons lodged", "none",
        "You can't reach", "fail",
        "awkward proposition", "fail",
        "little bit late", "fail",
        "still stunned", "fail",
        "too injured", "fail",
        "You cannot", "fail",
        "Could not find", "fail",
        "Roundtime", "ok",
        "seconds", "ok"
    )

    -- Check reget for success
    local buf = reget(5)
    if buf then
        for _, line in ipairs(buf) do
            if line:find("manage to dislodge") or line:find("skillfully wrench") then
                if not target_alive(target) then
                    bigshot_dislodge_location = {}
                    bigshot_dislodge_target = nil
                else
                    -- Remove this location from the list
                    for i, loc in ipairs(bigshot_dislodge_location) do
                        if loc == dislodge_loc then
                            table.remove(bigshot_dislodge_location, i)
                            break
                        end
                    end
                end
                break
            end
        end
    end

    return true
end

-- ==========================================================================
-- cmd_nudge_weapons — Reposition dropped weapons out of room
-- ==========================================================================

function M.cmd_nudge_weapons(bstate)
    debug_msg(bstate, "cmd_nudge_weapons")

    local weapon_nouns = {
        "axe", "scythe", "pitchfork", "falchion", "sword", "lance", "dagger",
        "estoc", "handaxe", "katana", "katar", "gauche", "rapier", "scimitar",
        "whip%-blade", "cudgel", "crowbill", "whip", "mace", "star", "hammer",
        "claidhmore", "flail", "flamberge", "maul", "pick", "staff", "mattock"
    }

    local wander_stance = (bstate and bstate.defensive_stance) or "defensive"

    -- Check for weapon-like loot in room
    local loot = GameObj.loot and GameObj.loot() or {}
    for _, item in ipairs(loot) do
        local noun = item.noun or ""
        local is_weapon = false
        for _, wn in ipairs(weapon_nouns) do
            if noun:find(wn) then is_weapon = true; break end
        end

        if is_weapon then
            M.change_stance(wander_stance, bstate)

            -- Need a free hand
            local rh = GameObj.right_hand and GameObj.right_hand() or nil
            local lh = GameObj.left_hand and GameObj.left_hand() or nil
            local sheathed = false

            if rh and rh.id and lh and lh.id then
                sheathed = true
                fput("sheath")
                -- Verify
                rh = GameObj.right_hand and GameObj.right_hand() or nil
                lh = GameObj.left_hand and GameObj.left_hand() or nil
                if rh and rh.id and lh and lh.id then
                    respond("[bigshot] Unable to empty hands via sheath.")
                    break
                end
            end

            -- Get weapon, move it to adjacent room, drop it
            -- This uses checkpaths which should be available in the API
            if checkpaths then
                local paths = checkpaths()
                if paths and #paths > 0 then
                    local dir = paths[1]
                    fput("get #" .. item.id)
                    put(dir)
                    put("drop #" .. item.id)

                    -- Reverse direction
                    local reverse = {
                        north="south", south="north", east="west", west="east",
                        northeast="southwest", southwest="northeast",
                        northwest="southeast", southeast="northwest",
                        up="down", down="up", out="in", ["in"]="out"
                    }
                    local rev = reverse[dir] or "out"
                    fput(rev)

                    if sheathed then fput("gird") end
                end
            end
        end
    end

    return true
end

-- ==========================================================================
-- cmd_jewel — Gemstone jewel activation (23 types)
-- ==========================================================================

function M.cmd_jewel(jewel_name, bstate)
    debug_msg(bstate, "cmd_jewel | " .. tostring(jewel_name))

    local activated_jewels = {
        bloodboil       = "Blood Boil",
        spellblade      = "Spellblade's Fury",
        arcascend       = "Arcanist's Ascendancy",
        geospite        = "Geomancer's Spite",
        forceofwill     = "Force of Will",
        arcaneintensity = "Arcane Intensity",
        arcaneopus      = "Arcane Opus",
        bloodsiphon     = "Blood Siphon",
        bloodwell       = "Blood Wellspring",
        epossess        = "Evanescent Possession",
        manawellspring  = "Mana Wellspring",
        spiritwell      = "Spirit Wellspring",
        stamwell        = "Stamina Wellspring",
        terrortribute   = "Terror's Tribute",
        arcblade        = "Arcanist's Blade",
        arcwill         = "Arcanist's Will",
        imaerabalm      = "Imaera's Balm",
        reckless        = "Reckless Precision",
        unearthchains   = "Unearthly Chains",
        witchhunt       = "Witchhunter's Ascendancy",
        manashield      = "Mana Shield",
        arcaneaegis     = "Arcane Aegis",
    }

    if not jewel_name or not activated_jewels[jewel_name] then
        respond("[bigshot] Unknown gemstone jewel mnemonic: " .. tostring(jewel_name))
        respond("[bigshot] Please submit gemstone information to EO for addition.")
        return false, "unknown jewel"
    end

    -- Cooldown check
    if Effects and Effects.Cooldowns.active(activated_jewels[jewel_name]) then
        return false, "cooldown"
    end

    waitrt()
    waitcastrt()

    local break_out = os.time() + 2
    while true do
        fput("gemstone activate " .. jewel_name)

        local result = matchtimeout(2,
            "%.%.%.wait", "wait",
            "That property isn't ready yet", "cooldown",
            "don't have that property equipped", "fail",
            "fail to find a target", "fail",
            "have not yet unlocked Gemstones", "fail",
            "Cast Roundtime", "ok",
            "keeps? the spell from working", "ok",
            "Be at peace my child", "ok",
            "Spells of War cannot be cast", "ok",
            "vision swims with a swirling haze", "ok",
            "magic fizzles ineffectually", "ok",
            "cough up some blood", "ok",
            "give yourself away", "ok",
            "unable to do that right now", "ok",
            "casting at nothing but thin air", "ok",
            "don't seem to be able to move", "ok",
            "Provoking a GameMaster", "ok",
            "can't think clearly enough", "ok",
            "too injured to make that dextrous", "ok",
            "can't make that dextrous", "ok"
        )

        if result == "wait" then
            waitrt()
        elseif result or os.time() > break_out then
            break
        else
            break
        end
        pause(0.25)
    end

    return true
end

-- ==========================================================================
-- cmd_1040 — Troubadour's Rally cure for incapacitated group
-- ==========================================================================

function M.cmd_1040(target, bstate)
    debug_msg(bstate, "cmd_1040 | target=" .. tostring(target))

    if not Spell or not Spell[1040] or not Spell[1040].known then
        return false, "not known"
    end

    waitrt()
    waitcastrt()

    -- Mana pulse if can't afford
    if not Spell[1040].affordable then
        fput("mana pulse")
    end

    -- If target is self, loop until cured
    local self_name = Char and Char.name or ""
    if target == self_name or target == nil then
        local max_tries = 10
        local tries = 0
        while tries < max_tries do
            -- Check if still incapacitated
            local still_affected = false
            if (stunned and stunned()) or (Effects and Effects.Debuffs and
                (Effects.Debuffs.active("Webbed") or Effects.Debuffs.active("Sleeping")
                 or Effects.Debuffs.active("Frozen"))) then
                still_affected = true
            end
            if not still_affected then break end

            if Spell[1040].affordable then
                if Spell[1040].cast then
                    Spell[1040].cast()
                else
                    fput("incant 1040")
                end
            else
                fput("mana pulse")
            end
            waitcastrt()
            tries = tries + 1
        end
    else
        -- Cast on group member
        if Spell[1040].affordable then
            if Spell[1040].cast then
                Spell[1040].cast()
            else
                fput("incant 1040")
            end
        end
    end

    return true
end

-- ==========================================================================
-- cmd_weed — Tangle Weed (610) for entangling
-- ==========================================================================

function M.cmd_weed(command, target, bstate)
    debug_msg(bstate, "cmd_weed | " .. tostring(command))

    if not target_alive(target) then return false, "target gone" end

    -- Check if room already has vines
    local loot = GameObj.loot and GameObj.loot() or {}
    for _, item in ipairs(loot) do
        local name = (item.name or ""):lower()
        if name:find("vine") or name:find("bramble") or name:find("widgeonweed")
            or name:find("vathor club") or name:find("swallowwort") or name:find("smilax")
            or name:find("creeper") or name:find("briar") or name:find("ivy")
            or name:find("tumbleweed") then
            return false, "already entangled"
        end
    end

    if not Spell or not Spell[610] or not Spell[610].known then return false, "not known" end
    if not Spell[610].affordable then return false, "not affordable" end

    waitcastrt()

    if command and command:lower():find("kweed") then
        -- Use evoke for kweed
        if Spell[610].force_evoke then
            Spell[610].force_evoke("#" .. target.id)
        else
            fput("incant 610 evoke at #" .. target.id)
        end
    else
        if Spell[610].cast then
            Spell[610].cast("#" .. target.id)
        else
            fput("incant 610 at #" .. target.id)
        end
    end

    waitcastrt()
    return true
end

-- ==========================================================================
-- wrack — Mana recovery via wracking/symbols
-- ==========================================================================

function M.wrack(bstate)
    debug_msg(bstate, "wrack")

    -- Arcane Wrack (9918)
    if Spell and Spell[9918] and Spell[9918].known then
        if not (Spell[9012] and Spell[9012].active) then
            local wrack_spirit = (bstate and bstate.wracking_spirit) or 6
            if (Char.spirit or 0) >= wrack_spirit then
                if Spell[9918].cast then Spell[9918].cast() end
                return
            end
        end
    end

    -- Warrior Wrack (9718)
    if Spell and Spell[9718] and Spell[9718].known then
        local casts = math.floor((Char.stamina or 0) / 50)
        for _ = 1, casts do
            if Spell[9718].cast then Spell[9718].cast() end
        end
        return
    end

    -- Symbol of Mana (9813)
    if Spell and Spell[9813] and Spell[9813].known then
        if not (Effects and Effects.Cooldowns.active("Symbol of Mana")) then
            if Spell[9813].cast then Spell[9813].cast() end
        end
    end
end

-- ==========================================================================
-- cmd_eachtarget — Execute command against each NPC
-- ==========================================================================

function M.cmd_eachtarget(command, target, bstate)
    debug_msg(bstate, "cmd_eachtarget | " .. command)

    local current_target = target
    local targets = GameObj.npcs()
    for _, npc in ipairs(targets or {}) do
        if npc.status and not npc.status:find("dead") and not npc.status:find("gone") then
            if npc.id ~= current_target.id then
                fput("target #" .. npc.id)
            end
            M.execute(command, npc, bstate)
        end
    end
    -- Re-target original
    if current_target and current_target.id then
        fput("target #" .. current_target.id)
    end
    return true
end

-- ==========================================================================
-- Main command dispatcher
-- ==========================================================================

function M.execute(command, target, bstate)
    if not command or command == "" then return false, "empty command" end

    -- Check modifiers
    if not command_check.should_execute(command, target, bstate) then
        return false, "conditions not met"
    end

    local original_command = command

    -- Store current command for registry
    if bstate then bstate._current_command = original_command end

    -- Strip modifiers from command
    local clean = command_check.strip_modifiers(command)
    if clean == "" then return false, "empty command after strip" end

    -- Handle rooted kick -> punch substitution
    if bigshot_rooted and clean:lower():find("%bkick%b") then
        clean = clean:gsub("[kK]ick", "punch")
    end

    -- Reset dislodge if target is dead
    if target and target.status and (target.status:find("dead") or target.status:find("gone")) then
        bigshot_dislodge_location = {}
    end

    -- Pre-command waits (skip for nudgeweapons and slipperymind)
    if not clean:lower():find("^nudgeweapon") and not clean:lower():find("slipperymind") then
        waitrt()
        if not clean:lower():find("^hide") and not clean:lower():find("^cock") then
            waitcastrt()
        end
    end

    -- Handle FORCE command: "force <cmd> until <goal>"
    local force_cmd, force_goal = clean:match("^force%s+(.+)%s+(?:till|until)%s+(%d+)")
    if not force_cmd then
        force_cmd, force_goal = clean:match("^force%s+(.+)%s+till%s+(%d+)")
    end
    if not force_cmd then
        force_cmd, force_goal = clean:match("^force%s+(.+)%s+until%s+(%d+)")
    end
    if force_cmd and force_goal then
        local result = M.cmd_force(force_cmd, tonumber(force_goal), target, bstate)
        once_commands_register(target, original_command)
        return result
    end

    -- Handle EACHTARGET command
    local each_cmd = clean:match("^eachtarget%s+(.+)")
    if each_cmd then
        return M.cmd_eachtarget(each_cmd, target, bstate)
    end

    -- Substitute #target with target ID
    if target and target.id then
        clean = clean:gsub("target", "#" .. target.id)
    end

    -- Soothe routine (1201) for various disabling effects
    if Spell and Spell[1201] and Spell[1201].known and Spell[1201].affordable then
        if (Spell[201] and Spell[201].active) or (Spell[216] and Spell[216].active)
            or (Spell[1015] and Spell[1015].active) or (Spell[1016] and Spell[1016].active)
            or (Spell[1108] and Spell[1108].active) or (Spell[1120] and Spell[1120].active) then
            waitrt()
            waitcastrt()
            if Spell[1201].cast then Spell[1201].cast() end
        end
    end

    -- Auto-bless if configured
    if bstate and bstate.bless and #bigshot_bless > 0 then
        M.cmd_bless(bstate)
    end

    -- Celerity (506) prefix: "celerity <cmd>" or "haste <cmd>" or "506 <cmd>"
    local celerity_cmd = clean:match("^(?:celerity|haste|506)%s+(.+)$")
    if not celerity_cmd then
        celerity_cmd = clean:match("^celerity%s+(.+)$") or clean:match("^haste%s+(.+)$") or clean:match("^506%s+(.+)$")
    end
    if celerity_cmd then
        clean = celerity_cmd
        if Spell and Spell[506] and (not Spell[506].active or (Spell[506].timeleft and Spell[506].timeleft <= 0.05)) then
            waitrt()
            M.cmd_spell("506", target, bstate)
            waitcastrt()
        end
    end

    -- Spirit Slayer (240) prefix
    local slayer_cmd = clean:match("^slayer%s+(.+)$") or clean:match("^240%s+(.+)$")
    if slayer_cmd then
        clean = slayer_cmd
        if Spell and Spell[240] and Spell[240].known and Spell[240].affordable then
            if not Effects or not Effects.Cooldowns.active(Spell[240].name) then
                if (not Spell[240].active) or (Spell[240].timeleft and Spell[240].timeleft <= 0.05) then
                    if Spell[240].cast then Spell[240].cast() end
                end
            end
        end
    end

    -- Tonis (1035) prefix
    local tonis_cmd = clean:match("^tonis%s+(.+)$") or clean:match("^1035%s+(.+)$")
    if tonis_cmd then
        clean = tonis_cmd
        if Spell and Spell[1035] and Spell[1035].known and Spell[1035].affordable then
            if (not Spell[1035].active) or (Spell[1035].timeleft and Spell[1035].timeleft <= 0.05) then
                if Spell[1035].cast then Spell[1035].cast() end
            end
        end
    end

    -- Final strip of remaining modifiers
    clean = clean:gsub("%b()", ""):match("^%s*(.-)%s*$")
    local cmd_lower = clean:lower()

    -- Stand up if needed (skip for certain commands)
    if standing and not standing() then
        if not cmd_lower:find("^fire") and not cmd_lower:find("^kneel") and not cmd_lower:find("^hide")
            and not cmd_lower:find("^608") and not cmd_lower:find("^incant 608") then
            fput("stand")
        end
    end

    -- Stance dance (skip for wait/sleep/wand/berserk/script/hide/nudgeweapon)
    if not cmd_lower:find("^%d+") and not cmd_lower:find("^wait") and not cmd_lower:find("^sleep")
        and not cmd_lower:find("^wand") and not cmd_lower:find("^berserk")
        and not cmd_lower:find("^script") and not cmd_lower:find("^hide")
        and not cmd_lower:find("^nudgeweapon") then
        local hunting_stance = (bstate and bstate.hunting_stance) or "offensive"
        M.change_stance(hunting_stance, bstate)
    end

    -- =====================================================================
    -- COMMAND DISPATCH
    -- =====================================================================

    local result, reason

    -- Spell casting (numeric = spell ID)
    if cmd_lower:match("^incant%s+%d+") or cmd_lower:match("^%d+") then
        result, reason = M.cmd_spell(clean, target, bstate)

    -- Assault maneuvers
    elseif cmd_lower:match("^barrage") or cmd_lower:match("^flurry") or cmd_lower:match("^fury")
        or cmd_lower:match("^gthrusts") or cmd_lower:match("^pummel") or cmd_lower:match("^thrash") then
        result, reason = M.cmd_assault(clean, target, bstate)

    -- Weapon techniques
    elseif cmd_lower:match("^pindown") or cmd_lower:match("^cripple") or cmd_lower:match("^charge")
        or cmd_lower:match("^twinhammer") or cmd_lower:match("^dizzyingswing") or cmd_lower:match("^clash")
        or cmd_lower:match("^volley") or cmd_lower:match("^pulverize") or cmd_lower:match("^cyclone")
        or cmd_lower:match("^whirlwind") or cmd_lower:match("^wblade") then
        result, reason = M.cmd_weapons(clean, target, bstate)

    -- Shield maneuvers
    elseif cmd_lower:match("^shield throw") or cmd_lower:match("^shield bash")
        or cmd_lower:match("^shield charge") or cmd_lower:match("^shield strike")
        or cmd_lower:match("^shield pin") or cmd_lower:match("^shield trample")
        or cmd_lower:match("^shield push") then
        result, reason = M.cmd_shields(clean, target, bstate)

    -- Combat maneuvers
    elseif cmd_lower:match("^bullrush") or cmd_lower:match("^coupdegrace") or cmd_lower:match("^cpress")
        or cmd_lower:match("^dirtkick") or cmd_lower:match("^disarm") or cmd_lower:match("^exsanguinate")
        or cmd_lower:match("^feint") or cmd_lower:match("^gkick") or cmd_lower:match("^hamstring")
        or cmd_lower:match("^haymaker") or cmd_lower:match("^headbutt") or cmd_lower:match("^kifocus")
        or cmd_lower:match("^leapattack") or cmd_lower:match("^mblow") or cmd_lower:match("^sattack")
        or cmd_lower:match("^sbash") or cmd_lower:match("^sblow") or cmd_lower:match("^scleave")
        or cmd_lower:match("^sthieve") or cmd_lower:match("^sunder") or cmd_lower:match("^tackle")
        or cmd_lower:match("^trip") or cmd_lower:match("^truestrike") or cmd_lower:match("^vaultkick") then
        result, reason = M.cmd_cmans(clean, target, bstate)

    -- Feats
    elseif cmd_lower:match("^chastise") or cmd_lower:match("^excoriate") then
        result, reason = M.cmd_feats(clean, target, bstate)

    -- Gemstone jewels
    elseif cmd_lower:match("^jewel%s+(%w+)") then
        local mnemonic = cmd_lower:match("^jewel%s+(%w+)")
        result, reason = M.cmd_jewel(mnemonic, bstate)

    -- Bearhug
    elseif cmd_lower:match("^bearhug") then
        result, reason = M.cmd_bearhug(target, bstate)

    -- Rogue combat maneuvers
    elseif cmd_lower:match("^cutthroat") or cmd_lower:match("^divert") or cmd_lower:match("^shroud")
        or cmd_lower:match("^eviscerate") or cmd_lower:match("^eyepoke") or cmd_lower:match("^footstomp")
        or cmd_lower:match("^garrote") or cmd_lower:match("^kneebash") or cmd_lower:match("^mug")
        or cmd_lower:match("^nosetweak") or cmd_lower:match("^spunch") or cmd_lower:match("^subdue")
        or cmd_lower:match("^sweep") or cmd_lower:match("^swiftkick") or cmd_lower:match("^templeshot")
        or cmd_lower:match("^throatchop") then
        result, reason = M.cmd_rogue_cmans(clean, target, bstate)

    -- Warrior shouts
    elseif cmd_lower:match("^shout") or cmd_lower:match("^yowlp") or cmd_lower:match("^holler")
        or cmd_lower:match("^bellow") or cmd_lower:match("^growl") or cmd_lower:match("^cry") then
        result, reason = M.cmd_warrior_shouts(clean, target, bstate)

    -- Throw
    elseif cmd_lower:match("^throw") then
        result, reason = M.cmd_throw(target, bstate)

    -- Tangle Weed
    elseif cmd_lower:match("^k?weed") then
        result, reason = M.cmd_weed(clean, target, bstate)

    -- Wand
    elseif cmd_lower:match("^wand%f[%W]") then
        result, reason = M.cmd_wand(target, bstate)

    -- Wandolier
    elseif cmd_lower:match("^wandolier") then
        local stance = cmd_lower:match("^wandolier%s+(%w+)") or ""
        result, reason = M.cmd_wandolier(target, stance, bstate)

    -- Hide
    elseif cmd_lower:match("^hide") then
        local attempts = cmd_lower:match("^hide%s+(%d+)")
        result, reason = M.cmd_hide(attempts, bstate)

    -- MStrike
    elseif cmd_lower:match("^mstrike") then
        result, reason = M.cmd_mstrike(clean, target, bstate)

    -- Fire/ranged
    elseif cmd_lower:match("^fire") then
        result, reason = M.cmd_ranged(target, bstate)

    -- Dislodge
    elseif cmd_lower:match("^dislodge") then
        local loc = cmd_lower:match("^dislodge%s+(.+)$") or ""
        result, reason = M.cmd_dislodge(target, loc, bstate)

    -- Burst of Swiftness
    elseif cmd_lower:match("^burst") then
        result, reason = M.cmd_burst(bstate)

    -- Surge of Strength
    elseif cmd_lower:match("^surge") then
        result, reason = M.cmd_surge(bstate)

    -- Berserk
    elseif cmd_lower:match("^berserk") then
        result, reason = M.cmd_berserk(bstate)

    -- Script
    elseif cmd_lower:match("^script%s+") then
        local name, script_args = cmd_lower:match("^script%s+(%S+)%s*(.*)")
        result, reason = M.cmd_run_script(name, script_args, bstate)

    -- Sleep/wait
    elseif cmd_lower:match("^sleep%s+") then
        local time_str, nostance = cmd_lower:match("^sleep%s+(%d+)(%s+nostance)?")
        result, reason = M.cmd_sleep(time_str, nostance, target, bstate)

    -- Stance change
    elseif cmd_lower:match("^stance%s+") then
        local new_stance = cmd_lower:match("^stance%s+(.+)")
        M.change_stance(new_stance, bstate)
        result = true

    -- Wait for swing
    elseif cmd_lower:match("^wait%s+%d+") then
        local wait_secs = tonumber(cmd_lower:match("^wait%s+(%d+)"))
        pause(wait_secs or 1)
        result = true

    -- Nudge weapons
    elseif cmd_lower:match("^nudgeweapons?") then
        result, reason = M.cmd_nudge_weapons(bstate)

    -- Ambush
    elseif cmd_lower:match("^ambush") then
        local aim = cmd_lower:match("^ambush%s+(.+)$")
        result, reason = M.cmd_ambush(aim, target, bstate)

    -- Unarmed combat
    elseif cmd_lower:match("^unarmed%s+") then
        local unarmed_args = cmd_lower:match("^unarmed%s+(.+)$")
        result, reason = M.cmd_unarmed(unarmed_args, target, bstate)

    -- Voln Smite
    elseif cmd_lower:match("^smite") then
        result, reason = M.cmd_volnsmite(target, bstate)

    -- Caststop
    elseif cmd_lower:match("^caststop%s+") then
        local spell_str, cs_extra = cmd_lower:match("^caststop%s+(%d+)%s*(.*)")
        if spell_str then
            bstate._caststop_spell = tonumber(spell_str)
            bstate._caststop_extra = cs_extra or ""
        end
        result, reason = M.cmd_caststop(target, bstate)

    -- Unravel / Bard Dispel
    elseif cmd_lower:match("^unravel") or cmd_lower:match("^barddispel") then
        local unravel_extra = cmd_lower:match("^(?:unravel|barddispel)%s+(.+)$")
        if not unravel_extra then
            unravel_extra = cmd_lower:match("^unravel%s+(.+)$") or cmd_lower:match("^barddispel%s+(.+)$")
        end
        bstate._unravel_extra = unravel_extra or ""
        result, reason = M.cmd_unravel(target, bstate)

    -- Stomp
    elseif cmd_lower:match("^stomp") then
        result, reason = M.cmd_stomp(bstate)

    -- Leech
    elseif cmd_lower:match("^leech") then
        result, reason = M.cmd_leech(bstate)

    -- Rapid Fire
    elseif cmd_lower:match("^rapid") then
        local ignore = cmd_lower:match("^rapid%w*%s+(%w+)") or ""
        result, reason = M.cmd_rapid(ignore, bstate)

    -- Song of Depression
    elseif cmd_lower:match("^depress") then
        result, reason = M.cmd_depress(target, bstate)

    -- Phase (704)
    elseif cmd_lower:match("^phase") then
        result, reason = M.cmd_phase(target, bstate)

    -- Curse (715)
    elseif cmd_lower:match("^curse%s+") then
        local curse_type = cmd_lower:match("^curse%s+(%w+)")
        if curse_type then bstate._curse_type = curse_type end
        result, reason = M.cmd_curse(target, bstate)

    -- Elemental Fury (917)
    elseif cmd_lower:match("^efury") then
        local efury_extra = cmd_lower:match("^efury%s+(%w+)") or ""
        result, reason = M.cmd_efury(target, efury_extra, bstate)

    -- Dagger Hurl
    elseif cmd_lower:match("^dhurl") then
        local dhurl_aim = cmd_lower:match("^dhurl%s+(.+)$") or ""
        result, reason = M.cmd_dhurl(target, dhurl_aim, bstate)

    -- Briar
    elseif cmd_lower:match("^briar") then
        local briar_weapon = cmd_lower:match("^briar%s+(%w+)")
        result, reason = M.cmd_briar(briar_weapon, bstate)

    -- Assume Aspect (650)
    elseif cmd_lower:match("^assume") then
        local asp1, asp2 = cmd_lower:match("^assume%s+(%w+)%s*(%w*)")
        result, reason = M.cmd_assume(asp1, asp2, bstate)

    -- Wield
    elseif cmd_lower:match("^wield%s+") then
        local wield_args = cmd_lower:match("^wield%s+(.+)$")
        result, reason = M.cmd_wield(wield_args, bstate)

    -- Store
    elseif cmd_lower:match("^store") then
        local store_hand = cmd_lower:match("^store%s+(%w+)") or "both"
        result, reason = M.cmd_store(store_hand, bstate)

    -- Tether (706)
    elseif cmd_lower:match("^tether") then
        local recast = cmd_lower:find("recast")
        result, reason = M.cmd_tether(target, recast, bstate)

    -- Troubadour's Rally (1040)
    elseif cmd_lower:match("^1040") then
        result, reason = M.cmd_1040(target, bstate)

    -- Generic: send command as-is
    else
        debug_msg(bstate, "generic command | " .. clean)
        M.bs_put(clean, bstate)
        result = true
    end

    -- Register command for once/room tracking
    once_commands_register(target, original_command)

    return result, reason
end

-- ==========================================================================
-- Execute a full command routine (list of commands)
-- ==========================================================================

function M.execute_routine(routine, target, bstate)
    if not routine or #routine == 0 then return true end

    -- Check for stance commands in the list
    local stance_dance = true
    for _, cmd in ipairs(routine) do
        if cmd:lower():find("^stance") then
            stance_dance = false
            break
        end
    end

    for _, cmd_str in ipairs(routine) do
        -- Death check
        if dead and dead() then return false, "dead" end

        -- Target gone check
        if target and target.status and (target.status:find("dead") or target.status:find("gone")) then
            return true, "target dead"
        end

        -- Should rest check
        if bigshot_should_rest then
            return false, bigshot_rest_reason or "should rest"
        end

        M.execute(cmd_str, target, bstate)
    end

    return true
end

-- ==========================================================================
-- Module state accessors (for other bigshot modules)
-- ==========================================================================

function M.should_rest()
    return bigshot_should_rest, bigshot_rest_reason
end

function M.reset_rest()
    bigshot_should_rest = false
    bigshot_rest_reason = ""
end

function M.reset_combat_state()
    bigshot_aim = 0
    bigshot_archery_aim = 0
    bigshot_archery_stuck = {}
    bigshot_archery_location = nil
    bigshot_unarmed_tier = 1
    bigshot_unarmed_followup = false
    bigshot_unarmed_followup_attack = ""
    bigshot_mstrike_taken = false
    bigshot_rooted = false
    bigshot_bond_return = false
    bigshot_dislodge_target = nil
    bigshot_dislodge_location = {}
    COMMANDS_REGISTRY = {}
end

function M.get_smite_list()
    return bigshot_smite_list
end

function M.get_bless_list()
    return bigshot_bless
end

function M.add_bless(weapon_id)
    bigshot_bless[#bigshot_bless + 1] = weapon_id
end

function M.set_dislodge(target_id, locations)
    bigshot_dislodge_target = target_id
    bigshot_dislodge_location = locations or {}
end

return M
