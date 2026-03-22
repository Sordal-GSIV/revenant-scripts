local M = {}

M.detected = false
M.tier = 0
M.has_distiller = false
M.container_id = nil

function M.detect(container_id)
    -- Send ANALYZE to detect survival kit
    M.container_id = container_id
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

function M.distill()
    if not M.has_distiller then
        respond("[eherbs] No distiller unlock on survival kit")
        return false
    end
    if not M.container_id then
        respond("[eherbs] Survival kit not detected — run ;eherbs load first")
        return false
    end

    -- ANALYZE the kit to read current solid/liquid contents
    fput("analyze #" .. M.container_id)
    local lines = {}
    for i = 1, 20 do
        local line = get()
        if not line then break end
        lines[#lines + 1] = line
        if line:find("Roundtime") or line == "" then break end
    end

    -- Can't analyze (kit not accessible), skip distilling
    for _, line in ipairs(lines) do
        if line:find("You can't seem to do that") then
            return false
        end
    end

    -- Extractor already running — nothing to do
    for _, line in ipairs(lines) do
        if line:find("The extractor is currently targeting") then
            local target = line:match("targeting (.-)%s*,") or line:match("targeting (.-)%s*<") or "something"
            respond("[eherbs] Extractor targeting " .. target .. ". Nothing to do.")
            return true
        end
    end

    -- Join lines for pattern matching
    local full_text = table.concat(lines, " ")

    -- Parse solid (DOSES) section: collect herb name → count
    local solid_counts = {}
    local edible_section = full_text:match("contains DOSEs (.-)%.")
    if edible_section then
        for name, count in edible_section:gmatch(">([^<]+)</a>%s*%((%d+)%)") do
            solid_counts[name] = tonumber(count) or 0
        end
    end

    -- Parse liquid (TINCTURES) section: collect herb name → count
    local liquid_counts = {}
    local liquid_section = full_text:match("contains TINCTUREs (.-)%.")
    if liquid_section then
        for name, count in liquid_section:gmatch(">([^<]+)</a>%s*%((%d+)%)") do
            liquid_counts[name] = tonumber(count) or 0
        end
    end

    -- Prefer solid herbs that have no liquid counterpart yet
    for name, _ in pairs(solid_counts) do
        if not liquid_counts[name] then
            fput("point #" .. M.container_id .. " at dose " .. name)
            return true
        end
    end

    -- Otherwise, distill the liquid herb with the lowest count that has a matching solid
    local best_target = nil
    local best_count = math.huge
    for name, count in pairs(liquid_counts) do
        if solid_counts[name] and count < best_count then
            best_count = count
            best_target = name
        end
    end

    if best_target then
        fput("point #" .. M.container_id .. " at dose " .. best_target)
        return true
    end

    return false
end

return M
