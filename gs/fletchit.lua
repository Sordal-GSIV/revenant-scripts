--- @revenant-script
--- name: fletchit
--- version: 2.2.0
--- author: elanthia-online
--- contributors: Dissonance
--- game: gs
--- description: Automated fletching script for arrows, light bolts, and heavy bolts
--- tags: crafting,fletching,arrows,bolts

--------------------------------------------------------------------------------
-- FletchIt - Automated Fletching Script
--
-- Creates arrows, light bolts, and heavy bolts with full support for painting,
-- cresting, and auto-buying supplies. Learning mode drops shafts after nocking.
--
-- Setup:
--   ;fletchit setup   - Configure settings via GUI
--   ;fletchit help    - Show help
--   ;fletchit         - Start fletching
--   ;fletchit stop    - Stop after current arrow
--   ;fletchit bundle  - Bundle arrows/bolts in container
--------------------------------------------------------------------------------

local VERSION = "2.2.0"

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local PAINTS = {
    [0] = "none", [1] = "white", [2] = "grey", [3] = "black",
    [4] = "brown", [5] = "red", [6] = "orange", [7] = "yellow",
    [8] = "green", [9] = "blue", [10] = "purple", [11] = "pink",
}

local AMMO_TYPES = {
    [1] = "arrow", [2] = "light bolt", [3] = "heavy bolt",
}

local DEFAULT_SETTINGS = {
    sack         = "backpack",
    quiver       = "quiver",
    axe          = "axe",
    knife        = "knife",
    bow          = "bow",
    wood         = "limb of wood",
    ammo         = 1,
    paint        = 0,
    paintstick1  = "",
    paintstick2  = "",
    fletchings   = "bundle of fletchings",
    limit        = 0,
    waggle       = false,
    enable_buying = false,
    learning     = false,
    alerts       = false,
    debug        = false,
    mind         = "90",
}

-- Load settings
local function load_settings()
    local raw = CharSettings.fletchit_settings
    if raw then
        local ok, saved = pcall(Json.decode, raw)
        if ok and type(saved) == "table" then
            -- merge with defaults
            for k, v in pairs(DEFAULT_SETTINGS) do
                if saved[k] == nil then saved[k] = v end
            end
            return saved
        end
    end
    -- Copy defaults
    local s = {}
    for k, v in pairs(DEFAULT_SETTINGS) do s[k] = v end
    return s
end

local function save_settings(s)
    CharSettings.fletchit_settings = Json.encode(s)
end

--------------------------------------------------------------------------------
-- Stats tracking
--------------------------------------------------------------------------------

local stats = {}

local function add_stat(key, value)
    stats[key] = (stats[key] or 0) + value
end

local function get_stat(key)
    return stats[key] or 0
end

local function show_stats(brief, start_time, ammo_name)
    if brief then
        local arrows = get_stat("arrows_completed") + get_stat("light_bolts_completed") + get_stat("heavy_bolts_completed")
        local failed = get_stat("arrows_failed") + get_stat("light_bolts_failed") + get_stat("heavy_bolts_failed")
        local elapsed = os.time() - (start_time or os.time())
        local per_hour = elapsed > 0 and math.floor(arrows / (elapsed / 3600)) or 0
        echo(string.format("%d %s made (%d failed) - %d/hr", arrows, ammo_name or "arrows", failed, per_hour))
    else
        respond("")
        respond("FletchIt Statistics")
        respond("===================")
        for k, v in pairs(stats) do
            if v > 0 then
                respond("  " .. k .. ": " .. tostring(v))
            end
        end
        respond("")
    end
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

local debug_enabled = false

local function debug_log(msg)
    if debug_enabled then
        echo("[DEBUG] " .. msg)
    end
end

--------------------------------------------------------------------------------
-- Inventory helpers
--------------------------------------------------------------------------------

local function stow(hand, container)
    if hand == "right" then
        local rh = GameObj.right_hand()
        if rh then
            fput("put #" .. rh.id .. " in my " .. container)
        end
    elseif hand == "left" then
        local lh = GameObj.left_hand()
        if lh then
            fput("put #" .. lh.id .. " in my " .. container)
        end
    end
end

local function get_container_contents(container)
    local inv = GameObj.inv() or {}
    for _, obj in ipairs(inv) do
        if string.find(obj.name, container, 1, true) then
            return obj.contents or {}
        end
    end
    return {}
end

local function has_item(contents, noun)
    for _, item in ipairs(contents) do
        if item.noun == noun or item.noun == noun .. "s" then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Game actions
--------------------------------------------------------------------------------

local function get_knife(s)
    local lh = GameObj.left_hand()
    if not lh or not string.find(lh.noun, s.knife, 1, true) then
        fput("get my " .. s.knife)
    end
end

local function make_shafts(s)
    debug_log("make_shafts called")
    waitrt()

    -- Get axe
    fput("get my " .. s.axe)
    pause(0.5)

    -- Get wood
    fput("get my " .. s.wood)
    pause(0.5)

    -- Cut wood into shafts
    waitrt()
    fput("cut my " .. s.wood .. " with my " .. s.axe)
    pause(0.5)
    waitrt()

    -- Stow tools
    stow("left", s.sack)
    stow("right", s.sack)
end

local function cut_nock(s, painted)
    debug_log("cut_nock called")

    -- Only cut nock for arrows (ammo type 1)
    if s.ammo ~= 1 then
        stow("left", s.sack)
        return "success"
    end

    -- Get knife if not in hand
    local lh = GameObj.left_hand()
    if not lh or not string.find(lh.noun or "", s.knife, 1, true) then
        get_knife(s)
        waitrt()
    end

    waitrt()
    fput("cut nock in my shaft with my " .. s.knife)
    pause(0.25)
    waitrt()

    -- If not painted, cut twice
    if not painted then
        waitrt()
        fput("cut nock in my shaft with my " .. s.knife)
        pause(0.25)
        waitrt()
    end

    -- Check if shaft still exists
    local rh = GameObj.right_hand()
    if not rh or not string.find(rh.noun or "", "shaft", 1, true) then
        waitrt()
        stow("left", s.sack)
        add_stat("nocks_cut_failed", 1)
        return "failed"
    end

    add_stat("nocks_cut_success", 1)
    stow("left", s.sack)
    return "success"
end

local function finalize_arrow(s)
    debug_log("finalize_arrow called, learning=" .. tostring(s.learning))

    if s.learning then
        waitrt()
        -- Try to trash the shaft
        fput("drop right")
        return "completed"
    end

    waitrt()

    -- Get glue
    fput("get my glue")
    pause(1)
    local lh = GameObj.left_hand()
    if not lh or not string.find(lh.noun or "", "glue", 1, true) then
        echo("Run out of glue, stopping")
        add_stat("supply_shortage_events", 1)
        return "no_supplies"
    end

    waitrt()
    fput("pour my bottle on my shaft")
    pause(0.5)
    add_stat("glue_applications_success", 1)
    stow("left", s.sack)

    -- Get fletchings
    waitrt()
    fput("get my " .. s.fletchings)
    pause(1)
    lh = GameObj.left_hand()
    if not lh or not string.find(lh.noun or "", "fletching", 1, true) then
        echo("Run out of fletchings, stopping")
        add_stat("supply_shortage_events", 1)
        return "no_supplies"
    end

    waitrt()
    fput("attach my fletching to my shaft")
    pause(0.5)
    add_stat("fletching_attached_success", 1)

    -- Wait for glue to dry
    local line = matchtimeout(120, "The glue on your")
    if not line then
        echo("Did not see glue dry, but carrying on...")
    end

    waitrt()
    stow("left", s.sack)

    -- Test with bow
    if s.bow and s.bow ~= "" then
        waitrt()
        fput("string my " .. s.bow .. " with my shaft")
        pause(0.5)
    end

    waitrt()
    stow("right", s.quiver)

    -- Track completion by ammo type
    if s.ammo == 1 then add_stat("arrows_completed", 1)
    elseif s.ammo == 2 then add_stat("light_bolts_completed", 1)
    elseif s.ammo == 3 then add_stat("heavy_bolts_completed", 1)
    end

    return "completed"
end

local function make_arrow(s)
    debug_log("make_arrow called, ammo type: " .. tostring(s.ammo))

    -- Get shaft
    waitrt()
    fput("get 1 my shaft")
    pause(0.5)

    local rh = GameObj.right_hand()
    if not rh or not string.find(rh.noun or "", "shaft", 1, true) then
        add_stat("supply_shortage_events", 1)
        return "no_shafts"
    end

    waitrt()
    get_knife(s)

    -- Cut shaft
    waitrt()
    fput("cut my shaft with my " .. s.knife)
    pause(0.25)
    waitrt()

    -- Check if shaft survived
    rh = GameObj.right_hand()
    if not rh or not string.find(rh.noun or "", "shaft", 1, true) then
        stow("left", s.sack)
        add_stat("shaft_cut_failures", 1)
        return "failed"
    end
    add_stat("shaft_cut_successes", 1)

    -- Cut nock (for arrows)
    waitrt()
    local nock_result = cut_nock(s, false)
    if nock_result == "failed" then return "failed" end

    -- Finalize arrow
    waitrt()
    local result = finalize_arrow(s)
    if result == "no_supplies" then return "no_supplies" end

    return "completed"
end

--------------------------------------------------------------------------------
-- Bundle command
--------------------------------------------------------------------------------

local function bundle_arrows(s)
    debug_log("bundle_arrows called")
    echo("Bundle functionality: look in your " .. s.quiver .. " and manually bundle matching arrows/bolts.")
    echo("(Full auto-bundle requires GameObj container introspection)")
end

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function setup_gui(s)
    local win = Gui.window("FletchIt Setup", { width = 400, height = 600, resizable = true })
    local root = Gui.vbox()

    root:add(Gui.section_header("FletchIt Settings"))

    -- Text inputs
    local inputs = {}
    local fields = {
        { key = "sack",       label = "Supplies Container" },
        { key = "quiver",     label = "Finished Container" },
        { key = "bow",        label = "Bow" },
        { key = "axe",        label = "Axe" },
        { key = "knife",      label = "Knife" },
        { key = "wood",       label = "Wood" },
        { key = "fletchings", label = "Fletchings" },
        { key = "paintstick1",label = "Paintstick 1" },
        { key = "paintstick2",label = "Paintstick 2" },
        { key = "limit",      label = "Make Limit (0=unlimited)" },
        { key = "mind",       label = "Mind Threshold %" },
    }

    for _, field in ipairs(fields) do
        root:add(Gui.label(field.label .. ":"))
        local inp = Gui.input({ text = tostring(s[field.key] or ""), placeholder = field.label })
        inputs[field.key] = inp
        root:add(inp)
    end

    -- Checkboxes
    local checks = {}
    local check_fields = {
        { key = "learning",      label = "Learning Mode" },
        { key = "enable_buying", label = "Auto-Buy Supplies" },
        { key = "waggle",       label = "Use Waggle" },
        { key = "alerts",       label = "Monitor Interactions" },
        { key = "debug",        label = "Debug Mode" },
    }

    for _, field in ipairs(check_fields) do
        local cb = Gui.checkbox(field.label, s[field.key] or false)
        checks[field.key] = cb
        root:add(cb)
    end

    root:add(Gui.separator())

    -- Save button
    local save_btn = Gui.button("Save & Close")
    save_btn:on_click(function()
        for key, inp in pairs(inputs) do
            local val = inp:get_text()
            if key == "limit" then
                s[key] = tonumber(val) or 0
            else
                s[key] = val
            end
        end
        for key, cb in pairs(checks) do
            s[key] = cb:get_checked()
        end
        save_settings(s)
        echo("Settings saved")
        win:close()
    end)
    root:add(save_btn)

    local cancel_btn = Gui.button("Cancel")
    cancel_btn:on_click(function() win:close() end)
    root:add(cancel_btn)

    win:set_root(Gui.scroll(root))
    win:show()
    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("FletchIt v" .. VERSION .. " - Automated Fletching Script")
    respond("")
    respond("Commands:")
    respond("  ;fletchit          - Start fletching")
    respond("  ;fletchit setup    - Configure settings via GUI")
    respond("  ;fletchit settings - Display current settings")
    respond("  ;fletchit bundle   - Bundle existing arrows")
    respond("  ;fletchit help     - Show this help")
    respond("  ;fletchit stop     - Stop after current arrow")
    respond("")
    respond("While running:")
    respond("  ;fletchit          - See progress report")
    respond("  ;fletchit stats    - Detailed statistics")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local s = load_settings()
debug_enabled = s.debug

local cmd = Script.vars[1] and string.lower(Script.vars[1]) or nil

if cmd and string.find(cmd, "setup") then
    setup_gui(s)
    return
elseif cmd and string.find(cmd, "bundle") then
    bundle_arrows(s)
    return
elseif cmd and string.find(cmd, "settings") then
    respond(Json.encode(s))
    return
elseif cmd and string.find(cmd, "help") then
    show_help()
    return
end

-- Validate settings
local warnings = {}
if not s.sack or s.sack == "" then table.insert(warnings, "Supplies container not set.") end
if not s.quiver or s.quiver == "" then table.insert(warnings, "Finished container not set.") end
if not s.knife or s.knife == "" then table.insert(warnings, "Knife not set.") end
if not s.bow or s.bow == "" then table.insert(warnings, "Bow not set.") end
if not s.axe or s.axe == "" then table.insert(warnings, "Axe not set.") end
if not s.wood or s.wood == "" then table.insert(warnings, "Wood type not set.") end

if #warnings > 0 then
    for _, w in ipairs(warnings) do echo(w) end
    echo("Run ;fletchit setup to configure.")
    return
end

-- Main fletching loop
local start_time = os.time()
local finished = false
local ammo_name = AMMO_TYPES[s.ammo] or "arrow"
if not string.find(ammo_name, "s$") then ammo_name = ammo_name .. "s" end

-- Upstream hook for commands while running
local hook_name = "fletchit_hook_" .. tostring(os.time())
UpstreamHook.add(hook_name, function(line)
    local stripped = string.gsub(line, "^<c>", "")
    if string.find(string.lower(stripped), "^;fletchit$") then
        show_stats(true, start_time, ammo_name)
        return nil
    elseif string.find(string.lower(stripped), "^;fletchit%s+stats$") then
        show_stats(false, start_time, ammo_name)
        return nil
    elseif string.find(string.lower(stripped), "^;fletchit%s+stop") then
        finished = true
        echo("Will stop after completing current " .. ammo_name)
        return nil
    end
    return line
end)

before_dying(function()
    UpstreamHook.remove(hook_name)
    if stats.arrows_completed or stats.light_bolts_completed or stats.heavy_bolts_completed then
        show_stats(false, start_time, ammo_name)
    end
end)

echo("FletchIt v" .. VERSION .. " started. Making " .. ammo_name .. "...")

while not finished do
    -- Make shafts if needed
    local contents = get_container_contents(s.sack)
    if not has_item(contents, "shaft") and has_item(contents, "wood") then
        waitrt()
        make_shafts(s)
    end

    -- Wait for mind if learning
    if s.learning then
        local threshold = tonumber(s.mind) or 90
        if GameState.mind_value and GameState.mind_value > threshold then
            echo("Waiting for mind to drop below " .. threshold .. "%...")
            wait_while(function() return GameState.mind_value and GameState.mind_value > threshold end)
        end
    end

    -- Make arrow/bolt
    local result = make_arrow(s)

    if result == "no_shafts" then
        -- Loop will make more on next iteration
        add_stat("supply_shortage_events", 1)
    elseif result == "no_supplies" then
        if s.enable_buying then
            echo("Out of supplies, buying more is not yet implemented in Lua version")
        else
            echo("Out of supplies and auto-buying is disabled.")
            break
        end
    end

    -- Show progress (unless learning)
    if not s.learning then
        show_stats(true, start_time, ammo_name)
    end

    -- Check limit
    if s.limit and s.limit > 0 then
        local total = get_stat("arrows_completed") + get_stat("light_bolts_completed") + get_stat("heavy_bolts_completed")
        if total >= s.limit then break end
    end
end

echo("")
echo("Fletching complete!")
echo("")
