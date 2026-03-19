--- eforgery slab cutting module
-- Handles measuring glyphs and cutting slabs on the slab-cutter.
local M = {}

local helpers  -- set by wire()
local state    -- set by wire()

function M.wire(deps)
    helpers = deps.helpers
    state   = deps.state
end

---------------------------------------------------------------------------
-- Measure glyph to determine required block size
---------------------------------------------------------------------------

function M.measure()
    helpers.dbg("measure")
    local cmd
    if state.make_hammers then
        cmd = "measure " .. state.glyph_name
    else
        cmd = "measure my " .. state.glyph_name
    end

    local res = dothistimeout(cmd, 5, "you determine it", "What were", "You can't seem")
    if not res then
        helpers.warn("No response to measure command")
        return
    end

    local pounds = res:match("necessary to have (%d+) pounds of")
    if pounds then
        state.size = tonumber(pounds)
        helpers.info("")
        helpers.info("Your glyph requires " .. state.size .. " pound blocks.  saving info...")
        helpers.info("")
    elseif res:find("You can't seem to get a good measurement without holding the metal") then
        M.get_bar()
        M.measure()
    else
        M.get_glyph()
    end
end

---------------------------------------------------------------------------
-- Get glyph — buy or retrieve glyph, then measure
---------------------------------------------------------------------------

function M.get_glyph()
    helpers.dbg("get_glyph")
    if state.glyph_container and state.glyph_no and state.glyph_name and state.glyph_material then
        move("out")
        helpers.buy(state.glyph_no, state.glyph_material)
        helpers.you_put(state.glyph_name, state.glyph_container)
        helpers.rent()
    elseif state.glyph_container and state.glyph_name then
        helpers.rent()
    end
    if not state.size then
        M.measure()
    end
end

---------------------------------------------------------------------------
-- Get slab — retrieve raw slab or buy one
---------------------------------------------------------------------------

function M.get_slab()
    helpers.dbg("get_slab")
    if not helpers.you_get(state.material_noun, state.slab_container) then
        if not checkright("iron") then
            helpers.dbg("buying slab")
            move("out")
            helpers.buy(state.material_no)
            helpers.rent()
        end
    end
    helpers.dbg("post get_slab swap")
    fput("swap")
    matchtimeout(3, "You swap")
end

---------------------------------------------------------------------------
-- Get bar — ensure correctly-sized block in left hand
---------------------------------------------------------------------------

function M.get_bar()
    helpers.dbg("get_bar")
    if not (checkleft(state.material_noun) or checkright(state.material_noun)) then
        if not helpers.you_get(state.material_noun, state.block_container) then
            if not state.slab_container then
                error("No slab container and no blocks available")
            end
            M.get_slab()
            if not state.size then
                M.measure()
            end
            M.cut(state.size)
            if not helpers.you_get(state.material_noun, state.block_container) then
                error("No blocks after cutting")
            end
        end
    end
    -- ensure material is in left hand
    while not checkleft(state.material_noun) do
        fput("swap")
        pause(0.5)
    end
end

---------------------------------------------------------------------------
-- Cut — cut a slab into blocks of target_size
---------------------------------------------------------------------------

function M.cut(target_size, pieces)
    helpers.dbg("cut(" .. tostring(target_size) .. ", " .. tostring(pieces) .. ")")
    if not checkroom("Workshop") then
        helpers.rent()
    end

    local left, right = 0, 0
    if pieces then
        -- manual mode: cut N pieces
        for _ = 1, pieces do
            left, right = M.cut_once(target_size, left, right)
            if not left then break end
        end
    else
        -- auto mode: cut until slab is gone
        while checkleft() do
            -- estimate starting weight based on noun
            if state.material_noun and state.material_noun:find("block") then
                left = 10
            elseif state.material_noun and state.material_noun:find("bar") then
                left = 15
            elseif state.material_noun and state.material_noun:find("slab") then
                left = 25
            end
            helpers.dbg("cut: about to call cut_once(" .. target_size .. ", L: " .. left .. ", R: " .. right .. ")")
            left, right = M.cut_once(target_size, left, right)
            if not left then break end
        end
    end
    -- scrap any leftover in left hand
    if checkleft() then
        helpers.scrap(GameObj.left_hand())
    end
end

---------------------------------------------------------------------------
-- cut_once — single cut operation on the slab-cutter
---------------------------------------------------------------------------

function M.cut_once(target_size, left, right)
    helpers.dbg("cut_once(" .. target_size .. ", " .. tostring(left) .. ", " .. tostring(right) .. ")")

    if left == target_size or (left > 0 and math.floor(left / 2) < target_size) then
        -- already right size or can't get 2 pieces — store it
        helpers.you_put("left", state.block_container)
    else
        -- poke to check proposed cut sizes
        fput("poke slab-cutter")
        local line = matchtimeout(10, "You've just set", "You slide your", "You've just reset",
            "You really can't accomplish much", "too small to cut in two",
            "further adjustment will cause it to fall out")

        if not line then
            helpers.warn("No response from slab-cutter")
            return nil, nil
        end

        if line:find("reset") then
            right = math.floor(left / 2)
            left = right
        else
            local l, r = line:match("into a (%d+)lb%. piece and a (%d+)lb%. piece")
            if l and r then
                left, right = tonumber(l), tonumber(r)
                helpers.dbg(left .. " " .. right)
            elseif line:find("too small to cut in two") then
                left = 1
                right = 0
            elseif line:find("further adjustment will cause it to fall out") then
                left = 2
                right = 0
            else
                if not checkleft() then M.get_slab() end
            end
        end

        if left + right == target_size then
            -- proposed cut exactly adds up to target
            helpers.you_put("left", state.block_container)
        elseif left + right < target_size and left + right > 0 then
            -- too small to be useful
            helpers.scrap(GameObj.left_hand())
        else
            -- push cutter until we find correct size
            while left ~= target_size and right ~= target_size do
                fput("push slab-cutter")
                local push_line = matchtimeout(10, "You slide", "As you prepare to slide")
                if not push_line then break end

                local pl, pr = push_line:match("cut it into a (%d+)lb%. piece and a (%d+)lb%. piece")
                if pl and pr then
                    pl, pr = tonumber(pl), tonumber(pr)
                    if pl + pr == target_size * 2 then
                        fput("poke slab-")
                        left, right = target_size, target_size
                    else
                        left, right = pl, pr
                    end
                elseif push_line:find("further adjustment will cause it to fall out") then
                    helpers.you_put("left", state.block_container)
                    return nil, nil
                else
                    helpers.warn("Unexpected response from slab-cutter: " .. push_line)
                end
            end

            -- pull to execute the cut
            fput("pull slab-cutter")

            if left == target_size and right == target_size then
                helpers.you_put("right", state.block_container)
                helpers.you_put("left", state.block_container)
                left, right = nil, nil
            elseif right == target_size then
                helpers.you_put("right", state.block_container)
                if left < target_size then
                    helpers.scrap(GameObj.left_hand())
                    left, right = nil, nil
                end
            elseif left == target_size then
                helpers.you_put("left", state.block_container)
                if right < target_size then
                    helpers.scrap(GameObj.left_hand())
                else
                    fput("swap")
                    left = right
                    right = nil
                end
            end
        end
    end

    pause(0.5)
    return left, right
end

---------------------------------------------------------------------------
-- Prepare — ensure we have blocks or raw slabs ready
---------------------------------------------------------------------------

function M.prepare()
    helpers.dbg("prepare")
    if not helpers.you_get(state.material_noun, state.block_container) then
        if state.slab_container then
            M.get_slab()
            M.measure()
            helpers.you_put(state.material_noun, state.slab_container)
        end
    end
end

return M
