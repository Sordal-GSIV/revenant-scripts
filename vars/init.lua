--- @revenant-script
--- name: vars
--- version: 1.2.1
--- author: Sordal
--- original-authors: Tillmen, Elanthia-Online
--- description: User variable editor with GUI
--- game: Gemstone
--- tags: core
--- @lic-certified: complete 2026-03-18

local args_lib = require("lib/args")
require("lib/vars")  -- registers global Vars

local input  = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd    = parsed.args[1]

local function show_list()
    local all = Vars.list()
    if next(all) == nil then
        respond("\n--- no variables are set\n\n")
        return
    end
    local keys = {}
    local max_len = 0
    for k in pairs(all) do
        keys[#keys + 1] = k
        if #k > max_len then max_len = #k end
    end
    table.sort(keys)
    local output = "\n--- " .. (GameState.name or "Character") .. "'s variables:\n\n"
    for _, k in ipairs(keys) do
        local v = all[k]
        local padded = string.rep(" ", max_len - #k) .. k
        output = output .. "   " .. padded .. ":  " .. tostring(v) .. "\n"
    end
    output = output .. "\n"
    respond(output)
end

local function show_help()
    local output = "\n"
    output = output .. "   ;vars setup              open a window to edit variables\n"
    output = output .. "   ;vars set NAME=VALUE     add or change a variable\n"
    output = output .. "   ;vars delete NAME        delete a variable\n"
    output = output .. "   ;vars list               show current variables\n"
    output = output .. "   ;vars get NAME           show a single variable\n"
    output = output .. "   ;vars clear yes          delete ALL variables\n"
    output = output .. "\n"
    respond(output)
end

if not cmd then
    show_list()
    return
end

if cmd == "help" then
    show_help()

elseif cmd == "set" then
    local name, value
    -- Support NAME=VALUE syntax (original format)
    local eq_name, eq_value = input:match("^set%s+([^%s=]+)%s*=%s*(.+)$")
    if eq_name then
        name, value = eq_name, eq_value:match("^(.-)%s*$")
    else
        name = parsed.args[2]
        if parsed.args[3] then
            local parts = {}
            for i = 3, #parsed.args do parts[#parts + 1] = parsed.args[i] end
            value = table.concat(parts, " ")
        end
    end

    if not name or not value then
        respond("Usage: ;vars set <name>=<value>")
        return
    end

    local old_value = Vars[name]
    -- Boolean coercion only (matches original behavior)
    if value:lower() == "true" then
        Vars[name] = true
    elseif value:lower() == "false" then
        Vars[name] = false
    else
        Vars[name] = value
    end

    if old_value == nil then
        respond('\n--- variable "' .. name .. '" set to: "' .. tostring(Vars[name]) .. '"\n\n')
    else
        respond('\n--- variable ' .. name .. ' changed to: ' .. tostring(Vars[name]) ..
            ' (was ' .. tostring(old_value) .. ')\n\n')
    end

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
        respond("\n--- variable " .. name .. " does not exist\n\n")
    end

elseif cmd == "delete" or cmd == "del" or cmd == "remove" or cmd == "rem" or cmd == "unset" then
    local name = parsed.args[2]
    if not name then
        respond("Usage: ;vars delete <name>")
        return
    end
    if Vars[name] == nil then
        respond("\n--- variable " .. name .. " does not exist\n\n")
    else
        Vars[name] = nil
        respond("\n--- variable " .. name .. " was deleted\n\n")
    end

elseif cmd == "list" then
    show_list()

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
    respond("Cleared " .. count .. " variables.")

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open()

else
    show_help()
end
