local settings = require("settings")

local M = {}

function M.open(state)
    local win = Gui.window("EHerbs Settings", { width = 500, height = 450 })
    local root = Gui.vbox()

    root:add(Gui.label("General"))
    local buy_chk = Gui.checkbox("Buy missing herbs", state.buy_missing)
    root:add(buy_chk)
    local deposit_chk = Gui.checkbox("Deposit coins after buying", state.deposit_coins)
    root:add(deposit_chk)
    local skip_chk = Gui.checkbox("Skip level 1 scars", state.skip_scars)
    root:add(skip_chk)
    local blood_chk = Gui.checkbox("Heal blood only", state.blood_only)
    root:add(blood_chk)
    local container_bar = Gui.hbox()
    container_bar:add(Gui.label("Herb container:"))
    local container_input = Gui.input({ text = state.herb_container or "herbsack" })
    container_bar:add(container_input)
    root:add(container_bar)

    root:add(Gui.separator())
    root:add(Gui.label("Preferences"))
    local yaba_chk = Gui.checkbox("Use yabathilium first (blood)", state.use_yaba)
    root:add(yaba_chk)
    local potions_chk = Gui.checkbox("Try potions before plants", state.use_potions)
    root:add(potions_chk)
    local mending_chk = Gui.checkbox("Use Sigil of Mending", state.use_mending)
    root:add(mending_chk)

    root:add(Gui.separator())
    root:add(Gui.label("Spells"))
    local s650_chk = Gui.checkbox("Cast Aspect of Yierka (650)", state.use_650)
    root:add(s650_chk)
    local s1035_chk = Gui.checkbox("Cast Song of Tonis (1035)", state.use_1035)
    root:add(s1035_chk)

    root:add(Gui.separator())
    local save_btn = Gui.button("Save & Close")
    root:add(save_btn)

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
