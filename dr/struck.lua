--- @revenant-script
--- name: struck
--- version: 16
--- author: Dreaven
--- game: dr
--- description: Client script for Thunder multi-character monitoring system
--- tags: multi-character, monitoring, networking
---
--- Converted from struck.lic (Lich5) to Revenant Lua
---
--- This is the "client" script of the ;thunder and ;struck script duo.
--- Connects to a local TCP server (;thunder) to share character stats
--- across multiple game instances.
---
--- Usage:
---   ;struck [port]   - Connect to Thunder server on specified port (default 4000)

local socket = require("socket") or nil
if not socket then
    echo("struck requires TCP socket support.")
    echo("Revenant multi-character support may provide this in the future.")
    return
end

hide_me()

-- Port configuration
local port = 4000
if Script.vars[1] and Script.vars[1]:match("^%d+$") then
    port = tonumber(Script.vars[1])
    UserVars.struck_port_number = port
elseif UserVars.struck_port_number then
    port = tonumber(UserVars.struck_port_number)
end

respond("#################################################################################################################")
respond("Message from ;struck:")
respond("You are currently set to connect to port " .. port .. ".")
respond("By default the port each character tries to connect to is port 4000.")
respond("If you want to change this then stop this script and start it as ;struck <number_here>")
respond("For example: ;struck 3000")
respond("After you have set the port number on this character you can start script as: ;struck")
respond("You only have to specify the port number if you want to change it again.")
respond("#################################################################################################################")

-- Connect to the Thunder server
local client, err = socket.tcp()
if not client then
    echo("Failed to create socket: " .. tostring(err))
    return
end

local ok, cerr = client:connect("localhost", port)
if not ok then
    echo("Failed to connect to Thunder server on port " .. port .. ": " .. tostring(cerr))
    echo("Make sure ;thunder is running on another character first.")
    return
end
client:settimeout(0.1)

local needed_values = {}
local send_the_game_lines = false
local exit_reason = nil
local current_request = nil
local current_stats = {}
local info_commands = {}

-- Silence downstream output for exp command
local silence_active = false
local silence_started = false

local function add_silence_hook()
    silence_started = false
    silence_active = true
    DownstreamHook.add("struck_silence", function(s)
        if silence_started then
            if s:find("<prompt") then
                DownstreamHook.remove("struck_silence")
                silence_active = false
                return nil
            elseif s:find("<output") then
                return s
            else
                return nil
            end
        elseif s:find("Level:") then
            silence_started = true
            return nil
        else
            return s
        end
    end)
end

local function send_message(message)
    if needed_values["Debug Mode"] == "Yes" then
        echo("Message sent: " .. message)
    end
    client:send(message .. "\n")
end

local function load_the_data(host_name)
    -- In Revenant, settings are stored per-character
    local save_file = "Thunder Settings"
    local load_data = CharSettings[save_file]
    if not load_data then return end

    local host_data = load_data[host_name]
    if not host_data then return end

    info_commands = host_data["Info Commands"] or {}

    for setting_name, value in pairs(host_data) do
        needed_values[setting_name] = value
    end
end

local function update_stat_values(stat_name, current_number, max_number)
    if current_number ~= current_stats[stat_name] and needed_values[stat_name] == "Yes" then
        current_stats[stat_name] = current_number
        send_message(checkname() .. ": " .. stat_name .. ": " .. current_number .. "/" .. max_number)
    end
end

local function update_status()
    local info = {}
    -- Check wounds/scars
    local injured = false
    local wound_parts = {"head", "neck", "chest", "abdomen", "back",
        "left_hand", "right_hand", "left_arm", "right_arm",
        "left_leg", "right_leg"}
    for _, part in ipairs(wound_parts) do
        if (Wounds[part] and Wounds[part] > 0) or (Scars[part] and Scars[part] > 0) then
            injured = true
            break
        end
    end
    if injured then table.insert(info, "Injured") end
    if checkprone and checkprone() then table.insert(info, "Prone") end
    if checkpoison and checkpoison() then table.insert(info, "Poisoned") end
    if checkdisease and checkdisease() then table.insert(info, "Diseased") end
    if checkbleeding and checkbleeding() then table.insert(info, "Bleeding") end
    if checkstunned and checkstunned() then table.insert(info, "Stunned") end
    if checkwebbed and checkwebbed() then table.insert(info, "Webbed") end
    if checkdead and checkdead() then
        info = {"DEAD"}
    end
    local info_str = #info > 0 and table.concat(info, ", ") or "GREAT!"

    if info_str ~= current_stats["Status"] then
        current_stats["Status"] = info_str
        send_message(checkname() .. ": Status: " .. info_str)
    end
end

local function update_bounty()
    local bounty = checkbounty and checkbounty() or ""
    local info = nil

    if bounty:find("The local gem dealer") then
        info = "Gem NPC"
    elseif bounty:find("You are not currently assigned a task") then
        info = "None"
    elseif bounty:find("You have succeeded in your task and can return") then
        info = "Finished Guild"
    elseif bounty:find("You succeeded in your task and should report") then
        info = "Finished Guard"
    elseif bounty:find("suppress bandit activity") then
        local count = bounty:match("kill (%d+)")
        info = (count or "?") .. " Bandits"
    elseif bounty:find("suppress.*activity") then
        local count, creature = bounty:match("kill (%d+).*of them.*")
        info = (count or "?") .. " Creatures"
    else
        info = "Other"
    end

    if info and info ~= current_stats["Bounty"] then
        current_stats["Bounty"] = info
        send_message(checkname() .. ": Bounty: " .. info)
    end
end

local function update_room()
    local room_id = Room.id or 0
    if room_id ~= current_stats["Room #"] then
        current_stats["Room #"] = room_id
        send_message(checkname() .. ": Room #: " .. room_id)
    end
end

local function receive_message()
    local message, err = client:receive("*l")
    if not message then
        if err == "timeout" then return false end
        exit_reason = "Disconnecting: Server connection lost."
        return true -- signal exit
    end

    echo("Message from server: " .. message)
    if #message < 1 then
        exit_reason = "Disconnecting: Server appears to be closed."
        return true
    elseif message == "Shut down." then
        exit_reason = "Disconnecting: Server told me to disconnect."
        return true
    elseif message:match("Host Name: ([a-zA-Z]+)") then
        local host_name = message:match("Host Name: ([a-zA-Z]+)")
        load_the_data(host_name)
    elseif message == "Respond now." then
        send_message(checkname() .. ": I am responding.")
    elseif message == "Send game lines." then
        send_the_game_lines = true
    elseif message == "Stop sending game lines." then
        send_the_game_lines = false
    elseif message:match("Action: (.*)") then
        local action = message:match("Action: (.*)")
        if action:match("^;k (.*)") then
            local script_name = action:match("^;k (.*)")
            kill_script(script_name)
        elseif action:match("^;u (.*)") or action:match("^;unpause (.*)") then
            local script_name = action:match("^;u (.*)") or action:match("^;unpause (.*)")
            unpause_script(script_name)
        elseif action:match("^;p (.*)") or action:match("^;pause (.*)") then
            local script_name = action:match("^;p (.*)") or action:match("^;pause (.*)")
            pause_script(script_name)
        elseif action == ";ka" then
            -- Kill all scripts except struck
            for _, s in ipairs(Script.running()) do
                if s.name ~= "struck" then s:kill() end
            end
        elseif action:match("^script") or action:match("^;") then
            local parts = {}
            for word in action:gmatch("%S+") do table.insert(parts, word) end
            if parts[1]:lower() == "script" then table.remove(parts, 1) end
            if parts[1] and parts[1]:sub(1,1) == ";" then parts[1] = parts[1]:sub(2) end
            local script_name = table.remove(parts, 1)
            if script_name then
                start_script(script_name, parts)
            end
        else
            put(action)
        end
    elseif message:match("Request: (.*)") then
        local command_name = message:match("Request: (.*)")
        if info_commands[command_name] then
            current_request = info_commands[command_name]["Game Line"]
            put(info_commands[command_name]["Command"])
        end
    end
    return false
end

-- Cleanup on exit
before_dying(function()
    DownstreamHook.remove("struck_silence")
    exit_reason = exit_reason or "Disconnecting: Script was stopped."
    echo(exit_reason)
    pcall(function()
        send_message(checkname() .. ": " .. exit_reason)
        client:close()
    end)
end)

-- Send our name to identify ourselves
send_message(checkname())

-- Stats update thread
local last_update = 0
local last_room_update = 0
local last_exp_update = 0
local last_mind_state = ""

-- Game line reading thread
local current_field_exp = nil
local max_field_exp = nil

-- Main loop - interleaves message receiving with stat updates
while true do
    -- Check for server messages (non-blocking)
    local should_exit = receive_message()
    if should_exit then break end

    -- Only update stats once we have settings loaded
    if next(needed_values) and needed_values["Stats"] ~= "Hide" then
        local now = os.clock()

        -- Update vitals periodically
        local update_interval = tonumber(needed_values["Update Info"]) or 5
        if now - last_update >= update_interval then
            last_update = now
            update_stat_values("Health", checkhealth and checkhealth() or 0, maxhealth and maxhealth() or 100)
            update_stat_values("Mana", checkmana and checkmana() or 0, maxmana and maxmana() or 100)
            update_stat_values("Stamina", checkstamina and checkstamina() or 0, maxstamina and maxstamina() or 100)
            update_stat_values("Spirit", checkspirit and checkspirit() or 0, maxspirit and maxspirit() or 100)
            if needed_values["Status"] == "Yes" then update_status() end
            if needed_values["Bounty"] == "Yes" then update_bounty() end
        end

        -- Update room periodically
        if needed_values["Room #"] == "Yes" then
            local room_interval = tonumber(needed_values["Update Room"]) or 2
            if now - last_room_update >= room_interval then
                last_room_update = now
                update_room()
            end
        end
    end

    -- Check for game lines
    local line = get_with_timeout(0.1)
    if line then
        -- Check for current request response
        if current_request and line:find(current_request) then
            local captured = line:match(current_request)
            send_message(checkname() .. ": Requested Info: " .. (captured or line))
            current_request = nil
        end

        -- Check for field exp
        local cur_exp, max_exp = line:match("Field Exp: ([%d,]+)/([%d,]+)")
        if cur_exp and max_field_exp == nil then
            current_field_exp = tonumber(cur_exp:gsub(",", ""))
            max_field_exp = tonumber(max_exp:gsub(",", ""))
        end

        -- Forward game lines if requested
        if send_the_game_lines then
            send_message(checkname() .. ": Game Line: " .. line)
        end
    end

    pause(0.05)
end
