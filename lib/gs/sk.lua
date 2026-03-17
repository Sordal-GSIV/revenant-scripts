--- Stat Knowledge spell list.
--- Tracks known spells with Infomon persistence.

local M = {}
local known = nil -- lazy loaded

local function load_known()
    if known then return end
    known = {}
    local raw = Infomon.get("sk.known")
    if raw and raw ~= "" then
        for num in raw:gmatch("(%d+)") do
            local n = tonumber(num)
            if n then
                known[#known + 1] = n
            end
        end
    end
end

local function save_known()
    local parts = {}
    for _, n in ipairs(known) do
        parts[#parts + 1] = tostring(n)
    end
    Infomon.set("sk.known", table.concat(parts, ","))
end

--- Return the array of known spell numbers.
function M.known()
    load_known()
    local copy = {}
    for i, v in ipairs(known) do
        copy[i] = v
    end
    return copy
end

--- Check if a spell number is known.
function M.known_p(num)
    load_known()
    for _, n in ipairs(known) do
        if n == num then return true end
    end
    return false
end

--- Add one or more spell numbers.
function M.add(...)
    load_known()
    for _, num in ipairs({...}) do
        if not M.known_p(num) then
            known[#known + 1] = num
        end
    end
    save_known()
end

--- Remove one or more spell numbers.
function M.remove(...)
    load_known()
    local to_remove = {}
    for _, num in ipairs({...}) do
        to_remove[num] = true
    end
    local filtered = {}
    for _, n in ipairs(known) do
        if not to_remove[n] then
            filtered[#filtered + 1] = n
        end
    end
    known = filtered
    save_known()
end

return M
