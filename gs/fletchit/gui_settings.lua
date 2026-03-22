--------------------------------------------------------------------------------
-- FletchIt - GUI Settings Module
--
-- GUI settings window with proper dropdowns for paint (25 entries) and
-- ammo type, plus all text inputs and checkboxes.
--
-- Original author: elanthia-online (Dissonance)
-- Lua conversion preserves all original functionality.
--------------------------------------------------------------------------------

local M = {}

--- Build the paint dropdown options list from the PAINTS table.
-- @param paints table paint color mapping (0-indexed)
-- @return table array of paint name strings, ordered by index
local function build_paint_options(paints)
    local options = {}
    local max_idx = 0
    for k, _ in pairs(paints) do
        if k > max_idx then max_idx = k end
    end
    for i = 0, max_idx do
        if paints[i] then
            table.insert(options, paints[i])
        end
    end
    return options
end

--- Build the ammo type dropdown options list.
-- @param ammo_types table ammo type mapping (1-indexed)
-- @return table array of ammo type strings
local function build_ammo_options(ammo_types)
    local options = {}
    for i = 1, 3 do
        if ammo_types[i] then
            table.insert(options, ammo_types[i])
        end
    end
    return options
end

--- Open the settings GUI window.
-- @param settings table current settings
-- @param paints table paint color mapping
-- @param ammo_types table ammo type mapping
-- @param save_fn function(settings) called to persist settings
-- @param debug_log function
function M.setup_gui(settings, paints, ammo_types, save_fn, debug_log)
    debug_log("setup_gui called")

    local win = Gui.window("FletchIt Setup", { width = 420, height = 720, resizable = true })
    local root = Gui.vbox()

    root:add(Gui.section_header("FletchIt v2.2.0 Settings"))
    root:add(Gui.separator())

    --------------------------------------------------------------------------
    -- Containers section
    --------------------------------------------------------------------------
    root:add(Gui.label("--- Containers ---"))

    local inputs = {}

    -- Supplies Container
    root:add(Gui.label("Supplies Container:"))
    inputs.sack = Gui.input({ text = tostring(settings.sack or ""), placeholder = "backpack" })
    root:add(inputs.sack)

    -- Finished Container (quiver)
    root:add(Gui.label("Finished Container:"))
    inputs.quiver = Gui.input({ text = tostring(settings.quiver or ""), placeholder = "backpack" })
    root:add(inputs.quiver)

    --------------------------------------------------------------------------
    -- Tools section
    --------------------------------------------------------------------------
    root:add(Gui.separator())
    root:add(Gui.label("--- Tools ---"))

    root:add(Gui.label("Bow:"))
    inputs.bow = Gui.input({ text = tostring(settings.bow or ""), placeholder = "bow" })
    root:add(inputs.bow)

    root:add(Gui.label("Axe:"))
    inputs.axe = Gui.input({ text = tostring(settings.axe or ""), placeholder = "handaxe" })
    root:add(inputs.axe)

    root:add(Gui.label("Knife:"))
    inputs.knife = Gui.input({ text = tostring(settings.knife or ""), placeholder = "dagger" })
    root:add(inputs.knife)

    --------------------------------------------------------------------------
    -- Ammo Type (dropdown)
    --------------------------------------------------------------------------
    root:add(Gui.separator())
    root:add(Gui.label("--- Ammunition ---"))

    root:add(Gui.label("Ammo Type:"))
    local ammo_options = build_ammo_options(ammo_types)
    -- editable_combo for ammo type dropdown
    local current_ammo_text = ammo_types[settings.ammo] or "arrow"
    inputs.ammo = Gui.editable_combo({
        text = current_ammo_text,
        hint = "Select ammo type",
        options = ammo_options,
    })
    root:add(inputs.ammo)

    --------------------------------------------------------------------------
    -- Supplies section
    --------------------------------------------------------------------------
    root:add(Gui.separator())
    root:add(Gui.label("--- Supplies ---"))

    root:add(Gui.label("Wood:"))
    inputs.wood = Gui.input({ text = tostring(settings.wood or ""), placeholder = "limb of wood" })
    root:add(inputs.wood)

    -- Paint dropdown (25 entries from the PAINTS table)
    root:add(Gui.label("Paint:"))
    local paint_options = build_paint_options(paints)
    local current_paint_text = paints[settings.paint] or "none"
    inputs.paint = Gui.editable_combo({
        text = current_paint_text,
        hint = "Select paint color",
        options = paint_options,
    })
    root:add(inputs.paint)

    root:add(Gui.label("Paintstick 1:"))
    inputs.paintstick1 = Gui.input({ text = tostring(settings.paintstick1 or ""), placeholder = "Leave blank for none" })
    root:add(inputs.paintstick1)

    root:add(Gui.label("Paintstick 2:"))
    inputs.paintstick2 = Gui.input({ text = tostring(settings.paintstick2 or ""), placeholder = "Leave blank for none" })
    root:add(inputs.paintstick2)

    root:add(Gui.label("Fletchings:"))
    inputs.fletchings = Gui.input({ text = tostring(settings.fletchings or ""), placeholder = "bundle of fletchings" })
    root:add(inputs.fletchings)

    --------------------------------------------------------------------------
    -- Options section
    --------------------------------------------------------------------------
    root:add(Gui.separator())
    root:add(Gui.label("--- Options ---"))

    root:add(Gui.label("Make Limit (blank=unlimited):"))
    inputs.limit = Gui.input({ text = tostring(settings.limit or ""), placeholder = "" })
    root:add(inputs.limit)

    root:add(Gui.label("Mind Threshold %:"))
    inputs.mind = Gui.input({ text = tostring(settings.mind or "60"), placeholder = "60" })
    root:add(inputs.mind)

    -- Checkboxes
    local checks = {}

    checks.enable_buying = Gui.checkbox("Auto-Buy Supplies", settings.enable_buying or false)
    root:add(checks.enable_buying)

    checks.learning = Gui.checkbox("Learning Mode", settings.learning or false)
    root:add(checks.learning)

    checks.waggle = Gui.checkbox("Use Waggle (ewaggle)", settings.waggle or false)
    root:add(checks.waggle)

    checks.alerts = Gui.checkbox("Monitor Interactions", settings.alerts or false)
    root:add(checks.alerts)

    checks.debug = Gui.checkbox("Debug Mode", settings.debug or false)
    root:add(checks.debug)

    --------------------------------------------------------------------------
    -- Buttons
    --------------------------------------------------------------------------
    root:add(Gui.separator())

    local save_btn = Gui.button("Save & Close")
    save_btn:on_click(function()
        -- Collect text inputs
        settings.sack        = string.lower(inputs.sack:get_text():match("^%s*(.-)%s*$"))
        settings.quiver      = string.lower(inputs.quiver:get_text():match("^%s*(.-)%s*$"))
        settings.bow         = string.lower(inputs.bow:get_text():match("^%s*(.-)%s*$"))
        settings.axe         = string.lower(inputs.axe:get_text():match("^%s*(.-)%s*$"))
        settings.knife       = string.lower(inputs.knife:get_text():match("^%s*(.-)%s*$"))
        settings.wood        = string.lower(inputs.wood:get_text():match("^%s*(.-)%s*$"))
        settings.fletchings  = string.lower(inputs.fletchings:get_text():match("^%s*(.-)%s*$"))
        settings.paintstick1 = string.lower(inputs.paintstick1:get_text():match("^%s*(.-)%s*$"))
        settings.paintstick2 = string.lower(inputs.paintstick2:get_text():match("^%s*(.-)%s*$"))
        settings.mind        = inputs.mind:get_text():match("^%s*(.-)%s*$")

        local limit_text = inputs.limit:get_text():match("^%s*(.-)%s*$")
        settings.limit = limit_text

        -- Collect ammo type from combo
        local ammo_text = inputs.ammo:get_text()
        local ammo_val = 1
        for k, v in pairs(ammo_types) do
            if string.lower(v) == string.lower(ammo_text) then
                ammo_val = k
                break
            end
        end
        settings.ammo = ammo_val

        -- Collect paint from combo
        local paint_text = inputs.paint:get_text()
        local paint_val = 0
        for k, v in pairs(paints) do
            if string.lower(v) == string.lower(paint_text) then
                paint_val = k
                break
            end
        end
        settings.paint = paint_val

        -- Collect checkboxes
        settings.enable_buying = checks.enable_buying:get_checked()
        settings.learning      = checks.learning:get_checked()
        settings.waggle        = checks.waggle:get_checked()
        settings.alerts        = checks.alerts:get_checked()
        settings.debug         = checks.debug:get_checked()

        save_fn(settings)
        echo("Settings saved")
        win:close()
    end)
    root:add(save_btn)

    local cancel_btn = Gui.button("Cancel")
    cancel_btn:on_click(function()
        echo("Closed without saving")
        win:close()
    end)
    root:add(cancel_btn)

    win:set_root(Gui.scroll(root))
    win:show()
    Gui.wait(win, "close")
end

return M
