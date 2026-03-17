--- @revenant-script
--- name: log
--- version: 1.0.0
--- author: elanthia-online
--- contributors: Tillmen, Tysong, Xanlin
--- game: gs
--- description: Log game output to text files with optional timestamps and room numbers
--- tags: logging,utility
---
--- Usage:
---   ;log                                    start logging
---   ;log --timestamp=%F_%T_%Z               add timestamps
---   ;log --rnum                             show Lich ID on room titles
---   ;log --exclude=u7199,288,2300           skip rooms by ID or UID
---   ;log --lines=50000                      lines per file (default 30000)
---
--- Logs to: <data_dir>/logs/<game>-<char>/<year>/<month>/<date_time>.log

local args = require("lib/args")

hide_me()

local opts = args.parse(Script.vars[0])

local stamp_enable = opts.timestamp and true or false
local stamp_format = opts.timestamp or "%F %T %Z"
local show_room_numbers = opts.rnum or opts.roomnum or false
local max_lines = tonumber(opts.lines) or 30000

-- Parse exclude list
local exclude_set = {}
if opts.exclude then
    for token in tostring(opts.exclude):gmatch("[^,]+") do
        exclude_set[token] = true
    end
end

local function is_excluded_room()
    local room_id = Map.current_room()
    if room_id and exclude_set[tostring(room_id)] then return true end
    local room_uid = GameState.room_id
    if room_uid and exclude_set["u" .. tostring(room_uid)] then return true end
    return false
end

local function get_log_dir()
    local base = (LICH_DIR or DATA_DIR or ".") .. "/logs"
    local game = GameState.game or "unknown"
    local name = GameState.name or "unknown"
    local year = os.date("%Y")
    local month = os.date("%m")
    return base .. "/" .. game .. "-" .. name .. "/" .. year .. "/" .. month
end

local function make_dirs(dir)
    os.execute('mkdir -p "' .. dir .. '"')
end

local function main()
    local started = false

    while true do
        local dir = get_log_dir()
        make_dirs(dir)
        local thisdate = os.date("%Y-%m-%d")
        local filename = dir .. "/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".log"
        local file = io.open(filename, "a")
        if not file then
            echo("log: cannot open " .. filename)
            return
        end

        file:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n")

        if not started then
            echo("Logging started: " .. filename)
            started = true
        end

        for _ = 1, max_lines do
            local line = get()
            if not line then break end

            -- Skip excluded rooms
            if is_excluded_room() then
                -- skip
            else
                -- Add room number to title if requested
                if show_room_numbers then
                    local room_title = GameState.room_title
                    if room_title and line:find(room_title, 1, true) then
                        local room_id = Map.current_room()
                        if room_id then
                            line = line:gsub("%]", " - " .. room_id .. "]", 1)
                        end
                    end
                end

                -- Skip push/pop stream lines
                if not line:match("^<push") and not line:match("^<pop") then
                    if stamp_enable then
                        file:write(os.date(stamp_format) .. ": " .. line .. "\n")
                    else
                        file:write(line .. "\n")
                    end
                end
            end

            -- Start new file if day changed
            if os.date("%Y-%m-%d") ~= thisdate then break end
        end

        file:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        file:close()
    end
end

main()
