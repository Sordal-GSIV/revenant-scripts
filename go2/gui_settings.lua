-- gui_settings.lua — go2 settings GUI (GS and DR aware)

local settings = require("settings")

local M = {}

local function is_gs() return (GameState.game or ""):find("^GS") ~= nil end
local function is_dr() return (GameState.game or ""):find("^DR") ~= nil end
local function is_plat() return (GameState.game or "") == "GSPlat" end
local function is_shattered() return (GameState.game or "") == "GSF" end

local function fmt_delay(state)
    return tostring(state.delay or 0)
end

-------------------------------------------------------------------------------
-- Build the "Misc / General" section
-------------------------------------------------------------------------------

local function build_general_tab(state, uv, local_s, local_uv)
    local vbox = Gui.vbox()

    -- Delay row
    local delay_hbox = Gui.hbox()
    delay_hbox:add(Gui.label("Delay (sec):"))
    local delay_input = Gui.input({ text = fmt_delay(state), placeholder = "0" })
    delay_input:on_change(function(v)
        local n = tonumber(v)
        if n then local_s.delay = n end
    end)
    delay_hbox:add(delay_input)

    -- Typeahead row
    delay_hbox:add(Gui.label("  Typeahead:"))
    local ta_input = Gui.input({ text = tostring(state.typeahead or 0), placeholder = "0" })
    ta_input:on_change(function(v)
        local n = tonumber(v)
        if n then local_s.typeahead = math.max(0, n) end
    end)
    delay_hbox:add(ta_input)
    vbox:add(delay_hbox)

    -- Checkbox row 1
    local cb1 = Gui.hbox()
    local hide_desc_chk = Gui.checkbox("Hide Room Descriptions", state.hide_room_descriptions)
    hide_desc_chk:on_change(function(v) local_s.hide_room_descriptions = v end)
    cb1:add(hide_desc_chk)

    local hide_title_chk = Gui.checkbox("Hide Room Titles", state.hide_room_titles)
    hide_title_chk:on_change(function(v) local_s.hide_room_titles = v end)
    cb1:add(hide_title_chk)

    local echo_chk = Gui.checkbox("Echo Input", state.echo_input)
    echo_chk:on_change(function(v) local_s.echo_input = v end)
    cb1:add(echo_chk)
    vbox:add(cb1)

    -- Checkbox row 2
    local cb2 = Gui.hbox()
    local stop_dead_chk = Gui.checkbox("Stop for Dead", state.stop_for_dead)
    stop_dead_chk:on_change(function(v) local_s.stop_for_dead = v end)
    cb2:add(stop_dead_chk)

    local no_confirm_chk = Gui.checkbox("Disable Confirmation", state.disable_confirm)
    no_confirm_chk:on_change(function(v) local_s.disable_confirm = v end)
    cb2:add(no_confirm_chk)
    vbox:add(cb2)

    -- GS-only options
    if is_gs() then
        vbox:add(Gui.separator())
        vbox:add(Gui.section_header("GemStone IV Options"))

        local gs1 = Gui.hbox()
        local get_silvers_chk = Gui.checkbox("Get Silvers from Bank", state.get_silvers)
        get_silvers_chk:on_change(function(v) local_s.get_silvers = v end)
        gs1:add(get_silvers_chk)

        local ret_silvers_chk = Gui.checkbox("Get Return Trip Silvers", state.get_return_silvers)
        ret_silvers_chk:on_change(function(v) local_s.get_return_silvers = v end)
        gs1:add(ret_silvers_chk)
        vbox:add(gs1)

        local gs2 = Gui.hbox()
        local vaalor_chk = Gui.checkbox("Use Vaalor Shortcut", state.vaalor_shortcut)
        vaalor_chk:on_change(function(v) local_s.vaalor_shortcut = v end)
        gs2:add(vaalor_chk)

        local seeking_chk = Gui.checkbox("Use Voln Seeking", state.use_seeking)
        seeking_chk:on_change(function(v) local_s.use_seeking = v end)
        -- Disable if not Voln
        gs2:add(seeking_chk)
        vbox:add(gs2)

        -- Ice mode
        local ice_hbox = Gui.hbox()
        ice_hbox:add(Gui.label("Ice Mode:"))
        local ice_opts = Gui.editable_combo({ text = local_uv.mapdb_ice_mode or "auto",
                                              options = { "auto", "wait", "run" } })
        ice_opts:on_change(function(v) local_uv.mapdb_ice_mode = v end)
        ice_hbox:add(ice_opts)
        vbox:add(ice_hbox)

        -- Rogue password (only for Rogues)
        if Stats and Stats.profession == "Rogue" then
            local rogue_hbox = Gui.hbox()
            rogue_hbox:add(Gui.label("Rogue Password:"))
            local rogue_input = Gui.input({
                text        = state.rogue_password or "",
                placeholder = "pull, push, tap... (7 actions)",
            })
            rogue_input:on_change(function(v) local_s.rogue_password = v end)
            rogue_hbox:add(rogue_input)
            vbox:add(rogue_hbox)
        end
    end

    -- DR-only options
    if is_dr() then
        vbox:add(Gui.separator())
        vbox:add(Gui.section_header("DragonRealms Options"))
        local dr1 = Gui.hbox()
        dr1:add(Gui.label("Auto Drag (name):"))
        local drag_input = Gui.input({
            text        = state.drag or "",
            placeholder = "character name to drag",
        })
        drag_input:on_change(function(v) local_s.drag = v end)
        dr1:add(drag_input)
        vbox:add(dr1)
    end

    return vbox
end

-------------------------------------------------------------------------------
-- Build the "Portals & Passes" section (GS only)
-------------------------------------------------------------------------------

local function build_portals_tab(state, uv, local_s, local_uv)
    local vbox = Gui.vbox()

    if not is_gs() then
        vbox:add(Gui.label("(Portals & Passes options are GemStone IV only)"))
        return vbox
    end

    -- Urchins / Portmasters
    vbox:add(Gui.section_header("Transport Options"))
    local t1 = Gui.hbox()
    local urchins_chk = Gui.checkbox("Use Urchin Guides", uv.mapdb_use_urchins)
    urchins_chk:on_change(function(v) local_uv.mapdb_use_urchins = v end)
    t1:add(urchins_chk)
    local pm_chk = Gui.checkbox("Use Portmasters", uv.mapdb_use_portmasters)
    pm_chk:on_change(function(v) local_uv.mapdb_use_portmasters = v end)
    t1:add(pm_chk)
    vbox:add(t1)

    -- Caravan to/from SoS
    local t2 = Gui.hbox()
    local car_to_chk = Gui.checkbox("Caravan to SoS", uv.mapdb_car_to_sos)
    car_to_chk:on_change(function(v) local_uv.mapdb_car_to_sos = v end)
    t2:add(car_to_chk)
    local car_from_chk = Gui.checkbox("Caravan from SoS", uv.mapdb_car_from_sos)
    car_from_chk:on_change(function(v) local_uv.mapdb_car_from_sos = v end)
    t2:add(car_from_chk)
    vbox:add(t2)

    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Chronomage Day Pass"))

    local dp1 = Gui.hbox()
    local use_dp_chk = Gui.checkbox("Use Day Pass", uv.mapdb_use_day_pass)
    use_dp_chk:on_change(function(v) local_uv.mapdb_use_day_pass = v end)
    dp1:add(use_dp_chk)
    vbox:add(dp1)

    local dp2 = Gui.hbox()
    dp2:add(Gui.label("Buy Day Pass:"))
    local buy_dp_input = Gui.input({
        text        = uv.mapdb_buy_day_pass or "",
        placeholder = "<on|off|wl,imt;imt,wl;...>",
    })
    buy_dp_input:on_change(function(v) local_uv.mapdb_buy_day_pass = v end)
    dp2:add(buy_dp_input)
    vbox:add(dp2)

    local dp3 = Gui.hbox()
    dp3:add(Gui.label("Pass Container:"))
    local sack_input = Gui.input({
        text        = uv.mapdb_day_pass_sack or "",
        placeholder = "container name",
    })
    sack_input:on_change(function(v) local_uv.mapdb_day_pass_sack = v end)
    dp3:add(sack_input)
    vbox:add(dp3)

    -- FWI Trinket
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Far Wanderer's Isle (FWI)"))
    local fwi_hbox = Gui.hbox()
    fwi_hbox:add(Gui.label("FWI Trinket:"))
    local fwi_input = Gui.input({
        text        = uv.mapdb_fwi_trinket or "",
        placeholder = "trinket name or 'off'",
    })
    fwi_input:on_change(function(v) local_uv.mapdb_fwi_trinket = v end)
    fwi_hbox:add(fwi_input)
    vbox:add(fwi_hbox)

    -- Hinterwilds Gigas
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Hinterwilds Travel"))
    local hw1 = Gui.hbox()
    local gigas_chk = Gui.checkbox("Use Gigas Fragments", state.use_gigas_hwtravel)
    gigas_chk:on_change(function(v) local_s.use_gigas_hwtravel = v end)
    hw1:add(gigas_chk)
    vbox:add(hw1)
    local hw2 = Gui.hbox()
    hw2:add(Gui.label("Min Fragments Before Using:"))
    local gigas_input = Gui.input({
        text        = tostring(state.gigas_min_number or 4),
        placeholder = "4",
    })
    gigas_input:on_change(function(v)
        local n = tonumber(v)
        if n then local_s.gigas_min_number = math.max(4, math.min(20, n)) end
    end)
    hw2:add(gigas_input)
    vbox:add(hw2)

    -- Portals (Plat and Shattered only)
    if is_plat() or is_shattered() then
        vbox:add(Gui.separator())
        vbox:add(Gui.section_header("Portals (Plat / Shattered)"))
        local p1 = Gui.hbox()
        local portals_chk = Gui.checkbox("Use Portals", uv.mapdb_use_portals)
        portals_chk:on_change(function(v) local_uv.mapdb_use_portals = v end)
        p1:add(portals_chk)
        if is_plat() then
            local old_portals_chk = Gui.checkbox("Use Old Portals", uv.mapdb_use_old_portals)
            old_portals_chk:on_change(function(v) local_uv.mapdb_use_old_portals = v end)
            p1:add(old_portals_chk)
            local portal_pass_chk = Gui.checkbox("Have Portal Pass", uv.mapdb_have_portal_pass)
            portal_pass_chk:on_change(function(v) local_uv.mapdb_have_portal_pass = v end)
            p1:add(portal_pass_chk)
        end
        vbox:add(p1)
    end

    return vbox
end

-------------------------------------------------------------------------------
-- Build the "Custom Targets" section
-------------------------------------------------------------------------------

local function build_targets_tab(local_targets)
    local vbox = Gui.vbox()
    vbox:add(Gui.label("Custom targets can be used with ';go2 <name>'"))
    vbox:add(Gui.label("Note: Array targets (multiple rooms) must be set via CLI"))
    vbox:add(Gui.separator())

    -- Table of current targets
    local tbl = Gui.table({ columns = { "Name", "Room ID(s)" } })
    for name, val in pairs(local_targets) do
        local display = type(val) == "table" and table.concat(val, ", ") or tostring(val)
        tbl:add_row({ name, display })
    end
    local scroll = Gui.scroll(tbl)
    vbox:add(scroll)

    -- Add new target
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Add Target"))
    local add_hbox = Gui.hbox()
    local name_input = Gui.input({ placeholder = "target name" })
    add_hbox:add(name_input)
    local room_input = Gui.input({ placeholder = "room ID (or 'current')" })
    add_hbox:add(room_input)
    local add_btn = Gui.button("Add")
    add_hbox:add(add_btn)
    vbox:add(add_hbox)

    add_btn:on_click(function()
        local name = name_input:get_text():match("^%s*(.-)%s*$")
        local room_str = room_input:get_text():match("^%s*(.-)%s*$")
        if name == "" or room_str == "" then
            respond("[go2] Name and room ID required")
            return
        end
        if name:match("^%d+$") then
            respond("[go2] Target name cannot be only digits")
            return
        end
        local room_id
        if room_str:lower() == "current" then
            room_id = Map.current_room()
            if not room_id then
                respond("[go2] Current room unknown")
                return
            end
        else
            room_id = tonumber(room_str)
        end
        if not room_id then
            respond("[go2] Invalid room ID: " .. room_str)
            return
        end
        local room = Map.find_room(room_id)
        if not room then
            respond("[go2] Room " .. room_id .. " not found in map database")
            return
        end
        local existing = local_targets[name]
        if existing then
            -- Append to existing array, or upgrade scalar to array
            if type(existing) == "table" then
                table.insert(existing, room_id)
                local_targets[name] = existing
            else
                local_targets[name] = { existing, room_id }
            end
        else
            local_targets[name] = room_id
        end
        tbl:add_row({ name, tostring(room_id) })
        respond("[go2] Saved target: " .. name .. " = " .. room_id)
    end)

    -- Delete target
    local del_hbox = Gui.hbox()
    local del_input = Gui.input({ placeholder = "target name to delete" })
    del_hbox:add(del_input)
    local del_btn = Gui.button("Delete")
    del_hbox:add(del_btn)
    vbox:add(del_hbox)

    del_btn:on_click(function()
        local name = del_input:get_text():match("^%s*(.-)%s*$")
        if name == "" then return end
        if local_targets[name] then
            local_targets[name] = nil
            tbl:clear()
            for n, v in pairs(local_targets) do
                local d = type(v) == "table" and table.concat(v, ", ") or tostring(v)
                tbl:add_row({ n, d })
            end
            respond("[go2] Deleted target: " .. name)
        else
            respond("[go2] Target not found: " .. name)
        end
    end)

    return vbox
end

-------------------------------------------------------------------------------
-- Public: open the settings window
-------------------------------------------------------------------------------

function M.open(state, uv, targets)
    local win_w = is_gs() and 640 or 420
    local win_h = is_gs() and 580 or 360

    local win = Gui.window("Go2 Settings v2.2.13", { width = win_w, height = win_h, resizable = true })

    -- Deep copy for local edits
    local local_s  = {}
    local local_uv = {}
    local local_t  = {}
    for k, v in pairs(state)   do local_s[k]  = v end
    for k, v in pairs(uv)      do local_uv[k] = v end
    for k, v in pairs(targets) do local_t[k]  = v end

    -- Tab bar
    local tabs = { "General", "Portals & Passes", "Custom Targets" }
    local tab_bar = Gui.tab_bar(tabs)

    tab_bar:set_tab_content(1, build_general_tab(state,   uv, local_s, local_uv))
    tab_bar:set_tab_content(2, build_portals_tab(state,   uv, local_s, local_uv))
    tab_bar:set_tab_content(3, build_targets_tab(local_t))

    local root = Gui.vbox()
    root:add(tab_bar)
    root:add(Gui.separator())

    -- Bottom bar
    local bottom = Gui.hbox()
    bottom:add(Gui.label("Changes only saved when you click Close →"))

    local save_btn = Gui.button("Close & Save")
    save_btn:on_click(function()
        -- Persist char settings
        for k, v in pairs(local_s)  do state[k]  = v end
        settings.save(state)

        -- Persist uservars
        for k, v in pairs(local_uv) do uv[k]     = v end
        settings.save_uservars(uv)

        -- Persist targets
        for k in pairs(targets) do targets[k] = nil end
        for k, v in pairs(local_t) do targets[k] = v end
        settings.save_targets(targets)

        respond("[go2] Settings saved")
        win:close()
    end)
    bottom:add(save_btn)
    root:add(bottom)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
end

return M
