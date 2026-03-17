local data = require("data")
local settings_mod = require("settings")
local util = require("util")
local hunting = require("hunting")

local M = {}

-- Forward declaration for recursive bounty_check
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

    -- Search Sailor's Grief for Seldit
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
                "SEARCH the area", "LOOT the item"
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
        hunting.go_hunting()
        return false
    else
        util.go2_rest()
        util.msg("info", "No Profile for " .. tostring(creature) .. ". Check Profiles tab.")
        return false
    end
end

--------------------------------------------------------------------------------
-- Bounty Handlers
--------------------------------------------------------------------------------

function M.bounty_get() M.ask_taskmaster("get") end

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
        if st.keep_hunting then hunting.go_hunting() end
    end

    M.ask_taskmaster("turn-in")

    if st.basic then util.silver_deposit(); return end
    if st.once_and_done then util.silver_deposit(); util.go2_rest(); return end

    util.check_health()
    local loot = st.selling_script ~= "" and st.selling_script or "eloot"
    Script.run(loot, "sell")
    util.silver_deposit()
end

function M.creature_culling(creature)
    util.msg("debug", "creature_culling: " .. tostring(creature))
    if M.switch_profile(creature) then hunting.go_hunting() end
end

function M.bandit_bounty(location)
    util.msg("debug", "bandit_bounty: " .. tostring(location))
    util.state.creature = "bandits"
    if M.switch_profile("bandits") then hunting.go_hunting() end
end

function M.gem_bounty(gem_name, count)
    util.msg("debug", "gem_bounty: " .. tostring(gem_name) .. " x" .. tostring(count))
    if (util.state.settings.hording_script or "") ~= "" then
        util.run_scripts(util.state.settings.hording_script)
    end
    if (Bounty.task or ""):find("succeeded") then return end
    hunting.go_hunting()
end

function M.skin_bounty(creature, skin, count)
    util.msg("debug", "skin_bounty: " .. tostring(creature))
    if M.switch_profile(creature) then hunting.go_hunting() end
end

function M.forage_bounty(herb, quantity, location)
    util.msg("debug", "forage_bounty: " .. tostring(herb) .. " x" .. tostring(quantity))
    location = location or "nearest"
    if herb == "trollear mushroom" then herb = "trollfear mushroom" end
    if herb and herb:find("^ayana ") then herb = "ayana leaf" end

    hunting.pre_hunt("forage")
    util.change_stance(100)

    -- Find rooms tagged with this herb
    local herb_rooms = Map.tags(herb) or {}
    if #herb_rooms == 0 then
        local herb_alt = herb:gsub("^some ", "")
        herb_rooms = Map.tags(herb_alt) or {}
    end
    if #herb_rooms == 0 then
        util.msg("yellow", "No forage rooms found for: " .. herb)
        hunting.post_hunt("forage")
        return
    end

    -- Sort by distance, limit to 10
    local current_id = Map.current_room()
    local with_dist = {}
    for _, rid in ipairs(herb_rooms) do
        local path = Map.find_path(current_id, rid)
        if path then with_dist[#with_dist + 1] = {id = rid, dist = #path} end
    end
    table.sort(with_dist, function(a, b) return a.dist < b.dist end)
    local targets = {}
    for i = 1, math.min(10, #with_dist) do targets[#targets + 1] = with_dist[i].id end

    local foraged = 0
    local qty = tonumber(quantity) or 1

    for _, room_id in ipairs(targets) do
        util.go2(room_id)

        -- Skip if hostile NPCs and "run" option
        local npcs = GameObj.npcs()
        local hostile = false
        for _, npc in ipairs(npcs) do
            if npc.status ~= "dead" then hostile = true; break end
        end
        if hostile and settings_mod.list_contains(util.state.settings.forage_options, "run") then
            goto continue_room
        end

        for _ = 1, 20 do
            fput("kneel"); util.wait_rt()

            put("forage for " .. herb)
            local result = matchtimeout(10, table.unpack(data.forage_results))
            util.wait_rt()

            if result and result:find("You forage") then
                fput("stow right"); fput("stow left")
                foraged = foraged + 1
                util.msg("yellow", foraged .. " of " .. qty .. " " .. herb .. " foraged")
                if foraged >= qty then fput("stand"); goto forage_done end
            elseif result and (result:find("can find no hint") or result:find("see no evidence")) then
                break
            elseif result then
                for _, inj in ipairs(data.forage_injuries) do
                    if result:find(inj) then
                        util.wait_rt()
                        if Spell[114].known and Spell[114].affordable then
                            put("incant 114"); util.wait_rt()
                        end
                        break
                    end
                end
            end
        end
        fput("stand")
        ::continue_room::
    end

    ::forage_done::
    fput("stand")

    -- Return and turn in
    util.fog()
    util.go2_rest()

    -- Turn in to herbalist
    util.go2("herbalist"); util.wait_rt()
    local herbalist = M.find_npc(data.herbalist_patterns)
    if herbalist then
        util.msg("info", "Turning in herbs to " .. herbalist.name)
        fput("give #" .. herbalist.id)
    end

    hunting.post_hunt("forage")
end

function M.heirloom_search(creature, item)
    util.msg("debug", "heirloom_search: " .. tostring(creature))
    if not M.switch_profile(creature) then return end

    hunting.pre_hunt("heirloom")
    util.change_stance(100)

    local wander_visited = {}
    for _ = 1, 200 do
        local npcs = GameObj.npcs()
        local hostile = false
        for _, npc in ipairs(npcs) do
            if npc.status and npc.status ~= "dead" then hostile = true; break end
        end

        if not hostile then
            fput("kneel"); util.wait_rt()
            fput("search"); util.wait_rt()
            fput("stand"); util.wait_rt()

            if (Bounty.task or ""):find("You have located") then
                local loot = GameObj.loot()
                for _, obj in ipairs(loot) do
                    if item and obj.name:find(item) then
                        fput("get #" .. obj.id); fput("stow #" .. obj.id); break
                    end
                end
                local rh = GameObj.right_hand()
                if rh then fput("stow right") end
                break
            end
        end

        -- Wander
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

function M.child_bounty(creature)
    util.msg("debug", "child_bounty: " .. tostring(creature))
    if not M.switch_profile(creature) then return end
    util.go2_rest()
    hunting.go_hunting()

    local found = false
    for _, npc in ipairs(GameObj.npcs()) do
        if npc.name:find("child") then found = true; break end
    end
    if found and (Bounty.task or ""):find("You have made contact") then
        local rescue = util.state.settings.rescue_script
        Script.run((rescue ~= "") and rescue or "echild")
        pause(2)
        util.go2_rest()
        hunting.post_hunt("child")
    end
end

function M.ask_guard()
    util.msg("debug", "ask_guard")
    util.go2("advguard"); util.wait_rt()
    local original = Bounty.task or ""
    local all = {}
    for _, obj in ipairs(GameObj.room_desc() or {}) do all[#all + 1] = obj end
    for _, obj in ipairs(GameObj.npcs() or {}) do all[#all + 1] = obj end
    for _, npc in ipairs(all) do
        if data.matches_any(npc.name, data.guard_patterns) then
            put("ask " .. npc.noun .. " about bounty")
            matchtimeout(5,
                "suppress bandit", "particularly dangerous",
                "SEARCH the area", "LOOT the item",
                "I don't have any tasks", "Try bugging me later",
                "Ah, so you have returned", "You have completed"
            )
            if util.bounty_change(original) then return end
        end
    end
end

--------------------------------------------------------------------------------
-- Exclusion Check
--------------------------------------------------------------------------------

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
-- Main Bounty Router
--------------------------------------------------------------------------------

M.bounty_check = function()
    util.msg("debug", "bounty_check: " .. (Bounty.task or ""))
    util.state.creature = nil

    if M.check_removal() then
        M.bounty_remove()
        if util.state.settings.once_and_done then util.go2_rest(); return end
    end

    local info = Bounty.parse()
    if not info then
        fput("bounty"); pause(2)
        info = Bounty.parse()
        if not info then util.msg("warn", "Could not parse bounty"); return end
    end

    local bt = info.type or "none"

    if info.done and bt ~= "heirloom" then M.bounty_complete()
    elseif bt == "none" then M.bounty_get()
    elseif bt == "failed" then M.ask_taskmaster("failure")
    elseif bt == "guard" or bt == "assignment" then M.ask_guard()
    elseif bt == "gem_assignment" then M.ask_assignment("jeweler")
    elseif bt == "skin_assignment" then M.ask_assignment("furrier")
    elseif bt == "herb_assignment" then M.ask_assignment("herbalist")
    elseif bt == "creature" or bt == "dangerous" or bt == "cull" then M.creature_culling(info.creature)
    elseif bt == "gem" then M.gem_bounty(info.gem, info.number or 1)
    elseif bt == "herb" then M.forage_bounty(info.herb, info.number or 1, info.area)
    elseif bt == "skin" then M.skin_bounty(info.creature, info.skin, info.number or 1)
    elseif bt == "heirloom" then M.heirloom_bounty(info.item, info.creature, info.area, info.action)
    elseif bt == "escort" then M.escort(info.start, info.destination)
    elseif bt == "rescue" then M.child_bounty(info.creature)
    elseif bt == "bandits" then M.bandit_bounty(info.area)
    else util.msg("warn", "Unknown bounty type: " .. tostring(bt)); return
    end

    M.bounty_check()
end

return M
