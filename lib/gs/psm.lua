-- Unified PSM module — registers CMan, Feat, Shield, Armor, Weapon, Ascension, Warcry as globals

local function normalize(name)
    return name:lower():gsub("[%s%-']", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

local function make_psm(prefix)
    local t = {}
    function t.known_p(name)
        local val = Infomon.get(prefix .. "." .. normalize(name))
        return val == "learned" or val == "active"
    end
    function t.active_p(name)
        return Infomon.get(prefix .. "." .. normalize(name)) == "active"
    end
    function t.available()
        local result = {}
        for _, kv in ipairs(Infomon.keys()) do
            if kv:match("^" .. prefix .. "%.") then
                local name = kv:sub(#prefix + 2)
                local val = Infomon.get(kv)
                if val == "learned" or val == "active" then
                    result[#result + 1] = { name = name, status = val }
                end
            end
        end
        return result
    end
    -- Metatable for CMan["name"] style access
    return setmetatable(t, {
        __index = function(_, key)
            if type(key) == "string" and not t[key] then
                return t.known_p(key)
            end
            return rawget(t, key)
        end
    })
end

CMan = make_psm("cman")
Feat = make_psm("feat")
Shield = make_psm("shield")
Armor = make_psm("armor")
Weapon = make_psm("weapon")
Ascension = make_psm("ascension")

-- Warcry is different: list of known warcries
Warcry = {
    known = function()
        local result = {}
        for _, kv in ipairs(Infomon.keys()) do
            if kv:match("^warcry%.") then
                result[#result + 1] = kv:sub(8)
            end
        end
        return result
    end
}

return true -- globals already registered
