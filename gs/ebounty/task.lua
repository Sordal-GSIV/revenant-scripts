local data = require("data")
local settings_mod = require("settings")
local util = require("util")
local hunting = require("hunting")

local M = {}

M.bounty_check = nil

--------------------------------------------------------------------------------
-- NPC Finding
--------------------------------------------------------------------------------

function M.find_npc(patterns)
    for attempt = 1, 5 do
        local all = {}
        for _, obj in ipairs(GameObj.room_desc() or {}) do all[#all + 1] = obj end
        for _, obj in ipairs(GameObj.npcs() or {}) do all[#all + 1] = obj end
        for _, npc in ipairs(all) do
            if data.matches_any(npc.name, patterns) then return npc end
        end
        if attempt > 1 then util.msg("yellow", "Trying to detect NPC (attempt " .. attempt .. ")") end
        util.wait_rt()
    end
    util.msg("yellow", "NPC not found after 5 attempts.")
    return nil
end

function M.find_taskmaster()
    local room = Room.current()
    local at_guild = false
    if room and room.tags then
        for _, tag in ipairs(room.tags) do
            if tag == "advguild" then at_guild = true; break end
        end
    end
    if not at_guild then util.go2("advguild"); util.wait_rt(); room = Room.current() end

    local current_id = Map.current_room()
    if room and room.uid and tostring(room.uid) == "7503207" then return "Halfwhistle" end

    local is_sg = false
    for _, sg in ipairs(data.sailors_grief_rooms) do
        if current_id == sg then is_sg = true; break end
    end
    if not is_sg then return "Taskmaster" end

    for _, npc in ipairs(GameObj.npcs()) do
        if npc.name:find("Seldit") then return "Seldit" end
    end
    for _ = 1, 3 do
        for _, spot in ipairs(data.sailors_grief_rooms) do
            util.go2("u" .. spot)
            for _, npc in ipairs(GameObj.npcs()) do
                if npc.name:find("Seldit") then return "Seldit" end
            end
        end
    end
    util.msg("yellow", "Could not find Seldit")
    return "Taskmaster"
end

function M.ask_taskmaster(action_type)
    util.msg("debug", "ask_taskmaster: " .. action_type)
    local st = util.state.settings
    local command, ask_count = "bounty", 1

    if action_type == "get" then
        local boost = ""
        if (st.boost_type or "") ~= "" and st.boost_type ~= "Any" then
            boost = " " .. st.boost_type
        end
        command = "bounty" .. boost
    elseif action_type == "remove" then command = "removal"; ask_count = 2
    elseif action_type == "expedite" then command = "expediting"; ask_count = 2
    end

    local original = Bounty.task or ""
    for attempt = 1, 5 do
        local npc = M.find_taskmaster()
        for _ = 1, ask_count do
            put("ask " .. npc .. " about " .. command)
            local result = matchtimeout(5,
                "Who are you trying to ask", "You have already been assigned",
                "I'm ready to assign you a new task", "Come back in about",
                "I have removed you from your current assignment",
                "The local gem dealer", "The local furrier",
                "It appears they have", "It appears that a local",
                "suppress bandit", "particularly dangerous",
                "SEARCH the area", "LOOT the item",
                "The local healer", "The local herbalist",
                "It appears they need your help"
            )
            if result and result:find("Who are you trying to ask") then
                npc = M.find_taskmaster()
            elseif result and result:find("You have already been assigned") then return
            elseif result and result:find("I'm ready to assign") and action_type == "expedite" then return
            end
            util.wait_rt()
        end
        if util.bounty_change(original) then return end
        util.msg("yellow", "Bounty did not change, retrying (" .. attempt .. ")")
    end
    util.msg("error", "Bounty did not change after 5 attempts")
end

function M.ask_assignment(npc_type)
    util.msg("debug", "ask_assignment: " .. npc_type)
    local patterns, dest
    if npc_type == "furrier" then patterns, dest = data.furrier_patterns, "furrier"
    elseif npc_type == "herbalist" then patterns, dest = data.herbalist_patterns, "herbalist"
    elseif npc_type == "jeweler" then patterns, dest = data.jeweler_patterns, "gemshop"
    end
    util.go2(dest); util.wait_rt()

    local original = Bounty.task or ""
    for attempt = 1, 5 do
        local npc = M.find_npc(patterns)
        if not npc then util.msg("error", "Could not find " .. npc_type); return end
        fput("ask #" .. npc.id .. " about bounty")
        if util.bounty_change(original) then return end
        util.msg("yellow", "Bounty did not change, retrying (" .. attempt .. ")")
        util.wait_rt()
    end
end

--------------------------------------------------------------------------------
-- Guard Interaction
--------------------------------------------------------------------------------

function M.guard_list()
    local guard_rooms = Map.tags("advguard") or {}
    if #guard_rooms == 0 then return {} end
    local current = Map.current_room()
    local with_dist = {}
    for _, rid in ipairs(guard_rooms) do
        local path = Map.find_path(current, rid)
        if path then with_dist[#with_dist + 1] = {id = rid, dist = #path} end
    end
    table.sort(with_dist, function(a, b) return a.dist < b.dist end)
    local result = {}
    for _, r in ipairs(with_dist) do result[#result + 1] = r.id end
    return result
end

function M.ask_guard()
    util.msg("debug", "ask_guard")
    local original = Bounty.task or ""
    local guards = M.guard_list()

    if #guards == 0 then
        util.go2("advguard")
        guards = {Map.current_room()}
    end

    for _, guard_room in ipairs(guards) do
        util.go2(guard_room); util.wait_rt()
        local all = {}
        for _, obj in ipairs(GameObj.room_desc() or {}) do all[#all + 1] = obj end
        for _, obj in ipairs(GameObj.npcs() or {}) do all[#all + 1] = obj end

        for _, npc in ipairs(all) do
            if data.matches_any(npc.name, data.guard_patterns) then
                put("ask " .. npc.noun .. " about bounty")
                local result = matchtimeout(5,
                    "suppress bandit", "particularly dangerous",
                    "SEARCH the area", "LOOT the item",
                    "I don't have any tasks", "Try bugging me later",
                    "Ah, so you have returned", "You have completed",
                    "cull their numbers"
                )

                if result and result:find("Ah, so you have returned") then
                    local info = Bounty.parse()
                    if info and info.item then
                        local containers = GameObj.inv() or {}
                        for _, bag in ipairs(containers) do
                            fput("get " .. info.item .. " from #" .. bag.id)
                            pause(0.3)
                            local rh = GameObj.right_hand()
                            if rh and rh.name:find(info.item) then
                                fput("give " .. npc.noun)
                                break
                            end
                        end
                    end
                end

                if util.bounty_change(original) then return end

                if result and (result:find("I don't have any tasks")
                    or result:find("Try bugging me later")) then
                    goto next_guard
                end
            end
        end
        ::next_guard::
    end
end

--------------------------------------------------------------------------------
-- Profile Switching
--------------------------------------------------------------------------------

function M.switch_profile(creature)
    util.msg("debug", "switch_profile: " .. tostring(creature))
    util.state.creature = creature
    local st = util.state.settings

    for _, letter in ipairs({"a","b","c","d","e","f","g","h","i","j"}) do
        local names = st["names_" .. letter] or ""
        if creature and names ~= "" and names:lower():find(creature:lower()) then
            util.state.only_required = st["kill_" .. letter] or false
            return true
        end
    end
    if creature == "bandits" and (st.bandits_profile or "") ~= "" then
        util.state.only_required = st.kill_bandits or false
        return true
    end
    if st.keep_hunting then
        util.msg("yellow", "No Profile for " .. tostring(creature) .. " — keep_hunting active")
        hunting.keep_hunting()
        return false
    else
        util.go2_rest()
        util.msg("info", "No Profile for " .. tostring(creature) .. ". Check Profiles tab.")
        return false
    end
end

--------------------------------------------------------------------------------
-- Boost / Voucher / Removal Checks
--------------------------------------------------------------------------------

function M.check_boost()
    put("boost info")
    local result = matchtimeout(5, "Bounty Boost", "You do not have", "What was that")
    if result and result:find("Bounty Boost") then return true end
    return false
end

function M.check_voucher()
    put("bounty")
    local result = matchtimeout(5, "expedited task reassignment", "You are not currently",
        "You have been tasked", "You were tasked", "Your current task")
    if result and result:find("expedited") then return true end
    return false
end

function M.check_removal()
    local st = util.state.settings
    local info = Bounty.parse()
    if not info or info.type == "none" then return false end

    local function check_excl(field, excl_key)
        if not info[field] or #(st[excl_key] or {}) == 0 then return false end
        for _, exc in ipairs(st[excl_key]) do
            if info[field]:lower():find(exc:lower()) then
                util.msg("info", info[field] .. " is excluded. Removing!")
                return true
            end
        end
        return false
    end

    if check_excl("creature", "creature_exclude") then return true end
    if check_excl("herb", "herb_exclude") then return true end
    if check_excl("gem", "gem_exclude") then return true end
    if check_excl("area", "location_exclude") then return true end

    local cw = data.crosswalk[info.type]
    if cw then
        for _, r in ipairs(settings_mod.build_reject_list(st)) do
            if r == cw then return true end
        end
    end

    if info.type == "heirloom" then
        if info.action == "search" and not settings_mod.list_contains(st.bounty_types, "heirloom_search") then return true end
        if info.action == "loot" and not settings_mod.list_contains(st.bounty_types, "heirloom_loot") then return true end
    end

    return false
end

--------------------------------------------------------------------------------
-- Bounty Task Details
--------------------------------------------------------------------------------

function M.fetch_bounty_details(info)
    if not info then return end
    local bt = info.type or ""
    if bt == "gem_assignment" then M.ask_assignment("jeweler")
    elseif bt == "skin_assignment" then M.ask_assignment("furrier")
    elseif bt == "herb_assignment" then M.ask_assignment("herbalist")
    elseif bt:find("assignment") or bt == "guard" then M.ask_guard()
    end
end

--------------------------------------------------------------------------------
-- Bounty Handlers
--------------------------------------------------------------------------------

function M.bounty_get()
    M.ask_taskmaster("get")
end

function M.bounty_remove(just_remove)
    M.ask_taskmaster("remove")
    if just_remove then return end
    if util.state.settings.use_vouchers then M.ask_taskmaster("expedite") end
end

function M.bounty_complete()
    local st = util.state.settings

    if GameState.mind == "saturated" then
        util.go2_rest()
        if st.basic or st.once_and_done then return end
    end
    while GameState.mind == "saturated" do
        if st.basic or st.once_and_done then return end
        pause(0.5)
        if st.keep_hunting then hunting.keep_hunting() end
    end

    M.ask_taskmaster("turn-in")

    if st.basic then
        util.silver_deposit()
        if st.once_and_done then
            M.get_new_bounty_before_exit()
            util.regroup()
        end
        return
    end
    if st.once_and_done then
        util.silver_deposit()
        M.get_new_bounty_before_exit()
        util.regroup()
        util.go2_rest()
        return
    end

    util.check_health()
    M.prep()
end

function M.prep(no_check)
    if not no_check then util.check_health() end
    local st = util.state.settings
    local loot = (st.selling_script ~= "") and st.selling_script or "eloot"
    Script.run(loot, "sell")
    util.silver_deposit()
end

function M.creature_culling(creature)
    util.msg("debug", "creature_culling: " .. tostring(creature))
    if M.switch_profile(creature) then hunting.go_hunting() end
end

function M.find_location(location)
    if not location then return end
    util.msg("debug", "find_location: " .. location)

    local all_rooms = Map.list() or {}
    local area_rooms = {}
    local area_set = {}

    for _, rid in ipairs(all_rooms) do
        local r = Map.find_room(rid)
        if r and r.location and r.location:find(location) then
            area_rooms[#area_rooms + 1] = rid
            area_set[rid] = true
        end
    end

    if #area_rooms == 0 then
        util.msg("yellow", "No rooms found for location: " .. location)
        return
    end

    local boundaries = {}
    for _, rid in ipairs(area_rooms) do
        local r = Map.find_room(rid)
        if r and r.wayto then
            for dest, _ in pairs(r.wayto) do
                local dest_id = tonumber(dest)
                if dest_id and not area_set[dest_id] then
                    boundaries[tostring(dest_id)] = true
                end
            end
        end
    end

    local boundary_list = {}
    for b, _ in pairs(boundaries) do boundary_list[#boundary_list + 1] = b end

    util.state.location_start = area_rooms[1]
    util.state.location_boundaries = table.concat(boundary_list, ",")
end

function M.bandit_bounty(location)
    util.msg("debug", "bandit_bounty: " .. tostring(location))
    util.state.creature = "bandits"

    if location then
        local st = util.state.settings
        for i = 1, 12 do
            local loc_name = st["location" .. i] or ""
            if loc_name ~= "" and location:lower():find(loc_name:lower()) then
                M.find_location(loc_name)
                break
            end
        end
    end

    if M.switch_profile("bandits") then
        util.state.bandit_flag = true
        hunting.go_hunting()
        util.state.bandit_flag = false
    end
end

function M.gem_bounty(gem_name, count)
    util.msg("debug", "gem_bounty: " .. tostring(gem_name) .. " x" .. tostring(count))
    local st = util.state.settings

    if (st.hording_script or "") ~= "" then
        util.run_scripts(st.hording_script)
        pause(2)
    end

    if (Bounty.task or ""):find("succeeded") then return end

    local containers = GameObj.inv() or {}
    local found = 0
    if gem_name then
        local gem_lower = gem_name:lower()
        for _, bag in ipairs(containers) do
            if bag.contents then
                for _, item in ipairs(bag.contents) do
                    if item.name:lower():find(gem_lower .. "$") then
                        found = found + 1
                    end
                end
            end
        end
    end

    if found >= (count or 1) then
        local loot = (st.selling_script ~= "") and st.selling_script or "eloot"
        Script.run(loot, "sell")
        return
    end

    hunting.go_hunting()
end

function M.skin_bounty(creature, skin, quantity)
    util.msg("debug", "skin_bounty: " .. tostring(creature) .. " skin=" .. tostring(skin))
    local st = util.state.settings
    local qty = (quantity or 1) + (st.extra_skin or 0)

    local norm_skin = skin or ""
    norm_skin = norm_skin:gsub("s$", "")
    norm_skin = norm_skin:gsub("teeth$", "tooth")
    norm_skin = norm_skin:gsub("hooves?$", "hoof")

    local containers = GameObj.inv() or {}
    local found = 0

    for _, bag in ipairs(containers) do
        if bag.contents then
            for _, item in ipairs(bag.contents) do
                local iname = item.name:lower()
                if iname:find(norm_skin:lower()) then
                    if iname:find("bundle") then
                        fput("look in #" .. item.id)
                        local result = matchtimeout(3, "count a total of", "You see")
                        if result then
                            local bundle_count = result:match("count a total of (%d+)")
                            if bundle_count then found = found + tonumber(bundle_count) end
                        end
                    else
                        found = found + 1
                    end
                end
            end
        end
    end

    util.msg("debug", "Found " .. found .. " of " .. qty .. " skins")

    if found >= qty then
        local loot = (st.selling_script ~= "") and st.selling_script or "eloot"
        Script.run(loot, "sell")
        return
    end

    util.state.remaining_skins = qty - found
    if M.switch_profile(creature) then hunting.go_hunting() end
end

--------------------------------------------------------------------------------
-- Foraging
--------------------------------------------------------------------------------

local function cast_forage_spells()
    local st = util.state.settings
    local opts = st.forage_options or {}
    local function has(opt) return settings_mod.list_contains(opts, opt) end

    if has("use_213") and Spell[213].known and Spell[213].affordable and not Spell[213].active then
        put("incant 213"); util.wait_rt()
    end
    if has("use_1011") and Spell[1011].known and Spell[1011].affordable and not Spell[1011].active then
        put("incant 1011"); util.wait_rt()
    end
    if has("use_709") and Spell[709].known and Spell[709].affordable and not Spell[709].active then
        put("incant 709"); util.wait_rt()
    end
    if has("use_604") and Spell[604].known and Spell[604].affordable and not Spell[604].active then
        put("incant 604"); util.wait_rt()
    end
    if has("use_604evoke") and Spell[604].known and Spell[604].affordable then
        put("incant 604 evoke"); util.wait_rt()
    end
    if has("use_506") and Spell[506].known and Spell[506].affordable and not Spell[506].active then
        put("incant 506"); util.wait_rt()
    end
    if has("use_919") and Spell[919].known and Spell[919].affordable and not Spell[919].active then
        put("incant 919"); util.wait_rt()
    end
    if has("use_140") and Spell[140].known and Spell[140].affordable and not Spell[140].active then
        put("incant 140"); util.wait_rt()
    end
    if has("use_1035") and Spell[1035].known and Spell[1035].affordable and not Spell[1035].active then
        put("incant 1035"); util.wait_rt()
    end
    if has("use_resolve") and Spell[9704].known and Spell[9704].affordable then
        put("incant 9704"); util.wait_rt()
    end
    if has("use_619") and Spell[619].known and Spell[619].affordable and not Spell[619].active then
        put("incant 619"); util.wait_rt()
    end
    if has("use_650") and Spell[650].known and Spell[650].affordable then
        if not Spell.active_p(9039) then
            put("incant 650"); util.wait_rt()
        end
    end
    if has("use_608") and Spell[608].known and Spell[608].affordable then
        put("incant 608"); util.wait_rt()
    elseif has("hiding") then
        fput("hide"); util.wait_rt()
    end
end

function M.forage_find(herb, location)
    local herb_fixed = data.herb_fixes[herb] or herb
    local herb_rooms = Map.tags(herb_fixed) or {}
    if #herb_rooms == 0 then
        local herb_alt = herb_fixed:gsub("^some ", "")
        herb_rooms = Map.tags(herb_alt) or {}
    end
    if #herb_rooms == 0 then return {} end

    local current_id = Map.current_room()
    local with_dist = {}
    for _, rid in ipairs(herb_rooms) do
        local path = Map.find_path(current_id, rid)
        if path and #path <= 90 then
            with_dist[#with_dist + 1] = {id = rid, dist = #path}
        end
    end
    table.sort(with_dist, function(a, b) return a.dist < b.dist end)

    local targets = {}
    local limit = (location == "nearest" or not location) and 10 or #with_dist
    for i = 1, math.min(limit, #with_dist) do
        targets[#targets + 1] = with_dist[i].id
    end
    return targets
end

function M.forage_turnin(herb)
    local current = Map.current_room()
    for _, uid in ipairs(data.herbalist_room_uids) do
        local rooms = Map.tags(uid) or {}
        for _, rid in ipairs(rooms) do
            local path = Map.find_path(current, rid)
            if path and #path <= 2 then
                util.go2(rid); util.wait_rt()
                local npc = M.find_npc(data.herbalist_patterns)
                if npc then
                    for _ = 1, 50 do
                        fput("give #" .. npc.id)
                        local result = matchtimeout(5, "This looks perfect", "partially used", "I don't need")
                        if not result or result:find("I don't need") then break end
                        pause(0.3)
                    end
                end
                return true
            end
        end
    end
    return false
end

function M.forage_return(recover_room)
    util.fog()
    util.go2_rest()

    util.go2("herbalist"); util.wait_rt()
    local npc = M.find_npc(data.herbalist_patterns)
    if npc then
        for _ = 1, 50 do
            fput("give #" .. npc.id)
            local result = matchtimeout(5, "This looks perfect", "partially used", "I don't need")
            if not result or result:find("I don't need") then break end
            pause(0.3)
        end
    end

    hunting.post_hunt("forage")

    local btask = Bounty.task or ""
    if not btask:find("succeeded") and not btask:find("not currently assigned") then
        util.msg("yellow", "Herbs depleted. Sleeping 3 minutes for room recovery...")
        pause(180)
    end
end

function M.forage_bounty(herb, quantity, location)
    util.msg("debug", "forage_bounty: " .. tostring(herb) .. " x" .. tostring(quantity))
    location = location or "nearest"
    local herb_fixed = data.herb_fixes[herb] or herb

    hunting.pre_hunt("forage")
    util.change_stance(100)

    local targets = M.forage_find(herb_fixed, location)
    if #targets == 0 then
        util.msg("yellow", "No forage rooms found for: " .. herb_fixed)
        hunting.post_hunt("forage")
        return
    end

    local foraged = 0
    local qty = tonumber(quantity) or 1
    local st = util.state.settings
    local opts = st.forage_options or {}
    local use_gambit = settings_mod.list_contains(opts, "use_gambit")
    local run_opt = settings_mod.list_contains(opts, "run")

    for _, room_id in ipairs(targets) do
        util.go2(room_id)

        local npcs = GameObj.npcs()
        local hostile = false
        for _, npc in ipairs(npcs) do
            if npc.status ~= "dead" then hostile = true; break end
        end
        if hostile and run_opt then
            goto continue_room
        end

        cast_forage_spells()

        for _ = 1, 20 do
            fput("kneel"); util.wait_rt()

            if use_gambit then
                put("forage for " .. herb_fixed .. " gambit")
            else
                put("forage for " .. herb_fixed)
            end
            local result = matchtimeout(10, table.unpack(data.forage_results))
            util.wait_rt()

            if result and result:find("You forage") then
                fput("stow right"); fput("stow left")
                foraged = foraged + 1
                util.msg("yellow", foraged .. " of " .. qty .. " " .. herb_fixed .. " foraged")
                if foraged >= qty then fput("stand"); goto forage_done end
            elseif result and (result:find("can find no hint") or result:find("see no evidence")
                    or result:find("foraging here recently")) then
                break
            elseif result then
                for _, inj in ipairs(data.forage_injuries) do
                    if result:find(inj) then
                        util.wait_rt()
                        util.check_health()
                        if Spell[114].known and Spell[114].affordable then
                            put("incant 114"); util.wait_rt()
                        end
                        break
                    end
                end
            end
        end
        fput("stand")

        M.forage_turnin(herb_fixed)

        ::continue_room::
    end

    ::forage_done::
    fput("stand")

    M.forage_return()
end

--------------------------------------------------------------------------------
-- Heirloom
--------------------------------------------------------------------------------

local function cast_heirloom_spells()
    local st = util.state.settings
    local opts = st.heirloom_options or {}
    local function has(opt) return settings_mod.list_contains(opts, opt) end

    if has("use_213") and Spell[213].known and Spell[213].affordable and not Spell[213].active then
        put("incant 213"); util.wait_rt()
    end
    if has("use_709") and Spell[709].known and Spell[709].affordable and not Spell[709].active then
        put("incant 709"); util.wait_rt()
    end
    if has("use_402") and Spell[402].known and Spell[402].affordable and not Spell[402].active then
        put("incant 402"); util.wait_rt()
    end
    if has("use_506") and Spell[506].known and Spell[506].affordable and not Spell[506].active then
        put("incant 506"); util.wait_rt()
    end
    if has("use_619") and Spell[619].known and Spell[619].affordable and not Spell[619].active then
        put("incant 619"); util.wait_rt()
    end
    if has("use_919") and Spell[919].known and Spell[919].affordable and not Spell[919].active then
        put("incant 919"); util.wait_rt()
    end
    if has("use_140") and Spell[140].known and Spell[140].affordable and not Spell[140].active then
        put("incant 140"); util.wait_rt()
    end
    if has("use_1011") and Spell[1011].known and Spell[1011].affordable and not Spell[1011].active then
        put("incant 1011"); util.wait_rt()
    end
    if has("use_1035") and Spell[1035].known and Spell[1035].affordable and not Spell[1035].active then
        put("incant 1035"); util.wait_rt()
    end
end

function M.heirloom_search(creature, item)
    util.msg("debug", "heirloom_search: " .. tostring(creature))
    if not M.switch_profile(creature) then return end

    hunting.pre_hunt("heirloom")
    util.change_stance(100)

    cast_heirloom_spells()

    local wander_visited = {}
    local st = util.state.settings
    local use_right = settings_mod.list_contains(st.heirloom_options or {}, "use_right")

    for _ = 1, 200 do
        local npcs = GameObj.npcs()
        local hostile = false
        for _, npc in ipairs(npcs) do
            if npc.status and npc.status ~= "dead" then hostile = true; break end
        end

        if not hostile then
            cast_heirloom_spells()
            fput("kneel"); util.wait_rt()
            fput("search"); util.wait_rt()
            fput("stand"); util.wait_rt()

            if (Bounty.task or ""):find("You have located") then
                local loot = GameObj.loot()
                for _, obj in ipairs(loot) do
                    if item and obj.name:find(item) then
                        fput("get #" .. obj.id)
                        if use_right then
                            fput("stow left")
                        else
                            fput("stow #" .. obj.id)
                        end
                        break
                    end
                end
                local rh = GameObj.right_hand()
                if rh and not use_right then fput("stow right") end
                break
            end
        end

        local room_obj = Room.current()
        if room_obj and room_obj.wayto then
            local exits = {}
            for dest, cmd in pairs(room_obj.wayto) do
                local skip = false
                for _, bad in ipairs(util.state.bad_rooms) do
                    if tonumber(dest) == bad then skip = true; break end
                end
                if not skip then exits[#exits + 1] = {dest = dest, cmd = cmd} end
            end
            local unvisited = {}
            for _, e in ipairs(exits) do
                if not wander_visited[e.dest] then unvisited[#unvisited + 1] = e end
            end
            local choice = #unvisited > 0
                and unvisited[math.random(#unvisited)]
                or (#exits > 0 and exits[math.random(#exits)] or nil)
            if choice then
                wander_visited[choice.dest] = true
                move(choice.cmd)
            else break end
        else break end
    end

    util.go2_rest()
    hunting.post_hunt("heirloom")
end

function M.heirloom_bounty(item, creature, location, action)
    if action == "loot" then
        if M.switch_profile(creature) then hunting.go_hunting() end
    elseif action == "search" then
        M.heirloom_search(creature, item)
    end
end

--------------------------------------------------------------------------------
-- Escort / Rescue
--------------------------------------------------------------------------------

function M.escort(pickup, dropoff)
    util.msg("debug", "escort: " .. tostring(pickup) .. " -> " .. tostring(dropoff))
    local st = util.state.settings
    local from = data.escort_pickup[pickup]
    local to = data.escort_dropoff[dropoff]
    if not from or not to then util.msg("error", "Unknown escort route"); M.bounty_remove(); return end

    local trip = from .. "_to_" .. to
    if not settings_mod.list_contains(st.escort_types or {}, trip)
       or not settings_mod.list_contains(st.bounty_types or {}, "escort") then
        M.bounty_remove(); return
    end
    if st.basic then return end

    hunting.pre_hunt("escort")
    Script.run(st.escort_script ~= "" and st.escort_script or "escortgo2")
    pause(2)
    util.go2_rest()
    hunting.post_hunt("escort")
end

function M.child_found()
    util.msg("debug", "child_found - child in room")
    local st = util.state.settings
    local rescue = st.rescue_script
    Script.run((rescue ~= "") and rescue or "echild")
    pause(2)
    util.go2_rest()
    hunting.post_hunt("child")
end

function M.child_bounty(creature)
    util.msg("debug", "child_bounty: " .. tostring(creature))
    if not M.switch_profile(creature) then return end

    for _, npc in ipairs(GameObj.npcs()) do
        if npc.name:find("child") and (Bounty.task or ""):find("You have made contact") then
            M.child_found()
            return
        end
    end

    hunting.go_hunting()

    for _, npc in ipairs(GameObj.npcs()) do
        if npc.name:find("child") then
            M.child_found()
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Cooldown / Exit
--------------------------------------------------------------------------------

function M.wait_until_next_bounty_available()
    local last_msg = 0
    while true do
        local btask = Bounty.task or ""
        if not btask:find("Come back in about") then return end
        local now = os.time()
        if now - last_msg >= 60 then
            util.msg("yellow", "Waiting for bounty cooldown... " .. util.elapsed())
            last_msg = now
        end
        pause(0.5)
    end
end

function M.get_new_bounty_before_exit()
    local st = util.state.settings
    if not st.new_bounty_on_exit then return end
    M.wait_until_next_bounty_available()
    M.bounty_get()
    pause(2)
    local info = Bounty.parse()
    if info and info.type ~= "none" then
        M.fetch_bounty_details(info)
        if M.check_removal() then M.bounty_remove() end
    end
end

function M.wait_for_bounty()
    local st = util.state.settings
    if st.use_boosts and M.check_boost() then
        M.bounty_get()
        return
    end
    if st.basic then util.go2_rest(); return end
    if st.keep_hunting then
        hunting.keep_hunting()
        M.wait_until_next_bounty_available()
    else
        M.wait_until_next_bounty_available()
    end
end

--------------------------------------------------------------------------------
-- Main Bounty Router
--------------------------------------------------------------------------------

M.bounty_check = function()
    util.msg("debug", "bounty_check: " .. (Bounty.task or ""))
    util.state.creature = nil

    if M.check_removal() then
        M.bounty_remove()
        if util.state.settings.once_and_done then
            M.get_new_bounty_before_exit()
            util.regroup()
            util.go2_rest()
            return
        end
    end

    local info = Bounty.parse()
    if not info then
        fput("bounty"); pause(2)
        info = Bounty.parse()
        if not info then util.msg("warn", "Could not parse bounty"); return end
    end

    local bt = info.type or "none"

    if info.done and bt ~= "heirloom" then
        M.bounty_complete()
    elseif bt == "none" then
        local btask = Bounty.task or ""
        if btask:find("Come back in about") then
            M.wait_for_bounty()
        else
            M.bounty_get()
        end
    elseif bt == "failed" then
        M.ask_taskmaster("failure")
    elseif bt == "guard" or bt:find("_assignment$") then
        if bt == "gem_assignment" then M.ask_assignment("jeweler")
        elseif bt == "skin_assignment" then M.ask_assignment("furrier")
        elseif bt == "herb_assignment" then M.ask_assignment("herbalist")
        else M.ask_guard() end
    elseif bt == "creature" or bt == "dangerous" or bt == "cull" then
        M.creature_culling(info.creature)
    elseif bt == "gem" then
        M.gem_bounty(info.gem, info.number or 1)
    elseif bt == "herb" then
        M.forage_bounty(info.herb, info.number or 1, info.area)
    elseif bt == "skin" then
        M.skin_bounty(info.creature, info.skin, info.number or 1)
    elseif bt == "heirloom" then
        M.heirloom_bounty(info.item, info.creature, info.area, info.action)
    elseif bt == "escort" then
        M.escort(info.start, info.destination)
    elseif bt == "rescue" or bt == "rescue_spawned" then
        M.child_bounty(info.creature)
    elseif bt == "bandits" then
        M.bandit_bounty(info.area)
    else
        util.msg("warn", "Unknown bounty type: " .. tostring(bt))
        return
    end

    M.bounty_check()
end

return M
