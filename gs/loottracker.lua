--- @revenant-script
--- name: loottracker
--- version: 0.2.1
--- author: Nisugi (Lua conversion by Sordal)
--- original_author: Nisugi
--- game: gs
--- description: Self-parsing loot tracking system - tracks searches, skins, boxes, sales, appraisals, bounties, bank transactions. Run in background while hunting.
--- tags: loot,tracking,hunting,gems,boxes,skins,sales,bounty,bank,lootcap
--- @lic-certified: complete 2026-03-18
---
--- Changelog (from Lich5 loottracker.lic):
---   v0.2.2: Gap-fill audit vs original 5014-line Ruby version:
---           - Added ;lt wands, ;lt box [id], ;lt creature <id> commands
---           - Added feeder_item, legendary_item, draconic_idol special find tracking
---           - Added missing bank transaction categories: note_deposit (written/bulk notes),
---             note_withdrawal (Terras scrip), player_give, debt_payment
---           - Fixed gem_sale FIFO fallback: appraised_value guard prevents
---             post-purify sale matching pre-purify gem record
---           - Added standalone dispatch routes for feeder/legendary special finds
---   v0.2.1: Full port to Revenant Lua. JSON file persistence replacing Sequel/SQLite.
---           All core tracking systems preserved: search, skin, box, sale, bank,
---           bounty, appraisal, loresong, loot cap, wand dupe, bundling,
---           chronomage ring, gemshop rejection, gem shatter.
---           Cross-character proxy support for loresong/appraise/dupe.
---   v0.2.0: Original Ruby version - full-featured loot tracker
---   v0.1.0: Initial beta release
---
--- Usage:
---   ;loottracker              Start tracking (run in background)
---   ;loottracker help         Show all commands
---
--- Reports:
---   ;loottracker cap          Monthly loot cap report (estimated vs realized)
---   ;loottracker cap last     Previous month's loot cap
---   ;loottracker recent       Recent items (filterable by type)
---   ;loottracker boxes        Recent boxes with contents
---   ;loottracker creatures    Top creatures by loot value
---   ;loottracker wands        Wand duplication stats
---
--- Debug:
---   ;loottracker debug        Toggle debug output

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local VERSION = "0.2.1"
local SCRIPT_NAME = "loottracker"
local MAX_BUFFER_SIZE = 100
local PAWN_CAP_VALUE = 25000
local LOOT_CAP_MONTHLY = 7500000

-- Town-based racial bonus lookup (5% bonus for selling in favorable towns)
local TOWN_RACIAL_BONUS = {
    ["Wehnimer's Landing"] = { Giantman = 5, Halfling = 5, ["Half-Elf"] = 5, ["Dark Elf"] = 5, ["Forest Gnome"] = 5 },
    ["Icemule Trace"]      = { Halfling = 5, Sylvankind = 5, ["Half-Krolvin"] = 5 },
    ["Solhaven"]           = { Human = 5, ["Half-Elf"] = 5 },
    ["River's Rest"]       = { Human = 5, ["Half-Krolvin"] = 5 },
    ["Ta'Vaalor"]          = { Elf = 5 },
    ["Ta'Illistim"]        = { Elf = 5, Sylvankind = 5, ["Burghal Gnome"] = 5, Erithian = 5, Aelotoi = 5 },
    ["Cysaegir"]           = { ["Dark Elf"] = 5, ["Forest Gnome"] = 5, Erithian = 5, Aelotoi = 5 },
    ["Kharam Dzu"]         = { Halfling = 5 },
    ["Zul Logoth"]         = { Halfling = 5 },
}

-- Box nouns (containers from creatures that can be opened/picked)
local BOX_NOUNS = {
    box = true, trunk = true, coffer = true, chest = true, strongbox = true,
    casket = true, lockbox = true, crate = true, case = true, reliquary = true,
}

-- Weapon nouns for fallback classification
local WEAPON_NOUNS = {}
for _, n in ipairs({
    "adze","axe","backsword","bardiche","bludgeon","broadsword","cestus","claidhmore","club","crossbow",
    "cudgel","dagger","dart","estoc","falchion","flail","flamberge","glaive","greataxe","greatsword",
    "halberd","hammer","handaxe","harpoon","hatchet","javelin","katana","katar","knife","lance","longsword",
    "mace","maul","mattock","naginata","pike","quarterstaff","rapier","runestaff","sabre","scimitar",
    "spear","staff","sword","trident","voulge","waraxe","warblade","whip","yierka-spur","yumi","bow",
}) do WEAPON_NOUNS[n] = true end

local ARMOR_NOUNS = {}
for _, n in ipairs({
    "helm","helmet","greaves","hauberk","breastplate","aventail","armor","leather","leathers",
    "cuirass","vambraces","gauntlets","pauldrons","aegis","shield","buckler","greatshield",
}) do ARMOR_NOUNS[n] = true end

local WAND_NOUNS = { wand = true, rod = true, baton = true }
local VALUABLE_NOUNS = { nugget = true, tusk = true }
local LOCKPICK_NOUNS = { lockpick = true }
local JUNK_NOUNS = { spring = true }

local GEM_NOUNS = {}
for _, n in ipairs({
    "duskjewel","snowstone","nightstone","hoarstone","kornerupine","glacialite","titanite",
    "labradorite","carnelian","galena","lichstone","snowdrop","seaglass","zoisite","teardrop",
    "oligoclase","citrine","spectrolite","chrysoberyl","bauxite","mournstone","firedrop",
    "spruce","chunk","fang",
}) do GEM_NOUNS[n] = true end

local AMBIGUOUS_GEM_NOUNS = { shard = true, core = true, crystal = true }

local GEM_PHRASES = {
    "glacial core","ammolite shard","cinnabar shard","nephrite shard","alexandrite shard",
    "shimmertine shard","everfrost shard","tigerfang crystal","dragonmist crystal",
    "azurite crystal","wulfenite crystal","salt crystal","sky blue crystal",
}

-- Type aliases for recent command
local RECENT_TYPE_ALIASES = {
    ["--gems"]="gem",["-g"]="gem",gems="gem",gem="gem",
    ["--boxes"]="box",["-b"]="box",boxes="box",box="box",
    ["--skins"]="skin",["-s"]="skin",skins="skin",skin="skin",
    ["--klocks"]="klock",["-k"]="klock",klocks="klock",klock="klock",
    ["--magic"]="magic",["-m"]="magic",magic="magic",
    ["--wands"]="wand",["-w"]="wand",wands="wand",wand="wand",
    ["--weapons"]="weapon",weapons="weapon",weapon="weapon",
    ["--armor"]="armor",["-a"]="armor",armor="armor",
    ["--jewelry"]="jewelry",["-j"]="jewelry",jewelry="jewelry",
    ["--clothing"]="clothing",clothing="clothing",
    ["--scrolls"]="scroll",scrolls="scroll",scroll="scroll",
    ["--valuables"]="valuable",["-v"]="valuable",valuables="valuable",valuable="valuable",
    ["--collectibles"]="collectible",collectibles="collectible",collectible="collectible",
    ["--lockpicks"]="lockpick",lockpicks="lockpick",lockpick="lockpick",
    ["--scarabs"]="scarab",scarabs="scarab",scarab="scarab",
    ["--reagents"]="reagent",["-r"]="reagent",reagents="reagent",reagent="reagent",
    ["--food"]="food",food="food",
    ["--jars"]="jar",jars="jar",jar="jar",
    ["--boons"]="boon",boons="boon",boon="boon",
    ["--ingots"]="ingot",ingots="ingot",ingot="ingot",
    ["--junk"]="junk",junk="junk",
    ["--other"]="other",["-o"]="other",other="other",
}

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

local LT = {
    enabled = false,
    debug_mode = false,
    buffer = {},
    pending_pool_drop = nil,
    pending_pool_returns = {},
    loresong_proxy = nil,
    appraise_proxy = nil,
    dupe_proxy = nil,
    -- Processor state
    pending_loresong_item = nil,
    pending_shop_appraise_item = nil,
    pending_gemshop_ask = nil,
    -- Data store: loaded per character per month
    data = nil,
    data_file = nil,
    character = nil,
    game = nil,
    -- Trading bonus cache
    _trading_bonus_cache = nil,
    _trading_bonus_time = 0,
}

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local function log(msg)
    local ts = os.date("%H:%M:%S")
    respond("[LootTracker " .. ts .. "] " .. msg)
end

local function debug_log(msg)
    if LT.debug_mode then
        log(msg)
    end
end

local function format_silver(amount)
    amount = tostring(math.floor(amount or 0))
    local result = ""
    local len = #amount
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. amount:sub(i, i)
    end
    return result
end

local function format_time(timestamp)
    if not timestamp then return "N/A" end
    return os.date("%m/%d %H:%M", timestamp)
end

local function parse_silvers(str)
    if not str then return nil end
    return tonumber((str:gsub(",", "")))
end

local function strip_xml(line)
    return (line:gsub("<[^>]+>", "")):match("^%s*(.-)%s*$") or ""
end

--- Split a string by whitespace
local function split(str)
    local t = {}
    for word in (str or ""):gmatch("%S+") do
        t[#t + 1] = word
    end
    return t
end

--- String left-justified to width
local function ljust(s, w)
    s = s or ""
    if #s >= w then return s:sub(1, w) end
    return s .. string.rep(" ", w - #s)
end

--- String right-justified to width
local function rjust(s, w)
    s = s or ""
    if #s >= w then return s end
    return string.rep(" ", w - #s) .. s
end

--- Get current timestamp (unix epoch seconds)
local function now()
    return os.time()
end

--- Generate a unique ID for records
local _id_counter = 0
local function next_id()
    _id_counter = _id_counter + 1
    return os.time() * 1000 + _id_counter
end

--------------------------------------------------------------------------------
-- Persistence (JSON file storage)
--
-- Data structure: one JSON file per character per month in data/loottracker/
-- File: data/loottracker/<character>_<YYYY>_<MM>.json
--
-- Schema:
--   loot_events[]     - search and box_open events
--   skin_events[]     - skinning events
--   bundle_events[]   - bundling events
--   loot_items[]      - individual items with tracking fields
--   bounty_rewards[]  - bounty completions
--   transactions[]    - financial transactions
--------------------------------------------------------------------------------

local function data_dir()
    return "data/loottracker"
end

local function data_file_for(char, year, month)
    return string.format("%s/%s_%04d_%02d.json", data_dir(), char, year, month)
end

local function current_data_file()
    local t = os.date("*t")
    return data_file_for(LT.character, t.year, t.month)
end

local function ensure_data_dir()
    if not File.exists(data_dir()) then
        File.mkdir(data_dir())
    end
end

local function empty_data()
    return {
        loot_events = {},
        skin_events = {},
        bundle_events = {},
        loot_items = {},
        bounty_rewards = {},
        transactions = {},
    }
end

local function load_data(filepath)
    if not filepath then return empty_data() end
    if not File.exists(filepath) then return empty_data() end
    local content = File.read(filepath)
    if not content or content == "" then return empty_data() end
    local ok, result = pcall(Json.decode, content)
    if ok and type(result) == "table" then
        -- Ensure all expected tables exist
        result.loot_events = result.loot_events or {}
        result.skin_events = result.skin_events or {}
        result.bundle_events = result.bundle_events or {}
        result.loot_items = result.loot_items or {}
        result.bounty_rewards = result.bounty_rewards or {}
        result.transactions = result.transactions or {}
        return result
    end
    return empty_data()
end

local function save_data()
    if not LT.data or not LT.data_file then return end
    ensure_data_dir()
    local ok, encoded = pcall(Json.encode, LT.data)
    if ok then
        File.write(LT.data_file, encoded)
    else
        log("ERROR: Failed to encode data: " .. tostring(encoded))
    end
end

--- Load data for a specific month (for reports on other months)
local function load_month_data(year, month)
    local filepath = data_file_for(LT.character, year, month)
    return load_data(filepath)
end

--- Initialize data for current character/month
local function init_data()
    LT.character = GameState.name or "Unknown"
    LT.game = GameState.game or "GS3"
    LT.data_file = current_data_file()
    LT.data = load_data(LT.data_file)
    debug_log("Data loaded: " .. LT.data_file)
end

--------------------------------------------------------------------------------
-- Item Classification
--------------------------------------------------------------------------------

local function classify_by_noun_and_name(noun, name)
    if not noun then return "other" end
    local nl = noun:lower()
    local namel = (name or ""):lower()

    if WAND_NOUNS[nl] then return "wand" end
    if VALUABLE_NOUNS[nl] then return "valuable" end
    if LOCKPICK_NOUNS[nl] then return "lockpick" end
    if BOX_NOUNS[nl] then return "box" end
    if GEM_NOUNS[nl] then return "gem" end
    if JUNK_NOUNS[nl] then return "junk" end
    if namel:find("%w+ ingot") then return "ingot" end

    if AMBIGUOUS_GEM_NOUNS[nl] then
        for _, phrase in ipairs(GEM_PHRASES) do
            if namel:find(phrase, 1, true) then return "gem" end
        end
    end

    if WEAPON_NOUNS[nl] then return "weapon" end
    if ARMOR_NOUNS[nl] then return "armor" end

    return "other"
end

local function classify_item(item_id)
    if not item_id then return "other" end
    local obj = GameObj[item_id]
    if not obj then return "other" end

    -- Check for ingot by name first
    if obj.name and obj.name:lower():find("%w+ ingot") then return "ingot" end

    local otype = (obj.type or ""):lower()
    if otype == "gem" then return "gem"
    elseif otype == "valuable" then return "valuable"
    elseif otype == "box" then return "box"
    elseif otype == "skin" then return "skin"
    elseif otype == "wand" then return "wand"
    elseif otype == "magic" then return "magic"
    elseif otype == "scroll" then return "scroll"
    elseif otype == "weapon" then return "weapon"
    elseif otype == "armor" or otype == "shield" then return "armor"
    elseif otype == "jewelry" then return "jewelry"
    elseif otype == "clothing" then return "clothing"
    elseif otype == "collectible" then return "collectible"
    elseif otype == "lockpick" then return "lockpick"
    elseif otype == "scarab" then return "scarab"
    elseif otype == "herb" or otype == "reagent" then return "reagent"
    elseif otype == "food" then return "food"
    elseif otype == "jar" then return "jar"
    elseif otype == "boon" then return "boon"
    else
        -- Fallback by noun
        local noun = obj.noun
        if not noun then return "other" end
        local nl = noun:lower()
        if BOX_NOUNS[nl] then return "box" end
        if WEAPON_NOUNS[nl] then return "weapon" end
        if ARMOR_NOUNS[nl] then return "armor" end
        if WAND_NOUNS[nl] then return "wand" end
        if LOCKPICK_NOUNS[nl] then return "lockpick" end
        return "other"
    end
end

--------------------------------------------------------------------------------
-- Trading Bonus Calculation
--------------------------------------------------------------------------------

local function calculate_trading_bonus()
    -- Cache for 5 minutes
    if LT._trading_bonus_cache and (now() - LT._trading_bonus_time) < 300 then
        return LT._trading_bonus_cache
    end

    local inf_bonus = 0
    local trading_bonus = 0
    local ok1, val1 = pcall(function()
        local s = Stats.enhanced_inf
        if s then return s[2] or 0 end
        return 0
    end)
    if ok1 then inf_bonus = val1 or 0 end

    local ok2, val2 = pcall(function()
        return Skills.to_bonus("trading") or 0
    end)
    if ok2 then trading_bonus = val2 or 0 end

    local value = math.floor((inf_bonus + trading_bonus) / 12)
    LT._trading_bonus_cache = value
    LT._trading_bonus_time = now()
    return value
end

local function current_location()
    local ok, loc = pcall(function()
        local room = Room.current()
        return room and room.location or nil
    end)
    if not ok or not loc then return nil end

    for town, _ in pairs(TOWN_RACIAL_BONUS) do
        if loc:find(town, 1, true) then return town end
    end
    return loc
end

local function calculate_racial_bonus()
    local location = current_location()
    if not location then return 0 end

    local ok, race = pcall(function() return Stats.race end)
    if not ok or not race then return 0 end

    for town, races in pairs(TOWN_RACIAL_BONUS) do
        if location:find(town, 1, true) then
            return races[race] or 0
        end
    end
    return 0
end

local function current_room_id()
    local ok, id = pcall(function() return GameState.room_id end)
    return ok and id or nil
end

--------------------------------------------------------------------------------
-- Record Creation Functions
--------------------------------------------------------------------------------

local function create_event(event_type, source_id, source_name, silvers)
    local id = next_id()
    local event = {
        id = id,
        event_type = event_type,
        source_id = tostring(source_id or ""),
        source_name = source_name or "",
        silvers_found = silvers or 0,
        character = LT.character,
        game = LT.game,
        room_id = current_room_id(),
        created_at = now(),
    }
    table.insert(LT.data.loot_events, event)
    return id
end

local function create_skin_event(creature_id, creature_name)
    local id = next_id()
    local event = {
        id = id,
        creature_id = tostring(creature_id or ""),
        creature_name = creature_name or "",
        character = LT.character,
        game = LT.game,
        created_at = now(),
    }
    table.insert(LT.data.skin_events, event)
    return id
end

local function find_item_by_id(item_id)
    for _, item in ipairs(LT.data.loot_items) do
        if item.item_id == tostring(item_id) then return item end
    end
    return nil
end

local function find_item_by_record_id(record_id)
    for _, item in ipairs(LT.data.loot_items) do
        if item.id == record_id then return item end
    end
    return nil
end

--- Find items matching a filter function
local function find_items(filter_fn)
    local results = {}
    for _, item in ipairs(LT.data.loot_items) do
        if filter_fn(item) then
            results[#results + 1] = item
        end
    end
    return results
end

--- Find first item matching a filter, sorted by created_at ascending (FIFO)
local function find_first_item(filter_fn)
    local oldest = nil
    for _, item in ipairs(LT.data.loot_items) do
        if filter_fn(item) then
            if not oldest or item.created_at < oldest.created_at then
                oldest = item
            end
        end
    end
    return oldest
end

local function create_item(opts)
    -- Check for duplicate by item_id + item_noun
    local item_id = tostring(opts.item_id or "")
    for _, existing in ipairs(LT.data.loot_items) do
        if existing.item_id == item_id and existing.item_noun == opts.item_noun then
            debug_log("Item already exists: " .. item_id .. "/" .. (opts.item_noun or ""))
            return existing.id
        end
    end

    local id = next_id()
    local item = {
        id = id,
        item_id = item_id,
        item_name = opts.item_name or "",
        item_noun = opts.item_noun,
        item_type = opts.item_type,
        item_source = opts.item_source,
        event_id = opts.event_id,
        skin_event_id = opts.skin_event_id,
        searcher = opts.searcher or LT.character,
        game = LT.game,
        created_at = now(),
        -- Sale/appraisal tracking fields (nil initially)
        appraised_value = nil,
        appraised_at = nil,
        loresong_value = nil,
        loresong_at = nil,
        loresong_value_2 = nil,
        loresong_at_2 = nil,
        sold_value = nil,
        sold_at = nil,
        sold_category = nil,
        sold_location = nil,
        sold_room_uid = nil,
        sold_trading_bonus = nil,
        sold_racial_bonus = nil,
        sold_to = nil,
        shop_appraisal = nil,
        shop_appraised_at = nil,
        -- Box tracking
        opened_at = nil,
        opened_event_id = nil,
        pool_dropped_at = nil,
        pool_room_uid = nil,
        pool_dropped_by = nil,
        pool_fee = nil,
        pool_tip = nil,
        -- Wand dupe
        dupe_source_id = nil,
        duplicated_at = nil,
        -- Shatter/rejection/lost
        shattered_at = nil,
        gemshop_rejected_at = nil,
        pawn_cap_value = nil,
        lost_at = nil,
    }
    table.insert(LT.data.loot_items, item)
    return id
end

--------------------------------------------------------------------------------
-- Recording Functions
--------------------------------------------------------------------------------

local function record_search(creature_id, creature_name, silvers, items)
    if not LT.enabled then return end

    local event_id = create_event("search", creature_id, creature_name, silvers)

    for _, item in ipairs(items) do
        create_item({
            item_id = item.id,
            item_name = item.name,
            item_noun = item.noun,
            item_type = classify_item(item.id),
            item_source = "search",
            event_id = event_id,
        })
    end

    debug_log("Recorded search: " .. creature_name .. " -> " .. (silvers or 0) .. " silvers, " .. #items .. " items")
    save_data()
    return event_id
end

local function record_skin(creature_id, creature_name, item_id, item_name, item_noun)
    if not LT.enabled then return end

    local skin_event_id = create_skin_event(creature_id, creature_name)

    create_item({
        item_id = item_id,
        item_name = item_name,
        item_noun = item_noun,
        item_type = "skin",
        item_source = "skin",
        skin_event_id = skin_event_id,
    })

    debug_log("Recorded skin: " .. item_name .. " from " .. creature_name)
    save_data()
    return skin_event_id
end

local function record_transaction(amount, category, subcategory, metadata, loot_item_id)
    if not LT.enabled then return end

    local t = os.date("*t")
    local txn = {
        id = next_id(),
        character = LT.character,
        game = LT.game,
        amount = amount,
        category = category,
        subcategory = subcategory,
        metadata = metadata,
        loot_item_id = loot_item_id,
        created_at = now(),
        year = t.year,
        month = t.month,
        day = t.day,
        hour = t.hour,
    }
    table.insert(LT.data.transactions, txn)
    debug_log("Recorded transaction: " .. category .. " " .. (amount >= 0 and "+" or "") .. amount)
    save_data()
end

local function record_bounty(bounty_points, experience, silver)
    if not LT.enabled then return end

    local reward = {
        id = next_id(),
        bounty_points = bounty_points,
        experience = experience,
        silver = silver,
        character = LT.character,
        game = LT.game,
        created_at = now(),
    }
    table.insert(LT.data.bounty_rewards, reward)

    if silver and silver > 0 then
        record_transaction(silver, "bounty_silver")
    end

    debug_log("Recorded bounty: " .. (bounty_points or 0) .. " BP, " .. (experience or 0) .. " XP, " .. (silver or 0) .. " silver")
    save_data()
end

local function record_bundle_event(event_type, skin_id, skin_name, bundle_id, bundle_name, container_id, container_name)
    if not LT.enabled then return end

    local event = {
        id = next_id(),
        event_type = event_type,
        skin_id = skin_id,
        skin_name = skin_name,
        bundle_id = bundle_id,
        bundle_name = bundle_name,
        container_id = container_id,
        container_name = container_name,
        character = LT.character,
        game = LT.game,
        created_at = now(),
    }
    table.insert(LT.data.bundle_events, event)
    debug_log("Recorded " .. event_type .. ": " .. skin_name .. " -> " .. bundle_name)
    save_data()
end

--- Find an item by ID, with name-based FIFO fallback and optional proxy filter
local function find_item_with_fallback(item_id, item_name, filter_fn, proxy)
    -- Try exact ID first
    local item = find_item_by_id(item_id)
    if item and (not filter_fn or filter_fn(item)) then return item end

    -- Fallback: name-based FIFO
    if item_name then
        local name_lower = item_name:lower()
        item = find_first_item(function(i)
            if proxy and i.searcher ~= proxy then return false end
            if filter_fn and not filter_fn(i) then return false end
            return i.item_name:lower():find(name_lower, 1, true) ~= nil
        end)
        if item then
            -- Update item_id for future lookups
            item.item_id = tostring(item_id)
            debug_log("Fallback matched: '" .. item_name .. "' -> item #" .. item.id)
        end
    end

    return item
end

local function update_item_appraisal(item_id, value, item_name, item_noun)
    if not LT.enabled then return false end

    local item = find_item_with_fallback(item_id, item_name,
        function(i) return not i.appraised_value end,
        LT.appraise_proxy)

    if not item then
        debug_log("Appraisal: item " .. item_id .. " not found")
        return false
    end

    item.appraised_value = value
    item.appraised_at = now()
    debug_log("Updated appraisal: " .. item_id .. " -> " .. value .. " silvers")
    save_data()
    return true
end

local function update_item_loresong(item_id, value, item_name, item_noun)
    if not LT.enabled then return false end

    local item = find_item_with_fallback(item_id, item_name, nil, LT.loresong_proxy)

    if not item then
        debug_log("Loresong: item " .. item_id .. " not found")
        return false
    end

    if not item.loresong_value then
        item.loresong_value = value
        item.loresong_at = now()
        debug_log("Updated loresong: " .. item_id .. " -> " .. value .. " silvers (pre-purify)")
    elseif value > item.loresong_value then
        item.loresong_value_2 = value
        item.loresong_at_2 = now()
        debug_log("Updated loresong: " .. item_id .. " -> " .. value .. " silvers (post-purify)")
    end

    save_data()
    return true
end

local function update_item_shop_appraisal(item_id, value, item_name, item_noun)
    if not LT.enabled then return false end

    local item = find_item_with_fallback(item_id, item_name, nil, LT.appraise_proxy)

    if not item then
        debug_log("Shop appraisal: item " .. item_id .. " not found")
        return false
    end

    if not item.shop_appraisal then
        item.shop_appraisal = value
        item.shop_appraised_at = now()
        item.sold_trading_bonus = calculate_trading_bonus()
        item.sold_racial_bonus = calculate_racial_bonus()
        debug_log("Updated shop appraisal: " .. item_id .. " -> " .. value .. " silvers")
        save_data()
    end

    return true
end

local function update_item_sold(item_id, value, category, item_name, item_noun)
    if not LT.enabled then return nil end

    -- For gem sales, guard against matching a pre-purify record when value is higher
    -- (post-purify gems are worth more; prefer matching a record whose appraised_value <= sale)
    local base_filter = function(i) return not i.sold_value end
    local filter_fn
    if category == "gem_sale" then
        filter_fn = function(i)
            return base_filter(i) and (not i.appraised_value or i.appraised_value <= value)
        end
    else
        filter_fn = base_filter
    end

    local item = find_item_with_fallback(item_id, item_name, filter_fn, LT.appraise_proxy)

    -- Create orphan_sale if not found
    if not item then
        local item_type = classify_item(item_id)
        if item_type == "other" and item_noun and item_name then
            item_type = classify_by_noun_and_name(item_noun, item_name)
        end
        local record_id = create_item({
            item_id = item_id,
            item_name = item_name or "",
            item_noun = item_noun,
            item_type = item_type,
            item_source = "orphan_sale",
            searcher = nil,
        })
        item = find_item_by_record_id(record_id)
        debug_log("Orphan sale created: " .. (item_name or "unknown"))
    end

    if not item then return nil end

    item.sold_value = value
    item.sold_at = now()
    item.sold_category = category
    item.sold_location = current_location()
    item.sold_trading_bonus = calculate_trading_bonus()
    item.sold_racial_bonus = calculate_racial_bonus()

    debug_log("Updated sale: " .. item_id .. " -> " .. value .. " silvers (" .. category .. ")")
    save_data()
    return item.id
end

local function record_box_open(box_id, box_name, silvers, items, loot_item_id)
    if not LT.enabled then return end

    -- Skip empty boxes (already opened)
    if #items == 0 and (not silvers or silvers == 0) then
        debug_log("Skipping empty box " .. box_id)
        return
    end

    -- Find original box record for searcher attribution
    local box_item = nil
    local original_searcher = LT.character

    if loot_item_id then
        box_item = find_item_by_record_id(loot_item_id)
    end

    if not box_item and LT.pending_pool_returns[box_id] then
        box_item = find_item_by_record_id(LT.pending_pool_returns[box_id])
    end

    if not box_item then
        -- Name-based FIFO search
        local name_lower = box_name:lower()
        box_item = find_first_item(function(i)
            return i.item_type == "box" and not i.opened_at
                and i.item_name:lower():find(name_lower, 1, true) ~= nil
        end)
    end

    if box_item then
        original_searcher = box_item.searcher or LT.character
    end

    local event_id = create_event("box_open", box_id, box_name, silvers)

    for _, item in ipairs(items) do
        create_item({
            item_id = item.id,
            item_name = item.name,
            item_noun = item.noun,
            item_type = classify_item(item.id),
            item_source = "box",
            event_id = event_id,
            searcher = original_searcher,
        })
    end

    -- Link box record
    if box_item then
        box_item.opened_at = now()
        box_item.opened_event_id = event_id
        box_item.item_id = tostring(box_id)
        LT.pending_pool_returns[box_id] = nil
    end

    debug_log("Recorded box: " .. box_name .. " -> " .. (silvers or 0) .. " silvers, " .. #items .. " items")
    save_data()
    return event_id
end

local function update_box_silvers(box_id, silvers)
    if not LT.enabled then return false end

    -- Find most recent box_open event for this box
    local target_event = nil
    for i = #LT.data.loot_events, 1, -1 do
        local e = LT.data.loot_events[i]
        if e.source_id == tostring(box_id) and e.event_type == "box_open" then
            target_event = e
            break
        end
    end

    if target_event then
        target_event.silvers_found = silvers
        debug_log("Updated box " .. box_id .. " silvers: " .. silvers)
        save_data()
        return true
    end
    return false
end

local function record_pool_drop(box_id, box_name, tip, fee)
    if not LT.enabled then return end

    -- Find box by ID first, then name
    local box_item = find_item_by_id(box_id)
    if not box_item or box_item.pool_dropped_at then
        local name_lower = box_name:lower()
        box_item = find_first_item(function(i)
            return i.item_type == "box" and not i.pool_dropped_at
                and i.item_name:lower():find(name_lower, 1, true) ~= nil
        end)
    end

    if box_item then
        box_item.pool_dropped_at = now()
        box_item.pool_dropped_by = LT.character
        box_item.pool_fee = fee
        box_item.pool_tip = tip
    end

    record_transaction(-fee, "locksmith_fee")
    if tip > 0 then
        record_transaction(-tip, "locksmith_tip")
    end

    save_data()
end

local function link_returned_pool_box(new_box_id, box_name)
    if not LT.enabled then return end

    local name_lower = box_name:lower()
    local box_item = find_first_item(function(i)
        return i.item_type == "box" and i.pool_dropped_at and not i.opened_at
            and i.item_name:lower():find(name_lower, 1, true) ~= nil
    end)

    if box_item then
        LT.pending_pool_returns[new_box_id] = box_item.id
        debug_log("Linked pool return: " .. box_name .. " -> item #" .. box_item.id)
    end
end

local function record_klock(item_id, item_name)
    if not LT.enabled then return end
    create_item({
        item_id = item_id,
        item_name = item_name,
        item_type = "klock",
        item_source = "search",
    })
    save_data()
end

local function record_special_find(item_name, find_type, item_id, item_noun, source_id)
    if not LT.enabled then return end
    local item_data = {
        item_id = item_id or ("special_" .. now() .. "_" .. math.random(1000)),
        item_name = item_name,
        item_noun = item_noun,
        item_type = find_type,
        item_source = "special_find",
    }
    if source_id then item_data.source_creature_id = tostring(source_id) end
    create_item(item_data)
    save_data()
end

local function record_gem_shatter(item_id, item_name, item_noun)
    if not LT.enabled then return end

    local item = find_item_with_fallback(item_id, item_name,
        function(i) return i.item_type == "gem" and not i.sold_value and not i.shattered_at end)

    if item then
        item.sold_value = 0
        item.sold_at = now()
        item.sold_category = "shattered"
        item.shattered_at = now()
        log("Shatter: " .. item_name .. " marked as shattered")
        save_data()
    else
        log("Shatter: " .. item_name .. " NOT FOUND in database")
    end
end

local function record_gemshop_rejection(item_id, item_name, item_noun)
    if not LT.enabled then return end

    local item = find_item_with_fallback(item_id, item_name,
        function(i) return not i.sold_value and not i.gemshop_rejected_at end)

    if item then
        item.gemshop_rejected_at = now()
        item.pawn_cap_value = PAWN_CAP_VALUE
        log("Gemshop rejection: " .. item_name .. " marked too valuable (25k pawn cap)")
        save_data()
    end
end

local function record_chronomage_ring(item_id, noun, name, credit_value)
    if not LT.enabled then return end

    local item = find_item_by_id(item_id)
    if item then
        item.sold_at = now()
        item.sold_to = "chronomage"
        item.sold_value = credit_value
    else
        create_item({
            item_id = item_id,
            item_name = name,
            item_noun = noun,
            item_type = "ring",
            item_source = "unknown",
        })
        local new_item = find_item_by_id(item_id)
        if new_item then
            new_item.sold_at = now()
            new_item.sold_to = "chronomage"
            new_item.sold_value = credit_value
        end
    end
    save_data()
end

local function record_wand_dupe(donor, copy)
    if not LT.enabled then return end

    -- Find or create donor
    local donor_item = find_item_by_id(donor.id)
    if not donor_item then
        create_item({
            item_id = donor.id,
            item_name = donor.name,
            item_noun = donor.noun,
            item_type = "wand",
            item_source = "wand_source",
        })
        donor_item = find_item_by_id(donor.id)
    end

    if donor_item then
        donor_item.duplicated_at = now()
    end

    -- Create copy
    create_item({
        item_id = copy.id,
        item_name = copy.name,
        item_noun = copy.noun,
        item_type = "wand",
        item_source = "wand_dupe",
        dupe_source_id = donor_item and donor_item.id or nil,
        searcher = donor_item and donor_item.searcher or LT.character,
    })
    local copy_item = find_item_by_id(copy.id)
    if copy_item then
        copy_item.duplicated_at = now()
    end

    debug_log("Recorded wand dupe: " .. copy.name .. " from " .. donor.name)
    save_data()
end

local function mark_box_lost(identifier)
    if not LT.enabled then return nil end

    local item = nil

    -- Try numeric record ID first
    if tonumber(identifier) then
        item = find_item_by_record_id(tonumber(identifier))
        if item and item.item_type ~= "box" then item = nil end
    end

    -- Fall back to name search (most recent unopened)
    if not item then
        local id_lower = identifier:lower()
        local newest = nil
        for _, i in ipairs(LT.data.loot_items) do
            if i.item_type == "box" and not i.opened_at and not i.lost_at then
                if i.item_name:lower():find(id_lower, 1, true) then
                    if not newest or i.created_at > newest.created_at then
                        newest = i
                    end
                end
            end
        end
        item = newest
    end

    if not item then return nil end

    item.lost_at = now()
    log("Marked box as lost: " .. item.item_name .. " (#" .. item.id .. ")")
    save_data()
    return item
end

--------------------------------------------------------------------------------
-- Pattern Matching (XML line parsing)
--
-- These Lua patterns match the XML-tagged game output to detect loot events.
-- Lua patterns cannot express full regex, so we use string.find with plain
-- text triggers first, then extract data with more specific patterns.
--------------------------------------------------------------------------------

--- Extract a tagged object: <a exist="ID" noun="NOUN">NAME</a>
--- Returns id, noun, name or nil
local function extract_obj(line, after_text)
    local start = 1
    if after_text then
        local pos = line:find(after_text, 1, true)
        if not pos then return nil end
        start = pos
    end
    local id, noun, name = line:match('<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>', start)
    return id, noun, name
end

--- Extract a bold-tagged object: <pushBold/><a exist="ID" noun="NOUN">NAME</a><popBold/>
local function extract_bold_obj(line, after_text)
    local start = 1
    if after_text then
        local pos = line:find(after_text, 1, true)
        if not pos then return nil end
        start = pos
    end
    local id, noun, name = line:match('<pushBold/><a exist="(%d+)" noun="([^"]+)">([^<]+)</a><popBold/>', start)
    return id, noun, name
end

--- Extract all <inv> items from a container line
local function extract_inv_items(line)
    local items = {}
    for container_id, item_id, noun, name in line:gmatch("<inv id='(%d+)'>%s*[Aa]n?%s*<a exist=\"(%d+)\" noun=\"([^\"]+)\">([^<]+)</a></inv>") do
        if noun ~= "coins" then
            items[#items + 1] = { id = item_id, noun = noun, name = name }
        end
    end
    -- Also match items without article
    for container_id, item_id, noun, name in line:gmatch("<inv id='(%d+)'>%s*<a exist=\"(%d+)\" noun=\"([^\"]+)\">([^<]+)</a></inv>") do
        if noun ~= "coins" then
            -- Avoid duplicates
            local found = false
            for _, existing in ipairs(items) do
                if existing.id == item_id then found = true; break end
            end
            if not found then
                items[#items + 1] = { id = item_id, noun = noun, name = name }
            end
        end
    end
    -- Also match "some <item>"
    for container_id, item_id, noun, name in line:gmatch("<inv id='(%d+)'>%s*some%s+<a exist=\"(%d+)\" noun=\"([^\"]+)\">([^<]+)</a></inv>") do
        if noun ~= "coins" then
            local found = false
            for _, existing in ipairs(items) do
                if existing.id == item_id then found = true; break end
            end
            if not found then
                items[#items + 1] = { id = item_id, noun = noun, name = name }
            end
        end
    end
    return items
end

--------------------------------------------------------------------------------
-- Event Processors
-- Each processor examines a chunk of buffered lines and records events.
--------------------------------------------------------------------------------

local Processors = {}

function Processors.process_search(chunk)
    local creature = nil
    local silvers = nil
    local items = {}
    local klocks = {}
    local special_finds = {}

    for _, line in ipairs(chunk) do
        -- Search trigger: "You search the <creature>"
        if line:find("You search the ", 1, true) then
            local cid, cnoun, cname = line:match('You search the <pushBold/><a exist="(%d+)" noun="([^"]+)">([^<]+)</a><popBold/>')
            if cid then
                creature = { id = cid, noun = cnoun, name = cname }
            end
        end

        -- Silver coins
        local silver_match = line:match('<pushBold/><a exist="%d+" noun="[^"]+">[^<]+</a><popBold/> had (%d[%d,]*) silvers on')
        if silver_match then
            silvers = parse_silvers(silver_match)
        end

        -- Items: had/carried/interesting/left patterns
        -- "Interesting, <creature> carried <item>"
        local iid, inoun, iname
        if line:find("Interesting,", 1, true) then
            iid, inoun, iname = line:match('Interesting, <pushBold/><a exist="%d+" noun="[^"]+">[^<]+</a><popBold/> carried [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            if not iid then
                iid, inoun, iname = line:match('Interesting, <pushBold/><a exist="%d+" noun="[^"]+">[^<]+</a><popBold/> carried some%s+<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            end
            if not iid then
                iid, inoun, iname = line:match('Interesting, <pushBold/><a exist="%d+" noun="[^"]+">[^<]+</a><popBold/> carried <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            end
        end
        -- "<creature> had <item> on"
        if not iid and line:find("> had ", 1, true) then
            iid, inoun, iname = line:match('<popBold/> had [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a> on')
            if not iid then
                iid, inoun, iname = line:match('<popBold/> had [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>%.')
            end
            if not iid then
                iid, inoun, iname = line:match('<popBold/> had <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> on')
            end
            if not iid then
                iid, inoun, iname = line:match('<popBold/> had <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>%.')
            end
        end
        -- "<creature> carried <item> on"
        if not iid and line:find("> carried ", 1, true) and not line:find("Interesting", 1, true) then
            iid, inoun, iname = line:match('<popBold/> carried [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a> on')
            if not iid then
                iid, inoun, iname = line:match('<popBold/> carried <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> on')
            end
        end
        -- "<creature> left <item> behind."
        if not iid and line:find("> left ", 1, true) then
            iid, inoun, iname = line:match('<popBold/> left [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a> behind%.')
            if not iid then
                iid, inoun, iname = line:match('<popBold/> left some%s+<a exist="(%d+)" noun="([^"]+)">([^<]+)</a> behind%.')
            end
            if not iid then
                iid, inoun, iname = line:match('<popBold/> left <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> behind%.')
            end
        end

        if iid then
            items[#items + 1] = { id = iid, noun = inoun, name = iname }
        end

        -- Klock keys/locks
        local kid, kname
        kid, kname = line:match('<a exist="(%d+)" noun="key">(.-)</a> appears on the ground!')
        if kid and kname and (kname:find("radiant") or kname:find("vibrant")) then
            klocks[#klocks + 1] = { id = kid, name = kname, type = "key" }
        end
        kid, kname = line:match('<a exist="(%d+)" noun="lock">(.-)</a> appears on the ground!')
        if kid and kname and (kname:find("radiant") or kname:find("vibrant")) then
            klocks[#klocks + 1] = { id = kid, name = kname, type = "lock" }
        end

        -- Gemstone dust
        if line:find("scintillating mote of gemstone dust", 1, true) then
            special_finds[#special_finds + 1] = { type = "gemstone_dust", name = "gemstone dust" }
        end

        -- Gemstone jewel at feet
        local jid, jnoun, jname = line:match('A glint of light catches your eye, and you notice [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a> at your feet!')
        if jid then
            special_finds[#special_finds + 1] = { type = "gemstone_jewel", id = jid, noun = jnoun, name = jname }
        end

        -- LTE boost
        if line:find("Long%-Term Experience Boost", 1, false) then
            special_finds[#special_finds + 1] = { type = "lte_boost", name = "Long-Term Experience Boost" }
        end

        -- Feeder item notification (Duskruin, etc.)
        if line:find("A glint of light draws your attention to your latest find", 1, true) then
            special_finds[#special_finds + 1] = { type = "feeder_item", name = "feeder item" }
        end

        -- Legendary item notification
        if line:find("heralding your discovery of a legendary treasure", 1, true) then
            special_finds[#special_finds + 1] = { type = "legendary_item", name = "legendary item" }
        end

        -- Draconic idol (found while rifling through creature's belongings)
        if line:find("rifling through", 1, true) and line:find("belongings", 1, true) and line:find("find a", 1, true) then
            local source_cid = line:match('<a exist="(%d+)" noun="[^"]+">.-</a>.-belongings')
            local did, dnoun, dname = line:match('find a <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            if did then
                special_finds[#special_finds + 1] = { type = "draconic_idol", id = did, noun = dnoun, name = dname, source_id = source_cid }
            end
        end
    end

    if not creature then return end

    debug_log("Search: " .. creature.name .. " -> " .. (silvers or 0) .. " silvers, " .. #items .. " items")
    record_search(creature.id, creature.name, silvers, items)

    for _, kl in ipairs(klocks) do
        record_klock(kl.id, kl.name)
    end
    for _, sf in ipairs(special_finds) do
        record_special_find(sf.name, sf.type, sf.id, sf.noun, sf.source_id)
    end
end

function Processors.process_skin(chunk)
    for _, line in ipairs(chunk) do
        if line:find("You skinned the ", 1, true) then
            local cid, cnoun, cname = line:match('You skinned the <pushBold/><a exist="(%d+)" noun="([^"]+)">([^<]+)</a><popBold/>')
            if not cid then
                cid, cnoun, cname = line:match('You skinned the .-<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>.-<popBold/>')
            end
            local sid, snoun, sname = line:match('yielding [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            if cid and sid then
                debug_log("Skin: " .. sname .. " from " .. cname)
                record_skin(cid, cname, sid, sname, snoun)
            end
        end
    end
end

function Processors.process_appraisal(chunk)
    local joined = table.concat(chunk, "\n")

    -- Gem appraisal
    local gid, gnoun, gname = joined:match('You peer intently at the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> as you turn it')
    if gid then
        local value_str = joined:match('worth approximately ([%d,]+) silvers')
        if value_str then
            local value = parse_silvers(value_str)
            debug_log("Gem appraisal: " .. gname .. " -> " .. value .. " silvers")
            update_item_appraisal(gid, value, gname, gnoun)
            return
        end
    end

    -- Skin appraisal (individual)
    local sid, snoun, sname = joined:match('You turn the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> over in your hands')
    if sid then
        local value_str = joined:match('worth approximately ([%d,]+) silvers')
        if value_str then
            local value = parse_silvers(value_str)
            debug_log("Skin appraisal: " .. sname .. " -> " .. value .. " silvers")
            update_item_appraisal(sid, value, sname, snoun)
            return
        end
    end

    -- Bundle appraisal (just log, no individual tracking)
    local bundle_val = joined:match('total value of your .- is approximately ([%d,]+) silvers')
    if bundle_val then
        debug_log("Bundle appraisal: ~" .. bundle_val .. " silvers")
    end
end

function Processors.process_loresong(chunk)
    local joined = table.concat(chunk, "\n")

    -- Cache item from "As you sing..." line
    local lid, lnoun, lname = joined:match('As you sing, you feel a faint resonating vibration from the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> in your hand')
    if lid then
        LT.pending_loresong_item = { id = lid, noun = lnoun, name = lname }
        debug_log("Loresong cached: " .. lname .. " (" .. lid .. ")")
    end

    -- Gem shatter
    local shid, shnoun, shname = joined:match('Your focused voice causes the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> to shatter')
    if shid then
        record_gem_shatter(shid, shname, shnoun)
        LT.pending_loresong_item = nil
        return
    end

    -- Value line
    local value_str = joined:match("it's worth about ([%d,]+) silvers")
    if value_str and LT.pending_loresong_item then
        local value = parse_silvers(value_str)
        local p = LT.pending_loresong_item
        debug_log("Loresong: " .. p.name .. " -> " .. value .. " silvers")
        update_item_loresong(p.id, value, p.name, p.noun)
        LT.pending_loresong_item = nil
    end
end

function Processors.process_bundle(chunk)
    for _, line in ipairs(chunk) do
        -- Bundle create: "As you place your <skin> inside your <container>...the two <bundle>"
        if line:find("into a neat bundle", 1, true) then
            local sk_id, sk_noun, sk_name = line:match('place your <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> inside')
            local ct_id, ct_noun, ct_name = line:match('inside your <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            local bd_id, bd_noun, bd_name = line:match('two <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> into a neat bundle')
            if sk_id and ct_id and bd_id then
                record_bundle_event("bundle_create", sk_id, sk_name, bd_id, bd_name, ct_id, ct_name)
            elseif line:find("arrange your two", 1, true) then
                local mid, mnoun, mname = line:match('your two <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> into a neat bundle')
                if mid then
                    record_bundle_event("bundle_create", mid, mname, mid, mname, nil, nil)
                end
            end
        end

        -- Bundle add: "You carefully add your <skin> to your bundle of <bundle>"
        if line:find("You carefully add your", 1, true) then
            local sk_id, sk_noun, sk_name = line:match('add your <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> to')
            local bd_id, bd_noun, bd_name = line:match('bundle of <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> inside')
            local ct_id, ct_noun, ct_name = line:match('inside your <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>%.')
            if sk_id and bd_id then
                record_bundle_event("bundle_add", sk_id, sk_name, bd_id, bd_name, ct_id, ct_name)
            end
        end
    end
end

function Processors.process_box(chunk)
    for _, line in ipairs(chunk) do
        -- Box return from pool
        if line:find("here's your", 1, true) and line:find("back", 1, true) then
            local bid, bnoun, bname = line:match('here\'s your <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> back')
            if bid then
                debug_log("Box returned from pool: " .. bname)
                link_returned_pool_box(bid, bname)
                return
            end
        end

        -- LOOK IN wedged box
        if line:find("<container id=", 1, true) then
            local box_id = line:match("<container id='(%d+)'")
            if box_id then
                local box_noun = line:match('In the <a exist="%d+" noun="([^"]+)">')
                local box_name = line:match('In the <a exist="%d+" noun="[^"]+">([^<]+)</a>:')
                if box_noun and BOX_NOUNS[box_noun] then
                    local items = extract_inv_items(line)
                    -- Find unopened box
                    local name_lower = (box_name or ""):lower()
                    local box_item = find_first_item(function(i)
                        return i.item_type == "box" and not i.opened_at and not i.lost_at
                            and i.item_name:lower():find(name_lower, 1, true) ~= nil
                    end)
                    if box_item then
                        debug_log("Box (LOOK IN): " .. (box_name or "") .. " -> " .. #items .. " items")
                        record_box_open(box_id, box_name or "", nil, items, box_item.id)
                    end
                    return
                end
            end
        end

        -- Manual silver gather: "You gather the remaining X coins from inside your <box>"
        local sil_str, bid2, bnoun2, bname2 = line:match('You gather the remaining ([%d,]+) <a exist="%d+" noun="coins">coins</a> from inside [Yy]?o?u?r?%s*[Aa]?n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
        if sil_str and bid2 then
            local sil = parse_silvers(sil_str)
            debug_log("Silver gather: " .. sil .. " from " .. bname2)
            if not update_box_silvers(bid2, sil) then
                record_transaction(sil, "box_silver")
            end
            return
        end

        -- Charm silver gather
        if line:find("You summon a swarm of", 1, true) and line:find("reclaiming them", 1, true) then
            local cbid, cbnoun, cbname = line:match('inside [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            local csil = line:match('locate a pile of ([%d,]+)')
            if cbid and csil then
                local sil = parse_silvers(csil)
                debug_log("Silver gather (charm): " .. sil .. " from " .. cbname)
                if not update_box_silvers(cbid, sil) then
                    record_transaction(sil, "box_silver")
                end
                return
            end
        end
    end
end

function Processors.process_locksmith(chunk)
    for _, line in ipairs(chunk) do
        -- Pool quote
        if line:find("You want a locksmith to open", 1, true) then
            local bid, bnoun, bname = line:match('open [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            local tip_str = line:match('tip of ([%d,]+) silvers')
            local fee_str = line:match('fee of ([%d,]+) silvers')
            if bid and tip_str and fee_str then
                LT.pending_pool_drop = {
                    box_id = bid, box_noun = bnoun, box_name = bname,
                    tip = parse_silvers(tip_str), fee = parse_silvers(fee_str),
                }
                debug_log("Pool quote: " .. bname .. " tip=" .. tip_str .. " fee=" .. fee_str)
            end
        end

        -- Pool confirmation
        if line:find("Your tip of", 1, true) and line:find("fee has been collected", 1, true) then
            local box_noun = line:match('takes your (%w+) and says')
            local tip_str = line:match('Your tip of ([%d,]+) silvers')
            local fee_str = line:match('the ([%d,]+) silvers? fee has been collected')
            if tip_str and fee_str then
                local tip = parse_silvers(tip_str)
                local fee = parse_silvers(fee_str)
                local pending = LT.pending_pool_drop
                if pending and pending.box_noun == box_noun and pending.tip == tip and pending.fee == fee then
                    debug_log("Pool confirm: " .. pending.box_name .. " tip=" .. tip .. " fee=" .. fee)
                    record_pool_drop(pending.box_id, pending.box_name, tip, fee)
                    LT.pending_pool_drop = nil
                else
                    record_transaction(-fee, "locksmith_fee")
                    if tip > 0 then record_transaction(-tip, "locksmith_tip") end
                end
            end
        end
    end
end

function Processors.process_sell(chunk)
    local pending_item = nil
    local is_worthless = false

    for _, line in ipairs(chunk) do
        -- Offer trigger
        if line:find("You offer to sell your", 1, true) then
            local sid, snoun, sname = line:match('sell your <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            if sid then pending_item = { id = sid, noun = snoun, name = sname } end
        end

        -- Worthless
        if line:find("That's basically worthless here,", 1, true) then
            is_worthless = true
        end
        if line:find("Where do you find this junk", 1, true) then
            is_worthless = true
        end

        -- Direct silver payment
        if line:find("glances at it briefly, then hands you", 1, true) then
            local sid, snoun, sname, sil = line:match('takes your <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>, glances at it briefly, then hands you ([%d,]+) silver coins')
            if sid and sil then
                local amount = parse_silvers(sil)
                local loot_item_id = update_item_sold(sid, amount, "pawn_sale", sname, snoun)
                debug_log("Pawn sale: " .. sname .. " -> +" .. amount .. " silvers")
                record_transaction(amount, "pawn_sale", nil, sname, loot_item_id)
                pending_item = nil
            end
        end

        -- Note/chit payment
        if line:find("scribbles out a", 1, true) and line:find("and hands it to you", 1, true) then
            local val_str = line:match('for ([%d,]+) silvers? and hands it to you')
            if val_str then
                local amount = parse_silvers(val_str)
                local loot_item_id = nil
                if pending_item then
                    loot_item_id = update_item_sold(pending_item.id, amount, "pawn_sale", pending_item.name, pending_item.noun)
                    debug_log("Pawn sale (note): " .. pending_item.name .. " -> +" .. amount .. " silvers")
                end
                record_transaction(amount, "pawn_sale", nil, pending_item and pending_item.name, loot_item_id)
                pending_item = nil
            end
        end
    end

    -- Handle worthless item
    if is_worthless and pending_item then
        local loot_item_id = update_item_sold(pending_item.id, 0, "pawn_sale", pending_item.name, pending_item.noun)
        record_transaction(0, "pawn_sale", nil, pending_item.name, loot_item_id)
    end
end

function Processors.process_shop_appraisal(chunk)
    local joined = table.concat(chunk, "\n")

    -- Jeweler single-line
    local jid, jnoun, jname, jsil = joined:match('takes the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> and inspects it carefully before saying, "I\'ll give you ([%d,]+) silvers? for it')
    if jid and jsil then
        update_item_shop_appraisal(jid, parse_silvers(jsil), jname, jnoun)
        return
    end

    -- "probably worth about" format
    local wid, wnoun, wname, wsil = joined:match('That <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> looks decent, probably worth about ([%d,]+) silvers')
    if wid and wsil then
        update_item_shop_appraisal(wid, parse_silvers(wsil), wname, wnoun)
        return
    end

    -- Pawn multi-line: step 1 - cache
    local pid, pnoun, pname = joined:match('turns the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a> over in [hH]')
    if pid then
        LT.pending_shop_appraise_item = { id = pid, noun = pnoun, name = pname }
    end

    -- Pawn multi-line: step 2 - value
    local val_str = joined:match("I[' ]ll [gGoO]%w+ you ([%d,]+) silver")
    if not val_str then
        val_str = joined:match("I will [oO]ffer you ([%d,]+) silver")
    end
    if val_str and LT.pending_shop_appraise_item then
        local p = LT.pending_shop_appraise_item
        update_item_shop_appraisal(p.id, parse_silvers(val_str), p.name, p.noun)
        LT.pending_shop_appraise_item = nil
    end
end

function Processors.process_gemshop(chunk)
    for _, line in ipairs(chunk) do
        -- ASK trigger (cache for rejection detection)
        if line:find("You ask", 1, true) and (line:find("would like to buy", 1, true) or line:find("to appraise", 1, true)) then
            local gid, gnoun, gname = line:match('<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
            if gid then
                LT.pending_gemshop_ask = { id = gid, noun = gnoun, name = gname }
            end
        end

        -- Rejection
        if line:find("not buying anything this valuable today", 1, true) and LT.pending_gemshop_ask then
            record_gemshop_rejection(LT.pending_gemshop_ask.id, LT.pending_gemshop_ask.name, LT.pending_gemshop_ask.noun)
            LT.pending_gemshop_ask = nil
        end

        -- Individual gem sale
        if line:find("gives it a careful examination and hands you", 1, true) then
            LT.pending_gemshop_ask = nil
            local gid, gnoun, gname = line:match('takes the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>, gives it a careful examination')
            local sil = line:match('hands you ([%d,]+) silver for it')
            if gid and sil then
                local amount = parse_silvers(sil)
                local loot_item_id = update_item_sold(gid, amount, "gem_sale", gname, gnoun)
                debug_log("Gem sale: " .. gname .. " -> +" .. amount .. " silvers")
                record_transaction(amount, "gem_sale", nil, gname, loot_item_id)
            end
        end

        -- Gem sale via note
        if line:find("gives it a careful examination and", 1, true) and line:find("note", 1, true) and line:find("silvers", 1, true) then
            local gid, gnoun, gname = line:match('takes the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>, gives it a careful examination')
            local sil = line:match('note.-for ([%d,]+) silvers')
            if gid and sil then
                local amount = parse_silvers(sil)
                local loot_item_id = update_item_sold(gid, amount, "gem_sale", gname, gnoun)
                debug_log("Gem sale (note): " .. gname .. " -> +" .. amount .. " silvers")
                record_transaction(amount, "gem_sale", nil, gname, loot_item_id)
            end
        end

        -- Bulk gem sale (cash)
        if line:find("removes the gems", 1, true) and line:find("hands it back to you", 1, true) then
            local sil = line:match('along with ([%d,]+) silver')
            if sil then
                local amount = parse_silvers(sil)
                debug_log("Bulk gem sale: +" .. amount .. " silvers")
                record_transaction(amount, "gem_sale", "bulk")
            end
        end

        -- Bulk gem sale (chit)
        if line:find("removes the gems and hands you", 1, true) then
            local sil = line:match('for ([%d,]+) silvers')
            if sil then
                local amount = parse_silvers(sil)
                debug_log("Bulk gem sale (chit): +" .. amount .. " silvers")
                record_transaction(amount, "gem_sale", "bulk_chit")
            end
        end
    end
end

function Processors.process_furrier(chunk)
    for _, line in ipairs(chunk) do
        -- Individual skin sale
        local fid, fnoun, fname, fsil
        -- "scrutinizes it carefully" or "appraises it minutely"
        fid, fnoun, fname = line:match('takes the <a exist="(%d+)" noun="([^"]+)">([^<]+)</a>, [sa]')
        if fid then
            fsil = line:match('then [hp]%w+ you ([%d,]+) silvers')
            if fsil then
                local amount = parse_silvers(fsil)
                local loot_item_id = update_item_sold(fid, amount, "furrier_sale")
                debug_log("Furrier sale: " .. fname .. " -> +" .. amount .. " silvers")
                record_transaction(amount, "furrier_sale", nil, fname, loot_item_id)
            end
        end

        -- Bulk skin sale
        if line:find("removes the item", 1, true) and line:find("hands it back to you", 1, true) then
            local sil = line:match('along with ([%d,]+) silver')
            if sil then
                local amount = parse_silvers(sil)
                debug_log("Bulk furrier sale: +" .. amount .. " silvers")
                record_transaction(amount, "furrier_sale", "bulk")
            end
        end
    end
end

function Processors.process_bank(chunk)
    for _, line in ipairs(chunk) do
        local stripped = strip_xml(line)

        -- Silver deposit
        local dep = line:match("You deposit ([%d,]+) silvers? into your account")
        if dep then
            record_transaction(parse_silvers(dep), "bank_deposit")
            goto continue_bank
        end

        -- Note deposit (written single note: "You deposit your note worth X into your account")
        local ndep_note = stripped:match("You deposit your notes? worth ([%d,]+) into your account")
        if ndep_note then
            record_transaction(parse_silvers(ndep_note), "note_deposit")
            goto continue_bank
        end

        -- Bulk note deposit step 1: "They add up to X silvers"
        local bulk_note = stripped:match("They add up to ([%d,]+) silvers?")
        if bulk_note then
            record_transaction(parse_silvers(bulk_note), "note_deposit")
            goto continue_bank
        end

        -- Bulk note deposit step 2 / note total: "That's a total of X silvers, bringing your balance to"
        local ndep = stripped:match("That's a total of ([%d,]+) silvers")
        if ndep then
            record_transaction(parse_silvers(ndep), "note_deposit")
            goto continue_bank
        end

        -- Silver withdrawal (teller hands you silvers)
        local wd = line:match("hands you ([%d,]+) silvers?")
        if wd and (line:find("teller carefully records", 1, true) or line:find("teller scribbles", 1, true)) then
            record_transaction(-parse_silvers(wd), "bank_withdrawal")
            goto continue_bank
        end
        local wd2 = line:match("Very well, a withdrawal of ([%d,]+) silvers")
        if wd2 then
            record_transaction(-parse_silvers(wd2), "bank_withdrawal")
            goto continue_bank
        end

        -- Note withdrawal via Terras scrip
        do
            local nw_sil, nw_fee = stripped:match("scrip for ([%d,]+) silvers?, with a ([%d,]+) silvers? fee")
            if nw_sil then
                record_transaction(-parse_silvers(nw_sil), "note_withdrawal")
                goto continue_bank
            end
        end

        -- Player give (sending silvers to another player)
        do
            local pg_sil = stripped:match("^You give .+ ([%d,]+) coins%.$")
            if pg_sil then
                record_transaction(-parse_silvers(pg_sil), "player_give")
                goto continue_bank
            end
        end

        -- Debt payment
        do
            local debt_str = stripped:match("I have a bill of ([%d,]+) silvers?")
            if debt_str then
                record_transaction(-parse_silvers(debt_str), "debt_payment")
                goto continue_bank
            end
        end

        ::continue_bank::
    end
end

function Processors.process_bounty(chunk)
    for _, line in ipairs(chunk) do
        local bp, xp, sil = line:match("%[You have earned ([%d,]+) bounty points?, ([%d,]+) experience points?, and ([%d,]+) silver%.%]")
        if bp then
            record_bounty(parse_silvers(bp), parse_silvers(xp), parse_silvers(sil))
        end
    end
end

function Processors.process_chronomage(chunk)
    for _, line in ipairs(chunk) do
        if line:find("gleefully snatches", 1, true) then
            local rid, rnoun, rname = line:match('<a exist="(%d+)" noun="([^"]+)">([^<]+)</a> from your outreached hand')
            local credit = line:match("I'll charge you ([%d,]+) silvers less")
            if rid and credit then
                record_chronomage_ring(rid, rnoun, rname, parse_silvers(credit))
            end
        end
    end
end

-- Standalone special find processor for events not inside a search chunk
function Processors.process_special_find(chunk)
    for _, line in ipairs(chunk) do
        if line:find("A glint of light draws your attention to your latest find", 1, true) then
            record_special_find("feeder item", "feeder_item")
        end
        if line:find("heralding your discovery of a legendary treasure", 1, true) then
            record_special_find("legendary item", "legendary_item")
        end
    end
end

function Processors.process_wand_dupe(chunk)
    local joined = table.concat(chunk, "\n")
    if not joined:find("looking almost identical to the original", 1, true) then return end

    -- Extract donor wand
    local did, dnoun, dname = joined:match('You gesture at [Aa]n?%s*<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
    if not did then return end

    -- Extract new wand from hand display
    local nid, nnoun, nname
    for _, line in ipairs(chunk) do
        nid, nnoun, nname = line:match('<[lr]%w+ exist="(%d+)" noun="([^"]+)">([^<]+)</')
        if nid then break end
    end
    if not nid then return end

    record_wand_dupe(
        { id = did, noun = dnoun, name = dname },
        { id = nid, noun = nnoun, name = nname }
    )
end

--------------------------------------------------------------------------------
-- Chunk Dispatcher
-- Examines a buffered chunk and routes to the appropriate processor.
--------------------------------------------------------------------------------

local function dispatch_chunk(chunk)
    local joined = table.concat(chunk, "\n")

    -- Order matters: most specific first
    if joined:find("You search the ", 1, true) then
        Processors.process_search(chunk)
    elseif joined:find("You skinned the ", 1, true) then
        Processors.process_skin(chunk)
    elseif joined:find("You peer intently at the ", 1, true) or
           (joined:find("You turn the ", 1, true) and joined:find("inspecting for flaws", 1, true)) then
        Processors.process_appraisal(chunk)
    elseif joined:find("faint resonating vibration", 1, true) or
           joined:find("it's worth about", 1, true) or
           joined:find("to shatter into thousands", 1, true) then
        Processors.process_loresong(chunk)
    elseif joined:find("into a neat bundle", 1, true) or
           joined:find("You carefully add your", 1, true) then
        Processors.process_bundle(chunk)
    elseif joined:find("here's your", 1, true) and joined:find("back", 1, true) then
        Processors.process_box(chunk)
    elseif joined:find("<container id=", 1, true) and joined:find("In the <a", 1, true) then
        Processors.process_box(chunk)
    elseif joined:find("You gather the remaining", 1, true) then
        Processors.process_box(chunk)
    elseif joined:find("You summon a swarm of", 1, true) then
        Processors.process_box(chunk)
    elseif joined:find("You want a locksmith to open", 1, true) or
           (joined:find("Your tip of", 1, true) and joined:find("fee has been collected", 1, true)) then
        Processors.process_locksmith(chunk)
    elseif joined:find("You offer to sell your", 1, true) or
           joined:find("glances at it briefly", 1, true) or
           joined:find("That's basically worthless here", 1, true) then
        Processors.process_sell(chunk)
    elseif joined:find("turns the ", 1, true) and joined:find("over in h", 1, true) then
        Processors.process_shop_appraisal(chunk)
    elseif joined:find("I'll give you", 1, true) or joined:find("I will offer you", 1, true) then
        Processors.process_shop_appraisal(chunk)
    elseif joined:find("probably worth about", 1, true) then
        Processors.process_shop_appraisal(chunk)
    elseif joined:find("gives it a careful examination and hands you", 1, true) or
           joined:find("removes the gems", 1, true) or
           joined:find("not buying anything this valuable today", 1, true) or
           (joined:find("You ask", 1, true) and (joined:find("would like to buy", 1, true) or joined:find("to appraise", 1, true))) then
        Processors.process_gemshop(chunk)
    elseif joined:find("scrutinizes it carefully", 1, true) or
           joined:find("appraises it minutely", 1, true) or
           (joined:find("removes the item", 1, true) and joined:find("hands it back", 1, true)) then
        Processors.process_furrier(chunk)
    elseif joined:find("You deposit", 1, true) and joined:find("into your account", 1, true) then
        Processors.process_bank(chunk)
    elseif joined:find("teller carefully records", 1, true) or joined:find("teller scribbles", 1, true) then
        Processors.process_bank(chunk)
    elseif joined:find("Very well, a withdrawal of", 1, true) then
        Processors.process_bank(chunk)
    elseif joined:find("That's a total of", 1, true) and joined:find("bringing your balance to", 1, true) then
        Processors.process_bank(chunk)
    elseif joined:find("They add up to", 1, true) then
        Processors.process_bank(chunk)
    elseif joined:find("scrip for", 1, true) and joined:find("silvers? fee", 1, true) then
        Processors.process_bank(chunk)
    elseif joined:find("I have a bill of", 1, true) and joined:find("silvers", 1, true) then
        Processors.process_bank(chunk)
    elseif joined:find("You give", 1, true) and joined:find("coins.", 1, true) then
        Processors.process_bank(chunk)
    -- Standalone special finds (outside search context, e.g. Duskruin feeder items)
    elseif joined:find("A glint of light draws your attention to your latest find", 1, true) then
        Processors.process_special_find(chunk)
    elseif joined:find("heralding your discovery of a legendary treasure", 1, true) then
        Processors.process_special_find(chunk)
    elseif joined:find("[You have earned", 1, true) and joined:find("bounty point", 1, true) then
        Processors.process_bounty(chunk)
    elseif joined:find("gleefully snatches", 1, true) and joined:find("silvers less", 1, true) then
        Processors.process_chronomage(chunk)
    elseif joined:find("looking almost identical to the original", 1, true) then
        Processors.process_wand_dupe(chunk)
    end
end

--------------------------------------------------------------------------------
-- Reports
--------------------------------------------------------------------------------

local Reports = {}

--- Compute estimated value for loot cap purposes
local function calculate_estimated_value(item)
    if not item then return nil end

    -- Ingots: no trading bonus
    if item.item_type == "ingot" then
        return item.sold_value or item.shop_appraisal
    elseif item.item_type == "gem" then
        if item.loresong_value then return item.loresong_value end
        if item.appraised_value then return item.appraised_value end
    elseif item.pawn_cap_value then
        return item.pawn_cap_value
    elseif item.shop_appraisal and not item.sold_value then
        if item.shop_appraisal >= PAWN_CAP_VALUE then return PAWN_CAP_VALUE end
        local total_bonus = (item.sold_trading_bonus or 0) + (item.sold_racial_bonus or 0)
        if total_bonus == 0 then return item.shop_appraisal end
        return math.floor(item.shop_appraisal / (1 + total_bonus / 100) + 0.5)
    end

    -- Fallback from sold value
    if not item.sold_value then return nil end
    if item.sold_value == PAWN_CAP_VALUE then return PAWN_CAP_VALUE end

    local total_bonus = (item.sold_trading_bonus or 0) + (item.sold_racial_bonus or 0)
    if total_bonus == 0 then return item.sold_value end
    return math.floor(item.sold_value / (1 + total_bonus / 100) + 0.5)
end

local function sum_estimated_values(items_list)
    local total = 0
    for _, item in ipairs(items_list) do
        total = total + (calculate_estimated_value(item) or 0)
    end
    return total
end

function Reports.summary_for_range(start_time, end_time, data)
    data = data or LT.data
    end_time = end_time or now()
    local char = LT.character

    local result = {
        start_time = start_time, end_time = end_time,
        search_count = 0, box_count = 0, skin_count = 0,
        silvers_search = 0, silvers_boxes = 0,
        items_found = 0, gems_found = 0, boxes_found = 0, skins_found = 0,
        klocks_found = 0, magic_found = 0, other_found = 0,
        gem_sales = 0, pawn_sales = 0, furrier_sales = 0,
        locksmith_fees = 0, locksmith_tips = 0,
        bank_deposits = 0, bank_withdrawals = 0, bounty_silver = 0,
        bounty_points = 0, bounty_experience = 0,
    }

    for _, e in ipairs(data.loot_events) do
        if e.character == char and e.created_at >= start_time and e.created_at < end_time then
            if e.event_type == "search" then
                result.search_count = result.search_count + 1
                result.silvers_search = result.silvers_search + (e.silvers_found or 0)
            elseif e.event_type == "box_open" then
                result.box_count = result.box_count + 1
                result.silvers_boxes = result.silvers_boxes + (e.silvers_found or 0)
            end
        end
    end

    for _, e in ipairs(data.skin_events) do
        if e.character == char and e.created_at >= start_time and e.created_at < end_time then
            result.skin_count = result.skin_count + 1
        end
    end

    for _, item in ipairs(data.loot_items) do
        if item.searcher == char and item.created_at >= start_time and item.created_at < end_time then
            result.items_found = result.items_found + 1
            if item.item_type == "gem" then result.gems_found = result.gems_found + 1
            elseif item.item_type == "box" then result.boxes_found = result.boxes_found + 1
            elseif item.item_type == "skin" then result.skins_found = result.skins_found + 1
            elseif item.item_type == "klock" then result.klocks_found = result.klocks_found + 1
            elseif item.item_type == "magic" then result.magic_found = result.magic_found + 1
            else result.other_found = result.other_found + 1
            end
        end
    end

    for _, tx in ipairs(data.transactions) do
        if tx.character == char and tx.created_at >= start_time and tx.created_at < end_time then
            local cat = tx.category
            local amt = tx.amount or 0
            if cat == "gem_sale" then result.gem_sales = result.gem_sales + amt
            elseif cat == "pawn_sale" then result.pawn_sales = result.pawn_sales + amt
            elseif cat == "furrier_sale" then result.furrier_sales = result.furrier_sales + amt
            elseif cat == "locksmith_fee" then result.locksmith_fees = result.locksmith_fees + amt
            elseif cat == "locksmith_tip" then result.locksmith_tips = result.locksmith_tips + amt
            elseif cat == "bank_deposit" then result.bank_deposits = result.bank_deposits + amt
            elseif cat == "bank_withdrawal" then result.bank_withdrawals = result.bank_withdrawals + amt
            elseif cat == "bounty_silver" then result.bounty_silver = result.bounty_silver + amt
            end
        end
    end

    for _, b in ipairs(data.bounty_rewards) do
        if b.character == char and b.created_at >= start_time and b.created_at < end_time then
            result.bounty_points = result.bounty_points + (b.bounty_points or 0)
            result.bounty_experience = result.bounty_experience + (b.experience or 0)
        end
    end

    return result
end

function Reports.summary_today()
    local t = os.date("*t")
    local start = os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
    return Reports.summary_for_range(start)
end

function Reports.summary_last_hours(hours)
    return Reports.summary_for_range(now() - hours * 3600)
end

function Reports.summary_month()
    local t = os.date("*t")
    local start = os.time({ year = t.year, month = t.month, day = 1, hour = 0, min = 0, sec = 0 })
    return Reports.summary_for_range(start)
end

function Reports.loot_cap_summary(year, month)
    local t = os.date("*t")
    year = year or t.year
    month = month or t.month

    local start_time = os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
    local end_year, end_month = year, month + 1
    if end_month > 12 then end_year = end_year + 1; end_month = 1 end
    local end_time = os.time({ year = end_year, month = end_month, day = 1, hour = 0, min = 0, sec = 0 })

    local data = load_month_data(year, month)
    local char = LT.character

    local search_count = 0
    local boxes_found = 0
    local boxes_lost = 0
    local skin_count = 0
    local silvers_loose = 0
    local silvers_boxes = 0
    local bounty_silver = 0

    for _, e in ipairs(data.loot_events) do
        if e.character == char then
            if e.event_type == "search" then
                search_count = search_count + 1
                silvers_loose = silvers_loose + (e.silvers_found or 0)
            elseif e.event_type == "box_open" then
                silvers_boxes = silvers_boxes + (e.silvers_found or 0)
            end
        end
    end

    for _, e in ipairs(data.skin_events) do
        if e.character == char then skin_count = skin_count + 1 end
    end

    for _, item in ipairs(data.loot_items) do
        if item.searcher == char and item.item_type == "box" then
            boxes_found = boxes_found + 1
            if item.lost_at then boxes_lost = boxes_lost + 1 end
        end
    end

    for _, b in ipairs(data.bounty_rewards) do
        if b.character == char then bounty_silver = bounty_silver + (b.silver or 0) end
    end

    -- Item breakdown
    local item_types = {}
    local type_order = {"gem","valuable","wand","jewelry","magic","weapon","armor","skin","clothing","scroll","collectible","lockpick","scarab","reagent","food","jar","boon","klock","ingot","junk"}

    -- Collect loot items (excluding boxes)
    local loot_sources = { search = true, box = true, skin = true, special_find = true }
    for _, itype in ipairs(type_order) do
        if itype ~= "wand" then
            local type_items = {}
            for _, item in ipairs(data.loot_items) do
                if item.searcher == char and item.item_type == itype
                   and loot_sources[item.item_source] then
                    type_items[#type_items + 1] = item
                end
            end
            if #type_items > 0 then
                local realized = 0
                for _, i in ipairs(type_items) do realized = realized + (i.sold_value or 0) end
                item_types[itype] = {
                    count = #type_items,
                    estimated = sum_estimated_values(type_items),
                    realized = realized,
                }
            end
        end
    end

    -- Wands: separate handling
    local searched_wands = {}
    local all_wands = {}
    local duped_count = 0
    for _, item in ipairs(data.loot_items) do
        if item.searcher == char and item.item_type == "wand" then
            all_wands[#all_wands + 1] = item
            if item.item_source == "search" then searched_wands[#searched_wands + 1] = item end
            if item.item_source == "wand_dupe" then duped_count = duped_count + 1 end
        end
    end
    if #all_wands > 0 then
        local wand_realized = 0
        for _, w in ipairs(all_wands) do wand_realized = wand_realized + (w.sold_value or 0) end
        item_types["wand"] = {
            count = #all_wands,
            searched = #searched_wands,
            duped = duped_count,
            estimated = sum_estimated_values(searched_wands),
            realized = wand_realized,
        }
    end

    -- Special finds
    local special_types = { gemstone_dust=true, gemstone_jewel=true, lte_boost=true, feeder_item=true, legendary_item=true, draconic_idol=true }
    local special_finds = 0
    for _, item in ipairs(data.loot_items) do
        if item.searcher == char and special_types[item.item_type] then
            special_finds = special_finds + 1
        end
    end

    -- Unsold at pawn cap
    local unsold_at_cap = 0
    for _, item in ipairs(data.loot_items) do
        if item.searcher == char and loot_sources[item.item_source]
           and item.item_type ~= "box" and not item.sold_value then
            if item.pawn_cap_value == PAWN_CAP_VALUE or (item.shop_appraisal and item.shop_appraisal >= PAWN_CAP_VALUE) then
                unsold_at_cap = unsold_at_cap + 1
            end
        end
    end

    return {
        year = year, month = month,
        start_time = start_time, end_time = end_time,
        search_count = search_count,
        boxes_found = boxes_found, boxes_lost = boxes_lost,
        skin_count = skin_count,
        silvers_loose = silvers_loose, silvers_boxes = silvers_boxes,
        bounty_silver = bounty_silver,
        items = item_types,
        special_finds = special_finds,
        unsold_at_cap = unsold_at_cap,
    }
end

function Reports.recent_items(limit, type_filter)
    limit = limit or 20
    local char = LT.character
    local results = {}

    -- Collect matching items
    for _, item in ipairs(LT.data.loot_items) do
        if item.searcher == char then
            if not type_filter or item.item_type == type_filter then
                results[#results + 1] = item
            end
        end
    end

    -- Sort by created_at descending
    table.sort(results, function(a, b) return a.created_at > b.created_at end)

    -- Limit
    local out = {}
    for i = 1, math.min(limit, #results) do
        out[i] = results[i]
    end
    return out
end

function Reports.recent_boxes(limit)
    limit = limit or 20
    local char = LT.character
    local results = {}

    for _, e in ipairs(LT.data.loot_events) do
        if e.event_type == "box_open" and e.character == char then
            results[#results + 1] = e
        end
    end

    table.sort(results, function(a, b) return a.created_at > b.created_at end)

    local out = {}
    for i = 1, math.min(limit, #results) do
        out[i] = results[i]
    end
    return out
end

function Reports.creature_stats(limit)
    limit = limit or 10
    local char = LT.character
    local start_time = now() - 86400

    -- Aggregate by source_name
    local stats = {}
    for _, e in ipairs(LT.data.loot_events) do
        if e.event_type == "search" and e.character == char and e.created_at >= start_time then
            local name = e.source_name or "unknown"
            if not stats[name] then
                stats[name] = { source_name = name, kills = 0, silvers = 0 }
            end
            stats[name].kills = stats[name].kills + 1
            stats[name].silvers = stats[name].silvers + (e.silvers_found or 0)
        end
    end

    local sorted = {}
    for _, v in pairs(stats) do sorted[#sorted + 1] = v end
    table.sort(sorted, function(a, b) return a.silvers > b.silvers end)

    local out = {}
    for i = 1, math.min(limit, #sorted) do
        out[i] = sorted[i]
    end
    return out
end

function Reports.transactions_by_category()
    local char = LT.character
    local start_time = now() - 86400

    local cats = {}
    for _, tx in ipairs(LT.data.transactions) do
        if tx.character == char and tx.created_at >= start_time then
            if not cats[tx.category] then
                cats[tx.category] = { category = tx.category, total = 0, count = 0 }
            end
            cats[tx.category].total = cats[tx.category].total + (tx.amount or 0)
            cats[tx.category].count = cats[tx.category].count + 1
        end
    end

    local sorted = {}
    for _, v in pairs(cats) do sorted[#sorted + 1] = v end
    table.sort(sorted, function(a, b) return a.total > b.total end)
    return sorted
end

function Reports.wands()
    local char = LT.character
    local sources = {}
    local dupes = {}

    for _, item in ipairs(LT.data.loot_items) do
        if item.searcher == char and item.item_type == "wand" then
            if item.duplicated_at and (item.item_source == "wand_source" or item.item_source == "search") then
                sources[#sources + 1] = item
            elseif item.item_source == "wand_dupe" then
                dupes[#dupes + 1] = item
            end
        end
    end

    table.sort(sources, function(a, b) return (a.duplicated_at or 0) > (b.duplicated_at or 0) end)
    table.sort(dupes, function(a, b) return (a.duplicated_at or 0) > (b.duplicated_at or 0) end)

    -- Limit to 20 each
    local src_out, dupe_out = {}, {}
    for i = 1, math.min(20, #sources) do src_out[i] = sources[i] end
    for i = 1, math.min(20, #dupes) do dupe_out[i] = dupes[i] end
    return { sources = src_out, dupes = dupe_out }
end

function Reports.box_list(limit)
    limit = limit or 10
    local char = LT.character
    local results = {}

    for _, item in ipairs(LT.data.loot_items) do
        if item.searcher == char and item.item_type == "box" then
            local source_name = nil
            if item.event_id then
                for _, e in ipairs(LT.data.loot_events) do
                    if e.id == item.event_id then source_name = e.source_name; break end
                end
            end
            local silvers = 0
            if item.opened_event_id then
                for _, e in ipairs(LT.data.loot_events) do
                    if e.id == item.opened_event_id then silvers = e.silvers_found or 0; break end
                end
            end
            results[#results + 1] = { box = item, source_name = source_name, silvers = silvers }
        end
    end

    table.sort(results, function(a, b) return a.box.created_at > b.box.created_at end)
    local out = {}
    for i = 1, math.min(limit, #results) do out[i] = results[i] end
    return out
end

function Reports.box_lookup(record_id)
    local char = LT.character
    local box_item = nil

    for _, item in ipairs(LT.data.loot_items) do
        if item.id == tonumber(record_id) and item.item_type == "box" and item.searcher == char then
            box_item = item; break
        end
    end
    if not box_item then return nil end

    local search_event = nil
    if box_item.event_id then
        for _, e in ipairs(LT.data.loot_events) do
            if e.id == box_item.event_id then search_event = e; break end
        end
    end

    local open_event, contents = nil, {}
    if box_item.opened_event_id then
        for _, e in ipairs(LT.data.loot_events) do
            if e.id == box_item.opened_event_id then open_event = e; break end
        end
        for _, item in ipairs(LT.data.loot_items) do
            if item.event_id == box_item.opened_event_id and item.item_type ~= "box" then
                contents[#contents + 1] = item
            end
        end
    end

    return {
        box = box_item,
        search_event = search_event,
        silvers = open_event and (open_event.silvers_found or 0) or 0,
        contents = contents,
    }
end

function Reports.creature_lookup(source_id)
    local char = LT.character
    local source_str = tostring(source_id)

    local search_event = nil
    for i = #LT.data.loot_events, 1, -1 do
        local e = LT.data.loot_events[i]
        if e.event_type == "search" and e.character == char and e.source_id == source_str then
            search_event = e; break
        end
    end

    local skin_event = nil
    for i = #LT.data.skin_events, 1, -1 do
        local e = LT.data.skin_events[i]
        if e.character == char and e.creature_id == source_str then
            skin_event = e; break
        end
    end

    local search_items = {}
    if search_event then
        for _, item in ipairs(LT.data.loot_items) do
            if item.event_id == search_event.id and item.item_type ~= "box" then
                search_items[#search_items + 1] = item
            end
        end
    end

    local skin_item = nil
    if skin_event then
        for _, item in ipairs(LT.data.loot_items) do
            if item.skin_event_id == skin_event.id then skin_item = item; break end
        end
    end

    local boxes = {}
    if search_event then
        for _, item in ipairs(LT.data.loot_items) do
            if item.event_id == search_event.id and item.item_type == "box" then
                local open_event, contents = nil, {}
                if item.opened_event_id then
                    for _, e in ipairs(LT.data.loot_events) do
                        if e.id == item.opened_event_id then open_event = e; break end
                    end
                    for _, ci in ipairs(LT.data.loot_items) do
                        if ci.event_id == item.opened_event_id and ci.item_type ~= "box" then
                            contents[#contents + 1] = ci
                        end
                    end
                end
                boxes[#boxes + 1] = {
                    box = item,
                    silvers = open_event and (open_event.silvers_found or 0) or 0,
                    contents = contents,
                }
            end
        end
    end

    return {
        source_id = source_str,
        search_event = search_event,
        skin_event = skin_event,
        search_items = search_items,
        skin_item = skin_item,
        boxes = boxes,
    }
end

--------------------------------------------------------------------------------
-- CLI Display
--------------------------------------------------------------------------------

local CLI = {}

local function mono_output(lines)
    respond("\n" .. table.concat(lines, "\n") .. "\n")
end

function CLI.show_summary(summary, period_label)
    local char = LT.character
    local game = LT.game
    local time_range = format_time(summary.start_time) .. " - " .. format_time(summary.end_time)

    local silvers_looted = summary.silvers_search + summary.silvers_boxes
    local sales_income = summary.gem_sales + summary.pawn_sales + summary.furrier_sales
    local expenses = summary.locksmith_fees + summary.locksmith_tips
    local net_income = silvers_looted + sales_income + summary.bounty_silver + expenses

    local out = {
        "",
        "LootTracker Summary for " .. char .. " (" .. game .. ")",
        "Period: " .. period_label .. " (" .. time_range .. ")",
        string.rep("-", 55),
        "  Searches:           " .. summary.search_count,
        "  Boxes Opened:       " .. summary.box_count,
        "  Skins:              " .. summary.skin_count,
        "",
        "  Silvers (Search):   " .. format_silver(summary.silvers_search),
        "  Silvers (Boxes):    " .. format_silver(summary.silvers_boxes),
        "  Silvers (Bounty):   " .. format_silver(summary.bounty_silver),
        "                      " .. string.rep("-", 12),
        "  Total Silvers:      " .. format_silver(silvers_looted + summary.bounty_silver),
        "",
        "  Items Found:        " .. summary.items_found,
        "    Gems:             " .. summary.gems_found,
        "    Boxes:            " .. summary.boxes_found,
        "    Skins:            " .. summary.skins_found,
    }
    if summary.klocks_found > 0 then out[#out + 1] = "    Klocks:           " .. summary.klocks_found end
    if summary.magic_found > 0 then out[#out + 1] = "    Magic:            " .. summary.magic_found end
    if summary.other_found > 0 then out[#out + 1] = "    Other:            " .. summary.other_found end

    out[#out + 1] = ""
    out[#out + 1] = "  Sales Income:"
    out[#out + 1] = "    Gem Sales:        " .. format_silver(summary.gem_sales)
    out[#out + 1] = "    Pawn Sales:       " .. format_silver(summary.pawn_sales)
    out[#out + 1] = "    Furrier Sales:    " .. format_silver(summary.furrier_sales)
    out[#out + 1] = ""
    out[#out + 1] = "  Expenses:"
    out[#out + 1] = "    Locksmith Fees:   " .. format_silver(summary.locksmith_fees)
    out[#out + 1] = "    Locksmith Tips:   " .. format_silver(summary.locksmith_tips)
    out[#out + 1] = ""
    out[#out + 1] = "  Bounty Rewards:"
    out[#out + 1] = "    Points:           " .. format_silver(summary.bounty_points)
    out[#out + 1] = "    Experience:       " .. format_silver(summary.bounty_experience)
    out[#out + 1] = string.rep("-", 55)
    out[#out + 1] = "  Net Income:         " .. format_silver(net_income)
    out[#out + 1] = ""

    mono_output(out)
end

function CLI.show_loot_cap(data)
    local char = LT.character
    local game = LT.game

    local month_names = {"January","February","March","April","May","June","July","August","September","October","November","December"}
    local period_label = month_names[data.month] .. " " .. data.year

    local t = os.date("*t")
    local is_current = (data.year == t.year and data.month == t.month)

    local item_order = {"gem","valuable","wand","jewelry","magic","weapon","armor","skin","clothing","scroll","collectible","lockpick","scarab","reagent","food","jar","boon","klock","ingot","junk"}
    local item_labels = {
        gem="Gems",valuable="Valuables",wand="Wands",jewelry="Jewelry",magic="Magic Items",
        weapon="Weapons",armor="Armor",skin="Skins",clothing="Clothing",scroll="Scrolls",
        collectible="Collectibles",lockpick="Lockpicks",scarab="Scarabs",reagent="Reagents",
        food="Food",jar="Jars",boon="Boons",klock="Klocks",ingot="Ingots",junk="Junk",
    }

    local total_estimated = data.silvers_loose + data.silvers_boxes + data.bounty_silver
    local total_realized = data.silvers_loose + data.silvers_boxes + data.bounty_silver

    local out = {
        "",
        "LootTracker - Loot Cap Report for " .. char .. " (" .. game .. ")",
    }
    if is_current then
        out[#out + 1] = "Period: " .. period_label .. " (Month-to-Date)"
        local seconds_until = data.end_time - now()
        if seconds_until > 0 then
            local days = math.floor(seconds_until / 86400)
            local hours = math.floor((seconds_until % 86400) / 3600)
            if days > 0 then
                out[#out + 1] = "Reset: 1st of next month (in " .. days .. "d " .. hours .. "h)"
            else
                out[#out + 1] = "Reset: 1st of next month (in " .. hours .. "h)"
            end
        end
    else
        out[#out + 1] = "Period: " .. period_label
    end

    out[#out + 1] = string.rep("=", 65)
    out[#out + 1] = ""
    out[#out + 1] = "  EVENTS"
    out[#out + 1] = "  " .. string.rep("-", 35)
    out[#out + 1] = "  Searches:             " .. data.search_count
    out[#out + 1] = "  Boxes Found:          " .. data.boxes_found
    if data.boxes_lost > 0 then
        out[#out + 1] = "  Boxes Lost:           " .. data.boxes_lost
    end
    out[#out + 1] = "  Creatures Skinned:    " .. data.skin_count
    out[#out + 1] = ""
    out[#out + 1] = "  LOOT CAP VALUE                     Estimated    Realized"
    out[#out + 1] = "  " .. string.rep("-", 60)
    out[#out + 1] = "  Silvers (loose):         " .. rjust(format_silver(data.silvers_loose), 12) .. "  " .. rjust(format_silver(data.silvers_loose), 11)
    out[#out + 1] = "  Silvers (boxes):         " .. rjust(format_silver(data.silvers_boxes), 12) .. "  " .. rjust(format_silver(data.silvers_boxes), 11)

    if data.items["ingot"] then
        out[#out + 1] = "  Silvers (ingots):      " .. rjust("--", 12) .. "  " .. rjust(format_silver(data.items["ingot"].realized), 11)
    end

    out[#out + 1] = ""

    for _, itype in ipairs(item_order) do
        local item_data = data.items[itype]
        if item_data then
            local label = ljust((item_labels[itype] or itype) .. " (" .. item_data.count .. "):", 24)
            local est_str = item_data.estimated > 0 and rjust(format_silver(item_data.estimated), 12) or rjust("--", 12)
            local real_str = item_data.realized > 0 and rjust(format_silver(item_data.realized), 11) or rjust("--", 11)
            out[#out + 1] = "  " .. label .. " " .. est_str .. "  " .. real_str
            total_estimated = total_estimated + item_data.estimated
            total_realized = total_realized + item_data.realized
        end
    end

    out[#out + 1] = ""
    out[#out + 1] = "  Bounty Silver:           " .. rjust(format_silver(data.bounty_silver), 12) .. "  " .. rjust(format_silver(data.bounty_silver), 11)
    out[#out + 1] = "  " .. string.rep("-", 60)
    out[#out + 1] = "  TOTAL LOOT CAP:          " .. rjust(format_silver(total_estimated), 12) .. "  " .. rjust(format_silver(total_realized), 11)
    out[#out + 1] = "                           " .. rjust("(estimated)", 12) .. "  " .. rjust("(realized)", 11)

    -- 7.5M cap reference
    out[#out + 1] = ""
    local pct_est = total_estimated > 0 and math.floor(total_estimated / LOOT_CAP_MONTHLY * 100) or 0
    local pct_real = total_realized > 0 and math.floor(total_realized / LOOT_CAP_MONTHLY * 100) or 0
    out[#out + 1] = "  Monthly Cap (7.5M):      " .. rjust(pct_est .. "%", 12) .. "  " .. rjust(pct_real .. "%", 11)

    if data.unsold_at_cap > 0 then
        local cap_est = data.unsold_at_cap * PAWN_CAP_VALUE
        out[#out + 1] = ""
        out[#out + 1] = "  " .. ljust("Unsold @ 25k (" .. data.unsold_at_cap .. "):", 24) .. " " .. rjust("0", 12) .. "  " .. rjust(format_silver(cap_est), 11)
    end

    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_recent_items(items, type_filter)
    local type_label = type_filter and (type_filter:sub(1,1):upper() .. type_filter:sub(2) .. "s") or "Items"

    local out = {
        "",
        "Recent " .. #items .. " " .. type_label .. ":",
        string.rep("-", 70),
    }

    for _, item in ipairs(items) do
        local time_str = format_time(item.created_at)
        local item_type = item.item_type or "other"
        if item_type == "gemstone_dust" then item_type = "dust"
        elseif item_type == "gemstone_jewel" then item_type = "jewel"
        elseif item_type == "lte_boost" then item_type = "boost"
        end
        local source = (item.item_source or ""):gsub("_find", ""):gsub("wand_dupe", "dupe"):gsub("wand_source", "source")
        out[#out + 1] = "  " .. ljust(item.item_name, 40) .. " " .. ljust(item_type, 11) .. " " .. ljust(source, 7) .. " " .. time_str
    end

    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_recent_boxes(boxes)
    local total_silvers = 0

    local out = {
        "",
        "Recent Boxes:",
        string.rep("-", 70),
    }

    for _, box in ipairs(boxes) do
        local time_str = format_time(box.created_at)
        local silvers = box.silvers_found or 0
        total_silvers = total_silvers + silvers
        out[#out + 1] = "  " .. ljust(box.source_name or "unknown", 30) .. " " .. rjust(format_silver(silvers), 10) .. " silvers   " .. time_str
    end

    out[#out + 1] = string.rep("-", 70)
    out[#out + 1] = "  " .. ljust("Total: " .. #boxes .. " boxes", 30) .. " " .. rjust(format_silver(total_silvers), 10) .. " silvers"
    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_transactions(data)
    local net = 0

    local out = {
        "",
        "Transaction Breakdown (Last 24 Hours):",
        string.rep("-", 55),
    }

    for _, row in ipairs(data) do
        local category = ljust(row.category, 20)
        local total = row.total or 0
        net = net + total
        local sign = total >= 0 and "+" or ""
        out[#out + 1] = "  " .. category .. " " .. rjust(sign .. format_silver(total), 12) .. "   (" .. row.count .. " transactions)"
    end

    out[#out + 1] = string.rep("-", 55)
    local sign = net >= 0 and "+" or ""
    out[#out + 1] = "  " .. ljust("Net:", 20) .. " " .. rjust(sign .. format_silver(net), 12)
    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_creatures(stats)
    local out = {
        "",
        "Top Creatures (Last 24 Hours):",
        string.rep("-", 60),
    }

    for _, row in ipairs(stats) do
        out[#out + 1] = "  " .. ljust(row.source_name or "unknown", 25) .. " " .. rjust(tostring(row.kills), 4) .. " kills   " .. rjust(format_silver(row.silvers), 10) .. " silvers"
    end

    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_status()
    local out = {
        "",
        "LootTracker Status",
        string.rep("-", 40),
        "  Version:          " .. VERSION,
        "  Tracking:         " .. (LT.enabled and "Active" or "Inactive"),
        "  Debug:            " .. (LT.debug_mode and "ON" or "OFF"),
        "  Data File:        " .. (LT.data_file or "N/A"),
        "  Character:        " .. (LT.character or "Unknown"),
        "  Game:             " .. (LT.game or "Unknown"),
        "",
    }
    mono_output(out)
end

function CLI.show_proxy()
    local out = {
        "",
        "Cross-Character Proxy Settings",
        string.rep("-", 40),
        "  Loresong proxy:   " .. (LT.loresong_proxy or "(none)"),
        "  Appraise proxy:   " .. (LT.appraise_proxy or "(none)"),
        "  Dupe proxy:       " .. (LT.dupe_proxy or "(none)"),
        "",
        "Usage:",
        "  ;lt proxy <name>           - Set all proxies to <name>",
        "  ;lt proxy loresong <name>  - Set loresong proxy only",
        "  ;lt proxy appraise <name>  - Set appraise proxy only",
        "  ;lt proxy dupe <name>      - Set dupe proxy only",
        "  ;lt proxy clear            - Clear all proxies",
        "",
    }
    mono_output(out)
end

function CLI.show_wands(wands_data)
    local sources = wands_data.sources
    local dupes = wands_data.dupes

    local out = {
        "",
        "Wand Duplications",
        string.rep("-", 70),
        "",
        "Source Wands (duplicated):",
    }

    if #sources == 0 then
        out[#out + 1] = "  No wand duplications recorded."
    else
        for _, wand in ipairs(sources) do
            local time_str = wand.duplicated_at and format_time(wand.duplicated_at) or "N/A"
            out[#out + 1] = "  " .. ljust(wand.item_name or "unknown", 40) .. " " .. time_str
        end
    end

    out[#out + 1] = ""
    out[#out + 1] = "Copy Wands (created via 918):"
    out[#out + 1] = string.rep("-", 70)

    if #dupes == 0 then
        out[#out + 1] = "  No copy wands recorded."
    else
        for _, wand in ipairs(dupes) do
            local time_str = wand.duplicated_at and format_time(wand.duplicated_at) or "N/A"
            local source_name = ""
            if wand.dupe_source_id then
                for _, src in ipairs(sources) do
                    if src.id == wand.dupe_source_id then
                        source_name = " (from " .. (src.item_name or "unknown") .. ")"
                        break
                    end
                end
            end
            out[#out + 1] = "  " .. ljust(wand.item_name or "unknown", 35) .. " " .. time_str .. source_name
        end
    end

    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_box_list(boxes)
    local out = {
        "",
        "Recent Boxes (use ';lt box <id>' for details):",
        string.rep("-", 85),
        "  " .. ljust("ID", 14) .. " " .. ljust("Box Name", 28) .. " " .. ljust("Source", 18) .. " " .. ljust("Status", 10) .. " " .. rjust("Silvers", 10),
        "  " .. string.rep("-", 83),
    }

    for _, data in ipairs(boxes) do
        local box = data.box
        local id_str = ljust(tostring(box.id), 14)
        local name_str = ljust((box.item_name or "unknown"):sub(1, 28), 28)
        local source_str = ljust((data.source_name or "unknown"):sub(1, 18), 18)
        local status = box.lost_at and "Lost" or box.opened_at and "Opened" or "Unopened"
        local status_str = ljust(status, 10)
        local silvers_str = box.opened_at and rjust(format_silver(data.silvers), 10) or rjust("-", 10)
        out[#out + 1] = "  " .. id_str .. " " .. name_str .. " " .. source_str .. " " .. status_str .. " " .. silvers_str
    end

    out[#out + 1] = ""
    out[#out + 1] = "Tip: Use ';lt box <id>' to see full details including contents and fees"
    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_box_detail(data)
    local box = data.box
    local out = {
        "",
        "Box Lookup: " .. (box.item_name or "unknown"),
        string.rep("-", 70),
        "",
        "BOX INFO:",
        "  Item ID:       " .. (box.item_id or "N/A"),
        "  Record ID:     " .. tostring(box.id),
        "  Found:         " .. format_time(box.created_at),
    }

    if data.search_event then
        local e = data.search_event
        out[#out + 1] = "  Source:        " .. (e.source_name or "unknown") .. " [creature ID: " .. (e.source_id or "?") .. "]"
    end

    out[#out + 1] = ""
    out[#out + 1] = "POOL INFO:"
    out[#out + 1] = "  Dropped At:    " .. (box.pool_dropped_at and format_time(box.pool_dropped_at) or "N/A")
    out[#out + 1] = "  Fee:           " .. (box.pool_fee and format_silver(box.pool_fee) or "N/A")
    out[#out + 1] = "  Tip:           " .. (box.pool_tip and format_silver(box.pool_tip) or "N/A")

    out[#out + 1] = ""
    out[#out + 1] = "STATUS:"

    if box.opened_at then
        out[#out + 1] = "  Opened:        Yes"
        out[#out + 1] = "  Opened At:     " .. format_time(box.opened_at)
        out[#out + 1] = "  Box Silvers:   " .. format_silver(data.silvers)

        out[#out + 1] = ""
        out[#out + 1] = "CONTENTS:"
        if #data.contents > 0 then
            for _, item in ipairs(data.contents) do
                local val_str = item.sold_value and format_silver(item.sold_value) or
                                item.appraised_value and ("~" .. format_silver(item.appraised_value)) or "--"
                out[#out + 1] = "  " .. ljust(item.item_name or "unknown", 40) .. " " .. ljust(item.item_type or "other", 10) .. " " .. rjust(val_str, 10)
            end
        else
            out[#out + 1] = "  (none recorded)"
        end

        local total_items = 0
        for _, item in ipairs(data.contents) do
            total_items = total_items + (item.sold_value or item.appraised_value or 0)
        end
        local total_cost = (box.pool_fee or 0) + (box.pool_tip or 0)

        out[#out + 1] = ""
        out[#out + 1] = string.rep("-", 70)
        out[#out + 1] = "NET VALUE:"
        out[#out + 1] = "  Silvers from box:  " .. format_silver(data.silvers)
        out[#out + 1] = "  Items Value:       " .. format_silver(total_items)
        out[#out + 1] = "  Pool costs:        -" .. format_silver(total_cost)
        out[#out + 1] = "  Net:               " .. format_silver(data.silvers + total_items - total_cost)
    elseif box.lost_at then
        out[#out + 1] = "  Lost:          Yes"
        out[#out + 1] = "  Lost At:       " .. format_time(box.lost_at)
    else
        out[#out + 1] = "  Opened:        No"
    end

    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_creature_lookup(data)
    if not data.search_event and not data.skin_event then
        respond("No records found for creature ID: " .. data.source_id)
        return
    end

    local creature_name = (data.search_event and data.search_event.source_name)
                       or (data.skin_event and data.skin_event.creature_name)
                       or "Unknown"

    local total_silvers = data.search_event and (data.search_event.silvers_found or 0) or 0
    local total_fees, total_tips = 0, 0
    for _, bd in ipairs(data.boxes) do
        total_silvers = total_silvers + bd.silvers
        total_fees = total_fees + (bd.box.pool_fee or 0)
        total_tips = total_tips + (bd.box.pool_tip or 0)
    end

    local total_items = 0
    for _, item in ipairs(data.search_items) do
        total_items = total_items + (item.sold_value or item.appraised_value or 0)
    end
    if data.skin_item then
        total_items = total_items + (data.skin_item.sold_value or data.skin_item.appraised_value or 0)
    end
    for _, bd in ipairs(data.boxes) do
        for _, item in ipairs(bd.contents) do
            total_items = total_items + (item.sold_value or item.appraised_value or 0)
        end
    end

    local out = {
        "",
        "Creature Lookup: " .. creature_name,
        "GameObj ID: " .. data.source_id,
        string.rep("-", 70),
    }

    if data.search_event then
        local e = data.search_event
        out[#out + 1] = ""
        out[#out + 1] = "SEARCH EVENT (ID: " .. tostring(e.id) .. ")"
        out[#out + 1] = "  Time:     " .. format_time(e.created_at)
        out[#out + 1] = "  Room:     " .. tostring(e.room_id or "N/A")
        out[#out + 1] = "  Silvers:  " .. format_silver(e.silvers_found)
        if #data.search_items > 0 then
            out[#out + 1] = ""
            out[#out + 1] = "  Items Found:"
            for _, item in ipairs(data.search_items) do
                local val_str = item.sold_value and ("+" .. format_silver(item.sold_value)) or
                                item.appraised_value and ("~" .. format_silver(item.appraised_value)) or "--"
                out[#out + 1] = "    " .. ljust(item.item_name or "unknown", 38) .. " " .. rjust(val_str, 12)
            end
        end
    end

    if data.skin_event then
        out[#out + 1] = ""
        out[#out + 1] = "SKIN EVENT (ID: " .. tostring(data.skin_event.id) .. ")"
        out[#out + 1] = "  Time:     " .. format_time(data.skin_event.created_at)
        if data.skin_item then
            local val_str = data.skin_item.sold_value and ("+" .. format_silver(data.skin_item.sold_value)) or
                            data.skin_item.appraised_value and ("~" .. format_silver(data.skin_item.appraised_value)) or "--"
            out[#out + 1] = "  " .. ljust(data.skin_item.item_name or "unknown", 38) .. " " .. rjust(val_str, 12)
        end
    end

    if #data.boxes > 0 then
        out[#out + 1] = ""
        out[#out + 1] = "BOXES (" .. #data.boxes .. "):"
        for i, bd in ipairs(data.boxes) do
            local box = bd.box
            local status = box.lost_at and "Lost" or box.opened_at and "Opened" or "Unopened"
            out[#out + 1] = ""
            out[#out + 1] = "  Box " .. i .. ": " .. (box.item_name or "unknown") .. " [ID: " .. tostring(box.id) .. "]"
            out[#out + 1] = "    Pool Fee:    " .. (box.pool_fee and format_silver(box.pool_fee) or "N/A")
            out[#out + 1] = "    Pool Tip:    " .. (box.pool_tip and format_silver(box.pool_tip) or "N/A")
            out[#out + 1] = "    Status:      " .. status
            if box.opened_at then
                out[#out + 1] = "    Opened At:   " .. format_time(box.opened_at)
                out[#out + 1] = "    Box Silvers: " .. format_silver(bd.silvers)
                if #bd.contents > 0 then
                    out[#out + 1] = "    Contents:"
                    for _, item in ipairs(bd.contents) do
                        local val_str = item.sold_value and ("+" .. format_silver(item.sold_value)) or
                                        item.appraised_value and ("~" .. format_silver(item.appraised_value)) or "--"
                        out[#out + 1] = "      " .. ljust(item.item_name or "unknown", 36) .. " " .. rjust(val_str, 12)
                    end
                else
                    out[#out + 1] = "    Contents:    (none recorded)"
                end
            end
        end
    end

    out[#out + 1] = ""
    out[#out + 1] = string.rep("-", 70)
    out[#out + 1] = "TOTALS:"
    out[#out + 1] = "  Silvers (search + boxes): " .. format_silver(total_silvers)
    out[#out + 1] = "  Items Value:              " .. format_silver(total_items)
    out[#out + 1] = "  Pool Fees:                -" .. format_silver(total_fees)
    out[#out + 1] = "  Pool Tips:                -" .. format_silver(total_tips)
    out[#out + 1] = "  Net:                      " .. format_silver(total_silvers + total_items - total_fees - total_tips)
    out[#out + 1] = ""
    mono_output(out)
end

function CLI.show_help()
    local out = {
        "",
        "LootTracker v" .. VERSION .. " - Self-parsing loot tracker",
        string.rep("-", 60),
        "Usage:",
        "  ;loottracker                    Start tracking (or show summary if running)",
        "  ;lt                             Alias for ;loottracker",
        "",
        "  ;loottracker summary            Last 24 hours (default)",
        "  ;loottracker summary today      Since midnight",
        "  ;loottracker summary month      Current month",
        "  ;loottracker summary <hours>    Last N hours",
        "",
        "Loot Cap Report (resets 1st of month):",
        "  ;loottracker cap                Current month loot cap",
        "  ;loottracker cap last           Previous month",
        "  ;loottracker cap 2025-12        Specific month",
        "",
        "  ;loottracker recent [n]         Recent items (default 20)",
        "  ;loottracker recent [n] <type>  Filter by type",
        "    Types: gems, boxes, skins, klocks, magic, wands, weapons, armor,",
        "           jewelry, clothing, scrolls, valuables, collectibles,",
        "           lockpicks, scarabs, reagents, food, jars, boons, ingots, junk, other",
        "",
        "  ;loottracker boxes [n]          Recent boxes with silvers",
        "  ;loottracker box                List recent boxes with drill-down IDs",
        "  ;loottracker box <id>           Full detail for one box (fee/tip/contents/net)",
        "  ;loottracker transactions       Transaction breakdown",
        "  ;loottracker creatures [n]      Top creatures by value (last 24h)",
        "  ;loottracker creature <id>      Full detail for one creature (GameObj ID)",
        "  ;loottracker wands              Wand duplication stats",
        "",
        "Cross-Character Proxy (for loresinging/appraising on behalf of others):",
        "  ;loottracker proxy              Show current proxy settings",
        "  ;loottracker proxy <name>       Set all proxies to <name>",
        "  ;loottracker proxy clear        Clear all proxies",
        "",
        "  ;loottracker status             Show tracker status",
        "  ;loottracker debug              Toggle debug mode",
        "  ;loottracker reset              Reset current month data",
        "  ;loottracker help               Show this help",
        "",
    }
    mono_output(out)
end

--------------------------------------------------------------------------------
-- Command Dispatcher
--------------------------------------------------------------------------------

local function process_command(args_str)
    local parts = split(args_str or "")
    local command = (parts[1] or ""):lower()
    local rest = {}
    for i = 2, #parts do rest[#rest + 1] = parts[i] end

    if command == "" or command == "summary" then
        local period = (rest[1] or ""):lower()
        local summary, label
        if period == "today" or period == "midnight" then
            summary = Reports.summary_today()
            label = "Since Midnight"
        elseif period == "month" or period == "monthly" then
            summary = Reports.summary_month()
            label = "Current Month"
        elseif tonumber(period) then
            local hours = tonumber(period)
            summary = Reports.summary_last_hours(hours)
            label = "Last " .. hours .. " Hours"
        else
            summary = Reports.summary_last_hours(24)
            label = "Last 24 Hours"
        end
        CLI.show_summary(summary, label)

    elseif command == "cap" or command == "lootcap" then
        local period = (rest[1] or ""):lower()
        local year, month
        if period == "last" or period == "previous" or period == "prev" then
            local t = os.date("*t")
            if t.month == 1 then year = t.year - 1; month = 12
            else year = t.year; month = t.month - 1 end
        else
            local y, m = period:match("^(%d%d%d%d)%-(%d%d?)$")
            if y and m then year = tonumber(y); month = tonumber(m) end
        end
        local data = Reports.loot_cap_summary(year, month)
        CLI.show_loot_cap(data)

    elseif command == "recent" then
        local limit = 20
        local type_filter = nil
        for _, arg in ipairs(rest) do
            if tonumber(arg) then
                limit = tonumber(arg)
            else
                type_filter = RECENT_TYPE_ALIASES[arg:lower()]
            end
        end
        local items = Reports.recent_items(limit, type_filter)
        CLI.show_recent_items(items, type_filter)

    elseif command == "boxes" then
        local limit = tonumber(rest[1]) or 20
        local boxes = Reports.recent_boxes(limit)
        CLI.show_recent_boxes(boxes)

    elseif command == "box" then
        if #rest > 0 and tonumber(rest[1]) then
            local data = Reports.box_lookup(tonumber(rest[1]))
            if data then
                CLI.show_box_detail(data)
            else
                respond("No box found with record ID: " .. rest[1])
            end
        else
            local boxes = Reports.box_list(10)
            CLI.show_box_list(boxes)
        end

    elseif command == "wands" then
        local wands_data = Reports.wands()
        CLI.show_wands(wands_data)

    elseif command == "creature" then
        if #rest == 0 then
            respond("Usage: ;lt creature <id>  - Look up creature by GameObj ID")
        else
            local data = Reports.creature_lookup(rest[1])
            CLI.show_creature_lookup(data)
        end

    elseif command == "transactions" or command == "tx" then
        local data = Reports.transactions_by_category()
        CLI.show_transactions(data)

    elseif command == "creatures" then
        local limit = tonumber(rest[1]) or 10
        local stats = Reports.creature_stats(limit)
        CLI.show_creatures(stats)

    elseif command == "status" then
        CLI.show_status()

    elseif command == "proxy" then
        if #rest == 0 then
            CLI.show_proxy()
        else
            local sub = rest[1]:lower()
            if sub == "clear" then
                LT.loresong_proxy = nil
                LT.appraise_proxy = nil
                LT.dupe_proxy = nil
                respond("  All proxies cleared.")
            elseif sub == "loresong" and rest[2] then
                LT.loresong_proxy = rest[2]
                respond("  Loresong proxy set to: " .. rest[2])
            elseif sub == "appraise" and rest[2] then
                LT.appraise_proxy = rest[2]
                respond("  Appraise proxy set to: " .. rest[2])
            elseif sub == "dupe" and rest[2] then
                LT.dupe_proxy = rest[2]
                respond("  Dupe proxy set to: " .. rest[2])
            else
                -- Shorthand: ;lt proxy Name
                LT.loresong_proxy = rest[1]
                LT.appraise_proxy = rest[1]
                LT.dupe_proxy = rest[1]
                respond("  All proxies set to: " .. rest[1])
            end
        end

    elseif command == "lost" then
        if #rest == 0 then
            respond("")
            respond("Mark a box as lost (died, decayed, etc.)")
            respond("Usage:")
            respond("  ;lt lost <name>    - Mark most recent unopened box matching name")
            respond("  ;lt lost #<id>     - Mark box by record ID")
            return
        end
        local identifier = table.concat(rest, " ")
        identifier = identifier:gsub("^#(%d+)$", "%1")
        local item = mark_box_lost(identifier)
        if item then
            respond("Marked as lost: " .. item.item_name .. " (#" .. item.id .. ")")
        else
            respond("No matching unopened box found for '" .. identifier .. "'")
        end

    elseif command == "reset" then
        LT.data = empty_data()
        save_data()
        log("Data reset for current month")

    elseif command == "debug" then
        LT.debug_mode = not LT.debug_mode
        respond("LootTracker debug: " .. (LT.debug_mode and "ON" or "OFF"))

    elseif command == "help" or command == "?" then
        CLI.show_help()

    else
        respond("Unknown command: " .. command .. ". Type ';loottracker help' for usage.")
    end
end

--------------------------------------------------------------------------------
-- Hook Management and Main Loop
--------------------------------------------------------------------------------

local hook_id = "LootTracker::downstream"
local upstream_hook_id = "LootTracker::upstream"

local function install_hooks()
    -- Downstream hook: buffer lines, dispatch on prompt
    DownstreamHook.add(hook_id, function(server_string)
        LT.buffer[#LT.buffer + 1] = server_string

        -- Slice on prompt (natural game action boundary)
        if server_string:find("<prompt time=", 1, true) then
            local chunk = LT.buffer
            LT.buffer = {}

            -- Quick dispatch (try to process)
            local ok, err = pcall(dispatch_chunk, chunk)
            if not ok then
                debug_log("Parser error: " .. tostring(err))
            end
        end

        -- Overflow protection
        if #LT.buffer > MAX_BUFFER_SIZE then
            local new_buf = {}
            for i = #LT.buffer - MAX_BUFFER_SIZE + 1, #LT.buffer do
                new_buf[#new_buf + 1] = LT.buffer[i]
            end
            LT.buffer = new_buf
        end

        return server_string  -- Pass through unchanged
    end)

    -- Upstream hook: intercept ;loottracker and ;lt commands
    UpstreamHook.add(upstream_hook_id, function(client_string)
        local cmd = client_string:match("^<?c?>?;l[oO][oO][tT][tT][rR][aA][cC][kK][eE][rR]%s*(.*)")
        if not cmd then
            cmd = client_string:match("^<?c?>?;[lL][tT]%s*(.*)")
        end
        if cmd then
            local ok, err = pcall(process_command, cmd)
            if not ok then
                log("Command error: " .. tostring(err))
            end
            return nil  -- Consume the command
        end
        return client_string  -- Pass through
    end)

    log("Hooks installed")
end

local function remove_hooks()
    DownstreamHook.remove(hook_id)
    UpstreamHook.remove(upstream_hook_id)
    log("Hooks removed")
end

--------------------------------------------------------------------------------
-- Entry Point
--------------------------------------------------------------------------------

no_kill_all()

-- Initialize data
init_data()

-- Register cleanup
before_dying(function()
    LT.enabled = false
    remove_hooks()
    save_data()
    log("Stopped")
end)

-- Parse command-line arguments
local first_arg = (Script.vars[1] or ""):lower()

if first_arg == "help" or first_arg == "-h" or first_arg == "--help" then
    CLI.show_help()
elseif first_arg == "summary" or first_arg == "cap" or first_arg == "lootcap" or
       first_arg == "recent" or first_arg == "boxes" or first_arg == "box" or
       first_arg == "transactions" or first_arg == "tx" or
       first_arg == "creatures" or first_arg == "creature" or
       first_arg == "wands" or first_arg == "status" or
       first_arg == "lost" or first_arg == "proxy" or first_arg == "reset" then
    -- One-shot report commands
    process_command(Script.vars[0] and Script.vars[0]:match("^%S+%s+(.*)$") or first_arg)
else
    -- Default: start tracking in background
    LT.enabled = true
    LT.debug_mode = (first_arg == "debug")

    install_hooks()
    log("Started (debug=" .. tostring(LT.debug_mode) .. ")")

    -- Stay alive - the hooks do all the work
    while true do
        pause(1)
    end
end
