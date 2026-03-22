--- Bigshot Recovery — rest cycle, cast signs, spell-ups, loot delegation
-- Port of rest(), cast_signs, hunting_prep, resting_prep, loot, display_watch
-- from bigshot.lic v5.12.1

local navigation = require("navigation")
local state_mod = require("state")
local commands = require("commands")
local config = require("config")

local M = {}

-- Tracking for hunt timing
local start_time = 0
local stored_times = {}
local birth_time = os.time()
local rest_prep_done = false

---------------------------------------------------------------------------
-- Start/Stop Watch — hunt timing
---------------------------------------------------------------------------

function M.start_watch()
    start_time = os.time()
end

function M.stop_watch()
    if start_time > 0 then
        local elapsed = os.time() - start_time
        stored_times[#stored_times + 1] = elapsed
        start_time = 0
    end
end

function M.display_watch()
    if #stored_times == 0 then
        respond("[bigshot] No hunt times recorded yet")
        return
    end

    local last = stored_times[#stored_times]
    local total = 0
    for _, t in ipairs(stored_times) do total = total + t end
    local avg = math.floor(total / #stored_times)

    local running = os.time() - birth_time
    local h = math.floor(running / 3600)
    local m = math.floor((running % 3600) / 60)
    local s = running % 60

    respond(string.format("[bigshot] Last hunt: %ds | Average: %ds | Hunts: %d | Running: %dh %dm %ds",
        last, avg, #stored_times, h, m, s))
end

---------------------------------------------------------------------------
-- Cast Signs — society signs, sigils, symbols, barkskin, etc.
---------------------------------------------------------------------------

function M.cast_signs(bstate, single_cast)
    local signs = bstate.signs
    if not signs or type(signs) ~= "table" or #signs == 0 then return end

    for _, sign_str in ipairs(signs) do
        sign_str = sign_str:match("^%s*(.-)%s*$")
        if sign_str ~= "" then
            local num = tonumber(sign_str)

            if num then
                -- Numeric spell/sign/sigil
                local spell = Spell[num]
                if spell and spell.known and not spell.active then
                    -- Check affordability
                    if spell.affordable then
                        waitrt()
                        waitcastrt()
                        -- Signs use specific verbs
                        if num >= 9900 and num <= 9920 then
                            -- CoL Signs
                            fput("sign of " .. (spell.name or ""))
                        elseif num >= 9700 and num <= 9720 then
                            -- GoS Sigils
                            fput("sigil of " .. (spell.name or ""):gsub("Sigil of ", ""))
                        elseif num >= 9800 and num <= 9830 then
                            -- Voln Symbols
                            fput("symbol of " .. (spell.name or ""):gsub("Symbol of ", ""))
                        elseif num >= 9600 and num <= 9620 then
                            -- Shadow abilities
                            if num == 9603 then fput("shadow mastery")
                            elseif num == 9605 then fput("surge of strength") end
                        elseif num == 605 then
                            -- Barkskin
                            fput("incant 605")
                        elseif num == 115 then
                            -- Fasthr's Reward
                            fput("incant 115")
                        elseif num == 515 then
                            -- Rapid Fire (if not already active)
                            if not Effects.Buffs.active("Rapid Fire") then
                                fput("rapidfire")
                            end
                        elseif num == 122420 then
                            -- Seanette's Shout
                            fput("seanettes")
                        else
                            fput("incant " .. num)
                        end
                        pause(0.5)
                        waitrt()
                        waitcastrt()
                    end
                end

                -- Break early in single cast mode
                if single_cast then return end
            else
                -- Non-numeric: treat as a command
                fput(sign_str)
                pause(0.5)
            end
        end
    end
end

--- Cast spell 902 (enchant weapon)
function M.cast902(bstate)
    if not Spell[902] or not Spell[902].known then return end
    if Spell[902].active then return end
    waitrt()
    waitcastrt()
    commands.change_stance("defensive", bstate)
    fput("incant 902")
    pause(1)
    waitrt()
    waitcastrt()
    commands.change_stance(bstate.hunting_stance, bstate)
end

--- Cast spell 411 (enchant weapon)
function M.cast411(bstate)
    if not Spell[411] or not Spell[411].known then return end
    if Spell[411].active then return end
    waitrt()
    waitcastrt()
    commands.change_stance("defensive", bstate)
    fput("incant 411")
    pause(1)
    waitrt()
    waitcastrt()
    commands.change_stance(bstate.hunting_stance, bstate)
end

---------------------------------------------------------------------------
-- Wracking / Power / Mana — society mana recovery
---------------------------------------------------------------------------

function M.wrack(bstate)
    if not bstate.use_wracking then return end

    local spirit = Char.spirit or 0
    local threshold = tonumber(bstate.wracking_spirit) or 0
    if threshold <= 0 then return end
    if spirit <= threshold then return end

    -- Determine which wracking to use based on profession/society
    -- CoL: Sign of Wracking (9915)
    if Spell[9915] and Spell[9915].known and Spell[9915].affordable then
        -- Check if other CoL signs are not draining spirit
        fput("sign of wracking")
        pause(1)
        return
    end

    -- GoS: Sigil of Power (9718)
    if Spell[9718] and Spell[9718].known and Spell[9718].affordable then
        fput("sigil of power")
        pause(1)
        return
    end

    -- Voln: Symbol of Mana (9818)
    if Spell[9818] and Spell[9818].known and Spell[9818].affordable then
        fput("symbol of mana")
        pause(1)
        return
    end
end

---------------------------------------------------------------------------
-- Hunting Prep / Resting Prep — run user commands
---------------------------------------------------------------------------

function M.hunting_prep(bstate)
    M._run_prep_commands(bstate.hunting_prep_commands, bstate)
end

function M.resting_prep(bstate)
    M._run_prep_commands(bstate.resting_commands, bstate)
end

function M._run_prep_commands(cmds, bstate)
    if not cmds or type(cmds) ~= "table" then return end
    for _, cmd_str in ipairs(cmds) do
        cmd_str = cmd_str:match("^%s*(.-)%s*$")
        if cmd_str ~= "" then
            -- Check if it's a script command
            local script_name = cmd_str:match("^script%s+(.+)")
            if script_name then
                local parts = {}
                for word in script_name:gmatch("%S+") do parts[#parts + 1] = word end
                local name = table.remove(parts, 1)
                local args = table.concat(parts, " ")
                Script.run(name, args)
                local timeout = 60
                local waited = 0
                while Script.running(name) and waited < timeout do
                    pause(0.5)
                    waited = waited + 0.5
                end
            else
                fput(cmd_str)
                pause(0.5)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Hunting Scripts / Resting Scripts — start/stop external scripts
---------------------------------------------------------------------------

function M.start_hunting_scripts(bstate)
    if not bstate.hunting_scripts or type(bstate.hunting_scripts) ~= "table" then return end
    for _, entry in ipairs(bstate.hunting_scripts) do
        entry = entry:match("^%s*(.-)%s*$")
        if entry ~= "" then
            local parts = {}
            for word in entry:gmatch("%S+") do parts[#parts + 1] = word end
            local name = table.remove(parts, 1)
            local args = table.concat(parts, " ")
            if name and not Script.running(name) then
                Script.run(name, args)
                pause(0.3)
            end
        end
    end
end

function M.stop_hunting_scripts(bstate)
    if not bstate.hunting_scripts or type(bstate.hunting_scripts) ~= "table" then return end
    for _, entry in ipairs(bstate.hunting_scripts) do
        local name = entry:match("^(%S+)")
        if name and Script.running(name) then
            Script.kill(name)
            pause(0.1)
        end
    end
end

function M.start_resting_scripts(bstate)
    if not bstate.resting_scripts or type(bstate.resting_scripts) ~= "table" then return end
    for _, entry in ipairs(bstate.resting_scripts) do
        entry = entry:match("^%s*(.-)%s*$")
        if entry ~= "" then
            local parts = {}
            for word in entry:gmatch("%S+") do parts[#parts + 1] = word end
            local name = table.remove(parts, 1)
            local args = table.concat(parts, " ")
            if name and not Script.running(name) then
                Script.run(name, args)
                pause(0.3)
            end
        end
    end
end

function M.stop_resting_scripts(bstate)
    if not bstate.resting_scripts or type(bstate.resting_scripts) ~= "table" then return end
    for _, entry in ipairs(bstate.resting_scripts) do
        local name = entry:match("^(%S+)")
        if name and Script.running(name) then
            Script.kill(name)
            pause(0.1)
        end
    end
end

---------------------------------------------------------------------------
-- Loot — delegate to loot script
---------------------------------------------------------------------------

function M.loot(bstate)
    local loot_script = bstate.loot_script
    if not loot_script or loot_script == "" then
        loot_script = "eloot"
    end

    -- Change to defensive stance before looting if configured
    if bstate.loot_stance then
        commands.change_stance("defensive", bstate)
    end

    -- Run loot script
    if Script.exists(loot_script) then
        Script.run(loot_script)
        local timeout = 30
        local waited = 0
        while Script.running(loot_script) and waited < timeout do
            pause(0.5)
            waited = waited + 0.5
        end
    else
        -- Fallback to basic loot command
        fput("loot room")
        pause(1)
    end

    -- Restore hunting stance
    if bstate.loot_stance then
        commands.change_stance(bstate.hunting_stance, bstate)
    end

    -- Check for box in hand (force rest if configured)
    if bstate.box_in_hand then
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (rh and rh.type and rh.type:find("box")) or (lh and lh.type and lh.type:find("box")) then
            bstate._should_rest = true
            bstate._rest_reason = "box stuck in hand after looting"
        end
    end
end

function M.looting_watch(script_name, bstate)
    local timeout = 30
    local waited = 0
    while Script.running(script_name) and waited < timeout do
        pause(0.5)
        waited = waited + 0.5
    end
end

---------------------------------------------------------------------------
-- LTE Boost — long-term experience boost usage
---------------------------------------------------------------------------

function M.use_lte_boost(bstate)
    local max_boosts = tonumber(bstate.lte_boost) or 0
    if max_boosts <= 0 then return end
    if (bstate._lte_boost_counter or 0) >= max_boosts then return end

    fput("boost longterm")
    pause(1)
    bstate._lte_boost_counter = (bstate._lte_boost_counter or 0) + 1
end

---------------------------------------------------------------------------
-- Display items needing blessing
---------------------------------------------------------------------------

function M.display_bless_items(bstate)
    local bless_list = commands.get_bless_list()
    if bless_list and #bless_list > 0 then
        respond("[bigshot] Items needing blessing:")
        for _, id in ipairs(bless_list) do
            respond("  Item ID: " .. tostring(id))
        end
    end
end

---------------------------------------------------------------------------
-- Wait for recovery (rest until thresholds met)
---------------------------------------------------------------------------

function M.wait_for_recovery(bstate)
    respond("[bigshot] Waiting for recovery...")
    local rest_interval = 60  -- seconds between checks
    local max_wait = 3600     -- 1 hour max

    local waited = 0
    while waited < max_wait do
        if state_mod.ready_to_hunt(bstate) then
            respond("[bigshot] Recovery complete")
            return true
        end
        M.display_watch()
        pause(rest_interval)
        waited = waited + rest_interval
    end

    respond("[bigshot] Recovery timeout — forcing hunt")
    return false
end

---------------------------------------------------------------------------
-- Full rest cycle
---------------------------------------------------------------------------

function M.rest(bstate)
    respond("[bigshot] Resting...")

    -- Reset rest tracking
    bstate._should_rest = false
    bstate._rest_reason = nil
    bstate._overkill_counter = 0
    bstate._lte_boost_counter = 0
    bstate._boon_cache = {}
    commands.reset_rest()

    -- Stop hunting scripts
    M.stop_hunting_scripts(bstate)
    M.stop_watch()

    -- Check bounty completion
    if bstate._bounty_mode and state_mod.bounty_check then
        local complete = state_mod.bounty_check(bstate)
        if complete then
            respond("[bigshot] Bounty complete!")
            return "bounty_done"
        end
    end

    -- Disable autosneak
    if bstate._sneaky_mode then
        fput("movement autosneak off")
        bstate._sneaky_mode = false
    end

    -- Fog return home
    navigation.fog_return(bstate)
    pause(0.5)

    -- Travel return waypoints
    local waypoints = bstate.return_waypoint_ids
    if waypoints and type(waypoints) == "table" and #waypoints > 0 then
        navigation.travel_waypoints(waypoints)
    end

    -- Go to resting room
    local rest_id = tonumber(bstate.resting_room_id)
    if rest_id and rest_id > 0 then
        navigation.goto_room_loop(rest_id)
    end

    -- Check for escape rooms (swallowed, etc.)
    navigation.escape_rooms(bstate)

    -- Display blessing needs
    M.display_bless_items(bstate)

    -- Run resting prep commands
    M.resting_prep(bstate)

    -- Start resting scripts
    M.start_resting_scripts(bstate)

    -- Display hunt timing
    M.display_watch()

    return "rested"
end

---------------------------------------------------------------------------
-- Pre-hunt setup
---------------------------------------------------------------------------

function M.pre_hunt(bstate)
    -- Run hunting prep commands
    M.hunting_prep(bstate)

    -- Travel to rally points first
    local rally_ids = bstate.rallypoint_room_ids
    if rally_ids and type(rally_ids) == "table" and #rally_ids > 0 then
        navigation.travel_waypoints(rally_ids)
    end

    -- Cast signs at rally point
    M.cast_signs(bstate)

    -- Check 902/411 recasts
    if bstate._cast902 then
        M.cast902(bstate)
        bstate._cast902 = false
    end
    if bstate._cast411 then
        M.cast411(bstate)
        bstate._cast411 = false
    end

    -- Start hunting scripts
    M.start_hunting_scripts(bstate)

    -- Go to hunting room
    local hunt_id = tonumber(bstate.hunting_room_id)
    if hunt_id and hunt_id > 0 then
        navigation.goto_room_loop(hunt_id)
    end

    -- Enable sneaky mode if configured
    if bstate.sneaky_sneaky then
        fput("movement autosneak on")
        bstate._sneaky_mode = true
    end

    -- Reset combat state
    commands.reset_combat_state()
end

---------------------------------------------------------------------------
-- Prepare for movement (transition between hunt and rest)
---------------------------------------------------------------------------

function M.prepare_for_movement(bstate)
    -- Reset combat variables
    state_mod.reset_variables(bstate, true)

    -- Change to wander stance
    local wander_stance = bstate.wander_stance
    if wander_stance and wander_stance ~= "" then
        commands.change_stance(wander_stance, bstate)
    else
        commands.change_stance("defensive", bstate)
    end
end

return M
