--- @module blackarts.tasks
-- Workshop crafting steps. Ported from BlackArts::Tasks (BlackArts.lic v3.12.x)

local state   = require("state")
local util    = require("util")
local inv     = require("inventory")

local M = {}

--------------------------------------------------------------------------------
-- do_steps_boil — loop until the contents reach a rolling boil
--------------------------------------------------------------------------------

function M.do_steps_boil()
    local BOIL_SUCCESS = Regex.new(
        "quickly flares up wildly, bringing the contents to a rolling boil"
    )
    local BOIL_RX = Regex.new(
        "flickers briefly, but then dies down" ..
        "|quickly flares up wildly, bringing the contents to a rolling boil"
    )
    while true do
        util.check_mana(10)
        local result = util.get_res("alchemy boil", BOIL_RX)
        util.wait_rt()
        if result and Regex.test(result, BOIL_SUCCESS) then break end
    end
end

--------------------------------------------------------------------------------
-- do_steps_channel — loop until spirit link formed
--------------------------------------------------------------------------------

function M.do_steps_channel()
    local CHAN_SUCCESS = Regex.new("^You focus .*? and link your spirit")
    local CHAN_RX = Regex.new(
        "^You focus .*? and link your spirit" ..
        "|^You attempt to channel"
    )
    while true do
        util.check_spirit()
        local result = util.get_res("alchemy channel", CHAN_RX)
        util.wait_rt()
        if result and Regex.test(result, CHAN_SUCCESS) then break end
    end
end

--------------------------------------------------------------------------------
-- do_steps_chant — loop until spell vanishes into solution
--------------------------------------------------------------------------------

function M.do_steps_chant(step)
    local CHANT_SUCCESS = Regex.new("vanish into the solution")
    local CHANT_RX = Regex.new("^You extend")
    while true do
        util.check_mana(40)
        local result = util.get_res("alchemy " .. step, CHANT_RX)
        util.wait_rt()
        if result and Regex.test(result, CHANT_SUCCESS) then break end
    end
end

--------------------------------------------------------------------------------
-- do_steps_simmer — loop until contents reach a slow simmer
--------------------------------------------------------------------------------

function M.do_steps_simmer()
    local SIMMER_SUCCESS = Regex.new(
        "quickly flares to life, bringing the contents to a slow simmer"
    )
    local SIMMER_RX = Regex.new(
        "flickers briefly, but then dies down" ..
        "|quickly flares to life, bringing the contents to a slow simmer"
    )
    while true do
        util.check_mana(10)
        local result = util.get_res("alchemy simmer", SIMMER_RX)
        util.wait_rt()
        if result and Regex.test(result, SIMMER_SUCCESS) then break end
    end
end

--------------------------------------------------------------------------------
-- do_steps_infuse — loop until thread fades naturally
--------------------------------------------------------------------------------

function M.do_steps_infuse()
    local INFUSE_SUCCESS = "The translucent thread fades away.  You feel slightly drained"
    while true do
        util.check_mana(10)
        util.get_res("alchemy infuse", Regex.new("^You focus"))
        local result = waitfor(
            "The translucent thread fades away.  You feel slightly drained from the ordeal.",
            "Your concentration lapses and the translucent thread connecting you to the solution fades away."
        )
        util.wait_rt()
        if result and result:find("slightly drained") then break end
    end
end

--------------------------------------------------------------------------------
-- do_steps_seal — seal the potion (requires empty flask if needed)
--------------------------------------------------------------------------------

function M.do_steps_seal()
    util.check_mana(20)
    if state.need_empty_flask and state.sacks["reagent"] then
        util.get_res(string.format("get empty flask from #%s", state.sacks["reagent"].id),
            state.get_regex or "You")
    end
    if state.cauldron then
        fput(string.format("look in #%s", state.cauldron.id))
    end
    util.get_res("alchemy seal", Regex.new("^You hold your hands over"))
    -- Wait for the ritual to complete
    local line
    repeat
        line = get()
    until line and (line:find("You sense that the ritual is complete") or
                    line:find("You sense something amiss with the solution"))
    util.wait_rt()
    require("actions").store_ingredient()
end

--------------------------------------------------------------------------------
-- do_steps_add — place an ingredient in the cauldron
--------------------------------------------------------------------------------

function M.do_steps_add(ingredient)
    if not ingredient or not ingredient.id then return end
    if not state.cauldron or not state.cauldron.id then return end
    util.get_res(string.format("put #%s in #%s", ingredient.id, state.cauldron.id),
        Regex.new("^You place|^You pour"))
    -- If an empty flask appeared in hand, store it
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    for _, hand in ipairs({rh, lh}) do
        if hand and hand.name == "empty flask" then
            if state.sacks["reagent"] then
                inv.store_item(state.sacks["reagent"], hand)
            end
            state.need_empty_flask = true
            break
        end
    end
end

--------------------------------------------------------------------------------
-- do_steps_grind — grind ingredient in mortar
--------------------------------------------------------------------------------

function M.do_steps_grind(ingredient)
    -- Get mortar (from hand or reagent sack)
    local mortar = nil
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    for _, hand in ipairs({rh, lh}) do
        if hand and hand.noun and hand.noun:find("mortar") then mortar = hand; break end
    end
    if not mortar and state.sacks["reagent"] and state.sacks["reagent"].contents then
        for _, item in ipairs(state.sacks["reagent"].contents) do
            if item.noun == "mortar" then mortar = item; break end
        end
    end
    if not mortar then
        util.msg_error("No mortar found. Please put a mortar in your reagent sack.")
        error("no mortar")
    end
    inv.drag(mortar)

    -- First grind checks for old-style mortar
    if state.mortar_check then
        local lines = util.get_lines("inspect #" .. mortar.id, "You carefully inspect|Inspecting that may not")
        for _, l in ipairs(lines) do
            if l:find("You carefully inspect") then
                util.msg("info", "Old-style mortar detected. Please 'tap mortar' then 'rub mortar' to convert it.")
                error("old style mortar")
            end
        end
        state.mortar_check = false
    end

    -- Place ingredient in mortar
    if ingredient and ingredient.id then
        util.get_res(string.format("put #%s in #%s", ingredient.id, mortar.id),
            state.put_regex or "You")
    end

    -- Grind until done
    while true do
        local result = util.get_res(
            "grind " .. (ingredient and ingredient.noun or "ingredient") .. " from my mortar",
            Regex.new("Roundtime|appears to be as ground as it'?s going to get|^Grind what|^With what do you intend to grind")
        )
        util.wait_rt()
        if result and result:find("as ground as it") then break end
        if result and result:find("^Grind what") then break end
        if result and result:find("^With what do you intend to grind") then
            -- Need pestle
            local pestle = nil
            if state.sacks["reagent"] and state.sacks["reagent"].contents then
                for _, item in ipairs(state.sacks["reagent"].contents) do
                    if item.noun == "pestle" then pestle = item; break end
                end
            end
            if not pestle then
                util.msg_error("Missing pestle.")
                error("no pestle")
            end
            util.get_res(string.format("_drag #%s #%s", pestle.id, mortar.id), state.put_regex or "You")
        end
    end

    -- Retrieve ground material from mortar
    if not mortar.contents then
        util.get_lines("look in #" .. mortar.id, "^In the .*? you see")
    end
    if mortar.contents then
        for _, item in ipairs(mortar.contents) do
            if item.noun ~= "pestle" and state.sacks["reagent"] then
                inv.store_item(state.sacks["reagent"], item)
            end
        end
    end
    -- Return mortar to sack
    if state.sacks["reagent"] then
        inv.store_item(state.sacks["reagent"], mortar)
    end
end

--------------------------------------------------------------------------------
-- do_steps_extract — extract reagent in workshop alembic
--------------------------------------------------------------------------------

function M.do_steps_extract()
    -- Ensure ingredient is in right hand
    local rh = GameObj.right_hand()
    if not (rh and rh.id) then
        fput("swap")
        util.wait_rt()
    end

    local return_room = nil
    if not util.is_workshop() then
        return_room = Room.id
        require("actions").go_empty_workshop()
    end

    util.check_mana(10)
    util.get_res("alchemy extract", Regex.new("^You carefully (?:pour|place)"))

    -- Wait for process to complete
    local done = false
    for _ = 1, 9000 do
        sleep(0.1)
        local line = get()
        if line and line:find("Sensing the process nearing its end") then
            done = true
            break
        end
    end
    util.wait_rt()
    require("actions").store_ingredient()

    if return_room then util.travel(return_room) end
    if not done then
        util.msg_error("Extract failed (game bug)")
        error("extract failed")
    end
end

--------------------------------------------------------------------------------
-- do_steps_distill — distill reagent using alembic
--------------------------------------------------------------------------------

function M.do_steps_distill()
    -- Ensure ingredient is in right hand
    local rh = GameObj.right_hand()
    if not (rh and rh.id) then
        fput("swap")
        util.wait_rt()
    end

    local return_room = nil
    if not util.is_workshop() then
        return_room = Room.id
        require("actions").go_empty_workshop()
    end

    util.get_res("alchemy distill", Regex.new("^You select an unused"))
    waitfor("Sensing the process nearing its end")
    util.wait_rt()
    require("actions").store_ingredient()

    if return_room then util.travel(return_room) end
end

--------------------------------------------------------------------------------
-- do_steps_separate — separate one item from a bundle
--------------------------------------------------------------------------------

function M.do_steps_separate()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local hand = (rh and rh.id) and rh or lh
    if hand and hand.noun then
        local noun = hand.noun:gsub("s$", "")
        util.get_res(string.format("get 1 %s from my %s", noun, hand.noun),
            Regex.new("^You separate"))
    end
    require("actions").store_ingredient()
end

--------------------------------------------------------------------------------
-- do_steps_refract — refract light through a lens in workshop
--------------------------------------------------------------------------------

function M.do_steps_refract(lens_name)
    -- Find lens in reagent sack
    local lens = nil
    if state.sacks["reagent"] and state.sacks["reagent"].contents then
        for _, item in ipairs(state.sacks["reagent"].contents) do
            if item.name == lens_name then lens = item; break end
        end
    end
    if not lens then
        util.msg_error("Failed to find lens '" .. lens_name .. "' in reagent sack")
        error("lens not found: " .. lens_name)
    end
    inv.drag(lens)
    util.get_res("alchemy refract",
        Regex.new("^The surface of the solution in .* shimmers in response!"))
    util.wait_rt()
    require("actions").store_ingredient()
end

--------------------------------------------------------------------------------
-- do_steps_special — collect sea water
--------------------------------------------------------------------------------

function M.do_steps_special()
    -- Find vial and flask for sea water collection
    local SEA_FLASK_RX = Regex.new(
        "^(?:small|small opaque|faceted) crystal flask$|^dark sphene-inset flask$"
    )
    local SEA_VIAL_RX = Regex.new(
        "^(?:clouded|warped|chipped|tapered|smoky|thick|slender|clear|blackened) glass vial$" ..
        "|^polished glaes vial$|^thin iron-encased vial$"
    )

    local vial, flask = nil, nil
    if state.sacks["reagent"] and state.sacks["reagent"].contents then
        for _, item in ipairs(state.sacks["reagent"].contents) do
            if not vial and Regex.test(item.name, SEA_VIAL_RX) then vial = item end
            if not flask and Regex.test(item.name, SEA_FLASK_RX) then flask = item end
        end
    end

    if not vial or not flask then
        util.msg_error("Cannot find vial or flask for sea water collection.")
        error("missing sea water containers")
    end

    -- Navigate to sea water collection point
    local sea_result = Map.find_nearest_by_tag("alchemy sea water")
    if not sea_result then
        util.msg_error("Cannot find a sea water collection point.")
        error("no sea water location")
    end

    local return_room = Room.id
    util.travel(sea_result.id)

    -- Fill vial
    inv.drag(vial)
    util.get_res("harvest water with #" .. vial.id,
        Regex.new("under water until it is filled|is already filled"))
    if state.sacks["reagent"] then inv.store_item(state.sacks["reagent"], vial) end

    -- Fill flask
    inv.drag(flask)
    util.get_res("harvest water with #" .. flask.id,
        Regex.new("under water until it is filled|is already filled"))
    if state.sacks["reagent"] then inv.store_item(state.sacks["reagent"], flask) end

    util.travel(return_room)
end

--------------------------------------------------------------------------------
-- do_steps_troll_blood — fill a vial with troll blood in a workshop
--------------------------------------------------------------------------------

function M.do_steps_troll_blood()
    -- The troll blood step requires a filled container (dark crimson fluid).
    -- The check happens in do_steps_light; if we reach here it means it's needed.
    util.msg("yellow", "Troll blood required — hunting for a troll...")
    local hunting = require("hunting")
    local room = hunting.hunting_areas("cave troll") or hunting.hunting_areas("hill troll")
    if room then
        util.travel(room)
        -- Signal bigshot to get troll blood (one kill)
        state.skin = "dark crimson"
        state.skin_number = 1
        state.creature = "cave troll"
        hunting.set_eval()
        Script.run("bigshot", {"bounty"})
    end
end

--------------------------------------------------------------------------------
-- do_steps_light — validate all ingredients are present, then light cauldron
--------------------------------------------------------------------------------

function M.do_steps_light(remaining_steps)
    state.need_empty_flask = false
    local error_flag = false
    local wait_spirit = false

    local temp_claimed = {}
    local temp_count   = {}
    for k, v in pairs(state.ingredient_count) do temp_count[k] = v end

    for _, sub_step in ipairs(remaining_steps) do
        if sub_step:find("troll blood") then
            -- handled by do_steps_troll_blood
        elseif sub_step:match("^add%s+(.*)") then
            local ingredient_name = sub_step:match("^add%s+(.*)")
            local guild = require("guild")
            local found, new_claimed, new_count =
                guild.check_ingredient(ingredient_name, temp_claimed, temp_count)
            temp_claimed = new_claimed
            temp_count = new_count
            if not found then
                util.msg_error("Missing ingredient: " .. ingredient_name)
                error_flag = true
                break
            end
        elseif sub_step == "channel" then
            wait_spirit = true
        elseif sub_step:match("^(?:buy|forage|kill)") then
            util.msg_error("Supply step reached during light: " .. sub_step)
        elseif sub_step == "seal" then
            break
        elseif sub_step:match("^refract (moonlight|sunlight)") then
            local light = sub_step:match("^refract (moonlight|sunlight)")
            if light == "sunlight" and util.is_moonlight() then
                util.msg_error("Missing sunlight for refract step")
                error_flag = true; break
            elseif light == "moonlight" and util.is_sunlight() then
                util.msg_error("Missing moonlight for refract step")
                error_flag = true; break
            end
            if not util.is_workshop() then
                state.start_room = Room.id
                require("actions").go_empty_workshop()
            end
        end
    end

    if error_flag then
        local guild = require("guild")
        guild.get_cauldron()
        error("missing ingredients for light step")
    end

    if wait_spirit then util.check_spirit() end

    -- Drop cauldron from personal carry and light it
    require("guild").drop_cauldron()
    util.check_mana(1)
    if state.cauldron then
        util.get_res(string.format("light #%s", state.cauldron.id),
            Regex.new("^You focus|^But that is already lit!"))
    end
end

--------------------------------------------------------------------------------
-- Main do_steps dispatcher
-- steps: array of step strings (mutated by shift)
-- single: if true, return after seal
--------------------------------------------------------------------------------

function M.do_steps(steps, single)
    util.eat_bread()
    util.sigil_concentration()
    inv.free_hands({ both = true })
    state.start_room = nil

    util.msg("debug", "Tasks.do_steps: all steps = " .. Json.encode(steps))

    local i = 1
    while i <= #steps do
        local step = steps[i]
        i = i + 1
        util.msg("debug", "Tasks.do_steps: step = " .. tostring(step))

        if step == "add troll blood" then
            M.do_steps_troll_blood()
        elseif step:match("^(add|grind|extract|distill|separate)%s+(.*)") then
            local action, ingredient_name = step:match("^(%w+)%s+(.*)")
            local ingredient = require("actions").get_ingredient(ingredient_name)
            if action == "add"      then M.do_steps_add(ingredient)
            elseif action == "grind"   then M.do_steps_grind(ingredient)
            elseif action == "extract" then M.do_steps_extract()
            elseif action == "distill" then M.do_steps_distill()
            elseif action == "separate" then M.do_steps_separate()
            end
        elseif step == "boil" then
            M.do_steps_boil()
        elseif step == "channel" then
            M.do_steps_channel()
        elseif step:match("^chant ") then
            M.do_steps_chant(step)
        elseif step:match("^infuse") then
            M.do_steps_infuse()
        elseif step == "light" then
            -- Pass remaining steps (from current index onward) for ingredient pre-check
            local rest = {}
            for j = i, #steps do rest[#rest+1] = steps[j] end
            M.do_steps_light(rest)
        elseif step:match("^refract (?:moonlight|sunlight) through (.* lens)$") then
            local lens_name = step:match("^refract (?:moonlight|sunlight) through (.* lens)$")
            M.do_steps_refract(lens_name)
        elseif step == "seal" then
            M.do_steps_seal()
            if single then return end
        elseif step == "simmer" then
            M.do_steps_simmer()
        elseif step == "special" then
            M.do_steps_special()
        elseif step == "check blood" then
            -- Validation only (handled in recursive_check_recipe)
        else
            util.msg_error("Unknown step: " .. tostring(step))
            error("unknown step: " .. tostring(step))
        end
    end

    if state.start_room then
        require("guild").get_cauldron()
        util.travel(state.start_room)
    end
end

--------------------------------------------------------------------------------
-- clean_equipment — clean the crucible in a workshop
--------------------------------------------------------------------------------

function M.clean_equipment()
    local location_list = util.find_workshops()
    local guild = require("guild")
    guild.get_cauldron()
    inv.free_hands({ both = true })
    go2(Char.prof:lower() .. " alchemy cleaning supplies")
    util.get_res("get rag", Regex.new("^You take"))

    local finished = false
    for _, ws in ipairs(location_list) do
        util.go2(ws.id)
        local result = util.get_res("clean crucible",
            Regex.new("You have|Perhaps you should check another workshop"))
        util.wait_rt()
        if result and result:find("You have completed") then
            finished = true
            break
        end
    end

    util.wait_rt()
    util.get_res("drop rag", state.put_regex or "You")

    if not finished then
        util.find_next_guild()
        M.clean_equipment()
    end

    state.visited_towns = {state.start_town}
    if state.current_admin then util.travel(state.current_admin) end
end

--------------------------------------------------------------------------------
-- sweep_labs — sweep the alchemy labs
--------------------------------------------------------------------------------

function M.sweep_labs()
    local location_list = util.find_workshops()
    local guild = require("guild")
    guild.get_cauldron()
    inv.free_hands({ both = true })

    local SWEEP_RX = Regex.new("already clean|You sweep|you manage to")
    local finished = false
    for _, ws in ipairs(location_list) do
        util.go2(ws.id)
        local result = util.get_res("sweep", SWEEP_RX)
        util.wait_rt()
        if result and result:find("You sweep") then
            finished = true
            break
        end
    end

    if not finished then
        util.find_next_guild()
        M.sweep_labs()
    end

    state.visited_towns = {state.start_town}
    if state.current_admin then util.travel(state.current_admin) end
end

--------------------------------------------------------------------------------
-- polish_lens — polish the tarnished lens
--------------------------------------------------------------------------------

function M.polish_lens()
    local location_list = util.find_workshops()
    local guild = require("guild")
    guild.get_cauldron()
    inv.free_hands({ both = true })

    local POLISH_RX = Regex.new("You polish|already been polished|gleams brightly")
    local finished = false
    for _, ws in ipairs(location_list) do
        util.go2(ws.id)
        local result = util.get_res("polish lens", POLISH_RX)
        util.wait_rt()
        if result and result:find("You polish") then
            finished = true
            break
        end
    end

    if not finished then
        util.find_next_guild()
        M.polish_lens()
    end

    state.visited_towns = {state.start_town}
    if state.current_admin then util.travel(state.current_admin) end
end

--------------------------------------------------------------------------------
-- distill_water — distill pure water in alembic (guild task)
--------------------------------------------------------------------------------

function M.distill_water()
    local guild = require("guild")
    guild.get_cauldron()
    inv.free_hands({ both = true })
    require("actions").go_empty_workshop()

    while true do
        util.get_res("pour alembic", Regex.new("^You collect"))
        util.wait_rt()
        util.get_res("light alembic", Regex.new("^You focus"))
        waitfor("pressure within it builds")
        util.get_res("turn alembic", Regex.new("^Turning a mithril lever"))
        waitfor("pressure within it builds")
        util.get_res("turn alembic", Regex.new("^Turning a mithril lever"))
        waitfor("the flame beneath it suddenly dies down")
        util.get_res("clean alembic", Regex.new("^Using a barrel of water"))
        util.wait_rt()
        util.get_res("get alembic", Regex.new("^Having cleaned the"))
        local line = waitfor("You have")
        util.wait_rt()
        if line == "[You have completed your training task.]" then break end
    end
end

--------------------------------------------------------------------------------
-- do_task_reps — repeat a task-step action for N reps
--------------------------------------------------------------------------------

function M.do_task_reps(action_fn, guild_module, skill)
    while true do
        util.wait_rt()
        action_fn()
        local status = guild_module.gld()
        if not status or not status[skill] then break end
        if (status[skill].reps or 0) == 0 then break end
    end
end

return M
