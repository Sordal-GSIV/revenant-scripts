local settings = require("settings")

local M = {}

function M.open(state, targets)
    local win = Gui.window("Go2 Settings", { width = 450, height = 500 })
    local root = Gui.vbox()

    -- Movement settings
    Gui.label("Movement Settings")
    local delay_box = Gui.hbox()
    Gui.label("Delay (sec):")
    local delay_input = Gui.input({ text = tostring(state.delay or 0) })

    local hide_desc_chk = Gui.checkbox("Hide room descriptions", state.hide_room_descriptions)
    local hide_title_chk = Gui.checkbox("Hide room titles", state.hide_room_titles)
    local disable_confirm_chk = Gui.checkbox("Disable confirmation prompts", state.disable_confirm)

    Gui.separator()

    -- Custom targets
    Gui.label("Custom Targets")
    local target_rows = {}
    local target_names = {}
    for name, val in pairs(targets) do
        local display = type(val) == "table" and table.concat(val, ",") or tostring(val)
        target_rows[#target_rows + 1] = { name, display }
        target_names[#target_names + 1] = name
    end
    local target_table = Gui.table({ columns = { "Name", "Room ID" }, rows = target_rows })

    local add_box = Gui.hbox()
    local name_input = Gui.input({ placeholder = "target name" })
    local room_input = Gui.input({ placeholder = "room ID" })
    local add_btn = Gui.button("Add")
    local delete_btn = Gui.button("Delete Selected")

    Gui.separator()

    local save_btn = Gui.button("Save & Close")

    win:set_root(root)

    -- Local state copy for modifications
    local local_state = {}
    for k, v in pairs(state) do local_state[k] = v end
    local local_targets = {}
    for k, v in pairs(targets) do local_targets[k] = v end

    -- Callbacks
    hide_desc_chk:on_change(function(val)
        local_state.hide_room_descriptions = val
    end)

    hide_title_chk:on_change(function(val)
        local_state.hide_room_titles = val
    end)

    disable_confirm_chk:on_change(function(val)
        local_state.disable_confirm = val
    end)

    add_btn:on_click(function()
        local name = name_input:get_text()
        local room_str = room_input:get_text()
        if not name or name == "" or not room_str or room_str == "" then
            respond("[go2] Name and room ID are required")
            return
        end
        local room_id = tonumber(room_str)
        if not room_id then
            respond("[go2] Room ID must be a number")
            return
        end
        local_targets[name] = room_id
        -- Refresh table
        local rows = {}
        for n, v in pairs(local_targets) do
            local display = type(v) == "table" and table.concat(v, ",") or tostring(v)
            rows[#rows + 1] = { n, display }
        end
        -- Table rows can't be updated after show in current GUI spec
        respond("[go2] Added target: " .. name .. " = " .. room_str)
    end)

    save_btn:on_click(function()
        -- Apply delay from input
        local delay_val = tonumber(delay_input:get_text())
        if delay_val then local_state.delay = delay_val end

        -- Persist
        for k, v in pairs(local_state) do state[k] = v end
        settings.save(state)

        for k in pairs(targets) do targets[k] = nil end
        for k, v in pairs(local_targets) do targets[k] = v end
        settings.save_targets(targets)

        respond("[go2] Settings saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
    -- If user closed via X without saving, changes are discarded
end

return M
