-- huntpro/loot.lua — Looting, skinning, encumbrance management
-- @revenant-script
-- @lic-certified: complete 2026-03-18
-- Original: huntpro.lic by Jara — loot_script, cock_support, wand management,
-- boost_loot, collectible, poolparty, sell_shells (lines ~2090-2118, 6400-6780)

local Loot = {}

---------------------------------------------------------------------------
-- Run the user's configured loot script on dead targets
---------------------------------------------------------------------------
function Loot.run_loot(hp)
    waitrt()

    -- Switch to guarded stance for looting
    local Combat = require("gs.huntpro.combat")
    Combat.stance_guarded(hp)

    -- Check if loot script is already running
    local loot_script = hp.loot_script or "eloot"
    if Script.running(loot_script) then return end

    local dead = GameObj.dead and GameObj.dead() or {}
    if #dead < 1 then return end

    -- Stow wands if using them
    if hp.combat_wands and hp.use_wands then
        Loot.put_wand(hp)
    end

    -- Run the loot script
    Script.run(loot_script)
    wait_while(function() return Script.running(loot_script) end)

    -- Restore aim if it was changed
    if hp.aim_fail and hp.aim_fail ~= 0 then
        waitrt()
        if hp.current_aim == "0" then
            fput("aim clear")
        else
            fput("aim " .. hp.current_aim)
        end
        hp.aim_fail = 0
    end

    -- Get wands back
    if hp.combat_wands and hp.use_wands then
        Loot.get_wands(hp)
    end

    -- Cock ranged weapon
    Loot.cock_support(hp)
end

---------------------------------------------------------------------------
-- Cock support for ranged weapons (styles 7-8)
---------------------------------------------------------------------------
function Loot.cock_support(hp)
    if not hp.use_cock then return end
    if hp.cock_block then return end

    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets > 0 then return end

    waitrt()
    local lh = GameObj.left_hand()
    if lh then
        fput("cock " .. lh.noun)
        hp.cock_block = true
    end
end

---------------------------------------------------------------------------
-- Wand management — get wand from container
---------------------------------------------------------------------------
function Loot.get_wands(hp)
    if not hp.use_wands then return end

    -- Try to get a wand from inventory
    local result = dothistimeout("get my wand", 3, "Get what", "You remove")
    if result and result:find("Get what") then
        -- No wands available
        hp.current_wand_name = nil
    end
end

---------------------------------------------------------------------------
-- Wand management — put wand away
---------------------------------------------------------------------------
function Loot.put_wand(hp)
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()

    if rh and rh.noun == "wand" then
        fput("stow my wand")
    end
    if lh and lh.noun == "wand" then
        fput("stow my wand")
    end
end

---------------------------------------------------------------------------
-- Activate wands in combat (wave at target)
---------------------------------------------------------------------------
function Loot.use_wands(hp, target_name)
    if not hp.current_wand_name then
        Loot.get_wands(hp)
    end
    if not hp.current_wand_name then return end

    local wand_noun = hp.current_wand_noun or "wand"
    local target = target_name or "target"

    local result = dothistimeout("wave my " .. wand_noun .. " at " .. target, 3,
        "Cast Roundtime", "You wave to a", "What were you referring")

    if result then
        if result:find("Cast Roundtime") then
            -- Wand worked
        elseif result:find("You wave to a") or result:find("What were you referring") then
            hp.current_wand_name = nil
        else
            -- Dead wand — dispose
            Loot.dispose_wand(hp)
        end
    end
end

---------------------------------------------------------------------------
-- Dispose of dead wand
---------------------------------------------------------------------------
function Loot.dispose_wand(hp)
    local wand_noun = hp.current_wand_noun or "wand"

    if hp.dead_wands and hp.dead_wands ~= "0" then
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if rh and rh.noun == wand_noun then
            fput("put my " .. wand_noun .. " in my " .. hp.dead_wands)
        elseif lh and lh.noun == wand_noun then
            fput("put my " .. wand_noun .. " in my " .. hp.dead_wands)
        end
    else
        -- No dead wand container — drop
        local rh = GameObj.right_hand()
        if rh and rh.noun == wand_noun then
            fput("drop right")
        end
        local lh = GameObj.left_hand()
        if lh and lh.noun == wand_noun then
            fput("drop left")
        end
    end

    hp.current_wand_name = nil
end

---------------------------------------------------------------------------
-- Boost loot activation
---------------------------------------------------------------------------
function Loot.boost_loot(hp)
    if not hp.boost_loot or hp.boost_loot == "0" then return end

    if hp.boost_loot == "minor" then
        if not Spell.active_p(9101) then
            waitrt()
            fput("boost loot minor")
        end
    elseif hp.boost_loot == "major" then
        if not Spell.active_p(9100) then
            waitrt()
            fput("boost loot major")
        end
    end
end

return Loot
