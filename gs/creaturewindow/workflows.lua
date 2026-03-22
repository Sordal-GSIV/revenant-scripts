--- Bounty workflow automation: guild, guard, gem, herb, skin, furrier.

local inventory = require("inventory")
local bounty_display = require("bounty_display")

local M = {}

--- Prepare hands for turn-in.
local function prepare_hands()
    local ok, _ = pcall(put, "stow all")
    if not ok then end -- ignore errors
end

--- Wait for go2 to finish.
local function wait_for_go2()
    while running("go2") do pause(0.2) end
end

--- Refresh bounty UI after a workflow completes.
local function refresh_bounty()
    bounty_display.parse()
end

--- Run the guild bounty workflow (go to advguild, ask taskmaster).
function M.run_guild()
    if bounty_display.guild_workflow_running then return end
    bounty_display.guild_workflow_running = true

    local ok, err = pcall(function()
        inventory.stop_turnin_scripts()
        Script.run("go2", "advguild")
        wait_for_go2()
        prepare_hands()

        local npc = inventory.find_origin_turnin_npc(bounty_display.origin_npc_id, bounty_display.origin_npc_noun)
                 or inventory.find_guild_taskmaster()
        if npc then
            bounty_display.ask_bounty_and_sync(npc)
        else
            respond("Creaturewindow: could not find a valid guild bounty NPC here.")
        end
    end)

    if not ok then
        respond("Creaturewindow guild workflow error: " .. tostring(err))
    end
    bounty_display.guild_workflow_running = false
    refresh_bounty()
end

--- Determine the go2 destination for guard turn-in.
local function guard_destination()
    local loc = (bounty_display.bounty_table().location or ""):lower()
    local room = Room.current()
    local room_loc = room and room.location and room.location:lower() or ""
    if loc:find("hinterwild") or room_loc:find("hinterwild") then
        return "advguard3"
    end
    return "advguard"
end

--- Run the guard bounty workflow.
function M.run_guard()
    if bounty_display.guard_workflow_running then return end
    bounty_display.guard_workflow_running = true

    local ok, err = pcall(function()
        inventory.stop_turnin_scripts()

        local dest = guard_destination()
        Script.run("go2", dest)
        wait_for_go2()
        prepare_hands()

        -- Get heirloom if completing that bounty
        if bounty_display.task_type() == "completeheirloom" then
            local heirloom_name = (bounty_display.bounty_table().heirloom or ""):match("^%s*(.-)%s*$")
            if heirloom_name ~= "" then
                local all = inventory.collect_all_inv()
                for _, item in ipairs(all) do
                    if inventory.item_matches_bounty(item.name or "", heirloom_name) then
                        fput("get #" .. item.id)
                        break
                    end
                end
            end
        end

        local npc = inventory.find_advguard_npc(bounty_display.bounty_table().turnin_npc)
                 or inventory.find_origin_turnin_npc(bounty_display.origin_npc_id, bounty_display.origin_npc_noun)

        -- Fallback: try advguard2
        if not npc and dest ~= "advguard2" then
            Script.run("go2", "advguard2")
            wait_for_go2()
            prepare_hands()
            npc = inventory.find_advguard_npc(bounty_display.bounty_table().turnin_npc)
               or inventory.find_origin_turnin_npc(bounty_display.origin_npc_id, bounty_display.origin_npc_noun)
        end

        if npc then
            bounty_display.ask_bounty_and_sync(npc)
        else
            respond("Creaturewindow: could not find a valid bounty NPC here.")
        end
    end)

    if not ok then
        respond("Creaturewindow guard workflow error: " .. tostring(err))
    end
    bounty_display.guard_workflow_running = false
    refresh_bounty()
end

--- Run the furrier bounty workflow (get skin specifics).
function M.run_furrier()
    if bounty_display.furrier_workflow_running then return end
    bounty_display.furrier_workflow_running = true

    local ok, err = pcall(function()
        inventory.stop_turnin_scripts()
        Script.run("go2", "furrier")
        wait_for_go2()
        prepare_hands()

        local npc = inventory.find_furrier_npc()
        if npc then
            bounty_display.ask_bounty_and_sync(npc)
        else
            respond("Creaturewindow: could not find a valid furrier NPC here.")
        end
    end)

    if not ok then
        respond("Creaturewindow furrier workflow error: " .. tostring(err))
    end
    bounty_display.furrier_workflow_running = false
    refresh_bounty()
end

--- Run the skin bounty sell workflow.
function M.run_skin()
    if bounty_display.skin_workflow_running then return end
    if bounty_display.task_type() ~= "skinspecifics" then
        respond("Creaturewindow: no active skin-specific bounty.")
        return
    end

    bounty_display.skin_workflow_running = true

    local ok, err = pcall(function()
        inventory.stop_turnin_scripts()
        Script.run("go2", "furrier")
        wait_for_go2()
        prepare_hands()

        local npc = inventory.find_furrier_npc()
        if not npc then
            respond("Creaturewindow: could not find a valid furrier NPC here.")
            return
        end

        -- Sell skins — pre-snapshot IDs to avoid stale ID drift during sell loop
        local skin_name = (bounty_display.bounty_table().skin or ""):match("^%s*(.-)%s*$")
        local target_count = tonumber(bounty_display.bounty_table().remaining) or 1
        if target_count < 1 then target_count = 1 end

        local skin_ids = {}
        local all = inventory.collect_all_inv()
        for _, item in ipairs(all) do
            if #skin_ids >= target_count then break end
            if inventory.item_matches_bounty(item.name or "", skin_name) then
                skin_ids[#skin_ids + 1] = item.id
            end
        end

        for _, skin_id in ipairs(skin_ids) do
            fput("get #" .. skin_id)
            fput("sell #" .. skin_id)
        end

        bounty_display.ask_bounty_and_sync(npc, true)
    end)

    if not ok then
        respond("Creaturewindow skin workflow error: " .. tostring(err))
    end
    bounty_display.skin_workflow_running = false
    refresh_bounty()
end

--- Run the herb bounty workflow (forage with zzherb, then turn in).
function M.run_herb()
    if bounty_display.herb_workflow_running then return end
    local t = bounty_display.task_type()
    if t ~= "herb" and t ~= "herbspecifics" then
        respond("Creaturewindow: no active herb-specific bounty.")
        return
    end

    bounty_display.herb_workflow_running = true

    local ok, err = pcall(function()
        inventory.stop_turnin_scripts()

        -- Need specifics?
        local needs_specifics = (t == "herb")
            or not bounty_display.bounty_table().remaining
            or bounty_display.current_herb_name() == ""

        if needs_specifics then
            Script.run("go2", "healer")
            wait_for_go2()
            prepare_hands()

            local npc = inventory.find_healer_npc() or inventory.find_bounty_npc()
            if not npc then
                respond("Creaturewindow: could not find healer/alchemist for herb specifics.")
                return
            end

            dothistimeout("ask #" .. npc.id .. " about bounty", 8,
                "concoction that requires", "retrieve %d+ samples", "You have been tasked to retrieve")
            pause(0.2)

            -- Re-parse
            for _ = 1, 8 do
                bounty_display.parse()
                if bounty_display.task_type() == "herbspecifics" then break end
                pause(0.2)
            end

            bounty_display.origin_room_id = GameState.room_id
            bounty_display.origin_npc_id = npc.id
            bounty_display.origin_npc_noun = npc.noun
        else
            bounty_display.capture_origin()
        end

        if bounty_display.task_type() ~= "herbspecifics" then
            respond("Creaturewindow: could not fetch herb specifics from healer/alchemist.")
            return
        end

        local origin_room = bounty_display.origin_room_id or GameState.room_id
        local herb_name = bounty_display.current_herb_name()
        local needed = tonumber(bounty_display.bounty_table().remaining) or 1
        if needed < 1 then needed = 1 end

        -- Count herbs on hand
        local on_hand = 0
        local all = inventory.collect_all_inv()
        for _, item in ipairs(all) do
            if inventory.item_matches_bounty(item.name or "", herb_name) then
                on_hand = on_hand + inventory.item_stack_count(item)
            end
        end

        local find_count = math.max(needed - on_hand, 0)

        -- Check for zzherb
        if not Script.exists("zzherb") then
            respond("Creaturewindow: zzherb script not found.")
            return
        end

        -- Wait for any existing zzherb to finish
        if running("zzherb") then
            respond("Creaturewindow: waiting for current zzherb run to finish...")
            while running("zzherb") do pause(0.2) end
        end

        if find_count > 0 and herb_name ~= "" then
            -- Run zzherb to forage
            Script.run("zzherb", herb_name .. " " .. find_count)
            while running("zzherb") do pause(0.2) end

            -- Fallback with "some" prefix
            on_hand = 0
            all = inventory.collect_all_inv()
            for _, item in ipairs(all) do
                if inventory.item_matches_bounty(item.name or "", herb_name) then
                    on_hand = on_hand + inventory.item_stack_count(item)
                end
            end

            if on_hand < needed then
                Script.run("zzherb", "some " .. herb_name .. " " .. find_count)
                while running("zzherb") do pause(0.2) end
            end

            -- Fallback with base noun
            on_hand = 0
            all = inventory.collect_all_inv()
            for _, item in ipairs(all) do
                if inventory.item_matches_bounty(item.name or "", herb_name) then
                    on_hand = on_hand + inventory.item_stack_count(item)
                end
            end

            if on_hand < needed then
                local noun = bounty_display.current_herb_noun()
                if noun ~= "" then
                    Script.run("zzherb", noun .. " " .. find_count)
                    while running("zzherb") do pause(0.2) end
                end
            end
        end

        -- Return to origin room
        if GameState.room_id ~= origin_room then
            Script.run("go2", tostring(origin_room))
            wait_for_go2()
            prepare_hands()
        end

        -- Hand in herbs
        local npc = inventory.find_origin_turnin_npc(bounty_display.origin_npc_id, bounty_display.origin_npc_noun)
        if not npc then
            Script.run("go2", "healer")
            wait_for_go2()
            prepare_hands()
            npc = inventory.find_origin_turnin_npc(bounty_display.origin_npc_id, bounty_display.origin_npc_noun)
               or inventory.find_healer_npc()
        end

        if npc then
            -- Give herbs one at a time
            while true do
                all = inventory.collect_all_inv()
                local herb_item = nil
                for _, item in ipairs(all) do
                    if inventory.item_matches_bounty(item.name or "", herb_name) then
                        herb_item = item
                        break
                    end
                end
                if not herb_item then break end
                fput("get #" .. herb_item.id)
                fput("give #" .. herb_item.id .. " to #" .. npc.id)
            end
            bounty_display.ask_bounty_and_sync(npc)
        else
            respond("Creaturewindow: could not find turn-in NPC.")
        end
    end)

    if not ok then
        respond("Creaturewindow herb workflow error: " .. tostring(err))
    end
    bounty_display.herb_workflow_running = false
    refresh_bounty()
end

--- Run the gem bounty workflow.
function M.run_gem()
    if bounty_display.gem_workflow_running then return end
    local t = bounty_display.task_type()
    if t ~= "gem" and t ~= "gemspecifics" then
        respond("Creaturewindow: no active gem bounty.")
        return
    end

    bounty_display.gem_workflow_running = true

    local ok, err = pcall(function()
        inventory.stop_turnin_scripts()
        bounty_display.capture_origin()

        -- Go to gemshop
        local town = (bounty_display.bounty_table().location or ""):match("^%s*(.-)%s*$")
        local preferred = inventory.GEMSHOP_UID_BY_TOWN[town]
        if preferred then
            Script.run("go2", preferred)
        else
            Script.run("go2", "gemshop")
        end
        wait_for_go2()
        prepare_hands()

        if inventory.blocked_gemshop_room() then
            respond("Creaturewindow: blocked gemshop detected; aborting gem workflow.")
            return
        end

        local npc = inventory.find_gem_npc()
        if not npc then
            respond("Creaturewindow: could not find gem dealer in gemshop.")
            return
        end

        -- Pre-clear stale gem state so change-detection works
        bounty_display.clear_gem_state()

        -- Get fresh specifics
        bounty_display.ask_bounty_and_sync(npc, false, 3.0)

        if bounty_display.task_type() ~= "gemspecifics"
           or (bounty_display.bounty_table().gem or "") == ""
           or (tonumber(bounty_display.bounty_table().remaining) or 0) <= 0 then
            respond("Creaturewindow: could not fetch fresh gem specifics from gem dealer.")
            return
        end

        local required = tonumber(bounty_display.bounty_table().remaining) or 1
        if required < 1 then required = 1 end
        local gem_name = bounty_display.bounty_table().gem or ""

        -- Try to find gem container in inventory and shake+sell
        -- First pass: search existing inventory state
        local all_entries = inventory.collect_all_inv_with_parent()
        local container_entry = nil
        for _, entry in ipairs(all_entries) do
            if inventory.is_gem_container(entry.item) and
               inventory.item_matches_bounty(entry.item.name or "", gem_name) then
                container_entry = entry
                break
            end
        end

        -- Second pass: hydrate containers and search again
        if not container_entry then
            inventory.hydrate_containers()
            all_entries = inventory.collect_all_inv_with_parent()
            for _, entry in ipairs(all_entries) do
                if inventory.is_gem_container(entry.item) and
                   inventory.item_matches_bounty(entry.item.name or "", gem_name) then
                    container_entry = entry
                    break
                end
            end
        end

        -- Third pass: try direct get commands
        if not container_entry then
            local result = inventory.try_get_gem_container(gem_name)
            if result then
                container_entry = { item = result.item, parent = nil }
                -- Track parent_id for returning later
                container_entry._parent_id = result.parent_id
            end
        end

        if container_entry then
            respond("Creaturewindow: found gem bounty container; shaking and selling up to " .. required .. ".")
            -- Shake and sell from container
            fput("get #" .. container_entry.item.id)
            for _ = 1, required do
                fput("shake #" .. container_entry.item.id)
                pause(0.2)
                -- Find gem in hands
                local rh = GameObj.right_hand()
                local lh = GameObj.left_hand()
                local gem_item = nil
                for _, hand in ipairs({lh, rh}) do
                    if hand and not inventory.is_gem_container(hand) and
                       inventory.item_matches_bounty(hand.name or "", gem_name) then
                        gem_item = hand
                        break
                    end
                end
                if gem_item then
                    fput("sell #" .. gem_item.id)
                end
            end
            -- Return container to its source
            local parent_id = container_entry._parent_id or (container_entry.parent and container_entry.parent.id)
            if parent_id then
                fput("put #" .. container_entry.item.id .. " in #" .. parent_id)
            else
                fput("stow #" .. container_entry.item.id)
            end
            bounty_display.ask_bounty_and_sync(npc, true)
            required = tonumber(bounty_display.bounty_table().remaining) or 0
        end

        if required <= 0 then return end

        -- Count gems on hand
        local on_hand = 0
        local all_items = inventory.collect_all_inv()
        for _, item in ipairs(all_items) do
            if inventory.item_matches_bounty(item.name or "", gem_name) and
               not inventory.is_gem_container(item) then
                on_hand = on_hand + inventory.item_stack_count(item)
            end
        end

        if on_hand < required then
            -- Try eloot
            if Script.exists("eloot") then
                Script.run("eloot", "bounty")
                while running("eloot") do pause(0.2) end

                -- Return to gemshop
                if preferred then
                    Script.run("go2", preferred)
                else
                    Script.run("go2", "gemshop")
                end
                wait_for_go2()
                prepare_hands()

                if inventory.blocked_gemshop_room() then
                    respond("Creaturewindow: blocked gemshop detected after eloot; aborting.")
                    return
                end
                npc = inventory.find_gem_npc()
                if not npc then
                    respond("Creaturewindow: could not find gem dealer after eloot run.")
                    return
                end
            else
                respond("Creaturewindow: eloot script not found.")
            end
        else
            respond("Creaturewindow: found " .. on_hand .. " matching gems on hand; skipping eloot bounty.")
        end

        -- Sell gems to NPC
        local target_count = tonumber(bounty_display.bounty_table().remaining) or 1
        if target_count < 1 then target_count = 1 end
        all_items = inventory.collect_all_inv()
        local sold = 0
        for _, item in ipairs(all_items) do
            if sold >= target_count then break end
            if inventory.item_matches_bounty(item.name or "", gem_name) and
               not inventory.is_gem_container(item) then
                fput("get #" .. item.id)
                fput("sell #" .. item.id)
                sold = sold + 1
            end
        end

        bounty_display.ask_bounty_and_sync(npc, true)
    end)

    if not ok then
        respond("Creaturewindow gem workflow error: " .. tostring(err))
    end
    bounty_display.gem_workflow_running = false
    refresh_bounty()
end

return M
