-- osacrew/spellup.lua
-- Spellup, blessing, status-check, and resource-check subsystems for OSA Crew.
-- Ported from osacrew.lic v6.0.6 (Ganalon / original authors).
-- Lines 2406-2772.

local M = {}

-- ---------------------------------------------------------------------------
-- Armor Specialization
-- ---------------------------------------------------------------------------

-- M.self_armor_spec(osa)
-- Applies the character's own armor specialization based on osa.my_armor_spec.
-- Supported types: blessing, reinforcement, support, casting, evasion,
-- fluidity, stealth.  Waits for RT before each fput.
-- Note: the original source has a typo "reinforement"; preserved here to
-- match actual game command expected by the server.
-- Source: self_armor_spec, lines 2406-2429.
function M.self_armor_spec(osa)
    local spec = (osa.my_armor_spec or ""):lower()
    if spec == "" then return end

    waitrt()
    if spec:find("blessing") then
        fput("armor blessing")
    elseif spec:find("reinforcement") then
        fput("armor reinforement")   -- matches original (server-side typo)
    elseif spec:find("support") then
        fput("armor support")
    elseif spec:find("casting") then
        fput("armor casting")
    elseif spec:find("evasion") then
        fput("armor evasion")
    elseif spec:find("fluidity") then
        fput("armor fluidity")
    elseif spec:find("stealth") then
        fput("armor stealth")
    end
end

-- M.apply_support(supportlist)
-- Iterates supportlist — an array of {person, type} pairs — and applies each
-- armor specialization to the named crew member.  Pauses 5s between entries.
-- Source: crew_apply_support, lines 2431-2465.
function M.apply_support(supportlist)
    for _, entry in ipairs(supportlist) do
        local person = entry[1]
        local stype  = (entry[2] or ""):lower()

        waitrt()
        if stype:find("blessing") then
            fput("armor blessing " .. person)
        elseif stype:find("reinforcement") then
            fput("armor reinforement " .. person)
        elseif stype:find("support") then
            fput("armor support " .. person)
        elseif stype:find("casting") then
            fput("armor casting " .. person)
        elseif stype:find("evasion") then
            fput("armor evasion " .. person)
        elseif stype:find("fluidity") then
            fput("armor fluidity " .. person)
        elseif stype:find("stealth") then
            fput("armor stealth " .. person)
        end

        pause(5)
    end
end

-- ---------------------------------------------------------------------------
-- Mana helpers
-- ---------------------------------------------------------------------------

-- M.build_mana_message()
-- Builds a mana-request string based on which mana control skills this
-- character has at rank >= 24 (spirit, mental, elemental).
-- Returns: message string, mana_types table.
-- Source: mana_share, lines 2467-2498.
function M.build_mana_message()
    local mana_types = {}

    if Skills.smc >= 24 then
        table.insert(mana_types, "Spiritual")
    end
    if Skills.mmc >= 24 then
        table.insert(mana_types, "Mental")
    end
    if Skills.emc >= 24 then
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
        -- 3 types: "I Need Spiritual, Mental or Elemental Mana!"
        local last = mana_types[n]
        local rest = {}
        for i = 1, n - 1 do
            table.insert(rest, mana_types[i])
        end
        message = "I Need " .. table.concat(rest, ", ") .. " or " .. last .. " Mana!"
    end

    return message, mana_types
end

-- M.need_mana(osa, crew_channel)
-- Loops while ewaggle is running.  If percentmana drops below 15, broadcasts
-- the mana-request message on crew_channel and waits until mana recovers
-- above 15.
-- Source: need_mana, lines 2500-2508.
function M.need_mana(osa, crew_channel)
    local mana_message = M.build_mana_message()
    while running("ewaggle") do
        pause(1)
        if Char.percent_mana < 15 then
            LNet.channel(crew_channel, mana_message)
            wait_until(function() return Char.percent_mana > 15 end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Spell state helpers
-- ---------------------------------------------------------------------------

-- M.spellup_time_left()
-- Inspects all active spells.  Collects timeleft values in the 2–250 minute
-- range.  Returns the average time left, or 1 if no qualifying spells are
-- found.
-- Source: crew_spellup_time_left, lines 2510-2521.
function M.spellup_time_left()
    local times = {}
    for _, s in ipairs(Spell.active()) do
        local tl = s.timeleft
        if tl and tl > 2 and tl <= 250 then
            table.insert(times, tl)
        end
    end

    if #times == 0 then
        return 1
    end

    local total = 0
    for _, t in ipairs(times) do
        total = total + t
    end
    return total / #times
end

-- M.spell_individual(osa, pc)
-- If groupspellup is enabled AND Kroderine Soul is not active/known, runs
-- ewaggle (spells 181-240) for the specified crew member.
-- Source: crew_spell_individual, lines 2523-2531.
function M.spell_individual(osa, pc)
    if osa.groupspellup then
        if not (Feat and Feat.known("Kroderine Soul")) then
            echo("Spelling up, " .. pc)
            Script.run("ewaggle", "--start-at=181 --stop-at=240 " .. pc)
            M.need_mana(osa, osa.crew_channel)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Full spellup sequence
-- ---------------------------------------------------------------------------

-- M.spell_up(osa, crew_channel, supportlist)
-- Full spellup sequence:
--   1. If Empath: kill any running ecure, run "ecure group", wait for finish.
--   2. If Kroderine Soul known: leave group and reopen it.
--   3. Parse "mana" command output to check mana spellup availability; if
--      fewer than 90 minutes of spell time remain, use "mana spellup".
--   4. Run ewaggle for group members and/or self per osa settings.
--   5. Run need_mana loop while ewaggle runs.
--   6. Apply armor support specs and self armor spec.
--   7. Signal crew_task_complete.
-- Source: crew_spell_up, lines 2533-2585.
function M.spell_up(osa, crew_channel, supportlist)
    -- Step 1: Empath group heal before spellup
    if Stats.profession == "Empath" then
        if running("ecure") then
            Script.kill("ecure")
        end
        wait_while(function() return running("ecure") end)
        Script.run("ecure", "group")
        wait_while(function() return running("ecure") end)
    end

    -- Step 2: Kroderine Soul — must be ungrouped to self-buff
    if Feat and Feat.known("Kroderine Soul") then
        multifput("leave", "group open")
    end

    -- Step 3: Check mana spellup availability and use if warranted
    local mana_spellup_available = false
    if osa.mana_spellup then
        fput("mana")
        -- Give the output time to arrive, then scan recent lines
        pause(0.5)
        local recent = table.concat(reget(20), "\n")
        local used, total = recent:match("You have used the MANA SPELLUP ability (%S+) out of (%S+) times for today%.")
        if used and total then
            -- Strip commas from numbers before comparing
            local u = tonumber(used:gsub(",", "")) or 0
            local t = tonumber(total:gsub(",", "")) or 0
            if t > 0 and u < t then
                mana_spellup_available = true
            end
        end

        if mana_spellup_available then
            local avg_left = M.spellup_time_left()
            if avg_left <= 90 then
                waitrt()
                waitcastrt()
                pause(0.2)
                fput("mana spellup")
            end
        end
    end

    -- Step 4: Launch ewaggle
    if osa.groupspellup then
        -- Build the group member list from the Group module
        local members = Group and Group.members or {}
        local member_str = table.concat(members, " ")
        if osa.selfspellup then
            Script.run("ewaggle", "--start-at=181 --stop-at=240 " .. member_str .. " self")
        else
            Script.run("ewaggle", "--start-at=181 --stop-at=240 " .. member_str)
        end
    else
        if osa.selfspellup then
            Script.run("ewaggle", "--start-at=181 --stop-at=240 self")
        end
    end

    -- Step 5: Monitor mana while ewaggle runs
    M.need_mana(osa, crew_channel)

    -- Step 6: Armor specs
    if osa.armor_specs and supportlist and #supportlist > 0 then
        M.apply_support(supportlist)
        -- Clear the list after applying (mirrors @supportlist.clear)
        for i = #supportlist, 1, -1 do
            supportlist[i] = nil
        end
    end
    M.self_armor_spec(osa)

    -- Step 7: Signal completion
    if crew_task_complete then
        crew_task_complete()
    end
end

-- ---------------------------------------------------------------------------
-- Bless coordination
-- ---------------------------------------------------------------------------

-- M.receive_bless(osa)
-- Waits up to 15s for any of the bless-completion patterns.  If none arrive,
-- warns that something may have gone wrong.
-- Source: recieve_bless, lines 2589-2598.
function M.receive_bless(osa)
    local pat = "a moment and then gently dissipates|leaving a soft white afterglow|appears to become incorporated into it|but it quickly returns to normal"
    local result = matchtimeout(15, pat)
    if result and (
        result:find("a moment and then gently dissipates") or
        result:find("leaving a soft white afterglow") or
        result:find("appears to become incorporated into it") or
        result:find("but it quickly returns to normal")
    ) then
        return
    else
        respond("")
        respond("                                  Something May Have Gone Wrong With The Bless                               ")
        respond("")
    end
end

-- M.get_bless(osa)
-- Full flow for a crew member requesting a bless from osa.blesser:
--   1. Sends "I Need Blessed Please!" private to blesser.
--   2. Waits for blesser to announce this character's name on the crew channel.
--   3. Removes UAC hands/feet gear (or girds if none configured).
--   4. Ensures weapon is in right hand (swaps if needed).
--   5. Reports one or two weapons and calls receive_bless for each.
--   6. Re-equips UAC gear or stows both hands.
-- Source: get_bless, lines 2600-2643.
function M.get_bless(osa)
    if not osa.needbless then return end

    local blesser = osa.blesser
    local crew    = osa.crew_channel
    local myname  = GameState.name

    LNet.private(blesser, "I Need Blessed Please!")

    -- Wait for the blesser to call our name on the crew channel
    waitfor("^%[" .. crew .. "%]-GSIV:" .. blesser .. ": \"" .. myname)

    -- Handle UAC gear
    local uac_hands = osa.uac_hands or ""
    local uac_feet  = osa.uac_feet  or ""

    if uac_hands == "" and uac_feet == "" then
        fput("gird")
        pause(1)
    else
        if uac_hands ~= "" then
            fput("remove " .. uac_hands)
            pause(0.5)
        end
        if uac_feet ~= "" then
            fput("remove " .. uac_feet)
        end
    end

    -- Ensure item is in right hand
    local lh = GameObj.left_hand()
    local rh = GameObj.right_hand()
    if lh and not rh then
        fput("swap")
    end

    -- Re-fetch after potential swap
    lh = GameObj.left_hand()
    rh = GameObj.right_hand()

    if lh and rh then
        -- Two weapons
        LNet.private(blesser, "I Have Two.")
        LNet.private(blesser, "I Am Ready.")
        M.receive_bless(osa)
        fput("swap")
        LNet.private(blesser, "Ok, The Next One Is Ready.")
        M.receive_bless(osa)
    else
        -- One weapon
        LNet.private(blesser, "I Have One.")
        LNet.private(blesser, "I Am Ready.")
        M.receive_bless(osa)
    end

    -- Re-equip
    if uac_hands == "" and uac_feet == "" then
        fput("store both")
    else
        if uac_hands ~= "" then
            fput("wear " .. uac_hands)
            pause(0.5)
        end
        if uac_feet ~= "" then
            fput("wear " .. uac_feet)
        end
    end
end

-- M.cast_bless(osa, name)
-- Waits up to 5s for "I Am Ready." or "Ok, The Next One Is Ready." private
-- from name.  If received, casts Spell 1604 (Blessings of the Arkati) if
-- known and affordable, then Spell 304 (Holy Blade / Bless) if known and
-- affordable, else falls back to "symbol bless".
-- Source: cast_bless, lines 2645-2658.
function M.cast_bless(osa, name)
    local pat = "^%[Private%]-GSIV:" .. name .. ": \"I Am Ready%.\"|^%[Private%]-GSIV:" .. name .. ": \"Ok, The Next One Is Ready%.\""
    local result = matchtimeout(5, pat)
    if result and (
        result:find("I Am Ready%.") or
        result:find("Ok, The Next One Is Ready%.")
    ) then
        if Spell[1604].known and Spell[1604]:affordable() then
            Spell[1604]:cast(name)
        end
        waitcastrt()
        if Spell[304].known and Spell[304]:affordable() then
            Spell[304]:cast(name)
        else
            fput("symbol bless " .. name)
        end
    end
end

-- M.give_bless(osa, name)
-- Announces name on the crew channel, waits for the recipient to report one
-- or two weapons, then calls cast_bless the appropriate number of times.
-- Source: give_bless, lines 2660-2668.
function M.give_bless(osa, name)
    local crew = osa.crew_channel
    LNet.channel(crew, name)

    local pat_one = "^%[Private%]-GSIV:" .. name .. ": \"I Have One%.\""
    local pat_two = "^%[Private%]-GSIV:" .. name .. ": \"I Have Two%.\""
    local combined = "^%[Private%]-GSIV:" .. name .. ": \"I Have (?:One|Two)%.\""
    local result = matchtimeout(5, combined)

    if result then
        if result:match(pat_one) then
            M.cast_bless(osa, name)
        elseif result:match(pat_two) then
            M.cast_bless(osa, name)
            M.cast_bless(osa, name)
        end
    end
end

-- M.who_needs_blessed(osa, blessname)
-- Collects up to 3s of "I Need Blessed Please!" private LNet messages.
-- Appends each sender to blessname (mutates in-place).  Recurses until the
-- 3s window expires.
-- Source: who_needs_blessed, lines 2670-2676.
function M.who_needs_blessed(osa, blessname)
    local pat    = "^%[Private%]-GSIV:(.-): \"I Need Blessed Please!\""
    local result = matchtimeout(3, pat)
    if result then
        local sender = result:match(pat)
        if sender then
            table.insert(blessname, sender)
            M.who_needs_blessed(osa, blessname)
        end
    end
end

-- M.begin_bless(osa, crew_channel)
-- Full bless coordination sequence:
--   - If this character can bless (Spell 304 or 9802 known) and osa.givebless
--     is enabled:
--       announces intent, collects who needs a bless, gives each one.
--   - Otherwise:
--       asks "Can Anyone Bless?" on the crew channel; waits for "I Can
--       Captain!" private response; assigns that responder as blesser;
--       waits for them to complete and then calls get_bless for self.
-- Source: begin_bless, lines 2678-2702.
function M.begin_bless(osa, crew_channel)
    if (Spell[304].known or Spell[9802].known) and osa.givebless then
        LNet.channel(crew_channel, "I Will Be Providing All Crew Blessings!")
        local blessname = {}
        LNet.channel(crew_channel, "Does Anyone Need A Bless?")
        M.who_needs_blessed(osa, blessname)
        for _, name in ipairs(blessname) do
            M.give_bless(osa, name)
        end
        LNet.channel(crew_channel, "The Crew Has Been Properly Blessed!")
    else
        LNet.channel(crew_channel, "Can Anyone Bless?")
        local pat    = "^%[Private%]-GSIV:(.-): \"I Can Captain!\""
        local result = matchtimeout(3, pat)
        if result then
            local blesser = result:match(pat)
            if blesser then
                osa.blesser = blesser
                LNet.channel(crew_channel, blesser .. ", Will You Please Bless The Crew?")
                waitfor("^%[" .. crew_channel .. "%]-GSIV:" .. blesser .. ": \"Does Anyone Need A Bless%?\"")
                M.get_bless(osa)
                waitfor("^%[" .. crew_channel .. "%]-GSIV:" .. blesser .. ": \"The Crew Has Been Properly Blessed Captain!")
            end
        else
            LNet.channel(crew_channel, "We Do Not Have Anyone Present Who Can Bless The Crew, We Will Continue Without!")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Status / resource reporting
-- ---------------------------------------------------------------------------

-- M.status_check(osa)
-- Reports character vitals to commander (private) or own client (respond).
-- Parses "exp" output to detect capped vs non-capped state and read PTP/MTP.
-- Source: status_check, lines 2704-2737.
function M.status_check(osa)
    local commander = osa.commander
    local myname    = GameState.name

    -- Parse experience data
    fput("exp")
    pause(0.5)
    local recent = table.concat(reget(30), "\n")

    local capped      = false
    local exptntp     = nil
    local ptp         = nil
    local mtp         = nil

    if recent:find("Exp to next TP:") then
        capped  = true
        exptntp = recent:match("Exp to next TP: ([%d,]+)")
    end

    local ptp_val, mtp_val = recent:match("PTPs/MTPs: ([%d,]+)/([%d,]+)")
    if ptp_val then
        ptp = ptp_val
        mtp = mtp_val
    end

    -- Build status string
    local hp  = GameState.health     or 0
    local mhp = GameState.max_health  or 0
    local mn  = GameState.mana        or 0
    local mmn = GameState.max_mana    or 0
    local st  = GameState.stamina     or 0
    local mst = GameState.max_stamina or 0
    local sp  = GameState.spirit      or 0
    local msp = GameState.max_spirit  or 0
    local lv  = (Stats.level or 0) + 1
    local mind_text = GameState.mind or "clear"
    local enc  = GameState.encumbrance_value or 0

    -- Capitalise mind text (e.g. "somewhat_full" → "Somewhat Full")
    local mind_display = mind_text:gsub("[_ ]+", " "):gsub("(%a)([%w_']*)", function(f, r)
        return f:upper() .. r:lower()
    end)

    local msg
    if not capped then
        -- next_level_text is not exposed as a first-class API; use exp parse
        local exp_till_lvl = recent:match("Exp until lvl: ([%d,]+)") or "unknown"
        msg = string.format(
            "Health: %d/%d | Mana: %d/%d | Stamina: %d/%d | Spirit: %d/%d | Exp Till Level %d: %s | State Of Mind: %s | Percent Encumbrance: %d%%",
            hp, mhp, mn, mmn, st, mst, sp, msp, lv, exp_till_lvl, mind_display, enc
        )
    else
        msg = string.format(
            "Health: %d/%d | Mana: %d/%d | Stamina: %d/%d | Spirit: %d/%d | Exp Till Next TP: %s | %s PTP's | %s MTP's | State Of Mind: %s | Percent Encumbrance: %d%%",
            hp, mhp, mn, mmn, st, mst, sp, msp,
            exptntp or "unknown",
            ptp or "0", mtp or "0",
            mind_display, enc
        )
    end

    if myname ~= commander then
        pause(math.random(1, 3))
        LNet.private(commander, msg)
    else
        pause(1)
        respond("")
        respond("    Your Stats Are:           " .. msg)
        respond("")
    end
end

-- M.gemstone_check(osa)
-- Reports gemstone tracker data to commander.  In Revenant the killtracker
-- global is not available, so we report that tracking is unavailable.
-- Source: gemstone_check, lines 2740-2745.
function M.gemstone_check(osa)
    local commander = osa.commander
    local myname    = GameState.name
    local msg       = "Gemstone tracking not available (killtracker not implemented in Revenant)."
    if myname ~= commander then
        pause(math.random(1, 3))
        LNet.private(commander, msg)
    else
        respond(msg)
    end
end

-- M.resource_check(osa)
-- Issues "resource" command, parses weekly and total resource values, and
-- reports to commander (private) or own client (respond).
-- Supported resource names: Vitality, Necrotic Energy, Essence,
-- Motes of Tranquility, Devotion, Nature's Grace, Luck Inspiration, Grit,
-- Guile.
-- Source: resource_check, lines 2747-2772.
function M.resource_check(osa)
    local commander = osa.commander
    local myname    = GameState.name

    fput("resource")
    pause(0.5)
    local recent = table.concat(reget(30), "\n")

    -- Extract weekly resource (X/50,000)
    local resource_name, resource_weekly = recent:match(
        "(Vitality|Necrotic Energy|Essence|Motes of Tranquility|Devotion|Nature's Grace|Luck Inspiration|Grit|Guile): ([%d,]+)/50,000"
    )

    -- Extract total (X/200,000)
    local resource_total = recent:match("([%d,]+)/200,000")

    if not resource_name then
        return
    end

    local msg = string.format("Weekly %s: %s | Total %s: %s",
        resource_name, resource_weekly or "unknown",
        resource_name, resource_total  or "unknown"
    )

    if myname ~= commander then
        pause(math.random(1, 3))
        LNet.private(commander, msg)
    else
        pause(1)
        respond("")
        respond("    Your Resource Stats Are:           " .. msg)
        respond("")
    end
end

return M
