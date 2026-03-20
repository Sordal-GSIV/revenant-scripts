--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: healbot2025
--- version: 0.76
--- author: Daedeus
--- contributors: Gib, Auryana
--- game: gs
--- description: Empath heal bot - responds to heal requests, appraises targets, tracks empaths
--- tags: empath, healing, healbot
---
--- Usage: ;healbot2025
---        ;healbot2025 invasion  - faster healing mode
---
--- Features:
---   - Wait 6s before responding (gives other healers a chance)
---   - High mind → wait 24s if other empaths are present
---   - Low mind → move quickly (2s wait)
---   - Monitors for other empaths taking the same target, skips if so
---   - Handles dead body heal requests
---   - Scans and maintains known_empath list (via 'who profession empath', every 5 min)
---   - Hardcoded backup list of known empaths
---   - Appraises target before accepting heal request
---   - Responds to taps, friend arrivals, bard/rogue/scarab accidents
---   - Maintains Sign of Staunching if known
---   - Pauses bigshot while healing
---   - Invasion mode: faster healing, skips scar healing

local invasion = Script.vars[1] and Script.vars[1]:lower() == "invasion"
if invasion then
    echo("************************")
    echo("**** INVASION MODE *****")
    echo("************************")
end

-- Hardcoded known empaths (backup for players who hide profession from WHO)
local KnownEmpaths = Regex.new(
    "Tawariell|Suvean|Chandrellia|Phatall|Tranquia|Vrom|Invuna|" ..
    "Roqe|Aezha|Treeva|Elionwey|Wanion|Samyael|Balley|Kahlanni|" ..
    "Yosaffbrig|Snarc|Dirvy|Martyle|Cyana|Xanthras|Rhangath|Iseo|" ..
    "Archengrace|Minniemae|Hanscold|Elionway|Dowfen|Telare|Anditus|" ..
    "Aeraaxu|Mirando|Morvai|Svanya")

-- Auto-heal friends when they arrive (add names here)
local friendlist = {}

-- Never auto-heal these people
local ignore = {}

-- Load/save known_empaths from CharSettings (JSON-serialized table)
local function load_known_empaths()
    if CharSettings.known_empaths then
        local ok, t = pcall(Json.decode, CharSettings.known_empaths)
        if ok and type(t) == "table" then return t end
    end
    return {}
end

local function save_known_empaths(empaths)
    CharSettings.known_empaths = Json.encode(empaths)
end

local known_empaths = load_known_empaths()

local function count_table(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- Suppress WHO output from the game window while we scan
local function squelch_who()
    local started = false
    DownstreamHook.add("squelch-who", function(s)
        if started then
            if s:find("<prompt") then
                DownstreamHook.remove("squelch-who")
                return nil
            elseif s:find("<output") then
                return s
            else
                return nil
            end
        elseif s:find("Brave Adventurers Questing:") then
            started = true
            return nil
        else
            return s
        end
    end)
end

-- Scan WHO list for empaths and add to known_empaths
local function scan_for_empaths()
    echo("***Checking for new empaths...***")
    local number_added = 0
    squelch_who()
    silence_me()
    fput("who profession empath")
    silence_me()
    local in_list = false
    while true do
        local line = get()
        if line:find("Brave Adventurers Questing:") then
            in_list = true
        elseif in_list then
            if line:find("Total:") then break end
            -- Skip table headers and server messages
            if not line:find("^%[.*%]%-[A-Za-z]+:") and not line:find('^%[server%]:') then
                for name in line:gmatch("%u%l+") do
                    if not known_empaths[name] then
                        known_empaths[name] = "empath"
                        number_added = number_added + 1
                    end
                end
            end
        end
    end
    save_known_empaths(known_empaths)
    echo("***Added " .. number_added .. " new empaths to the list.***")
end

-- Appraise person and transfer all wounds; also transfer blood loss while healthy
local function gd_wound_transfer(person)
    fput("appraise " .. person)
    local line = matchtimeout(5, "You take a quick appraisal of")
    if not line or not line:find("You take a quick appraisal of") then return end

    local wounds = {}
    if line:find("head")                        then table.insert(wounds, "head") end
    if line:find("neck")                        then table.insert(wounds, "neck") end
    if line:find("right eye")                   then table.insert(wounds, "right eye") end
    if line:find("left eye")                    then table.insert(wounds, "left eye") end
    if line:find("back")                        then table.insert(wounds, "back") end
    if line:find("chest")                       then table.insert(wounds, "chest") end
    if line:find("abdomen") or line:find("abdominal") then table.insert(wounds, "abdomen") end
    if line:find("left arm")                    then table.insert(wounds, "left arm") end
    if line:find("right arm")                   then table.insert(wounds, "right arm") end
    if line:find("left hand")                   then table.insert(wounds, "left hand") end
    if line:find("right hand")                  then table.insert(wounds, "right hand") end
    if line:find("left leg")                    then table.insert(wounds, "left leg") end
    if line:find("right leg")                   then table.insert(wounds, "right leg") end
    if line:find("twitching") or line:find("convulsions") then table.insert(wounds, "nerves") end
    if line:find("no apparent injuries")        then wounds = {} end

    for _, wound in ipairs(wounds) do
        put("transfer " .. person .. " " .. wound)
        pause(0.25)
    end

    if not line:find("no apparent injuries") then
        local result = "You take some of somebody's blood loss."
        while health() > 75 and result:find("some of .+ blood loss") do
            fput("transfer " .. person)
            result = matchwait("You take", "You infuse", "Nothing happens.")
            if not result then break end
        end
    end

    echo("wound transfer done")
end

-- Cast a cure spell for cureloc at mana cost curemana.
-- Checks profession, level, circle ranks, and mana before casting.
-- Returns false if cast was attempted, true if skipped.
local function healbot_cure(cureloc, curemana)
    local curelevel = curemana
    if curelevel > 14 then curelevel = curelevel - 4 end
    waitrt()
    waitcastrt()
    if mana() >= curemana
        and Char.prof == "Empath"
        and Char.level >= curelevel
        and Spells.empath >= curelevel
    then
        if cureloc == "" then
            fput("cure")
        else
            fput("cure " .. cureloc)
        end
        pause(2)
        return false
    end
    waitrt()
    waitcastrt()
    return true
end

-- Heal self: wounds or scars, multi-pass by severity rank, mana-aware.
-- Does not heal rank 1 wounds/scars (let Troll's Blood handle those; avoid RT).
-- dtr: depth-to-reach (1-3 passes; pass 0=rank3, 1=rank2, 2=rank2 with lower cost)
local function healbot_healme(htype, dtr)
    if health() < max_health() then healbot_cure("", 1) end
    if dtr > 3 then dtr = 3 end
    if dtr < 1 then dtr = 1 end

    if htype == "Wounds" then
        local n_list = {3, 2, 2}
        local x_list = {5, 5, 0}
        for m = 1, dtr do
            local n = n_list[m]
            local x = x_list[m]
            if Wounds.head == n      then healbot_cure("head",       4 + x) end
            if Wounds.leftArm == n   then healbot_cure("left arm",   2 + x) end
            if Wounds.rightArm == n  then healbot_cure("right arm",  2 + x) end
            if Wounds.nsys == n      then healbot_cure("nerves",     3 + x) end
            if Wounds.leftEye == n   then healbot_cure("left eye",   5 + x) end
            if Wounds.rightEye == n  then healbot_cure("right eye",  5 + x) end
            if Wounds.leftHand == n  then healbot_cure("left hand",  2 + x) end
            if Wounds.rightHand == n then healbot_cure("right hand", 2 + x) end
            if not invasion then
                if Wounds.neck == n     then healbot_cure("neck",     4 + x) end
                if Wounds.chest == n    then healbot_cure("chest",    5 + x) end
                if Wounds.abdomen == n  then healbot_cure("abdomen",  5 + x) end
                if Wounds.leftLeg == n  then healbot_cure("left leg", 2 + x) end
                if Wounds.rightLeg == n then healbot_cure("right leg",2 + x) end
                if Wounds.back == n     then healbot_cure("back",     5 + x) end
            end
        end
    elseif htype == "Scars" then
        local n_list = {3, 2, 2}
        local x_list = {4, 4, 4}
        for m = 1, dtr do
            local n = n_list[m]
            local x = x_list[m]
            -- Skip scar healing during invasion (too much RT)
            if invasion then n = 4 end
            if Scars.head == n      then healbot_cure("head",       13 + x) end
            if Scars.neck == n      then healbot_cure("neck",       13 + x) end
            if Scars.chest == n     then healbot_cure("chest",      14 + x) end
            if Scars.abdomen == n   then healbot_cure("abdomen",    14 + x) end
            if Scars.leftArm == n   then healbot_cure("left arm",   11 + x) end
            if Scars.rightArm == n  then healbot_cure("right arm",  11 + x) end
            if Scars.leftLeg == n   then healbot_cure("left leg",   11 + x) end
            if Scars.rightLeg == n  then healbot_cure("right leg",  11 + x) end
            if Scars.back == n      then healbot_cure("back",       14 + x) end
            if Scars.leftHand == n  then healbot_cure("left hand",  11 + x) end
            if Scars.rightHand == n then healbot_cure("right hand", 11 + x) end
            if Scars.nsys == n      then healbot_cure("nerves",     12 + x) end
            if Scars.leftEye == n   then healbot_cure("left eye",   14 + x) end
            if Scars.rightEye == n  then healbot_cure("right eye",  14 + x) end
        end
    end
end

-- Check if any other known empaths are currently in the room
local function any_other_empaths()
    for _, pc in ipairs(GameObj.pcs()) do
        if pc.noun ~= Char.name and known_empaths[pc.noun] ~= nil then
            return true
        end
    end
    return false
end

-- Forward declarations for GUI callbacks (defined later, called inside process_line)
local gui_add_event, gui_set_current, gui_update_stats

-- Compiled regexes (module-level for reuse across calls)
-- Heal request: captures [1]=speaker_name, [2]=verb (whispers/asks/exclaims/says)
local heal_request_re = Regex.new(
    "(?:^Speaking .*?to )?(?:you, |(?:[A-Z][a-z]+), )?(?:The (?:ghostly voice|ghost) of )?" ..
    "([A-Z][a-z]+).*(whispers,|asks,|exclaims,|says,)" ..
    "(?i).*?(?:heal[^t]|bleed|minor|'?ealing?|lacerations|cuts|wound|patch|empath|poison|disease|medic)" ..
    ".*?(?:\\.|!|\\?)\"")

-- Arrival pattern
local arrival_re = Regex.new(
    "([A-Za-z]+)(?:'s group | )" ..
    "(just arrived|arrives at your table|just came crawling in|just limped in|" ..
    "just came marching in|just came sashaying in gracefully|just arrived, skipping merrily|" ..
    "just tiptoed in|just strode in|just stumbled in|just came trudging in)")

-- Process a single line from the game — handles all healbot triggers
local function process_line(line)

    -- ── Empath meditation detected → add to known list, skip healing ────────
    local med_name = line:match("([A-Z][a-z]+) meditates over")
    if med_name then
        if not known_empaths[med_name] then
            known_empaths[med_name] = "empath"
            save_known_empaths(known_empaths)
            echo("*** " .. med_name .. " is meditating — added as known empath ***")
        end
        return
    end

    -- ── Heal request (spoken/whispered/asked) ──────────────────────────────
    local caps = heal_request_re:captures(line)
    if caps then
        local healee = caps[1]  -- speaker name
        local verb   = caps[2]  -- whispers/asks/exclaims/says

        -- Skip "Speaking to Name" unless directed at us
        if line:find("Speaking .*to") and not line:find("Speaking .*to you") then
            return
        end

        -- Ignore list
        for _, ig in ipairs(ignore) do
            if ig == healee then return end
        end

        if not healee or healee:find("Speaking") then return end

        -- Collect dead PCs in room for dead-body handling
        local bodies = {}
        for _, pc in ipairs(GameObj.pcs()) do
            if pc.status and pc.status:find("dead") then
                table.insert(bodies, pc.name)
            end
        end

        -- Pause bigshot while we handle this
        if running("bigshot") then pause_script("bigshot") end

        echo("***** Healing requested by " .. healee .. "... *****")
        gui_set_current("Request from: " .. healee)

        -- Skip known empaths
        if known_empaths[healee] ~= nil or KnownEmpaths:test(healee) then
            echo("*** " .. healee .. " is an empath ***")
            gui_add_event(healee, "Skipped (empath)")
            return
        end

        -- Determine wait time based on mind load and room empaths
        local waittime  = 6
        local sleeptime = 3
        local mind = GameState.mind_value

        if mind <= 25 then
            waittime  = 2
            sleeptime = 1
            echo("*** Mind low, moving quickly on " .. healee .. " ***")
        end
        if mind > 70 then
            if not any_other_empaths() then
                echo("*** There seem to be no other empaths, so we won't wait extra long ***")
            else
                waittime = 24
                echo("*** Mind high, waiting longer to see if " .. healee .. " gets healed.. ***")
            end
        end
        if invasion then
            waittime = 3
            echo("*** It's an invasion, we'll move quickly ***")
        end
        if verb and verb:find("whispers") then
            echo("*** Direct whisper, expediting ***")
            sleeptime = 1
            waittime  = 1
        end

        -- Watch for a competing healer taking this target
        local result = matchtimeout(waittime + checkrt(),
            "nods at " .. healee,
            "nods to " .. healee,
            "focuses on " .. healee .. " with intense concentration")
        if result then
            local other = result:match("^(.+) nods at") or
                          result:match("^(.+) nods to ")  or
                          result:match("^(.+) focuses on " .. healee .. " with intense concentration")
            if other then
                echo("***** Looks like " .. other .. " is healing " .. healee .. ". ******")
                gui_add_event(healee, "Skipped (beaten by " .. other .. ")")
                return
            end
        end

        echo("***** We will heal " .. healee .. ". ******")

        -- Appraise to confirm injuries
        local appraise = dothistimeout("appraise " .. healee, 5, "You take a quick appraisal")
        if appraise and appraise:find("no apparent injuries") then
            echo("***** " .. healee .. " is not injured.  False alarm? *****")
            if #bodies > 0 then
                -- Maybe they're requesting for a dead body
                local deader = nil
                for _, body in ipairs(bodies) do
                    if line:find(body, 1, true) then
                        deader = body
                        break
                    end
                end
                if deader then
                    echo("*** Maybe they are talking about the dead body, " .. deader .. " ***")
                    local dead_appraise = dothistimeout("appraise " .. deader, 5, "You take a quick appraisal")
                    if dead_appraise and dead_appraise:find("no apparent injuries") then
                        echo("*** The dead body has no injuries. ***")
                        return
                    else
                        fput("nod " .. healee)
                        fput("nod " .. deader)
                        healee = deader
                    end
                else
                    return
                end
            else
                return
            end
        else
            fput("nod " .. healee)
        end

        pause(sleeptime)
        gui_set_current("Healing: " .. healee)
        gui_add_event(healee, "Transferring wounds")
        gd_wound_transfer(healee)
        gui_set_current("Waiting for heal requests...")
        return
    end

    -- ── Friend arrived ──────────────────────────────────────────────────────
    local acaps = arrival_re:captures(line)
    if acaps then
        local who = acaps[1]
        for _, f in ipairs(friendlist) do
            if f == who then
                echo("Friend " .. who .. " arrived.")
                gd_wound_transfer(who)
                return
            end
        end
        return
    end

    -- ── Direct tap ─────────────────────────────────────────────────────────
    local tapper = line:match("([A-Za-z]+) taps you lightly on the shoulder")
    if tapper then
        echo("Direct tap.")
        pause(2)
        fput("nod " .. tapper)
        pause(2)
        gd_wound_transfer(tapper)
        return
    end

    -- ── Bard accident (gem shatter) ─────────────────────────────────────────
    if line:find("shatters into thousands of fragments") then
        local bard_re = Regex.new("(.*)'s voice focuses on the .* which quickly shatters into thousands of fragments")
        local bcaps = bard_re:captures(line)
        if bcaps and bcaps[1] then
            echo("Uh oh bard accident.")
            gd_wound_transfer(bcaps[1])
        end
        return
    end

    -- ── Rogue accident (perforation / boiling ground) ───────────────────────
    if line:find("severely perforated") or line:find("begins to boil violently") then
        local rogue_re = Regex.new("(.*) is severely perforated|The ground beneath (.*) begins to boil violently")
        local rcaps = rogue_re:captures(line)
        if rcaps then
            local victim = rcaps[1] or rcaps[2]
            if victim then
                echo("Uh oh rogue accident.")
                gd_wound_transfer(victim)
            end
        end
        return
    end

    -- ── Scarab poison ───────────────────────────────────────────────────────
    if line:find("sickly greenish hue") then
        local sc_re = Regex.new("\\. (.*) looks ill as (?:his|her) skin takes on a sickly greenish hue")
        local scaps = sc_re:captures(line)
        if scaps and scaps[1] then
            echo("Uh oh scarab poison.")
            Spell[114]:cast(scaps[1])
            gd_wound_transfer(scaps[1])
        end
        return
    end

    -- ── Scarab disease ──────────────────────────────────────────────────────
    if line:find("yellowish tint") then
        local dis_re = Regex.new("\\. (.*?) moans to (?:him|her)self and (?:his|her) skin takes on a yellowish tint\\.")
        local dcaps = dis_re:captures(line)
        if dcaps and dcaps[1] then
            echo("Uh oh scarab disease")
            Spell[113]:cast(dcaps[1])
        end
        return
    end

    -- ── Blood scarab ────────────────────────────────────────────────────────
    if line:find("drawing the blood from his body") then
        local blood_re = Regex.new("(.*) gasps in pain and shock as .* drawing the blood from his body")
        local blcaps = blood_re:captures(line)
        if blcaps and blcaps[1] then
            echo("Uh oh blood scarab.")
            for _ = 1, 10 do
                fput("transfer " .. blcaps[1])
                fput("cure blood")
                pause(3)
            end
        end
        return
    end
end

-- ── GUI ────────────────────────────────────────────────────────────────────

local gui_win         = nil
local gui_status_lbl  = nil
local gui_mind_lbl    = nil
local gui_health_lbl  = nil
local gui_mana_lbl    = nil
local gui_empaths_lbl = nil
local gui_current_lbl = nil
local gui_events_tbl  = nil
local gui_events      = {}

gui_add_event = function(healee, event_text)
    if not gui_win then return end
    local ts = os.date("%H:%M:%S")
    table.insert(gui_events, 1, { ts, healee or "?", event_text })
    if #gui_events > 50 then table.remove(gui_events) end
    gui_events_tbl:clear()
    for _, row in ipairs(gui_events) do
        gui_events_tbl:add_row(row)
    end
end

gui_set_current = function(text)
    if gui_current_lbl then gui_current_lbl:set_text(text) end
end

gui_update_stats = function(empath_count)
    if not gui_win then return end
    local mind  = GameState.mind_value or 0
    local hp    = health()     or 0
    local hpmax = max_health() or 100
    local mn    = mana()       or 0
    local mnmax = max_mana()   or 100
    gui_mind_lbl:set_text(string.format("Mind: %3d%%", mind))
    gui_health_lbl:set_text(string.format("  HP: %d/%d", hp, hpmax))
    gui_mana_lbl:set_text(string.format("  Mana: %d/%d", mn, mnmax))
    gui_empaths_lbl:set_text(string.format("Known empaths: %d", empath_count))
end

local function init_gui()
    local mode_text = invasion and "HealBot 2025  ─  INVASION MODE" or "HealBot 2025  ─  Active"
    gui_win = Gui.window(mode_text, { width = 420, height = 500, resizable = true })
    local root = Gui.vbox()

    -- Status header
    gui_status_lbl = Gui.label(mode_text)
    root:add(gui_status_lbl)
    root:add(Gui.separator())

    -- Stats card
    local stats_card = Gui.card({ title = "Character Status" })
    local stats_row  = Gui.hbox()
    gui_mind_lbl    = Gui.label("Mind:   ---")
    gui_health_lbl  = Gui.label("  HP:   ---")
    gui_mana_lbl    = Gui.label("  Mana: ---")
    stats_row:add(gui_mind_lbl)
    stats_row:add(gui_health_lbl)
    stats_row:add(gui_mana_lbl)
    stats_card:add(stats_row)
    gui_empaths_lbl = Gui.label("Known empaths: 0")
    stats_card:add(gui_empaths_lbl)
    root:add(stats_card)

    -- Current action
    gui_current_lbl = Gui.label("Waiting for heal requests...")
    root:add(gui_current_lbl)
    root:add(Gui.separator())

    -- Events table
    local events_card = Gui.card({ title = "Recent Events" })
    gui_events_tbl = Gui.table({ columns = { "Time", "Healee", "Event" } })
    events_card:add(Gui.scroll(gui_events_tbl))
    root:add(events_card)

    gui_win:set_root(root)
    gui_win:show()
    gui_win:on_close(function() gui_win = nil end)
end

-- Try to open GUI (optional; continues if monitor feature not compiled in)
local gui_ok, gui_err = pcall(init_gui)
if not gui_ok then
    echo("[healbot] GUI unavailable: " .. tostring(gui_err))
end

-- ── Startup ──────────────────────────────────────────────────────────────────
echo("***HealBot knows about " .. count_table(known_empaths) .. " empaths.***")
scan_for_empaths()
local last_scan = GameState.server_time

-- ── Main loop ────────────────────────────────────────────────────────────────
while true do
    -- Scan for new empaths every 5 minutes
    if GameState.server_time - last_scan > 300 then
        scan_for_empaths()
        last_scan = GameState.server_time
    end

    -- Keep Sign of Staunching active
    local sos = Spell["Sign of Staunching"]
    if sos and sos.known and sos:affordable() and not sos.active then
        fput("sign of staunching")
    end

    gui_update_stats(count_table(known_empaths))

    local line = matchtimeout(10,
        "whispers", "asks", "exclaims", "says",
        "just arrived", "just came", "just limped", "just strode",
        "just stumbled", "just tiptoed", "just trudged", "arrives at your table",
        "taps you lightly on the shoulder",
        "shatters into thousands of fragments",
        "severely perforated",
        "drawing the blood from his body",
        "begins to boil violently",
        "sickly greenish hue",
        "yellowish tint",
        "meditates over")

    if line then
        process_line(line)
    end

    healbot_healme("Wounds", 3)
    healbot_healme("Scars", 3)
end
