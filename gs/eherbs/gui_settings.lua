local settings = require("settings")

local M = {}

function M.open(state)
    local win = Gui.window("EHerbs Settings", { width = 500, height = 450 })
    local root = Gui.vbox()

    Gui.label("General")
    local buy_chk = Gui.checkbox("Buy missing herbs", state.buy_missing)
    local deposit_chk = Gui.checkbox("Deposit coins after buying", state.deposit_coins)
    local skip_chk = Gui.checkbox("Skip level 1 scars", state.skip_scars)
    local blood_chk = Gui.checkbox("Heal blood only", state.blood_only)
    local container_bar = Gui.hbox()
    Gui.label("Herb container:")
    local container_input = Gui.input({ text = state.herb_container or "herbsack" })

    Gui.separator()
    Gui.label("Preferences")
    local yaba_chk = Gui.checkbox("Use yabathilium first (blood)", state.use_yaba)
    local potions_chk = Gui.checkbox("Try potions before plants", state.use_potions)
    local mending_chk = Gui.checkbox("Use Sigil of Mending", state.use_mending)

    Gui.separator()
    Gui.label("Spells")
    local s650_chk = Gui.checkbox("Cast Aspect of Yierka (650)", state.use_650)
    local s1035_chk = Gui.checkbox("Cast Song of Tonis (1035)", state.use_1035)

    Gui.separator()
    local save_btn = Gui.button("Save & Close")

    win:set_root(root)

    -- Callbacks
    buy_chk:on_change(function(v) state.buy_missing = v end)
    deposit_chk:on_change(function(v) state.deposit_coins = v end)
    skip_chk:on_change(function(v) state.skip_scars = v end)
    blood_chk:on_change(function(v) state.blood_only = v end)
    yaba_chk:on_change(function(v) state.use_yaba = v end)
    potions_chk:on_change(function(v) state.use_potions = v end)
    mending_chk:on_change(function(v) state.use_mending = v end)
    s650_chk:on_change(function(v) state.use_650 = v end)
    s1035_chk:on_change(function(v) state.use_1035 = v end)

    save_btn:on_click(function()
        state.herb_container = container_input:get_text() or "herbsack"
        settings.save(state)
        respond("[eherbs] Settings saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
