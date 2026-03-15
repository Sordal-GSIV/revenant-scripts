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

    Gui.separator()

    -- Loot tab content
    Gui.label("Loot Types (comma-separated):")
    local loot_types_input = Gui.input({
        text = table.concat(state.loot_types or {}, ",")
    })
    Gui.label("Exclude items containing:")
    local exclude_input = Gui.input({
        text = table.concat(state.loot_exclude or {}, ",")
    })
    local use_disk_chk = Gui.checkbox("Use floating disk", state.use_disk)
    local defensive_chk = Gui.checkbox("Switch to defensive stance", state.loot_defensive)
    Gui.label("Overflow container:")
    local overflow_input = Gui.input({ text = state.overflow_container or "" })

    Gui.separator()

    -- Skin settings
    Gui.label("Skinning")
    local skin_chk = Gui.checkbox("Enable skinning", state.skin_enable)
    local skin_kneel_chk = Gui.checkbox("Kneel to skin", state.skin_kneel)
    Gui.label("Skin weapon:")
    local skin_weapon_input = Gui.input({ text = state.skin_weapon or "" })
    Gui.label("Skin sheath:")
    local skin_sheath_input = Gui.input({ text = state.skin_sheath or "" })

    Gui.separator()
    local save_btn = Gui.button("Save & Close")

    win:set_root(root)

    -- Callbacks
    use_disk_chk:on_change(function(v) state.use_disk = v end)
    defensive_chk:on_change(function(v) state.loot_defensive = v end)
    skin_chk:on_change(function(v) state.skin_enable = v end)
    skin_kneel_chk:on_change(function(v) state.skin_kneel = v end)

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
        settings.save(state)
        respond("[eloot] Settings saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
