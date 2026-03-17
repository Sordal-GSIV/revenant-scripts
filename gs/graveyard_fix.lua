--- @revenant-script
--- name: graveyard_fix
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Override graveyard bronze gate wayto/timeto to always PUSH instead of relying on spells alone
--- tags: graveyard,gate,navigation,map-fix
---
--- Patches the map database so the bronze gate in the graveyard is navigated
--- via PUSH when spells are unavailable. Run once per session.

echo("Graveyard gate set to always PUSH!!")

-- Room UIDs
local gate_outside_ids = Map.ids_from_uid(18002)
local gate_climb_ids   = Map.ids_from_uid(18062)
local gate_inside_ids  = Map.ids_from_uid(18003)

if not gate_outside_ids or not gate_outside_ids[1] then
    echo("graveyard_fix: could not resolve UID 18002")
    return
end

local outside = gate_outside_ids[1]
local climb   = gate_climb_ids and gate_climb_ids[1]
local inside  = gate_inside_ids and gate_inside_ids[1]

-- Patch: outside -> climb (go gate, else climb)
if climb then
    local room = Room[outside]
    if room then
        room.timeto[tostring(climb)] = function()
            if (Skills.climbing or 0) >= math.max(GameState.encumbrance / 1.25, 101) then
                return 3.0
            end
            return nil
        end
        room.wayto[tostring(climb)] = function()
            local result = dothistimeout("go bronze gate", 5,
                { "The bronze gate appears to be closed", "Obvious paths", "Obvious exits" })
            if result and result:find("Obvious") then
                return true
            else
                empty_hands()
                move("climb gate")
            end
        end
    end
end

-- Spell list for gate-opening
local SPELL_LIST = { 407, 1604, 304, 1207 }

local function gate_push_wayto(success_re)
    return function()
        local cast_attempted = false
        while true do
            local result = dothistimeout("go bronze gate", 5,
                { "The bronze gate appears to be closed", "Obvious paths", "Obvious exits", "none" })
            if result and result:find("Obvious") then
                break
            end

            -- Try a spell first
            local spell_num = nil
            for _, num in ipairs(SPELL_LIST) do
                if Spell[num] and Spell[num].known then
                    spell_num = num
                    break
                end
            end

            if spell_num and not cast_attempted then
                cast_attempted = true
                local spell = Spell[spell_num]
                if not spell:affordable() then break end
                spell:cast("bronze gate")
            else
                empty_hands()
                dothistimeout("push bronze gate", 16, {
                    "gate .* open",
                    "ancient hinges of the gate creak",
                    "Summoning the power",
                    "gate slowly opens",
                    "bronze gate pops open",
                    "opened wide enough to slip through",
                    "through a massive bronze gate",
                })
                fill_hands()
            end
        end
    end
end

-- Patch: outside -> inside (push gate)
if inside then
    local room = Room[outside]
    if room then
        room.timeto[tostring(inside)] = 30.0
        room.wayto[tostring(inside)] = gate_push_wayto("Obvious paths")
    end
end

-- Patch: inside -> outside (push gate)
if inside and outside then
    local room = Room[inside]
    if room then
        room.timeto[tostring(outside)] = 30.0
        room.wayto[tostring(outside)] = gate_push_wayto("Obvious paths")
    end
end
