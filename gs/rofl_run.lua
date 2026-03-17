--- @revenant-script
--- name: rofl_run
--- version: 1.0.4
--- author: elanthia-online
--- contributors: Tysong, Dissonance
--- game: gs
--- description: Runs the Rings of Lumnis event using rofl-puzzles and rofl-questions
--- tags: rings of lumnis,RoL
---
--- Changelog (from Lich5):
---   v1.0.4 (2025-04-25) - xml_encode in help, corrected mono/stash calls
---   v1.0.3 (2025-04-23) - improved hand handling, alternate commands
---   v1.0.2 (2025-04-22) - bugfix in header keyword
---   v1.0.1 (2025-04-21) - kill support scripts on exit
---   v1.0.0 (2025-04-20) - created

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

UserVars.rofl_debug = UserVars.rofl_debug or false
UserVars.ignore_ringing_xp = UserVars.ignore_ringing_xp or "no"
UserVars.stop_ringing = UserVars.stop_ringing or "no"
UserVars.ringing_start_resting = UserVars.ringing_start_resting or 90
UserVars.ringing_stop_resting = UserVars.ringing_stop_resting or 90

--------------------------------------------------------------------------------
-- Ring configurations (balcony UID, rest UID, ring room UIDs)
--------------------------------------------------------------------------------

local RINGS = {
    planes   = { balcony = 7111001, rest = 7110206, rooms = { 7111002, 7111003, 7111004, 7111005 } },
    spirit   = { balcony = 7112001, rest = 7110215, rooms = { 7112002, 7112003, 7112004, 7112005 } },
    elements = { balcony = 7113001, rest = 7110221, rooms = { 7113002, 7113003, 7113004, 7113005 } },
    chaos    = { balcony = 7114001, rest = 7110227, rooms = { 7114002, 7114003, 7114004, 7114005 } },
    order    = { balcony = 7115001, rest = 7110233, rooms = { 7115002, 7115003, 7115004, 7115005 } },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function go2(uid)
    Script.run("go2", "u" .. tostring(uid))
    wait_while(function() return running("go2") end)
end

local function table_contains(t, val)
    for _, v in ipairs(t) do if v == val then return true end end
    return false
end

local function at_uid(uid)
    local room = Room.current()
    return room and room.uid and table_contains(type(room.uid) == "table" and room.uid or { room.uid }, uid)
end

local function check_support_scripts()
    if not running("rofl-puzzles") then
        Script.start("rofl-puzzles")
    end
    if not running("rofl-questions") then
        Script.start("rofl-questions", "auto")
    end
    pause(1)
    if not running("rofl-puzzles") or not running("rofl-questions") then
        echo("Support scripts failed to start! Download rofl-puzzles and rofl-questions.")
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- Main ringing loop
--------------------------------------------------------------------------------

local function ringing_loop(config)
    if not check_support_scripts() then return end

    before_dying(function()
        if running("rofl-puzzles") then Script.kill("rofl-puzzles") end
        if running("rofl-questions") then Script.kill("rofl-questions") end
    end)

    while true do
        -- Check for runs
        local out = dothistimeout("look at scholar's card", 2, { "This card grants travel" })
        if not out then
            echo("You are out of runs!")
            return
        end

        -- XP management
        if UserVars.ignore_ringing_xp ~= "yes" then
            local start_pct = tonumber(UserVars.ringing_start_resting) or 90
            if percentmind() > start_pct then
                echo("Mind " .. percentmind() .. "%; resting...")
                go2(config.rest)
                local stop_pct = tonumber(UserVars.ringing_stop_resting) or 90
                while percentmind() > stop_pct do pause(1) end
            end
        end

        -- Navigate to balcony
        if not at_uid(config.balcony) then
            if hidden() then fput("unhide") end
            go2(config.balcony)
        end

        -- Enter a ring room
        local dirs = { "ne", "nw" }
        fput(dirs[math.random(#dirs)])
        fput(math.random(2) == 1 and "n" or "look")

        -- Get card
        dothistimeout("get scholar's card", 2, { "You remove a", "You already have that" })

        check_support_scripts()

        -- Enter ring
        dothistimeout("go ring", 2, { "If this is intended" })
        dothistimeout("go ring", 2, { "Bright light bursts" })

        -- Wait for completion (returned to ring room)
        while true do
            local room = Room.current()
            if room and room.uid then
                local uid = type(room.uid) == "table" and room.uid[1] or room.uid
                if table_contains(config.rooms, uid) then break end
            end
            pause(1)
        end

        pause(3)

        -- Check stop flag
        if UserVars.stop_ringing == "yes" then
            go2(config.rest)
            echo("Stopping. Var reset to no.")
            UserVars.stop_ringing = "no"
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("** Rings of Lumnis Runner **")
    respond("")
    respond("USAGE: ;rofl_run <planes|spirit|elements|chaos|order>")
    respond("")
    respond("  ;rofl_run help            - Show this help")
    respond("  ;rofl_run stop            - Stop after current run")
    respond("  ;rofl_run absorb_xp       - Enable XP management")
    respond("  ;rofl_run ignore_xp       - Disable XP management")
    respond("  ;rofl_run debug           - Toggle debug mode")
    respond("")
    respond("Requires: rofl-puzzles and rofl-questions scripts")
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]
if not arg1 or arg1 == "" then show_help(); return end

local a = arg1:lower()
if a:find("plane") or a:find("planar") then
    ringing_loop(RINGS.planes)
elseif a:find("spirit") then
    ringing_loop(RINGS.spirit)
elseif a:find("element") then
    ringing_loop(RINGS.elements)
elseif a:find("chaos") then
    ringing_loop(RINGS.chaos)
elseif a:find("order") then
    ringing_loop(RINGS.order)
elseif a:find("help") then
    show_help()
elseif a:find("ignore_xp") then
    UserVars.ignore_ringing_xp = "yes"
    echo("XP status will be ignored.")
elseif a:find("absorb_xp") then
    UserVars.ignore_ringing_xp = "no"
    echo("XP will be absorbed before continuing.")
elseif a:find("debug") then
    UserVars.rofl_debug = not UserVars.rofl_debug
    echo("Debug: " .. tostring(UserVars.rofl_debug))
elseif a:find("stop") then
    UserVars.stop_ringing = "yes"
    echo("Will stop after current run.")
else
    show_help()
end
