--- CreatureWindow runtime state and settings persistence.

local M = {}

-- Default settings
M.DEFAULTS = {
    single_column    = false,
    display_avg_ttk  = false,
    display_last_ttk = false,
    display_kpm      = false,
    display_bounty   = true,
}

-- Runtime state
M.single_column    = false
M.display_avg_ttk  = false
M.display_last_ttk = false
M.display_kpm      = false
M.display_bounty   = true

-- Recent lines buffer for custom status detection
M.recent_lines = {}
M.MAX_RECENT_LINES = 25

--- Load persisted settings from CharSettings.
function M.load()
    local stored = CharSettings.creaturewindow
    if stored then
        local ok, tbl = pcall(Json.decode, stored)
        if ok and type(tbl) == "table" then
            for k, default in pairs(M.DEFAULTS) do
                if tbl[k] ~= nil then
                    M[k] = tbl[k]
                else
                    M[k] = default
                end
            end
            return
        end
    end
    -- No stored settings — use defaults
    for k, v in pairs(M.DEFAULTS) do
        M[k] = v
    end
end

--- Save current settings to CharSettings.
function M.save()
    local tbl = {}
    for k, _ in pairs(M.DEFAULTS) do
        tbl[k] = M[k]
    end
    CharSettings.creaturewindow = Json.encode(tbl)
end

--- Push a line to the recent-lines ring buffer.
function M.push_recent_line(line)
    M.recent_lines[#M.recent_lines + 1] = line
    while #M.recent_lines > M.MAX_RECENT_LINES do
        table.remove(M.recent_lines, 1)
    end
end

--- Toggle a boolean setting, save, and return new value.
function M.toggle(key)
    M[key] = not M[key]
    M.save()
    return M[key]
end

return M
