--- @revenant-script
--- name: invoker
--- version: 2.4.1
--- author: elanthia-online
--- contributors: Nesmeor, Athias, Tysong
--- game: gs
--- description: Monitors for the FWI invoker and visits for spellup
--- tags: utility,spellup
---
--- Changelog (from Lich5):
---   v2.4.1 (2025-04-12) - Logic to wait for invoker if arrived early
---   v2.4.0 (2024-08-06) - tzinfo gem loading
---   v2.3.1 (2024-08-06) - Fix endless loop after invoker move
---   v2.3.0 (2024-06-18) - Updated timing to even hours UTC

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function load_list(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

local function save_list(key, val)
    CharSettings[key] = Json.encode(val)
end

local scripts_to_pause = load_list("scripts_to_pause", { "bigshot", "ebounty" })
local scripts_to_kill  = load_list("scripts_to_kill", { "sloot", "poolparty", "eloot" })
local auto_mode = CharSettings["invoker_auto"] == "true"

local INVOKER_LOCATION = 3677  -- FWI Gardenia Commons

local current_hour = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function go2(dest)
    if hidden() or invisible() then fput("unhide") end
    waitrt()
    waitcastrt()
    Script.run("go2", tostring(dest) .. " --disable-confirm")
    wait_while(function() return running("go2") end)
    pause(0.2)
end

local function check_time()
    -- Invoker appears every even hour for 15 minutes (Eastern time)
    local t = os.date("!*t")  -- UTC
    -- Convert to Eastern roughly (UTC-5 or UTC-4)
    local eastern_hour = (t.hour - 5) % 24
    if eastern_hour % 2 ~= 0 then return false end
    return t.min >= 0 and t.min <= 15
end

local function halt_scripts()
    local resumed = {}
    for _, name in ipairs(scripts_to_pause) do
        if running(name) then
            Script.pause(name)
            resumed[#resumed + 1] = name
        end
    end
    for _, name in ipairs(scripts_to_kill) do
        if running(name) then Script.kill(name) end
    end
    return resumed
end

local function resume_scripts(resumed)
    for _, name in ipairs(resumed) do
        if running(name) then Script.unpause(name) end
    end
end

local function get_silvers()
    if Char.silver >= 10000 then return end
    go2("bank")
    fput("withdraw " .. (10000 - Char.silver) .. " silver")
    go2(INVOKER_LOCATION)
end

local function get_spells()
    -- Wait for invoker NPC if early
    local npcs = GameObj.npcs()
    local found = false
    for _, npc in ipairs(npcs) do
        if npc.noun == "invoker" then found = true; break end
    end
    if not found then
        echo("Invoker not here yet, waiting...")
        for _ = 1, 60 do
            pause(5)
            npcs = GameObj.npcs()
            for _, npc in ipairs(npcs) do
                if npc.noun == "invoker" then found = true; break end
            end
            if found then break end
        end
    end

    local result = dothistimeout("ask invoker about spells", 3, {
        "I've already granted you some spells",
        "The cost for my services is 10,000 silver",
        "releases upon you a flurry of abjurations",
    })

    if result and result:find("The cost for my services") then
        fput("ask invoker about spells")
    elseif result and result:find("already granted") then
        echo("Already received spells this hour.")
    end
end

local function visit_invoker()
    local return_room = Room.current()
    local return_id = return_room and return_room.id or nil

    go2(INVOKER_LOCATION)
    get_silvers()
    get_spells()

    if return_id then
        go2(return_id)
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("Invoker - Monitors for the FWI invoker and visits for spellup.")
    respond("")
    respond("  ;invoker           - Run in monitor mode")
    respond("  ;invoker auto      - Run with auto-visit enabled")
    respond("  ;invoker toggle    - Toggle default auto mode")
    respond("  ;invoker list      - Show pause/kill script lists")
    respond("  ;invoker add pause/kill <script>")
    respond("  ;invoker remove pause/kill <script>")
    respond("  ;invoker help      - This message")
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]

if arg1 == "help" then
    show_help()
    return
elseif arg1 == "toggle" then
    auto_mode = not auto_mode
    CharSettings["invoker_auto"] = tostring(auto_mode)
    echo("Auto mode: " .. tostring(auto_mode))
    return
elseif arg1 == "list" then
    echo("Scripts to pause: " .. table.concat(scripts_to_pause, ", "))
    echo("Scripts to kill: " .. table.concat(scripts_to_kill, ", "))
    return
elseif arg1 == "add" then
    local arg2 = Script.vars[2]
    local arg3 = Script.vars[3]
    if arg2 == "pause" and arg3 then
        scripts_to_pause[#scripts_to_pause + 1] = arg3
        save_list("scripts_to_pause", scripts_to_pause)
        echo(arg3 .. " added to pause list")
    elseif arg2 == "kill" and arg3 then
        scripts_to_kill[#scripts_to_kill + 1] = arg3
        save_list("scripts_to_kill", scripts_to_kill)
        echo(arg3 .. " added to kill list")
    end
    return
elseif arg1 == "remove" then
    local arg2 = Script.vars[2]
    local arg3 = Script.vars[3]
    if arg2 == "pause" and arg3 then
        for i = #scripts_to_pause, 1, -1 do
            if scripts_to_pause[i] == arg3 then table.remove(scripts_to_pause, i) end
        end
        save_list("scripts_to_pause", scripts_to_pause)
        echo(arg3 .. " removed from pause list")
    elseif arg2 == "kill" and arg3 then
        for i = #scripts_to_kill, 1, -1 do
            if scripts_to_kill[i] == arg3 then table.remove(scripts_to_kill, i) end
        end
        save_list("scripts_to_kill", scripts_to_kill)
        echo(arg3 .. " removed from kill list")
    end
    return
elseif arg1 == "auto" then
    auto_mode = true
end

--------------------------------------------------------------------------------
-- Main monitoring loop
--------------------------------------------------------------------------------

echo("Invoker monitor running. Auto mode: " .. tostring(auto_mode))

while true do
    if check_time() then
        local new_hour = os.date("*t").hour
        if current_hour ~= new_hour then
            current_hour = new_hour

            if auto_mode then
                echo("Invoker is available. Auto-visiting in 15 seconds...")
                pause(15)
                local resumed = halt_scripts()
                visit_invoker()
                resume_scripts(resumed)
            else
                echo("The invoker is now available. Use ;invoker auto to auto-visit.")
            end
        end
    end
    pause(60)
end
