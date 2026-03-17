--- @revenant-script
--- name: paladinaura
--- version: 2025.03.09
--- author: Demandred
--- game: gs
--- description: Maintain a paladin aura (Divine Shield, Zealot, or Fervor) through death and dispel
--- tags: paladin, upkeep, auras
---
--- Usage:
---   ;paladinaura           - start maintaining aura (default: Divine Shield / 1609)
---   ;paladinaura help      - show help
---
--- Set UserVars.paladin_aura to your preferred aura:
---   ;e UserVars.paladin_aura = 1609
---   ;e UserVars.paladin_aura = "Zealot"
---   ;e UserVars.paladin_aura = "Fervor"

if not Spell[1609] or not Spell[1609].known then
    echo("You don't know any aura spells")
    echo("Exiting.")
    return
end

if Script.vars[1] and Script.vars[1]:lower():find("help") then
    echo("Just set the UserVars.paladin_aura var to whichever aura you wish to maintain.")
    echo("It can be any of: Divine Shield, 1609, Zealot, 1617, Fervor, and 1618.")
    echo("Example: ;e UserVars.paladin_aura = 1609")
    echo("     or: ;e UserVars.paladin_aura = \"Fervor\"")
    echo("     or: ;e UserVars.paladin_aura = \"zealot\"")
    return
end

if not UserVars.paladin_aura then
    UserVars.paladin_aura = 1609
end

local time_for_next_cast = os.time()

local function can_cast()
    -- Check for severe injuries preventing casting
    if Wounds.head >= 2 or Scars.head >= 2 then return false end
    if Wounds.rightEye >= 2 or Scars.rightEye >= 2 then return false end
    if Wounds.leftEye >= 2 or Scars.leftEye >= 2 then return false end
    if (Wounds.rightArm >= 2 or Scars.rightArm >= 2) and (Wounds.leftArm >= 1 or Scars.leftArm >= 1) then return false end
    if (Wounds.leftArm >= 2 or Scars.leftArm >= 2) and (Wounds.rightArm >= 1 or Scars.rightArm >= 1) then return false end
    if Wounds.rightArm == 3 or Wounds.leftArm == 3 then return false end
    if Scars.rightArm == 3 or Scars.leftArm == 3 then return false end
    return true
end

while true do
    -- Determine aura (can change on the fly)
    local aura_str = tostring(UserVars.paladin_aura)
    local my_aura

    if aura_str:lower():find("divine shield") or aura_str:find("1609") then
        my_aura = {1609, "Divine Shield"}
    elseif aura_str:lower():find("zealot") or aura_str:find("1617") then
        my_aura = {1617, "Zealot"}
    elseif aura_str:lower():find("fervor") or aura_str:find("1618") then
        my_aura = {1618, "Fervor"}
    else
        echo("You screwed up your aura choice. Fix UserVars.paladin_aura to include a proper choice then restart me. Divine Shield, 1609, Zealot, 1617, Fervor, and 1618 are your choices.")
        return
    end

    pause(1)

    -- Skip if aura is already active
    if Effects.Spells.active(my_aura[2]) then
        -- already active, just loop
    else
        -- Wait out death and injury
        while dead() or running("eherbs") or running("useherbs") or not can_cast() do
            pause(1)
        end

        -- Wait for mana
        while not Spell[my_aura[1]].affordable do
            pause(1)
        end

        -- Wait for recast timer
        while os.time() < time_for_next_cast do
            pause(1)
        end

        -- Pause other scripts briefly
        waitrt()
        waitcastrt()
        pause(1)

        local line = dothistimeout(
            "incant " .. my_aura[1],
            5,
            "your shield arm feels much more nimble|Your spirit is empowered with an overwhelming sense of determination and resolve|a divine force suddenly radiates around you|You must wait (%d+) seconds before switching auras%."
        )

        if line and line:find("You must wait (%d+) seconds") then
            local wait_secs = tonumber(line:match("You must wait (%d+) seconds")) or 0
            time_for_next_cast = os.time() + wait_secs + 1
        elseif line and (line:find("your shield arm") or line:find("Your spirit is empowered") or line:find("a divine force")) then
            time_for_next_cast = os.time() + 61
        end
    end
end
