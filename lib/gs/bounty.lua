-- Bounty structured parser
-- Parses Bounty.task text into structured fields.

local _bounty_cache_text = nil
local _bounty_cache_result = nil

function Bounty.parse()
    local task = Bounty.task
    if task == "" or task == nil then return nil end
    if task == _bounty_cache_text then return _bounty_cache_result end
    _bounty_cache_text = task

    local info = { done = false }

    -- Completion markers
    if task:find("You have succeeded") or task:find("succeeded in your task")
       or task:find("You have completed your task") then
        info.done = true
    end

    -- No bounty
    if task:find("You are not currently assigned") then
        info.type = "none"
        _bounty_cache_result = info; return info
    end

    -- Failed
    if task:find("your task is failed") then
        info.type = "failed"
        _bounty_cache_result = info; return info
    end

    -- Creature culling
    local count, creature = task:match("hunt down and kill (%d+) (.-) ")
    if count then
        info.type = "creature"
        info.creature = creature
        info.number = tonumber(count)
        info.count = tonumber(count)
        info.area = task:match("near ([%w%s'%-]+)%.")
        _bounty_cache_result = info; return info
    end

    -- Boss (dangerous)
    if task:match("particularly dangerous") then
        info.type = "dangerous"
        info.creature = task:match("dangerous (.-) that has") or task:match("dangerous (.-)%.")
        info.number = 1
        info.count = 1
        _bounty_cache_result = info; return info
    end

    -- Cull (suppress activity, non-bandit)
    local cull_creature = task:match("suppress (.-) activity")
    if cull_creature and not task:find("bandit") then
        info.type = "cull"
        info.creature = cull_creature
        _bounty_cache_result = info; return info
    end

    -- Bandits
    if task:find("suppress bandit") or task:find("bandits you encounter") then
        info.type = "bandits"
        info.area = task:match("near ([%w%s'%-]+)%.") or task:match("activity near ([%w%s'%-]+)")
        _bounty_cache_result = info; return info
    end

    -- Gem
    if task:find("gem dealer") then
        info.type = "gem"
        info.gem = task:match("has an order for .+ ([%w%s'%-]+)%.")
        info.number = tonumber(task:match("has asked that you gather (%d+)") or task:match("retrieve (%d+)")) or 1
        info.count = info.number
        _bounty_cache_result = info; return info
    end

    -- Herb/forage
    if task:find("concoction") or task:find("herbalist") or task:find("healer") then
        info.type = "herb"
        info.herb = task:match("requires .- ([%w%s'%-]+) found") or task:match("gather .- stems? of ([%w%s'%-]+)")
        info.number = tonumber(task:match("requires (%d+)") or task:match("gather (%d+)")) or 1
        info.count = info.number
        info.area = task:match("found .- in ([%w%s'%-]+)")
        _bounty_cache_result = info; return info
    end

    -- Skin
    if task:find("furrier") then
        info.type = "skin"
        info.skin = task:match("retrieve %d+ ([%w%s'%-]+) of at least")
        info.creature = task:match("quality from .- ([%w%s'%-]+)")
        info.number = tonumber(task:match("retrieve (%d+)")) or 1
        info.count = info.number
        _bounty_cache_result = info; return info
    end

    -- Heirloom
    if task:find("heirloom") or task:find("SEARCH the area") or task:find("LOOT the item") or task:find("lost .* somewhere") then
        info.type = "heirloom"
        info.item = task:match("lost ([%w%s'%-]+) somewhere") or task:match("retrieve a ([%w%s'%-]+)")
        info.creature = task:match("known to be near ([%w%s'%-]+)") or task:match("from .- ([%w%s'%-]+) corpse")
        info.area = task:match("somewhere .- in ([%w%s'%-]+)")
        if task:find("SEARCH") or task:find("do a thorough SEARCH") then
            info.action = "search"
        elseif task:find("LOOT") then
            info.action = "loot"
        end
        if task:find("You have located") then info.done = true end
        _bounty_cache_result = info; return info
    end

    -- Escort
    if task:find("escort") then
        info.type = "escort"
        info.start = task:match("meet .+ at ([%w%s'%-,]+) in order")
        info.destination = task:match("escort .+ to ([%w%s'%-]+)%.")
        _bounty_cache_result = info; return info
    end

    -- Rescue (child)
    if task:find("child") or task:find("rescue") then
        info.type = "rescue"
        info.creature = task:match("fleeing from .- ([%w%s'%-]+)") or task:match("visions of .+ ([%w%s'%-]+)")
        if task:find("You have made contact") then info.done = true end
        _bounty_cache_result = info; return info
    end

    -- Guard/assignment redirects
    if task:find("Report to") or task:find("report to") then
        if task:find("gem dealer") then info.type = "gem_assignment"
        elseif task:find("furrier") then info.type = "skin_assignment"
        elseif task:find("herbalist") or task:find("healer") then info.type = "herb_assignment"
        elseif task:find("guard") or task:find("sergeant") or task:find("sentry") then info.type = "guard"
        else info.type = "assignment" end
        _bounty_cache_result = info; return info
    end

    -- Taskmaster turn-in
    if info.done then
        info.type = "taskmaster"
        _bounty_cache_result = info; return info
    end

    _bounty_cache_result = info
    return info
end

--- Convenience: get bounty type as a string
function Bounty.type_sym()
    local info = Bounty.parse()
    if not info then return "none" end
    if info.done and info.type ~= "heirloom" then return "taskmaster" end
    return info.type or "none"
end
