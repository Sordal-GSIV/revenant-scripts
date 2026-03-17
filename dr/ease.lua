--- @revenant-script
--- name: ease
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Cast Ease Burden repeatedly until near mindlock, then rest.
--- tags: magic, training, ease_burden
---
--- Converted from ease.lic

local cool_down_time = 30

local function cast_spell(spell)
    put("prep " .. spell)
    while true do
        local line = get()
        if line and line == "You feel fully prepared to cast your spell." then
            put("cast")
            return
        end
    end
end

local function mind_lock()
    put("exp")
    while true do
        local line = get()
        if line then
            if line:match("3[1-4]/34") then
                return true
            elseif line:find("EXP HELP") then
                return false
            end
        end
    end
end

while true do
    if mind_lock() then
        pause(cool_down_time)
    else
        cast_spell("ease")
    end
end
