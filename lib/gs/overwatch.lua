--- Hidden creature tracking.
--- Watches for hide/reveal/silent-strike patterns via DownstreamHook.

local M = {}
local enabled = false
local room_with_hiders_id = nil

local HIDE_PATTERNS = {
    "slips into hiding",
    "fades into the shadows",
    "disappears into the shadows",
    "blends with the shadows",
    "slips into the shadows",
    "quickly disappears from view",
    "figure quickly disappears",
    "Something stirs in the shadows",
    "slips out of sight",
    "vanishes into the shadows",
    "darts into the shadows",
    "fades from sight",
    "dissolves into the shadows",
    "moves too swiftly to follow",
    "melds into the shadows",
}

local REVEAL_PATTERNS = {
    "is revealed from hiding",
    "is forced from hiding",
    "comes out of hiding",
    "leaps out of hiding",
    "suddenly leaps from hiding",
    "shadows melt away to reveal",
    "You discover",
    "You reveal",
    "lunges from the shadows",
    "emerges from hiding",
    "springs from hiding",
    "pounces from hiding",
    "flies out of the shadows",
    "bursts from hiding",
    "charges out of hiding",
    "stumbles from hiding",
    "rushes from the shadows",
    "darts from the shadows",
    "is dragged from hiding",
    "is flushed from hiding",
    "snaps out of hiding",
}

local SILENT_STRIKE_PATTERNS = {
    "leaps from hiding to attempt",
    "leaps out and swings",
    "leaps from the shadows",
    "darts out of hiding",
    "lunges from hiding",
    "springs from concealment",
}

local function check_patterns(line, patterns)
    for _, pattern in ipairs(patterns) do
        if string.find(line, pattern, 1, true) then
            return true
        end
    end
    return false
end

local function hook_fn(line)
    if check_patterns(line, HIDE_PATTERNS) then
        room_with_hiders_id = GameState.room_id
    elseif check_patterns(line, REVEAL_PATTERNS) then
        -- Creature revealed; don't clear room_with_hiders (may be more)
    elseif check_patterns(line, SILENT_STRIKE_PATTERNS) then
        -- Attack from hiding; creature may re-hide immediately
        room_with_hiders_id = GameState.room_id
    end
    return line
end

--- Register the downstream hook.
function M.enable()
    if enabled then return end
    DownstreamHook.add("__overwatch", hook_fn)
    enabled = true
end

--- Remove the downstream hook.
function M.disable()
    if not enabled then return end
    DownstreamHook.remove("__overwatch")
    enabled = false
end

--- True if the current room has known hiders.
function M.hiders()
    return room_with_hiders_id == GameState.room_id
end

--- Return the room ID with hiders, or nil.
function M.room_with_hiders()
    return room_with_hiders_id
end

--- Reset tracking state.
function M.clear()
    room_with_hiders_id = nil
end

return M
