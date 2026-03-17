local M = {}
local creature_db = nil

local function load_db()
    if creature_db then return end
    local path = "gs/ebestiary/creatures.json"
    local content = File.read(path)
    if content then
        local ok, data = pcall(Json.decode, content)
        if ok then creature_db = data end
    end
    creature_db = creature_db or {}
end

function M.find(name_or_noun)
    load_db()
    local search = name_or_noun:lower()
    for name, c in pairs(creature_db) do
        if name:lower() == search then
            c.name = c.name or name
            return c
        end
        -- Check noun (last word of the name)
        local noun = name:match("%S+$")
        if noun and noun:lower() == search then
            c.name = c.name or name
            return c
        end
    end
    return nil
end

function M.list()
    load_db()
    return creature_db
end

-- Wrap a GameObj NPC with creature data
function M.new(gameobj)
    if not gameobj then return nil end
    local data = M.find(gameobj.noun) or M.find(gameobj.name) or {}
    return {
        id = gameobj.id,
        name = gameobj.name,
        noun = gameobj.noun,
        status = gameobj.status,
        level = data.level,
        type = data.type,
        undead = data.undead or false,
        aggressive = true, -- NPCs are aggressive by default
    }
end

return M
