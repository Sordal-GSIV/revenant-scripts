--- @revenant-script
--- name: beseech
--- version: 1.4.0
--- author: Peggyanne
--- game: gs
--- description: Auto-beseech when stunned, webbed, or otherwise debuffed (1635)
--- tags: beseech,debuff,stun,web,auto
---
--- Runs in background. When stunned/webbed/bound/etc, checks mana and uses BESEECH.
--- Pauses bigshot if running.
---
--- Usage:
---   ;beseech        - start monitoring
---   ;beseech help   - show help

local DEBUFF_NAMES = {
    "Stunned", "Condemn", "Calm", "Frenzy", "Curse",
    "Blinded", "Webbed", "Bind", "Interference",
    "Moonbeam", "Stone Fist",
}

local function beseech_me()
    waitrt()
    if Spell[1635] and Spell[1635].known and Spell[1635]:affordable() then
        fput("beseech")
    end
end

local function big_running()
    if running("bigshot") then
        Script.pause("bigshot")
        beseech_me()
        Script.unpause("bigshot")
    else
        beseech_me()
    end
end

local function check_status()
    local has_debuff = false

    if stunned() or webbed() or bound() then
        has_debuff = true
    end

    -- Check named debuffs if Effects API is available
    for _, name in ipairs(DEBUFF_NAMES) do
        if Effects and Effects.Debuffs and Effects.Debuffs.active then
            if Effects.Debuffs.active(name) then
                has_debuff = true
                break
            end
        end
    end

    if has_debuff then
        if Spell[1635] and Spell[1635].known and Spell[1635]:affordable() then
            waitrt()
            big_running()
            check_status()  -- re-check after beseech
        end
    end
end

-- Help
local arg = Script.vars[1]
if arg and arg:lower() == "help" then
    echo([[
This script runs in the background and when you are stunned or webbed
or otherwise made immobile it will check for mana and use the verb BESEECH.
If you are running Bigshot, it will pause it, beseech and then unpause.
~Peggyanne
]])
    return
end

while true do
    pause(1)
    check_status()
end
