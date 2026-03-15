--- @revenant-script
--- name: bigshot
--- version: 1.0.0
--- author: Sordal
--- depends: go2 >= 1.0, eloot >= 1.0
--- description: Full hunting automation — combat, navigation, rest, bounty, group

local args_lib = require("lib/args")
local config = require("config")

local state = config.load()
local input = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd = parsed.args[1]

local function show_help()
    respond("Usage: ;bigshot [mode] [options]")
    respond("")
    respond("Modes:")
    respond("  (no args) / solo   Hunt solo")
    respond("  quick              Hunt in current room only")
    respond("  bounty             Hunt with bounty tracking")
    respond("  single / once      One hunt cycle then exit")
    respond("  head N             Lead group of N followers")
    respond("  tail / follow      Follow group leader")
    respond("  setup              Open settings GUI")
    respond("  profile save NAME  Save settings profile")
    respond("  profile load NAME  Load settings profile")
    respond("  profile list       List saved profiles")
    respond("  display            Show all current settings")
    respond("  help               Show this help")
end

if cmd == "help" or not cmd then
    if not cmd then
        respond("[bigshot] Hunting loop not yet implemented — run ;bigshot setup to configure")
    else
        show_help()
    end
    return

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open(state)
    return

elseif cmd == "display" then
    respond("[bigshot] Current settings:")
    local keys = {}
    for k in pairs(state) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = state[k]
        if type(v) == "table" then
            respond("  " .. k .. " = [" .. table.concat(v, ", ") .. "]")
        else
            respond("  " .. k .. " = " .. tostring(v))
        end
    end
    return

elseif cmd == "profile" then
    local subcmd = parsed.args[2]
    local name = parsed.args[3]
    if subcmd == "save" and name then
        config.save_profile(state, name)
    elseif subcmd == "load" and name then
        local profile = config.load_profile(name)
        if profile then
            for k, v in pairs(profile) do state[k] = v end
            config.save(state)
            respond("[bigshot] Loaded and saved profile: " .. name)
        end
    elseif subcmd == "list" then
        local profiles = config.list_profiles()
        if #profiles == 0 then
            respond("[bigshot] No saved profiles")
        else
            respond("[bigshot] Saved profiles:")
            for _, p in ipairs(profiles) do respond("  " .. p) end
        end
    else
        respond("Usage: ;bigshot profile <save|load|list> [name]")
    end
    return

elseif cmd == "solo" or cmd == "quick" or cmd == "bounty"
    or cmd == "single" or cmd == "once"
    or cmd == "head" or cmd == "tail" or cmd == "follow" then
    respond("[bigshot] Hunting mode '" .. cmd .. "' not yet implemented")
    respond("[bigshot] Settings and GUI are ready — use ;bigshot setup to configure")
    return

else
    show_help()
end
