local settings = require("settings")

local M = {}

function M.open(state)
    local win = Gui.window("EHerbs Settings", { width = 520, height = 600 })
    local root = Gui.vbox()

    -- General section
    root:add(Gui.section_header("General"))
    local buy_chk = Gui.checkbox("Buy missing herbs", state.buy_missing)
    root:add(buy_chk)
    local deposit_chk = Gui.checkbox("Deposit coins after buying", state.deposit_coins)
    root:add(deposit_chk)
    local skip_chk = Gui.checkbox("Skip level 1 scars", state.skip_scars)
    root:add(skip_chk)
    local blood_chk = Gui.checkbox("Blood-only mode (default)", state.blood_toggle)
    root:add(blood_chk)
    local debug_chk = Gui.checkbox("Debug mode", state.debug)
    root:add(debug_chk)

    local container_bar = Gui.hbox()
    container_bar:add(Gui.label("Herb container:"))
    local container_input = Gui.input({ text = state.herb_container or "herbsack" })
    container_bar:add(container_input)
    root:add(container_bar)

    local withdraw_bar = Gui.hbox()
    withdraw_bar:add(Gui.label("Withdraw amount:"))
    local withdraw_input = Gui.input({ text = tostring(state.withdraw_amount or 8000) })
    withdraw_bar:add(withdraw_input)
    root:add(withdraw_bar)

    local stock_bar = Gui.hbox()
    stock_bar:add(Gui.label("Stock percent (0=default):"))
    local stock_input = Gui.input({ text = tostring(state.stock_percent or 0) })
    stock_bar:add(stock_input)
    root:add(stock_bar)

    root:add(Gui.separator())

    -- Preferences section
    root:add(Gui.section_header("Herb Preferences"))
    local yaba_chk = Gui.checkbox("Use yabathilium first (blood)", state.use_yaba)
    root:add(yaba_chk)
    local potions_chk = Gui.checkbox("Try potions before plants", state.use_potions)
    root:add(potions_chk)
    local distiller_chk = Gui.checkbox("Use survival kit distiller", state.use_distiller)
    root:add(distiller_chk)

    root:add(Gui.separator())

    -- Spells section
    root:add(Gui.section_header("Spells"))
    local mending_chk = Gui.checkbox("Use Sigil of Mending (9713)", state.use_mending)
    root:add(mending_chk)
    local s650_chk = Gui.checkbox("Cast Aspect of Yierka (650)", state.use_650)
    root:add(s650_chk)
    local s1035_chk = Gui.checkbox("Cast Song of Tonis (1035)", state.use_1035)
    root:add(s1035_chk)

    root:add(Gui.separator())

    -- NPC Healer section
    root:add(Gui.section_header("Cutthroat / NPC Healer"))
    local cutthroat_chk = Gui.checkbox("Heal cutthroat automatically", state.heal_cutthroat)
    root:add(cutthroat_chk)
    local npchealer_chk = Gui.checkbox("Use NPC healer for cutthroat", state.use_npchealer)
    root:add(npchealer_chk)

    root:add(Gui.separator())

    -- Save button
    local save_btn = Gui.button("Save & Close")
    root:add(save_btn)

    win:set_root(Gui.scroll(root))

    -- Callbacks
    buy_chk:on_change(function(v) state.buy_missing = v end)
    deposit_chk:on_change(function(v) state.deposit_coins = v end)
    skip_chk:on_change(function(v) state.skip_scars = v end)
    blood_chk:on_change(function(v) state.blood_toggle = v end)
    debug_chk:on_change(function(v) state.debug = v end)
    yaba_chk:on_change(function(v) state.use_yaba = v end)
    potions_chk:on_change(function(v) state.use_potions = v end)
    distiller_chk:on_change(function(v) state.use_distiller = v end)
    mending_chk:on_change(function(v) state.use_mending = v end)
    s650_chk:on_change(function(v) state.use_650 = v end)
    s1035_chk:on_change(function(v) state.use_1035 = v end)
    cutthroat_chk:on_change(function(v) state.heal_cutthroat = v end)
    npchealer_chk:on_change(function(v) state.use_npchealer = v end)

    save_btn:on_click(function()
        state.herb_container = container_input:get_text() or "herbsack"
        state.withdraw_amount = tonumber(withdraw_input:get_text()) or 8000
        state.stock_percent = tonumber(stock_input:get_text()) or 0
        settings.save(state)
        respond("[eherbs] Settings saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
