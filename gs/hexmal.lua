--- @revenant-script
--- name: hexmal
--- version: 1.1.0
--- author: unknown
--- game: gs
--- description: Calculate Maximum Animatable Level (MAL) for Sorcerers
--- tags: sorcerer, animate, mal, utility
--- @lic-certified: complete 2026-03-19

-- MAL = (700s ranks, capped at level) - 10
--     + (700s ranks over level / 10, max of 5)
--     + (WIS Bonus / 5)
--     + (Sorcerous Lore, Necromancy Ranks / 10)

local ok, err = pcall(function()
    local level = Stats.level
    local wisdom = Stats.wisdom.enhanced.bonus  -- enhanced bonus
    local sorcspells = Spells.sorcerer
    local necro_ranks = Skills.slnecromancy

    -- (700s ranks, capped at level)
    local capped_700 = math.min(sorcspells, level)

    -- (700s ranks over level)
    local over_700 = math.max(sorcspells - level, 0)

    -- (700s ranks over level / 10, max of 5)
    local over_700_bonus = math.floor(over_700 / 10)
    if over_700_bonus > 5 then over_700_bonus = 5 end

    -- (WIS Bonus / 5)
    local wis_term = math.floor(wisdom / 5)

    -- (Sorcerous Lore, Necromancy Ranks / 10)
    local necro_term = math.floor(necro_ranks / 10)

    -- Final MAL
    local mal = capped_700 - 10 + over_700_bonus + wis_term + necro_term

    respond("===== Maximum Animatable Level (MAL) =====")
    respond(string.format("Level:                                %d", level))
    respond(string.format("700s ranks (Sorcerer circle):         %d", sorcspells))
    respond(string.format("  - Capped at level:                  %d", capped_700))
    respond(string.format("700s ranks over level:                %d", over_700))
    respond(string.format("  -> Over-level bonus (/10, max 5):   %d", over_700_bonus))
    respond(string.format("Wisdom bonus:                         %d", wisdom))
    respond(string.format("  -> WIS term (bonus / 5):            %d", wis_term))
    respond(string.format("Sorcerous Lore, Necromancy ranks:     %d", necro_ranks))
    respond(string.format("  -> Necromancy term (ranks / 10):    %d", necro_term))
    respond("-------------------------------------------")
    respond(string.format("Maximum Animatable Level (MAL):        %d", mal))
    respond("===========================================")
end)

if not ok then
    respond("MAL script error: " .. tostring(err))
end
