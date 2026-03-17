--- Crit table lookup scaffold.
--- Data files to be loaded later; provides the API surface now.

local M = {}
local tables = {}

--- Load crit data from a directory (stub).
function M.load(data_dir)
    respond("data loading not yet implemented")
end

--- Parse a crit line from game output (stub).
function M.parse(line)
    return nil
end

--- Fetch a crit entry by type, location, and rank.
function M.fetch(crit_type, location, rank)
    if not tables[crit_type] then return nil end
    if not tables[crit_type][location] then return nil end
    return tables[crit_type][location][rank]
end

--- Return available crit types.
function M.types_list()
    return {}
end

--- Return available locations.
function M.locations_list()
    return {}
end

--- Return available ranks.
function M.ranks_list()
    return {}
end

return M
