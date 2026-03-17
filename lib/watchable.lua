-- lib/watchable.lua
-- Event system that fires callbacks when Infomon values change.
-- Game-agnostic (works for both GS and DR).

local M = {}
local watchers = {}  -- key → array of callbacks

-- Register a callback for when an Infomon key changes
function M.watch(key, callback)
    watchers[key] = watchers[key] or {}
    watchers[key][#watchers[key] + 1] = callback
end

function M.unwatch(key, callback)
    if not watchers[key] then return end
    for i, cb in ipairs(watchers[key]) do
        if cb == callback then
            table.remove(watchers[key], i)
            return
        end
    end
end

-- Check for changes — called periodically or after Infomon.sync
local cached_values = {}
function M.check()
    for key, cbs in pairs(watchers) do
        local current = Infomon.get(key)
        if current ~= cached_values[key] then
            local old = cached_values[key]
            cached_values[key] = current
            for _, cb in ipairs(cbs) do
                pcall(cb, key, current, old)
            end
        end
    end
end

-- Start periodic checking via DownstreamHook (checks on each prompt)
local check_counter = 0
DownstreamHook.add("__watchable", function(line)
    -- Only check on prompts (every few seconds) to avoid overhead
    if line:match("^>") then
        check_counter = check_counter + 1
        if check_counter >= 5 then  -- every 5th prompt
            check_counter = 0
            M.check()
        end
    end
    return line
end)

return M
