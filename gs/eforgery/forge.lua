--- eforgery forge module
-- Glyph application, grinding, tempering (tongs), keeper/average/trash handlers, polishing
local data = require("eforgery/data")
local M = {}

local helpers  -- set by wire()
local state    -- set by wire()
local cutting  -- set by wire()

function M.wire(deps)
    helpers = deps.helpers
    state   = deps.state
    cutting = deps.cutting
end

---------------------------------------------------------------------------
-- Oil management — ensure correct oil in tempering trough
---------------------------------------------------------------------------

function M.oil()
    helpers.dbg("oil")
    waitrt()
    -- wear hammer if holding it and other hand is occupied
    if checkright("forging-hammer") and checkleft() then
        fput("wear forging")
    end

    local oil_type = data.MATERIAL_OIL[state.material_name]
    if not oil_type then
        helpers.warn("Unknown material for oil lookup: " .. tostring(state.material_name))
        return
    end

    local expected = data.OIL_TROUGH[oil_type]
    local res = dothistimeout("look in trough", 10, "In the trough")

    if res and expected and not res:find(expected) then
        -- wrong oil or empty — drain first
        if res:find("oil") or res:find("water") then
            fput("pull plug")
            -- stow any oil that ends up in hands
            if state.oil_container and (checkright("oil") or checkleft("oil")) then
                helpers.you_put("oil", state.oil_container)
            elseif checkright("oil") then
                helpers.empty_right_hand()
            elseif checkleft("oil") then
                helpers.empty_left_hand()
            end
        end

        if oil_type ~= "water" then
            if helpers.you_get(oil_type, state.oil_container) then
                while checkright("oil") or checkleft("oil") do
                    fput("pour oil in trough")
                end
            elseif state.oil_container then
                M.buy_oil()
            else
                helpers.warn("No oil container set. Run ;eforgery setup.")
                error("No oil container")
            end
        else
            fput("get bucket")
            waitrt()
        end
    end
end

---------------------------------------------------------------------------
-- Buy oil — purchase oil from merchant
---------------------------------------------------------------------------

function M.buy_oil()
    helpers.dbg("buy_oil")
    waitrt()
    if checkright("forging-hammer") and checkleft() then
        fput("wear forging")
    end
    multimove("go door", "out")
    if state.oil_container then
        helpers.you_put("slab", state.block_container)
        local oil_type = data.MATERIAL_OIL[state.material_name]
        helpers.buy(data.OIL_ORDER[oil_type])
        helpers.you_put("oil", state.oil_container)
        helpers.clear_note()
        helpers.you_get("slab", state.block_container)
        fput("swap")
        helpers.rent()
        move("go door")
    else
        helpers.warn("No oil container set. Run ;eforgery setup.")
        error("No oil container")
    end
end

---------------------------------------------------------------------------
-- Salvage oil — drain trough and save remaining oil at session end
---------------------------------------------------------------------------

function M.salvage_oil()
    helpers.dbg("salvage_oil")
    local res = dothistimeout("look in trough", 10, "In the trough")
    if res and res:find("oil") then
        fput("pull plug")
        if state.oil_container and (checkright("oil") or checkleft("oil")) then
            helpers.you_put("oil", state.oil_container)
        elseif checkright("oil") then
            helpers.empty_right_hand()
        elseif checkleft("oil") then
            helpers.empty_left_hand()
        end
    end
end

---------------------------------------------------------------------------
-- Glyph — apply glyph to material, then route to grind or tongs
---------------------------------------------------------------------------

function M.glyph()
    helpers.dbg("glyph")
    waitrt()
    if state.make_hammers then
        fput("stare " .. state.glyph_name)
    else
        fput("stare my " .. state.glyph_name)
    end

    local done = false
    while not done do
        local line = get()

        if line:find("Your left hand is empty") then
            done = true
            waitrt()
            fput("swap")
            local swap_result = matchtimeout(3, "swap")
            if swap_result and swap_result:find("have anything to swap") then
                cutting.get_bar()
            end

        elseif line:find("grinder that may suit") then
            done = true
            waitrt()
            M.grind()

        elseif line:find("door to the forging chamber") then
            done = true
            waitrt()
            M.tongs()

        elseif line:find("has already been worked on") and (line:find("cannot be scribed") or line:find("It cannot be scribed")) then
            done = true
            waitrt()
            M.tongs()

        elseif line:find("Roundtime:") then
            -- glyph degraded or ambiguous — determine machine manually
            done = true
            waitrt()
            if state.make_hammers then
                M.grind()
            elseif checkleft() == "block" then
                M.grind()
            else
                local lh = GameObj.left_hand()
                if lh and (lh.noun == "slab" or lh.noun == "bar") and
                   lh.name and (lh.name:find("haft") or lh.name:find("handle") or lh.name:find("hilt") or lh.name:find("shaft")) then
                    M.grind()
                elseif checkleft("slab") or checkleft("bar") then
                    M.tongs()
                else
                    helpers.info("Please report what you're forging; the script cannot determine the machine to use.")
                end
            end

        elseif line:find("realize it is too small") then
            done = true
            waitrt()
            helpers.trash(checkleft() or "left")

        elseif line:find("What were you referring to") or line:find("You stare at nothing in particular") then
            done = true
            waitrt()
            helpers.you_put(state.material_noun, state.block_container)
            cutting.get_glyph()

        elseif line:find("The material in your left hand is not in a form that the glyph will work on") then
            done = true
            waitrt()
            helpers.warn("Something unexpected is in your left hand.")
            helpers.empty_left_hand()
            cutting.get_bar()
            M.glyph()
        end
    end
end

---------------------------------------------------------------------------
-- Grind — turn the grinder and handle results
---------------------------------------------------------------------------

function M.grind()
    helpers.dbg("grind")
    if checkright("forging-hammer") then
        fput("wear forging")
    end
    if state.surge and Spell[9605] and Spell[9605].timeleft < 1 then
        helpers.use_surge()
    end
    waitrt()
    fput("turn grinder")
    local line = matchtimeout(30, "doesn't budge", "Resignedly", "you need to hold it in your",
        "satisfied with the piece", "vindictive", "very best")
    waitrt()

    if not line then
        helpers.warn("No response from grinder")
        return
    end

    -- AFK check (skip if rent expired)
    if state.afk and not line:find("doesn't budge") then
        M.afk_wait()
    end

    if line:find("doesn't budge") then
        -- rent expired
        helpers.you_put(state.material_noun, state.block_container)
        move("out")
        helpers.rent()

    elseif line:find("Resignedly") then
        state.failures = state.failures + 1
        state.reps = state.reps + 1
        M.glyph()

    elseif line:find("you need to hold it in your") then
        fput("swap")

    elseif line:find("very best") then
        state.reps = state.reps + 1
        if state.rank then
            helpers.trash(checkleft() or "left")
        else
            M.keeper()
        end
        if checkright(state.material_noun) then
            helpers.scrap(GameObj.right_hand())
        end

    elseif line:find("satisfied with the piece") then
        state.reps = state.reps + 1
        if state.rank then
            helpers.trash(checkleft() or "left")
        else
            M.average()
        end
        if checkright(state.material_noun) then
            helpers.scrap(GameObj.right_hand())
        end

    elseif line:find("vindictive") then
        state.reps = state.reps + 1
        state.major_failures = state.major_failures + 1
        helpers.trash(checkleft() or "left")
        if checkright(state.material_noun) then
            helpers.scrap(GameObj.right_hand())
        end
    end
end

---------------------------------------------------------------------------
-- Tongs — tempering loop in forge chamber
---------------------------------------------------------------------------

function M.tongs()
    helpers.dbg("tongs")
    waitrt()
    move("go door")
    M.oil()

    local done = false
    while not done do
        if state.surge and Spell[9605] and Spell[9605].timeleft < 1 then
            helpers.use_surge()
        end
        helpers.hammer_time()
        fput("get tongs")
        local line = matchtimeout(30,
            "tempering trough is empty",
            "will be ruined if you try to set the temper with",
            "tongs on the anvil",
            "tongs to the anvil",
            "need to be holding",
            "material you want to work",
            "expired",
            "has not been scribed",
            "hanging crystal and spreads",
            "into the tempering trough",
            "anvil as you shake your head",
            "hammer in your right",
            "this would be a real waste",
            "best work")

        helpers.dbg(line or "(no match)")
        waitrt()

        if not line then
            helpers.info("No response — retrying")
            goto continue
        end

        -- AFK check on certain results
        if state.afk and (line:find("best work") or line:find("into the tempering trough")
            or line:find("hanging crystal") or line:find("tongs on the anvil")
            or line:find("tongs to the anvil") or line:find("anvil as you shake your head")) then
            M.afk_wait()
        end

        if line:find("need to be holding") or line:find("material you want to work") then
            error("Missing material or tongs — cannot continue")

        elseif line:find("this would be a real waste") or line:find("will be ruined") or line:find("trough is empty") then
            M.oil()

        elseif line:find("hammer in your right") then
            helpers.hammer_time()

        elseif line:find("tongs to the anvil") or line:find("has not been scribed") then
            done = true
            move("go door")
            fput("wear my forging")
            M.glyph()

        elseif line:find("expired") then
            multimove("go door", "out")
            helpers.rent()
            move("go door")

        elseif line:find("best work") then
            state.reps = state.reps + 1
            done = true
            fput("wear my forging")
            move("go door")
            if state.rank then
                helpers.trash(checkleft() or "left")
            else
                M.keeper()
            end

        elseif line:find("into the tempering trough") then
            state.reps = state.reps + 1
            done = true
            fput("wear my forging")
            move("go door")
            if state.rank then
                helpers.trash(checkleft() or "left")
            else
                M.average()
            end

        elseif line:find("hanging crystal and spreads") then
            state.reps = state.reps + 1
            state.failures = state.failures + 1
            fput("wear my forging")
            move("go door")
            helpers.trash(checkleft() or "left")
            done = true

        else
            state.reps = state.reps + 1
        end

        ::continue::
    end

    -- safety: if not already in main room, ensure apron worn
    if not (line and (line:find("hanging crystal") or line:find("into the tempering trough")
        or line:find("best work") or line:find("tongs to the anvil"))) then
        fput("wear forging")
        move("go door")
    end
end

---------------------------------------------------------------------------
-- Keeper — store perfect piece
---------------------------------------------------------------------------

function M.keeper()
    helpers.dbg("keeper")
    if state.safe_keepers then
        fput("mark my " .. (checkleft() or "left"))
    end
    state.keepers = state.keepers + 1
    if state.keeper_container then
        helpers.you_put(checkleft() or "left", state.keeper_container)
    else
        helpers.warn("No keeper container set! Aborting...")
        helpers.info("Deal with your keeper, then run ;eforgery setup to set the keeper container.")
        error("No keeper container")
    end
    M.print_stats()
end

---------------------------------------------------------------------------
-- Average — store average piece
---------------------------------------------------------------------------

function M.average()
    helpers.dbg("average")
    state.successes = state.successes + 1
    if state.average_container then
        helpers.you_put(checkleft() or "left", state.average_container)
    else
        helpers.trash(checkleft() or "left")
    end
    M.print_stats()
end

---------------------------------------------------------------------------
-- Polish — polish rough pieces in keeper container
---------------------------------------------------------------------------

function M.polish()
    helpers.dbg("polish")
    if not state.keeper_container then return end

    local container = nil
    for _, item in ipairs(GameObj.inv()) do
        if item.noun and item.noun:find(state.keeper_container) then
            container = item
            break
        end
    end
    if not container or not container.contents then return end

    for _, item in ipairs(container.contents) do
        if item.name and (item.name:find("rough") or item.name:find("polished"))
            and item.noun and item.noun:find("-")
            and (not item.type or item.type == "uncommon") then
            helpers.info("It looks like " .. item.name .. " needs polishing.")

            if not checkroom("Workshop") then
                move("go door")
            end
            fput("get #" .. item.id .. " from #" .. container.id)
            fput("swap")
            fput("lean polisher")
            local line = matchtimeout(30, "rent on this workshop has expired",
                "You give the polishing wheel a shove")
            waitrt()
            if line and line:find("rent on this workshop has expired") then
                move("out")
                helpers.rent()
                fput("lean polisher")
                matchtimeout(60, "You straighten up from working at the polishing wheel")
            elseif line and line:find("You give the polishing wheel a shove") then
                matchtimeout(60, "You straighten up from working at the polishing wheel")
            end
            waitrt()
            fput("_drag #" .. item.id .. " #" .. container.id)
        end
    end
    pause(1)
end

---------------------------------------------------------------------------
-- AFK wait
---------------------------------------------------------------------------

function M.afk_wait()
    helpers.dbg("afk_wait")
    if state.reps > 0 and state.afk_count and state.afk_count > 0 and state.reps % state.afk_count == 0 then
        helpers.warn("")
        helpers.warn("Waiting on user input. ;unpause eforgery to continue.")
        helpers.warn("")
        Script.pause()
    end
end

---------------------------------------------------------------------------
-- Forge — main forge action (get_bar + glyph)
---------------------------------------------------------------------------

function M.forge()
    helpers.dbg("forge")
    cutting.get_bar()
    M.glyph()
end

---------------------------------------------------------------------------
-- Breakdown — cleanup at session end
---------------------------------------------------------------------------

function M.breakdown()
    helpers.dbg("breakdown")
    if checkroom("Forge") then
        M.salvage_oil()
    end
    M.print_stats()
end

---------------------------------------------------------------------------
-- Print stats
---------------------------------------------------------------------------

function M.print_stats()
    helpers.info("eforgery session stats:")
    helpers.info("  Best pieces:    " .. state.keepers)
    helpers.info("  Average pieces: " .. state.successes)
    helpers.info("  Minor failures: " .. state.failures)
    helpers.info("  Major failures: " .. state.major_failures)
end

return M
