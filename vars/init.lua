--- @revenant-script
--- name: vars
--- version: 1.0.0
--- author: Sordal
--- description: User variable editor with GUI

local args_lib = require("lib/args")
require("lib/vars")  -- registers global Vars

local input  = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd    = parsed.args[1]

local function show_list()
    local all = Vars.list()
    local count = 0
    local keys = {}
    for k in pairs(all) do
        keys[#keys + 1] = k
        count = count + 1
    end
    table.sort(keys)
    respond("User variables (" .. count .. "):")
    for _, k in ipairs(keys) do
        local v = all[k]
        local t = type(v)
        respond(string.format("  %-25s  %-8s  %s", k, t, tostring(v)))
    end
end

local function show_help()
    respond("Usage: ;vars [command]")
    respond("")
    respond("Commands:")
    respond("  (no args)            List all variables")
    respond("  set <name> <value>   Set a variable")
    respond("  set <name>=<value>   Set a variable (alt syntax)")
    respond("  get <name>           Show a single variable")
    respond("  unset <name>         Delete a variable")
    respond("  clear yes            Delete ALL variables")
    respond("  setup                Open GUI editor")
    respond("  help                 Show this help")
end

if not cmd then
    show_list()
    return
end

if cmd == "help" then
    show_help()

elseif cmd == "set" then
    local name, value
    -- Support NAME=VALUE syntax
    local eq_name, eq_value = input:match("^set%s+([^%s=]+)%s*=%s*(.+)$")
    if eq_name then
        name, value = eq_name, eq_value
    else
        name = parsed.args[2]
        if parsed.args[3] then
            local parts = {}
            for i = 3, #parsed.args do parts[#parts + 1] = parsed.args[i] end
            value = table.concat(parts, " ")
        end
    end

    if not name or not value then
        respond("Usage: ;vars set <name> <value>  or  ;vars set <name>=<value>")
        return
    end

    -- Boolean coercion
    if value:lower() == "true" then
        Vars[name] = true
    elseif value:lower() == "false" then
        Vars[name] = false
    else
        local num = tonumber(value)
        if num then
            Vars[name] = num
        else
            Vars[name] = value
        end
    end
    respond("Set: " .. name .. " = " .. tostring(Vars[name]) .. " (" .. type(Vars[name]) .. ")")

elseif cmd == "get" then
    local name = parsed.args[2]
    if not name then
        respond("Usage: ;vars get <name>")
        return
    end
    local val = Vars[name]
    if val ~= nil then
        respond(name .. " = " .. tostring(val) .. " (" .. type(val) .. ")")
    else
        respond(name .. " is not set")
    end

elseif cmd == "unset" then
    local name = parsed.args[2]
    if not name then
        respond("Usage: ;vars unset <name>")
        return
    end
    Vars[name] = nil
    respond("Unset: " .. name)

elseif cmd == "clear" then
    if parsed.args[2] ~= "yes" then
        respond("Usage: ;vars clear yes  (confirmation required)")
        return
    end
    local all = Vars.list()
    local count = 0
    for k in pairs(all) do
        Vars[k] = nil
        count = count + 1
    end
    respond("Cleared " .. count .. " variables")

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open()

else
    show_help()
end
