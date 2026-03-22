--- @revenant-script
--- name: spritearmor
--- version: 1.0.0
--- author: Ralkean
--- game: gs
--- tags: sprite, armor, mana, automation
--- description: Manages sprite armor reserves - analyzes, touches, and refills mana automatically
---
--- Original Lich5 authors: Ralkean
--- Ported to Revenant Lua from spritearmor.lic

local stored = 0
local reserve_ready = false
local infusion_ready = false
local timer = 0

local SPRITE_STORED_RX = "Total Stored:</popBold/> (%d+)"
local SPRITE_RESERVE_TIME_RX = "Spritely Reserves:</popBold/> Ready"
local SPRITE_INFUSION_TIME_RX = "Mana Infusion %(TOUCH%):</popBold/> Mana Infusion %(TOUCH%) Required"

local function check_sprite()
    reserve_ready = false
    infusion_ready = false
    waitrt()
    local res = quiet_command("anal my chain", "You analyze")
    for _, line in ipairs(res or {}) do
        local s = line:match(SPRITE_STORED_RX)
        if s then stored = tonumber(s) end
        if line:find("Spritely Reserves:</popBold/> Ready") then
            reserve_ready = true
        end
        if line:find("Mana Infusion %(TOUCH%):</popBold/> Mana Infusion %(TOUCH%) Required") then
            infusion_ready = true
        end
    end
    timer = 60
end

local function touch()
    waitrt()
    fput("touch my chain")
end

local function getmana()
    waitrt()
    for _ = 1, 5 do put("turn my chain") end
    wait(0.25)
    waitrt()
    for _ = 1, 5 do put("wave chain") end
    wait(0.25)
end

while true do
    if timer < 1 then
        check_sprite()
    end

    if stored < 800 and reserve_ready then
        if checkmana() > 350 then
            touch()
            check_sprite()
        elseif checkmana() + 0.9 * stored > 350 then
            local cur = Room.current()
            local at_node = cur and cur.tags_include and cur.tags_include("node")
            if not at_node then
                getmana()
                check_sprite()
            end
        end
    end

    if infusion_ready then
        touch()
        check_sprite()
    end

    if checkmana() < 70 and checkmana() > 9 and stored > 350 then
        echo("low mana")
        getmana()
        check_sprite()
    end

    wait(1)
    timer = timer - 1
end
