--- @revenant-script
--- @lic-audit: level1.lic validated 2026-03-18
--- name: level1
--- author: SpiffyJr
--- game: gs
--- description: Navigate hardcoded targets to gain level 1
--- tags: utility,leveling,newbie
---
--- Usage:
---   ;level1 <town>    -- navigate town locations to gain level 1
---   ;level1            -- show available towns

--------------------------------------------------------------------------------
-- Hardcoded room/tag targets by town abbreviation
--------------------------------------------------------------------------------

local hardcoded_targets = {
    wl = {
        4041, 3824,
        "herbalist", "armorshop", "weaponshop", "furrier", "pawnshop", "bank",
        387, 7543, "gemshop", 1195, "locksmith", 221,
        8664, 8686, 8632, "alchemist", 8817, 1264, 3931,
    },
    it = {
        2334, 2406, 3363,
        "armorshop", "weaponshop", "furrier", "pawnshop", "bank",
        2429, "gemshop", 3448, 3426, 2424, "locksmith", "alchemist",
        3403, 2458, 2487, 3371, 2488,
    },
    tv = {
        10369, 10397, 10396,
        "armorshop", "weaponshop", "furrier", "pawnshop", "bank",
        10313, 5909, "gemshop", "locksmith", 5826, "alchemist", 10382,
    },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function go2(room)
    waitrt()
    if Room.id == tonumber(tostring(room)) then return end

    Script.run("go2", tostring(room) .. " _disable_confirm_")
    wait_while(function() return running("go2") end)
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local town = Script.vars[1]

if not town then
    respond("Usage: ;level1 <town>")
    respond("Towns:")
    for key, _ in pairs(hardcoded_targets) do
        respond("  " .. key)
    end
    return
end

town = town:lower()

if hardcoded_targets[town] then
    for _, room in ipairs(hardcoded_targets[town]) do
        go2(tostring(room))
    end

    go2("town")
else
    respond("Unable to find location " .. town .. " in target list")
end
