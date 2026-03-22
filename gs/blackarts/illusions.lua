--- @module blackarts.illusions
-- Illusion guild skills. Ported from BlackArts::Illusions (BlackArts.lic v3.12.x)

local state = require("state")
local util  = require("util")

local M = {}

-- Forward declaration for guild module reference (set by init.lua)
M.guild = nil

--------------------------------------------------------------------------------
-- Determine which illusion is available at given rank
--------------------------------------------------------------------------------

function M.latest_illusion(rank)
    if rank <= 6  then return "illusion rose"      end
    if rank <= 14 then return "illusion vortex"    end
    if rank <= 24 then return "illusion maelstrom" end
    if rank <= 34 then return "illusion void"      end
    if rank <= 47 then return "illusion shadow"    end
    return "illusion demon"
end

--------------------------------------------------------------------------------
-- Check audience size (need >= 5 audience points)
-- audience task requires witnesses: inactive=1pt, active=2pt
--------------------------------------------------------------------------------

function M.check_audience()
    local pcs = GameObj.pcs()
    if #pcs > 4 then return true end
    if #pcs < 3 then return false end

    local audience = 0
    local lines = util.get_lines("gld rank all", "You look around, but don't see anyone else")
    for _, line in ipairs(lines) do
        if line:find("is not part of your guild") then
            audience = audience + 1
        elseif line:find("is an inactive member of the Sorcerer Guild") then
            audience = audience + 1
        elseif line:find("is an active member of the Sorcerer Guild") then
            audience = audience + 2
        end
    end
    return audience > 4
end

--------------------------------------------------------------------------------
-- Main illusion dispatcher
--------------------------------------------------------------------------------

function M.do_illusions(place, guild_module)
    if place == "audience" then
        go2("town")
    elseif place == "speed" then
        local actions = require("actions")
        actions.go_empty_workshop()
    end

    util.wait_rt()

    local rank = 0
    if guild_module then
        local status = guild_module.gld()
        if status and status.illusions then
            rank = status.illusions.rank or 0
        end
    end

    local illusion = M.latest_illusion(rank)

    if illusion:find("shadow") then
        M.do_shadow(place, nil, guild_module)
        return
    elseif illusion:find("demon") then
        M.do_demons(place, guild_module)
        return
    end

    -- Simple loop illusions (rose, vortex, maelstrom, void)
    while true do
        if place == "audience" then
            while not M.check_audience() do sleep(5) end
        end

        fput(illusion)
        util.wait_rt()

        -- Find the illusion item in hand and destroy it
        local rh = GameObj.right_hand()
        local destroy = nil
        if rh and rh.name then
            if rh.name:find("black essence rose") then
                destroy = "eat my rose"
            elseif rh.name:find("vortex") then
                destroy = "peer my vortex"
            elseif rh.name:find("tempest") then
                destroy = "peer my tempest"
            elseif rh.name:find("void") then
                destroy = "poke my void"
            end
        end

        if destroy then
            fput(destroy)
            util.wait_rt()
            if place == "audience" and guild_module then
                local status = guild_module.gld()
                if status and status.illusions and
                   status.illusions.reps and status.illusions.reps > 0 then
                    sleep(35)
                end
            end
        end

        -- Check remaining reps
        if guild_module then
            local status = guild_module.gld()
            if status and status.illusions then
                if (status.illusions.reps or 0) == 0 then break end
            else
                break
            end
        else
            break
        end
    end
end

--------------------------------------------------------------------------------
-- Shadow illusion
--------------------------------------------------------------------------------

function M.shadow_item(item_name)
    if not item_name or item_name == "" then
        util.msg_error("Missing a shadow drop item. Please check settings.")
        error("missing shadow drop item")
    end

    -- Search all worn containers for the item
    for _, worn in ipairs(GameObj.inv()) do
        if worn.contents then
            for _, thing in ipairs(worn.contents) do
                if thing.name and thing.name:find(item_name, 1, true) then
                    state.shadow_item = thing
                    state.shadow_container = worn
                    return
                end
            end
        end
    end

    util.msg_error("Could not find shadow drop item: " .. item_name)
    error("shadow item not found")
end

function M.do_shadow(place, item, guild_module)
    local inv = require("inventory")
    local drop_item = item or (util.cfg and util.cfg.shadow_drop_item) or ""

    if not item then
        M.shadow_item(drop_item)
        if state.shadow_item then
            inv.drag(state.shadow_item)
            util.get_res(string.format("_drag #%s drop", state.shadow_item.id), state.put_regex or "You drop")
            util.wait_rt()
        end
    end

    -- Safety cleanup on death
    before_dying(function()
        local loot = GameObj.loot()
        for _, obj in ipairs(loot) do
            if obj.name and obj.name:find("errant shadow") then
                util.wait_rt()
                fput("illusion shadow shadow")
                util.wait_rt()
                break
            end
        end
        if state.shadow_item and state.shadow_container then
            for _, obj in ipairs(GameObj.loot()) do
                if obj.id == state.shadow_item.id then
                    inv.store_item(state.shadow_container, state.shadow_item)
                    break
                end
            end
        end
    end)

    while true do
        if place == "audience" then
            while not M.check_audience() do sleep(5) end
        end

        while checkmana() <= 3 do sleep(0.5) end

        fput("illusion shadow " .. drop_item)
        util.wait_rt()

        -- If errant shadow appeared, perform the second command
        local loot = GameObj.loot()
        for _, obj in ipairs(loot) do
            if obj.name and obj.name:find("errant shadow") then
                util.wait_rt()
                fput("illusion shadow shadow")
                util.wait_rt()
                if place == "audience" and guild_module then
                    local status = guild_module.gld()
                    if status and status.illusions and
                       status.illusions.reps and status.illusions.reps > 0 then
                        sleep(35)
                    end
                end
                break
            end
        end

        if guild_module then
            local status = guild_module.gld()
            if status and status.illusions and (status.illusions.reps or 0) == 0 then
                break
            end
        else
            break
        end
    end

    sleep(1)
    if not item and state.shadow_item and state.shadow_container then
        inv.store_item(state.shadow_container, state.shadow_item)
    end
end

--------------------------------------------------------------------------------
-- Demon illusion
--------------------------------------------------------------------------------

function M.demon_refresh()
    -- Look for a vakra-rune stone in inventory to refresh demon duration
    for _, worn in ipairs(GameObj.inv()) do
        if worn.contents then
            for _, thing in ipairs(worn.contents) do
                if thing.name and thing.name:find("stone") then
                    local lines = util.get_lines("read #" .. thing.id, "You quickly recognize the rune")
                    for _, line in ipairs(lines) do
                        if line:find("vakra") then
                            local inv = require("inventory")
                            inv.drag(thing)
                            fput("rub #" .. thing.id)
                            inv.store_item(worn, thing)
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function M.demon_permit()
    for _, worn in ipairs(GameObj.inv()) do
        if worn.contents then
            for _, thing in ipairs(worn.contents) do
                if thing.name and thing.name:find("demon permit") then
                    return true
                end
            end
        end
    end
    return false
end

function M.demon_allowed()
    local town_result = Map.find_nearest_by_tag("town")
    if not town_result then return false end
    local rm = Room[town_result.id]
    local town = (rm and rm.location) or ""

    if town:lower():find("icemule") or town:lower():find("mist") or town:lower():find("landing") then
        return true
    elseif town:lower():find("zul") or town:lower():find("kharam") then
        if M.demon_permit() then
            return true
        else
            util.msg("yellow", "No demon permit. Please buy one and restart.")
            error("no demon permit")
        end
    else
        util.msg("yellow", "Demons are not allowed in this town.")
        error("demons not allowed here")
    end
end

function M.determine_demon()
    if not Effects.Spells.active("Minor Summoning") then
        util.msg("yellow", "No demon active. Please summon one and restart.")
        error("no demon active")
    end

    state.demon_id = nil
    local lines = util.get_lines("tell md to follow",
        "You have no minor demon at this time|You command your|is already following you")
    for _, line in ipairs(lines) do
        -- Extract demon NPC id from XML
        local id = line:match('<a exist="(%d+)" noun="')
        if id then
            state.demon_id = id
            break
        end
    end
end

function M.do_demons(place, guild_module)
    if place then M.demon_allowed() end
    M.determine_demon()

    while true do
        if not Effects.Spells.active("Minor Summoning") then
            util.msg("yellow", "No demon active. Please summon one and restart.")
            error("no demon active")
        end

        if Effects.Spells.time_left("Minor Summoning") < 0.5 then
            M.demon_refresh()
        end

        if place == "audience" then
            while not M.check_audience() do sleep(5) end
        end

        while checkmana() <= 5 do sleep(0.5) end

        local result = util.get_res(
            "illusion demon #" .. (state.demon_id or ""),
            "You shift your gaze to your|is already illusioned"
        )
        util.wait_rt()

        if result and (result:find("Piece by piece") or result:find("is already illusioned")) then
            util.wait_rt()
            while checkmana() <= 5 do sleep(0.5) end
            fput("illusion demon #" .. (state.demon_id or "") .. " dispel")
            util.wait_rt()

            if place == "audience" and guild_module then
                local status = guild_module.gld()
                if status and status.illusions then
                    local reps = status.illusions.reps or 0
                    if reps > 0 or (result and result:find("is already illusioned")) then
                        sleep(35)
                    end
                end
            end
        end

        if guild_module then
            local status = guild_module.gld()
            if status and status.illusions and (status.illusions.reps or 0) == 0 then
                break
            end
        else
            break
        end
    end
end

return M
