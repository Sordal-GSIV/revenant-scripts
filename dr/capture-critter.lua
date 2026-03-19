--- @revenant-script
--- name: capture-critter
--- version: 1.0.0
--- author: khariz
--- original-authors: khariz, dr-scripts community contributors
--- game: dr
--- description: Participate in DR seasonal critter-capture events (Chris'Mas, Hollow Eve, Taffelberry Faire).
---              Walks capture event rooms, picks up event critters, and deposits them at the return surface.
--- tags: event, capture, seasonal, critter
--- source: https://elanthipedia.play.net/Lich_script_development#capture-critter
--- @lic-certified: complete 2026-03-18
---
--- Conversion notes vs Lich5:
---   * get_data("capture") loads data/dr/base-capture.json (converted from base-capture.yaml).
---   * Ruby !ruby/regexp YAML entries stored as "!pcre:<pattern>" strings in JSON;
---     detected at runtime and passed directly to Regex.new for PCRE matching.
---   * Regexp.union + word-boundary -> Regex.new with alternation and (?i) flag.
---   * DRRoom.room_objs now populated by lib/dr/parser.lua room-objs XML component parsing.
---   * DRCI.in_hand? -> DRCI.in_hand() (alias added to common_items.lua).
---   * OpenStruct-merged custom event data -> plain Lua table assignment.

-- Ensure dependency globals are available (provides get_settings, get_data, parse_args)
if not get_settings then
    echo("capture-critter: dependency must be running. Start it with ;dependency")
    return
end

local settings         = get_settings()
local capture_settings = settings.capture_critter_settings or {}
local dbg              = capture_settings.debug

local function dbg_echo(msg)
    if dbg then echo(msg) end
end

-- Load capture event data from data/dr/base-capture.json
local event_data = get_data("capture")
if type(event_data) ~= "table" or not next(event_data) then
    echo("capture-critter: failed to load base-capture.json — ensure data/dr/base-capture.json exists")
    return
end

-- Inject custom event if the player has configured one in their settings.
-- Mirrors Lich5: if capture_critter_settings.custom.room_list is non-empty,
-- add it as the "custom" event alongside the built-in events.
local custom_cfg = capture_settings.custom or {}
if type(custom_cfg.room_list) == "table" and #custom_cfg.room_list > 0 then
    event_data.custom = custom_cfg
end

-- Build a sorted list of valid event names for help/error messages
local function sorted_event_keys()
    local keys = {}
    for k in pairs(event_data) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

-- Parse arguments: one required positional arg — the event name
local arg_definitions = {
    {
        {
            name        = "event",
            regex       = "^%a[%w_]*$",
            optional    = false,
            description = "Name of event (" .. table.concat(sorted_event_keys(), ", ") .. ")",
        }
    }
}

local args = parse_args(arg_definitions)
if not args then return end

-- Register "critter-done" flag — fires on the "game over" broadcast
-- Each capture event sends a message like "Phew! All of the..." or "Whew! All of the..."
Flags.add("critter-done", "^[PW]hew!  All of the")

-- Look up the requested event
local event_info = event_data[args.event]
if not event_info then
    echo("'" .. args.event .. "' is not a valid event name. Valid events:\n\n  " ..
         table.concat(sorted_event_keys(), "\n  ") .. "\n")
    Flags.delete("critter-done")
    return
end

-- Build the critter-matching PCRE regex from the event's critter_names list.
-- Each name is either:
--   "!pcre:<pattern>" — a raw PCRE pattern (e.g., negative lookbehind for scarecrow)
--   "<word>"          — a plain literal; escaped and wrapped in word boundaries
local function build_critter_re(critter_names)
    local parts = {}
    for _, name in ipairs(critter_names or {}) do
        if type(name) == "string" then
            if name:sub(1, 6) == "!pcre:" then
                -- Raw PCRE pattern — include as-is in the alternation
                table.insert(parts, name:sub(7))
            else
                -- Escape PCRE metacharacters in the literal name, then wrap in \b...\b
                local escaped = name:gsub("([%.%+%*%?%[%]%^%$%(%)%|%{%}\\%-])", "\\%1")
                table.insert(parts, escaped)
            end
        end
    end
    if #parts == 0 then
        echo("capture-critter: no critter names defined for event '" .. args.event .. "'")
        return nil
    end
    -- Combine all alternates under a single word-bounded capture group, case-insensitive
    return Regex.new("(?i)\\b(" .. table.concat(parts, "|") .. ")\\b")
end

local critter_re = build_critter_re(event_info.critter_names)
if not critter_re then
    Flags.delete("critter-done")
    return
end

-- Clean up on exit
before_dying(function()
    Flags.delete("critter-done")
end)

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

--- Return the matched critter noun if obj_name is a capture target, else nil.
local function match_critter(obj_name)
    dbg_echo("match_critter(" .. tostring(obj_name) .. ")")
    local caps = critter_re:captures(tostring(obj_name))
    return caps and caps[1] or nil
end

--- Return the first critter noun visible in DRRoom.room_objs, or nil.
local function find_critter_in_room()
    local objs = DRRoom and DRRoom.room_objs or {}
    for _, obj in ipairs(objs) do
        local critter = match_critter(obj)
        if critter then return critter end
    end
    return nil
end

--- Dispose or stow an item based on whether it appears in the junk list.
--- Returns true if the item was handled as junk (disposed), false otherwise.
local function handle_item(item)
    if not item then return false end
    dbg_echo("handle_item(" .. item .. ")")
    local junk = capture_settings.junk or {}
    for _, junk_name in ipairs(junk) do
        if item == junk_name then
            dbg_echo(item .. " is junk")
            DRCI.dispose_trash(item, settings.worn_trashcan, settings.worn_trashcan_verb)
            return true
        end
    end
    dbg_echo(item .. " is not junk")
    DRCI.put_away_item(item, capture_settings.reward_container)
    return false
end

--- Pick up a critter and deposit it at the event return surface.
local function capture_and_return(critter)
    dbg_echo("capture_and_return(" .. critter .. ")")
    DRC.fix_standing()

    fput("get " .. critter)
    pause(0.5)
    waitrt()

    local held_item = DRC.right_hand() or DRC.left_hand()

    -- Junk check: some events (Hollow Eve) yield junk items on "get <critter>".
    -- For example, "get shark" may pick up "discarded sharkskin" instead of the shark.
    if held_item then
        local junk = capture_settings.junk or {}
        for _, junk_name in ipairs(junk) do
            if held_item == junk_name then
                handle_item(held_item)
                return
            end
        end
    end

    -- Verify we actually picked something up before attempting the return trip
    if not (held_item and DRCI.in_hand(held_item)) then return end

    DRCT.walk_to(event_info.return_room)
    fput("put my " .. held_item .. " on " .. event_info.return_surface)
    pause(1)
    waitrt()

    -- Stow anything that ended up in hand after depositing on the surface
    held_item = DRC.right_hand() or DRC.left_hand()
    if held_item then handle_item(held_item) end
end

-------------------------------------------------------------------------------
-- Main loop
-------------------------------------------------------------------------------

dbg_echo("run")
while true do
    -- 1. Walk each room in the event's room list until we find a critter
    local found = false
    for _, room_id in ipairs(event_info.room_list) do
        DRCT.walk_to(room_id)
        if find_critter_in_room() then
            found = true
            break
        end
    end

    -- 2. No critters found: exit if the event has ended, otherwise wait and retry
    if not found then
        if Flags["critter-done"] then
            DRC.message("All critters captured! Event complete.")
            break
        end
        DRC.message("Waiting on more critters.")
        pause(15)
    else
        -- 3. Capture every critter visible in the current room
        local critter = find_critter_in_room()
        while critter do
            capture_and_return(critter)
            critter = find_critter_in_room()
        end
    end
end
