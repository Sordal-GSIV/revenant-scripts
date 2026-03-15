--- @revenant-script
--- name: go2
--- version: 1.0.0
--- author: Sordal
--- description: Room-to-room navigation with pathfinding

local settings = require("settings")
local pathfinder = require("pathfinder")
local movement = require("movement")
local resolver = require("resolver")

local args_lib = require("lib/args")
local parsed = args_lib.parse(Script.vars[0] or "")
local cmd = parsed.args[1]
local state = settings.load()

-- === Command dispatch ===

local function show_help()
    respond("Usage: ;go2 <destination> [options]")
    respond("")
    respond("Destinations:")
    respond("  <room_id>       Navigate to room by ID")
    respond("  <tag>           Navigate to nearest room with tag (e.g., bank, inn)")
    respond("  <text>          Search room titles")
    respond("  u<uid>          Navigate by UID")
    respond("  goback          Return to room where go2 was last started")
    respond("")
    respond("Commands:")
    respond("  help            Show this help")
    respond("  setup           Open settings GUI")
    respond("  list            Show current settings and custom targets")
    respond("  save <n>=<id>   Save custom target (use 'current' for current room)")
    respond("  delete <name>   Delete custom target")
    respond("")
    respond("Options:")
    respond("  --delay=N           Seconds to wait between moves")
    respond("  --disable-confirm   Skip confirmation prompts")
    respond("  --hide-desc         Hide room descriptions during travel")
    respond("  --hide-titles       Hide room titles during travel")
end

local function show_list()
    respond("[go2] Current settings:")
    respond("  delay: " .. (state.delay or 0))
    respond("  hide_room_descriptions: " .. tostring(state.hide_room_descriptions))
    respond("  hide_room_titles: " .. tostring(state.hide_room_titles))
    respond("  disable_confirm: " .. tostring(state.disable_confirm))
    respond("")
    local targets = settings.load_targets()
    local count = 0
    for _ in pairs(targets) do count = count + 1 end
    if count > 0 then
        respond("[go2] Custom targets:")
        for name, val in pairs(targets) do
            local display = type(val) == "table" and table.concat(val, ",") or tostring(val)
            respond("  " .. name .. " = " .. display)
        end
    else
        respond("[go2] No custom targets saved")
    end
end

local function handle_save()
    local arg = parsed.args[2]
    if not arg or not arg:find("=") then
        respond("Usage: ;go2 save <name>=<room_id|current>")
        return
    end
    local name, val_str = arg:match("^(.-)=(.+)$")
    if not name or not val_str then
        respond("Usage: ;go2 save <name>=<room_id|current>")
        return
    end
    local targets = settings.load_targets()
    if val_str:lower() == "current" then
        local room_id = Map.current_room()
        if not room_id then
            respond("[go2] Error: current room unknown")
            return
        end
        targets[name] = room_id
        respond("[go2] Saved target: " .. name .. " = " .. room_id .. " (current room)")
    else
        local room_id = tonumber(val_str)
        if not room_id then
            respond("[go2] Error: room ID must be a number or 'current'")
            return
        end
        targets[name] = room_id
        respond("[go2] Saved target: " .. name .. " = " .. room_id)
    end
    settings.save_targets(targets)
end

local function handle_delete()
    local name = parsed.args[2]
    if not name then
        respond("Usage: ;go2 delete <name>")
        return
    end
    local targets = settings.load_targets()
    if targets[name] then
        targets[name] = nil
        settings.save_targets(targets)
        respond("[go2] Deleted target: " .. name)
    else
        respond("[go2] Target not found: " .. name)
    end
end

-- Dispatch non-navigation commands
if not cmd or cmd == "help" then
    show_help()
    return
elseif cmd == "setup" then
    local gui = require("gui_settings")
    local targets = settings.load_targets()
    gui.open(state, targets)
    return
elseif cmd == "list" then
    show_list()
    return
elseif cmd == "save" then
    handle_save()
    return
elseif cmd == "delete" then
    handle_delete()
    return
end

-- === Navigation mode ===

-- Build target string from all non-flag args
local target_parts = {}
for _, arg in ipairs(parsed.args) do
    target_parts[#target_parts + 1] = arg
end
local target = table.concat(target_parts, " ")

-- Apply CLI flag overrides
local overrides = {}
local function override(key, value)
    if overrides[key] == nil then
        overrides[key] = state[key]
    end
    state[key] = value
end

if parsed["disable-confirm"] then override("disable_confirm", true) end
if parsed["hide-desc"] then override("hide_room_descriptions", true) end
if parsed["hide-titles"] then override("hide_room_titles", true) end
if parsed.delay then
    local d = tonumber(parsed.delay)
    if d then override("delay", d) end
end

-- Restore overrides on exit
before_dying(function()
    if next(overrides) then
        local s = settings.load()
        for k, v in pairs(overrides) do
            s[k] = v
        end
        settings.save(s)
    end
    pathfinder.clear_blacklist()
end)

-- Save start room for goback
local start_room = Map.current_room()
if start_room then
    settings.save_start_room(start_room)
end

-- Install desc/title squelch hooks if needed
if state.hide_room_descriptions then
    DownstreamHook.add("go2_hide_desc", function(line)
        if line:find("<roomDesc>") or line:find("</roomDesc>") then return nil end
        return line
    end)
    before_dying(function() DownstreamHook.remove("go2_hide_desc") end)
end

if state.hide_room_titles then
    DownstreamHook.add("go2_hide_title", function(line)
        if line:find("<roomName>") or line:find("</roomName>") then return nil end
        return line
    end)
    before_dying(function() DownstreamHook.remove("go2_hide_title") end)
end

-- Resolve target
local current_room = Map.current_room()
if not current_room then
    respond("[go2] Error: current room not found in map database")
    return
end

local dest_id, confirm, err = resolver.resolve(target, current_room)
if not dest_id then
    respond("[go2] Error: " .. (err or "unknown error"))
    return
end

-- Confirmation
if confirm and not state.disable_confirm then
    local dest_room = Map.find_room(dest_id)
    local steps = pathfinder.estimate_steps(current_room, dest_id)
    respond("[go2] Destination: " .. (dest_room and dest_room.title or "Room " .. dest_id)
        .. " [" .. dest_id .. "]"
        .. (steps and (" — " .. steps .. " steps") or ""))
    respond("[go2] Pausing — ;unpause go2 to proceed, ;kill go2 to cancel")
    -- pause_script equivalent: the script yields here until unpaused
    -- This relies on the pause mechanism in the engine
    pause(999999)  -- effectively blocks until killed or unpaused
end

-- Navigation loop
local max_retries = 5
local retries = 0

while retries < max_retries do
    current_room = Map.current_room()
    if not current_room then
        respond("[go2] Error: lost position — current room unknown")
        break
    end

    if current_room == dest_id then
        respond("[go2] Arrived at destination")
        break
    end

    local path, path_err = pathfinder.find(current_room, dest_id)
    if not path then
        respond("[go2] Error: " .. path_err)
        break
    end

    if #path == 0 then
        respond("[go2] Already at destination")
        break
    end

    if state.echo_input then
        respond("[go2] Moving — " .. #path .. " steps remaining")
    end

    local ok, walk_err = movement.walk(path, state, function(i, total, cmd_str)
        if state.echo_input then
            respond("[go2] Step " .. i .. "/" .. total .. ": " .. cmd_str)
        end
    end)

    if ok then
        respond("[go2] Arrived at destination")
        break
    elseif walk_err == "retry" then
        retries = retries + 1
        if retries < max_retries then
            respond("[go2] Movement failed — re-routing (attempt " .. retries .. "/" .. max_retries .. ")")
            pause(0.5)
        end
    else
        respond("[go2] Error: " .. tostring(walk_err))
        break
    end
end

if retries >= max_retries then
    respond("[go2] Error: exceeded maximum retries (" .. max_retries .. ")")
end
