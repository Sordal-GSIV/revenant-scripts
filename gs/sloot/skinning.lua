--- sloot/skinning.lua
-- Skinning: prepare_skinner, skin_critter, finish_skinner, stand_up.
-- Mirrors skinning procs from sloot.lic v3.5.2.

local sacks_mod = require("sloot/sacks")
local items_mod = require("sloot/items")

local M = {}

-- Internal skinning state
local skin_prepared      = false
local skin_empty_hands   = false
local skinweapon         = nil
local skinweaponblunt    = nil
local skinweaponcurrent  = nil
local prev_stance        = "defensive"

local SKIN_RX = Regex.new("skinned|botched|already been|cannot skin|must be a member|can only skin|You are unable to break through|You break through the crust|You crack open a portion")
local STANCE_RX = Regex.new("^You are now in an? (\\w+) stance|You move into")

function M.set_prev_stance(s)
    prev_stance = s or "defensive"
end

--- Switch stance (retry until matched or already at target).
function M.change_stance(target)
    if target == prev_stance then return end
    -- Defensive = stance value 0; keep retrying until there
    while true do
        local cur = checkstance()
        if cur == target then break end
        -- defensive and already <= 80 (original Ruby logic: "defensive" and checkstance 80)
        if target == "defensive" and type(cur) == "number" and cur <= 80 then break end
        local res = dothistimeout("stance " .. target, 2, STANCE_RX)
        if res then
            local rt_match = res:match("Roundtime: (%d+)") or res:match("wait (%d+)")
            if rt_match then
                pause(tonumber(rt_match) - 1)
            end
        end
        local new_cur = checkstance()
        if new_cur == target then break end
        if target == "defensive" then break end -- best effort
    end
    prev_stance = target
end

--- True if safe to kneel/stance (no live NPCs, or safe mode off).
local function safe_to_enhance(settings)
    if not settings.enable_skin_safe_mode then return true end
    for _, npc in ipairs(GameObj.npcs()) do
        if npc.status ~= "dead" then return false end
    end
    return true
end

--- Prepare for skinning a critter (spells, stance, kneel, weapon).
function M.prepare_skinner(critter, settings)
    if not critter then return end
    local sacks = sacks_mod.sacks
    -- Skip if in exclude list
    local skip_list = settings.skin_exclude or {}
    for _, nm in ipairs(skip_list) do
        if critter.name == nm then return end
    end
    if skin_prepared then return end
    if not settings.enable_skinning then return end

    -- Sigil of Resolve (9704)
    if Spell.known(9704) and Spell.affordable(9704) and not Spell.active(9704)
       and settings.enable_skin_sigil then
        Spell.cast(9704)
    end

    -- Skinning spell (604)
    if Spell.known(604) and Spell.affordable(604) and settings.enable_skin_604 then
        while not Spell.active(604) do
            Spell.cast(604)
        end
    end

    -- Alternate weapon
    if settings.enable_skin_alternate then
        if Regex.test(critter.name, "krag dweller|greater krynch|massive boulder") then
            empty_hands()
            skin_empty_hands = true
        else
            items_mod.free_hand(settings)
        end

        -- Choose regular or blunt weapon based on critter type
        skinweaponcurrent = skinweapon
        local blunt_name = UserVars["skinweaponblunt"] or ""
        if Regex.test(critter.name, "krynch|spiked cavern urchin|krag dweller|stone mastiff|gargoyle|massive boulder")
           and blunt_name ~= "" then
            skinweaponcurrent = skinweaponblunt
        end

        if skinweaponcurrent then
            if not items_mod.get_item(skinweaponcurrent, sacks["skinweapon"]) then
                echo("[SLoot] ** failed to find skin weapon in sack")
            end
        end
    else
        if Regex.test(critter.name, "krag dweller|greater krynch|massive boulder") then
            items_mod.free_hand(settings)
        end
    end

    if safe_to_enhance(settings) then
        if settings.enable_skin_kneel then
            while not checkkneeling() do
                dothistimeout("kneel", 5, Regex.new("^You kneel down\\.?$|^You move to|^You are already kneeling\\.?$"))
            end
        end
        if settings.enable_skin_offensive then
            M.change_stance("offensive")
        end
    end

    skin_prepared = true
end

--- Stand up after skinning.
local function stand_up(settings)
    local verb = settings.skin_stand_verb or ""
    if verb == "" then
        while not standing() do
            dothistimeout("stand", 5, Regex.new("^You stand back up\\.?$"))
        end
    else
        while not standing() do
            fput(verb)
        end
    end
end

--- Finish skinning (restore stance, stand, stow weapon).
function M.finish_skinner(settings)
    if not skin_prepared then return end
    if not settings.enable_skinning then return end

    if settings.enable_skin_stance_first then
        M.change_stance(prev_stance)
        stand_up(settings)
    else
        stand_up(settings)
        M.change_stance(prev_stance)
    end

    -- Stow alternate skin weapon
    if settings.enable_skin_alternate and skinweaponcurrent then
        local sacks = sacks_mod.sacks
        local wsack_name = UserVars["skinweaponsack"] or ""
        local wsack = wsack_name ~= "" and GameObj.find_inv(wsack_name) or sacks["skinweapon"]
        if wsack then
            if not items_mod.put_item(skinweaponcurrent, wsack) then
                echo("[SLoot] failed to stow skin weapon")
            end
        end
    end

    if skin_empty_hands then
        fill_hands()
        skin_empty_hands = false
    end

    skin_prepared = false
end

--- Skin one critter. Handle gem-from-crust extraction.
function M.skin_critter(critter, settings)
    if not critter then return end
    local sacks = sacks_mod.sacks
    local skip_list = settings.skin_exclude or {}
    for _, nm in ipairs(skip_list) do
        if critter.name == nm then return end
    end

    local cmd = "skin #" .. critter.id
    -- With alternate weapon in hand
    local lh = GameObj.left_hand()
    if skinweaponcurrent and lh and lh.name:lower():find((skinweaponcurrent.noun or ""):lower()) then
        cmd = cmd .. " with #" .. lh.id
    end

    local res = dothistimeout(cmd, 5, SKIN_RX)
    if not res then return end

    if Regex.test(res, "^You cannot skin") then
        skip_list[#skip_list + 1] = critter.name
    elseif Regex.test(res, "You break through the crust of the .+ and withdraw |You crack open a portion of the .+ and uncover ") then
        -- Gem dropped into hand — stow it
        local gemsack = sacks["gem"]
        if gemsack then
            local rh = GameObj.right_hand()
            local lh2 = GameObj.left_hand()
            local gem = (rh and rh.noun == "gem" and rh) or (lh2 and lh2.noun == "gem" and lh2)
            if gem then
                items_mod.put_item(gem, gemsack)
            end
        end
    end
end

--- Load skin weapon references from sack (called at startup when alternate skinning enabled).
function M.load_skin_weapons(settings)
    if not settings.enable_skin_alternate then return end
    local sacks = sacks_mod.sacks
    local wsack = sacks["skinweapon"]
    if not wsack then
        echo("** skinning is enabled but I could not find your skin weapon sack")
        error("missing skinweapon sack")
    end

    -- Ensure we can see sack contents
    if not wsack.contents then
        fput("look in #" .. wsack.id)
    end

    local sw_name = UserVars["skinweapon"] or ""
    local swb_name = UserVars["skinweaponblunt"] or ""

    for _, obj in ipairs(wsack.contents or {}) do
        if sw_name ~= "" and obj.name:lower():find(sw_name:lower()) then
            skinweapon = obj
        end
        if swb_name ~= "" and obj.name:lower():find(swb_name:lower()) then
            skinweaponblunt = obj
        end
    end

    if not skinweapon then
        echo("** skinning is enabled but I could not find your skin weapon")
    end
    if not skinweaponblunt then
        skinweaponblunt = skinweapon
    end
end

return M
