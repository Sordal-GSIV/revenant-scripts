--- Bigshot Combat Monitor — downstream hook for tracking combat state
-- Port of hunt_monitor from bigshot.lic v5.12.1
-- Watches game output for: bandits, weapon reactions, arcane reflexes,
-- smite/703/1614 tracking, archery stuck locations, bless wear-off,
-- flee messages, UAC tier/followup, rooted status, bond return, etc.

local M = {}

local hook_name = nil
local bstate = nil

---------------------------------------------------------------------------
-- Install the monitor hook
---------------------------------------------------------------------------
function M.start(name, state)
    hook_name = name .. "_monitor"
    bstate = state

    DownstreamHook.remove(hook_name)
    before_dying(function() DownstreamHook.remove(hook_name) end)

    DownstreamHook.add(hook_name, function(line)
        return M.process(line)
    end)
end

function M.stop()
    if hook_name then
        DownstreamHook.remove(hook_name)
    end
end

---------------------------------------------------------------------------
-- Process a single downstream line
---------------------------------------------------------------------------
function M.process(line)
    if not line or not bstate then return line end

    -- Bandit ambush detection
    if not bstate._bandits then
        if line:find("leaps from hiding to attack!") then
            bstate._ambusher_here = true
        elseif line:find("flies out of the shadows toward")
            or line:find("A shadowy figure leaps from hiding to attack") then
            bstate._ambusher_here = true
        end
    end

    -- Weapon reaction opportunity
    local reaction_cmd = line:match("You could use this opportunity to.-WEAPON (%S+ #%d+)")
    if reaction_cmd then
        bstate._reaction = reaction_cmd
    end

    -- Arcane reflex
    if line:find("Vital energy infuses you, hastening your arcane reflexes!") then
        bstate._arcane_reflex = true
    elseif line:find("Nature's blessing of vitality departs as your arcane prowess returns to normal") then
        bstate._arcane_reflex = false
    end

    -- Smite tracking (crimson mist → corporeal/vulnerable)
    local smite_id = line:match("crimson mist.-exist=\"(%d+)\".-corporeal plane!")
        or line:match("crimson mist.-exist=\"(%d+)\".-vulnerable!")
    if smite_id then
        bstate._smite_list = bstate._smite_list or {}
        bstate._smite_list[smite_id] = true
    end
    local unsmite_id = line:match("crimson mist.-exist=\"(%d+)\".-returns to an ethereal state")
        or line:match("crimson mist.-exist=\"(%d+)\".-appears less vulnerable")
    if unsmite_id then
        bstate._smite_list = bstate._smite_list or {}
        bstate._smite_list[unsmite_id] = nil
    end

    -- 703 (Cloak of Shadows) tracking
    local id_703 = line:match("exist=\"(%d+)\".-is suddenly surrounded by a blood red haze")
    if id_703 then
        bstate._703_list = bstate._703_list or {}
        bstate._703_list[id_703] = true
    end
    local un703 = line:match("blood red haze dissipates.-exist=\"(%d+)\"")
    if un703 then
        bstate._703_list = bstate._703_list or {}
        bstate._703_list[un703] = nil
    end

    -- 1614 (Righteous Rebuke) tracking
    local id_1614 = line:match("exist=\"(%d+)\".-your radiant aura!")
    if id_1614 then
        bstate._1614_list = bstate._1614_list or {}
        bstate._1614_list[id_1614] = true
    end
    local un1614 = line:match("exist=\"(%d+)\".-recovers from being rebuked")
    if un1614 then
        bstate._1614_list = bstate._1614_list or {}
        bstate._1614_list[un1614] = nil
    end

    -- Archery stuck location tracking
    local stuck_loc = line:match("sticks in .-'s (%S+)!")
    if stuck_loc then
        bstate._archery_stuck = bstate._archery_stuck or {}
        bstate._archery_stuck[#bstate._archery_stuck + 1] = stuck_loc
        bstate._dislodge_location = bstate._dislodge_location or {}
        bstate._dislodge_location[#bstate._dislodge_location + 1] = stuck_loc
        local dt = line:match("sticks in .-exist=\"(%d+)\"")
        if dt then bstate._dislodge_target = dt end
    end

    -- Archery aim tracking
    local aim_loc = line:match("You're now aiming at the (%S+) of")
    if aim_loc then
        bstate._archery_location = aim_loc
    elseif line:find("You're now no longer aiming at anything in particular") then
        bstate._archery_location = nil
    end

    -- Bless tracking (weapon shrugs off damage)
    local bless_id = line:match("exist=\"(%d+)\".-strikes? true.- shrugs off some of the damage!")
    if bless_id then
        bstate._bless_needed = bstate._bless_needed or {}
        bstate._bless_needed[bless_id] = true
    end
    local unbless_id = line:match("Your.-exist=\"(%d+)\".-returns? to normal%.")
    if unbless_id then
        bstate._bless_needed = bstate._bless_needed or {}
        bstate._bless_needed[unbless_id] = true
    end

    -- Room change (bolting) resets
    if line:find("^You bolt") then
        bstate._ambusher_here = false
        bstate._smite_list = {}
        bstate._aim_index = 0
        bstate._ambush_index = 0
        bstate._archery_aim_index = 0
        bstate._archery_stuck = {}
        bstate._unarmed_tier = 1
        bstate._unarmed_followup = false
        bstate._unarmed_followup_attack = ""
        bstate._703_list = {}
        bstate._1614_list = {}
        bstate._flee = false
        bstate._reaction = nil
    end

    -- Custom flee message
    local flee_msg = bstate.flee_message
    if flee_msg and flee_msg ~= "" then
        for pattern in flee_msg:gmatch("[^|]+") do
            pattern = pattern:match("^%s*(.-)%s*$")
            if pattern ~= "" and line:find(pattern) then
                bstate._flee = true
                break
            end
        end
    end

    -- UAC followup
    local followup_attack = line:match("Strike leaves foe vulnerable to a followup (%S+) attack!")
    if followup_attack then
        bstate._unarmed_followup = true
        bstate._unarmed_followup_attack = followup_attack
    end

    -- UAC tier tracking
    local tier_word = line:match("You have (%S+) positioning against")
    if tier_word then
        if tier_word == "decent" then
            bstate._unarmed_tier = 1
        elseif tier_word == "good" then
            bstate._unarmed_tier = 2
        elseif tier_word == "excellent" then
            bstate._unarmed_tier = 3
        end
    end

    -- Bond return (thrown weapon)
    if line:find("rises out of the shadows and flies back to your waiting hand!") then
        bstate._bond_return = true
    end

    -- Swift Justice charges
    local sj_up = line:match("Your Swift Justice charges are increased to (%d+)%.")
    if sj_up then bstate._swift_justice = tonumber(sj_up) end
    local sj_down = line:match("Swift Justice surges through you!.-reduced to (%d+)%.")
    if sj_down then bstate._swift_justice = tonumber(sj_down) end

    -- Rooted status
    if line:find("You don't seem to be able to move")
        or line:find("coils tightly around you, holding you in place!") then
        bstate._rooted = true
    elseif line:find("finally able to break free") then
        bstate._rooted = false
    end

    -- 902 (enchant) expired
    if line:find("stops glowing%.") then
        bstate._cast902 = true
    end
    -- 411 (enchant) expired
    if line:find("scintillating.-light surrounding the.-fades away") then
        bstate._cast411 = true
    end

    return line
end

return M
