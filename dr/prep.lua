--- @revenant-script
--- name: prep
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Auto-prep spell handling. Stops humming if needed, retries on roundtime/stun.
--- tags: magic, prep, spell
---
--- Usage: Set alias prep=;prep then ;prep <spell> <mana> [target]

silence_me()

local spell = table.concat({Script.vars[1] or "", Script.vars[2] or "", Script.vars[3] or ""}, " ")
spell = spell:match("^%s*(.-)%s*$")

local function try_prep()
    fput("prep " .. spell)
    while true do
        local line = get()
        if line then
            if line:find("%.%.%.wait") then
                pause(1)
                return try_prep()
            elseif line:find("spell") then
                return true
            elseif line:find("You should stop playing before you do that") then
                fput("stop hum")
                fput("prep " .. spell)
            elseif line:find("stunned") then
                pause(2)
                return try_prep()
            end
        end
    end
end

try_prep()
