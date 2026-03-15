--- Lich5-compatible Vars module.
--- Stores arbitrary Lua values as JSON in CharSettings with __v: prefix.
--- Usage: Vars = require("lib/lich_vars")
---   Vars["key"] = {foo = "bar"}   -- stores as JSON
---   Vars["key"]                    -- returns {foo = "bar"}
---   Vars.my_key = "hello"         -- dot syntax works too
---   Vars.my_key                   -- returns "hello"
---   Vars["key"] = nil             -- deletes

local PREFIX = "__v:"

local function vars_get(key)
    local raw = CharSettings[PREFIX .. key]
    if raw == nil then return nil end
    local ok, val = pcall(Json.decode, raw)
    if ok and val ~= nil then return val end
    return raw  -- fallback: return raw string if not valid JSON
end

local function vars_set(key, val)
    if val == nil then
        CharSettings[PREFIX .. key] = nil
    else
        CharSettings[PREFIX .. key] = Json.encode(val)
    end
end

local Vars = {}

function Vars.list()
    -- Cannot enumerate CharSettings keys from Lua (no pairs support on metatable).
    -- Return empty table. Scripts needing full listing should use the ;vars CLI.
    return {}
end

function Vars.save()
    -- No-op: CharSettings persists on write
end

local mt = {
    __index = function(t, key)
        -- Check for module methods first
        local method = rawget(Vars, key)
        if method then return method end
        return vars_get(key)
    end,
    __newindex = function(t, key, val)
        vars_set(key, val)
    end,
}

setmetatable(Vars, mt)

return Vars
