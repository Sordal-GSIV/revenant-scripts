--- @module blackarts.inventory
-- Inventory management. Ported from BlackArts::Inventory (BlackArts.lic v3.12.x)

local state = require("state")
local util  = require("util")

local M = {}

-- Pre-compiled regexes set during init
local GET_RX = Regex.new(
    "^You (?:shield the opening|discreetly |carefully |deftly |slowly )?(?:remove|draw|grab|reach|slip|tuck|retrieve|already have|unsheathe|detach|swap|sling)" ..
    "|^Get what\\?" ..
    "|^Why don't you leave some for others" ..
    "|^You need a free hand" ..
    "|^You already have" ..
    "|^You take" ..
    "|Reaching over your shoulder" ..
    "|^As you draw" ..
    "|^Ribbons of.*?light" ..
    "|^An eclipse of spectral moths" ..
    "|^You aren't assigned that task"
)

local PUT_RX = Regex.new(
    "^(?:You carefully (?:add|hang|secure))" ..
    "|^(?:You (?:put|(?:discreetly )?tuck|attach|toss|place|.*? place|slip|wipe off the blade|absent-mindedly drop|find an incomplete bundle|untie your drawstring))" ..
    "|^The .+ is already a bundle" ..
    "|^Your bundle would be too large" ..
    "|^The .+ is too large to be bundled" ..
    "|If you wish to continue, throw the item away" ..
    "|you feel pleased with yourself at having cleaned" ..
    "|over your shoulder" ..
    "|two items in that location" ..
    "|wear three functional items" ..
    "|^Your .*? won't fit"
)

--------------------------------------------------------------------------------
-- Return all contents across the herb, reagent, and default sacks
--------------------------------------------------------------------------------

function M.all_sack_contents()
    local all = {}
    local seen = {}
    for _, sack_name in ipairs({"herb", "reagent", "default"}) do
        local sack = state.sacks[sack_name]
        if sack and sack.contents then
            for _, item in ipairs(sack.contents) do
                if not seen[item.id] then
                    seen[item.id] = true
                    all[#all + 1] = item
                end
            end
        end
    end
    return all
end

--------------------------------------------------------------------------------
-- Return contents of default/reagent sacks only (for buy-from-shop checks)
--------------------------------------------------------------------------------

function M.bags_to_check()
    local herb_id    = state.sacks["herb"]    and state.sacks["herb"].id    or nil
    local default_id = state.sacks["default"] and state.sacks["default"].id or nil
    local reagent_id = state.sacks["reagent"] and state.sacks["reagent"].id or nil

    -- All the same bag — return nil (check all_sack_contents instead)
    if herb_id == default_id and default_id == reagent_id then return nil end

    local contents = {}
    local seen = {}

    if default_id and default_id ~= herb_id then
        local s = state.sacks["default"]
        if s and s.contents then
            for _, item in ipairs(s.contents) do
                if not seen[item.id] then seen[item.id] = true; contents[#contents + 1] = item end
            end
        end
    end
    if reagent_id and reagent_id ~= herb_id and reagent_id ~= default_id then
        local s = state.sacks["reagent"]
        if s and s.contents then
            for _, item in ipairs(s.contents) do
                if not seen[item.id] then seen[item.id] = true; contents[#contents + 1] = item end
            end
        end
    end

    return #contents > 0 and contents or nil
end

--------------------------------------------------------------------------------
-- Free one or both hands
--------------------------------------------------------------------------------

function M.free_hands(opts)
    opts = opts or {}
    if (opts.right or opts.both) and GameObj.right_hand() and GameObj.right_hand().id then
        fput("stow right")
        sleep(0.2)
    end
    if (opts.left or opts.both) and GameObj.left_hand() and GameObj.left_hand().id then
        fput("stow left")
        sleep(0.2)
    end
end

function M.free_hand()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if (rh and rh.id) and (lh and lh.id) then
        M.free_hands({ right = true })
    end
end

--------------------------------------------------------------------------------
-- Drag an item into a free hand
--------------------------------------------------------------------------------

function M.drag(item)
    if not item or not item.id then return false end
    local rh = GameObj.right_hand()
    local to = (rh and rh.id) and "left" or "right"
    local res = dothistimeout(string.format("_drag #%s %s", item.id, to), 5, GET_RX)
    if not res then return false end
    sleep(0.2)
    return true
end

-- Like drag but uses single_drag (no target hand choice — left if possible)
function M.single_drag(item)
    if not item or not item.id then return false end
    -- Try right, then left
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh and rh.id and lh and lh.id then
        M.free_hand()
    end
    return M.drag(item)
end

--------------------------------------------------------------------------------
-- Store an item into a container
--------------------------------------------------------------------------------

function M.store_item(bag, item)
    if not bag or not item or not item.id then return false end
    util.get_res(string.format("_drag #%s #%s", item.id, bag.id), PUT_RX)
    sleep(0.2)
    return true
end

--------------------------------------------------------------------------------
-- Open a sack by role name and look inside it
--------------------------------------------------------------------------------

function M.open_container(sack_name)
    local sack = state.sacks[sack_name]
    if not sack or not sack.id then return end
    dothistimeout(string.format("look in #%s", sack.id), 5,
        Regex.new("In the|There is nothing|you glance"))
    sleep(0.3)
end

function M.open_single_container(sack_name)
    M.open_container(sack_name)
end

--------------------------------------------------------------------------------
-- Initialise sacks from the stow-list system
--------------------------------------------------------------------------------

function M.init_sacks()
    fput("stow list")
    sleep(1)
    for _, stype in ipairs({"default", "herb", "reagent"}) do
        local sack_var = UserVars[stype .. "sack"]
        if sack_var and sack_var ~= "" then
            local found = GameObj.find_inv(sack_var)
            if found then
                state.sacks[stype] = found
            end
        end
    end
    for _, stype in ipairs({"default", "herb", "reagent"}) do
        if state.sacks[stype] then
            M.open_container(stype)
        end
    end
end

return M
