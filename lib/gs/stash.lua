-- lib/gs/stash.lua
-- Item storage/retrieval helper for managing treasure containers.

local M = {}

-- Stash an item in a container
function M.stash(item, container)
    container = container or "backpack"
    fput("put " .. item .. " in my " .. container)
end

-- Retrieve an item from a container
function M.retrieve(item, container)
    container = container or "backpack"
    fput("get " .. item .. " from my " .. container)
end

-- Stash all loot
function M.stash_loot(container)
    local loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        fput("get #" .. obj.id)
        M.stash(obj.noun, container)
    end
end

return M
