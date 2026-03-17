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
    tabs:add(rest_btn)
    tabs:add(hunt_btn)
    tabs:add(cmd_btn)
    tabs:add(misc_btn)
    root:add(tabs)

    root:add(Gui.separator())

    -- Resting tab
    root:add(Gui.label("Resting Settings"))
    local rest_hbox = Gui.hbox()
    rest_hbox:add(Gui.label("Rest room ID:"))
    local rest_room_input = Gui.input({ text = tostring(state.rest_room or "") })
    rest_hbox:add(rest_room_input)
    root:add(rest_hbox)

    root:add(Gui.label("Rest thresholds:"))
    local exp_hbox = Gui.hbox()
    exp_hbox:add(Gui.label("Exp %:"))
    local exp_input = Gui.input({ text = tostring(state.rest_till_exp or 80) })
    exp_hbox:add(exp_input)
    exp_hbox:add(Gui.label("Mana %:"))
    local mana_input = Gui.input({ text = tostring(state.rest_till_mana or 80) })
    exp_hbox:add(mana_input)
    root:add(exp_hbox)

    local spirit_hbox = Gui.hbox()
    spirit_hbox:add(Gui.label("Spirit:"))
    local spirit_input = Gui.input({ text = tostring(state.rest_till_spirit or 100) })
    spirit_hbox:add(spirit_input)
    spirit_hbox:add(Gui.label("Stamina %:"))
    local stam_input = Gui.input({ text = tostring(state.rest_till_percentstamina or 80) })
    spirit_hbox:add(stam_input)
    root:add(spirit_hbox)

    root:add(Gui.separator())

    -- Hunting tab
    root:add(Gui.label("Hunting Settings"))
    local hunt_hbox = Gui.hbox()
    hunt_hbox:add(Gui.label("Hunting room ID:"))
    local hunt_room_input = Gui.input({ text = tostring(state.hunting_room_id or 0) })
    hunt_hbox:add(hunt_room_input)
    root:add(hunt_hbox)

    root:add(Gui.label("Boundaries (comma-separated room IDs):"))
    local bounds_input = Gui.input({
        text = table.concat(state.hunting_boundaries or {}, ",")
    })
    root:add(bounds_input)

    root:add(Gui.label("Wander wait (seconds):"))
    local wander_input = Gui.input({ text = tostring(state.wander_wait or 0) })
    root:add(wander_input)

    local skin_chk = Gui.checkbox("Enable skinning", state.skin_enable)
    root:add(skin_chk)
    local disk_chk = Gui.checkbox("Use floating disk", state.use_disk)
    root:add(disk_chk)

    root:add(Gui.label("Loot script:"))
    local loot_input = Gui.input({ text = state.loot_script or "eloot" })
    root:add(loot_input)

    root:add(Gui.separator())

    -- Profile management
    root:add(Gui.label("Profiles"))
    local prof_hbox = Gui.hbox()
    local prof_input = Gui.input({ placeholder = "profile name" })
    prof_hbox:add(prof_input)
    local save_prof_btn = Gui.button("Save Profile")
    prof_hbox:add(save_prof_btn)
    local load_prof_btn = Gui.button("Load Profile")
    prof_hbox:add(load_prof_btn)
    root:add(prof_hbox)

    root:add(Gui.separator())
    local save_btn = Gui.button("Save & Close")
    root:add(save_btn)

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
