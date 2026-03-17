local M = {}

M.detected = false
M.tier = 0
M.has_distiller = false

function M.detect(container_id)
    -- Send ANALYZE to detect survival kit
    fput("analyze #" .. container_id)
    local found = false
    local tier = 0
    local distiller = false

    for i = 1, 10 do
        local line = get()
        if not line then break end
        if line:find("Survivalist's Kit") then
            found = true
        end
        local cap = line:match("Capacity: (%d+)/5")
        if cap then tier = tonumber(cap) end
        if line:find("Liquid Extractor") then distiller = true end
        if line:find("Roundtime") or line == "" then break end
    end

    M.detected = found
    M.tier = tier
    M.has_distiller = distiller

    if found then
        respond("[eherbs] Survival kit detected: tier " .. tier
            .. (distiller and ", has distiller" or ""))
    end

    return found
end

function M.get_contents(container_noun)
    fput("look in my " .. container_noun)
    local contents = {}

    while true do
        local line = get()
        if not line then break end
        -- Parse dose/tincture lines
        local count, name = line:match("(%d+) doses? of (.+)")
        if not count then
            count, name = line:match("(%d+) tinctures? of (.+)")
        end
        if count and name then
            contents[#contents + 1] = {
                name = name:match("^%s*(.-)%s*$"),
                count = tonumber(count),
            }
        end
        if line:find("Roundtime") or line == "" then break end
    end

    return contents
end

function M.max_capacity()
    return (M.tier * 25) + 25
end

function M.distill(container_noun, herb_noun)
    if not M.has_distiller then
        respond("[eherbs] No distiller unlock on survival kit")
        return false
    end
    fput("point my " .. container_noun .. " at my " .. herb_noun)
    return true
end

return M
