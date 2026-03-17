--- @revenant-script
--- name: boon
--- version: 3.5.0
--- author: Steworaeus
--- game: gs
--- tags: loot, skinning, selling, locksmith
--- description: Versatile looting, skinning, selling, and locksmith automation (derived from SpiffyLoot)
---
--- Original Lich5 authors: Steworaeus, SpiffyJr
--- Ported to Revenant Lua from boon.lic v3.5
---
--- Usage:
---   ;boon              — run skin/search/loot cycle on current room
---   ;boon sell         — run automated sell routine
---   ;boon deposit      — deposit coins at bank
---   ;boon setup        — configure settings (terminal UI)
---   ;boon left/right   — loot from sack in your hand
---   ;boon help         — show help

local VERSION = "3.5.0"

--------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------

local PUT_PATTERNS = {
    "^You put", "^You tuck", "^You attempt to shield", "^You place",
    "^You slip", "^You wipe off", "^You absent%-mindedly drop",
    "^You carefully add", "^You find an incomplete bundle",
    "^You untie your drawstring", "^The .+ is already a bundle",
    "^Your bundle would be too large", "^The .+ is too large to be bundled",
    "^As you place",
}

local function is_put_result(line)
    for _, pat in ipairs(PUT_PATTERNS) do
        if Regex.test(line, pat) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local settings = CharSettings.get("boon") or {}

settings.skin_exclude           = settings.skin_exclude or {}
settings.loot_exclude           = settings.loot_exclude or "drake|feras|black ora"
settings.critter_exclude        = settings.critter_exclude or ""
settings.sell_exclude           = settings.sell_exclude or ""

-- Loot type enables
settings.enable_loot_gem        = (settings.enable_loot_gem == nil) and true or settings.enable_loot_gem
settings.enable_loot_box        = (settings.enable_loot_box == nil) and true or settings.enable_loot_box
settings.enable_loot_skin       = (settings.enable_loot_skin == nil) and true or settings.enable_loot_skin
settings.enable_loot_herb       = (settings.enable_loot_herb == nil) and true or settings.enable_loot_herb
settings.enable_loot_jewelry    = (settings.enable_loot_jewelry == nil) and true or settings.enable_loot_jewelry
settings.enable_loot_scroll     = (settings.enable_loot_scroll == nil) and true or settings.enable_loot_scroll
settings.enable_loot_wand       = (settings.enable_loot_wand == nil) and true or settings.enable_loot_wand
settings.enable_loot_magic      = (settings.enable_loot_magic == nil) and true or settings.enable_loot_magic
settings.enable_loot_reagent    = settings.enable_loot_reagent or false
settings.enable_loot_valuable   = settings.enable_loot_valuable or false

-- Skinning
settings.enable_skinning        = settings.enable_skinning or false
settings.enable_skin_kneel      = settings.enable_skin_kneel or false
settings.enable_skin_offensive  = settings.enable_skin_offensive or false
settings.enable_skin_alternate  = settings.enable_skin_alternate or false
settings.enable_skin_604        = settings.enable_skin_604 or false
settings.enable_skin_sigil      = settings.enable_skin_sigil or false
settings.enable_skin_safe_mode  = settings.enable_skin_safe_mode or true

-- Selling
settings.enable_sell_locksmith  = settings.enable_sell_locksmith or false
settings.enable_sell_type_gem   = (settings.enable_sell_type_gem == nil) and true or settings.enable_sell_type_gem
settings.enable_sell_type_skin  = settings.enable_sell_type_skin or false

-- Disk
settings.enable_disking         = settings.enable_disking or false
settings.enable_phasing         = settings.enable_phasing or false

-- Stow hand preference
settings.enable_stow_left       = settings.enable_stow_left or false

-- Self drops only
settings.enable_self_drops      = settings.enable_self_drops or false

-- Ammo gathering
settings.enable_gather          = settings.enable_gather or false
settings.ammo_name              = settings.ammo_name or ""

-- Stockpile
settings.enable_sell_stockpile  = settings.enable_sell_stockpile or false
settings.orb_value              = settings.orb_value or 5000

-- Overflow sack
settings.overflowsack           = settings.overflowsack or ""

-- Search all dead
settings.enable_search_all      = (settings.enable_search_all == nil) and true or settings.enable_search_all

-- Safe hiding
settings.enable_safe_hiding     = settings.enable_safe_hiding or false

local function save_settings()
    CharSettings.set("boon", settings)
end

save_settings()

--------------------------------------------------------------------------------
-- Container resolution
--------------------------------------------------------------------------------

local sacks = {}

local function resolve_sacks()
    local types = { "gem", "box", "skin", "herb", "jewelry", "scroll", "wand", "magic", "reagent", "valuable", "weapon", "clothing", "ammo", "lockpick", "uncommon" }
    local inv = GameObj.inv()
    for _, t in ipairs(types) do
        local sack_name = UserVars and UserVars[t .. "sack"]
        if sack_name and sack_name ~= "" then
            for _, obj in ipairs(inv) do
                if obj.name:lower():find(sack_name:lower(), 1, true) or
                   (obj.noun and obj.noun:lower():find(sack_name:lower(), 1, true)) then
                    sacks[t] = obj
                    break
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Item handling
--------------------------------------------------------------------------------

local function get_item(item, from)
    if from then
        fput("get #" .. (type(item) == "table" and item.id or item) .. " from #" .. (type(from) == "table" and from.id or from))
    else
        fput("get #" .. (type(item) == "table" and item.id or item))
    end
    local result = matchtimeout(5, "^You .+get", "^You remove", "^You pick up", "^Get what", "could not find")
    return result and not (result:find("Get what") or result:find("could not"))
end

local function put_item(item, container)
    local item_id = type(item) == "table" and item.id or item
    local container_ref = type(container) == "table" and ("#" .. container.id) or ("my " .. container)
    fput("put #" .. item_id .. " in " .. container_ref)
    local result = matchtimeout(5, table.unpack(PUT_PATTERNS))
    return result ~= nil
end

local function go2(dest)
    if not dest or dest == "" then return end
    Script.run("go2", tostring(dest))
end

local function change_stance(stance)
    fput("stance " .. stance)
    waitrt()
end

local function free_hand()
    local rh = GameObj.right_hand and GameObj.right_hand()
    local lh = GameObj.left_hand and GameObj.left_hand()
    if rh and lh then
        if settings.enable_stow_left then
            fput("stow left")
        else
            fput("stow right")
        end
    end
end

--------------------------------------------------------------------------------
-- Skinning
--------------------------------------------------------------------------------

local function find_dead()
    local npcs = GameObj.npcs()
    local dead = {}
    for _, npc in ipairs(npcs) do
        if npc.status == "dead" then
            -- Check critter exclusion
            local excluded = false
            if settings.critter_exclude ~= "" then
                if Regex.test(npc.name, settings.critter_exclude) then excluded = true end
            end
            if not excluded then dead[#dead+1] = npc end
        end
    end
    return dead
end

local function safe_to_enhance()
    if not settings.enable_skin_safe_mode then return true end
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if npc.status ~= "dead" then return false end
    end
    return true
end

local function skin_critters()
    if not settings.enable_skinning then return end

    local dead = find_dead()
    if #dead == 0 then return end

    local stowed_hands = false

    -- Pre-skinning prep
    if settings.enable_skin_604 and Spell and Spell[604] then
        if Spell[604].known and Spell[604].affordable and not Spell[604].active then
            put("incant 604")
            waitrt()
        end
    end

    if settings.enable_skin_sigil and Spell and Spell[9704] then
        if Spell[9704].known and Spell[9704].affordable and not Spell[9704].active then
            put("incant 9704")
            waitrt()
        end
    end

    if safe_to_enhance() then
        if settings.enable_skin_kneel then fput("kneel") end
        if settings.enable_skin_offensive then change_stance("offensive") end
    end

    -- Skin each critter
    for _, critter in ipairs(dead) do
        local skip = false
        for _, excl in ipairs(settings.skin_exclude) do
            if critter.name:find(excl, 1, true) then skip = true; break end
        end
        if skip then goto continue_skin end
        if critter.name:find("Grimswarm") then goto continue_skin end

        waitrt()
        put("skin #" .. critter.id)
        matchtimeout(5, "skinned", "botched", "already been", "cannot skin", "must be a member", "can only skin", "unable to break", "break through", "crack open")
        waitrt()

        ::continue_skin::
    end

    -- Post-skinning cleanup
    if settings.enable_skin_kneel then
        while not standing() do fput("stand") end
    end
    change_stance("defensive")
end

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------

local function search_dead()
    local dead = find_dead()
    for _, critter in ipairs(dead) do
        waitrt()
        put("search #" .. critter.id)
        matchtimeout(5, "^You search", "^What were you", "plunge your hand", "withdraw")
        waitrt()
        if not settings.enable_search_all then break end
    end
end

--------------------------------------------------------------------------------
-- Looting
--------------------------------------------------------------------------------

local function should_loot(item)
    -- Check exclusions
    if settings.loot_exclude ~= "" and Regex.test(item.name, settings.loot_exclude) then
        return false
    end
    if item.name:find("severed.*arm") or item.name:find("severed.*leg") then
        return false
    end

    -- Check type enables
    local item_type = item.type or ""
    local loot_types = {
        gem = settings.enable_loot_gem,
        box = settings.enable_loot_box,
        skin = settings.enable_loot_skin,
        herb = settings.enable_loot_herb,
        jewelry = settings.enable_loot_jewelry,
        scroll = settings.enable_loot_scroll,
        wand = settings.enable_loot_wand,
        magic = settings.enable_loot_magic,
        reagent = settings.enable_loot_reagent,
        valuable = settings.enable_loot_valuable,
    }

    for t, enabled in pairs(loot_types) do
        if enabled and item_type:find(t) then return true end
    end

    return false
end

local function loot_room(exclude_ids)
    local loot = GameObj.loot()
    if not loot or #loot == 0 then return end

    for _, item in ipairs(loot) do
        -- Skip excluded IDs (pre-existing loot)
        if exclude_ids and exclude_ids[item.id] then goto continue_loot end

        if item.name == "some silver coins" then
            fput("get #" .. item.id)
            goto continue_loot
        end

        if should_loot(item) then
            free_hand()
            if get_item(item, nil) then
                -- Route to appropriate container
                local item_type = (item.type or ""):match("^([^,]+)") or ""
                local sack = sacks[item_type]

                -- Try disk for boxes
                if item_type == "box" and settings.enable_disking then
                    local disk = GameObj.find(GameState.name .. " disk")
                    if disk and put_item(item, disk) then goto continue_loot end
                end

                if sack then
                    if not put_item(item, sack) then
                        -- Try overflow
                        if settings.overflowsack ~= "" then
                            for overflow_name in settings.overflowsack:gmatch("[^,]+") do
                                local overflow = nil
                                for _, inv_item in ipairs(GameObj.inv()) do
                                    if inv_item.name:find(overflow_name:match("^%s*(.-)%s*$"), 1, true) then
                                        overflow = inv_item; break
                                    end
                                end
                                if overflow and put_item(item, overflow) then goto continue_loot end
                            end
                        end
                        fput("drop #" .. item.id)
                    end
                else
                    fput("stow #" .. item.id)
                end
            end
        end

        ::continue_loot::
    end
end

--------------------------------------------------------------------------------
-- Selling
--------------------------------------------------------------------------------

local function deposit_coins()
    go2("bank")
    fput("deposit all")
end

local function sell_routine()
    local cur_room = Map.current_room()
    local silver_breakdown = {}

    -- Find items to sell across all sacks
    local to_sell = {} -- keyed by sell location

    for sack_type, sack in pairs(sacks) do
        if not sack.contents then
            fput("look in #" .. sack.id)
            pause(1)
        end
        local contents = sack.contents or {}
        for _, item in ipairs(contents) do
            if settings.sell_exclude ~= "" and Regex.test(item.name, settings.sell_exclude) then
                goto continue_sell_check
            end
            if item.sellable and item.sellable ~= "" then
                local sell_type = item.type and item.type:match("^([^,]+)") or ""
                local should_sell = false
                if sell_type == "gem" and settings.enable_sell_type_gem then should_sell = true end
                if sell_type == "skin" and settings.enable_sell_type_skin then should_sell = true end
                if should_sell then
                    local loc = item.sellable:match("^([^,]+)") or "gemshop"
                    if not to_sell[loc] then to_sell[loc] = {} end
                    to_sell[loc][#to_sell[loc]+1] = item
                end
            end
            ::continue_sell_check::
        end
    end

    -- Locksmith
    if settings.enable_sell_locksmith then
        local box_sack = sacks["box"]
        if box_sack then
            local boxes = {}
            for _, item in ipairs(box_sack.contents or {}) do
                if item.type and item.type:find("box") then boxes[#boxes+1] = item end
            end
            if #boxes > 0 then
                go2("locksmith")
                for _, box in ipairs(boxes) do
                    get_item(box, nil)
                    -- Ring chime/bell to summon locksmith
                    local activator = nil
                    for _, obj in ipairs(GameObj.loot() or {}) do
                        if Regex.test(obj.noun, "chime|bell") then activator = obj; break end
                    end
                    if activator then
                        put("ring #" .. activator.id)
                        local cost_line = matchtimeout(5, "cost ya.*(%d+) silvers", "already open")
                        if cost_line and cost_line:find("cost ya") then
                            fput("pay")
                            matchtimeout(5, "accepts", "have enough")
                            fput("open #" .. box.id)
                            fput("look in #" .. box.id)
                            pause(1)
                            -- Loot box contents
                            if box.contents then
                                for _, item in ipairs(box.contents) do
                                    if should_loot(item) then
                                        get_item(item, box)
                                        local itype = (item.type or ""):match("^([^,]+)") or ""
                                        local s = sacks[itype]
                                        if s then put_item(item, s) else fput("stow right") end
                                    end
                                end
                            end
                            -- Trash empty box
                            local trash = nil
                            for _, obj in ipairs(GameObj.loot() or {}) do
                                if Regex.test(obj.noun, "crate|barrel|wastebarrel") then trash = obj; break end
                            end
                            if trash then put_item(box, trash) else fput("drop #" .. box.id) end
                        end
                    end
                end
            end
        end
    end

    -- Sell at each location
    for location, items in pairs(to_sell) do
        local start_silver = GameState.silver or 0
        go2(location)

        for _, item in ipairs(items) do
            if get_item(item, nil) then
                fput("sell #" .. item.id)
                matchtimeout(5, "offer", "ask")
                -- If still in hand, stow it back
                local rh = GameObj.right_hand and GameObj.right_hand()
                if rh and rh.id == item.id then
                    local itype = (item.type or ""):match("^([^,]+)") or ""
                    put_item(item, sacks[itype] or "")
                end
            end
        end

        silver_breakdown[location] = (GameState.silver or 0) - start_silver
    end

    deposit_coins()
    go2(cur_room)

    -- Report
    if next(silver_breakdown) then
        respond("\n--- Silver Breakdown ---")
        local total = 0
        for loc, amount in pairs(silver_breakdown) do
            respond("  " .. loc .. ": " .. amount)
            total = total + amount
        end
        respond("  Total: " .. total)
        respond("---\n")
    end
end

--------------------------------------------------------------------------------
-- Ammo gathering
--------------------------------------------------------------------------------

local function gather_ammo()
    if not settings.enable_gather then return end
    if settings.ammo_name == "" then return end

    local ammo_noun = settings.ammo_name:match("(arrow|bolt|dart)") or ""
    if ammo_noun == "" then echo("Invalid ammo type"); return end

    local loot = GameObj.loot()
    local found = {}
    for _, item in ipairs(loot) do
        if item.name:find(settings.ammo_name, 1, true) then
            found[#found+1] = item
        end
    end

    if #found > 0 then
        fput("stow right"); fput("stow left")
        put("gather " .. ammo_noun)
        matchtimeout(5, "^You gather", "^You pick up", "could not")
        local rh = GameObj.right_hand and GameObj.right_hand()
        if rh and Regex.test(rh.noun, "arrow|bolt|dart") then
            local ammo_sack = UserVars and UserVars.ammosack
            if ammo_sack then
                fput("put my " .. rh.noun .. " in my " .. ammo_sack)
            else
                fput("stow my " .. rh.noun)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local function show_setup()
    respond("\n=== Boon v" .. VERSION .. " Settings ===")
    respond("Skinning:      " .. tostring(settings.enable_skinning))
    respond("  Kneel:       " .. tostring(settings.enable_skin_kneel))
    respond("  Offensive:   " .. tostring(settings.enable_skin_offensive))
    respond("  604:         " .. tostring(settings.enable_skin_604))
    respond("  Safe mode:   " .. tostring(settings.enable_skin_safe_mode))
    respond("")
    respond("Loot types:")
    respond("  Gems:        " .. tostring(settings.enable_loot_gem))
    respond("  Boxes:       " .. tostring(settings.enable_loot_box))
    respond("  Skins:       " .. tostring(settings.enable_loot_skin))
    respond("  Herbs:       " .. tostring(settings.enable_loot_herb))
    respond("  Jewelry:     " .. tostring(settings.enable_loot_jewelry))
    respond("  Scrolls:     " .. tostring(settings.enable_loot_scroll))
    respond("  Wands:       " .. tostring(settings.enable_loot_wand))
    respond("  Magic:       " .. tostring(settings.enable_loot_magic))
    respond("")
    respond("Selling:")
    respond("  Locksmith:   " .. tostring(settings.enable_sell_locksmith))
    respond("  Gems:        " .. tostring(settings.enable_sell_type_gem))
    respond("  Skins:       " .. tostring(settings.enable_sell_type_skin))
    respond("")
    respond("Disk/Phase:    " .. tostring(settings.enable_disking) .. "/" .. tostring(settings.enable_phasing))
    respond("Loot exclude:  " .. settings.loot_exclude)
    respond("===\n")
end

local function show_help()
    respond("\nBoon v" .. VERSION .. " by Steworaeus")
    respond("Derived from SpiffyLoot by SpiffyJr\n")
    respond("Usage:")
    respond("  ;boon              — skin, search, and loot current room")
    respond("  ;boon sell         — run automated selling")
    respond("  ;boon deposit      — deposit coins at bank")
    respond("  ;boon setup        — show settings")
    respond("  ;boon left/right   — loot from sack in your hand")
    respond("  ;boon help         — show this help")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

resolve_sacks()

local input = Script.vars[1] or ""

if input:match("^setup$") then
    show_setup()
    return
elseif input:match("^help$") or input:match("^%?$") then
    show_help()
    return
elseif input:match("^sell$") then
    sell_routine()
    return
elseif input:match("^deposit$") then
    deposit_coins()
    return
elseif input:match("^left$") then
    local lh = GameObj.left_hand and GameObj.left_hand()
    if lh and lh.contents then
        loot_room(nil)
    end
    return
elseif input:match("^right$") then
    local rh = GameObj.right_hand and GameObj.right_hand()
    if rh and rh.contents then
        loot_room(nil)
    end
    return
end

-- Safe hiding check
if settings.enable_safe_hiding and GameState.hidden then
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if npc.status ~= "dead" then
            echo("Hostile NPCs present while hidden — aborting")
            return
        end
    end
end

-- Track pre-existing loot IDs for self-drops mode
local previous_ids = {}
if settings.enable_self_drops then
    local loot = GameObj.loot()
    for _, item in ipairs(loot) do
        previous_ids[item.id] = true
    end
end

-- Execute the cycle
skin_critters()
search_dead()
loot_room(settings.enable_self_drops and previous_ids or nil)
gather_ammo()
