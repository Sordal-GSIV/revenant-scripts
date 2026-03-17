local M = {}

require("lib/vars")  -- ensures Vars is available

function M.open()
    local win = Gui.window("User Variables", { width = 500, height = 400 })
    local root = Gui.vbox()

    local var_table = Gui.table({ columns = { "Name", "Value", "Type" } })
    root:add(var_table)

    root:add(Gui.separator())

    local form = Gui.hbox()
    local name_input = Gui.input({ placeholder = "variable name" })
    form:add(name_input)
    local value_input = Gui.input({ placeholder = "value" })
    form:add(value_input)
    local set_btn = Gui.button("Set")
    form:add(set_btn)
    root:add(form)

    local action_bar = Gui.hbox()
    local delete_btn = Gui.button("Delete")
    action_bar:add(delete_btn)
    local refresh_btn = Gui.button("Refresh")
    action_bar:add(refresh_btn)
    root:add(action_bar)

    root:add(Gui.separator())
    local close_btn = Gui.button("Close")
    root:add(close_btn)

    win:set_root(root)

    local function refresh()
        var_table:clear()
        local all = Vars.list()
        local keys = {}
        for k in pairs(all) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = all[k]
            var_table:add_row({ k, tostring(v), type(v) })
        end
        respond("[vars] " .. #keys .. " variables loaded")
    end

    refresh()

    set_btn:on_click(function()
        local name = name_input:get_text()
        local value = value_input:get_text()
        if not name or name == "" then
            respond("[vars] Name is required")
            return
        end
        if not value or value == "" then
            respond("[vars] Value is required")
            return
        end
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
        respond("[vars] Set: " .. name .. " = " .. tostring(Vars[name]))
        refresh()
    end)

    delete_btn:on_click(function()
        local name = name_input:get_text()
        if not name or name == "" then
            respond("[vars] Enter the variable name to delete")
            return
        end
        if Vars[name] ~= nil then
            Vars[name] = nil
            respond("[vars] Deleted: " .. name)
            refresh()
        else
            respond("[vars] Not found: " .. name)
        end
    end)

    refresh_btn:on_click(function()
        refresh()
    end)

    close_btn:on_click(function()
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
