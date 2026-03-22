--- @revenant-script
--- name: dirty_deeds
--- version: 1.1.0
--- author: Dreaven
--- game: gs
--- tags: deeds, deed, landing, icemule, rivers rest, utility
--- description: Comprehensive deed acquisition tool for GemStone IV
---
--- @lic-certified: complete 2026-03-18
--- Original Lich5 author: Dreaven (Tgo01) — dirty-deeds.lic v16
--- Ported to Revenant Lua from dirty-deeds.lic v16
---
--- Changelog:
---   v1.1.0 (2026-03-18): Full parity with lic v16
---     - Implement Confirm/Decline/Use Silver interactive GUI workflow
---     - Implement pre-purchase dwarf ruby flow (upfront confirmation)
---     - Decline removes item set from pool and continues loop (no break)
---     - Add Version History tab (5th tab)
---     - Keep list moved to Settings (global/cross-character, matching original)
---     - Enhanced stats display: per-day metrics, average per deed
---     - Overage display in items table when not using Auto Multiplier
---     - Fix influence stat indexing: inf_stat[2] (bonus) not inf_stat[1] (value)
---     - Stop button during confirmation wait properly aborts
---
--- Features:
---   - Deed cost calculation based on level and current deed count
---   - Gem appraisal system: navigate to gem shops, appraise gems in containers
---   - Multi-town support: Landing, Icemule Trace, River's Rest
---   - Bank operations: withdraw silver, deposit excess
---   - Deed acquisition workflow: buy gems, navigate to temple, offer gems
---   - Statistics tracking: deeds acquired, silver spent, time elapsed
---   - Deed calculator display (cost table)
---   - Settings persistence via CharSettings / Settings
---   - GUI with Confirm/Decline/Use Silver interactive flow
---
--- Usage:
---   ;dirty_deeds          - Open GUI and run
---   ;dirty_deeds setup    - Open GUI in setup mode
---   ;dirty_deeds calc     - Show deed calculator
---   ;dirty_deeds help     - Show help

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local ALL_TOWNS = { "Landing", "Icemule", "River's Rest" }

local AUTO_MULTIPLIER_LOW  = 4.0   -- gems valued < 1000
local AUTO_MULTIPLIER_HIGH = 10.0  -- gems valued >= 1000

local DWARF_RUBY_ORDER          = 14
local DWARF_RUBY_ROOM           = "9269"
local DWARF_RUBY_COST           = 4500
local DWARF_RUBY_ORIGINAL_VALUE = 6000

local LANDING_BANK_ROOM = "400"

-- Town-specific room IDs
local TOWN_DATA = {
    ["Landing"] = {
        deed_room    = "4045",
        appraise_shop = "1776",
        race_bonus   = { "Giant", "Halfling", "Half-Elf", "Dark Elf", "Forest Gnome" },
    },
    ["Icemule"] = {
        deed_room    = "23547",
        appraise_shop = "2464",
        race_bonus   = { "Halfling", "Krolvin", "Sylvan" },
    },
    ["River's Rest"] = {
        deed_room    = "10854",
        appraise_shop = "10935",
        race_bonus   = { "Human", "Krolvin" },
    },
}

-- River's Rest valid gems (shells, beryl, bloodjewel, etc.)
local RIVERREST_GEMS = {
    "amethyst clam shell", "angulate wentletrap shell", "beige clam shell",
    "black helmet shell", "black-spined conch shell", "blue-banded coquina shell",
    "bright noble pectin shell", "blue periwinkle shell", "candystick tellin shell",
    "checkered chiton shell", "crown conch shell", "crown-of-Charl shell",
    "dark brown triton shell", "dovesnail shell", "egg cowrie shell",
    "emperor's crown shell", "empress's crown shell", "fluted limpet shell",
    "giant paper nautilus shell", "golden cowrie shell", "golden triton shell",
    "polished hornsnail shell", "piece of iridescent mother-of-pearl",
    "king helmet shell", "iridescent tempest shell", "large chipped clam shell",
    "large moonsnail shell", "lavender nassa shell", "leopard cowrie shell",
    "lynx cowrie shell", "marlin spike shell", "multi-colored snail shell",
    "opaque spiral shell", "pearl nautilus shell", "pink-banded coquina shell",
    "pink clam shell", "polished batwing chiton shell", "polished black tegula shell",
    "polished green abalone shell", "polished red abalone shell",
    "polished silver abalone shell", "purple-cap cowrie shell",
    "queen helmet shell", "red helmet shell", "ruby-lined nassa shell",
    "sea urchin shell", "silvery clam shell", "snake-head cowrie shell",
    "snow cowrie shell", "Solhaven Bay scallop shell",
    "sparkling silvery conch shell", "speckled conch shell",
    "spiny siren's-comb shell", "spiral turret shell",
    "split-back pink conch shell", "striated abalone shell", "sundial shell",
    "three-lined nassa shell", "tiger cowrie shell", "tiger-striped nautilus shell",
    "translucent golden spiral shell", "yellow-banded coquina shell",
    "yellow helmet shell", "white clam shell", "white gryphon's wing shell",
    "Kezmonian honey beryl", "Selanthan bloodjewel",
    "uncut star-of-Tamzyrr diamond", "dwarf-cut sapphire",
}

-- Build a lookup set for River's Rest gems
local RIVERREST_SET = {}
for _, name in ipairs(RIVERREST_GEMS) do RIVERREST_SET[name] = true end

-- Icemule valid items (wands and lockpicks)
local ICEMULE_ITEMS = {
    "oaken wand", "polished bloodwood wand", "twisted wand", "smooth bone wand",
    "clear glass wand", "pale thanot wand", "iron wand", "silver wand",
    "aquamarine wand", "golden wand", "metal wand", "green coral wand",
    "smooth amber wand", "slender blue wand", "crystal wand", "lockpick",
}

local ICEMULE_SET = {}
for _, name in ipairs(ICEMULE_ITEMS) do ICEMULE_SET[name] = true end

-- ---------------------------------------------------------------------------
-- Utility functions
-- ---------------------------------------------------------------------------

local function add_commas(n)
    local s = tostring(math.floor(n))
    local neg = ""
    if s:sub(1, 1) == "-" then
        neg = "-"
        s = s:sub(2)
    end
    local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if result:sub(1, 1) == "," then result = result:sub(2) end
    return neg .. result
end

local function plural(word, count)
    return count == 1 and word or (word .. "s")
end

--- Calculate GS3 level from NORMAL experience (not ascension).
--- The deed formula uses the GS3-era level tiers.
local function get_gs3_level(experience)
    local level = 0
    local remaining = experience

    local tiers = {
        { 50000,  10000 },
        { 100000, 20000 },
        { 150000, 30000 },
        { 200000, 40000 },
    }

    for _, tier in ipairs(tiers) do
        if remaining <= 0 then break end
        local used = math.min(remaining, tier[1])
        level = level + math.floor(used / tier[2])
        remaining = remaining - used
    end

    if remaining > 0 then
        level = level + math.floor(remaining / 50000)
    end

    return level
end

--- The Landing deed formula (used for all towns).
--- cost = (deeds^2 * 20) + (gs3_level * 100) + 101
local function deed_formula(deeds, gs3_level)
    return (deeds * deeds * 20) + (gs3_level * 100) + 101
end

--- Calculate trade bonus (trading skill + influence bonus, capped at 28, plus racial)
--- NOTE: Stats.enhanced_inf returns {value, bonus} (1-indexed Lua).
---       Ruby original used enhanced_inf[1] (0-indexed = bonus). Lua equivalent is [2].
local function calc_trade_bonus(town)
    local trading_ranks = Skills.trading or 0
    local trading_bonus_val = Skills.to_bonus(trading_ranks) or 0
    local bonus = 0
    if trading_bonus_val > 0 then
        local inf_stat = Stats.enhanced_inf
        local inf_bonus = 0
        if inf_stat then
            -- Lua 1-indexed: [1]=value, [2]=bonus. Ruby 0-indexed [1]=bonus.
            inf_bonus = type(inf_stat) == "table" and (inf_stat[2] or 0) or inf_stat
        end
        bonus = math.max(math.floor((trading_bonus_val + inf_bonus) / 12), 0)
    end
    bonus = math.min(bonus, 28)

    -- Racial bonus (+5)
    local race = Stats.race or ""
    local td = TOWN_DATA[town]
    if td and td.race_bonus then
        for _, r in ipairs(td.race_bonus) do
            if race:lower():find(r:lower(), 1, true) then
                bonus = bonus + 5
                break
            end
        end
    end
    return bonus
end

--- Check if an item is usable for deeds in the given town
local function is_deed_item(item, town)
    local name = item.name or ""
    if town == "Landing" then
        return item.type == "gem"
    elseif town == "Icemule" then
        for _, iname in ipairs(ICEMULE_ITEMS) do
            if name:find(iname, 1, true) then return true end
        end
        return false
    elseif town == "River's Rest" then
        return RIVERREST_SET[name] ~= nil
    end
    return false
end

--- Check if an item name matches any entry in the keep list
local function is_kept_item(name, keep_list)
    if not keep_list or #keep_list == 0 then return false end
    local lower_name = name:lower()
    for _, pattern in ipairs(keep_list) do
        if lower_name:find(pattern:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local state = {
    -- Settings (persisted)
    town            = "Landing",
    container_name  = nil,
    item_multiplier = 3.0,
    deeds_wanted    = 10,
    keep_value      = 20000,
    auto_multiplier = true,
    confirm_required = false,
    accountant      = false,
    use_dwarf_rubies = false,

    -- Runtime
    running         = false,
    stop_requested  = false,
    gs3_level       = 0,
    current_deeds   = 0,
    silvers_needed  = 0,
    trading_bonus   = 0,
    deeds_gained    = 0,
    item_data_cache = {},   -- cached appraisal data by item id

    -- Permission flow (Confirm/Decline/Use Silver)
    perm_pending    = false,
    perm_result     = nil,  -- "yes", "no", "silver"

    -- Running totals for current session
    total_original_value  = 0,
    total_appraised_value = 0,
    total_multiplied_value = 0,
    lost_appraised_value  = 0,
    total_silver_used     = 0,
    total_silver_saved    = 0,
    lost_silver           = 0,
}

-- keep_list is global (shared across characters, stored in Settings)
local keep_list = {}

-- Stats (persisted per-character)
local stats = {}

-- GUI widgets
local gui = {}

-- ---------------------------------------------------------------------------
-- Settings persistence
-- ---------------------------------------------------------------------------

local function load_keep_list()
    -- Keep list is universal (all characters share it) — stored in Settings
    local raw = Settings.dirty_deeds_keep_list
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then
            keep_list = data
        end
    end
    -- Migration: if keep_list is empty, check old per-character CharSettings
    if #keep_list == 0 then
        local cs_raw = CharSettings.dirty_deeds_settings
        if cs_raw then
            local ok, data = pcall(Json.decode, cs_raw)
            if ok and data and type(data.keep_list) == "table" and #data.keep_list > 0 then
                keep_list = data.keep_list
                -- Save migrated list to Settings and clear from CharSettings value
                Settings.dirty_deeds_keep_list = Json.encode(keep_list)
            end
        end
    end
end

local function save_keep_list()
    Settings.dirty_deeds_keep_list = Json.encode(keep_list)
end

local function load_settings()
    local raw = CharSettings.dirty_deeds_settings
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then
            state.town            = data.town or state.town
            state.container_name  = data.container_name or state.container_name
            state.item_multiplier = tonumber(data.item_multiplier) or state.item_multiplier
            state.deeds_wanted    = tonumber(data.deeds_wanted) or state.deeds_wanted
            state.keep_value      = tonumber(data.keep_value) or state.keep_value
            state.auto_multiplier = data.auto_multiplier ~= false
            state.confirm_required = data.confirm_required == true
            state.accountant      = data.accountant == true
            state.use_dwarf_rubies = data.use_dwarf_rubies == true
            echo("Settings loaded.")
        end
    end
end

local function save_settings()
    local data = {
        town            = state.town,
        container_name  = state.container_name,
        item_multiplier = state.item_multiplier,
        deeds_wanted    = state.deeds_wanted,
        keep_value      = state.keep_value,
        auto_multiplier = state.auto_multiplier,
        confirm_required = state.confirm_required,
        accountant      = state.accountant,
        use_dwarf_rubies = state.use_dwarf_rubies,
        -- keep_list no longer stored here; now in Settings
    }
    CharSettings.dirty_deeds_settings = Json.encode(data)
    save_keep_list()
    echo("Settings saved.")
end

local function load_stats()
    local raw = CharSettings.dirty_deeds_stats
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then
            stats = data
        end
    end
    -- Ensure all stat keys exist
    local keys = {
        "lost_silver", "lost_appraised_value", "total_silver_used",
        "total_silver_saved", "total_original_value", "total_appraised_value",
        "deeds_gained_items", "deeds_gained_silver", "total_needed",
        "silvers_spent_dwarf_rubies", "deeds_gained_dwarf_rubies",
        "silvers_lost_dwarf_rubies", "dwarf_ruby_deed_fails",
        "silver_deed_fails", "item_deed_fails", "start_time",
    }
    for _, k in ipairs(keys) do
        if stats[k] == nil then stats[k] = 0 end
    end
end

local function save_stats()
    local total = (stats.deeds_gained_items or 0)
                + (stats.deeds_gained_silver or 0)
                + (stats.deeds_gained_dwarf_rubies or 0)
    if total > 0 then
        CharSettings.dirty_deeds_stats = Json.encode(stats)
        echo("Stats saved.")
    end
end

-- ---------------------------------------------------------------------------
-- Game interaction helpers
-- ---------------------------------------------------------------------------

local function empty_hands()
    local rh = GameObj.right_hand()
    if rh then fput("stow right") end
    local lh = GameObj.left_hand()
    if lh then fput("stow left") end
end

local function must_kneel()
    while not GameState.kneeling do
        waitrt()
        fput("kneel")
        pause(0.2)
    end
end

local function must_stand()
    while not GameState.standing do
        waitrt()
        fput("stand")
        pause(0.1)
    end
end

local function get_deed_cost()
    fput("experience")
    while true do
        local line = get()
        if line and line:find("Long%-Term Exp:") then break end
    end
    local experience = require("lib/gs/experience")
    local exp_val = experience.total or 0
    state.gs3_level = get_gs3_level(exp_val)
    state.current_deeds = experience.deeds or 0
    state.silvers_needed = deed_formula(state.current_deeds, state.gs3_level)
    state.trading_bonus = calc_trade_bonus(state.town)
end

local function go_to_deed_room()
    local td = TOWN_DATA[state.town]
    if not td then return end
    if Script.running("go2") then Script.kill("go2") end
    local room_id = tostring(td.deed_room)
    while tostring(GameState.room_id) ~= room_id do
        if GameState.room_id == nil then move("out") end
        Map.go2(room_id)
        if tostring(GameState.room_id) == room_id then break end
        echo("Someone might be in the deed room. Trying again.")
        pause(2)
    end
    if state.town == "Icemule" then fput("close door") end
end

local function get_landing_bank_balance()
    local balance = 0
    if Script.running("go2") then Script.kill("go2") end
    Map.go2(LANDING_BANK_ROOM)
    fput("deposit all")
    fput("check balance")
    while true do
        local line = get()
        if line then
            local amt = line:match("Your balance is currently at ([%d,]+) silver")
            if amt then
                balance = tonumber(amt:gsub(",", "")) or 0
                break
            elseif line:find("don't seem to have an open account") then
                balance = 0
                break
            end
        end
    end
    return balance
end

--- Find the container GameObj by name from inventory
local function find_container(name)
    if not name then return nil end
    local inv = GameObj.inv()
    if not inv then return nil end
    for _, item in ipairs(inv) do
        if item.name == name then return item end
    end
    -- Partial match fallback
    for _, item in ipairs(inv) do
        if item.name and item.name:find(name, 1, true) then return item end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Appraisal
-- ---------------------------------------------------------------------------

--- Appraise a single item. Returns appraised value (with trading bonus) or 0.
local function appraise_item(item, container)
    -- Check cache
    if state.item_data_cache[item.id] then
        return state.item_data_cache[item.id]
    end

    -- Get the item from container
    local attempts = 0
    while not GameObj.right_hand() and attempts < 5 do
        waitrt()
        fput("get #" .. item.id)
        pause(0.3)
        attempts = attempts + 1
    end

    fput("appraise #" .. item.id)
    local value = 0
    while true do
        local line = get()
        if line then
            local amt = line:match("I'll give you ([%d,]+) silvers? for it")
                or line:match("I'll give you ([%d,]+) silver coins? for it")
                or line:match("I already quoted ([%d,]+) silvers?")
            if amt then
                value = tonumber(amt:gsub(",", "")) or 0
                break
            elseif line:find("I only deal in gems and jewelry") or line:find("I've no use for that") then
                value = 0
                break
            end
        end
    end

    -- Put item back
    if GameObj.right_hand() then
        waitrt()
        fput("put #" .. item.id .. " in #" .. container.id)
        pause(0.3)
    end

    -- Cache it
    if value > 0 then
        state.item_data_cache[item.id] = value
    end
    return value
end

-- ---------------------------------------------------------------------------
-- Deed actions (town-specific temple/offering)
-- ---------------------------------------------------------------------------

local function perform_deed_actions_landing(items, use_silver)
    go_to_deed_room()
    fput("hit chime with mallet")
    fput("hit chime with mallet")
    must_kneel()

    if use_silver then
        fput("drop " .. state.silvers_needed .. " silver")
    else
        for item_id, _ in pairs(items) do
            fput("get #" .. item_id)
            fput("drop #" .. item_id)
        end
    end

    fput("hit chime with mallet")
    if Script.running("go2") then Script.kill("go2") end
    Map.go2("4044")
end

local function perform_deed_actions_icemule(items)
    fput("pull chain")
    fput("open drawer")
    for item_id, _ in pairs(items) do
        fput("get #" .. item_id)
        fput("put #" .. item_id .. " in drawer")
    end
    fput("close drawer")
    fput("open door")
    fput("close door")
end

local function perform_deed_actions_rr(items)
    must_stand()
    must_kneel()
    waitrt()
    fput("look in pool")
    fput("look in pool")
    waitrt()
    fput("touch pool")
    for item_id, _ in pairs(items) do
        fput("get #" .. item_id)
        fput("put #" .. item_id .. " in pool")
    end
    fput("touch pool")
    while true do
        local line = get()
        if line then
            if line:find("He smiles sadly at you") then
                break
            elseif line:find("You are welcome to my garden") then
                while GameObj.right_hand() do
                    waitrt()
                    fput("stow right")
                    pause(0.1)
                end
                fput("touch flower")
                fput("get seed")
                fput("plant seed")
                must_stand()
                move("out")
                break
            end
        end
    end
end

local function perform_deed_actions(items, use_silver)
    if state.town == "Landing" then
        perform_deed_actions_landing(items, use_silver)
    elseif state.town == "Icemule" then
        perform_deed_actions_icemule(items)
    elseif state.town == "River's Rest" then
        perform_deed_actions_rr(items)
    end
end

-- ---------------------------------------------------------------------------
-- Item selection logic
-- ---------------------------------------------------------------------------

--- Given a hash of {item_id => item_stats}, find the best combination whose
--- total multiplied value meets or exceeds the needed amount, wasting as
--- little value as possible.
local function select_items_for_deed(all_items, needed)
    -- Count items
    local count = 0
    for _ in pairs(all_items) do count = count + 1 end

    if count == 0 then return nil end

    if count <= 18 then
        -- Exhaustive combination search for small sets
        local item_list = {}
        for id, data in pairs(all_items) do
            table.insert(item_list, { id = id, data = data })
        end

        local best_total = math.huge
        local best_combo = nil

        -- Generate all combinations using bit manipulation
        local n = #item_list
        local total_combos = (2 ^ n) - 1
        for mask = 1, total_combos do
            local combo_total = 0
            local combo = {}
            for i = 1, n do
                if mask % (2 ^ i) >= 2 ^ (i - 1) then
                    combo_total = combo_total + item_list[i].data.multiplied_value
                    combo[item_list[i].id] = item_list[i].data
                end
            end
            if combo_total >= needed and combo_total < best_total then
                best_total = combo_total
                best_combo = combo
            end
        end
        return best_combo
    else
        -- Greedy approach for larger sets: sort by value ascending, accumulate
        local sorted = {}
        for id, data in pairs(all_items) do
            table.insert(sorted, { id = id, data = data })
        end
        table.sort(sorted, function(a, b)
            return a.data.multiplied_value < b.data.multiplied_value
        end)

        local selected = {}
        local total = 0
        for _, entry in ipairs(sorted) do
            if total >= needed then break end
            selected[entry.id] = entry.data
            total = total + entry.data.multiplied_value
        end

        if total < needed then return nil end

        -- Try to remove unnecessary items (smallest first already in selected)
        local sel_sorted = {}
        for id, data in pairs(selected) do
            table.insert(sel_sorted, { id = id, data = data })
        end
        table.sort(sel_sorted, function(a, b)
            return a.data.multiplied_value < b.data.multiplied_value
        end)
        for _, entry in ipairs(sel_sorted) do
            local new_total = total - entry.data.multiplied_value
            if new_total >= needed then
                selected[entry.id] = nil
                total = new_total
            end
        end

        return selected
    end
end

-- ---------------------------------------------------------------------------
-- Items table display
-- ---------------------------------------------------------------------------

local function show_items_table(items, auto_multi, item_multiplier)
    if not items then return end
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    if count == 0 then return end

    -- Sort by original value
    local sorted = {}
    for _, data in pairs(items) do table.insert(sorted, data) end
    table.sort(sorted, function(a, b) return a.original_value < b.original_value end)

    respond("")
    if auto_multi then
        respond("All items and their values based on the 'Auto Multiplier' settings (" ..
                AUTO_MULTIPLIER_LOW .. "x for <1k, " .. AUTO_MULTIPLIER_HIGH .. "x for >=1k).")
    else
        respond("All items and their values based on your 'Item Multiplier' setting (" ..
                tostring(item_multiplier) .. "x).")
    end
    respond(string.rep("-", 80))
    respond(string.format("%-30s | %14s | %15s | %16s",
        "Name", "Original Value", "Appraised Value", "Multiplied Value"))
    respond(string.rep("-", 80))
    for _, data in ipairs(sorted) do
        respond(string.format("%-30s | %14s | %15s | %16s",
            data.item_name:sub(1, 30),
            add_commas(data.original_value),
            add_commas(data.appraised_value),
            add_commas(data.multiplied_value)))
    end
    respond(string.rep("-", 80))
    respond("")
end

-- ---------------------------------------------------------------------------
-- Permission flow helpers
-- ---------------------------------------------------------------------------

--- Enable/disable confirm buttons in GUI. No-ops when GUI not active.
local function set_confirm_buttons(enable_confirm, enable_use_silver)
    if gui.confirm_btn then
        if enable_confirm then
            gui.confirm_btn:set_text("Confirm")
        end
    end
    -- Note: actual enable/disable state is managed by perm_pending flag.
    -- The buttons' on_click handlers check perm_pending before acting.
end

--- Wait for user to click Confirm, Decline, or Use Silver.
--- Returns: "yes", "no", or "silver". Returns "no" if stop is requested.
local function wait_for_permission()
    state.perm_pending = true
    state.perm_result = nil
    update_gui_info()

    wait_until(function()
        return (not state.perm_pending) or state.stop_requested
    end)

    if state.stop_requested then
        state.perm_pending = false
        return "no"
    end

    return state.perm_result or "no"
end

-- ---------------------------------------------------------------------------
-- Core deed acquisition workflow
-- ---------------------------------------------------------------------------

local function get_item_values(container)
    waitrt()
    fput("open #" .. container.id)
    fput("look in #" .. container.id)
    pause(1)

    local contents = container.contents
    if not contents then
        echo("Container appears empty or contents not available.")
        return {}
    end

    local all_item_stats = {}
    local total_usable = 0
    local appraised_count = 0
    local kv = state.keep_value
    local trading_bonus = state.trading_bonus

    -- Count usable items
    for _, item in ipairs(contents) do
        if is_deed_item(item, state.town) and not is_kept_item(item.name, keep_list) then
            total_usable = total_usable + 1
        end
    end

    echo("Total items: " .. total_usable)

    -- Navigate to appraise shop
    local td = TOWN_DATA[state.town]
    if td then
        if Script.running("go2") then Script.kill("go2") end
        Map.go2(td.appraise_shop)
    end

    empty_hands()

    for _, item in ipairs(contents) do
        if state.stop_requested then break end

        local appraised_value = nil

        if state.use_dwarf_rubies and item.name == "dwarf-cut ruby" then
            appraised_value = math.floor(DWARF_RUBY_ORIGINAL_VALUE * (100 + trading_bonus) / 100)
        elseif is_deed_item(item, state.town) and not is_kept_item(item.name, keep_list) then
            -- Try cache first, otherwise appraise
            if state.item_data_cache[item.id] then
                appraised_value = state.item_data_cache[item.id]
            else
                appraised_value = appraise_item(item, container)
            end
            appraised_count = appraised_count + 1
            local remaining = total_usable - appraised_count
            echo("Appraised " .. appraised_count .. "/" .. total_usable ..
                 " (items remaining to be appraised: " .. remaining .. ")")
        end

        if appraised_value and appraised_value > 0 then
            local original_value
            if state.use_dwarf_rubies and item.name == "dwarf-cut ruby" then
                original_value = DWARF_RUBY_ORIGINAL_VALUE
            else
                original_value = math.floor(appraised_value / (100 + trading_bonus) * 100)
            end

            if appraised_value < kv or (state.use_dwarf_rubies and item.name == "dwarf-cut ruby") then
                local multi
                if state.auto_multiplier and state.town == "Landing" then
                    multi = original_value < 1000 and AUTO_MULTIPLIER_LOW or AUTO_MULTIPLIER_HIGH
                else
                    multi = state.item_multiplier
                end

                all_item_stats[item.id] = {
                    item_name        = item.name,
                    item_id          = item.id,
                    original_value   = original_value,
                    appraised_value  = appraised_value,
                    multiplied_value = math.floor(original_value * multi),
                }
            end
        end
    end

    return all_item_stats
end

--- Pre-purchase dwarf rubies for all desired deeds.
--- Returns true to proceed, false to abort.
local function pre_purchase_dwarf_rubies(container)
    get_deed_cost()
    local starting_deeds = state.current_deeds
    local deeds_wanted   = state.deeds_wanted
    local gs3_level      = state.gs3_level
    local multi          = state.auto_multiplier and AUTO_MULTIPLIER_HIGH or state.item_multiplier

    -- Count rubies already owned in the container
    local dwarf_rubies_owned = 0
    local contents = container.contents or {}
    for _, item in ipairs(contents) do
        if item.name == "dwarf-cut ruby" then
            dwarf_rubies_owned = dwarf_rubies_owned + 1
        end
    end

    -- Calculate total rubies needed and any silver-only deeds
    local begin_deeds = starting_deeds
    local dwarf_rubies_needed = 0
    local silver_needed = 0
    for _ = 1, deeds_wanted do
        local needed = deed_formula(begin_deeds, gs3_level)
        if needed > DWARF_RUBY_COST then
            dwarf_rubies_needed = dwarf_rubies_needed + math.ceil(needed / (DWARF_RUBY_ORIGINAL_VALUE * multi))
        else
            silver_needed = silver_needed + needed
        end
        begin_deeds = begin_deeds + 1
    end

    local net_rubies_needed = math.max(dwarf_rubies_needed - dwarf_rubies_owned, 0)
    local total_silvers_needed = (DWARF_RUBY_COST * net_rubies_needed) + silver_needed

    local word_deeds = plural("deed", deeds_wanted)

    -- Show info to user
    echo("You need a total of " .. dwarf_rubies_needed .. " dwarf-cut rubies to get " ..
         deeds_wanted .. " " .. word_deeds .. ".")
    echo("You currently have " .. dwarf_rubies_owned .. " dwarf-cut rubies.")

    -- Ask for confirmation via GUI
    if state.perm_pending ~= nil then  -- GUI is running
        if net_rubies_needed == 0 and silver_needed == 0 then
            echo("You already have enough dwarf-cut rubies! No silver needed.")
            echo("Click 'Confirm' to proceed or 'Decline'/'Stop' to stop.")
        else
            echo("Total cost will be " .. add_commas(total_silvers_needed) .. " silver.")
            echo("Click 'Confirm' if this cost is acceptable, or 'Decline'/'Stop' to stop.")
        end

        local result = wait_for_permission()
        if result ~= "yes" then
            echo("You have chosen not to buy dwarf-cut rubies.")
            return false
        end
    end

    if net_rubies_needed == 0 and silver_needed == 0 then
        return true
    end

    -- Check bank balance
    local balance = get_landing_bank_balance()
    if balance < total_silvers_needed then
        echo("You do not have enough silver (" .. add_commas(total_silvers_needed) ..
             " needed, " .. add_commas(balance) .. " available).")
        return false
    end

    -- Buy rubies
    if net_rubies_needed > 0 then
        echo("Buying " .. net_rubies_needed .. " dwarf-cut " ..
             plural("ruby", net_rubies_needed) .. ".")
        empty_hands()
        fput("withdraw " .. (DWARF_RUBY_COST * net_rubies_needed) .. " note")
        if Script.running("go2") then Script.kill("go2") end
        Map.go2(DWARF_RUBY_ROOM)
        local rubies_bought = 0
        for _ = 1, net_rubies_needed do
            if state.stop_requested then break end
            fput("order " .. DWARF_RUBY_ORDER)
            fput("buy")
            fput("put my ruby in #" .. container.id)
            rubies_bought = rubies_bought + 1
        end
        stats.silvers_spent_dwarf_rubies = (stats.silvers_spent_dwarf_rubies or 0) +
                                           (DWARF_RUBY_COST * rubies_bought)
    end

    if state.stop_requested then return false end

    -- Deposit all and withdraw silver for direct-silver deeds
    if Script.running("go2") then Script.kill("go2") end
    Map.go2(LANDING_BANK_ROOM)
    fput("deposit all")
    if silver_needed > 0 then
        fput("withdraw " .. silver_needed .. " silver")
    end

    return true
end

local function run_deed_acquisition()
    state.running = true
    state.stop_requested = false
    state.perm_pending = false
    state.perm_result = nil
    state.deeds_gained = 0
    state.total_original_value = 0
    state.total_appraised_value = 0
    state.total_multiplied_value = 0
    state.lost_appraised_value = 0
    state.total_silver_used = 0
    state.total_silver_saved = 0
    state.lost_silver = 0

    -- Validate container
    local container = find_container(state.container_name)
    if not container then
        echo("ERROR: Could not find container '" .. tostring(state.container_name) .. "'.")
        state.running = false
        return
    end

    -- Effective flags (some settings only apply in Landing)
    local effective_auto_multi  = state.auto_multiplier and state.town == "Landing"
    local effective_dwarf       = state.use_dwarf_rubies and state.town == "Landing"
    local effective_accountant  = state.accountant and not effective_dwarf

    -- Pre-purchase dwarf rubies if needed
    if effective_dwarf then
        if not pre_purchase_dwarf_rubies(container) then
            if state.stop_requested then
                echo("Stopped by user.")
            end
            state.running = false
            return
        end
        if state.stop_requested then
            echo("Stopped by user.")
            state.running = false
            return
        end
    end

    -- Calculate deed cost and appraise items
    get_deed_cost()
    update_gui_info()

    local all_items = get_item_values(container)

    if state.stop_requested then
        echo("Stopped by user.")
        state.running = false
        return
    end

    -- Show initial item table (before deed loop)
    if next(all_items) then
        show_items_table(all_items, effective_auto_multi, state.item_multiplier)
        echo("Getting you those deeds!")
    elseif not effective_dwarf then
        echo("There are no items in your container that can be used for a deed in " .. state.town .. ".")
        if not effective_accountant then
            state.running = false
            return
        end
    end

    -- Navigate to deed room for Icemule/River's Rest (stay there for all attempts)
    if state.town == "Icemule" or state.town == "River's Rest" then
        go_to_deed_room()
    end

    -- Main deed loop
    while state.deeds_gained < state.deeds_wanted and not state.stop_requested do
        get_deed_cost()
        update_gui_info()

        if state.deeds_gained >= state.deeds_wanted then
            local word_1 = state.deeds_wanted == 1 and "deed" or "deeds"
            local word_2 = state.deeds_wanted == 1 and "got it" or "got'em"
            echo("You wanted " .. state.deeds_wanted .. " " .. word_1 .. " and you " .. word_2 .. "!")
            break
        end

        local needed = state.silvers_needed
        local items = nil
        local use_silver = false

        -- Determine item set or silver mode
        if effective_dwarf and needed <= DWARF_RUBY_COST then
            -- Cheaper to use silver directly
            use_silver = true
        else
            items = select_items_for_deed(all_items, needed)
        end

        -- If no items found, check if accountant can fall back to silver
        if not items and not use_silver then
            if effective_accountant and state.town == "Landing" then
                echo("Not enough items. Silver needed: " .. add_commas(needed) ..
                     ". Attempting to use silver instead...")
                use_silver = true
            else
                echo("NOT ENOUGH FOR A DEED!")
                echo("Try decreasing the Item Multiplier setting.")
                break
            end
        end

        -- If we have items, calculate totals and check accountant / confirm
        local total_appr = 0
        local total_orig = 0
        local total_mult = 0
        if items and not use_silver then
            for _, data in pairs(items) do
                total_appr = total_appr + data.appraised_value
                total_orig = total_orig + data.original_value
                total_mult = total_mult + data.multiplied_value
            end

            show_items_table(items, effective_auto_multi, state.item_multiplier)

            local saved_by_items = needed - total_appr
            respond("Total Needed For Deed:   " .. add_commas(needed))
            respond("Total Saved Using Items: " .. add_commas(saved_by_items))
            if effective_auto_multi then
                respond("Total Original Value:    " .. add_commas(total_orig))
                respond("Total Appraised Value:   " .. add_commas(total_appr))
                respond("Total Multiplied Value:  " .. add_commas(total_mult))
            else
                local orig_overage = total_orig - math.ceil(needed / state.item_multiplier)
                local appr_overage = total_appr - math.ceil(needed / state.item_multiplier)
                local mult_overage = total_mult - needed
                respond("Total Original Value:    " .. add_commas(total_orig) ..
                        " (" .. add_commas(orig_overage) .. " more than needed)")
                respond("Total Appraised Value:   " .. add_commas(total_appr) ..
                        " (" .. add_commas(appr_overage) .. " more than needed)")
                respond("Total Multiplied Value:  " .. add_commas(total_mult) ..
                        " (" .. add_commas(mult_overage) .. " more than needed)")
            end
            respond("")

            -- Accountant check: silver is cheaper than items
            local accountant_silver = effective_accountant and needed < total_appr and
                                      state.town == "Landing"
            if accountant_silver then
                echo("Using silvers would cost less than the total appraised value of selected items.")
                if state.confirm_required then
                    echo("Click 'Use Silver' to use silver, 'Confirm' to use items, or 'Decline' to skip.")
                else
                    echo("Click 'Use Silver' to use silver for this deed, or the deed loop will use items.")
                end
            end

            -- Interactive confirmation if required or accountant offers silver
            if state.confirm_required or accountant_silver then
                local result = wait_for_permission()
                if result == "no" then
                    -- Decline: remove this item set from pool and continue
                    echo("Declined. Removing these items from this session's pool.")
                    for id, _ in pairs(items) do
                        all_items[id] = nil
                    end
                    goto continue_loop
                elseif result == "silver" then
                    use_silver = true
                end
                -- "yes" falls through to use items
            end
        end

        -- Execute deed attempt
        if use_silver then
            if state.town == "Landing" then
                local balance = get_landing_bank_balance()
                if balance >= needed then
                    fput("withdraw " .. needed .. " silver")
                    Map.go2("goback")
                else
                    echo("Not enough silver in bank! Need " .. add_commas(needed) ..
                         " but have " .. add_commas(balance) .. ".")
                    break
                end
            end

            local before_deeds = state.current_deeds
            perform_deed_actions({}, true)
            get_deed_cost()

            if before_deeds == state.current_deeds then
                state.lost_silver = state.lost_silver + needed
                stats.lost_silver = (stats.lost_silver or 0) + needed
                stats.silver_deed_fails = (stats.silver_deed_fails or 0) + 1
                echo("You did not receive a deed after that silver attempt.")
                echo("While the Landing deed formula is accurate in silver, this shouldn't happen.")
                break
            else
                state.total_silver_used = state.total_silver_used + needed
                stats.total_silver_used = (stats.total_silver_used or 0) + needed
                stats.deeds_gained_silver = (stats.deeds_gained_silver or 0) + 1
                stats.total_needed = (stats.total_needed or 0) + needed
                state.deeds_gained = state.deeds_gained + 1
                if stats.start_time == 0 then stats.start_time = os.time() end
                echo("Deed gained! You're up to " .. state.current_deeds .. " deeds now!")
            end

        elseif items then
            -- Dwarf ruby deed: track silver spent on rubies used
            if effective_dwarf then
                local ruby_count = 0
                for _ in pairs(items) do ruby_count = ruby_count + 1 end
                stats.silvers_spent_dwarf_rubies = (stats.silvers_spent_dwarf_rubies or 0) +
                                                   (ruby_count * DWARF_RUBY_COST)
            end

            local before_deeds = state.current_deeds
            perform_deed_actions(items, false)
            get_deed_cost()

            if before_deeds == state.current_deeds then
                if effective_dwarf then
                    local ruby_count = 0
                    for _ in pairs(items) do ruby_count = ruby_count + 1 end
                    stats.silvers_lost_dwarf_rubies = (stats.silvers_lost_dwarf_rubies or 0) +
                                                      (ruby_count * DWARF_RUBY_COST)
                    stats.dwarf_ruby_deed_fails = (stats.dwarf_ruby_deed_fails or 0) + 1
                else
                    state.lost_appraised_value = state.lost_appraised_value + total_appr
                    stats.lost_appraised_value = (stats.lost_appraised_value or 0) + total_appr
                    stats.item_deed_fails = (stats.item_deed_fails or 0) + 1
                end
                echo("You did not receive a deed after that attempt.")
                echo("While the Landing deed formula is known in silver, item multipliers are approximate.")
                echo("Try decreasing the Item Multiplier and see if that helps get a deed.")
                break
            else
                if effective_dwarf then
                    stats.deeds_gained_dwarf_rubies = (stats.deeds_gained_dwarf_rubies or 0) + 1
                else
                    state.total_original_value = state.total_original_value + total_orig
                    state.total_appraised_value = state.total_appraised_value + total_appr
                    state.total_multiplied_value = state.total_multiplied_value + total_mult
                    state.total_silver_saved = state.total_silver_saved + (needed - total_appr)
                    stats.total_original_value = (stats.total_original_value or 0) + total_orig
                    stats.total_appraised_value = (stats.total_appraised_value or 0) + total_appr
                    stats.total_silver_saved = (stats.total_silver_saved or 0) + (needed - total_appr)
                    stats.deeds_gained_items = (stats.deeds_gained_items or 0) + 1
                end
                stats.total_needed = (stats.total_needed or 0) + needed
                state.deeds_gained = state.deeds_gained + 1
                if stats.start_time == 0 then stats.start_time = os.time() end
                echo("Deed gained! You're up to " .. state.current_deeds .. " deeds now!")

                -- Remove used items from pool so they're not reused
                if not use_silver then
                    for id, _ in pairs(items) do
                        all_items[id] = nil
                    end
                end
            end
        else
            echo("No items available and silver is not an option. Stopping.")
            break
        end

        update_gui_info()
        ::continue_loop::
    end

    -- Show session summary
    if state.deeds_gained > 0 then
        local deeds = state.deeds_gained
        respond("")
        respond("=== Session Summary ===")
        respond("Total Deeds Gained: " .. deeds)
        if state.total_silver_used > 0 then
            respond("Total Silver Used: " .. add_commas(state.total_silver_used))
            respond("Total Silver Saved: " .. add_commas(state.total_silver_used) ..
                    " (saved by using silver instead of items)")
        end
        if state.total_original_value > 0 then
            respond("Total Original Value:   " .. add_commas(state.total_original_value) ..
                    " (avg per deed: " .. add_commas(math.floor(state.total_original_value / deeds)) .. ")")
            respond("Total Appraised Value:  " .. add_commas(state.total_appraised_value) ..
                    " (avg per deed: " .. add_commas(math.floor(state.total_appraised_value / deeds)) .. ")")
            respond("Total Multiplied Value: " .. add_commas(state.total_multiplied_value) ..
                    " (avg per deed: " .. add_commas(math.floor(state.total_multiplied_value / deeds)) .. ")")
        end
        if state.lost_appraised_value > 0 then
            respond("Appraised Value Lost (failed attempts): " .. add_commas(state.lost_appraised_value))
        end
        if state.lost_silver > 0 then
            respond("Silver Lost (failed attempts): " .. add_commas(state.lost_silver))
        end
        respond("")
    end

    -- Return to appraise shop
    if state.town == "Icemule" then fput("open door") end
    local td = TOWN_DATA[state.town]
    if td then
        if Script.running("go2") then Script.kill("go2") end
        Map.go2(td.appraise_shop)
    end

    save_stats()
    state.running = false
end

-- ---------------------------------------------------------------------------
-- Deed Calculator (CLI)
-- ---------------------------------------------------------------------------

local function show_deed_calculator(experience, starting_deeds, ending_deeds, multiplier)
    experience = experience or (require("lib/gs/experience").total or 0)
    starting_deeds = starting_deeds or (require("lib/gs/experience").deeds or 0)
    ending_deeds = ending_deeds or (starting_deeds + 10)
    multiplier = multiplier or 3.0

    local gs3_level = get_gs3_level(experience)
    local deeds_wanted = ending_deeds - starting_deeds
    if deeds_wanted <= 0 then
        echo("Ending deeds must be greater than starting deeds.")
        return
    end

    local total_silvers = 0
    local current = starting_deeds
    respond("")
    respond("=== Deed Calculator ===")
    respond(string.format("Normal Experience:  %s", add_commas(experience)))
    respond(string.format("GS3 Level:          %s", add_commas(gs3_level)))
    respond(string.format("Multiplier:         %.1fx", multiplier))
    respond("")
    respond(string.format("%-6s | %15s | %15s", "Deed#", "Silver Cost", "Item Value"))
    respond(string.rep("-", 42))

    for i = 1, deeds_wanted do
        local cost = deed_formula(current, gs3_level)
        local item_val = math.ceil(cost / multiplier)
        total_silvers = total_silvers + cost
        respond(string.format("%-6d | %15s | %15s", current + 1, add_commas(cost), add_commas(item_val)))
        current = current + 1
    end

    respond(string.rep("-", 42))
    local avg_silver = math.ceil(total_silvers / deeds_wanted)
    local total_item = math.ceil(total_silvers / multiplier)
    local avg_item = math.ceil(total_item / deeds_wanted)
    respond(string.format("Total Silver:       %s (avg: %s per deed)", add_commas(total_silvers), add_commas(avg_silver)))
    respond(string.format("Total Item Value:   %s (avg: %s per deed)", add_commas(total_item), add_commas(avg_item)))
    respond("")
end

-- ---------------------------------------------------------------------------
-- Stats display
-- ---------------------------------------------------------------------------

local function show_stats()
    local total_deeds = (stats.deeds_gained_items or 0) + (stats.deeds_gained_silver or 0) +
                        (stats.deeds_gained_dwarf_rubies or 0)
    if total_deeds == 0 then
        respond("No deeds have been tracked yet. Get a deed to start tracking stats.")
        return
    end

    local total_fails = (stats.item_deed_fails or 0) + (stats.silver_deed_fails or 0) +
                        (stats.dwarf_ruby_deed_fails or 0)
    local total_attempts = total_deeds + total_fails

    local function pct(gained, attempts)
        if attempts == 0 then return "N/A" end
        return string.format("%.2f%%", (gained / attempts) * 100)
    end

    local start_time = stats.start_time or 0
    local total_days = 1
    if start_time > 0 then
        local elapsed = os.time() - start_time
        total_days = math.max(math.floor(elapsed / 86400) + 1, 1)
    end

    local years  = math.floor(total_days / 365)
    local rem    = total_days % 365
    local months = math.floor(rem / 30)
    local days   = rem % 30

    respond("")
    respond("=== Dirty Deeds Statistics ===")
    respond(string.format("Total Deeds Gained:                 %s", add_commas(total_deeds)))
    respond(string.format("Total Failed Attempts:              %s", add_commas(total_fails)))
    respond(string.format("Total Attempts:                     %s", add_commas(total_attempts)))
    respond(string.format("Total Deed Success Rate:            %s", pct(total_deeds, total_attempts)))
    respond(string.format("Total Needed For All Deeds:         %s", add_commas(stats.total_needed or 0)))
    if total_deeds > 0 then
        respond(string.format("Average Needed Per Deed:            %s",
            add_commas(math.floor((stats.total_needed or 0) / total_deeds))))
    end

    -- Date stats
    respond(string.rep("-", 73))
    respond("ALL DATE STATS")
    if start_time > 0 then
        local dt = os.date("*t", start_time)
        respond(string.format("Date Started Using ;dirty-deeds:    %d/%d/%d",
            dt.month, dt.day, dt.year))
        respond(string.format("You Have Been Using Script for:     %d %s / %d %s / %d %s",
            years, plural("Year", years), months, plural("Month", months), days, plural("Day", days)))
    end
    respond(string.format("Average Deeds Gained Per Day:       %.2f", total_deeds / total_days))

    local item_appr_val = stats.total_appraised_value or 0
    local silver_used   = stats.total_silver_used or 0
    local dwarf_spent   = stats.silvers_spent_dwarf_rubies or 0
    if item_appr_val > 0 then
        respond(string.format("Appraised Value Used Per Day:       %s",
            add_commas(math.floor(item_appr_val / total_days))))
    end
    if silver_used > 0 then
        respond(string.format("Silver Used Per Day:                %s",
            add_commas(math.floor(silver_used / total_days))))
    end
    if dwarf_spent > 0 then
        respond(string.format("Dwarf Rubies Value Spent Per Day:   %s",
            add_commas(math.floor(dwarf_spent / total_days))))
    end

    -- Items section
    local item_deeds = stats.deeds_gained_items or 0
    local item_fails = stats.item_deed_fails or 0
    if item_deeds > 0 or item_fails > 0 then
        respond(string.rep("-", 73))
        respond("STATS OF ALL ITEMS USED FOR DEEDS")
        respond(string.format("Deeds Gained:                       %s", add_commas(item_deeds)))
        respond(string.format("Deed Failed Attempts:               %s", add_commas(item_fails)))
        respond(string.format("Total Attempts:                     %s", add_commas(item_deeds + item_fails)))
        respond(string.format("Success Rate:                       %s", pct(item_deeds, item_deeds + item_fails)))
        respond(string.format("Original Value Of All Items Used:   %s", add_commas(stats.total_original_value or 0)))
        respond(string.format("Appraised Value Of All Items Used:  %s", add_commas(item_appr_val)))
        respond(string.format("Total Silver Saved:                 %s", add_commas(stats.total_silver_saved or 0)))
        respond(string.format("Total Appraised Value Lost:         %s", add_commas(stats.lost_appraised_value or 0)))
        if item_deeds > 0 and item_appr_val > 0 then
            respond(string.format("Average Appraised Value Per Deed:   %s",
                add_commas(math.floor(item_appr_val / item_deeds))))
        end
    end

    -- Silver section
    local silver_deeds = stats.deeds_gained_silver or 0
    local silver_fails = stats.silver_deed_fails or 0
    if silver_deeds > 0 or silver_fails > 0 then
        respond(string.rep("-", 73))
        respond("STATS OF ALL SILVER USED FOR DEEDS")
        respond(string.format("Deeds Gained:                       %s", add_commas(silver_deeds)))
        respond(string.format("Deed Failed Attempts:               %s", add_commas(silver_fails)))
        respond(string.format("Total Attempts:                     %s", add_commas(silver_deeds + silver_fails)))
        respond(string.format("Success Rate:                       %s", pct(silver_deeds, silver_deeds + silver_fails)))
        respond(string.format("Total Silver Used:                  %s", add_commas(silver_used)))
        respond(string.format("Total Silver Lost:                  %s", add_commas(stats.lost_silver or 0)))
        if silver_deeds > 0 and silver_used > 0 then
            respond(string.format("Average Silver Per Deed:            %s",
                add_commas(math.floor(silver_used / silver_deeds))))
        end
    end

    -- Dwarf rubies section
    local dwarf_deeds = stats.deeds_gained_dwarf_rubies or 0
    local dwarf_fails = stats.dwarf_ruby_deed_fails or 0
    if dwarf_deeds > 0 or dwarf_fails > 0 then
        respond(string.rep("-", 73))
        respond("STATS FOR DWARF RUBIES USED FOR DEEDS")
        respond(string.format("Deeds Gained:                       %s", add_commas(dwarf_deeds)))
        respond(string.format("Deed Failed Attempts:               %s", add_commas(dwarf_fails)))
        respond(string.format("Total Attempts:                     %s", add_commas(dwarf_deeds + dwarf_fails)))
        respond(string.format("Success Rate:                       %s", pct(dwarf_deeds, dwarf_deeds + dwarf_fails)))
        respond(string.format("Silvers Spent On Dwarf Rubies:      %s", add_commas(dwarf_spent)))
        respond(string.format("Silvers Lost On Failed Attempts:    %s", add_commas(stats.silvers_lost_dwarf_rubies or 0)))
        if dwarf_deeds > 0 and dwarf_spent > 0 then
            respond(string.format("Average Silver Per Deed:            %s",
                add_commas(math.floor(dwarf_spent / dwarf_deeds))))
        end
    end

    respond(string.rep("-", 73))
    respond("")
end

-- ---------------------------------------------------------------------------
-- GUI helpers
-- ---------------------------------------------------------------------------

--- Update the info labels in the GUI
function update_gui_info()
    if gui.info_label then
        gui.info_label:set_text(
            "Trading Bonus: " .. state.trading_bonus .. "%"
            .. "\nGS3 Level: " .. state.gs3_level
            .. "\nCurrent Deeds: " .. state.current_deeds
            .. "\nSilver Needed: " .. add_commas(state.silvers_needed)
        )
    end
    if gui.status_label then
        if state.running then
            if state.perm_pending then
                gui.status_label:set_text("Status: Waiting for your confirmation...")
            else
                gui.status_label:set_text("Status: Running... Deeds gained: " .. state.deeds_gained)
            end
        else
            gui.status_label:set_text("Status: Idle")
        end
    end
    -- Show/hide confirm buttons based on pending state
    if gui.confirm_btn then
        local txt = state.perm_pending and "Confirm" or "Confirm (inactive)"
        gui.confirm_btn:set_text(txt)
    end
end

local function update_calc_display()
    if not gui.calc_label then return end
    local exp_text   = gui.calc_exp_input   and gui.calc_exp_input:get_text()   or ""
    local start_text = gui.calc_start_input and gui.calc_start_input:get_text() or ""
    local end_text   = gui.calc_end_input   and gui.calc_end_input:get_text()   or ""
    local multi_text = gui.calc_multi_input and gui.calc_multi_input:get_text() or ""

    local experience = tonumber(exp_text)   or 0
    local starting   = tonumber(start_text) or 0
    local ending     = tonumber(end_text)   or 1
    local multi      = tonumber(multi_text) or 3.0

    if ending <= starting then ending = starting + 1 end
    local gs3_level   = get_gs3_level(experience)
    local deeds_wanted = ending - starting

    local total_silvers = 0
    local current = starting
    for _ = 1, deeds_wanted do
        total_silvers = total_silvers + deed_formula(current, gs3_level)
        current = current + 1
    end
    local avg_silver = math.ceil(total_silvers / deeds_wanted)
    local total_item = math.ceil(total_silvers / multi)
    local avg_item   = math.ceil(total_item / deeds_wanted)

    gui.calc_label:set_text(
        "GS3 Level: " .. gs3_level
        .. "\nDeeds Wanted: " .. deeds_wanted
        .. "\nTotal Silver Needed: " .. add_commas(total_silvers) .. " (avg: " .. add_commas(avg_silver) .. ")"
        .. "\nTotal Item Value: " .. add_commas(total_item) .. " (avg: " .. add_commas(avg_item) .. ")"
    )
end

local function update_stats_display()
    if not gui.stats_label then return end
    local total_deeds = (stats.deeds_gained_items or 0) + (stats.deeds_gained_silver or 0) +
                        (stats.deeds_gained_dwarf_rubies or 0)
    if total_deeds == 0 then
        gui.stats_label:set_text("Get a deed to start tracking stats.")
        return
    end

    local total_fails = (stats.item_deed_fails or 0) + (stats.silver_deed_fails or 0) +
                        (stats.dwarf_ruby_deed_fails or 0)
    local total_attempts = total_deeds + total_fails

    local function pct(gained, attempts)
        if attempts == 0 then return "N/A" end
        return string.format("%.2f%%", (gained / attempts) * 100)
    end

    local start_time = stats.start_time or 0
    local total_days = 1
    if start_time > 0 then
        local elapsed = os.time() - start_time
        total_days = math.max(math.floor(elapsed / 86400) + 1, 1)
    end
    local years  = math.floor(total_days / 365)
    local rem    = total_days % 365
    local months = math.floor(rem / 30)
    local days   = rem % 30

    local lines = {}
    table.insert(lines, "Total Deeds Gained: " .. add_commas(total_deeds))
    table.insert(lines, "Total Failed: " .. add_commas(total_fails))
    table.insert(lines, "Success Rate: " .. pct(total_deeds, total_attempts))
    table.insert(lines, "Total Needed: " .. add_commas(stats.total_needed or 0))
    table.insert(lines, "")

    if start_time > 0 then
        local dt = os.date("*t", start_time)
        table.insert(lines, string.format("Started: %d/%d/%d", dt.month, dt.day, dt.year))
        table.insert(lines, string.format("Using for: %dy / %dmo / %dd", years, months, days))
        table.insert(lines, string.format("Avg per day: %.2f", total_deeds / total_days))
        table.insert(lines, "")
    end

    local item_deeds = stats.deeds_gained_items or 0
    if item_deeds > 0 then
        local item_appr = stats.total_appraised_value or 0
        table.insert(lines, "--- Items ---")
        table.insert(lines, "  Deeds: " .. add_commas(item_deeds) ..
            " (" .. pct(item_deeds, item_deeds + (stats.item_deed_fails or 0)) .. ")")
        table.insert(lines, "  Appraised Value: " .. add_commas(item_appr))
        if item_deeds > 0 and item_appr > 0 then
            table.insert(lines, "  Avg/deed: " .. add_commas(math.floor(item_appr / item_deeds)))
        end
        if total_days > 0 and item_appr > 0 then
            table.insert(lines, "  Appr/day: " .. add_commas(math.floor(item_appr / total_days)))
        end
        table.insert(lines, "  Silver Saved: " .. add_commas(stats.total_silver_saved or 0))
        table.insert(lines, "  Value Lost: " .. add_commas(stats.lost_appraised_value or 0))
        table.insert(lines, "")
    end

    local silver_deeds = stats.deeds_gained_silver or 0
    if silver_deeds > 0 then
        local su = stats.total_silver_used or 0
        table.insert(lines, "--- Silver ---")
        table.insert(lines, "  Deeds: " .. add_commas(silver_deeds) ..
            " (" .. pct(silver_deeds, silver_deeds + (stats.silver_deed_fails or 0)) .. ")")
        table.insert(lines, "  Silver Used: " .. add_commas(su))
        if silver_deeds > 0 and su > 0 then
            table.insert(lines, "  Avg/deed: " .. add_commas(math.floor(su / silver_deeds)))
        end
        if total_days > 0 and su > 0 then
            table.insert(lines, "  Silver/day: " .. add_commas(math.floor(su / total_days)))
        end
        table.insert(lines, "")
    end

    local dwarf_deeds = stats.deeds_gained_dwarf_rubies or 0
    if dwarf_deeds > 0 then
        local ds = stats.silvers_spent_dwarf_rubies or 0
        table.insert(lines, "--- Dwarf Rubies ---")
        table.insert(lines, "  Deeds: " .. add_commas(dwarf_deeds) ..
            " (" .. pct(dwarf_deeds, dwarf_deeds + (stats.dwarf_ruby_deed_fails or 0)) .. ")")
        table.insert(lines, "  Silver Spent: " .. add_commas(ds))
        if dwarf_deeds > 0 and ds > 0 then
            table.insert(lines, "  Avg/deed: " .. add_commas(math.floor(ds / dwarf_deeds)))
        end
        if total_days > 0 and ds > 0 then
            table.insert(lines, "  Silver/day: " .. add_commas(math.floor(ds / total_days)))
        end
        table.insert(lines, "")
    end

    gui.stats_label:set_text(table.concat(lines, "\n"))
end

local function update_keep_list_display()
    if gui.keep_list_label then
        if #keep_list > 0 then
            local sorted = {}
            for _, v in ipairs(keep_list) do table.insert(sorted, v) end
            table.sort(sorted)
            gui.keep_list_label:set_text("Items to keep:\n" .. table.concat(sorted, ", "))
        else
            gui.keep_list_label:set_text("No items in keep list.")
        end
    end
end

-- ---------------------------------------------------------------------------
-- GUI build
-- ---------------------------------------------------------------------------

local function build_gui()
    local experience = require("lib/gs/experience")
    local win = Gui.window("Dirty Deeds - " .. (GameState.name or ""),
                           { width = 520, height = 680, resizable = true })

    -- Tab bar with 5 pages (matches original)
    local tabs = Gui.tab_bar({ "Get Deeds", "Keep", "Deed Calculator", "Stats", "Version History" })

    -- ==========================================================================
    -- Tab 1: Get Deeds
    -- ==========================================================================
    local get_deeds_box = Gui.vbox()

    -- Info section
    local info_card = Gui.card({ title = "Character Info" })
    gui.info_label = Gui.label("Loading...")
    info_card:add(gui.info_label)
    get_deeds_box:add(info_card)

    -- Settings section
    local settings_card = Gui.card({ title = "Settings" })
    local settings_box = Gui.vbox()

    -- Town selection
    local town_box = Gui.hbox()
    town_box:add(Gui.label("Town: "))
    gui.town_combo = Gui.editable_combo({ text = state.town, options = ALL_TOWNS, hint = "Select town" })
    gui.town_combo:on_change(function()
        local val = gui.town_combo:get_text()
        for _, t in ipairs(ALL_TOWNS) do
            if t == val then
                state.town = val
                break
            end
        end
    end)
    town_box:add(gui.town_combo)
    settings_box:add(town_box)

    -- Container selection
    local container_box = Gui.hbox()
    container_box:add(Gui.label("Container: "))
    local container_names = {}
    local inv = GameObj.inv()
    if inv then
        for _, item in ipairs(inv) do
            if item.contents then
                table.insert(container_names, item.name)
            end
        end
    end
    gui.container_combo = Gui.editable_combo({
        text = state.container_name or (container_names[1] or ""),
        options = container_names,
        hint = "Select container",
    })
    gui.container_combo:on_change(function()
        state.container_name = gui.container_combo:get_text()
    end)
    if not state.container_name and container_names[1] then
        state.container_name = container_names[1]
    end
    container_box:add(gui.container_combo)
    settings_box:add(container_box)

    -- Item Multiplier
    local multi_box = Gui.hbox()
    multi_box:add(Gui.label("Item Multiplier: "))
    gui.multi_input = Gui.input({ text = tostring(state.item_multiplier), placeholder = "3.0" })
    gui.multi_input:on_change(function()
        local val = tonumber(gui.multi_input:get_text())
        if val and val > 0 then state.item_multiplier = val end
    end)
    multi_box:add(gui.multi_input)
    settings_box:add(multi_box)

    -- Deeds Wanted
    local deeds_box_row = Gui.hbox()
    deeds_box_row:add(Gui.label("Deeds Wanted: "))
    gui.deeds_input = Gui.input({ text = tostring(state.deeds_wanted), placeholder = "10" })
    gui.deeds_input:on_change(function()
        local val = tonumber(gui.deeds_input:get_text())
        if val and val > 0 then state.deeds_wanted = math.floor(val) end
    end)
    deeds_box_row:add(gui.deeds_input)
    settings_box:add(deeds_box_row)

    -- Keep Value
    local keep_val_box = Gui.hbox()
    keep_val_box:add(Gui.label("Keep Value (min): "))
    gui.keep_val_input = Gui.input({ text = tostring(state.keep_value), placeholder = "20000" })
    gui.keep_val_input:on_change(function()
        local val = tonumber(gui.keep_val_input:get_text())
        if val and val >= 0 then state.keep_value = math.floor(val) end
    end)
    keep_val_box:add(gui.keep_val_input)
    settings_box:add(keep_val_box)

    -- Checkboxes
    gui.auto_multi_check = Gui.checkbox("Auto Multiplier (4x/<1k, 10x/>=1k, Landing only)", state.auto_multiplier)
    gui.auto_multi_check:on_change(function()
        state.auto_multiplier = gui.auto_multi_check:get_checked()
    end)
    settings_box:add(gui.auto_multi_check)

    gui.confirm_check = Gui.checkbox("Confirm before each deed attempt", state.confirm_required)
    gui.confirm_check:on_change(function()
        state.confirm_required = gui.confirm_check:get_checked()
    end)
    settings_box:add(gui.confirm_check)

    gui.accountant_check = Gui.checkbox("Accountant (suggest silver when cheaper)", state.accountant)
    gui.accountant_check:on_change(function()
        state.accountant = gui.accountant_check:get_checked()
    end)
    settings_box:add(gui.accountant_check)

    gui.dwarf_check = Gui.checkbox("Use Silver/Dwarf Rubies (Landing only)", state.use_dwarf_rubies)
    gui.dwarf_check:on_change(function()
        state.use_dwarf_rubies = gui.dwarf_check:get_checked()
    end)
    settings_box:add(gui.dwarf_check)

    settings_card:add(settings_box)
    get_deeds_box:add(settings_card)

    -- Buttons row 1: Save / Defaults
    local btn_box = Gui.hbox()
    gui.save_btn = Gui.button("Save Settings")
    gui.save_btn:on_click(function()
        save_settings()
    end)
    btn_box:add(gui.save_btn)

    gui.defaults_btn = Gui.button("Defaults")
    gui.defaults_btn:on_click(function()
        state.item_multiplier = 3.0
        state.deeds_wanted = 10
        state.keep_value = 20000
        state.auto_multiplier = true
        state.confirm_required = false
        state.accountant = false
        state.use_dwarf_rubies = false
        gui.multi_input:set_text("3.0")
        gui.deeds_input:set_text("10")
        gui.keep_val_input:set_text("20000")
        gui.auto_multi_check:set_checked(true)
        gui.confirm_check:set_checked(false)
        gui.accountant_check:set_checked(false)
        gui.dwarf_check:set_checked(false)
        echo("Settings reset to defaults.")
    end)
    btn_box:add(gui.defaults_btn)
    get_deeds_box:add(btn_box)

    -- Buttons row 2: Get Deeds / Stop
    local action_box = Gui.hbox()
    gui.get_deeds_btn = Gui.button("Get Deeds!")
    gui.get_deeds_btn:on_click(function()
        if state.running then
            echo("Already running!")
            return
        end
        run_deed_acquisition()
        update_stats_display()
    end)
    action_box:add(gui.get_deeds_btn)

    gui.stop_btn = Gui.button("Stop")
    gui.stop_btn:on_click(function()
        state.stop_requested = true
        -- If waiting for permission, cancel it
        if state.perm_pending then
            state.perm_result = "no"
            state.perm_pending = false
        end
        echo("Stop requested. Will halt after current action.")
    end)
    action_box:add(gui.stop_btn)
    get_deeds_box:add(action_box)

    -- Buttons row 3: Confirm / Decline / Use Silver (for interactive confirmation)
    local confirm_box = Gui.hbox()

    gui.confirm_btn = Gui.button("Confirm (inactive)")
    gui.confirm_btn:on_click(function()
        if state.perm_pending then
            state.perm_result = "yes"
            state.perm_pending = false
        end
    end)
    confirm_box:add(gui.confirm_btn)

    gui.decline_btn = Gui.button("Decline")
    gui.decline_btn:on_click(function()
        if state.perm_pending then
            state.perm_result = "no"
            state.perm_pending = false
        end
    end)
    confirm_box:add(gui.decline_btn)

    gui.use_silver_btn = Gui.button("Use Silver")
    gui.use_silver_btn:on_click(function()
        if state.perm_pending then
            state.perm_result = "silver"
            state.perm_pending = false
        end
    end)
    confirm_box:add(gui.use_silver_btn)
    get_deeds_box:add(confirm_box)

    -- Status
    gui.status_label = Gui.label("Status: Idle")
    get_deeds_box:add(gui.status_label)

    tabs:set_tab_content(1, Gui.scroll(get_deeds_box))

    -- ==========================================================================
    -- Tab 2: Keep
    -- ==========================================================================
    local keep_box = Gui.vbox()
    local keep_card = Gui.card({ title = "Keep List" })
    local keep_inner = Gui.vbox()

    keep_inner:add(Gui.label(
        "IMPORTANT: Never enter the leading 'a', 'an', or 'some' part of an item's name.\n\n" ..
        "This is a universal setting for all of your characters.\n\n" ..
        "Enter the name of an item you want to keep — the script won't use that item for a deed.\n\n" ..
        "You can enter a full name or a partial name.\n\n" ..
        "Example: 'large yellow diamond' keeps all large yellow diamonds, or just 'diamond' keeps all diamonds.\n\n" ..
        "Click 'Save' to save any changes."
    ))
    keep_inner:add(Gui.separator())

    -- Add entry
    local add_box = Gui.hbox()
    gui.keep_add_input = Gui.input({ placeholder = "Item name to keep" })
    add_box:add(gui.keep_add_input)
    local keep_add_btn = Gui.button("Add")
    keep_add_btn:on_click(function()
        local text = gui.keep_add_input:get_text()
        if text and #text > 0 then
            text = text:match("^%s*(.-)%s*$")
            local found = false
            for _, v in ipairs(keep_list) do
                if v == text then found = true; break end
            end
            if not found then
                table.insert(keep_list, text)
                table.sort(keep_list)
            end
            gui.keep_add_input:set_text("")
            update_keep_list_display()
        end
    end)
    add_box:add(keep_add_btn)
    keep_inner:add(add_box)

    -- Remove entry
    local remove_box = Gui.hbox()
    gui.keep_remove_input = Gui.input({ placeholder = "Item name to remove" })
    remove_box:add(gui.keep_remove_input)
    local keep_remove_btn = Gui.button("Remove")
    keep_remove_btn:on_click(function()
        local text = gui.keep_remove_input:get_text()
        if text and #text > 0 then
            text = text:match("^%s*(.-)%s*$")
            for i, v in ipairs(keep_list) do
                if v == text then
                    table.remove(keep_list, i)
                    break
                end
            end
            gui.keep_remove_input:set_text("")
            update_keep_list_display()
        end
    end)
    remove_box:add(keep_remove_btn)
    keep_inner:add(remove_box)

    -- Remove all + save
    local keep_btn_box = Gui.hbox()
    local remove_all_btn = Gui.button("Remove All")
    remove_all_btn:on_click(function()
        keep_list = {}
        update_keep_list_display()
    end)
    keep_btn_box:add(remove_all_btn)

    local keep_save_btn = Gui.button("Save")
    keep_save_btn:on_click(function()
        save_settings()
    end)
    keep_btn_box:add(keep_save_btn)
    keep_inner:add(keep_btn_box)

    keep_inner:add(Gui.separator())
    gui.keep_list_label = Gui.label("")
    keep_inner:add(gui.keep_list_label)
    update_keep_list_display()

    keep_card:add(keep_inner)
    keep_box:add(keep_card)
    tabs:set_tab_content(2, Gui.scroll(keep_box))

    -- ==========================================================================
    -- Tab 3: Deed Calculator
    -- ==========================================================================
    local calc_box = Gui.vbox()
    local calc_card = Gui.card({ title = "Deed Cost Calculator" })
    local calc_inner = Gui.vbox()

    local exp_val  = experience.total or 0
    local deed_val = experience.deeds or 0

    local calc_exp_box = Gui.hbox()
    calc_exp_box:add(Gui.label("Normal Experience: "))
    gui.calc_exp_input = Gui.input({ text = tostring(exp_val), placeholder = "0" })
    gui.calc_exp_input:on_change(function() update_calc_display() end)
    calc_exp_box:add(gui.calc_exp_input)
    calc_inner:add(calc_exp_box)

    local calc_start_box = Gui.hbox()
    calc_start_box:add(Gui.label("Starting Deeds: "))
    gui.calc_start_input = Gui.input({ text = tostring(deed_val), placeholder = "0" })
    gui.calc_start_input:on_change(function() update_calc_display() end)
    calc_start_box:add(gui.calc_start_input)
    calc_inner:add(calc_start_box)

    local calc_end_box = Gui.hbox()
    calc_end_box:add(Gui.label("Ending Deeds: "))
    gui.calc_end_input = Gui.input({ text = tostring(deed_val + 10), placeholder = "10" })
    gui.calc_end_input:on_change(function() update_calc_display() end)
    calc_end_box:add(gui.calc_end_input)
    calc_inner:add(calc_end_box)

    local calc_multi_box = Gui.hbox()
    calc_multi_box:add(Gui.label("Item Multiplier: "))
    gui.calc_multi_input = Gui.input({ text = "3.0", placeholder = "3.0" })
    gui.calc_multi_input:on_change(function() update_calc_display() end)
    calc_multi_box:add(gui.calc_multi_input)
    calc_inner:add(calc_multi_box)

    calc_inner:add(Gui.separator())
    gui.calc_label = Gui.label("")
    calc_inner:add(gui.calc_label)
    update_calc_display()

    calc_card:add(calc_inner)
    calc_box:add(calc_card)
    tabs:set_tab_content(3, Gui.scroll(calc_box))

    -- ==========================================================================
    -- Tab 4: Stats
    -- ==========================================================================
    local stats_box = Gui.vbox()
    local stats_card = Gui.card({ title = "Lifetime Statistics" })
    gui.stats_label = Gui.label("")
    stats_card:add(gui.stats_label)
    update_stats_display()
    stats_box:add(stats_card)
    tabs:set_tab_content(4, Gui.scroll(stats_box))

    -- ==========================================================================
    -- Tab 5: Version History
    -- ==========================================================================
    local vh_box = Gui.vbox()
    local vh_card = Gui.card({ title = "Version History" })
    local vh_label = Gui.label(
        "Version 16 (original .lic):\n" ..
        "  New feature: 'Keep Value' setting keeps items at or above this value.\n" ..
        "  Updated 'Buy Dwarf Rubies' -> 'Use Silver/Dwarf Rubies':\n" ..
        "    Now determines if silver is cheaper than buying a dwarf ruby.\n" ..
        "  'Use Silver' checkbox renamed to 'Accountant'.\n" ..
        "----\n" ..
        "Version 15 (original .lic):\n" ..
        "  Town tooltip now lists which items can be used in each town.\n" ..
        "----\n" ..
        "Version 14 (original .lic):\n" ..
        "  Option to buy dwarf-cut rubies added.\n" ..
        "  Auto Multiplier uses 10x for rubies.\n" ..
        "----\n" ..
        "Version 13 (original .lic):\n" ..
        "  Complete overhaul with GUI.\n" ..
        "  Correct Landing formula implemented.\n" ..
        "  Silver fallback option.\n" ..
        "  Stats page added.\n" ..
        "  Deed calculator added.\n" ..
        "  Item value cache (per session).\n" ..
        "----\n" ..
        "Revenant port v1.1.0 (2026-03-18):\n" ..
        "  Full parity with lic v16.\n" ..
        "  Confirm/Decline/Use Silver interactive workflow.\n" ..
        "  Pre-purchase dwarf ruby flow with upfront confirmation.\n" ..
        "  Decline removes item set from pool and continues.\n" ..
        "  Keep list is universal (all characters).\n" ..
        "  Enhanced stats: per-day, avg per deed.\n" ..
        "  Overage display when not using Auto Multiplier.\n"
    )
    vh_card:add(vh_label)
    vh_box:add(vh_card)
    tabs:set_tab_content(5, Gui.scroll(vh_box))

    -- Set root
    win:set_root(tabs)
    win:show()

    -- Initialize deed info
    get_deed_cost()
    update_gui_info()

    -- Startup instructions (mirroring original)
    echo("Items are worth more than their value when used to get a deed, but the exact multiplier is unknown. Use the 'Item Multiplier' to set how much you want to value items when trying for a deed.")
    echo("Through my own testing: gems in the Landing seem to have a 4x multiplier if the gem value is less than 1000, and a 10x multiplier for items with values of 1000+. The 'Auto Multiplier' setting uses these values.")
    echo("Icemule multiplier seems to be anywhere from 3x-17x.")
    echo("Experiment with different multipliers to find a good one that gives you the most value while still getting a deed.")
    echo("If you fail to get a deed: try lowering the 'Item Multiplier'.")

    -- On close, save stats and stop
    win:on_close(function()
        state.stop_requested = true
        if state.perm_pending then
            state.perm_result = "no"
            state.perm_pending = false
        end
        save_stats()
    end)

    -- Wait for window close
    Gui.wait(win, "close")
end

-- ---------------------------------------------------------------------------
-- CLI help
-- ---------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("=== Dirty Deeds - Deed Acquisition Tool ===")
    respond("Original author: Dreaven (Tgo01)")
    respond("")
    respond("Commands:")
    respond("  ;dirty_deeds          - Open GUI and run")
    respond("  ;dirty_deeds setup    - Open GUI in setup mode")
    respond("  ;dirty_deeds calc     - Show deed calculator (CLI)")
    respond("  ;dirty_deeds stats    - Show lifetime statistics")
    respond("  ;dirty_deeds help     - This help")
    respond("")
    respond("Supported Towns:")
    respond("  Landing      - Uses any gems for deeds")
    respond("  Icemule      - Uses wands and lockpicks for deeds")
    respond("  River's Rest - Uses River's Rest gems for deeds")
    respond("")
    respond("Settings are saved per-character via CharSettings.")
    respond("Keep list is universal (all characters share it) via Settings.")
    respond("The deed formula: (deeds^2 * 20) + (GS3_level * 100) + 101")
    respond("")
    respond("Tips:")
    respond("  - Auto Multiplier uses 4x for items <1000 value, 10x for >=1000 (Landing only)")
    respond("  - Use Silver/Dwarf Rubies will pre-purchase rubies or use silver directly (Landing only)")
    respond("  - Accountant suggests silver when cheaper than items")
    respond("  - Keep Value prevents items above threshold from being used")
    respond("  - Keep List lets you exclude specific items by name (universal, all characters)")
    respond("  - Confirm checkbox: shows Confirm/Decline buttons before each deed attempt")
    respond("")
end

-- ---------------------------------------------------------------------------
-- Main entry point
-- ---------------------------------------------------------------------------

load_keep_list()
load_settings()
load_stats()

before_dying(function()
    save_stats()
end)

local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or ""

if cmd == "help" then
    show_help()
elseif cmd == "calc" or cmd == "calculator" then
    show_deed_calculator()
elseif cmd == "stats" then
    show_stats()
elseif cmd == "setup" then
    build_gui()
else
    -- Default: open GUI
    build_gui()
end
