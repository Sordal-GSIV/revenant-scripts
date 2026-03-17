local settings = require("settings")

local M = {}

function M.open(state)
    local win = Gui.window("ELoot Settings", { width = 600, height = 500 })
    local root = Gui.vbox()

    -- Tab buttons
    local tabs = Gui.hbox()
    local loot_tab_btn = Gui.button("* Loot")
    local skin_tab_btn = Gui.button("Skin")
    local current_tab = "loot"
    tabs:add(loot_tab_btn)
    tabs:add(skin_tab_btn)
    root:add(tabs)

    root:add(Gui.separator())

    -- Loot tab content
    root:add(Gui.label("Loot Types (comma-separated):"))
    local loot_types_input = Gui.input({
        text = table.concat(state.loot_types or {}, ",")
    })
    root:add(loot_types_input)
    root:add(Gui.label("Exclude items containing:"))
    local exclude_input = Gui.input({
        text = table.concat(state.loot_exclude or {}, ",")
    })
    root:add(exclude_input)
    local use_disk_chk = Gui.checkbox("Use floating disk", state.use_disk)
    root:add(use_disk_chk)
    local defensive_chk = Gui.checkbox("Switch to defensive stance", state.loot_defensive)
    root:add(defensive_chk)
    root:add(Gui.label("Overflow container:"))
    local overflow_input = Gui.input({ text = state.overflow_container or "" })
    root:add(overflow_input)

    root:add(Gui.separator())

    -- Skin settings
    root:add(Gui.label("Skinning"))
    local skin_chk = Gui.checkbox("Enable skinning", state.skin_enable)
    root:add(skin_chk)
    local skin_kneel_chk = Gui.checkbox("Kneel to skin", state.skin_kneel)
    root:add(skin_kneel_chk)
    root:add(Gui.label("Skin weapon:"))
    local skin_weapon_input = Gui.input({ text = state.skin_weapon or "" })
    root:add(skin_weapon_input)
    root:add(Gui.label("Skin sheath:"))
    local skin_sheath_input = Gui.input({ text = state.skin_sheath or "" })
    root:add(skin_sheath_input)

    root:add(Gui.separator())

    -- Sell settings
    root:add(Gui.label("Sell Settings"))
    root:add(Gui.label("Sell container:"))
    local sell_container_input = Gui.input({ text = state.sell_container or "" })
    root:add(sell_container_input)
    root:add(Gui.label("Sell exclude (comma-sep):"))
    local sell_exclude_input = Gui.input({
        text = table.concat(state.sell_exclude or {}, ",")
    })
    root:add(sell_exclude_input)
    root:add(Gui.label("Appraise gemshop min:"))
    local sell_appraise_gemshop_input = Gui.input({ text = tostring(state.sell_appraise_gemshop or "") })
    root:add(sell_appraise_gemshop_input)
    root:add(Gui.label("Appraise pawnshop min:"))
    local sell_appraise_pawnshop_input = Gui.input({ text = tostring(state.sell_appraise_pawnshop or "") })
    root:add(sell_appraise_pawnshop_input)

    root:add(Gui.separator())

    -- Boxes settings
    root:add(Gui.label("Boxes"))
    local locksmith_pool_chk = Gui.checkbox("Use locksmith pool", state.sell_locksmith_pool)
    root:add(locksmith_pool_chk)
    local locksmith_chk = Gui.checkbox("Use town locksmith", state.sell_locksmith)
    root:add(locksmith_chk)
    local pool_tip_hbox = Gui.hbox()
    pool_tip_hbox:add(Gui.label("Pool tip:"))
    local locksmith_pool_tip_input = Gui.input({ text = tostring(state.locksmith_pool_tip or "") })
    pool_tip_hbox:add(locksmith_pool_tip_input)
    local locksmith_pool_tip_percent_chk = Gui.checkbox("Tip as percent", state.locksmith_pool_tip_percent)
    pool_tip_hbox:add(locksmith_pool_tip_percent_chk)
    root:add(pool_tip_hbox)

    root:add(Gui.separator())
    local save_btn = Gui.button("Save & Close")
    root:add(save_btn)

    win:set_root(root)

    -- Callbacks
    use_disk_chk:on_change(function(v) state.use_disk = v end)
    defensive_chk:on_change(function(v) state.loot_defensive = v end)
    skin_chk:on_change(function(v) state.skin_enable = v end)
    skin_kneel_chk:on_change(function(v) state.skin_kneel = v end)
    locksmith_pool_chk:on_change(function(v) state.sell_locksmith_pool = v end)
    locksmith_chk:on_change(function(v) state.sell_locksmith = v end)
    locksmith_pool_tip_percent_chk:on_change(function(v) state.locksmith_pool_tip_percent = v end)

    save_btn:on_click(function()
        -- Parse comma-separated inputs
        state.loot_types = {}
        for t in (loot_types_input:get_text() or ""):gmatch("[^,]+") do
            state.loot_types[#state.loot_types + 1] = t:match("^%s*(.-)%s*$")
        end
        state.loot_exclude = {}
        for t in (exclude_input:get_text() or ""):gmatch("[^,]+") do
            state.loot_exclude[#state.loot_exclude + 1] = t:match("^%s*(.-)%s*$")
        end
        state.overflow_container = overflow_input:get_text() or ""
        state.skin_weapon = skin_weapon_input:get_text() or ""
        state.skin_sheath = skin_sheath_input:get_text() or ""
        -- Sell settings
        state.sell_container = sell_container_input:get_text() or ""
        state.sell_exclude = {}
        for t in (sell_exclude_input:get_text() or ""):gmatch("[^,]+") do
            state.sell_exclude[#state.sell_exclude + 1] = t:match("^%s*(.-)%s*$")
        end
        state.sell_appraise_gemshop = tonumber(sell_appraise_gemshop_input:get_text()) or 0
        state.sell_appraise_pawnshop = tonumber(sell_appraise_pawnshop_input:get_text()) or 0
        -- Boxes settings
        state.locksmith_pool_tip = tonumber(locksmith_pool_tip_input:get_text()) or 0
        settings.save(state)
        respond("[eloot] Settings saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
