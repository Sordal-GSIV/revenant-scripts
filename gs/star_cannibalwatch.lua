--- @revenant-script
--- name: star_cannibalwatch
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Watch for cannibal detection and auto-cast profession-appropriate spell
--- tags: cannibal,detection,auto-cast
---
--- Profession spell mapping:
---   Ranger -> 609 (Sunburst)
---   Wizard -> 912 (Call Wind)
---
--- To stop: ;kill star_cannibalwatch

local SCRIPTS_TO_PAUSE = { "bigshot" }

local CANNIBAL_TRIGGER =
    "A sudden electric chill travels down the back of your neck.  " ..
    "You are unable to shake the sensation that you are being watched."

local PROFESSION_SPELL = {
    Ranger = "609",
    Wizard = "912",
}

local spell = PROFESSION_SPELL[Char.prof]

if not spell then
    echo("star_cannibalwatch: unsupported profession '" .. tostring(Char.prof) ..
         "' -- add your spell to PROFESSION_SPELL and restart.")
    return
end

echo("star_cannibalwatch: watching for cannibals (" .. Char.prof .. " -> incant " .. spell .. ")...")

while true do
    local line = get()
    if line and line:find(CANNIBAL_TRIGGER, 1, true) then
        echo("CANNIBAL DETECTED!")

        -- Pause helper scripts
        for _, s in ipairs(SCRIPTS_TO_PAUSE) do
            if running(s) then Script.pause(s) end
        end

        fput("incant " .. spell)

        -- Unpause helper scripts
        for _, s in ipairs(SCRIPTS_TO_PAUSE) do
            if running(s) then Script.unpause(s) end
        end
    end
end
