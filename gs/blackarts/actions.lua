--- @module blackarts.actions
-- Ingredient acquisition and cleanup. Ported from BlackArts::Actions (BlackArts.lic v3.12.x)

local state   = require("state")
local util    = require("util")
local inv     = require("inventory")

local M = {}

-- Herb bundle list (for cleanup sorting into herb sack)
local HERB_NAMES = {
    "some torban leaf", "some basal moss", "some acantha leaf",
    "some ambrominas leaf", "some cactacae spine", "some aloeas stem",
    "some haphip root", "some pothinir grass", "some ephlox moss",
    "some calamia fruit", "some sovyn clove", "some wolifrew lichen",
    "some woth flower",
}

local HERB_SET = {}
for _, h in ipairs(HERB_NAMES) do HERB_SET[h] = true end

--------------------------------------------------------------------------------
-- Store whatever ingredient ended up in hand after a crafting step
--------------------------------------------------------------------------------

function M.store_ingredient()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    for _, hand in ipairs({rh, lh}) do
        if hand and hand.id then
            -- Try reagent sack first, then default
            local target = state.sacks["reagent"] or state.sacks["default"]
            if target then
                inv.store_item(target, hand)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Navigate to an empty workshop
--------------------------------------------------------------------------------

function M.go_empty_workshop()
    local workshops = util.find_workshops()
    for _, ws in ipairs(workshops) do
        util.travel(ws.id)
        -- Check for an available cauldron
        local cauldron = nil
        for _, obj in ipairs(GameObj.room_desc()) do
            if obj.noun and (obj.noun == "cauldron" or obj.noun == "vat" or
                             obj.noun == "kettle" or obj.noun == "boiler") then
                cauldron = obj
                break
            end
        end
        if not cauldron then
            for _, obj in ipairs(GameObj.loot()) do
                if obj.noun and (obj.noun == "cauldron" or obj.noun == "vat" or
                                 obj.noun == "kettle" or obj.noun == "boiler") then
                    cauldron = obj
                    break
                end
            end
        end
        if cauldron then
            state.cauldron = cauldron
            return
        end
    end
    util.msg_error("No available cauldron found in any workshop.")
    error("no empty workshop")
end

--------------------------------------------------------------------------------
-- Buy ingredients from shop(s)
-- shopping_list: {[room_id] = {[item_name] = count, ...}, ...}
--------------------------------------------------------------------------------

function M.buy(shopping_list, recipes_mod)
    util.msg("debug", "Actions.buy: shopping_list = " .. Json.encode(shopping_list))

    -- Open all sacks
    for _, stype in ipairs({"herb", "reagent", "default"}) do
        inv.open_single_container(stype)
    end

    util.get_note()
    inv.free_hands({ both = true })

    for room_id, items in pairs(shopping_list) do
        util.travel(tonumber(room_id))

        local menu = util.read_menu()
        util.get_note()
        if state.note then inv.drag(state.note) end
        util.travel(tonumber(room_id))

        for item_name, num in pairs(items) do
            -- Check equivalents
            local order_name = item_name
            if recipes_mod then
                local equivs = recipes_mod.alchemy_equivalents
                for _, group in ipairs(equivs) do
                    local in_group = false
                    for _, e in ipairs(group) do
                        if e == item_name then in_group = true; break end
                    end
                    if in_group then
                        for _, e in ipairs(group) do
                            if menu[e] then order_name = e; break end
                        end
                        break
                    end
                end
            end

            local order_num = menu[order_name]
            if not order_num then
                util.msg_error("Failed to find '" .. order_name .. "' on menu")
                error("item not on menu: " .. order_name)
            end

            -- Buy in batches of 10
            local remaining = num
            while remaining > 0 do
                local batch = math.min(remaining, 10)
                remaining = remaining - batch

                util.get_res("order " .. batch .. " of " .. order_num, "BUY")
                local result = fput("buy")
                if result and result:lower():find("do not have enough") then
                    if util.cfg and util.cfg.no_bank then
                        util.msg_error("Insufficient funds.")
                        error("insufficient funds")
                    else
                        util.silver_deposit()
                        util.get_note(true)
                        util.travel(tonumber(room_id))
                        inv.free_hands({ both = true })
                        if state.note then inv.drag(state.note) end
                        util.get_res("order " .. batch .. " of " .. order_num, "BUY")
                        fput("buy")
                    end
                end

                -- Wait for item to appear in hand
                local bought = nil
                for _ = 1, 20 do
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    for _, hand in ipairs({rh, lh}) do
                        if hand and hand.id and hand.name and
                           not hand.name:find("Empty") and
                           not hand.name:find("note") and
                           not hand.name:find("scrip") and
                           not hand.name:find("chit") then
                            bought = hand
                            break
                        end
                    end
                    if bought then break end
                    sleep(0.1)
                end

                if bought then
                    if bought.name and bought.name:find("package") then
                        util.get_res("open my package", "^You open|^That is already open")
                        util.get_res(string.format("empty my package in #%s",
                            state.sacks["default"].id), "everything falls in")
                        util.get_res("throw my package", "^You throw away")
                    else
                        inv.store_item(state.sacks["default"], bought)
                    end
                end
            end
        end

        -- Put the note away
        if state.note then inv.single_drag(state.note) end
    end
end

--------------------------------------------------------------------------------
-- Buy elusive reagents from the floating reagent shop table
--------------------------------------------------------------------------------

function M.buy_elusive(buy_only)
    if not (util.cfg and util.cfg.buy_reagents) then return end

    if not buy_only then
        -- ensure cauldron is handled (called separately)
    end

    if not UserVars.needed_reagents or UserVars.needed_reagents == "" then return end

    go2("town")
    util.get_note()
    inv.free_hands({ both = true })
    go2("reagent shop")

    -- Find the shop table
    local table_obj = nil
    for _, obj in ipairs(GameObj.loot()) do
        if obj.noun == "table" then table_obj = obj; break end
    end
    for _, obj in ipairs(GameObj.room_desc()) do
        if obj.noun == "table" then table_obj = obj; break end
    end

    local count = {}
    local keep_looking = true

    while keep_looking do
        -- Get table contents via look
        local table_contents = {}
        if table_obj then
            local lines = util.get_lines("look on #" .. table_obj.id, "^On the|There is nothing")
            for _, line in ipairs(lines) do
                local id, noun, name = line:match('<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>')
                if id and noun and name then
                    table_contents[#table_contents + 1] = {id=id, noun=noun, name=name}
                end
            end
        end

        local look_again = false
        local needed_rx = Regex.new(UserVars.needed_reagents)

        local matching = {}
        for _, obj in ipairs(table_contents) do
            if Regex.test(obj.name, needed_rx) then
                matching[#matching + 1] = obj
            end
        end

        if #matching > 0 then
            inv.free_hands({ both = true })
            if state.note then inv.drag(state.note) end

            for _, obj in ipairs(matching) do
                count[obj.name] = count[obj.name] or 0
                -- Count current stock
                if count[obj.name] == 0 then
                    for _, s in ipairs(inv.all_sack_contents()) do
                        if s.name == obj.name then count[obj.name] = count[obj.name] + 1 end
                    end
                    -- Also count jar doses
                    for _, s in ipairs(inv.all_sack_contents()) do
                        if s.after_name and s.after_name:find(obj.name, 1, true) then
                            count[obj.name] = count[obj.name] + util.jar_count(s)
                        end
                    end
                end

                if count[obj.name] < 20 then
                    count[obj.name] = count[obj.name] + 1
                    if GameState.invisible then fput("unhide") end

                    local result = fput("buy #" .. obj.id)
                    if result and result:lower():find("do not have enough") then
                        if util.cfg and util.cfg.no_bank then
                            util.msg_error("Insufficient funds.")
                            error("insufficient funds")
                        else
                            util.silver_deposit()
                            util.get_note(true)
                            go2("reagent shop")
                            M.buy_elusive(true)
                            return
                        end
                    end

                    -- Get item from hand
                    local bought = nil
                    for _ = 1, 20 do
                        local rh = GameObj.right_hand()
                        local lh = GameObj.left_hand()
                        for _, hand in ipairs({rh, lh}) do
                            if hand and hand.id and hand.name and
                               not hand.name:find("Empty") and
                               not hand.name:find("note") and
                               not hand.name:find("scrip") then
                                bought = hand; break
                            end
                        end
                        if bought then break end
                        sleep(0.1)
                    end
                    if bought and state.sacks["reagent"] then
                        inv.store_item(state.sacks["reagent"], bought)
                    end
                    look_again = true
                end
            end

            if state.note then inv.single_drag(state.note) end
            sleep(0.05)
            M.top_off_jars()
        end

        keep_looking = look_again
    end

    state.last_alchemy_buy = os.time()
end

--------------------------------------------------------------------------------
-- Top off partially-used jars from loose reagents in default/reagent sack
--------------------------------------------------------------------------------

function M.top_off_jars()
    -- This is handled automatically by the game's alchemy system.
    -- Placeholder for explicit jar-filling logic if needed.
end

--------------------------------------------------------------------------------
-- Forage for herbs
-- forage_list: {[herb_name] = count, ...}
--------------------------------------------------------------------------------

function M.forage(forage_list, cfg)
    local hunting = require("hunting")

    for herb, num in pairs(forage_list) do
        local location_list = M.forage_find(herb)
        if not location_list or #location_list == 0 then
            util.msg_error("Failed to find a foraging location for: " .. herb)
            error("no forage location for: " .. herb)
        end

        local herb_base = herb:gsub("^some ", "")
        local forage_item = util.fix_forage_name(herb_base)
        local found_count = 0

        hunting.pre_hunt(cfg)
        util.wait_rt()

        if not GameState.stance or GameState.stance ~= "defensive" then
            fput("stance defensive")
        end

        util.mapped_room()

        for _, room_id in ipairs(location_list) do
            util.travel(room_id)
            util.wait_rt()

            -- Check if room is in no-forage list
            local no_forage = false
            for _, nf in ipairs(state.no_forage) do
                if nf == room_id then no_forage = true; break end
            end
            if no_forage then goto continue end

            -- Skip if monsters present and "run" option not set
            local has_targets = #GameObj.targets() > 0
            if has_targets and cfg and cfg.forage_options and
               not (function()
                   for _, v in ipairs(cfg.forage_options) do
                       if v == "run" then return true end
                   end
                   return false
               end)() then
                goto continue
            end

            while found_count < num do
                -- Cast helper spells if configured
                if cfg then
                    local opts = cfg.forage_options or {}
                    local function has_opt(o)
                        for _, v in ipairs(opts) do if v == o then return true end end
                        return false
                    end

                    -- Spell 919 (Floating Disk — provides foraging bonus)
                    if has_opt("use_919") and not Effects.Buffs.active(919) and
                       not Effects.Cooldowns.active(919) then
                        util.cast_spell(919)
                    end
                    -- Spell 140 (Haste)
                    if has_opt("use_140") and not Effects.Buffs.active(140) and
                       not Effects.Cooldowns.active(140) then
                        util.cast_spell(140)
                    end
                    -- Spell 709 (WoT — clear limbs)
                    local has_limbs = false
                    for _, npc in ipairs(GameObj.npcs()) do
                        if npc.name and npc.name:match("^(?:arm|appendage|claw|limb|pincer|tentacle)s?$") then
                            has_limbs = true; break
                        end
                    end
                    if has_opt("use_709") and not has_limbs and #GameObj.targets() > 0 then
                        util.cast_spell(709)
                    end
                    -- Spell 213 (Cleric sense — find herbs)
                    if has_opt("use_213") and (Char.prof == "Cleric" or Char.prof == "Empath") then
                        if not util.in_town(room_id) then
                            local sense_lines = util.get_lines("sense", "You open your soul to the lesser")
                            local nothing = false
                            for _, l in ipairs(sense_lines) do
                                if l:find("Nothing stands out to you") then nothing = true; break end
                            end
                            if nothing then util.cast_spell(213) end
                        end
                    end
                end

                -- Kneel for foraging bonus (outside town)
                if not util.in_town(room_id) and GameState.standing then
                    fput("kneel")
                    sleep(0.2)
                end

                util.check_mana(1)
                util.wait_rt()

                local FORAGE_RX = Regex.new(
                    "^You forage" ..
                    "|^You make so much noise" ..
                    "|^You stumble about in a fruitless" ..
                    "|you are unable to find anything useful" ..
                    "|^As you carefully forage around you" ..
                    "|^You begin to forage around when your hand" ..
                    "|^As you forage around you suddenly feel" ..
                    "|^You begin to forage around when suddenly" ..
                    "|^You fumble about so badly"
                )

                local result = dothistimeout("forage " .. forage_item, 8, FORAGE_RX)
                util.wait_rt()

                if result and result:find("^You forage") then
                    -- Extract found item
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    local found_item = nil
                    for _, hand in ipairs({rh, lh}) do
                        if hand and hand.id then found_item = hand; break end
                    end
                    if found_item then
                        -- Bundle or store
                        if HERB_SET[found_item.name] then
                            -- Try to bundle
                            local bundle = nil
                            for _, s in ipairs(inv.all_sack_contents()) do
                                if s.name == found_item.name then bundle = s; break end
                            end
                            if bundle then
                                inv.drag(bundle)
                            end
                            local bundle_res = dothistimeout("bundle", 3,
                                Regex.new("^Carefully, you combine|^If you add anything more|^You do not have anything to bundle"))
                            if bundle_res and bundle_res:find("If you add anything more") then
                                -- Bundle full, store new item
                                inv.store_item(state.sacks["herb"] or state.sacks["default"], found_item)
                            else
                                inv.store_item(state.sacks["herb"] or state.sacks["default"],
                                    GameObj.right_hand() or GameObj.left_hand())
                            end
                        else
                            inv.store_item(state.sacks["herb"] or state.sacks["default"], found_item)
                        end
                        found_count = found_count + 1
                        if found_count >= num then break end
                    end
                end

                -- Check for foraging injury
                if result then
                    local INJURY_RX = Regex.new(
                        "^You begin to forage around when your hand comes into contact with something that stabs" ..
                        "|^As you forage around you suddenly feel a sharp pain" ..
                        "|suddenly you feel a burning sensation in your hand"
                    )
                    if Regex.test(result, INJURY_RX) then
                        util.msg("yellow", "Foraging injury! Waiting for round time.")
                        util.wait_rt()
                        -- Stand if kneeling
                        if not GameState.standing then fput("stand") end
                    end
                end

                -- Stand back up
                if not GameState.standing then
                    fput("stand")
                    sleep(0.2)
                end
            end

            if found_count >= num then break end
            ::continue::
        end

        hunting.post_hunt(cfg)
    end
end

--------------------------------------------------------------------------------
-- Find foraging locations for a herb name
-- Returns a list of room IDs sorted by travel cost
--------------------------------------------------------------------------------

function M.forage_find(herb)
    local herb_base = herb:gsub("^some ", "")
    local results = Map.find_all_nearest_by_tag(herb_base)
    if not results or #results == 0 then
        -- Try the fix_forage_name variant
        local fixed = util.fix_forage_name(herb_base)
        results = Map.find_all_nearest_by_tag(fixed)
    end
    if not results then results = {} end

    -- Filter out no-forage rooms and boundary-crossing rooms
    local filtered = {}
    for _, r in ipairs(results) do
        local no_forage = false
        for _, nf in ipairs(state.no_forage) do
            if nf == r.id then no_forage = true; break end
        end
        if not no_forage then
            local in_boundary = false
            for _, fence in ipairs(state.boundaries) do
                if r.id == fence then in_boundary = true; break end
            end
            if not in_boundary then
                filtered[#filtered + 1] = r.id
            end
        end
    end

    return filtered
end

--------------------------------------------------------------------------------
-- Get a specific ingredient from inventory (dragging to hand)
--------------------------------------------------------------------------------

function M.get_ingredient(ingredient_name)
    -- Search all sacks for the ingredient
    for _, item in ipairs(inv.all_sack_contents()) do
        if item.name == ingredient_name or
           (item.name and item.name:find(ingredient_name, 1, true)) then
            inv.drag(item)
            return item
        end
    end
    util.msg_error("Could not find ingredient: " .. ingredient_name)
    error("ingredient not found: " .. ingredient_name)
end

--------------------------------------------------------------------------------
-- Get supplies needed for upcoming recipes
-- shopping_list: {[shop_room_id] = {[item] = count}, ...}
-- forage_list:   {[herb] = count}
-- kill_list:     {[creature] = {[skin] = count}}
--------------------------------------------------------------------------------

function M.get_supplies(shopping_list, forage_list, kill_list, cfg, recipes_mod)
    util.msg("debug", "Actions.get_supplies: starting supply run")

    -- Kill first (most time-consuming)
    if kill_list then
        for creature, skins in pairs(kill_list) do
            for skin, _ in pairs(skins) do
                state.skin     = skin
                state.creature = creature
                local room = require("hunting").hunting_areas(creature)
                if room then
                    util.travel(room)
                    require("hunting").switch_profile(skin, cfg)
                    require("hunting").go_hunting(cfg)
                end
            end
        end
    end

    -- Forage
    if forage_list and next(forage_list) then
        M.forage(forage_list, cfg)
    end

    -- Buy
    if shopping_list and next(shopping_list) then
        M.buy(shopping_list, recipes_mod)
    end
end

--------------------------------------------------------------------------------
-- Cleanup: bundle herbs, trash items, sort reagents, sell consignment, deposit
--------------------------------------------------------------------------------

function M.cleanup(cfg)
    util.msg("debug", "Actions.cleanup: starting")
    inv.free_hands({ both = true })

    -- Bundle herbs from default/reagent bags into herb sack
    local to_check = inv.bags_to_check()
    if to_check then
        for _, item in ipairs(to_check) do
            if HERB_SET[item.name] then
                -- Find existing bundle
                local bundle = nil
                if state.sacks["herb"] and state.sacks["herb"].contents then
                    for _, s in ipairs(state.sacks["herb"].contents) do
                        if s.name == item.name then bundle = s; break end
                    end
                end
                if bundle then
                    util.get_res("get #" .. bundle.id, state.get_regex or "You")
                end
                local herb = item
                util.get_res("get #" .. herb.id, state.get_regex or "You")
                dothistimeout("bundle", 3, Regex.new("^Carefully|^If you add|^You do not have"))
                -- Store result
                local result_item = GameObj.right_hand() or GameObj.left_hand()
                if result_item and result_item.id then
                    inv.store_item(state.sacks["herb"] or state.sacks["default"], result_item)
                end
            end
        end
    end

    -- Trash listed items
    if cfg and cfg.trash and #cfg.trash > 0 then
        local trash_rx = table.concat(cfg.trash, "|")
        local trash_can = nil
        for _, item in ipairs(inv.all_sack_contents()) do
            if item.name and Regex.test(item.name, Regex.new(trash_rx)) then
                if not trash_can then
                    trash_can = util.find_trash()
                    if not trash_can then
                        go2("locksmith pool")
                        trash_can = util.find_trash()
                    end
                end
                if trash_can then
                    inv.drag(item)
                    fput(string.format("put #%s in #%s", item.id, trash_can.id))
                    sleep(0.2)
                end
            end
        end
    end

    -- Move herbs and reagents to proper sacks
    if state.sacks["default"] and state.sacks["default"].contents then
        for _, item in ipairs(state.sacks["default"].contents) do
            if item.type and item.type:find("herb") then
                if state.sacks["herb"] and state.sacks["herb"].id ~= state.sacks["default"].id then
                    inv.drag(item)
                    inv.store_item(state.sacks["herb"], item)
                end
            elseif item.type and item.type:find("reagent") then
                if state.sacks["reagent"] and state.sacks["reagent"].id ~= state.sacks["default"].id then
                    inv.drag(item)
                    inv.store_item(state.sacks["reagent"], item)
                end
            end
        end
    end

    -- Buy elusive reagents if it's been more than 10 minutes
    if (os.time() - (state.last_alchemy_buy or 0)) > 600 then
        M.buy_elusive()
    else
        M.top_off_jars()
    end

    -- Sell consignment items
    if cfg and cfg.sell_consignment and cfg.consignment_include and #cfg.consignment_include > 0 then
        local sell_rx = table.concat(cfg.consignment_include, "|")
        local to_sell = {}
        for _, item in ipairs(inv.all_sack_contents()) do
            if item.name and Regex.test(item.name, Regex.new(sell_rx)) then
                to_sell[#to_sell + 1] = item
            end
        end
        if #to_sell > 0 then
            go2("consignment")
            for _, item in ipairs(to_sell) do
                util.sell_item(item)
            end
        end
    end

    -- Run eloot to sell alchemy drops
    if not (cfg and cfg.no_bank) then
        Script.run("eloot", {"sell", "alchemy_mode"})
    end

    -- Deposit silver
    util.silver_deposit()
end

return M
