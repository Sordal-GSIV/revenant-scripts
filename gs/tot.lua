--- @revenant-script
--- name: tot
--- version: 1.1.0
--- author: Alastir
--- game: gs
--- description: Trick or Treat automation — door knocking, soul shard/candy/token/invitation tracking
--- tags: halloween, trick or treat, event, seasonal
--- @lic-certified: complete 2026-03-19
---
--- Original .lic author: Alastir (10/3/2022)
--- Ported to Revenant Lua by: Sordal
---
--- Changelog from Lich5:
---   v1.1.0 (2026-03-19) — Full Revenant port; Frontend.supports_streams() replaces
---             $frontend == "stormfront"; command handler replaces ;e globals;
---             stream to loot window via pushStream XML; unified knock_door helper;
---             os.time() timing replacing Time.now; fmt_mmss replacing strftime
---
--- Setup:
---   1. Purchase a candy bag at [In The Bag, Entry - 31584]
---   2. ;vars set lootsack=<container>  (e.g. backpack, cloak)
---   3. ;vars set keepsack=<container>  (for tokens/invitations; defaults to lootsack)
---   4. Configure bigshot (Hunting Tab and Commands Tab) — uses ;bigshot quick for combat
---   5. Start with combat gear in hands (or empty hands; script uses GIRD)
---   6. Start at room #31980:  ;tot
---
--- In-game commands while running:
---   ;tot pause    — toggle pause between runs (default: off)
---   ;tot drops    — toggle picking up gem/stone drops (default: on)
---
--- Variables:
---   Vars.lootsack — container for broken treasure / gem drops
---   Vars.keepsack — container for tokens and invitations (optional, defaults to lootsack)

-- ─── Runtime settings ─────────────────────────────────────────────────────────
local tot_pause = false
local tot_drops = true

-- ─── Run statistics ────────────────────────────────────────────────────────────
local tot_total       = 0    -- soul shards found this barrel run
local tot_knocks_left = 10   -- knocks remaining this barrel
local tot_grand_total = 0    -- cumulative soul shards across all barrels
local tot_start_time  = 0    -- os.time() when current barrel started

-- ─── Starting room pool (sampled without replacement per barrel) ───────────────
local ALL_STARTING_LOCATIONS = {"32033","32038","32026","32029","32000","32009","31990"}
local starting_locations     = {}

-- ─── Wander state ─────────────────────────────────────────────────────────────
local wander_last_room = nil

-- ─── Container names ──────────────────────────────────────────────────────────
local lootsack = Vars.lootsack or "backpack"
local keepsack = Vars.keepsack or lootsack

-- ─── Helpers ──────────────────────────────────────────────────────────────────
--- Format seconds as MM:SS (mirrors Ruby Time.at(secs).strftime("%M:%S"))
local function fmt_mmss(secs)
    secs = math.max(0, math.floor(secs + 0.5))
    return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

--- Stream text to the Loot window (Stormfront/Wrayth); respond() on plain clients.
local function loot_stream(text)
    if Frontend.supports_streams() then
        put('<pushStream id="loot" ifClosedStyle="watching"/>' .. text .. '\r\n<popStream/>\r\n')
    else
        respond(text)
    end
end

-- ─── Command handler ──────────────────────────────────────────────────────────
UpstreamHook.add("tot_cmds", function(line)
    local cmd = line:match("^;tot%s+(.*)")
    if not cmd then return line end
    cmd = cmd:lower():match("^%s*(.-)%s*$")
    if cmd == "pause" then
        tot_pause = not tot_pause
        respond("[tot] Pause between runs: " .. tostring(tot_pause))
    elseif cmd == "drops" then
        tot_drops = not tot_drops
        respond("[tot] Pick up gem/stone drops: " .. tostring(tot_drops))
    end
    return nil  -- squelch ;tot commands from reaching the game
end)

before_dying(function()
    UpstreamHook.remove("tot_cmds")
end)

-- ─── Intro ────────────────────────────────────────────────────────────────────
respond("[tot] Trick or Treat script by Alastir")
respond("[tot] Variables:")
respond("[tot]   Vars.lootsack = " .. lootsack)
respond("[tot]   Vars.keepsack = " .. keepsack)
respond("[tot] The script can be paused between runs:")
respond("[tot]   tot_pause = " .. tostring(tot_pause) .. "  (;tot pause to toggle)")
respond("[tot] The script can pick up gem/stone drops and break them:")
respond("[tot]   tot_drops = " .. tostring(tot_drops) .. "  (;tot drops to toggle)")
respond("[tot] You NEED a candy bag (purchased at [In The Bag, Entry - 31584])")
respond("[tot] Start at room #31980, then: ;unpause tot")
pause_script()

-- ─── Combat helpers ───────────────────────────────────────────────────────────
local function stand()
    if not standing() then
        waitrt()
        fput("stance offensive")
        local tries = 0
        while not standing() and tries < 10 do
            fput("stand")
            pause(0.5)
            tries = tries + 1
        end
    end
end

local function haste()
    waitrt()
    waitcastrt()
    local prof = Stats.prof
    if prof == "Bard" then
        if not Spell[1035].active and Spell[1035].known and Spell[1035]:affordable() then
            Spell[1035]:cast()
        end
    elseif prof == "Wizard" then
        if not Spell[506].active and Spell[506].known and Spell[506]:affordable() then
            Spell[506]:cast()
        end
    end
end

--- Manual attack loop (used for Alastir's character specifically).
local function do_attack()
    stand()
    haste()
    if GameState.stance ~= "offensive" then
        fput("stance offensive")
    end
    while true do
        local result = dothistimeout("attack", 2,
            "You thrust", "You swing", "You lunge", "You hack", "You slash",
            "You do not currently have a target",
            "You currently have no valid target",
            "Be at peace my child",
            "%.%.%.wait", "Wait %d+ second",
            "Please rephrase")
        if not result then break end
        if result:find("You thrust") or result:find("You swing") or
           result:find("You lunge")  or result:find("You hack")  or result:find("You slash") then
            pause(0.1)
            waitrt()
            waitcastrt()
            -- continue attacking
        elseif result:find("do not currently have a target") or
               result:find("no valid target") or
               result:find("Be at peace") then
            fput("loot")
            break
        elseif result:find("wait") or result:find("Wait") then
            -- roundtime: retry immediately
        else
            break
        end
    end
end

--- Pick up gems and stones from the ground and stow them.
local function tot_cleanup()
    local gem_re = Regex.new(
        "agate|alexandrite|amethyst|auroraline|crowstone|crystal|dreamstone|" ..
        "everine|fluorite|jasper|obsidian|onyx|opal|rosette|sapphire|" ..
        "scolecite|scoria|soulstone|stone|sunstone")
    local loot = GameObj.loot()
    local has_gems = false
    for _, obj in ipairs(loot) do
        if obj.noun and gem_re:test(obj.noun) then
            has_gems = true
            break
        end
    end
    if not has_gems then return end

    fput("store all")
    loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        if obj.noun and gem_re:test(obj.noun) then
            local result = dothistimeout("get #" .. obj.id, 5,
                "You can't pick that up",
                "You gather the remaining",
                "You pick up",
                "You can only loot creatures",
                "You reach out and try to grab")
            if not result then
                break
            elseif result:find("You can't pick that up") then
                break
            elseif result:find("You pick up") then
                fput("put #" .. obj.id .. " in my " .. lootsack)
            elseif result:find("You can only loot creatures") then
                fput("out")
            elseif result:find("You reach out and try to grab") then
                break
            end
        end
    end
end

--- Break a treasure object; stow silver or the resulting item.
local function tot_break(obj)
    pause(0.3)
    local result = dothistimeout("break #" .. obj.id, 10,
        "Glancing around, you notice some silver coins scattered across the floor",
        "Glancing around, you notice .* on the floor and pick it up",
        "I don't understand what you typed")
    if result and result:find("silver coins") then
        fput("get coins")
    elseif result and result:find("Glancing around, you notice") then
        local rh = GameObj.right_hand()
        if rh then
            fput("put " .. rh.noun .. " in my " .. lootsack)
        end
    end
end

--- Full combat cycle: run bigshot quick (or manual attack) until room is clear.
local function tot_attack()
    fput("target random")
    local function has_live_targets()
        local targets = GameObj.targets()
        for _, npc in ipairs(targets) do
            if npc.status and not (npc.status:find("dead") or npc.status:find("gone")) then
                return true
            end
        end
        return false
    end

    while has_live_targets() do
        if Char.name == "Alastir" then
            stand()
            haste()
            do_attack()
        elseif Script.exists("bigshot") then
            Script.run("bigshot", "quick")
            wait_while(function() return running("bigshot") end)
            if Stats.prof == "Sorcerer" then
                fput("stop 709")
            end
            fput("loot")
        else
            respond("[tot] Bigshot not found — handle the creature and unpause when done.")
            fput("stance defensive")
            pause_script()
            fput("store all")
            fput("loot")
        end

        if tot_drops then
            tot_cleanup()
        end
    end
end

-- ─── Candy helper ─────────────────────────────────────────────────────────────
local function candy()
    local result = dothistimeout("put my candy in my bag", 5,
        "Having located the interior compartment specific",
        "I could not find what you were referring to")
    if result and result:find("I could not find what you were referring to") then
        fput("put my candy in my " .. lootsack)
    end
end

-- ─── Round stats / reset ──────────────────────────────────────────────────────
local function to_start()
    loot_stream("Total Found: " .. tot_total .. " soul shards.")
    tot_grand_total = tot_grand_total + tot_total
    loot_stream("Grand Total: " .. tot_grand_total .. " soul shards.")
    local elapsed = os.time() - tot_start_time
    loot_stream("Total Time: " .. fmt_mmss(elapsed) .. "!")
    if tot_pause then
        pause_script()
    end
end

-- ─── Encumbrance guard ────────────────────────────────────────────────────────
local function check_encumbrance()
    if GameState.encumbrance_value >= 20 then
        for _ = 1, 5 do
            respond("[tot] You're carrying too much stuff, lighten up!")
        end
        Script.kill(Script.name)
    end
end

-- ─── Wander ───────────────────────────────────────────────────────────────────
local BAD_ROOMS = {["29290"] = true, ["29291"] = true, ["29292"] = true}

local function wander()
    if Room.id == 4 then
        walk()
        return
    end
    local room = Room.current()
    if not room or not room.wayto then
        walk()
        return
    end

    -- Build list of eligible exits (excluding bad rooms)
    local options = {}
    for dest_id, cmd in pairs(room.wayto) do
        if not BAD_ROOMS[dest_id] then
            table.insert(options, {id = dest_id, cmd = cmd})
        end
    end

    if #options == 0 then
        walk()
        return
    end

    -- Avoid immediately backtracking to last room
    if #options > 1 and wander_last_room then
        local filtered = {}
        for _, opt in ipairs(options) do
            if opt.id ~= wander_last_room then
                table.insert(filtered, opt)
            end
        end
        if #filtered > 0 then options = filtered end
    end

    local choice = options[math.random(#options)]
    move(choice.cmd)
    wander_last_room = tostring(room.id)
end

-- ─── Start a new barrel run ───────────────────────────────────────────────────
local function start()
    local result = dothistimeout("go entry", 5,
        "shadowy apparition accepts your key and unlocks a large gated entry",
        "You need to redeem a barrel key to get inside")
    if result and result:find("shadowy apparition accepts") then
        tot_start_time  = os.time()
        tot_total       = 0
        tot_knocks_left = 10

        -- Refill starting location pool when exhausted
        if #starting_locations == 0 then
            for _, r in ipairs(ALL_STARTING_LOCATIONS) do
                table.insert(starting_locations, r)
            end
        end

        -- Pick a random starting room and remove it from the pool
        local idx  = math.random(#starting_locations)
        local room = starting_locations[idx]
        table.remove(starting_locations, idx)
        loot_stream("~ Starting in room " .. room .. "!")

        Script.run("go2", room)
        wait_while(function() return running("go2") end)

    elseif result and result:find("barrel key") then
        loot_stream("~ Out of Entries!")
        error("[tot] No barrel keys remaining — stopping.")
    end
end

-- ─── Door knocking ────────────────────────────────────────────────────────────
-- Shared handler for items tossed by the spectral hand.
local function handle_spectral_gift(result)
    tot_knocks_left = tot_knocks_left - 1

    if result:find("soul shards") then
        -- Extract the soul shard count (may be "a large bag of 500", "a small bag of 250",
        -- or "tosses you 75 soul shards directly").
        local amount = 0
        local raw = result:match("bag of (%d+) soul shards")
                 or result:match("tosses you (%d+) soul shards")
        if raw then
            amount = tonumber(raw) or 0
        else
            -- Fallback: grab everything between "bag of" / "tosses you" and "soul shards"
            local word = result:match("bag of (.+) soul shards that")
                      or result:match("tosses you (.+) soul shards that")
            if word then amount = tonumber(word) or 0 end
        end
        tot_total = tot_total + amount
        loot_stream("Found " .. amount .. " soul shards. (" .. tot_knocks_left .. ")")
        respond("[tot] You have " .. tot_knocks_left .. " knocks left.")

    elseif result:find("wrapped piece of candy") then
        loot_stream("Found candy! (" .. tot_knocks_left .. ")")
        candy()
        respond("[tot] You have " .. tot_knocks_left .. " knocks left.")

    elseif result:find("pumpkin%-etched token") or result:find("pair of .* species") then
        loot_stream("* Found token! (" .. tot_knocks_left .. ")")
        fput("put token in my " .. keepsack)
        respond("[tot] You have " .. tot_knocks_left .. " knocks left.")

    elseif result:find("painted black invitation") then
        -- Pause immediately for the rare invitation
        loot_stream("*** Found INVITATION!!!!! (" .. tot_knocks_left .. ")")
        fput("put invitation in my " .. keepsack)
        respond("[tot] INVITATION found — unpause the script to continue.")
        pause_script()
        respond("[tot] You have " .. tot_knocks_left .. " knocks left.")

    elseif result:find("ghezyte%-veined sea glass bauble") then
        loot_stream("Found sea glass bauble! (" .. tot_knocks_left .. ")")
        fput("put bauble in my " .. keepsack)
        respond("[tot] You have " .. tot_knocks_left .. " knocks left.")
    end
end

-- Shared creature-encounter logic (bursts out / thrown inside).
local function handle_creature()
    loot_stream("Found creature!")
    fput("gird")
    tot_attack()
    fput("store all")
    fput("out")
end

-- Shared free-hand check.
local function ensure_free_hand()
    fput("store weapon")
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh then
        fput("put " .. rh.noun .. " in my " .. lootsack)
    elseif lh then
        fput("put " .. lh.noun .. " in my " .. lootsack)
    end
end

-- Patterns shared by knockone and knocktwo.
local KNOCK_PATTERNS = {
    "You've recently knocked on this door%.",
    "What were you referring to%?",
    "A spectral hand tosses you",
    "bursts out, clearly angered",
    "grabs you and throws you inside",
    "You don't have time to knock",
    "You need a free hand to knock",
}

-- Forward declarations so knockone can call knocktwo and vice versa.
local knockone, knocktwo

--- Perform the first door knock in a room; on success proceed to knocktwo.
knockone = function()
    -- If we wandered back to the neighborhood entrance, print run stats.
    if Room.title == "Endeltime Estates, Neighborhood" then
        to_start()
        return
    end
    if Room.id == 31583 then
        fput("go neighborhood")
    end

    -- Store any left-hand item before knocking.
    local lh = GameObj.left_hand()
    if lh then fput("store left") end

    local result = dothistimeout("knock door", 5, table.unpack(KNOCK_PATTERNS))
    if not result then
        to_start()
        return
    end

    if result:find("You've recently knocked on this door") then
        knocktwo()
    elseif result:find("What were you referring to") then
        to_start()
    elseif result:find("A spectral hand tosses you") then
        handle_spectral_gift(result)
        knocktwo()
    elseif result:find("bursts out") or
           result:find("grabs you and throws you inside") or
           result:find("You don't have time to knock") then
        handle_creature()
        knocktwo()
    elseif result:find("You need a free hand to knock") then
        ensure_free_hand()
    end
end

--- Perform the second door knock in a room; on success proceed to wander.
knocktwo = function()
    if Room.title == "Endeltime Estates, Neighborhood" then
        to_start()
        return
    end
    if Room.id == 31583 then
        fput("go neighborhood")
    end

    local lh = GameObj.left_hand()
    if lh then fput("store left") end

    local result = dothistimeout("knock other door", 5, table.unpack(KNOCK_PATTERNS))
    if not result then
        to_start()
        return
    end

    if result:find("You've recently knocked on this door") then
        wander()
    elseif result:find("What were you referring to") then
        to_start()
    elseif result:find("A spectral hand tosses you") then
        handle_spectral_gift(result)
        wander()
    elseif result:find("bursts out") or
           result:find("grabs you and throws you inside") or
           result:find("You don't have time to knock") then
        handle_creature()
        wander()
    elseif result:find("You need a free hand to knock") then
        ensure_free_hand()
    end
end

-- ─── Main loop ────────────────────────────────────────────────────────────────
while true do
    check_encumbrance()

    if Room.id == 31980 then
        loot_stream("~ I'm going Trick or Treating!")
        start()
    else
        knockone()
    end
end
