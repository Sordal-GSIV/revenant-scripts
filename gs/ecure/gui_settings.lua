local config = require("config")

local M = {}

function M.show(settings)
    local win = Gui.window("ECure Configuration", { width = 500, height = 500, resizable = true })
    local root = Gui.vbox()

    -- Tab bar: Basic | Hunt Mode | Heal Mode
    local tabs = Gui.tab_bar({ "Basic Setup", "Hunt Mode", "Heal Mode" })
    root:add(tabs)

    -- === Basic Setup Tab ===
    local basic = Gui.vbox()

    -- All wounds/scars level
    local global_box = Gui.hbox()
    global_box:add(Gui.label("All Wounds Level (0-3):"))
    local wounds_input = Gui.input({ text = tostring(settings.all_wounds_level or 0), placeholder = "0" })
    global_box:add(wounds_input)
    global_box:add(Gui.label("All Scars Level (0-3):"))
    local scars_input = Gui.input({ text = tostring(settings.all_scars_level or 0), placeholder = "0" })
    global_box:add(scars_input)
    basic:add(global_box)

    -- Mode toggle
    local mode_box = Gui.hbox()
    mode_box:add(Gui.label("Current Mode:"))
    local mode_btn = Gui.button(settings.mode == "hunt" and "Hunt Mode" or "Heal Mode")
    mode_btn:on_click(function()
        settings.mode = settings.mode == "heal" and "hunt" or "heal"
        mode_btn:set_text(settings.mode == "hunt" and "Hunt Mode" or "Heal Mode")
    end)
    mode_box:add(mode_btn)
    basic:add(mode_box)

    -- Checkboxes
    local hnp = Gui.checkbox("Head/Nerve Priority", settings.head_nerve_priority ~= false)
    hnp:on_change(function(v) settings.head_nerve_priority = v end)
    basic:add(hnp)

    local tb = Gui.checkbox("Use Troll's Blood (1125)", settings.use_trolls_blood or false)
    tb:on_change(function(v) settings.use_trolls_blood = v end)
    basic:add(tb)

    local signs = Gui.checkbox("Use CoL Signs", settings.use_signs or false)
    signs:on_change(function(v) settings.use_signs = v end)
    basic:add(signs)

    local alt = Gui.checkbox("Alternative Behavior", settings.alternative_behavior or false)
    alt:on_change(function(v) settings.alternative_behavior = v end)
    basic:add(alt)

    -- Done verb
    local done_box = Gui.hbox()
    done_box:add(Gui.label("Done Verb:"))
    local done_input = Gui.input({ text = settings.done_verb or "", placeholder = "e.g., bow" })
    done_input:on_change(function() settings.done_verb = done_input:get_text() end)
    done_box:add(done_input)
    basic:add(done_box)

    basic:add(Gui.section_header("3=ignore, 0=heal completely"))
    tabs:set_tab_content(1, basic)

    -- === Hunt/Heal Mode Tabs ===
    for tab_idx, mode in ipairs({ "hunt", "heal" }) do
        local mode_vbox = Gui.vbox()
        mode_vbox:add(Gui.section_header(mode:sub(1,1):upper() .. mode:sub(2) .. " Mode Thresholds"))

        local tbl = Gui.table({ columns = { "Body Part", "Wounds", "Scars" } })
        for _, part in ipairs(config.BODY_PARTS) do
            local display = part:gsub("(right)(.*)", "%1 %2"):gsub("(left)(.*)", "%1 %2")
            display = display:sub(1,1):upper() .. display:sub(2)
            local w_lvl = config.wound_level(settings, part, mode)
            local s_lvl = config.scar_level(settings, part, mode)
            tbl:add_row({ display, tostring(w_lvl), tostring(s_lvl) })
        end
        mode_vbox:add(tbl)
        mode_vbox:add(Gui.label("(Edit thresholds via ;ecure --list or per-part CLI)"))
        tabs:set_tab_content(tab_idx + 1, mode_vbox)
    end

    -- Save button
    local save_btn = Gui.button("Save Settings")
    save_btn:on_click(function()
        settings.all_wounds_level = tonumber(wounds_input:get_text()) or 0
        settings.all_scars_level = tonumber(scars_input:get_text()) or 0
        config.save(settings)
        respond("[ecure] Settings saved")
        win:close()
    end)
    root:add(save_btn)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
end

return M
