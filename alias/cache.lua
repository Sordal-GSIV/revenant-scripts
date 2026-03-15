local M = {}

local char_aliases = {}
local global_aliases = {}
local tier2_aliases = {}

function M.load_all()
    local raw_char = CharSettings["aliases"]
    if raw_char then
        local ok, t = pcall(Json.decode, raw_char)
        char_aliases = (ok and type(t) == "table") and t or {}
    else
        char_aliases = {}
    end

    local raw_global = Settings["aliases_global"]
    if raw_global then
        local ok, t = pcall(Json.decode, raw_global)
        global_aliases = (ok and type(t) == "table") and t or {}
    else
        global_aliases = {}
    end
end

function M.set_tier2(list)
    tier2_aliases = list or {}
end

function M.get_char()    return char_aliases end
function M.get_global()  return global_aliases end
function M.get_tier2()   return tier2_aliases end

function M.save_char(list)
    char_aliases = list
    CharSettings["aliases"] = Json.encode(list)
end

function M.save_global(list)
    global_aliases = list
    Settings["aliases_global"] = Json.encode(list)
end

function M.reload()
    M.load_all()
end

return M
