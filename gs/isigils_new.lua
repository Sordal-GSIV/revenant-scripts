--- @revenant-script
--- name: isigils_new
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Guardians of Sunfist sigil maintenance - keeps configured sigils active
--- tags: GoS, sigils, society
--- @lic-certified: complete 2026-03-19
---
--- Usage:
---   ;isigils_new        - Run with current settings
---   ;isigils_new setup  - Configure sigils (GUI or text fallback)
---   ;isigils_new help   - Show help with per-sigil costs

-- ── Sigil definitions ────────────────────────────────────────────────────────

local SIGIL_DATA = {
    { num = 9703, name = "Sigil of Contact",          desc = "Activates ESP Net",                                           mana = 1,  stam = 0,  dur = "19min" },
    { num = 9704, name = "Sigil of Resolve",           desc = "Adds half Sunfist rank to Climbing/Swimming/Survival",       mana = 0,  stam = 5,  dur = "90sec" },
    { num = 9705, name = "Sigil of Minor Bane",        desc = "+5 AS, Adds 10 CER damage weighting vs hated foes",         mana = 3,  stam = 3,  dur = "60sec" },
    { num = 9706, name = "Sigil of Bandages",          desc = "Act without breaking bandaged wounds",                       mana = 0,  stam = 10, dur = "5min"  },
    { num = 9707, name = "Sigil of Defense",           desc = "Adds 1 DS per Sunfist rank",                                mana = 5,  stam = 5,  dur = "5min"  },
    { num = 9708, name = "Sigil of Offense",           desc = "Adds 1 AS per Sunfist rank",                                mana = 5,  stam = 5,  dur = "5min"  },
    { num = 9710, name = "Sigil of Minor Protection",  desc = "+5 DS, Adds 10 CER damage padding",                         mana = 5,  stam = 10, dur = "60sec" },
    { num = 9711, name = "Sigil of Focus",             desc = "Adds 1 TD per Sunfist rank",                                mana = 5,  stam = 5,  dur = "60sec" },
    { num = 9713, name = "Sigil of Mending",           desc = "+15 hp regen per pulse, eat all herbs in 3sec",             mana = 10, stam = 15, dur = "10min" },
    { num = 9714, name = "Sigil of Concentration",     desc = "+5 mana per pulse",                                         mana = 0,  stam = 30, dur = "10min" },
    { num = 9715, name = "Sigil of Major Bane",        desc = "+10 AS, Adds 10 CER crit weighting vs hated foes",          mana = 10, stam = 10, dur = "60sec" },
    { num = 9716, name = "Sigil of Determination",     desc = "Ignore moderate injuries for casting, etc",                  mana = 0,  stam = 30, dur = "5min"  },
    { num = 9717, name = "Sigil of Health",            desc = "Recover 15 HP or half of HP (whichever is greater)",         mana = 10, stam = 20, dur = "instant" },
    { num = 9718, name = "Sigil of Power",             desc = "Convert 50 stamina to 25 mana",                             mana = 0,  stam = 50, dur = "instant" },
    { num = 9719, name = "Sigil of Major Protection",  desc = "+10 DS, Adds 10 CER crit padding",                          mana = 10, stam = 15, dur = "60sec" },
}

-- Quick lookup by num
local SIGIL_BY_NUM = {}
for _, s in ipairs(SIGIL_DATA) do
    SIGIL_BY_NUM[s.num] = s
end

-- Mutually exclusive pairs
local EXCLUSIVE_PAIRS = {
    { 9705, 9715 },  -- minor bane vs major bane
    { 9710, 9719 },  -- minor protection vs major protection
}

-- ── Default settings ─────────────────────────────────────────────────────────

local DEFAULTS = {
    health_threshold           = 70,   -- % health to trigger Sigil of Health (9717)
    health_min_stamina         = 30,   -- absolute stamina required for Sigil of Health
    mana_threshold             = 70,   -- % mana to trigger Sigil of Power (9718)
    mana_min_stamina           = 70,   -- % stamina required for Sigil of Power
    determination_min_stamina  = 30,   -- absolute stamina required for Sigil of Determination (9716)
    reserve_mana               = 0,    -- never cast if mana would drop below this
    reserve_stamina            = 0,    -- never cast if stamina would drop below this
}

-- ── Settings load/save ───────────────────────────────────────────────────────

local function load_settings()
    local settings = {}

    -- Sigil enable booleans
    for _, s in ipairs(SIGIL_DATA) do
        local key = "sigil_" .. s.num
        local val = CharSettings[key]
        settings[s.num] = (val == "true")
    end

    -- Config values
    for key, default in pairs(DEFAULTS) do
        local raw = CharSettings["isigils_" .. key]
        if raw and raw ~= "" then
            settings[key] = tonumber(raw) or default
        else
            settings[key] = default
        end
    end

    return settings
end

local function save_settings(settings)
    for _, s in ipairs(SIGIL_DATA) do
        CharSettings["sigil_" .. s.num] = settings[s.num] and "true" or "false"
    end
    for key, _ in pairs(DEFAULTS) do
        CharSettings["isigils_" .. key] = tostring(settings[key] or DEFAULTS[key])
    end
end

-- ── Conditional casting logic ────────────────────────────────────────────────

--- Check if we can afford a spell respecting global resource reserves.
--- Conditional sigils (9716, 9717, 9718) use their own minimums instead.
local function can_afford_with_reserves(sigil_entry, settings)
    -- Conditional sigils have their own separate resource checks
    if sigil_entry.num == 9716 or sigil_entry.num == 9717 or sigil_entry.num == 9718 then
        return true
    end

    -- CRITICAL: Force fresh resource readings before checking reserves
    -- (mirrors the thread-safe fix in the original .lic)
    waitrt(); waitcastrt()

    local res_mana = settings.reserve_mana or 0
    local res_stam = settings.reserve_stamina or 0

    if sigil_entry.mana > 0 then
        if mana() < (sigil_entry.mana + res_mana) then return false end
    end
    if sigil_entry.stam > 0 then
        if stamina() < (sigil_entry.stam + res_stam) then return false end
    end

    return true
end

--- Should we cast Sigil of Power (9718)? Mana below threshold, stamina % sufficient.
local function should_cast_power(settings)
    local threshold = settings.mana_threshold or 70
    local min_stam_pct = settings.mana_min_stamina or 70

    waitrt(); waitcastrt()
    local max_stam = max_stamina() or 1
    local current_stam_pct = math.floor(stamina() / max_stam * 100)
    local current_mana_pct = math.floor(mana() / (max_mana() or 1) * 100)

    return current_mana_pct < threshold and current_stam_pct >= min_stam_pct
end

--- Should we cast Sigil of Health (9717)? Health below threshold, stamina sufficient.
local function should_cast_health(settings)
    local threshold = settings.health_threshold or 70
    local min_stam = settings.health_min_stamina or 30

    local current_hp_pct = math.floor(health() / (max_health() or 1) * 100)
    return current_hp_pct < threshold and stamina() >= min_stam
end

--- Should we cast Sigil of Determination (9716)?
--- Check for head/eye injuries level 2+, or combined arm/hand injuries >= 3.
local function should_cast_determination(settings)
    local min_stam = settings.determination_min_stamina or 30
    if stamina() < min_stam then return false end

    -- Check head or eye injuries at level 2+
    local head_max = math.max(
        Wounds.head or 0, Scars.head or 0,
        Wounds.leftEye or 0, Scars.leftEye or 0,
        Wounds.rightEye or 0, Scars.rightEye or 0
    )
    if head_max > 1 then return true end

    -- Check arm/hand injuries that prevent casting
    local left_max = math.max(
        Wounds.leftArm or 0, Wounds.leftHand or 0,
        Scars.leftArm or 0, Scars.leftHand or 0
    )
    local right_max = math.max(
        Wounds.rightArm or 0, Wounds.rightHand or 0,
        Scars.rightArm or 0, Scars.rightHand or 0
    )

    return (left_max + right_max) >= 3
end

-- ── Help ─────────────────────────────────────────────────────────────────────

local function show_help()
    respond("")
    respond("iSigils - Guardians of Sunfist Sigil Upkeep")
    respond("Usage:")
    respond("   ;" .. Script.name .. "          run with current settings")
    respond("   ;" .. Script.name .. " setup    configure sigils")
    respond("   ;" .. Script.name .. " help     show this message")
    respond("")
    respond("Available sigils:")
    for _, s in ipairs(SIGIL_DATA) do
        local cost_str = string.format("%dm/%ds", s.mana, s.stam)
        respond(string.format("  %d: %-30s  Cost: %-8s  Duration: %s", s.num, s.name, cost_str, s.dur))
    end
    respond("")
    respond("Conditional sigils:")
    respond("  9716 (Determination): Casts when head/eye wounds >= 2 or arm/hand combined >= 3")
    respond("  9717 (Health):        Casts when HP % < threshold and stamina >= minimum")
    respond("  9718 (Power):         Casts when Mana % < threshold and stamina % >= minimum")
    respond("")
    respond("Resource reserves:")
    respond("  reserve_mana / reserve_stamina prevent casting non-conditional sigils")
    respond("  if resources would drop below the reserve amount.")
    respond("")
end

-- ── GUI setup ────────────────────────────────────────────────────────────────

local function gui_setup(settings)
    local win = Gui.window("iSigils - Guardians of Sunfist Sigil Upkeep", { width = 700, height = 600, resizable = true })
    local root = Gui.vbox()
    local scroll = Gui.scroll(root)

    -- Header
    root:add(Gui.section_header("Sigil Configuration"))

    -- Store checkbox/input refs for saving
    local checkboxes = {}
    local inputs = {}

    for _, s in ipairs(SIGIL_DATA) do
        local row = Gui.hbox()

        -- Checkbox for enabling sigil
        local label_text = string.format("%d: %s (%dm/%ds, %s)", s.num, s.name, s.mana, s.stam, s.dur)
        local cb = Gui.checkbox(label_text, settings[s.num] or false)
        checkboxes[s.num] = cb
        row:add(cb)

        -- Conditional sigil threshold inputs
        if s.num == 9717 then -- Sigil of Health
            row:add(Gui.label("  HP %:"))
            local hp_input = Gui.input({ text = tostring(settings.health_threshold or 70), placeholder = "70" })
            inputs["health_threshold"] = hp_input
            row:add(hp_input)
            row:add(Gui.label("  Min Stam:"))
            local stam_input = Gui.input({ text = tostring(settings.health_min_stamina or 30), placeholder = "30" })
            inputs["health_min_stamina"] = stam_input
            row:add(stam_input)
        elseif s.num == 9718 then -- Sigil of Power
            row:add(Gui.label("  Mana %:"))
            local mana_input = Gui.input({ text = tostring(settings.mana_threshold or 70), placeholder = "70" })
            inputs["mana_threshold"] = mana_input
            row:add(mana_input)
            row:add(Gui.label("  Min Stam %:"))
            local stam_input = Gui.input({ text = tostring(settings.mana_min_stamina or 70), placeholder = "70" })
            inputs["mana_min_stamina"] = stam_input
            row:add(stam_input)
        elseif s.num == 9716 then -- Sigil of Determination
            row:add(Gui.label("  Min Stam:"))
            local stam_input = Gui.input({ text = tostring(settings.determination_min_stamina or 30), placeholder = "30" })
            inputs["determination_min_stamina"] = stam_input
            row:add(stam_input)
        end

        root:add(row)
    end

    -- Real-time mutual exclusion: checking one unchecks the other (mirrors GTK signal_connect toggled)
    for _, pair in ipairs(EXCLUSIVE_PAIRS) do
        local cb_a = checkboxes[pair[1]]
        local cb_b = checkboxes[pair[2]]
        if cb_a and cb_b then
            cb_a:on_change(function(checked) if checked then cb_b:set_checked(false) end end)
            cb_b:on_change(function(checked) if checked then cb_a:set_checked(false) end end)
        end
    end

    -- Separator
    root:add(Gui.separator())

    -- Global reserves section
    root:add(Gui.section_header("Global Reserves (non-conditional sigils only)"))
    root:add(Gui.label("Power, Health, and Determination use their own minimums above."))

    local reserve_row = Gui.hbox()
    reserve_row:add(Gui.label("Reserve Mana:"))
    local res_mana_input = Gui.input({ text = tostring(settings.reserve_mana or 0), placeholder = "0" })
    inputs["reserve_mana"] = res_mana_input
    reserve_row:add(res_mana_input)
    reserve_row:add(Gui.label("  Reserve Stamina:"))
    local res_stam_input = Gui.input({ text = tostring(settings.reserve_stamina or 0), placeholder = "0" })
    inputs["reserve_stamina"] = res_stam_input
    reserve_row:add(res_stam_input)
    root:add(reserve_row)

    -- Save button
    local save_btn = Gui.button("Save and Close")
    save_btn:on_click(function()
        -- Collect checkbox states
        for _, s in ipairs(SIGIL_DATA) do
            settings[s.num] = checkboxes[s.num]:get_checked()
        end

        -- Enforce mutual exclusion on save
        for _, pair in ipairs(EXCLUSIVE_PAIRS) do
            if settings[pair[1]] and settings[pair[2]] then
                -- Keep first, disable second
                settings[pair[2]] = false
            end
        end

        -- Collect input values
        for key, input_widget in pairs(inputs) do
            local val = tonumber(input_widget:get_text()) or DEFAULTS[key] or 0
            settings[key] = val
        end

        save_settings(settings)
        echo("Settings saved.")
        win:close()
    end)
    root:add(save_btn)

    win:set_root(scroll)
    win:show()
    Gui.wait(win, "close")
end

-- ── Text-mode setup fallback ─────────────────────────────────────────────────

local function text_setup(settings)
    respond("Current sigil configuration:")
    respond("")
    for _, s in ipairs(SIGIL_DATA) do
        local state = settings[s.num] and "ON" or "off"
        local cost_str = string.format("%dm/%ds", s.mana, s.stam)
        respond(string.format("  %d: %-30s [%3s]  Cost: %-8s  Duration: %s", s.num, s.name, state, cost_str, s.dur))
    end
    respond("")
    respond("Thresholds:")
    respond("  health_threshold:          " .. tostring(settings.health_threshold))
    respond("  health_min_stamina:        " .. tostring(settings.health_min_stamina))
    respond("  mana_threshold:            " .. tostring(settings.mana_threshold))
    respond("  mana_min_stamina:          " .. tostring(settings.mana_min_stamina))
    respond("  determination_min_stamina: " .. tostring(settings.determination_min_stamina))
    respond("  reserve_mana:              " .. tostring(settings.reserve_mana))
    respond("  reserve_stamina:           " .. tostring(settings.reserve_stamina))
    respond("")
    respond("To toggle a sigil:  CharSettings['sigil_9703'] = 'true'")
    respond("To set a threshold: CharSettings['isigils_health_threshold'] = '50'")
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local arg1 = (Script.vars[1] or ""):lower()

if arg1 == "help" then
    show_help()
    exit()
elseif arg1 == "setup" then
    local settings = load_settings()
    -- Try GUI, fall back to text
    local ok, err = pcall(function()
        gui_setup(settings)
    end)
    if not ok then
        echo("GUI not available (" .. tostring(err) .. "), using text mode.")
        text_setup(settings)
    end
    exit()
end

-- ── Main sigil maintenance loop ──────────────────────────────────────────────

local settings = load_settings()

echo("iSigils active. Maintaining " .. (function()
    local count = 0
    for _, s in ipairs(SIGIL_DATA) do
        if settings[s.num] then count = count + 1 end
    end
    return count
end)() .. " sigils.")

while true do
    if dead() then exit() end

    -- Synchronize with roundtime
    waitrt()
    waitcastrt()

    for _, s in ipairs(SIGIL_DATA) do
        if settings[s.num] then
            local spell = Spell[s.num]
            if spell and spell.known and not spell.active then
                -- Refresh RT sync before each check
                waitrt()
                waitcastrt()

                -- Check affordability
                if spell:affordable() then
                    -- Check global reserves (skipped for conditional sigils)
                    if can_afford_with_reserves(s, settings) then
                        local should_cast = true

                        -- Conditional sigil checks
                        if s.num == 9718 then
                            should_cast = should_cast_power(settings)
                        elseif s.num == 9717 then
                            should_cast = should_cast_health(settings)
                        elseif s.num == 9716 then
                            should_cast = should_cast_determination(settings)
                        end

                        if should_cast then
                            -- Final safety affordability check before casting
                            if spell:affordable() then
                                spell:cast()
                                waitrt()
                                waitcastrt()
                                pause(0.1)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Longer sleep between full loops to prevent resource thrashing
    pause(2)
end
