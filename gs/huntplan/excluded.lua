--- huntplan excluded.lua — impassable path overrides
-- These room→room pairs are treated as blocked regardless of Map data.
-- Source: huntplan.lic lines 3046-3095

local M = {}

-- excluded[src][dst] = true means src→dst is impassable
local paths = {
    [7160]  = { [8432]  = true },
    [8569]  = { [8568]  = true },
    [4312]  = { [4313]  = true },
    [6633]  = { [6634]  = true },
    [6636]  = { [6634]  = true },
    [3584]  = { [3924]  = true },
    [3697]  = { [3698]  = true },
    [6955]  = { [6985]  = true, [22229] = true },
}

-- Level-conditional entry: (3566→3565) blocked if char level < 30
-- Caller must call M.apply_level_exclusions(char_level) after init.
local level_paths = {
    { src = 3566, dst = 3565, min_level = 30 },
}

function M.is_excluded(src, dst)
    return paths[src] and paths[src][dst] == true
end

function M.apply_level_exclusions(char_level)
    for _, rule in ipairs(level_paths) do
        if char_level < rule.min_level then
            paths[rule.src] = paths[rule.src] or {}
            paths[rule.src][rule.dst] = true
        else
            if paths[rule.src] then
                paths[rule.src][rule.dst] = nil
            end
        end
    end
end

return M
