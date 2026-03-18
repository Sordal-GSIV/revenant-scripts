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
    -- Track per-part input widgets so Save can read them
    local part_inputs = {}  -- part_inputs[mode][part] = { wounds = input, scars = input }

    for tab_idx, mode in ipairs({ "hunt", "heal" }) do
        part_inputs[mode] = {}
        local mode_vbox = Gui.vbox()
        mode_vbox:add(Gui.section_header(mode:sub(1,1):upper() .. mode:sub(2) .. " Mode Thresholds (0-3)"))
        mode_vbox:add(Gui.label("3=ignore, 0=heal completely"))

        -- Header row
        local header = Gui.hbox()
        header:add(Gui.label(string.format("%-14s  %-8s  %s", "Body Part", "Wounds", "Scars")))
        mode_vbox:add(header)
        mode_vbox:add(Gui.separator())

        for _, part in ipairs(config.BODY_PARTS) do
            local display = part:gsub("(right)(.*)", "%1 %2"):gsub("(left)(.*)", "%1 %2")
            display = display:sub(1,1):upper() .. display:sub(2)

            local w_lvl = config.wound_level(settings, part, mode)
            local s_lvl = config.scar_level(settings, part, mode)

            local row = Gui.hbox()
            row:add(Gui.label(string.format("%-14s", display)))

            local w_input = Gui.input({ text = tostring(w_lvl), placeholder = "0" })
            local s_input = Gui.input({ text = tostring(s_lvl), placeholder = "0" })

            row:add(w_input)
            row:add(s_input)
            mode_vbox:add(row)

            part_inputs[mode][part] = { wounds = w_input, scars = s_input }
        end

        local scroll = Gui.scroll(mode_vbox)
        tabs:set_tab_content(tab_idx + 1, scroll)
    end

    -- Save button
    local save_btn = Gui.button("Save Settings")
    save_btn:on_click(function()
        settings.all_wounds_level = tonumber(wounds_input:get_text()) or 0
        settings.all_scars_level = tonumber(scars_input:get_text()) or 0

        -- Save per-part threshold values from the editable inputs
        for _, mode in ipairs({ "hunt", "heal" }) do
            if part_inputs[mode] then
                for _, part in ipairs(config.BODY_PARTS) do
                    local pi = part_inputs[mode][part]
                    if pi then
                        local w_val = math.max(0, math.min(3, tonumber(pi.wounds:get_text()) or 0))
                        local s_val = math.max(0, math.min(3, tonumber(pi.scars:get_text()) or 0))
                        settings[part .. "_wounds_" .. mode] = w_val
                        settings[part .. "_scars_" .. mode] = s_val
                    end
                end
            end
        end

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
