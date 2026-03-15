local M = {}

function M.open(cache)
    local win = Gui.window("Aliases", { width = 500, height = 400 })
    local root = Gui.vbox()

    -- Scope toggle
    local scope_bar = Gui.hbox()
    local char_btn = Gui.button("* Character")
    local global_btn = Gui.button("Global")
    local current_scope = "char"  -- "char" or "global"

    -- Alias table
    local alias_table = Gui.table({ columns = { "Name", "Pattern", "Replacement" }, rows = {} })

    Gui.separator()

    -- Add form
    local add_bar = Gui.hbox()
    local name_input = Gui.input({ placeholder = "name" })
    local pattern_input = Gui.input({ placeholder = "pattern" })
    local repl_input = Gui.input({ placeholder = "replacement" })

    -- Actions
    local action_bar = Gui.hbox()
    local add_btn = Gui.button("Add")
    local delete_btn = Gui.button("Delete Selected")
    local enabled_chk = Gui.checkbox("Enabled", CharSettings["alias_enabled"] ~= "false")

    Gui.separator()
    local save_btn = Gui.button("Save & Close")

    win:set_root(root)

    -- Local working copies
    local char_list = {}
    local global_list = {}
    for _, e in ipairs(cache.get_char()) do char_list[#char_list + 1] = e end
    for _, e in ipairs(cache.get_global()) do global_list[#global_list + 1] = e end

    local function get_active_list()
        return current_scope == "char" and char_list or global_list
    end

    local function refresh_table()
        local list = get_active_list()
        local rows = {}
        for _, e in ipairs(list) do
            rows[#rows + 1] = { e.name, e.pattern, tostring(e.replacement) }
        end
        -- Table row update depends on Gui API support
        respond("[alias] " .. #list .. " aliases in " .. current_scope .. " scope")
    end

    refresh_table()

    -- Callbacks
    char_btn:on_click(function()
        current_scope = "char"
        char_btn:set_label("* Character")
        global_btn:set_label("Global")
        refresh_table()
    end)

    global_btn:on_click(function()
        current_scope = "global"
        char_btn:set_label("Character")
        global_btn:set_label("* Global")
        refresh_table()
    end)

    add_btn:on_click(function()
        local name = name_input:get_text()
        local pattern = pattern_input:get_text()
        local repl = repl_input:get_text()
        if not name or name == "" or not pattern or pattern == "" or not repl or repl == "" then
            respond("[alias] Name, pattern, and replacement are all required")
            return
        end
        local list = get_active_list()
        -- Replace existing with same name
        local found = false
        for i, e in ipairs(list) do
            if e.name == name then
                list[i] = { name = name, pattern = pattern, replacement = repl }
                found = true
                break
            end
        end
        if not found then
            list[#list + 1] = { name = name, pattern = pattern, replacement = repl }
        end
        refresh_table()
        respond("[alias] Added: " .. name)
    end)

    delete_btn:on_click(function()
        -- Without table row selection event, delete by name from input
        local name = name_input:get_text()
        if not name or name == "" then
            respond("[alias] Enter the alias name to delete in the name field")
            return
        end
        local list = get_active_list()
        local new = {}
        local removed = false
        for _, e in ipairs(list) do
            if e.name ~= name then
                new[#new + 1] = e
            else
                removed = true
            end
        end
        if removed then
            if current_scope == "char" then
                char_list = new
            else
                global_list = new
            end
            refresh_table()
            respond("[alias] Deleted: " .. name)
        else
            respond("[alias] Not found: " .. name)
        end
    end)

    enabled_chk:on_change(function(val)
        CharSettings["alias_enabled"] = val and "true" or "false"
    end)

    save_btn:on_click(function()
        cache.save_char(char_list)
        cache.save_global(global_list)
        respond("[alias] Settings saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
    -- If closed via X without Save, changes are discarded
end

return M
