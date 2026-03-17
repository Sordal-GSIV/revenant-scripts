local config = require("config")

local M = {}

function M.open(state)
    local win = Gui.window("Bigshot Settings", { width = 650, height = 500 })
    local root = Gui.vbox()

    -- Tab bar
    local tabs = Gui.hbox()
    local rest_btn = Gui.button("* Resting")
    local hunt_btn = Gui.button("Hunting")
    local cmd_btn = Gui.button("Commands")
    local misc_btn = Gui.button("Misc")

    Gui.separator()

    -- Resting tab
    Gui.label("Resting Settings")
    local rest_hbox = Gui.hbox()
    Gui.label("Rest room ID:")
    local rest_room_input = Gui.input({ text = tostring(state.rest_room or "") })

    Gui.label("Rest thresholds:")
    local exp_hbox = Gui.hbox()
    Gui.label("Exp %:")
    local exp_input = Gui.input({ text = tostring(state.rest_till_exp or 80) })
    Gui.label("Mana %:")
    local mana_input = Gui.input({ text = tostring(state.rest_till_mana or 80) })

    local spirit_hbox = Gui.hbox()
    Gui.label("Spirit:")
    local spirit_input = Gui.input({ text = tostring(state.rest_till_spirit or 100) })
    Gui.label("Stamina %:")
    local stam_input = Gui.input({ text = tostring(state.rest_till_percentstamina or 80) })

    Gui.separator()

    -- Hunting tab
    Gui.label("Hunting Settings")
    local hunt_hbox = Gui.hbox()
    Gui.label("Hunting room ID:")
    local hunt_room_input = Gui.input({ text = tostring(state.hunting_room_id or 0) })

    Gui.label("Boundaries (comma-separated room IDs):")
    local bounds_input = Gui.input({
        text = table.concat(state.hunting_boundaries or {}, ",")
    })

    Gui.label("Wander wait (seconds):")
    local wander_input = Gui.input({ text = tostring(state.wander_wait or 0) })

    local skin_chk = Gui.checkbox("Enable skinning", state.skin_enable)
    local disk_chk = Gui.checkbox("Use floating disk", state.use_disk)

    Gui.label("Loot script:")
    local loot_input = Gui.input({ text = state.loot_script or "eloot" })

    Gui.separator()

    -- Profile management
    Gui.label("Profiles")
    local prof_hbox = Gui.hbox()
    local prof_input = Gui.input({ placeholder = "profile name" })
    local save_prof_btn = Gui.button("Save Profile")
    local load_prof_btn = Gui.button("Load Profile")

    Gui.separator()
    local save_btn = Gui.button("Save & Close")

    win:set_root(root)

    -- Callbacks
    skin_chk:on_change(function(v) state.skin_enable = v end)
    disk_chk:on_change(function(v) state.use_disk = v end)

    save_prof_btn:on_click(function()
        local name = prof_input:get_text()
        if name and name ~= "" then
            config.save_profile(state, name)
        end
    end)

    load_prof_btn:on_click(function()
        local name = prof_input:get_text()
        if name and name ~= "" then
            local profile = config.load_profile(name)
            if profile then
                for k, v in pairs(profile) do state[k] = v end
                respond("[bigshot] Loaded profile: " .. name)
            end
        end
    end)

    save_btn:on_click(function()
        state.rest_room = rest_room_input:get_text() or ""
        state.rest_till_exp = tonumber(exp_input:get_text()) or 80
        state.rest_till_mana = tonumber(mana_input:get_text()) or 80
        state.rest_till_spirit = tonumber(spirit_input:get_text()) or 100
        state.rest_till_percentstamina = tonumber(stam_input:get_text()) or 80
        state.hunting_room_id = tonumber(hunt_room_input:get_text()) or 0
        state.hunting_boundaries = {}
        for id in (bounds_input:get_text() or ""):gmatch("[^,]+") do
            local n = tonumber(id:match("^%s*(.-)%s*$"))
            if n then state.hunting_boundaries[#state.hunting_boundaries + 1] = n end
        end
        state.wander_wait = tonumber(wander_input:get_text()) or 0
        state.loot_script = loot_input:get_text() or "eloot"
        config.save(state)
        respond("[bigshot] Settings saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
