--- @module blackarts.guild
-- Guild task management, recipe engine, cauldron handling.
-- Ported from BlackArts::Guild (BlackArts.lic v3.12.x)

local state   = require("state")
local util    = require("util")
local inv     = require("inventory")

local M = {}

-- Recursive padding counter (for debug output depth tracking)
local recursive_padding = 0

-- Lazy-loaded recipes module
local function recipes_mod()
    return require("recipes")
end

--------------------------------------------------------------------------------
-- GLD output parsing
-- Returns {guild={standing,vouchers,guild_night}, alchemy={rank,task,reps}, ...}
--------------------------------------------------------------------------------

local GLD_TYPE_MAP = {
    ["General Alchemy"]   = "alchemy",
    ["Alchemic Potions"]  = "potions",
    ["Alchemic Trinkets"] = "trinkets",
    ["Illusions"]         = "illusions",
}

function M.gld()
    local result = { guild = {} }
    for _, t in pairs(GLD_TYPE_MAP) do
        if t ~= "illusions" or Char.prof == "Sorcerer" then
            result[t] = {}
        end
    end

    fput("gld")
    local current_type = nil

    for _ = 1, 50 do
        local line = get()
        if not line then break end

        -- Guild standing
        if Regex.test(line, "You (?:are an?|have) (?:inactive member|member|no guild affiliation|Guild Master|Grandmaster)") then
            result.guild.standing = line:match("You %w+ (%w+ ?%w*)")
        end

        -- Rank line: "You have N ranks in the X skill."
        local rank_str = line:match("You have (%d+) ranks? in the (.+) skill")
        if rank_str then
            local n = tonumber(rank_str)
            local type_name = line:match("in the (.+) skill")
            if type_name and GLD_TYPE_MAP[type_name] then
                current_type = GLD_TYPE_MAP[type_name]
                if result[current_type] then result[current_type].rank = n end
            end
        end

        -- "You have no ranks in the X skill."
        if line:find("You have no ranks") then
            local type_name = line:match("in the (.+) skill")
            if type_name and GLD_TYPE_MAP[type_name] then
                current_type = GLD_TYPE_MAP[type_name]
                if result[current_type] then result[current_type].rank = 0 end
            end
        end

        -- "Master of X."
        local master = line:match("Master of (.+)%.")
        if master and GLD_TYPE_MAP[master] then
            if result[GLD_TYPE_MAP[master]] then
                result[GLD_TYPE_MAP[master]].rank = 63
            end
        end

        -- Task assignment
        local task = line:match("told you to (.+)%.")
        if task and current_type and result[current_type] then
            result[current_type].task = task
        end

        -- Promotion ready
        if Regex.test(line, "earned enough training points") and current_type and result[current_type] then
            result[current_type].task = "promotion"
        end

        -- No task
        if Regex.test(line, "not currently training|not yet obtained|not yet been assigned|not been assigned") then
            if current_type and result[current_type] then
                result[current_type].task = "no task"
                result[current_type].reps = 0
            end
        end

        -- Reps remaining
        local reps = line:match("(%d+) repetitions? remaining")
        if reps and current_type and result[current_type] then
            result[current_type].reps = tonumber(reps)
        end
        if line:find("no repetitions remaining") and current_type and result[current_type] then
            result[current_type].reps = 0
        end

        -- Vouchers
        local vouchers = line:match("have (%d+) task trading vouchers")
        if vouchers then result.guild.vouchers = tonumber(vouchers) end

        -- Guild night
        if Regex.test(line, "Guild Night|doubled") then
            result.guild.guild_night = true
        end

        if Regex.test(line, "^>$|<prompt") then break end
    end

    util.msg("debug", "Guild.gld: result = " .. Json.encode(result))
    return result
end

--------------------------------------------------------------------------------
-- Check audience for illusion task (need >= 5 audience points)
--------------------------------------------------------------------------------

function M.check_audience()
    return require("illusions").check_audience()
end

--------------------------------------------------------------------------------
-- Check and apply guild boost if configured
--------------------------------------------------------------------------------

function M.check_boost(guild_status)
    if not (util.cfg and util.cfg.use_boost) then return end
    if Effects.Buffs.active("Guild Boost") then return end
    if guild_status.guild and guild_status.guild.guild_night then return end

    local lines = util.get_lines("boost info",
        "your Login Rewards information is as follows")
    local boosts = 0
    for _, line in ipairs(lines) do
        local n = line:match("Guild Boosts.*?(%d+)$")
        if n then boosts = tonumber(n:gsub(",", "")); break end
    end
    if boosts > 0 then
        fput("boost guild profession")
        util.wait_rt()
    end
end

--------------------------------------------------------------------------------
-- Initialize a fresh tracker table
--------------------------------------------------------------------------------

function M.initialize_tracker()
    return {
        error             = {},
        recipe_count      = {},
        claimed_ingredients = {},
        ingredient_count  = {},
        extra_ingredients = {},
        found             = {},
        buy               = {},
        forage            = {},
        kill_for          = {},
        steps             = {},
        prepare_steps     = {},
        finish_steps      = {},
        cost              = 0,
        time              = 0,
        itime             = {},
        icost             = {},
    }
end

--------------------------------------------------------------------------------
-- Deep-copy a tracker (needed for recursive exploration of recipe trees)
--------------------------------------------------------------------------------

local function copy_tracker(t)
    local function deep_copy(orig)
        local copy = {}
        for k, v in pairs(orig) do
            if type(v) == "table" then
                copy[k] = deep_copy(v)
            else
                copy[k] = v
            end
        end
        return copy
    end
    return deep_copy(t)
end

--------------------------------------------------------------------------------
-- check_ingredient — look for an ingredient across all sacks
-- Returns: found (bool), new_claimed_list, new_count_map
--------------------------------------------------------------------------------

function M.check_ingredient(ingredient_name, temp_claimed, temp_count)
    temp_claimed = temp_claimed or {}
    temp_count   = temp_count or {}
    for k, v in pairs(state.ingredient_count) do
        if temp_count[k] == nil then temp_count[k] = v end
    end

    local rm = recipes_mod()
    local all_contents = inv.all_sack_contents()

    -- Build equivalents list
    local equivalents = {ingredient_name}
    for _, group in ipairs(rm.alchemy_equivalents) do
        local in_group = false
        for _, e in ipairs(group) do
            if e == ingredient_name then in_group = true; break end
        end
        if in_group then equivalents = group; break end
    end

    -- 1. Check for multi-dose minor holy oil
    for _, item in ipairs(all_contents) do
        local name_match = false
        for _, eq in ipairs(equivalents) do
            if item.name == eq then name_match = true; break end
        end
        if name_match and item.name and item.name:lower():find("minor holy oil") then
            if temp_count[item.id] == nil then
                inv.free_hands({ both = true })
                util.get_res("get #" .. item.id, state.get_regex or "You")
                local lines = util.get_lines("measure #" .. item.id, "minor holy oil")
                local amount = 1
                for _, l in ipairs(lines) do
                    local n = l:match("(%d+)%s+dose")
                    if n then amount = tonumber(n); break end
                end
                temp_count[item.id] = amount
                state.ingredient_count[item.id] = amount
                inv.single_drag(item)
            end
            if (temp_count[item.id] or 0) > 0 then
                temp_count[item.id] = temp_count[item.id] - 1
                return true, temp_claimed, temp_count
            end
        end
    end

    -- 2. Check for unbundled, unclaimed single item
    local BUNDLED_HERB_RX = Regex.new(
        "^some acantha leaf$|^some cactacae spine$|^some ambrominas leaf$|^some torban leaf$" ..
        "|^some wolifrew lichen$|^some sovyn clove$|^some ephlox moss$|^some pothinir grass$" ..
        "|^some haphip root$|^some calamia fruit$|^some aloeas stem$|^some basal moss$|^some woth flower$"
    )
    for _, item in ipairs(all_contents) do
        local name_match = false
        for _, eq in ipairs(equivalents) do
            if item.name == eq then name_match = true; break end
        end
        if name_match and not (item.name and Regex.test(item.name, BUNDLED_HERB_RX)) and
           not (item.name and item.name:lower():find("minor holy oil")) then
            local claimed = false
            for _, c in ipairs(temp_claimed) do
                if c == item.id then claimed = true; break end
            end
            if not claimed then
                temp_claimed[#temp_claimed + 1] = item.id
                return true, temp_claimed, temp_count
            end
        end
    end

    -- 3. Check for bundled herbs
    for _, item in ipairs(all_contents) do
        local name_match = false
        for _, eq in ipairs(equivalents) do
            if item.name == eq then name_match = true; break end
        end
        if name_match and item.name and Regex.test(item.name, BUNDLED_HERB_RX) then
            if temp_count[item.id] == nil then
                inv.free_hands({ both = true })
                util.get_res("get #" .. item.id, state.get_regex or "You")
                local lines = util.get_lines("measure #" .. item.id, "has %d+ (?:bite|bites) left")
                local amount = 1
                for _, l in ipairs(lines) do
                    local n = l:match("has (%d+) (?:bite|bites) left")
                    if n and tonumber(n) > 0 then amount = tonumber(n); break end
                end
                temp_count[item.id] = amount
                state.ingredient_count[item.id] = amount
                inv.single_drag(item)
            end
            if (temp_count[item.id] or 0) > 0 then
                temp_count[item.id] = temp_count[item.id] - 1
                return true, temp_claimed, temp_count
            end
        end
    end

    -- 4. Check for reagent jar containing the ingredient
    for _, item in ipairs(all_contents) do
        if item.after_name then
            for _, eq in ipairs(equivalents) do
                -- Build a loose regex for matching jar contents
                local eq_pattern = eq:gsub("some ", "(?:some )?")
                                     :gsub("handful of ", "(?:handful of )?")
                                     :gsub("sprig of ", "(?:sprig of )?")
                                     :gsub("tooth", "(?:teeth|tooth)")
                                     :gsub("leaf", "(?:leaf|leaves)")
                                     :gsub("y%b", "(?:y|ie)")
                local jar_rx_str = "containing " .. eq_pattern
                if Regex.test(item.after_name, Regex.new(jar_rx_str)) then
                    if temp_count[item.id] == nil then
                        local amount = util.jar_count(item)
                        temp_count[item.id] = amount
                        state.ingredient_count[item.id] = amount
                    end
                    if (temp_count[item.id] or 0) > 0 then
                        temp_count[item.id] = temp_count[item.id] - 1
                        return true, temp_claimed, temp_count
                    end
                    break
                end
            end
        end
    end

    -- 5. Check for bundle-of-X
    for _, item in ipairs(all_contents) do
        if item.name then
            for _, eq in ipairs(equivalents) do
                local bundle_name = "bundle of " .. eq
                if item.name:find(bundle_name, 1, true) then
                    if temp_count[item.id] == nil then
                        local lines = util.get_lines("measure #" .. item.id, "total of %d+")
                        local amount = 0
                        for _, l in ipairs(lines) do
                            local n = l:match("total of (%d+)")
                            if n then amount = tonumber(n); break end
                        end
                        temp_count[item.id] = amount
                        state.ingredient_count[item.id] = amount
                    end
                    if (temp_count[item.id] or 0) > 0 then
                        temp_count[item.id] = temp_count[item.id] - 1
                        return true, temp_claimed, temp_count
                    end
                    break
                end
            end
        end
    end

    return false, temp_claimed, temp_count
end

--------------------------------------------------------------------------------
-- check_locations — find room + travel time for a forage/hunt/buy location
-- Returns: room_id (0 if inaccessible), travel_time
--------------------------------------------------------------------------------

function M.check_locations(item, place)
    -- Check cache first
    for _, entry in ipairs(state.locations) do
        if entry.starting_room == Room.id and entry.item == item then
            return entry.room, entry.travel
        end
    end

    local extra_time = (place == "hunting") and 30 or (place == "foraging") and 10 or 0
    local room_id = 0
    local travel_time = 0

    if place == "hunting" then
        local hunting = require("hunting")
        local r = hunting.hunting_areas(item)
        if r then room_id = r end
    else
        local result = Map.find_nearest_by_tag(item)
        if result then room_id = result.id end
    end

    if room_id ~= 0 and room_id ~= Room.id then
        local cost = Map.path_cost(Room.id, room_id)
        if not cost then
            room_id = 0
        else
            -- Check boundaries
            for _, fence in ipairs(state.boundaries) do
                if room_id == fence then room_id = 0; break end
            end
            if room_id ~= 0 then
                travel_time = extra_time + (cost * 0.4)
            end
        end
    end

    -- Cache the result
    state.locations[#state.locations + 1] = {
        starting_room = Room.id,
        item          = item,
        room          = room_id,
        travel        = travel_time,
    }

    return room_id, travel_time
end

--------------------------------------------------------------------------------
-- recursive_check_recipe — evaluate one recipe recursively
-- Populates tracker with cost/time/buy/forage/kill/error info
--------------------------------------------------------------------------------

function M.recursive_check_recipe(recipe, tracker, top_level)
    recursive_padding = recursive_padding + 3
    local rm = recipes_mod()

    for _, step in ipairs(recipe.steps) do
        recursive_padding = recursive_padding + 3

        if step:match("^(?:add|grind|extract|distill|separate)%s+(.*)") then
            local ingredient_name = step:match("^%w+%s+(.*)")

            if step:find("^grind") then
                -- Check for mortar
                local has_mortar = false
                for _, item in ipairs(inv.all_sack_contents()) do
                    if item.noun == "mortar" then has_mortar = true; break end
                end
                if not has_mortar then tracker.error["mortar"] = 1 end
                tracker.time = tracker.time + (Char.prof == "Wizard" and 5 or 25)
            elseif step:find("^extract") then
                if (state.ranks or 0) > 14 then
                    tracker.time = tracker.time + 40
                else
                    tracker.error["extract skill"] = 1
                end
            elseif step:find("^distill") then
                tracker.time = tracker.time + 40
            end

            -- Check if this is an "extra ingredient" (ayanad crystal produced in sub-recipe)
            local in_extra = false
            for i, e in ipairs(tracker.extra_ingredients) do
                if e == ingredient_name then
                    table.remove(tracker.extra_ingredients, i)
                    in_extra = true
                    break
                end
            end

            if not in_extra then
                local found, new_claimed, new_count = M.check_ingredient(
                    ingredient_name, tracker.claimed_ingredients, tracker.ingredient_count)
                if found then
                    tracker.claimed_ingredients = new_claimed
                    tracker.ingredient_count    = new_count
                    tracker.found[ingredient_name] = (tracker.found[ingredient_name] or 0) + 1
                    -- Add opportunity cost
                    if rm.alchemy_reagent_op_cost[ingredient_name] then
                        tracker.cost = tracker.cost + rm.alchemy_reagent_op_cost[ingredient_name]
                    end
                else
                    -- Try sub-recipes
                    local sub_recipes = {}
                    for _, r in ipairs(rm.alchemy_recipes) do
                        if r.product == ingredient_name then
                            sub_recipes[#sub_recipes + 1] = r
                        end
                    end
                    if #sub_recipes > 0 then
                        local tracker_list = {}
                        for _, sub_recipe in ipairs(sub_recipes) do
                            local t2 = copy_tracker(tracker)
                            t2 = M.recursive_check_recipe(sub_recipe, t2, false)
                            tracker_list[#tracker_list + 1] = t2
                            for k, v in pairs(state.ingredient_count) do
                                if tracker.ingredient_count[k] == nil then
                                    tracker.ingredient_count[k] = v
                                end
                            end
                        end
                        -- Sort by cost+time, prefer error-free
                        table.sort(tracker_list, function(a, b)
                            local ae = 0; for _, v in pairs(a.error) do ae = ae + v end
                            local be = 0; for _, v in pairs(b.error) do be = be + v end
                            if ae ~= be then return ae < be end
                            return (a.cost + a.time * 15) < (b.cost + b.time * 15)
                        end)
                        tracker = tracker_list[1]
                    else
                        tracker.error[ingredient_name] = (tracker.error[ingredient_name] or 0) + 1
                    end
                end
            end

        elseif step:match("^buy%s+.*?from%s+(.*)") then
            local place = step:match("^buy%s+.*?from%s+(.*)")
            local room_id, travel_time = M.check_locations(place, "shopping")
            tracker.time = tracker.time + travel_time
            tracker.cost = tracker.cost + (recipe.cost or 0)
            if room_id == 0 then
                tracker.error[place .. " to buy " .. recipe.product] =
                    (tracker.error[place .. " to buy " .. recipe.product] or 0) + 1
            else
                local key = room_id .. ";" .. recipe.product
                tracker.buy[key] = (tracker.buy[key] or 0) + 1
            end

        elseif step:match("^forage") then
            local light = step:match("^forage( in sunlight| in moonlight)?")
            local herb_name = recipe.product:gsub("^some ", "")
            local room_id, travel_time = M.check_locations(herb_name, "foraging")

            if room_id == 0 then
                tracker.error[recipe.product] = (tracker.error[recipe.product] or 0) + 1
            elseif light == " in sunlight" and util.is_moonlight() then
                tracker.error["sunlight to forage for " .. recipe.product] = 1
            elseif light == " in moonlight" and util.is_sunlight() then
                tracker.error["moonlight to forage for " .. recipe.product] = 1
            else
                tracker.time = tracker.time + travel_time
                tracker.forage[recipe.product] = (tracker.forage[recipe.product] or 0) + 1
            end

        elseif step:match("^kill%s+(.*)") then
            local npc = step:match("^kill%s+(.*)")
            local room_id, travel_time = M.check_locations(npc, "hunting")
            if room_id == 0 then
                tracker.error[recipe.product] = (tracker.error[recipe.product] or 0) + 1
            else
                tracker.kill_for[npc] = tracker.kill_for[npc] or {}
                tracker.time = tracker.time + travel_time
                tracker.kill_for[npc][recipe.product] =
                    (tracker.kill_for[npc][recipe.product] or 0) + 1
            end

        elseif step == "light" then
            -- Cauldron check
            local has_cauldron = false
            if state.cauldron then has_cauldron = true end
            for _, obj in ipairs(GameObj.room_desc()) do
                if obj.noun and obj.noun == "cauldron" then has_cauldron = true; break end
            end
            for _, obj in ipairs(inv.all_sack_contents()) do
                if obj.noun and obj.noun == "cauldron" then has_cauldron = true; break end
            end
            if not has_cauldron then tracker.error["cauldron"] = 1 end

        elseif step == "special" then
            local SEA_FLASK_RX = Regex.new("^(?:small|small opaque|faceted) crystal flask$|^dark sphene-inset flask$")
            local SEA_VIAL_RX  = Regex.new("^(?:clouded|warped|chipped|tapered|smoky|thick|slender|clear|blackened) glass vial$|^polished glaes vial$|^thin iron-encased vial$")
            local has_flask, has_vial = false, false
            for _, item in ipairs(inv.all_sack_contents()) do
                if Regex.test(item.name, SEA_FLASK_RX) then has_flask = true end
                if Regex.test(item.name, SEA_VIAL_RX)  then has_vial  = true end
            end
            if not has_flask then tracker.error["flask for sea water"] = 1 end
            if not has_vial  then tracker.error["vial for sea water"]  = 1 end
            tracker.time = tracker.time + 40

        elseif step == "check blood" then
            local has_blood = false
            local SEA_FLASK_RX = Regex.new("^(?:small|small opaque|faceted) crystal flask$|^dark sphene-inset flask$")
            local SEA_VIAL_RX  = Regex.new("^(?:clouded|warped|chipped|tapered|smoky|thick|slender|clear|blackened) glass vial$|^polished glaes vial$|^thin iron-encased vial$")
            for _, item in ipairs(inv.all_sack_contents()) do
                if Regex.test(item.name, SEA_FLASK_RX) or Regex.test(item.name, SEA_VIAL_RX) then
                    local lines = util.get_lines("look in #" .. item.id, "cork that")
                    for _, l in ipairs(lines) do
                        if l:find("dark crimson fluid") then has_blood = true; break end
                    end
                end
                if has_blood then break end
            end
            if not has_blood then tracker.error["troll blood"] = 1 end
            tracker.time = tracker.time + 40

        elseif step == "simmer" then  tracker.time = tracker.time + 20
        elseif step == "boil"   then  tracker.time = tracker.time + 20
        elseif step:find("^chant") then tracker.time = tracker.time + 30
        elseif step:find("^infuse") then
            tracker.time = tracker.time + 15
            if (state.ranks or 0) < 30 then tracker.error["alchemy infuse"] = 1 end
        elseif step == "channel" then tracker.time = tracker.time + 30
        elseif step == "seal"    then tracker.time = tracker.time + 26
        elseif step:match("^refract (moonlight|sunlight) through (.* lens)$") then
            local light, lens = step:match("^refract (moonlight|sunlight) through (.* lens)$")
            local has_lens = false
            for _, item in ipairs(inv.all_sack_contents()) do
                if item.name == lens then has_lens = true; break end
            end
            if not has_lens then tracker.error[lens] = 1 end
            if (light == "sunlight" and util.is_moonlight()) or
               (light == "moonlight" and util.is_sunlight()) then
                tracker.error[light] = 1
            end
            tracker.time = tracker.time + 10
        end

        recursive_padding = recursive_padding - 3
    end

    -- Record steps in tracker
    if top_level then
        tracker.recipe_count[recipe.product] = (tracker.recipe_count[recipe.product] or 0) + 1
        for _, step in ipairs(recipe.steps) do
            if not step:match("^(?:buy|forage|kill)") then
                tracker.finish_steps[#tracker.finish_steps + 1] = step
            end
        end
    else
        for _, step in ipairs(recipe.steps) do
            if not step:match("^(?:buy|forage|kill|check blood)") then
                tracker.prepare_steps[#tracker.prepare_steps + 1] = step
            end
        end
    end

    for _, step in ipairs(recipe.steps) do
        if not step:match("^(?:buy|forage|kill)") then
            tracker.steps[#tracker.steps + 1] = step
        end
    end

    -- Mark ayanad crystal as available extra if produced by sub-recipe
    if recipe.product:match("^(?:s'|t')?ayanad crystal$") then
        tracker.extra_ingredients[#tracker.extra_ingredients + 1] = recipe.product
    end

    recursive_padding = recursive_padding - 3
    return tracker
end

--------------------------------------------------------------------------------
-- check_recipe — find best recipe(s) and build a full supply plan
-- args: {name=, names=, recipe=, recipes=, reps=, prep_create=}
--------------------------------------------------------------------------------

function M.check_recipe(args)
    util.msg("debug", "Guild.check_recipe: args = " .. Json.encode(args))
    local rm = recipes_mod()

    local recipe_list = {}
    if args.name then
        for _, r in ipairs(rm.alchemy_recipes) do
            if r.product == args.name then recipe_list[#recipe_list + 1] = r end
        end
    elseif args.names then
        local name_set = {}
        for _, n in ipairs(args.names) do name_set[n] = true end
        for _, r in ipairs(rm.alchemy_recipes) do
            if name_set[r.product] then recipe_list[#recipe_list + 1] = r end
        end
    elseif args.recipe then
        recipe_list = {args.recipe}
    elseif args.recipes then
        recipe_list = args.recipes
    end

    args.reps = args.reps or 1

    -- Evaluate each candidate and compute value = cost + time*15
    for _, recipe in ipairs(recipe_list) do
        local t2 = M.recursive_check_recipe(recipe, M.initialize_tracker(), true)
        recipe._value = t2.cost + t2.time * 15
        recursive_padding = 0
    end

    -- Filter to feasible recipes (unless prep_create mode)
    if not args.prep_create then
        local feasible = {}
        for _, recipe in ipairs(recipe_list) do
            local t2 = M.recursive_check_recipe(recipe, M.initialize_tracker(), true)
            recursive_padding = 0
            if not next(t2.error) then
                feasible[#feasible + 1] = recipe
            end
        end
        if #feasible > 0 then recipe_list = feasible end
    end

    if #recipe_list == 0 then
        M.no_recipe()
    end

    table.sort(recipe_list, function(a, b)
        return (a._value or 0) < (b._value or 0)
    end)

    -- Run multiple reps to accumulate supply needs
    local tracker = M.initialize_tracker()
    for _, recipe in ipairs(recipe_list) do
        local temp = M.initialize_tracker()
        for _ = 1, args.reps do
            temp = M.recursive_check_recipe(recipe, temp, true)
            recursive_padding = 0
            -- Merge ingredient counts
            for k, v in pairs(state.ingredient_count) do
                if temp.ingredient_count[k] == nil then temp.ingredient_count[k] = v end
            end
        end
        if next(temp.error) == nil or args.prep_create then
            tracker = temp
            break
        end
    end

    if not next(tracker.recipe_count) then
        util.msg_error("Failed to find a viable recipe. Use ';blackarts suggest' for details.")
        if (os.time() - (state.last_alchemy_buy or 0)) > 600 then
            require("actions").buy_elusive()
        end
        error("no viable recipe")
    end

    -- Post-process: kill counts (how many of each skin are needed)
    for creature, skins in pairs(tracker.kill_for) do
        for skin, _ in pairs(skins) do
            local count = 0
            for _, step in ipairs(tracker.steps) do
                if step:find(skin) then count = count + 1 end
            end
            tracker.kill_for[creature][skin] = count
        end
    end

    -- Restructure buy: {"room;item" -> N} => {room -> {item -> N}}
    local fixed_buy = {}
    for key, num in pairs(tracker.buy) do
        local room, item = key:match("^([^;]+);(.*)")
        if room and item then
            fixed_buy[room] = fixed_buy[room] or {}
            fixed_buy[room][item] = num
        end
    end
    tracker.buy = fixed_buy

    -- Clean up internal fields
    tracker.claimed_ingredients = nil
    tracker.ingredient_count    = nil
    tracker.extra_ingredients   = nil

    util.msg("debug", "Guild.check_recipe: tracker = " .. Json.encode(tracker))
    return tracker
end

--------------------------------------------------------------------------------
-- no_recipe — error handler when no recipe can be found
--------------------------------------------------------------------------------

function M.no_recipe()
    util.msg_error("Unable to find a recipe for current guild task.")
    respond("Run ';blackarts suggest' for a breakdown of what's missing.")
    error("no recipe available")
end

--------------------------------------------------------------------------------
-- gld_suggestions — populate guild_status with matching recipe lists
--------------------------------------------------------------------------------

function M.gld_suggestions(guild_status)
    local rm = recipes_mod()
    for skill_type, info in pairs(guild_status) do
        if type(info) == "table" and info.recipes == nil and info.task then
            local task = info.task
            local rank = info.rank or 0
            local req_step = task:match("(?:with your|that involve) (.*?)(?:(?: ability| mana|ing spells|ing|ing mana|ing spirit))?$")

            if req_step and task:find("cauldron workshop") then
                info.recipes = {}
                for _, r in ipairs(rm.alchemy_recipes) do
                    if r.type == skill_type and r.rank and
                       rank >= r.rank[1] and rank <= r.rank[2] then
                        local has_step = false
                        local has_refract = false
                        for _, s in ipairs(r.steps) do
                            if s:match("^" .. req_step) then has_step = true end
                            if s:find("^refract") then has_refract = true end
                        end
                        if has_step and not has_refract then
                            info.recipes[#info.recipes + 1] = r
                        end
                    end
                end
            elseif req_step then
                info.recipes = {}
                for _, r in ipairs(rm.alchemy_recipes) do
                    if r.type == skill_type and r.rank and
                       rank >= r.rank[1] and rank <= r.rank[2] then
                        local has_step = false
                        for _, s in ipairs(r.steps) do
                            if s:match("^" .. req_step) then has_step = true; break end
                        end
                        if has_step then info.recipes[#info.recipes + 1] = r end
                    end
                end
            elseif task:find("follow some tough recipes") or task:find("visit a skilled master") then
                info.recipes = {}
                for _, r in ipairs(rm.alchemy_recipes) do
                    if r.product ~= "flask of pure water" and r.type == skill_type and r.rank and
                       rank >= r.rank[1] and rank <= r.rank[2] then
                        info.recipes[#info.recipes + 1] = r
                    end
                end
            elseif task == "practice distilling for reagents" then
                info.recipes = {}
                for _, r in ipairs(rm.alchemy_recipes) do
                    if r.product == "flask of pure water" then
                        info.recipes[#info.recipes + 1] = r
                    end
                end
            else
                info.recipes = {}
                for _, r in ipairs(rm.alchemy_recipes) do
                    if r.type == skill_type and r.rank and
                       rank >= r.rank[1] and rank <= r.rank[2] then
                        info.recipes[#info.recipes + 1] = r
                    end
                end
            end
        end
    end
    return guild_status
end

--------------------------------------------------------------------------------
-- Cauldron management
--------------------------------------------------------------------------------

function M.get_cauldron()
    -- If we have a cauldron in inventory, do nothing
    for _, item in ipairs(inv.all_sack_contents()) do
        if item.noun and (item.noun == "cauldron" or item.noun == "boiler") then
            state.cauldron = item
            return
        end
    end
    -- Check room
    for _, item in ipairs(GameObj.room_desc()) do
        if item.noun and (item.noun == "cauldron" or item.noun == "boiler") then
            state.cauldron = item
            return
        end
    end
    for _, item in ipairs(GameObj.loot()) do
        if item.noun and (item.noun == "cauldron" or item.noun == "boiler") then
            state.cauldron = item
            return
        end
    end
end

function M.drop_cauldron()
    if not state.cauldron then return end
    -- Check if cauldron is being carried
    for _, item in ipairs(inv.all_sack_contents()) do
        if item.id == state.cauldron.id then
            inv.drag(state.cauldron)
            fput("drop #" .. state.cauldron.id)
            sleep(0.3)
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Navigate to the administrator then get a guild task
--------------------------------------------------------------------------------

function M.get_work(skill)
    if state.current_admin then
        util.travel(state.current_admin)
    else
        go2(Char.prof:lower() .. " alchemy administrator")
    end

    local npc = GameObj.find_npc("training")
    if npc then
        fput(string.format("ask #%s to train %s", npc.id, skill))
    end
    sleep(2)
end

function M.get_promoted(skill)
    go2(Char.prof:lower() .. " alchemy guildmaster")
    local npc = GameObj.find_npc("guild")
    if npc then
        fput(string.format("ask #%s about next %s", npc.id, skill))
    end
    sleep(2)
end

function M.remove_task(skill)
    if state.current_admin then util.travel(state.current_admin) end
    local npc = GameObj.find_npc("training")
    if npc then
        fput(string.format("ask #%s about trade %s", npc.id, skill))
    end
    sleep(2)
end

--------------------------------------------------------------------------------
-- skilled_masters — visit an Arcane Master for a training lesson
--------------------------------------------------------------------------------

function M.skilled_masters(skill, reps)
    go2(Char.prof:lower() .. " alchemy masters")
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if npc.name and npc.name:find("Master") and not npc.name:find("Guild Master") then
            fput(string.format("ask %s about training %s", npc.noun, skill))
            sleep(3)
            for _ = 1, 20 do
                local line = get()
                if not line then break end
                if line:find("LIGHT the cauldron") then
                    fput("light cauldron")
                elseif line:find("EXTINGUISH the cauldron") then
                    fput("extinguish cauldron")
                elseif line:find("ALCHEMY SEAL") or line:find("SEAL the mixture") then
                    fput("alchemy seal")
                elseif line:find("completed your training task") then
                    break
                end
            end
            break
        end
    end
end

--------------------------------------------------------------------------------
-- Guild activity router — routes a task to the right handler
--------------------------------------------------------------------------------

function M.activity(guild_status, skill, cfg)
    local task_module = require("tasks")
    local info = guild_status[skill]
    if not info then
        util.msg_error("Unknown skill: " .. tostring(skill))
        return
    end

    local task = info.task or "no task"
    local reps = info.reps or 0

    util.msg("yellow", string.format("[BlackArts] Task: %s (%d reps)", task, reps))

    if task == "promotion" then
        M.get_promoted(skill)
        M.new_task(skill, cfg)

    elseif task == "no task" or reps == 0 then
        M.get_work(skill)
        M.new_task(skill, cfg)

    elseif task:find("clean alchemic equipment") then
        task_module.clean_equipment()
        M.new_task(skill, cfg)

    elseif task:find("sweep the alchemy labs") then
        task_module.sweep_labs()
        M.new_task(skill, cfg)

    elseif task:find("polish tarnished lens") then
        task_module.polish_lens()
        M.new_task(skill, cfg)

    elseif task:find("distill") and task:find("pure water") then
        task_module.distill_water()
        M.new_task(skill, cfg)

    elseif task:find("visit a skilled master") or task:find("find an Arcane Master") then
        M.skilled_masters(skill, reps)
        M.new_task(skill, cfg)

    elseif task:find("practice grinding") then
        if cfg and cfg.no_alchemy then
            M.remove_task(skill)
        else
            go2(Char.prof:lower() .. " alchemy workshop")
            local mortar = nil
            for _, item in ipairs(inv.all_sack_contents()) do
                if item.noun == "mortar" then mortar = item; break end
            end
            if mortar then
                inv.drag(mortar)
                for _ = 1, reps do
                    util.wait_rt()
                    fput("alchemy grind")
                    sleep(3)
                end
                inv.free_hands({ both = true })
            end
        end
        M.new_task(skill, cfg)

    elseif task:find("Illusion") and task:find("audience") then
        local illusions = require("illusions")
        illusions.do_illusions("audience", M)
        M.new_task(skill, cfg)

    elseif task:find("Illusion") and task:find("one minute") then
        local illusions = require("illusions")
        illusions.do_illusions("speed", M)
        M.new_task(skill, cfg)

    elseif task:find("cauldron workshop") or task:find("tough recipes") or
           task:find("follow some tough") then
        -- Workshop recipe task
        M.check_boost(guild_status)
        local guild_status2 = M.gld()
        guild_status2 = M.gld_suggestions(guild_status2)
        local info2 = guild_status2[skill]

        if not info2 or not info2.recipes or #info2.recipes == 0 then
            util.msg_error("No suitable recipe found for task: " .. task)
            M.new_task(skill, cfg)
            return
        end

        local tracker = M.check_recipe({recipes = info2.recipes, reps = info2.reps or 1})
        if not tracker then
            M.new_task(skill, cfg)
            return
        end

        -- Acquire supplies
        local actions = require("actions")
        actions.get_supplies(tracker.buy, tracker.forage, tracker.kill_for, cfg, recipes_mod())

        -- Set up workshop
        M.get_cauldron()
        actions.go_empty_workshop()

        -- Execute recipe steps
        local steps = {}
        for _, s in ipairs(tracker.finish_steps) do steps[#steps+1] = s end
        for _ = 1, (info2.reps or 1) do
            task_module.do_steps(steps)
        end

        actions.cleanup(cfg)
        M.new_task(skill, cfg)

    else
        util.msg_error("Unhandled task: " .. task)
        util.msg("yellow", "Please complete this task manually and restart.")
    end
end

--------------------------------------------------------------------------------
-- new_task — pick the next skill to train and dispatch
--------------------------------------------------------------------------------

function M.new_task(skill, cfg)
    local guild_status = M.gld()

    -- Check if all skills mastered
    local all_mastered = true
    for _, stype in ipairs({"alchemy", "potions", "trinkets"}) do
        if guild_status[stype] and (guild_status[stype].rank or 0) < 63 then
            all_mastered = false; break
        end
    end
    if all_mastered then
        respond("[BlackArts] Congratulations! You are a master of alchemy, potions, and trinkets.")
        return
    end

    -- If no specific skill requested, pick lowest-rank from cfg.skill_types
    if not skill and cfg and cfg.skill_types then
        local min_rank = 999
        for _, stype in ipairs(cfg.skill_types) do
            if stype ~= "learn" and stype ~= "teach" then
                local rank = guild_status[stype] and (guild_status[stype].rank or 0) or 0
                if rank < min_rank then
                    min_rank = rank
                    skill = stype
                end
            end
        end
    end

    if not skill then
        util.msg("yellow", "No skills available for training. Check settings.")
        return
    end

    -- Once-and-done check
    if cfg and cfg.once_and_done then
        util.msg("yellow", "Task complete. Once-and-done mode. Exiting.")
        return
    end

    M.activity(guild_status, skill, cfg)
end

return M
