--- Bard song calculations.
--- Duration, renewal cost, and sonic bonus computations.

local M = {}

local renewed_at = nil

-- Bard song spell numbers and their mana costs
local BARD_SONGS = { 1003, 1006, 1009, 1010, 1012, 1014, 1018, 1019, 1025 }

--- Base duration by level bracket.
function M.duration_base(level)
    if level <= 25 then
        return 120 + level * 4
    elseif level <= 50 then
        return 220 + (level - 25) * 3
    elseif level <= 75 then
        return 295 + (level - 50) * 2
    else
        return 345 + (level - 75)
    end
end

--- Full duration including elair bonus.
function M.duration()
    local level = Char.level or 0
    local elair = tonumber(Infomon.get("skill.elemental_lore_-_air")) or 0
    return M.duration_base(level) + elair
end

--- Mark songs as renewed now.
function M.renewed()
    renewed_at = os.time()
end

--- Return seconds of song time remaining (min 0).
function M.timeleft()
    if not renewed_at then return 0 end
    local elapsed = os.time() - renewed_at
    local remaining = M.duration() - elapsed
    if remaining < 0 then return 0 end
    return remaining
end

--- Sum mana cost for active bard songs.
function M.renew_cost()
    local total = 0
    for _, num in ipairs(BARD_SONGS) do
        if Spell and Spell.active_p and Spell.active_p(num) then
            local spell = Spell.get and Spell.get(num)
            if spell and spell.mana_cost then
                local cost = tonumber(spell.mana_cost) or 0
                total = total + cost
            end
        end
    end
    return total
end

--- Base sonic bonus from bard spell ranks.
function M.sonicbonus()
    local bard_ranks = tonumber(Infomon.get("skill.spell_research_-_bard")) or 0
    return math.floor(bard_ranks / 2)
end

--- Sonic armor bonus.
function M.sonicarmorbonus()
    return M.sonicbonus() + 15
end

--- Sonic blade bonus.
function M.sonicbladebonus()
    return M.sonicbonus() + 10
end

--- Sonic shield bonus.
function M.sonicshieldbonus()
    return M.sonicbonus() + 10
end

--- Valor bonus based on bard ranks and level.
function M.valorbonus()
    local bard_ranks = tonumber(Infomon.get("skill.spell_research_-_bard")) or 0
    local level = Char.level or 0
    return 10 + math.floor((math.min(bard_ranks, level) - 10) / 2)
end

return M
