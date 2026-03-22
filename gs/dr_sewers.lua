--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: dr_sewers
--- version: 2.0.0
--- author: Alastir
--- game: gs
--- description: Duskruin Bloodriven Village sewer search automation
--- tags: duskruin, sewers, bloodscrip, event
---
--- Original author: Alastir
--- Changelog (Lich5):
---   2018-06-14 - Initial release
---   2022-02-26 - Removed auto-chat to merchant; added bloodscrip counter per run and grand total;
---                shows how many searches left per sewer run
---   2023-08-15 - Changed from bookletsack to eventsack for script uniformity
---   2025-08-08 - Removed booklet system (go grate uses stamped voucher directly);
---                converted to UIDs for Shattered/Platinum instance support
---
--- Converted to Revenant Lua by Sordal-GSIV 2026-03-20
--- Full parity with dr_sewers.lic revision 2025-08-08:
---   per-run timing, stream_window loot/familiar output, stun detection in search loop,
---   hidden-person detection, phosphorescent slime dribble handling, shimmering indigo orb
---   (3x RPA), cache bloodscrip congrats, full rare-find flow (rod/swatch/thread/dust),
---   cesspool total/time reporting, eventsack variable removed (voucher used directly)
---
--- Usage:
---   ;dr_sewers
--- Variables (set with ;vars set key=value):
---   lootsack  — container for normal finds (bloodscrip, crystals, rats, generic items)
---   keepsack  — container for rare finds (rod, swatch, thread, dust, indigo orb)

local Vars = require("lib/vars")

-- ── Startup configuration display ─────────────────────────────────────────────

echo("This script provided by Alastir")
echo("")
echo("Variables used:")
echo("Vars.lootsack = Where treasure is stored")
echo("Vars.lootsack is set to " .. tostring(Vars.lootsack))
echo("You can change this by typing -- ;vars set lootsack=container")
echo("")
echo("Vars.keepsack = Where special drops are stored")
echo("Vars.keepsack is set to " .. tostring(Vars.keepsack))
echo("You can change this by typing -- ;vars set keepsack=container")
echo("")
echo("Bloodscrip will be automatically redeemed into your TICKET BALANCE.")
echo("")
echo(";unpause dr_sewers if you are satisfied with this setup.")

-- Pause until the user runs ;unpause dr_sewers
Script.pause("dr_sewers")
pause(0.001)

-- ── Per-run state ──────────────────────────────────────────────────────────────

local grand_total  = 0
local run_total    = 0
local run_start    = 0
local knocks_left  = 10

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function stand_up()
    if not standing() then
        fput("stance offensive")
        fput("stand")
    end
end

local function fmt_time(elapsed_secs)
    local m = math.floor(elapsed_secs / 60)
    local s = math.floor(elapsed_secs % 60)
    return string.format("%02d:%02d", m, s)
end

local function lootsack()
    return Vars.lootsack or "pack"
end

local function keepsack()
    return Vars.keepsack or lootsack()
end

-- Stow item in right or left hand by game-object ID.
-- Returns false (and pauses) if the container is full.
local function stow_hand(hand_obj, bag)
    if not hand_obj then return true end
    local result = dothistimeout(
        "put #" .. hand_obj.id .. " in my " .. bag, 5,
        "You put", "won't fit in the")
    if result and result:match("won't fit in the") then
        echo("Your container is full, maybe you should unload!?!?")
        echo("Figure it out, and ;unpause dr_sewers when you fix yourself.")
        Script.pause("dr_sewers")
        pause(0.001)
        return false
    end
    return true
end

-- ── Enter sewers ──────────────────────────────────────────────────────────────

local function enter_sewers()
    if percentencumbrance() > 2 then
        -- > 2 ordinal (0-5) ≈ Heavy or worse ≈ over 50% Lich5 scale
        echo("You're carrying too much stuff, lighten up!")
        echo("You're carrying too much stuff, lighten up!")
        echo("You're carrying too much stuff, lighten up!")
        echo("You're carrying too much stuff, lighten up!")
        echo("You're carrying too much stuff, lighten up!")
        Script.pause("dr_sewers")
        pause(0.001)
    end

    local result = dothistimeout("go grate", 5,
        "You need to redeem a stamped voucher or booklet to get inside the sewers.",
        "The tunnel sweeper accepts your stamped voucher and says,")

    if result and result:match("The tunnel sweeper accepts") then
        stand_up()
        move("up")
        move("up")
        move("out")
        run_start   = os.time()
        run_total   = 0
        knocks_left = 10
    elseif result and result:match("You need to redeem") then
        echo("Out of booklets!")
        Script.exit()
    else
        echo("Unexpected result at sewer grate — pausing.")
        Script.pause("dr_sewers")
        pause(0.001)
    end
end

-- ── Search sewers ─────────────────────────────────────────────────────────────

local function search_sewers()
    while true do
        -- Bail if stunned
        if stunned() then break end

        -- Bail if we've drifted into the Cesspool
        if Room.title:match("Cesspool") then break end

        -- Hands-full check
        if GameObj.right_hand() and GameObj.left_hand() then
            echo("Your hands are full, why are your hands full?!?!?")
            echo("Figure it out, and ;unpause dr_sewers when you fix yourself.")
            Script.pause("dr_sewers")
            pause(0.001)
        end

        local result = dothistimeout("search", 5,
            "You notice .* who is quite obviously attempting to remain hidden.",
            "Thick beads of phosphorescent slime dribble",
            "You search around and find %d+ bloodscrip, which you pocket!",
            "You search around and find %d+ bonus bloodscrip, which you pocket!",
            "You search around and find a cache of [%d,]+ bloodscrip",
            "You search around and find a .* crystal!",
            "You search around and find a flat etched stone!",
            "You search around and find a shimmering indigo orb!",
            "You search around the area and find .* rat!",
            "You search around and find an odd gem!",
            "You search around and find .*!",
            "You've recently searched",
            "As you begin to search the area, a wave of sewage",
            "You search around the area and find a small rat, but it scurries off",
            "You don't find anything of interest here.")

        if not result then break end

        -- ── Hidden person ────────────────────────────────────────────────────
        if result:match("You notice .* who is quite obviously attempting to remain hidden") then
            echo("Something went wrong!")

        -- ── Phosphorescent slime dribble → walk to random exit ───────────────
        elseif result:match("Thick beads of phosphorescent slime dribble") then
            fput("look")
            waitrt()
            walk()

        -- ── Regular bloodscrip ───────────────────────────────────────────────
        elseif result:match("You search around and find %d+ bloodscrip, which you pocket") then
            local scrip = tonumber(result:match("find (%d+) bloodscrip"))
            if scrip then
                knocks_left = knocks_left - 1
                run_total   = run_total + scrip
                stream_window("Found " .. scrip .. " bloodscrip. (" .. knocks_left .. ")", "loot")
            end
            waitrt()

        -- ── Bonus bloodscrip (does NOT decrement knocks_left) ────────────────
        elseif result:match("You search around and find %d+ bonus bloodscrip, which you pocket") then
            local scrip = tonumber(result:match("find (%d+) bonus bloodscrip"))
            if scrip then
                run_total = run_total + scrip
                stream_window("Found " .. scrip .. " bonus bloodscrip. (" .. knocks_left .. ")", "loot")
            end
            waitrt()

        -- ── Cache of bloodscrip ──────────────────────────────────────────────
        elseif result:match("You search around and find a cache of") then
            knocks_left = knocks_left - 1
            local raw   = result:match("cache of ([%d,]+) bloodscrip")
            if raw then
                local amount = tonumber(raw:gsub(",", "")) or 0
                run_total = run_total + amount
                stream_window("Found a cache of bloodscrip worth " .. raw .. "! (" .. knocks_left .. ")", "loot")
            end
            echo("* Congrats!!  You won a cache of bloodscrip!")
            echo("* Congrats!!  You won a cache of bloodscrip!")
            echo("* Congrats!!  You won a cache of bloodscrip!")
            echo("* Congrats!!  You won a cache of bloodscrip!")
            echo("* Congrats!!  You won a cache of bloodscrip!")
            waitrt()

        -- ── Crystal (MoonShard pendant bloodrune) ────────────────────────────
        elseif result:match("You search around and find a .* crystal!") then
            stream_window("Found a crystal for the moonshard pendant.", "loot")
            echo("* Congrats!!  You won a potential bloodrune!")
            echo("* You can read the crystal (once) or look at it to see letters/symbols!")
            echo("* You can then go to the following link to see which one you've won.")
            echo("* https://gswiki.play.net/MoonShard_pendant *")
            echo("* Congrats!!  You won a potential bloodrune!")
            waitrt()
            fput("put my stone in my " .. lootsack())

        -- ── Flat etched stone (MoonShard pendant bloodrune) ──────────────────
        elseif result:match("You search around and find a flat etched stone!") then
            stream_window("Found a stone for the moonshard pendant.", "loot")
            echo("* Congrats!!  You won a potential bloodrune!")
            echo("* You can read the stone (once) or look at it to see letters/symbols!")
            echo("* You can then go to the following link to see which one you've won.")
            echo("* https://gswiki.play.net/MoonShard_pendant *")
            echo("* Congrats!!  You won a potential bloodrune!")
            waitrt()
            fput("put my stone in my " .. lootsack())

        -- ── Shimmering indigo orb (3x RPA) ───────────────────────────────────
        elseif result:match("You search around and find a shimmering indigo orb!") then
            stream_window("Found a 3x RPA orb!", "loot")
            waitrt()
            fput("put my orb in my " .. keepsack())

        -- ── Rat ──────────────────────────────────────────────────────────────
        elseif result:match("You search around the area and find .* rat!") then
            stream_window("Found a rat!", "loot")
            waitrt()
            local rh = GameObj.right_hand()
            if rh then
                stow_hand(rh, lootsack())
            end

        -- ── Odd gem (WPS Smithy invitation) ──────────────────────────────────
        elseif result:match("You search around and find an odd gem!") then
            stream_window("Found a WPS smithy invite!", "loot")
            echo("* Congrats!!  You found an invitation to the WPS Smithy!")
            waitrt()

        -- ── Generic find — classify by noun then stow ────────────────────────
        elseif result:match("You search around and find .*!") then
            waitrt()
            local rh   = GameObj.right_hand()
            local lh   = GameObj.left_hand()
            local hand = rh or lh
            local noun = hand and hand.noun

            if noun == "rod" then
                stream_window("Rare Find: Found a slender wood rod!", "loot")
                echo("* Congrats!!  You won a slender wooden rod for the major Bag of Holding!")
                echo("* This can be sold to the ringleader for 100 bloodscrip!")
                fput("put my rod in my " .. keepsack())
                waitrt()
            elseif noun == "swatch" then
                stream_window("Rare Find: Found a swatch of material!", "loot")
                echo("* Congrats!!  You won a swatch of material for the major Bag of Holding!")
                fput("put my swatch in my " .. keepsack())
                waitrt()
            elseif noun == "thread" then
                stream_window("Rare Find: Found a strand of veniom thread!", "loot")
                echo("* Congrats!!  You won a strand of veniom thread for the major Bag of Holding!")
                fput("put my thread in my " .. keepsack())
                waitrt()
            elseif noun == "dust" then
                stream_window("Rare Find: Found a handful of sparkling dust!", "loot")
                echo("* Congrats!!  You won a handful of sparkling dust for the major Bag of Holding!")
                fput("put my dust in my " .. keepsack())
                waitrt()
            elseif rh then
                stream_window("Found " .. (rh.name or rh.noun or "item") .. "!", "loot")
                stow_hand(rh, lootsack())
            elseif lh then
                stream_window("Found " .. (lh.name or lh.noun or "item") .. "!", "loot")
                stow_hand(lh, lootsack())
            end

        -- ── Recently searched / wave of sewage / rat scurried → walk ─────────
        elseif result:match("You've recently searched")
            or result:match("As you begin to search the area, a wave of sewage")
            or result:match("You search around the area and find a small rat, but it scurries off") then
            waitrt()
            fput("look")
            walk()

        -- ── Nothing here → done with this section ────────────────────────────
        elseif result:match("You don't find anything of interest here") then
            break
        end
    end
end

-- ── Cesspool check ────────────────────────────────────────────────────────────

local function cesspool_check()
    if Room.title:match("Cesspool") then
        stream_window("Total Found: " .. run_total .. " bloodscrip.", "loot")
        grand_total = grand_total + run_total
        stream_window("Grand Total: " .. grand_total .. " bloodscrip.", "loot")
        local elapsed = os.difftime(os.time(), run_start)
        stream_window("Total Time: " .. fmt_time(elapsed) .. "!", "loot")
    elseif Room.title:match("Bloodriven Village, Sewer") then
        waitrt()
        walk()
    end
end

-- ── Main loop ─────────────────────────────────────────────────────────────────

if Room.title:match("Bloodriven Village, Sewer") then
    -- Already inside; start timing this run
    run_start = os.time()
else
    stream_window("Walking to the Bloodriven Village, Sewer Grate.", "familiar")
    Script.run("go2", "u8214001")
    while running("go2") do pause(0.5) end
    enter_sewers()
end

while true do
    if Room.title:match("Cesspool") then
        stream_window("Walking to the Bloodriven Village, Sewer Grate.", "familiar")
        Script.run("go2", "u8214001")
        while running("go2") do pause(0.5) end
    elseif Room.title:match("Sewer Grate") then
        stream_window("Entering the sewers!", "familiar")
        enter_sewers()
    else
        search_sewers()
        waitrt()
        cesspool_check()
    end
end
