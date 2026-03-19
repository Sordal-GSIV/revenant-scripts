--- @revenant-module
--- name: flags
--- description: Pattern event capture system (game-agnostic)

local M = {}

local registry = {}   -- key → { patterns = {...}, match = nil }
local hook_installed = false

local function ensure_hook()
    if hook_installed then return end
    hook_installed = true
    DownstreamHook.add("__flags_hook", function(line)
        for _, entry in pairs(registry) do
            if entry.match == nil then
                for _, pat in ipairs(entry.patterns) do
                    if line:find(pat) then
                        entry.match = line
                        break
                    end
                end
            end
        end
        return line
    end)
end

--- Register patterns for a key (varargs). Resets any existing match.
function M.add(key, ...)
    ensure_hook()
    local patterns = {...}
    registry[key] = { patterns = patterns, match = nil }
end

--- Clear the match for a key (keep patterns registered).
function M.reset(key)
    if registry[key] then
        registry[key].match = nil
    end
end

--- Remove a key entirely.
function M.remove(key)
    registry[key] = nil
end

--- Remove a key entirely (Lich5 compatibility alias for remove).
M.delete = M.remove

--- Remove all registered keys.
function M.clear_all()
    registry = {}
end

--- Peek at a flag's current match without auto-resetting it.
-- Mirrors Lich5 Flags["key"] read semantics: the value persists until explicitly
-- reset or deleted. Use this when you need to check a flag repeatedly in a loop.
-- @param key string Flag key
-- @return any The matched line, or nil if not yet matched
function M.get(key)
    local entry = registry[key]
    if not entry then return nil end
    return entry.match  -- peek; does NOT reset
end

--- Force-set a flag to a truthy value (manually trigger without a game line).
-- Mirrors Lich5's Flags['key'] = value assignment.
-- @param key string Flag key
-- @param value any Value to set as the match (default true)
function M.set(key, value)
    if registry[key] then
        registry[key].match = (value ~= nil) and value or true
    else
        registry[key] = { patterns = {}, match = (value ~= nil) and value or true }
    end
end

-- Metatable: Flags["key"] returns the matched line and auto-resets.
setmetatable(M, {
    __index = function(_, key)
        local entry = registry[key]
        if not entry then return nil end
        local result = entry.match
        entry.match = nil
        return result
    end,
})

return M
