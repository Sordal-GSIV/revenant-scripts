--- @revenant-script
--- name: knackstone
--- version: 1.0.0
--- author: elanthia-online
--- original-authors: elanthia-online, dr-scripts community contributors
--- game: dr
--- description: Use the knackstone to vote for the next DragonRealms boon.
---              Supports both worn and container storage modes.
---              Preferences are configured via knackstone_preferences in settings.
---              Defaults to voting for highest-value economy/XP boons first.
--- tags: boon, voting, knackstone, utility
--- source: https://elanthipedia.play.net/Lich_script_development#knackstone
--- @lic-certified: complete 2026-03-18
---
--- Conversion notes vs Lich5:
---   * Lich::Util.issue_command -> local issue_command using put + get_noblock polling.
---   * DRCI.in_hands?/remove_item?/wear_item?/put_away_item? -> DRCI equivalents (no ?).
---   * DRCI.get_item_if_not_held?(item, container) -> DRCI.get_item(item, container)
---     (Lua version does not accept container arg in get_item_if_not_held).
---   * DRC.left_hand/right_hand properties -> DRC.left_hand()/right_hand() functions.
---   * hidden?/invisible? -> hidden()/invisible() globals.
---   * get_settings -> get_settings() call.

-- Ensure dependency globals are available
if not get_settings then
    echo("knackstone: dependency must be running. Start it with ;dependency")
    return
end

local settings = get_settings()

-- Settings
local KNACKSTONE = settings.knackstone_noun      or "knackstone"
local CONTAINER  = settings.knackstone_container or "watery portal"
local WORN       = settings.knackstone_worn      or false
local PREFS      = settings.knackstone_preferences
local DEBUG      = settings.knackstone_debug     or false

-- Default voting preferences (ordered by priority, highest first)
local DEFAULT_PREFERENCES = {
    "bonus gem value from creatures",
    "bonus creature swarm activity",
    "bonus coins dropped from creatures",
    "bonus REXP value",
    "bonus experience",
    "bonus scroll drop chance",
    "bank fee removal",
    "bonus crafting experience",
    "bonus work order payouts",
    "bonus item drop chance",
    "bonus crafting prestige",
    "bonus to treasure map drop chance",
}

if not PREFS then
    PREFS = DEFAULT_PREFERENCES
end

-- Compiled regex patterns (reused across calls)
local BONUS_OPTIONS_RE = Regex.new("As best you can tell, it could be (.+), (.+), or (.+)\\.\\s*")
local ALREADY_USED_RE  = Regex.new("You have already cast your will to influence this cycle's future boon options")
local CONFIRMATION_RE  = Regex.new("repeat the command within 15 seconds")

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function dbg(msg)
    if DEBUG then echo("[knackstone] " .. msg) end
end

--- Send a command and collect game response lines.
--- Mirrors Lich5's Lich::Util.issue_command behavior:
--- sends cmd, waits for start_pat match, then collects lines until end_pat
--- matches (inclusive) or the line stream goes idle.
--- @param cmd string  Command to send to the game
--- @param start_pat string  PCRE regex — begin collecting from this line
--- @param end_pat string|nil  PCRE regex — stop collecting at this line (nil = idle timeout)
--- @param timeout number|nil  Total timeout in seconds (default 10)
--- @return table  Array of collected lines starting from the start_pat line
local function issue_command(cmd, start_pat, end_pat, timeout)
    local lines = {}
    put(cmd)
    local deadline = os.time() + (timeout or 10)

    -- Phase 1: wait for start_pat
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            if Regex.test(start_pat, line) then
                lines[#lines + 1] = line
                if end_pat and Regex.test(end_pat, line) then
                    return lines
                end
                break
            end
        else
            pause(0.05)
        end
    end

    if #lines == 0 then return lines end  -- timed out before start_pat

    -- Phase 2: collect until end_pat or line stream goes idle (1s quiet = done)
    local idle_deadline = os.time() + 1
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            lines[#lines + 1] = line
            idle_deadline = os.time() + 1  -- reset idle timer on activity
            if end_pat and Regex.test(end_pat, line) then break end
        else
            if os.time() >= idle_deadline then break end
            pause(0.05)
        end
    end

    return lines
end

--- Return the 1-based index of opt in PREFS, or math.huge if not found.
local function pref_index(opt)
    for i, p in ipairs(PREFS) do
        if p == opt then return i end
    end
    return math.huge
end

--- Pick the best option from a list, based on PREFS order (lowest index wins).
local function find_best_option(options)
    dbg("Available options: " .. table.concat(options, ", "))
    dbg("Sorting by preferences: " .. table.concat(PREFS, ", "))
    local best = options[1]
    for i = 2, #options do
        if pref_index(options[i]) < pref_index(best) then
            best = options[i]
        end
    end
    echo("Chosen option: " .. best)
    return best
end

--- Send a whisper vote command; returns true if confirmation is required.
local function whisper_command(cmd)
    local response = issue_command(
        cmd,
        "You whisper the fate",
        "Roundtime|You have cast your lot to fate",
        10
    )
    for _, line in ipairs(response) do
        if CONFIRMATION_RE:test(line) then return true end
    end
    return false
end

--- Vote for the chosen option by its 1-indexed position in the options table.
local function vote_for(choice, options)
    local choice_number = 1
    for i, opt in ipairs(options) do
        if opt == choice then choice_number = i; break end
    end
    local cmd = "WHISPER MY " .. KNACKSTONE .. " " .. choice_number
    dbg("Executing: " .. cmd)
    local needs_confirm = whisper_command(cmd)
    if needs_confirm then whisper_command(cmd) end
end

--- Rub the knackstone, parse the three boon options, and cast the vote.
local function use_knackstone()
    local response = issue_command(
        "rub my " .. KNACKSTONE,
        "As you rub",
        nil,
        10
    )

    -- Check if already voted this cycle
    for _, line in ipairs(response) do
        if ALREADY_USED_RE:test(line) then
            echo("Knackstone has already been used for this cycle.")
            return
        end
    end

    -- Find the options line
    local options_line
    for _, line in ipairs(response) do
        if line:find("As best you can tell") then
            options_line = line
            break
        end
    end

    if not options_line then
        echo("Could not determine knackstone options from response.")
        return
    end

    local caps = BONUS_OPTIONS_RE:captures(options_line)
    if not caps or not caps[1] then
        echo("Could not parse knackstone options from: " .. options_line)
        return
    end

    local options = { caps[1], caps[2], caps[3] }
    local choice = find_best_option(options)
    vote_for(choice, options)
end

--- Returns true if both hands are occupied.
local function hands_full()
    return DRC.left_hand() ~= nil and DRC.right_hand() ~= nil
end

--- Remove worn knackstone into an empty hand; returns true on success.
local function remove_worn_knackstone()
    if DRCI.in_hands(KNACKSTONE) then return true end
    if hands_full() then
        DRC.message("Hands full, cannot remove knackstone.")
        return false
    end
    if not DRCI.remove_item(KNACKSTONE) then
        DRC.message("Could not remove knackstone. Something is wrong!")
        return false
    end
    return true
end

--- Re-wear the knackstone after use.
local function wear_knackstone()
    if not DRCI.wear_item(KNACKSTONE) then
        DRC.message("Could not wear knackstone. Something is wrong!")
    end
end

--- Return the knackstone to its container.
local function put_away_knackstone()
    if not DRCI.put_away_item(KNACKSTONE, CONTAINER) then
        DRC.message("Could not put away knackstone. Something is wrong!")
    end
end

--- Retrieve the knackstone from its container into hand; returns true on success.
local function ensure_knackstone_in_hand()
    if DRCI.in_hands(KNACKSTONE) then return true end
    if hands_full() then
        DRC.message("Hands full, cannot get knackstone.")
        return false
    end
    return DRCI.get_item(KNACKSTONE, CONTAINER)
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

-- Cannot use while hidden or invisible
if hidden() or invisible() then
    echo("Cannot use knackstone while hidden or invisible.")
    return
end

if WORN then
    if not remove_worn_knackstone() then return end
    use_knackstone()
    wear_knackstone()
else
    if not ensure_knackstone_in_hand() then return end
    use_knackstone()
    put_away_knackstone()
end
