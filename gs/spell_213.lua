--- @revenant-script
--- name: spell_213
--- version: 0.3.0
--- author: Tsalinx
--- game: gs
--- description: Cast and maintain Minor Sanctuary (213), exits on room change or failure
--- tags: 213, sanct, sanctuary, cleric
---
--- Usage:
---   ;spell_213
---
--- Tip: ;alias add --global 213 = ;spell_213

local cur = nil

local function makeasanct()
    while true do
        if Spell[213].affordable then
            waitcastrt()
            clear()
            fput("incant 213")
            local result = matchtimeout(2,
                "already peaceful and calm",
                "A sense of peace and calm",
                "spirit of aggression",
                "chaotic nature",
                "You strain to call",
                "Your armor prevents"
            )
            result = result or ""

            if result:find("chaotic nature") or result:find("You strain to call") then
                _respond(monsterbold_start() .. "**Terminating script because there seems to be a demon here!**" .. monsterbold_end())
                return false
            elseif result:find("already peaceful and calm") then
                _respond(monsterbold_start() .. "**Terminating script because this room is already peaceful enough!**" .. monsterbold_end())
                return false
            elseif result:find("A sense of peace and calm") then
                _respond(monsterbold_start() .. "**Minor sanctuary maintenance enabled.**" .. monsterbold_end())
                return true
            elseif result:find("Your armor prevents") then
                -- Try again
            else
                _respond(monsterbold_start() .. "**Clear the room first or try your luck again!**" .. monsterbold_end())
                return false
            end
        else
            fput("mana pulse")
            pause(3)
        end
    end
end

local function roomcheck()
    local room = Room.current()
    if not room or room.id ~= cur then
        _respond(monsterbold_start() .. "**Terminating script because you moved rooms.**" .. monsterbold_end())
        return false
    end
    return true
end

local room = Room.current()
cur = room and room.id

if not makeasanct() then return end

while true do
    clear()
    local status = matchtimeout(3,
        "any sense of peace and security",
        "you terminate the Minor Sanctuary spell",
        "begins to wane from the area",
        "passes away from the area"
    )

    if not status then
        if not roomcheck() then return end
    elseif status:find("you terminate the Minor Sanctuary spell") then
        return
    else
        if not roomcheck() then return end
        if not makeasanct() then return end
    end
end
