--- ELoot GUI settings window
-- Ported from eloot.lic GTK settings UI to Revenant Gui widgets.
-- Provides a tabbed settings window for all ELoot configuration categories.
--
-- Usage:
--   local GuiSettings = require("gs.eloot.gui_settings")
--   GuiSettings.open(data, function(new_settings) ... end)

local M = {}

-- ---------------------------------------------------------------------------
-- Forward-declare lazy requires
-- ---------------------------------------------------------------------------

local function Settings() return require("gs.eloot.settings") end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Create a labeled checkbox row.
-- @param label string display label
-- @param key string settings key
-- @param state table current settings
-- @return table widget, string key
local function make_checkbox(label, key, state)
    local checked = state[key] or false
    return Gui.checkbox(label, checked), key
end

--- Create a labeled text input row.
-- @param label string display label
-- @param key string settings key
-- @param state table current settings
-- @return table widget, string key
local function make_input(label, key, state)
    local value = state[key] or ""
    if type(value) == "table" then
        value = table.concat(value, ", ")
    end
    return Gui.input({ label = label, value = tostring(value) }), key
end

--- Create a labeled number input row.
-- @param label string display label
-- @param key string settings key
-- @param state table current settings
-- @return table widget, string key
local function make_number_input(label, key, state)
    local value = state[key] or 0
    return Gui.input({ label = label, value = tostring(value) }), key
end

--- Create a multi-line list display with add/remove.
-- @param label string display label
-- @param key string settings key
-- @param state table current settings
-- @return table widget, string key
local function make_list_input(label, key, state)
    local items = state[key] or {}
    local value = ""
    if type(items) == "table" then
        value = table.concat(items, "\n")
    end
    return Gui.input({ label = label, value = value, multiline = true, lines = 4 }), key
end

--- Parse a comma/newline-separated string into a list.
local function parse_list(text)
    local result = {}
    if not text or text == "" then return result end
    for item in text:gmatch("[^\n,]+") do
        local trimmed = item:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            result[#result + 1] = trimmed
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Tab builders — each returns a vbox with the controls for that category
-- ---------------------------------------------------------------------------

local function build_looting_tab(state, refs)
    local children = {}

    children[#children + 1] = Gui.label("-- Looting Behavior --")

    local w, k
    w, k = make_checkbox("Enable skinning", "skin_enable", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Skin sheath container", "skin_sheath", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Loot defensively (prone)", "loot_defensive", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Use disk", "use_disk", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Use group disks", "use_disk_group", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Track full sacks", "track_full_sacks", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Loot exclusions (one per line)", "loot_exclude", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Auto-close containers", "auto_close", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Crumbly items", "crumbly", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Unskinnable creatures", "unskinnable", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Unlootable items", "unlootable", state)
    refs[k] = w; children[#children + 1] = w

    return Gui.scroll(Gui.vbox(children))
end

local function build_selling_tab(state, refs)
    local children = {}

    children[#children + 1] = Gui.label("-- Selling Options --")

    local w, k
    w, k = make_list_input("Sell loot types (one per line)", "sell_loot_types", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Sell containers (one per line)", "sell_container", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Sell exclusions (one per line)", "sell_exclude", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Sell shroud items", "sell_shroud", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Sell aspect items", "sell_aspect", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Sell collectibles", "sell_collectibles", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Sell gold rings", "sell_gold_rings", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Bulk gem selling", "bulk_gems", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Keep containers closed", "keep_closed", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_number_input("Gemshop appraise limit", "sell_appraise_gemshop", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_number_input("Pawnshop appraise limit", "sell_appraise_pawnshop", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Between-sell scripts", "between_scripts", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Share silvers with group", "sell_share_silvers", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Sell on FWI", "sell_fwi", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_number_input("Keep silver amount", "sell_keep_silver", state)
    refs[k] = w; children[#children + 1] = w

    return Gui.scroll(Gui.vbox(children))
end

local function build_skinning_tab(state, refs)
    local children = {}

    children[#children + 1] = Gui.label("-- Skinning Options --")

    local w, k
    w, k = make_checkbox("Enable skinning", "skin_enable", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Kneel to skin", "skin_kneel", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Use spell 604 to skin", "skin_604", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Use Resolve to skin", "skin_resolve", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Skin sheath (sharp)", "skin_sheath", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Skin weapon (sharp)", "skin_weapon", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Skin sheath (blunt)", "skin_sheath_blunt", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Skin weapon (blunt)", "skin_weapon_blunt", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Skin exclusions", "skin_exclude", state)
    refs[k] = w; children[#children + 1] = w

    return Gui.scroll(Gui.vbox(children))
end

local function build_locksmith_tab(state, refs)
    local children = {}

    children[#children + 1] = Gui.label("-- Locksmith Pool Options --")

    local w, k
    w, k = make_checkbox("Use locksmith pool", "sell_locksmith_pool", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Use standard tipping", "use_standard_tipping", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_number_input("Pool tip amount", "sell_locksmith_pool_tip", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Tip is percentage", "sell_locksmith_pool_tip_percent", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_number_input("Withdraw amount for pool", "locksmith_withdraw_amount", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Always check pool", "always_check_pool", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Display box contents", "display_box_contents", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Use locksmith when gem bounty active", "locksmith_when_gem_bounty", state)
    refs[k] = w; children[#children + 1] = w

    return Gui.scroll(Gui.vbox(children))
end

local function build_hoarding_tab(state, refs)
    local children = {}

    children[#children + 1] = Gui.label("-- Gem Hoarding --")

    local w, k
    w, k = make_checkbox("Enable gem hoarding", "gem_horde", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Use locker for gems", "gem_horde_locker", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Gem locker city", "gem_locker_name", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Gem stash container", "gem_horde_container", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Gem source containers", "gem_horde_containers", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Gem bounty turn-in", "gem_horde_turnin", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Hoard everything (gem)", "gem_everything_list", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Gem exclusions", "gem_everything", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Only hoard specific gems", "gem_only_list", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Gem include list", "gem_list", state)
    refs[k] = w; children[#children + 1] = w

    children[#children + 1] = Gui.label("")
    children[#children + 1] = Gui.label("-- Alchemy Hoarding --")

    w, k = make_checkbox("Enable alchemy hoarding", "alchemy_horde", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Use locker for alchemy", "alchemy_horde_locker", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Alchemy locker city", "alchemy_locker_name", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Alchemy stash container", "alchemy_horde_container", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Alchemy source containers", "alchemy_horde_containers", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Hoard everything (alchemy)", "alchemy_everything_list", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Alchemy exclusions", "alchemy_everything", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Only hoard specific reagents", "alchemy_only_list", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_list_input("Alchemy include list", "alchemy_list", state)
    refs[k] = w; children[#children + 1] = w

    children[#children + 1] = Gui.label("")
    children[#children + 1] = Gui.label("Hoarding Notes:")
    children[#children + 1] = Gui.label("  Requires jars to store items")
    children[#children + 1] = Gui.label("  Able to use any size jar")
    children[#children + 1] = Gui.label("  Able to use empty jars for new gems")
    children[#children + 1] = Gui.label("  Does not buy jars")
    children[#children + 1] = Gui.label("  Will skip over full jars")

    return Gui.scroll(Gui.vbox(children))
end

local function build_che_tab(state, refs)
    local children = {}

    children[#children + 1] = Gui.label("-- CHE / House Locker --")

    local w, k
    w, k = make_checkbox("Use house/CHE locker (gem)", "gem_horde_locker_che", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("CHE locker rooms (gem, comma-separated)", "gem_horde_che_rooms", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("CHE entry command (gem)", "gem_horde_che_entry", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("CHE exit command (gem)", "gem_horde_che_exit", state)
    refs[k] = w; children[#children + 1] = w

    children[#children + 1] = Gui.label("")

    w, k = make_checkbox("Use house/CHE locker (alchemy)", "alchemy_horde_locker_che", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("CHE locker rooms (alchemy, comma-separated)", "alchemy_horde_che_rooms", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("CHE entry command (alchemy)", "alchemy_horde_che_entry", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("CHE exit command (alchemy)", "alchemy_horde_che_exit", state)
    refs[k] = w; children[#children + 1] = w

    return Gui.scroll(Gui.vbox(children))
end

local function build_display_tab(state, refs)
    local children = {}

    children[#children + 1] = Gui.label("-- Display / Debug --")

    local w, k
    w, k = make_checkbox("Debug mode", "debug", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Debug to file", "debug_file", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Silence messages", "silence", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Favor left hand", "favor_left", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_checkbox("Log unlootables", "log_unlootables", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Overflow container", "overflow_container", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Secondary overflow", "secondary_overflow", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Coin hand container", "coin_hand_name", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Charm name", "charm_name", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Appraisal container", "appraisal_container", state)
    refs[k] = w; children[#children + 1] = w

    return Gui.scroll(Gui.vbox(children))
end

local function build_bloodband_tab(state, refs)
    local children = {}

    children[#children + 1] = Gui.label("-- Blood Band --")

    local w, k
    w, k = make_checkbox("Use blood band/bracer", "use_bloodbands", state)
    refs[k] = w; children[#children + 1] = w

    w, k = make_input("Blood band item name", "blood_band_name", state)
    refs[k] = w; children[#children + 1] = w

    return Gui.scroll(Gui.vbox(children))
end

-- ---------------------------------------------------------------------------
-- Value collection — read widget values back into a settings table
-- ---------------------------------------------------------------------------

--- Mapping of setting keys to their default type (for parsing).
local BOOLEAN_KEYS = {
    skin_enable = true, skin_kneel = true, skin_604 = true, skin_resolve = true,
    loot_defensive = true, loot_phase = true,
    use_disk = true, use_disk_group = true, track_full_sacks = true,
    favor_left = true, log_unlootables = true,
    sell_shroud = true, sell_aspect = true, sell_collectibles = true,
    sell_gold_rings = true, sell_share_silvers = true, sell_fwi = true,
    keep_closed = true, bulk_gems = true,
    sell_locksmith = true, sell_locksmith_pool = true,
    use_standard_tipping = true, sell_locksmith_pool_tip_percent = true,
    always_check_pool = true, display_box_contents = true,
    locksmith_when_gem_bounty = true,
    gem_horde = true, gem_horde_locker = true, gem_horde_turnin = true,
    gem_everything_list = true, gem_only_list = true,
    gem_horde_locker_che = true,
    alchemy_horde = true, alchemy_horde_locker = true,
    alchemy_everything_list = true, alchemy_only_list = true,
    alchemy_horde_locker_che = true,
    use_bloodbands = true, use_house_locker = true,
    debug = true, debug_file = true, silence = true,
    sigil_determination_on_fail = true,
}

local NUMBER_KEYS = {
    sell_appraise_gemshop = true, sell_appraise_pawnshop = true,
    sell_keep_silver = true, sell_locksmith_pool_tip = true,
    locksmith_withdraw_amount = true, gambling_toss_min = true,
}

local LIST_KEYS = {
    loot_exclude = true, auto_close = true, crumbly = true,
    unskinnable = true, unlootable = true, skin_exclude = true,
    sell_loot_types = true, sell_container = true, sell_exclude = true,
    sell_keep_scrolls = true, sell_appraise_types = true,
    between_scripts = true, hoard_exclusion = true,
    gem_horde_containers = true, gem_everything = true, gem_list = true,
    alchemy_horde_containers = true, alchemy_everything = true, alchemy_list = true,
}

--- Collect values from widget refs back into a settings table.
-- @param refs table { [key] = widget }
-- @param base table original settings for fallback
-- @return table new settings
local function collect_values(refs, base)
    local result = {}
    -- Copy base first
    for k, v in pairs(base) do
        result[k] = v
    end
    -- Override with widget values
    for key, widget in pairs(refs) do
        local val = widget.value
        if val == nil then
            -- Skip unreadable widgets
        elseif BOOLEAN_KEYS[key] then
            if type(val) == "boolean" then
                result[key] = val
            else
                result[key] = val == "true" or val == "on" or val == "yes"
            end
        elseif NUMBER_KEYS[key] then
            result[key] = tonumber(val) or 0
        elseif LIST_KEYS[key] then
            if type(val) == "string" then
                result[key] = parse_list(val)
            elseif type(val) == "table" then
                result[key] = val
            end
        else
            result[key] = val
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Main entry point
-- ---------------------------------------------------------------------------

--- Open the ELoot settings GUI window.
-- @param data table ELoot data state (must contain data.settings)
-- @param on_save function callback receiving new settings table
function M.open(data, on_save)
    local state = data.settings or {}
    local refs = {}  -- key -> widget mapping for value collection

    -- Build tab content
    local tabs = {
        { label = "Looting",    content = build_looting_tab(state, refs) },
        { label = "Selling",    content = build_selling_tab(state, refs) },
        { label = "Skinning",   content = build_skinning_tab(state, refs) },
        { label = "Locksmith",  content = build_locksmith_tab(state, refs) },
        { label = "Hoarding",   content = build_hoarding_tab(state, refs) },
        { label = "CHE",        content = build_che_tab(state, refs) },
        { label = "Display",    content = build_display_tab(state, refs) },
        { label = "Blood Band", content = build_bloodband_tab(state, refs) },
    }

    local tab_bar = Gui.tab_bar(tabs)

    -- Save and Cancel buttons
    local save_btn = Gui.button("Save Settings")
    local cancel_btn = Gui.button("Cancel")

    local button_row = Gui.hbox({ save_btn, cancel_btn })

    local layout = Gui.vbox({
        Gui.label("ELoot Settings v2.7.0"),
        tab_bar,
        button_row,
    })

    local win = Gui.window("ELoot Settings", { width = 600, height = 500, content = layout })

    -- Button callbacks
    save_btn.on_click = function()
        local new_settings = collect_values(refs, state)
        if on_save then
            on_save(new_settings)
        end
        win:close()
    end

    cancel_btn.on_click = function()
        win:close()
    end
end

return M
