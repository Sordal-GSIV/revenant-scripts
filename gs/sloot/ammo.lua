--- sloot/ammo.lua
-- Ammo gathering with bundle tracking.
-- Mirrors gather_ammo proc and get_bundle_details proc from sloot.lic v3.5.2.

local settings_mod = require("sloot/settings")

local M = {}

-- Persistent bundle tracking (like $sloot_bundles in Lich5)
local sloot_bundles = {}

--- Get strength/durability/name details from an ammo bundle.
-- @param bundle  GameObj for a bundle
-- @returns table with id, strength, durability, name
local function get_bundle_details(bundle)
    local details = { id = bundle.id }

    fput("look at #" .. bundle.id)
    local deadline = os.clock() + 5
    while os.clock() < deadline do
        local line = get_noblock()
        if not line then pause(0.1) else
            local str, dur = line:match("a strength of (%d+) and a durability of (%d+)")
            if str then
                details.strength    = tonumber(str)
                details.durability  = tonumber(dur)
            end
            local nm = line:match('Each individual projectile will be "([^"]+)"')
            if nm then
                details.name = nm
                break
            end
        end
    end
    return details
end

--- Gather ammo from the ground and bundle it appropriately.
function M.gather_ammo(settings)
    if not settings.enable_gather then return end

    local ammo_name = (settings.ammo_name or ""):match("^%s*(.-)%s*$")
    if ammo_name == "" then
        echo("[SLoot] failed to gather: you must specify the ammo name")
        return
    end

    local ammosack_name = settings_mod.uvar_get("ammosack")
    if ammosack_name == "" then
        echo("[SLoot] failed to gather: you must specify an ammo container")
        return
    end

    local quiver = GameObj.find_inv(ammosack_name)
    if not quiver then
        echo("[SLoot] failed to gather: ammo container not found")
        return
    end

    -- Detect ammo noun from ammo_name
    local ammo_noun = nil
    for _, noun in ipairs({ "bolt", "arrow", "dart" }) do
        if ammo_name:find(noun) then
            ammo_noun = noun
            break
        end
    end
    if not ammo_noun then
        echo("[SLoot] failed to gather: unknown arrow noun")
        return
    end

    -- Refresh bundle tracking — remove bundles no longer in quiver
    local quiver_contents = quiver.contents or {}
    local quiver_ids = {}
    for _, obj in ipairs(quiver_contents) do quiver_ids[obj.id] = true end
    local new_bundles = {}
    for _, sb in ipairs(sloot_bundles) do
        if quiver_ids[sb.id] then
            new_bundles[#new_bundles + 1] = sb
        end
    end
    sloot_bundles = new_bundles

    -- Record any new bundles in the quiver
    for _, obj in ipairs(quiver_contents) do
        if obj.type == "ammo" and obj.name:lower():find("bundle") then
            local already = false
            for _, sb in ipairs(sloot_bundles) do
                if sb.id == obj.id then already = true; break end
            end
            if not already then
                sloot_bundles[#sloot_bundles + 1] = get_bundle_details(obj)
            end
        end
    end

    -- Find ammo on the ground
    local ammo_on_ground = {}
    for _, obj in ipairs(GameObj.loot()) do
        if obj.type == "ammo" and obj.name:lower():find(ammo_name:lower()) then
            ammo_on_ground[#ammo_on_ground + 1] = obj
        end
    end

    if #ammo_on_ground > 0 then
        local res = dothistimeout("gather " .. ammo_noun, 2, Regex.new("The bolt is out of your reach\\.|You gather|You pick up"))
        if res and Regex.test(res, "You gather") then
            wait_until(function()
                local rh = GameObj.right_hand()
                return rh and rh.id ~= nil
            end)
        end
    end

    -- Put gathered ammo into matching bundle
    local rh = GameObj.right_hand()
    if rh then
        if rh.name:lower():find(ammo_noun .. "s") then
            local details = get_bundle_details(rh)
            for _, bundle in ipairs(sloot_bundles) do
                if bundle.name == details.name then
                    fput("put #" .. details.id .. " in #" .. bundle.id)
                    return
                end
            end
        elseif rh.name:lower():find(ammo_name:lower()) then
            for _, bundle in ipairs(sloot_bundles) do
                if bundle.name and rh.name:lower():find(bundle.name:lower()) then
                    fput("put #" .. rh.id .. " in #" .. bundle.id)
                    return
                end
            end
        end
    end
end

return M
