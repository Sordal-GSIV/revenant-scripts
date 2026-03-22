--- @revenant-script
--- name: gemstone_tracker
--- version: 15.0.0
--- author: Dreaven (Tgo01)
--- game: gs
--- description: Track Ascension gemstone drops, kills, properties, and statistics with full GUI
--- tags: gems, tracking, loot, statistics, ascension, hinterwilds
--- @lic-certified: complete 2026-03-19
---
--- Full port of gemstone-tracker.lic v15 by Dreaven (Tgo01) to Revenant Lua.
---
--- Tracks kills on Ascension critters, detects gemstone finds, records
--- gemstone properties/rarities, computes find rate probabilities, and
--- provides historical statistics with a tabbed GUI window.
---
--- Supports multi-character groups where one "Captain" runs the script
--- and tracks stats for the entire group in real time.
---
--- Changelog (from Lich5):
---   v15  — Fixed bugs to prevent script crashing.
---   v11  — Fixed week-boundary gemstone detection.
---   v10  — Fixed rare crash bug.
---   v9   — Fixed 2nd/3rd gemstone kill tracking.
---   v5   — Added find rate probability calculations (1/1500 pity system).
---   v4   — Added window size settings tab.
---   v3   — Renamed "Leader" to "Captain", fixed group save bugs.
---   v2   — Fixed empty string bug in Group management.
---
--- Usage:
---   ;gemstone_tracker         - Start tracking (runs in background)
---   ;send show                - Open the tracker window
---
--- The script monitors game output for:
---   - "You search the <critter>." (your loot)
---   - "<Name> searches a <critter>." (group member loot)
---   - "** A glint of light catches your eye..." (gemstone found)
---   - Mugging messages (hasty search / riches)
---   - "Property:" / "Rarity:" lines when examining jewels
---
--- Contact: Dreaven in-game, Tgo01 on Player's Corner, dreaven. on Discord

hide_me()

local data = require("data")
local constants = require("constants")
local gui = require("gui")

---------------------------------------------------------------------------
-- Load data and initialize
---------------------------------------------------------------------------
data.load()

-- Ensure current character exists
data.ensure_character(GameState.name)
data.check_reset(GameState.name)

-- Create GUI window (hidden until ;send show)
gui.create_window()

echo("Gemstone Tracker running. Enter ;send show to open the window.")

---------------------------------------------------------------------------
-- Cleanup on exit
---------------------------------------------------------------------------
before_dying(function()
    data.save()
    gui.close()
end)

---------------------------------------------------------------------------
-- Timing: auto-save every 5 min, GUI refresh every ~1 sec (in main loop)
---------------------------------------------------------------------------
local SAVE_INTERVAL = 300  -- seconds
local last_save = os.time()
local last_refresh = os.time()

---------------------------------------------------------------------------
-- Ascension critter matching via Regex (handles full descriptive names)
---------------------------------------------------------------------------
local ascension_re = Regex.new(constants.ascension_pattern)

local function is_ascension_critter(critter_name)
    return ascension_re:test(critter_name)
end

---------------------------------------------------------------------------
-- Track state for mugging detection
---------------------------------------------------------------------------
local mugging_name = nil
local mugging_critter = nil

---------------------------------------------------------------------------
-- Main game line processing loop
---------------------------------------------------------------------------
while true do
    -- Periodic GUI refresh (~1 sec)
    local now = os.time()
    if now - last_refresh >= 1 then
        gui.refresh_display()
        last_refresh = now
    end

    -- Periodic auto-save (5 min) + reload for multi-character sync
    if now - last_save >= SAVE_INTERVAL then
        data.save()
        data.load()
        last_save = now
    end

    local line = get_noblock()
    if not line then
        pause(0.25)
        goto continue
    end

    local sline = line

    -- Process gemstone property info when examining a jewel
    gui.process_gem_info_line(sline)

    -------------------------------------------------------------------
    -- "You search the <critter>." — own loot
    -------------------------------------------------------------------
    local critter = sline:match("^You search the (.-)%.$")
    if critter then
        local name = GameState.name
        gui.state.current_looter = name
        gui.state.last_critter_looted = critter
        data.ensure_character(name)
        if is_ascension_critter(critter) then
            local gems_month = data.gems_found_this_month(name)
            local found_week = data.found_gem_this_week(name)
            if not found_week and gems_month < 3 then
                data.record_kill(name, critter)
            end
            gui.state.kills_this_hunt = gui.state.kills_this_hunt + 1
        end
        goto continue
    end

    -------------------------------------------------------------------
    -- "<Name> searches a/an <critter>." — group member loot
    -------------------------------------------------------------------
    local searcher, searched_critter = sline:match("^([a-zA-Z]+) searches an? (.-)%.$")
    if searcher then
        gui.state.current_looter = searcher
        if data.in_group(searcher) then
            data.ensure_character(searcher)
            gui.state.last_critter_looted = searched_critter
            if is_ascension_critter(searched_critter) then
                local gems_month = data.gems_found_this_month(searcher)
                local found_week = data.found_gem_this_week(searcher)
                if not found_week and gems_month < 3 then
                    data.record_kill(searcher, searched_critter)
                end
                gui.state.kills_this_hunt = gui.state.kills_this_hunt + 1
            end
        end
        goto continue
    end

    -------------------------------------------------------------------
    -- Gemstone found — your feet
    -------------------------------------------------------------------
    if sline:match("%*%* A glint of light catches your eye, and you notice .+ at your feet! %*%*") then
        local name = GameState.name
        local last_critter = gui.state.last_critter_looted or "Unknown"
        local date_key = data.record_gemstone(name, last_critter)
        gui.state.last_gemstone_found = date_key

        echo("##############################################################")
        echo("CONGRATULATIONS! " .. name .. " has found a jewel!")
        echo("Hold the jewel in either hand, open the window (;send show),")
        echo("select " .. name .. " from the dropdown, go to Current tab,")
        echo("and click 'Add Gemstone' to record its properties.")
        echo("##############################################################")

        gui.refresh_char_list()
        gui.refresh_display()
        goto continue
    end

    -------------------------------------------------------------------
    -- Gemstone found — someone else's feet
    -------------------------------------------------------------------
    local other_finder = sline:match("%*%* A glint of light catches your eye, and you notice .+ at ([a-zA-Z]+)'s feet! %*%*")
    if other_finder then
        if data.in_group(other_finder) then
            local last_critter = gui.state.last_critter_looted or "Unknown"
            local date_key = data.record_gemstone(other_finder, last_critter)
            gui.state.last_gemstone_found = date_key

            echo("##############################################################")
            echo("CONGRATULATIONS! " .. other_finder .. " has found a jewel!")
            echo("If " .. other_finder .. " is in your group, give the jewel to")
            echo("the Captain and click 'Add Gemstone' on the Current tab.")
            echo("##############################################################")

            gui.refresh_char_list()
            gui.refresh_display()
        end
        goto continue
    end

    -------------------------------------------------------------------
    -- Mugging — start tracking
    -------------------------------------------------------------------
    local mugger, mug_critter = sline:match("In the scuffle, (.-) roughly pats the (.-) down for hidden valuables!")
    if mugger then
        data.ensure_character(mugger)
        if data.in_group(mugger) and is_ascension_critter(mug_critter) then
            mugging_name = mugger
            mugging_critter = mug_critter
        end
        goto continue
    end

    -------------------------------------------------------------------
    -- Mugging — completion (group member)
    -------------------------------------------------------------------
    if sline:match("hasty search scatters the .+ riches") then
        if mugging_name and mugging_critter and data.in_group(mugging_name) then
            if sline:find(mugging_critter, 1, true) then
                local gems_month = data.gems_found_this_month(mugging_name)
                local found_week = data.found_gem_this_week(mugging_name)
                if not found_week and gems_month < 3 then
                    data.record_kill(mugging_name, mugging_critter)
                end
            end
        end
        mugging_name = nil
        mugging_critter = nil
        goto continue
    end

    -------------------------------------------------------------------
    -- Mugging — own character
    -- Ruby: /^Your hasty search scatters the ([\w\s]+?)(?='s|'|\b') riches to the floor!/
    -------------------------------------------------------------------
    local own_mug_critter = sline:match("^Your hasty search scatters the (.+) riches to the floor!")
    if own_mug_critter then
        -- Strip possessive suffix: "critter's" → "critter", "critter'" → "critter"
        own_mug_critter = own_mug_critter:gsub("'s%s*$", ""):gsub("'%s*$", "")
    end
    if own_mug_critter then
        local name = GameState.name
        data.ensure_character(name)
        if is_ascension_critter(own_mug_critter) then
            local gems_month = data.gems_found_this_month(name)
            local found_week = data.found_gem_this_week(name)
            if not found_week and gems_month < 3 then
                data.record_kill(name, own_mug_critter)
            end
        end
        goto continue
    end

    -------------------------------------------------------------------
    -- ;send show — open the window
    -------------------------------------------------------------------
    if sline == "show" then
        gui.show_window()
        goto continue
    end

    ::continue::
end
