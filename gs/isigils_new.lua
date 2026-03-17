--- @revenant-script
--- name: isigils_new
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Guardians of Sunfist sigil maintenance - keeps configured sigils active
--- tags: GoS, sigils, society
---
--- Usage:
---   ;isigils_new        - Run with current settings
---   ;isigils_new setup  - Configure sigils (text mode)
---   ;isigils_new help   - Show help

local SIGILS = {
    {num=9703, name="Contact",   mana=1,  stam=0,  dur="19min"},
    {num=9704, name="Resolve",   mana=0,  stam=5,  dur="90sec"},
    {num=9705, name="Minor Bane",mana=3,  stam=3,  dur="60sec"},
    {num=9707, name="Defense",   mana=5,  stam=5,  dur="5min"},
    {num=9708, name="Offense",   mana=5,  stam=5,  dur="5min"},
    {num=9710, name="Minor Prot",mana=5,  stam=10, dur="60sec"},
    {num=9711, name="Focus",     mana=5,  stam=5,  dur="60sec"},
    {num=9713, name="Mending",   mana=10, stam=15, dur="10min"},
    {num=9714, name="Conc",      mana=0,  stam=30, dur="10min"},
    {num=9715, name="Major Bane",mana=10, stam=10, dur="60sec"},
    {num=9719, name="Major Prot",mana=10, stam=15, dur="60sec"},
}

if script.vars[1] == "help" then
    respond("iSigils - Sigil maintenance")
    respond(";isigils_new       - Run with saved settings")
    respond(";isigils_new setup - Configure")
    for _, s in ipairs(SIGILS) do
        respond(string.format("  %d: %s (%dm/%ds, %s)", s.num, s.name, s.mana, s.stam, s.dur))
    end
    exit()
elseif script.vars[1] == "setup" then
    respond("Configure sigils to maintain (toggle with spell number):")
    for _, s in ipairs(SIGILS) do
        local active = CharSettings["sigil_" .. s.num] and "ON" or "off"
        respond(string.format("  %d: %s [%s]", s.num, s.name, active))
    end
    respond("Use: ;e CharSettings['sigil_9703'] = true  (to enable)")
    exit()
end

while true do
    if checkdead and checkdead() then exit() end
    waitrt(); waitcastrt()

    for _, s in ipairs(SIGILS) do
        if CharSettings["sigil_" .. s.num] then
            local spell = Spell[s.num]
            if spell and spell.known and not spell.active and spell.affordable then
                spell.cast()
                waitrt(); waitcastrt()
                pause(0.1)
            end
        end
    end
    pause(2)
end
