-- Bounty structured parser
-- Parses Bounty.task text into structured fields.
-- Usage: local info = Bounty.parse()

local _bounty_cache_text = nil
local _bounty_cache_result = nil

function Bounty.parse()
    local task = Bounty.task
    if task == "" then return nil end
    if task == _bounty_cache_text then return _bounty_cache_result end
    _bounty_cache_text = task

    local info = { done = false }

    -- Creature task
    local count, creature = task:match("hunt down and kill (%d+) (.-) ")
    if count then
        info.type = "creature"
        info.creature = creature
        info.count = tonumber(count)
        if task:match("You have completed your task") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Dangerous creature
    if task:match("particularly dangerous") then
        local creature2 = task:match("dangerous (.-) that has")
            or task:match("dangerous (.-)%.")
        info.type = "dangerous"
        info.creature = creature2
        info.count = 1
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Cull task
    local cull_creature = task:match("suppress (.-) activity")
    if cull_creature then
        info.type = "cull"
        info.creature = cull_creature
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Gem task
    local gem = task:match("retrieve a ([%w%s'%-]+) from")
        or task:match("retrieve .- ([%w%s'%-]+)%.")
    if task:match("gem") or (gem and not task:match("heirloom")) then
        info.type = "gem"
        info.item = gem
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Herb task
    local herb = task:match("gather %d+ stems? of ([%w%s'%-]+)")
    if herb then
        info.type = "herb"
        info.item = herb
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Skin task
    local skin = task:match("retrieve %d+ (.-) skin")
    if skin then
        info.type = "skin"
        info.item = skin
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Escort task
    local town = task:match("escort .- to ([%w%s'%-]+)")
    if town then
        info.type = "escort"
        info.town = town
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Rescue task
    if task:match("rescue") then
        info.type = "rescue"
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Bandits task
    if task:match("bandits") then
        info.type = "bandits"
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    -- Heirloom task
    if task:match("heirloom") then
        info.type = "heirloom"
        local item2 = task:match("retrieve a ([%w%s'%-]+)")
        info.item = item2
        if task:match("You have completed") then info.done = true end
        _bounty_cache_result = info
        return info
    end

    _bounty_cache_result = info
    return info
end
