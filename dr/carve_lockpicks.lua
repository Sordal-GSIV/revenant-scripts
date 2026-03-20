--- @revenant-script
--- name: carve_lockpicks
--- version: 1.0
--- author: dr-scripts community; ported to Revenant by Sordal-GSIV
--- game: dr
--- description: Carves lockpicks with carving knife, drawing from keyblank pockets until empty.
--- tags: crafting, lockpicks, engineering
---
--- Original: carve-lockpicks.lic (https://github.com/rpherbig/dr-scripts)
--- Authors: dr-scripts contributors (Tillmen, Sheltim, and others)
--- Changelog: See https://github.com/rpherbig/dr-scripts/commits/main/carve-lockpicks.lic
---
--- Ported from carve-lockpicks.lic (Lich5) to Revenant Lua.
--- @lic-certified: complete 2026-03-19
---
--- Usage:
---   ;carve_lockpicks                                            - Carve lockpicks
---   ;carve_lockpicks ring                                       - Put completed batches on rings
---   ;carve_lockpicks ratio_last                                 - Show most recent grandmaster %
---   ;carve_lockpicks ratio_all                                  - Show average grandmaster %
---   ;carve_lockpicks ratio_reset                                - Reset all ratio history
---   ;carve_lockpicks buy_rings <pockets> <masters_ord> <grands_ord>
---
--- YAML Settings (under lockpick_carve_settings):
---   grand_container: carryall          # bag for completed grandmaster's lockpicks
---   master_container: toolkit          # bag for completed master's lockpicks
---   trash_container:                   # bag for sub-master picks (blank = dispose)
---   pocket_container: watery portal    # source of fresh keyblank pockets
---   initial_grand: false               # true to initial your grandmaster picks
---   full_rings_container: backpack     # bag for full rings (must differ from grand/master bag)
---   ring_picks: true                   # put carved picks on rings by default
---   carve_past_ring_capacity: false    # continue carving after rings run out

-------------------------------------------------------------------------------
-- Exit sentinel: use pcall + error(__EXIT__) to exit from nested functions
-------------------------------------------------------------------------------

local __EXIT__ = {}
local function done()
    error(__EXIT__)
end

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------

local settings   = get_settings()
local bag        = settings.crafting_container
local bag_items  = settings.crafting_items_in_container
local belt       = settings.engineering_belt
local lp         = settings.lockpick_carve_settings or {}

-------------------------------------------------------------------------------
-- Arg parsing
-------------------------------------------------------------------------------

local args = Script.vars or {}
local arg1 = args[1] and args[1]:lower() or ""

-------------------------------------------------------------------------------
-- Session counters and ring-slot tracking
-------------------------------------------------------------------------------

local grands_count   = 0
local masters_count  = 0
local grand_batch    = false
local master_batch   = false
local grands_ring_ready  = 25
local masters_ring_ready = 25

-------------------------------------------------------------------------------
-- Ratio history (stored as JSON array of integer percentages in UserVars)
-------------------------------------------------------------------------------

local function load_ratio()
    local raw = UserVars.grands_ratio_json
    if raw and raw ~= "" then
        return Json.decode(raw) or {}
    end
    return {}
end

local function save_ratio(list)
    UserVars.grands_ratio_json = Json.encode(list)
end

local function calc_ratio()
    local list = load_ratio()
    if #list == 0 then return 0 end
    local total = 0
    for _, v in ipairs(list) do total = total + v end
    return math.floor(total / #list + 0.5)
end

-------------------------------------------------------------------------------
-- Ring purchase mode
-------------------------------------------------------------------------------

local function purchase_rings(pockets, mord, gord)
    local mrings, grings
    local list = load_ratio()
    if #list == 0 then
        DRC.message("No data with which to do a ratio calculation, so doing an even split")
        mrings = pockets + 1
        grings = pockets + 1
    else
        local total_rings = (pockets * 50) / 25
        grings = math.floor(calc_ratio() / 100.0 * total_rings + 0.5)
        mrings = total_rings - grings
        grings = grings + math.max(math.floor(grings / 5), 1)
        mrings = mrings + math.max(math.floor(mrings / 5), 1)
    end

    DRC.message("Buying:\nMaster's rings: " .. tostring(mrings) .. "\nGrandmaster's rings: " .. tostring(grings))
    pause(1)

    -- Verify we can afford both ring types
    local total_needed = 0
    local currency     = ""
    local counts       = { mrings, grings }
    local ords         = { mord, gord }
    for i, ord in ipairs(ords) do
        local result = DRC.bput("shop " .. ord .. " lockpick ring",
            "I could not find", "Cost: %d+ %w+")
        local cost_s, curr = result:match("Cost: (%d+) (%w+)")
        if cost_s then
            currency      = curr
            total_needed  = total_needed + tonumber(cost_s) * counts[i]
        else
            DRC.message("Cannot find " .. ord .. " lockpick ring to purchase here.")
            return
        end
    end

    DRC.message("Total purchase price is: " .. DRCM.minimize_coins(total_needed))
    pause(1)
    local on_hand = DRCM.check_wealth(currency)
    if on_hand < total_needed then
        DRC.message("Need coin in the amount of: " .. DRCM.minimize_coins(total_needed - on_hand))
        pause(1)
        return
    else
        DRC.message("Sufficient coin on hand, purchasing.")
        pause(1)
    end

    -- Buy grandmaster rings
    for _ = 1, grings do
        DRCT.buy_item(Room.id, gord .. " lockpick ring")
        DRCI.put_away_item("lockpick ring", lp.grand_container)
    end
    -- Buy master rings
    for _ = 1, mrings do
        DRCT.buy_item(Room.id, mord .. " lockpick ring")
        DRCI.put_away_item("lockpick ring", lp.master_container)
    end
end

-------------------------------------------------------------------------------
-- check_status: re-buff if needed, ensure sitting
-------------------------------------------------------------------------------

local function check_status()
    local waggle = settings.waggle_sets and settings.waggle_sets["carve"]
    if waggle then
        -- Build list of individual words from waggle entries, filter out
        -- delay/khri/combat-skill keywords, capitalize remaining words.
        -- Each entry is like "Khri Harness" → yields "Harness" after filter.
        -- Then we check DRSpells.active_spells()["Khri Harness"].
        local spell_names = {}
        local SKIP = { delay=true, khri=true, puncture=true, slice=true,
                       impact=true, fire=true, cold=true, electric=true }
        for _, entry in ipairs(waggle) do
            for word in tostring(entry):gmatch("%S+") do
                local lower = word:lower()
                if not SKIP[lower] then
                    spell_names[#spell_names + 1] = lower:sub(1,1):upper() .. lower:sub(2)
                end
            end
        end

        local active     = DRSpells.active_spells()
        local need_buff  = false
        for _, name in ipairs(spell_names) do
            if not active["Khri " .. name] then
                need_buff = true
                break
            end
        end
        if need_buff then
            DRC.wait_for_script_to_complete("buff", { "carve" })
        end
    end

    if not sitting() then
        DRC.bput("sit", "You sit", "You are already sitting", "You rise", "While swimming?")
    end
end

-------------------------------------------------------------------------------
-- ring_batch / stow_lockpick (mutually recursive — use local + upvalue pattern)
-------------------------------------------------------------------------------

local stow_lockpick  -- forward declare

local function ring_batch(type_name)
    DRCC.stow_crafting_item("carving knife", bag, belt)
    local ring_container = lp[type_name .. "_container"]

    if not DRCI.get_item("lockpick ring", ring_container) then
        DRC.message("Out of empty rings for " .. type_name .. " picks")
        if type_name == "grand" then
            grand_batch       = false
            grands_ring_ready = 25
        else
            master_batch       = false
            masters_ring_ready = 25
        end
        stow_lockpick(ring_container)
        if not lp.carve_past_ring_capacity then
            done()
        end
        DRCC.get_crafting_item("carving knife", bag, bag_items, belt)
        return
    end

    for _ = 1, 25 do
        DRCI.get_item("lockpick", ring_container)
        DRCI.put_away_item("lockpick", "lockpick ring")
    end

    if not DRCI.put_away_item("lockpick ring", lp.full_rings_container) then
        DRC.message("Out of room for rings")
        done()
    end

    if type_name == "grand" then
        grands_ring_ready = 25
    else
        masters_ring_ready = 25
    end

    DRCC.get_crafting_item("carving knife", bag, bag_items, belt)
end

--- Put a completed lockpick into the appropriate container.
--- Returns only if the script should continue; calls done() on bag-full.
stow_lockpick = function(container)
    if not DRCI.put_away_item("lockpick", container) then
        DRC.message("Bag's full, exiting")
        DRCC.stow_crafting_item("carving knife", bag, belt)
        done()
        return
    end

    if grands_ring_ready <= 0 and grand_batch then
        ring_batch("grand")
    elseif masters_ring_ready <= 0 and master_batch then
        ring_batch("master")
    end
end

-------------------------------------------------------------------------------
-- empty_pocket: dispose of an empty keyblank pocket, fetch a fresh one
-------------------------------------------------------------------------------

local function empty_pocket()
    -- Get the empty pocket into hand so we can dispose of it
    DRCI.get_item("keyblank pocket")
    if DRCI.in_hands("keyblank pocket") then
        DRCI.dispose_trash("keyblank pocket", settings.worn_trashcan, settings.worn_trashcan_verb)
    end

    -- Try to open the next pocket already in inventory
    local result = DRC.bput("open my keyblank pocket",
        "You open", "What were you referring", "That is already open")
    if not result:find("referring") then
        return  -- another pocket is available and now open
    end

    -- No pockets in inventory — fetch one from the portal container
    if DRCI.get_item("keyblank pocket", lp.pocket_container) then
        DRCI.put_away_item("keyblank pocket", lp.full_rings_container)
        DRC.bput("open my keyblank pocket", "You open", "What were you referring", "That is already open")
    else
        DRCC.stow_crafting_item("carving knife", bag, belt)
        done()
    end
end

-------------------------------------------------------------------------------
-- get_keyblank: draw the next keyblank from the open pocket
-------------------------------------------------------------------------------

local get_keyblank  -- forward declare for recursion

get_keyblank = function()
    local result = DRC.bput("get keyblank from my keyblank pocket",
        "You get", "What were you referring to", "You need a free hand")

    if result:find("What were you referring to") then
        local cnt = DRC.bput("count my keyblank pocket",
            "nothing inside the keyblank pocket",
            "It looks like there",
            "I could not find what you were referring to")
        if cnt:find("nothing inside") then
            empty_pocket()
        elseif cnt:find("It looks like there") then
            DRC.bput("open my keyblank pocket", "You open a")
        elseif cnt:find("I could not find") then
            DRCC.stow_crafting_item("carving knife", bag, belt)
            done()
            return
        end
        get_keyblank()

    elseif result:find("You need a free hand") then
        local put = DRC.bput("Put my keyblank in my keyblank pocket",
            "You put a", "What were you referring to")
        if put:find("referring") then
            fput("stow left")
        end
        get_keyblank()
    end
end

-------------------------------------------------------------------------------
-- carve: inner carving loop until no lockpick/keyblank remains in left hand
-------------------------------------------------------------------------------

local function carve()
    while true do
        local lh     = DRC.left_hand() or ""
        local result = DRC.bput("carve my " .. lh .. " with my knife",
            "proudly glance down at a grandmaster",
            "proudly glance down at a master",
            "but feel your knife slip",
            "You are too injured to do any carving",
            "Roundtime",
            "It would be better to find a creature to carve",
            "You cannot figure out how to do that")

        if result:find("proudly glance down at a grandmaster") then
            if lp.initial_grand then
                DRC.bput("carve my lockpick with my knife", "With the precision and skill")
            end
            grands_count       = grands_count + 1
            grands_ring_ready  = grands_ring_ready - 1
            stow_lockpick(lp.grand_container)

        elseif result:find("proudly glance down at a master") then
            masters_count      = masters_count + 1
            masters_ring_ready = masters_ring_ready - 1
            stow_lockpick(lp.master_container)

        elseif result:find("It would be better") or result:find("You cannot figure out") then
            -- Sub-master pick carved; stow or dispose
            local cur_lh = DRC.left_hand()
            if cur_lh then
                if lp.trash_container then
                    DRCI.put_away_item("lockpick", lp.trash_container)
                else
                    DRCI.dispose_trash("lockpick", settings.worn_trashcan, settings.worn_trashcan_verb)
                end
            end

        elseif result:find("You are too injured") then
            DRC.message("Need to be completely wound-free, go get healed")
            DRC.bput("Put my keyblank in my keyblank pocket", "You put a")
            DRCC.stow_crafting_item("carving knife", bag, belt)
            done()
            return
        end

        waitrt()

        local cur_lh = DRC.left_hand() or ""
        if not (cur_lh:find("lockpick") or cur_lh:find("keyblank")) then
            break
        end
    end
end

-------------------------------------------------------------------------------
-- main_loop
-------------------------------------------------------------------------------

local function main_loop()
    DRCC.get_crafting_item("carving knife", bag, bag_items, belt)

    -- Ensure at least one keyblank pocket is accessible before starting
    local has_pocket = DRCI.exists("keyblank pocket")
    if not has_pocket then
        has_pocket = DRCI.get_item("keyblank pocket", lp.pocket_container)
            and DRCI.put_away_item("keyblank pocket", lp.full_rings_container)
    end

    if has_pocket then
        while true do
            check_status()
            get_keyblank()
            carve()
        end
    else
        DRCC.stow_crafting_item("carving knife", bag, belt)
    end
end

-------------------------------------------------------------------------------
-- before_dying: session stats + update ratio history
-------------------------------------------------------------------------------

before_dying(function()
    local total = grands_count + masters_count
    if total == 0 then return end

    local pct = (grands_count / total) * 100.0
    DRC.message("Total grandmaster's picks: " .. tostring(grands_count))
    DRC.message("Total master's picks: " .. tostring(masters_count))
    DRC.message(string.format("Grandmaster's percentage:  %.2f%%", pct))

    local list = load_ratio()
    if #list > 0 then
        local avg     = calc_ratio()
        local rounded = math.floor(pct + 0.5)
        if avg > rounded then
            DRC.message(string.format(
                "This was a bad run, past carving projects yielded %.2f%% more Grandmaster's than Master's picks",
                avg - pct))
        elseif avg < rounded then
            DRC.message(string.format(
                "Nice job, this run beat your past projects by carving %.2f%% more Grandmaster's than Master's picks",
                pct - avg))
        else
            DRC.message("Consistent with past performance, no gain or loss in ratio of Grandmaster's to Master's picks")
        end
    end

    table.insert(list, math.floor(pct + 0.5))
    save_ratio(list)
end)

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------

-- Initialise ring-batch mode from arg or YAML default
if arg1 == "ring" or lp.ring_picks then
    master_batch = true
    grand_batch  = true
end

-- Pre-count lockpicks already in the destination containers to set ring slots
local grand_on_hand  = DRCI.count_items_in_container("lockpick", lp.grand_container)
local master_on_hand = DRCI.count_items_in_container("lockpick", lp.master_container)
grands_ring_ready    = 25 - grand_on_hand
masters_ring_ready   = 25 - master_on_hand

if grands_ring_ready < 25 then
    echo("Grands on hand: " .. tostring(grand_on_hand))
end
if masters_ring_ready < 25 then
    echo("Masters on hand: " .. tostring(master_on_hand))
end

-- Dispatch
local ok, err = pcall(function()
    if arg1 == "buy_rings" then
        local pockets = tonumber(args[2]) or 0
        local mord    = args[3] or "first"
        local gord    = args[4] or "second"
        purchase_rings(pockets, mord, gord)

    elseif arg1 == "ratio_last" then
        local list = load_ratio()
        if #list > 0 then
            DRC.message("Most recent percentage of Grandmaster's to Master's picks: " .. tostring(list[#list]))
        else
            DRC.message("No ratio history recorded yet.")
        end

    elseif arg1 == "ratio_all" then
        DRC.message("Average of all recorded carving projects to date, Grandmaster's percentages: " .. tostring(calc_ratio()))

    elseif arg1 == "ratio_reset" then
        local list = load_ratio()
        DRC.message("Resetting past carving projects data. Historical data: " .. Json.encode(list))
        save_ratio({})

    else
        main_loop()
    end
end)

if not ok and err ~= __EXIT__ then
    error(tostring(err), 0)
end
