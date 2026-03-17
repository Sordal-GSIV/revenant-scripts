-- lib/gs/stowlist.lua
-- Parse STOW LIST command output to track stow target containers.
-- NOTE: check() must be called from a running script context (needs fput/get).

local M = {}

local CATEGORIES = {
    "box", "gem", "herb", "skin", "wand", "scroll", "potion",
    "trinket", "reagent", "lockpick", "treasure", "forageable",
    "collectible", "default",
}

local state = {}
local checked = false

--- Parse STOW LIST output. Must be called from a running script.
function M.check(opts)
    opts = opts or {}
    for _, cat in ipairs(CATEGORIES) do state[cat] = nil end
    checked = false

    waitrt()
    fput("stow list")

    local header = waitfor("You have the following containers set as stow targets:", 5)
    if not header then
        if not opts.quiet then respond("[stowlist] Failed to parse stow list") end
        return false
    end

    while true do
        local line = get()
        if not line or line:match("^>") then break end

        local cat, container = line:match("^%s+(%w+)%s*:%s*(.+)$")
        if cat and container then
            cat = cat:lower()
            container = container:match("^%s*(.-)%s*$")
            if container ~= "none" and container ~= "" then
                state[cat] = container
            end
        end
    end

    checked = true
    return true
end

function M.valid()
    if not checked then return false end
    return true
end

function M.reset()
    for _, cat in ipairs(CATEGORIES) do state[cat] = nil end
    checked = false
end

function M.stow_list()
    local result = {}
    for _, cat in ipairs(CATEGORIES) do
        result[cat] = state[cat]
    end
    return result
end

setmetatable(M, {
    __index = function(_, key)
        if state[key] ~= nil then return state[key] end
        if key == "checked" then return checked end
        return rawget(M, key)
    end,
})

return M
