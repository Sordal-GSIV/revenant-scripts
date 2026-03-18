--- @revenant-script
--- name: sloot
--- version: 3.5.2
--- author: SpiffyJr
--- contributors: Athias, Demandred, Tysong, Deysh, Ondreian, Lieo, Lobe, Etheirys
--- game: gs
--- description: Smart loot management — skin, search, loot, sort, sell
--- tags: loot,hunting,sell
---
--- Ported from Lich5 Ruby SpiffyLoot (sloot) v3.5.2
--- Original author: SpiffyJr <spiffyjr@gmail.com>
---
--- Usage:
---   ;sloot                  - Run skin/search/loot in current room
---   ;sloot sell             - Run automated selling routine
---   ;sloot deposit          - Deposit coins per settings
---   ;sloot setup            - Open GUI configuration
---   ;sloot left|right       - Loot from sack in hand
---   ;sloot help             - Show help

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function load_json(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

local function save_json(key, val)
    CharSettings[key] = Json.encode(val)
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    enable_loot_gem        = true,
    enable_loot_skin       = true,
    enable_loot_box        = true,
    enable_loot_magic      = true,
    enable_loot_scroll     = true,
    enable_loot_wand       = true,
    enable_loot_jewelry    = true,
    enable_loot_herb       = true,
    enable_loot_reagent    = true,
    enable_loot_lockpick   = true,
    enable_loot_uncommon   = true,
    enable_loot_valuable   = true,
    enable_loot_collectible = true,
    enable_loot_clothing   = false,
    enable_loot_ammo       = false,
    enable_skinning        = false,
    enable_skin_alternate  = false,
    enable_skin_kneel      = false,
    enable_skin_offensive  = false,
    enable_skin_604        = false,
    enable_skin_sigil      = false,
    enable_skin_safe_mode  = true,
    enable_skin_stance_first = false,
    enable_search_all      = true,
    enable_stow_left       = false,
    enable_safe_hiding     = false,
    enable_self_drops      = false,
    enable_disking         = false,
    enable_gather          = false,
    enable_sell_locksmith  = false,
    enable_sell_stockpile  = false,
    enable_locker_boxes    = false,
    enable_sell_chronomage = false,
    enable_sell_type_gem   = true,
    enable_sell_type_skin  = true,
    enable_sell_type_magic = false,
    enable_sell_type_scroll = false,
    enable_sell_type_wand  = false,
    enable_sell_type_jewelry = false,
    enable_sell_type_empty_box = false,
    enable_sell_type_scarab = false,
    enable_stance_on_start = false,
    overflowsack           = "",
    ammo_name              = "",
    skin_stand_verb        = "",
    skin_exclude           = {},
    safe_ignore            = "",
    loot_exclude           = "",
    sell_exclude           = "",
    critter_exclude        = "",
}

local settings = load_json("sloot_settings", DEFAULT_SETTINGS)
for k, v in pairs(DEFAULT_SETTINGS) do
    if settings[k] == nil then settings[k] = v end
end

--------------------------------------------------------------------------------
-- Sack tracking
--------------------------------------------------------------------------------

local sacks = {}
local SACK_TYPES = {
    "clothing", "ammo", "box", "gem", "herb", "jewelry", "lockpick",
    "magic", "reagent", "scroll", "skin", "uncommon", "wand",
    "skinweapon", "valuable", "collectible",
}

--- Locate sacks from UserVars
local function find_sacks()
    for _, stype in ipairs(SACK_TYPES) do
        local sack_name = UserVars[stype .. "sack"]
        if sack_name and sack_name ~= "" then
            local found = GameObj.find_inv(sack_name)
            if found then
                sacks[stype] = found
            elseif settings["enable_loot_" .. stype] then
                echo("** failed to find " .. stype .. " sack")
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Item manipulation
--------------------------------------------------------------------------------

local GET_RX = Regex.new("^You (?:remove|grab|get|pick)|^You already have|^Get what")
local PUT_RX = Regex.new("^You (?:put|tuck|place|slip|drop|absent|attempt)|^The .+ won't fit|already")

local function get_item(item, container)
    if not item then return false end

    local cmd
    if container then
        cmd = string.format("get #%s in #%s", item.id, container.id)
    else
        cmd = string.format("get #%s", item.id)
    end

    local res = dothistimeout(cmd, 5, GET_RX)
    if not res then return false end

    return not Regex.test(res, "Get what")
end

local function put_item(item, container_id)
    if not item or not container_id then return false end

    local cmd = string.format("put #%s in #%s", item.id, tostring(container_id))
    local res = dothistimeout(cmd, 5, PUT_RX)
    if not res then return false end

    return Regex.test(res, "^You (?:put|tuck|place|slip)")
end

local function free_hand()
    if not checkleft() or not checkright() then return end

    if settings.enable_stow_left then
        empty_left_hand()
    else
        empty_right_hand()
    end
end

--------------------------------------------------------------------------------
-- Stance management
--------------------------------------------------------------------------------

local prev_stance = "defensive"
local STANCE_RX = Regex.new("^You are now in an? (\\w+) stance")

local function change_stance(target)
    if target == prev_stance then return end
    local res = dothistimeout("stance " .. target, 5, STANCE_RX)
    if res then
        prev_stance = target
    end
end

--------------------------------------------------------------------------------
-- Loot routines
--------------------------------------------------------------------------------

local function grab_loot(loot_obj, sack)
    if not loot_obj then return end

    -- Try to get the item
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if (not rh or rh.id ~= loot_obj.id) and (not lh or lh.id ~= loot_obj.id) then
        local res = dothistimeout(string.format("get #%s", loot_obj.id), 5, GET_RX)
        if not res then return end
    end

    -- Determine which sack to use based on type
    if not sack then
        local item_types = loot_obj.type or ""
        for stype in string.gmatch(item_types, "[^,]+") do
            stype = stype:match("^%s*(.-)%s*$")
            if sacks[stype] then
                sack = sacks[stype]
                break
            end
        end
    end

    if sack then
        local result = put_item(loot_obj, sack.id)
        if not result then
            -- Try overflow sacks
            if settings.overflowsack and settings.overflowsack ~= "" then
                for overflow in string.gmatch(settings.overflowsack, "[^,]+") do
                    overflow = overflow:match("^%s*(.-)%s*$")
                    local osack = GameObj.find_inv(overflow)
                    if osack and put_item(loot_obj, osack.id) then
                        return
                    end
                end
            end
            echo("failed to stow " .. (loot_obj.name or "item"))
            fput(string.format("drop #%s", loot_obj.id))
        end
    else
        echo("no sack found for " .. (loot_obj.name or "item"))
    end
end

local function loot_it(array, exclude_ids)
    if not array then return end
    exclude_ids = exclude_ids or {}

    -- Apply loot exclusion filter
    local loot_exclude = settings.loot_exclude or ""

    for _, loot_obj in ipairs(array) do
        -- Skip severed limbs
        if Regex.test(loot_obj.name or "", "severed.*(?:arm|leg)") then
            goto continue
        end

        -- Skip excluded IDs
        if exclude_ids[loot_obj.id] then
            exclude_ids[loot_obj.id] = nil
            goto continue
        end

        -- Skip excluded names
        if loot_exclude ~= "" and Regex.test(loot_obj.name or "", loot_exclude) then
            goto continue
        end

        -- Check if type matches something we want
        local item_types = loot_obj.type or ""
        local want = false
        for stype in string.gmatch(item_types, "[^,]+") do
            stype = stype:match("^%s*(.-)%s*$")
            if settings["enable_loot_" .. stype] then
                want = true
                break
            end
        end

        if want then
            free_hand()
            grab_loot(loot_obj, nil)
        elseif loot_obj.name == "some silver coins" then
            dothistimeout(string.format("get #%s", loot_obj.id), 5,
                Regex.new("^You gather the remaining"))
        end

        ::continue::
    end
end

--------------------------------------------------------------------------------
-- Skinning
--------------------------------------------------------------------------------

local skin_prepared = false
local skin_empty_hands = false
local skinweapon = nil
local skinweaponblunt = nil
local skinweaponcurrent = nil

local function safe_to_enhance()
    if not settings.enable_skin_safe_mode then return true end
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if npc.status ~= "dead" then return false end
    end
    return true
end

local function prepare_skinner(critter)
    if not critter then return end
    local skip_list = settings.skin_exclude or {}
    for _, name in ipairs(skip_list) do
        if critter.name == name then return end
    end
    if skin_prepared then return end
    if not settings.enable_skinning then return end

    -- Sigil of Resolve (9704)
    if Spell.known(9704) and Spell.affordable(9704) and not Spell.active(9704)
       and settings.enable_skin_sigil then
        Spell.cast(9704)
    end

    -- Skinning spell (604)
    if Spell.known(604) and Spell.affordable(604) and settings.enable_skin_604 then
        while not Spell.active(604) do
            Spell.cast(604)
        end
    end

    if settings.enable_skin_alternate then
        if Regex.test(critter.name, "krag dweller|greater krynch|massive boulder") then
            empty_hands()
            skin_empty_hands = true
        else
            free_hand()
        end
    else
        if Regex.test(critter.name, "krag dweller|greater krynch|massive boulder") then
            free_hand()
        end
    end

    if safe_to_enhance() then
        if settings.enable_skin_kneel and not checkkneeling() then
            dothistimeout("kneel", 5, Regex.new("^You kneel down|^You are already kneeling"))
        end
        if settings.enable_skin_offensive then
            change_stance("offensive")
        end
    end

    skin_prepared = true
end

local function finish_skinner()
    if not skin_prepared then return end
    if not settings.enable_skinning then return end

    local function stand_up()
        local verb = settings.skin_stand_verb or ""
        if verb == "" then
            while not standing() do
                dothistimeout("stand", 5, Regex.new("^You stand back up"))
            end
        else
            while not standing() do
                fput(verb)
            end
        end
    end

    if settings.enable_skin_stance_first then
        change_stance(prev_stance)
        stand_up()
    else
        stand_up()
        change_stance(prev_stance)
    end

    if skin_empty_hands then
        fill_hands()
        skin_empty_hands = false
    end

    skin_prepared = false
end

local SKIN_RX = Regex.new("skinned|botched|already been|cannot skin|must be a member|can only skin|You are unable to break through|You break through the crust|You crack open a portion")

local function skin_critter(critter)
    if not critter then return end
    local skip_list = settings.skin_exclude or {}
    for _, name in ipairs(skip_list) do
        if critter.name == name then return end
    end

    local cmd = string.format("skin #%s", critter.id)
    local res = dothistimeout(cmd, 5, SKIN_RX)
    if res and Regex.test(res, "^You cannot skin") then
        skip_list[#skip_list + 1] = critter.name
    end
end

--------------------------------------------------------------------------------
-- Dead creature detection
--------------------------------------------------------------------------------

local function find_dead()
    local npcs = GameObj.npcs()
    local dead = {}
    local critter_exclude = settings.critter_exclude or ""

    for _, npc in ipairs(npcs) do
        if npc.status == "dead" then
            if critter_exclude == "" or not Regex.test(npc.name, critter_exclude) then
                dead[#dead + 1] = npc
            end
        end
    end
    return dead
end

--------------------------------------------------------------------------------
-- Deposit / Sell (simplified)
--------------------------------------------------------------------------------

local function deposit_coins()
    local silver = checksilvers()
    if silver < 100 then return end
    go2("bank")
    fput("deposit all")
end

local function msg(text)
    echo("[SLoot] " .. text)
end

--------------------------------------------------------------------------------
-- Sell routine
--------------------------------------------------------------------------------

local function sell_routine()
    local cur_room = Room.id
    local silver_breakdown = {}

    -- Sell at various shops based on settings
    local found_sacks = {}
    local selling = {}
    local types = {}

    for k, v in pairs(settings) do
        local stype = string.match(k, "^enable_sell_type_(.+)$")
        if stype and v then
            types[#types + 1] = stype
            local sname = UserVars[stype .. "sack"]
            if sname then
                local found = GameObj.find_inv(sname)
                if found then
                    found_sacks[found.id] = found
                end
            end
        end
    end

    -- Scan sacks for sellable items
    for _, sack in pairs(found_sacks) do
        local contents = sack.contents or {}
        for _, item in ipairs(contents) do
            if item.sellable and item.sellable ~= "" then
                local item_types = item.type or ""
                for it in string.gmatch(item_types, "[^,]+") do
                    it = it:match("^%s*(.-)%s*$")
                    for _, st in ipairs(types) do
                        if it == st then
                            if not selling[item.sellable] then
                                selling[item.sellable] = {}
                            end
                            selling[item.sellable][#selling[item.sellable] + 1] = item
                            break
                        end
                    end
                end
            end
        end
    end

    -- Check if anything to sell
    local has_items = false
    for _ in pairs(selling) do has_items = true; break end
    if not has_items then
        msg("nothing to sell")
    else
        empty_hands()
        for location, items in pairs(selling) do
            local loc_parts = {}
            for part in string.gmatch(location, "[^,]+") do
                loc_parts[#loc_parts + 1] = part
            end
            local first_loc = loc_parts[1]

            local start_silver = checksilvers()
            go2(first_loc)

            for _, item in ipairs(items) do
                if get_item(item, nil) then
                    dothistimeout(string.format("sell #%s", item.id), 5,
                        Regex.new("ask|offer"))
                    -- If still in hand, stow it
                    if checkleft() == item.noun or checkright() == item.noun then
                        fput(string.format("stow #%s", item.id))
                    end
                end
            end

            silver_breakdown[first_loc] = checksilvers() - start_silver
        end
    end

    deposit_coins()
    if cur_room then go2(tostring(cur_room)) end
    fill_hands()

    -- Report
    local total = 0
    for loc, silver in pairs(silver_breakdown) do
        msg(string.format("%s: %d", loc, silver))
        total = total + silver
    end
    if total > 0 then
        msg(string.format("total: %d silver", total))
    end
end

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function setup_gui()
    local win = Gui.window("SLoot Setup", 400, 600)
    local box = Gui.vbox(win)

    Gui.label(box, "=== SLoot Settings ===")
    Gui.label(box, "")

    -- Loot type toggles
    Gui.label(box, "Loot Types:")
    local loot_types = { "gem", "skin", "box", "magic", "scroll", "wand",
        "jewelry", "herb", "reagent", "lockpick", "uncommon", "valuable", "collectible", "clothing", "ammo" }

    for _, lt in ipairs(loot_types) do
        local key = "enable_loot_" .. lt
        Gui.checkbox(box, lt:sub(1,1):upper() .. lt:sub(2), settings[key] or false, function(val)
            settings[key] = val
            save_json("sloot_settings", settings)
        end)
    end

    Gui.label(box, "")
    Gui.label(box, "Skinning:")
    Gui.checkbox(box, "Enable Skinning", settings.enable_skinning or false, function(val)
        settings.enable_skinning = val
        save_json("sloot_settings", settings)
    end)
    Gui.checkbox(box, "Kneel to Skin", settings.enable_skin_kneel or false, function(val)
        settings.enable_skin_kneel = val
        save_json("sloot_settings", settings)
    end)

    Gui.label(box, "")
    Gui.label(box, "Selling:")
    local sell_types = { "gem", "skin", "magic", "scroll", "wand", "jewelry" }
    for _, st in ipairs(sell_types) do
        local key = "enable_sell_type_" .. st
        Gui.checkbox(box, "Sell " .. st, settings[key] or false, function(val)
            settings[key] = val
            save_json("sloot_settings", settings)
        end)
    end

    Gui.show(win)
    respond("[SLoot] Setup window opened.")
end

--------------------------------------------------------------------------------
-- Command handlers
--------------------------------------------------------------------------------

local function show_help()
    msg("SLoot - Smart Loot Management")
    msg("  Author: SpiffyJr")
    msg("")
    msg("  ;sloot           - skin, search, loot current room")
    msg("  ;sloot setup     - open GUI settings")
    msg("  ;sloot sell      - run sell routine")
    msg("  ;sloot deposit   - deposit coins")
    msg("  ;sloot left      - loot from left hand container")
    msg("  ;sloot right     - loot from right hand container")
    msg("  ;sloot help      - this message")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local cmd = (Script.vars[1] or ""):lower()

if cmd == "setup" or cmd == "config" then
    setup_gui()
    return
elseif cmd == "sell" then
    find_sacks()
    sell_routine()
    return
elseif cmd == "deposit" then
    deposit_coins()
    return
elseif Regex.test(cmd, "^help|^\\?$") then
    show_help()
    return
elseif cmd == "left" then
    find_sacks()
    local hand = GameObj.left_hand
    if hand and hand.contents then
        loot_it(hand.contents, {})
    end
    return
elseif cmd == "right" then
    find_sacks()
    local hand = GameObj.right_hand
    if hand and hand.contents then
        loot_it(hand.contents, {})
    end
    return
elseif cmd ~= "" then
    show_help()
    return
end

-- Default: skin, search, loot
find_sacks()

-- Safe hiding check
if settings.enable_safe_hiding and hiding() then
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if npc.status ~= "dead" and not Regex.test(npc.type or "", "escort")
           and (settings.safe_ignore == "" or not Regex.test(npc.name, settings.safe_ignore)) then
            return  -- unsafe, exit
        end
    end
end

-- Track existing loot IDs for self-drops mode
local previous_loot_ids = {}
if settings.enable_self_drops then
    for _, l in ipairs(GameObj.loot()) do
        previous_loot_ids[l.id] = true
    end
end

-- Skin dead creatures
local critters = find_dead()
if settings.enable_skinning then
    for _, critter in ipairs(critters) do
        if not Regex.test(critter.name, "Grimswarm") and not Regex.test(critter.type or "", "bandit") then
            prepare_skinner(critter)
            skin_critter(critter)
        end
    end
    finish_skinner()
end

-- Search dead creatures
local SEARCH_RX = Regex.new("^You search|^What were you referring to|You plunge your hand|withdraw a|causing assorted foliage|You quickly grab")

for _, critter in ipairs(critters) do
    local res = dothistimeout(string.format("search #%s", critter.id), 5, SEARCH_RX)

    if res and Regex.test(res, "withdraw a (?:cold blue gem|fiery red gem)") then
        if checkright() == "gem" then
            loot_it({ GameObj.right_hand() }, {})
        elseif checkleft() then
            loot_it({ GameObj.left_hand() }, {})
        end
    end

    -- Bramble patch loot
    if checkright() and Regex.test(checkright(), "berry|thorn") then
        fput("stow right")
    elseif checkleft() and Regex.test(checkleft(), "berry|thorn") then
        fput("stow left")
    end

    if not settings.enable_search_all then break end
end

-- Stance on start
if settings.enable_stance_on_start then
    change_stance("defensive")
end

-- Loot ground items
local target = GameObj.loot()
loot_it(target, previous_loot_ids)

-- Restore hand contents
if settings.enable_stow_left then
    fill_left_hand()
else
    fill_right_hand()
end
