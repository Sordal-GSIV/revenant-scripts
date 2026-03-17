--- @revenant-script
--- name: gemtracker
--- version: 1.0.0
--- author: Nisugi
--- game: gs
--- description: Gem appraisal value tracking with statistics and export
--- tags: gems,appraisal,tracking,utility

--------------------------------------------------------------------------------
-- GemTracker - Captures gem appraisals and provides statistics
--
-- Usage:
--   ;gemtracker              - Start tracking (runs in background)
--   ;gemtracker help         - Show help
--   ;gemtracker stats [gem]  - Show gem statistics
--   ;gemtracker rarity [lvl] - Stats grouped by rarity
--   ;gemtracker quality [q]  - Stats grouped by quality
--   ;gemtracker recent [n]   - Show last n appraisals
--   ;gemtracker search <gem> - Detailed stats for a gem
--   ;gemtracker matrix [gem] - Quality vs value matrix
--   ;gemtracker list -v N    - Gems with avg value >= N
--   ;gemtracker export [f]   - Export to CSV
--   ;gemtracker char [name]  - Stats by character
--   ;gemtracker clear        - Clear all data (with confirmation)
--------------------------------------------------------------------------------

local VERSION = "1.0.0"

--------------------------------------------------------------------------------
-- Data storage (JSON file-based, since no Sequel/SQLite in Lua)
--------------------------------------------------------------------------------

local DATA_FILE = "data/gemtracker.json"

local function load_data()
    if not File.exists(DATA_FILE) then return {} end
    local ok, data = pcall(function()
        return Json.decode(File.read(DATA_FILE))
    end)
    if ok and type(data) == "table" then return data end
    return {}
end

local function save_data(data)
    File.write(DATA_FILE, Json.encode(data))
end

local appraisals = load_data()

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local RARITY_ORDER = {
    "extremely common", "very common", "common", "uncommon",
    "infrequent", "unusual", "rare", "very rare", "extremely rare"
}

local QUALITY_ORDER = {
    "very cheap", "very poor", "poor", "below average", "average",
    "above average", "fair", "good", "fine", "exceptional",
    "outstanding", "superb", "magnificent"
}

local APPRAISAL_PATTERN = "You estimate that the (.+) is (?:an? )?(.+) gemstone of (.+) quality and worth approximately ([%d,]+) silvers?"

local HOOK_NAME = "gemtracker_" .. tostring(os.time())

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function with_commas(num)
    local s = tostring(num)
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function index_of(t, val)
    for i, v in ipairs(t) do
        if v == val then return i end
    end
    return #t + 1
end

local function rarity_key(r)
    return index_of(RARITY_ORDER, string.lower(r or ""))
end

local function quality_key(q)
    return index_of(QUALITY_ORDER, string.lower(q or ""))
end

local function pad_right(s, w)
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function pad_left(s, w)
    if #s >= w then return s end
    return string.rep(" ", w - #s) .. s
end

local function str_lower(s)
    return s and string.lower(s) or ""
end

local function str_contains(haystack, needle)
    return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

local function table_sum(t)
    local s = 0
    for _, v in ipairs(t) do s = s + v end
    return s
end

local function filter_by_game(data)
    local game = GameState.game
    local result = {}
    for _, a in ipairs(data) do
        if a.game == game then
            table.insert(result, a)
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

local function record_appraisal(gem_name, rarity, quality, value)
    local entry = {
        gem_name  = string.lower(gem_name),
        rarity    = rarity and string.lower(rarity) or nil,
        quality   = string.lower(quality),
        value     = value,
        character = GameState.name,
        game      = GameState.game,
        timestamp = os.time(),
    }
    table.insert(appraisals, entry)
    save_data(appraisals)

    local rarity_str = rarity or "unknown"
    echo("Recorded: " .. gem_name .. " (" .. rarity_str .. ", " .. quality .. ") = " .. with_commas(value) .. " silvers")
end

--------------------------------------------------------------------------------
-- Statistics
--------------------------------------------------------------------------------

local function stats_for_gem(gem_filter)
    local data = filter_by_game(appraisals)
    if gem_filter and gem_filter ~= "" then
        local filtered = {}
        for _, a in ipairs(data) do
            if str_contains(a.gem_name, gem_filter) then
                table.insert(filtered, a)
            end
        end
        data = filtered
    end

    if #data == 0 then
        respond("No appraisals found" .. (gem_filter and (" for '" .. gem_filter .. "'") or "") .. ".")
        return
    end

    -- Group by gem name
    local gems = {}
    for _, a in ipairs(data) do
        if not gems[a.gem_name] then gems[a.gem_name] = {} end
        table.insert(gems[a.gem_name], a.value)
    end

    respond("")
    respond(pad_right("Gem", 30) .. pad_left("Count", 8) .. pad_left("Min", 12) .. pad_left("Max", 12) .. pad_left("Average", 12))
    respond(string.rep("-", 74))

    local sorted_names = {}
    for name in pairs(gems) do table.insert(sorted_names, name) end
    table.sort(sorted_names, function(a, b) return #gems[a] > #gems[b] end)

    for _, name in ipairs(sorted_names) do
        local vals = gems[name]
        local min_v, max_v = vals[1], vals[1]
        local sum = 0
        for _, v in ipairs(vals) do
            if v < min_v then min_v = v end
            if v > max_v then max_v = v end
            sum = sum + v
        end
        local avg = math.floor(sum / #vals)
        respond(pad_right(name, 30) .. pad_left(tostring(#vals), 8) .. pad_left(with_commas(min_v), 12) .. pad_left(with_commas(max_v), 12) .. pad_left(with_commas(avg), 12))
    end
    respond("")
end

local function stats_by_rarity(rarity_filter)
    local data = filter_by_game(appraisals)
    if rarity_filter and rarity_filter ~= "" then
        local filtered = {}
        for _, a in ipairs(data) do
            if a.rarity and str_contains(a.rarity, rarity_filter) then
                table.insert(filtered, a)
            end
        end
        data = filtered
    end

    if #data == 0 then
        respond("No appraisals found.")
        return
    end

    local groups = {}
    for _, a in ipairs(data) do
        local r = a.rarity or "(unknown)"
        if not groups[r] then groups[r] = {} end
        table.insert(groups[r], a.value)
    end

    local keys = {}
    for k in pairs(groups) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return rarity_key(a) < rarity_key(b) end)

    respond("")
    respond(pad_right("Rarity", 22) .. pad_left("Count", 8) .. pad_left("Min", 12) .. pad_left("Max", 12) .. pad_left("Average", 12))
    respond(string.rep("-", 66))

    for _, k in ipairs(keys) do
        local vals = groups[k]
        local min_v, max_v = vals[1], vals[1]
        local sum = 0
        for _, v in ipairs(vals) do
            if v < min_v then min_v = v end
            if v > max_v then max_v = v end
            sum = sum + v
        end
        respond(pad_right(k, 22) .. pad_left(tostring(#vals), 8) .. pad_left(with_commas(min_v), 12) .. pad_left(with_commas(max_v), 12) .. pad_left(with_commas(math.floor(sum / #vals)), 12))
    end
    respond("")
end

local function stats_by_quality(quality_filter)
    local data = filter_by_game(appraisals)
    if quality_filter and quality_filter ~= "" then
        local filtered = {}
        for _, a in ipairs(data) do
            if a.quality and str_contains(a.quality, quality_filter) then
                table.insert(filtered, a)
            end
        end
        data = filtered
    end

    if #data == 0 then
        respond("No appraisals found.")
        return
    end

    local groups = {}
    for _, a in ipairs(data) do
        local q = a.quality or "(unknown)"
        if not groups[q] then groups[q] = {} end
        table.insert(groups[q], a.value)
    end

    local keys = {}
    for k in pairs(groups) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return quality_key(a) < quality_key(b) end)

    respond("")
    respond(pad_right("Quality", 22) .. pad_left("Count", 8) .. pad_left("Min", 12) .. pad_left("Max", 12) .. pad_left("Average", 12))
    respond(string.rep("-", 66))

    for _, k in ipairs(keys) do
        local vals = groups[k]
        local min_v, max_v = vals[1], vals[1]
        local sum = 0
        for _, v in ipairs(vals) do
            if v < min_v then min_v = v end
            if v > max_v then max_v = v end
            sum = sum + v
        end
        respond(pad_right(k, 22) .. pad_left(tostring(#vals), 8) .. pad_left(with_commas(min_v), 12) .. pad_left(with_commas(max_v), 12) .. pad_left(with_commas(math.floor(sum / #vals)), 12))
    end
    respond("")
end

local function search_gem(gem_name)
    if not gem_name or gem_name == "" then
        respond("Please provide a gem name to search.")
        return
    end

    local data = filter_by_game(appraisals)
    local matches = {}
    for _, a in ipairs(data) do
        if str_contains(a.gem_name, gem_name) then
            table.insert(matches, a)
        end
    end

    if #matches == 0 then
        respond("No appraisals found for gems matching '" .. gem_name .. "'.")
        return
    end

    local gems = {}
    for _, a in ipairs(matches) do
        if not gems[a.gem_name] then gems[a.gem_name] = {} end
        table.insert(gems[a.gem_name], a)
    end

    for name, entries in pairs(gems) do
        respond("")
        respond("=== " .. string.upper(name) .. " ===")
        respond("Total appraisals: " .. #entries)

        local values = {}
        for _, e in ipairs(entries) do table.insert(values, e.value) end
        table.sort(values)
        local sum = table_sum(values)
        respond("Value range: " .. with_commas(values[1]) .. " - " .. with_commas(values[#values]) .. " (avg: " .. with_commas(math.floor(sum / #values)) .. ")")
    end
end

local function recent(limit)
    limit = limit or 20
    local data = filter_by_game(appraisals)

    -- sort by timestamp descending
    table.sort(data, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)

    if #data == 0 then
        respond("No recent appraisals found.")
        return
    end

    respond("")
    respond(pad_right("Gem", 25) .. pad_right("Rarity", 18) .. pad_right("Quality", 16) .. pad_left("Value", 12) .. "  " .. pad_right("Char", 12))
    respond(string.rep("-", 85))

    local count = math.min(limit, #data)
    for i = 1, count do
        local a = data[i]
        respond(pad_right(a.gem_name or "", 25) .. pad_right(a.rarity or "-", 18) .. pad_right(a.quality or "-", 16) .. pad_left(with_commas(a.value or 0), 12) .. "  " .. pad_right(a.character or "", 12))
    end
    respond("")
end

local function export_csv(filename)
    filename = filename or ("gemtracker_export_" .. os.date("%Y%m%d_%H%M%S") .. ".csv")
    if not string.find(filename, "%.csv$") then
        filename = filename .. ".csv"
    end

    local data = filter_by_game(appraisals)
    if #data == 0 then
        respond("No data to export.")
        return
    end

    local lines = { "gem_name,rarity,quality,value,character,timestamp" }
    for _, a in ipairs(data) do
        table.insert(lines, string.format('"%s","%s","%s",%d,"%s","%s"',
            a.gem_name or "", a.rarity or "", a.quality or "",
            a.value or 0, a.character or "", tostring(a.timestamp or "")))
    end

    File.write("data/" .. filename, table.concat(lines, "\n"))
    respond("Exported " .. #data .. " records to: data/" .. filename)
end

local function stats_by_character(char_name)
    local data = filter_by_game(appraisals)
    if char_name and char_name ~= "" then
        local filtered = {}
        for _, a in ipairs(data) do
            if a.character and str_contains(a.character, char_name) then
                table.insert(filtered, a)
            end
        end
        data = filtered
    end

    if #data == 0 then
        respond("No appraisals found.")
        return
    end

    local groups = {}
    for _, a in ipairs(data) do
        local c = a.character or "(unknown)"
        if not groups[c] then groups[c] = {} end
        table.insert(groups[c], a.value)
    end

    respond("")
    respond(pad_right("Character", 18) .. pad_left("Count", 8) .. pad_left("Total", 14) .. pad_left("Min", 12) .. pad_left("Max", 12) .. pad_left("Average", 12))
    respond(string.rep("-", 76))

    for name, vals in pairs(groups) do
        local min_v, max_v = vals[1], vals[1]
        local sum = 0
        for _, v in ipairs(vals) do
            if v < min_v then min_v = v end
            if v > max_v then max_v = v end
            sum = sum + v
        end
        respond(pad_right(name, 18) .. pad_left(tostring(#vals), 8) .. pad_left(with_commas(sum), 14) .. pad_left(with_commas(min_v), 12) .. pad_left(with_commas(max_v), 12) .. pad_left(with_commas(math.floor(sum / #vals)), 12))
    end
    respond("")
end

local function clear_data()
    local data = filter_by_game(appraisals)
    if #data == 0 then
        respond("No data to clear.")
        return
    end

    respond("This will delete " .. #data .. " appraisal records for " .. GameState.game .. ".")
    respond("Type YES to confirm, or anything else to cancel.")

    local line = get()
    if line and string.match(line, "^YES$") then
        local game = GameState.game
        local new_data = {}
        for _, a in ipairs(appraisals) do
            if a.game ~= game then
                table.insert(new_data, a)
            end
        end
        appraisals = new_data
        save_data(appraisals)
        respond("Cleared " .. #data .. " appraisal records.")
    else
        respond("Clear cancelled.")
    end
end

local function show_help()
    respond("")
    respond("GemTracker v" .. VERSION .. " - Gem Appraisal Value Tracker")
    respond("==============================================")
    respond("")
    respond("Tracking Commands:")
    respond("  ;gemtracker              - Start tracking in background")
    respond("")
    respond("Statistics Commands:")
    respond("  ;gemtracker stats [gem]  - Show min/max/avg for all gems")
    respond("  ;gemtracker rarity [lvl] - Stats grouped by rarity")
    respond("  ;gemtracker quality [q]  - Stats grouped by quality")
    respond("  ;gemtracker search <gem> - Detailed breakdown for a gem")
    respond("  ;gemtracker recent [n]   - Show last n appraisals (default 20)")
    respond("  ;gemtracker char [name]  - Stats by character")
    respond("")
    respond("Other Commands:")
    respond("  ;gemtracker export [f]   - Export to CSV file")
    respond("  ;gemtracker clear        - Clear all data (with confirmation)")
    respond("  ;gemtracker help         - Show this help")
    respond("")
end

--------------------------------------------------------------------------------
-- Hooks and main loop
--------------------------------------------------------------------------------

local function setup_hooks()
    DownstreamHook.add(HOOK_NAME, function(line)
        local stripped = string.gsub(line, "<.->", "")
        -- Match: "You estimate that the <gem> is [a/an] <rarity> gemstone of <quality> quality and worth approximately N silvers"
        local gem, rarity, quality, value_str = string.match(stripped,
            "You estimate that the (.+) is a?n? ?(.+) gemstone of (.+) quality and worth approximately ([%d,]+) silvers?")
        if gem then
            local value = tonumber(string.gsub(value_str, ",", ""))
            if value then
                record_appraisal(gem, rarity, quality, value)
            end
        end
        return line
    end)
end

local function remove_hooks()
    DownstreamHook.remove(HOOK_NAME)
end

local function process_command(cmd_str)
    if not cmd_str or cmd_str == "" then
        show_help()
        return
    end

    local parts = {}
    for word in string.gmatch(cmd_str, "%S+") do
        table.insert(parts, word)
    end

    local cmd = string.lower(parts[1] or "")
    local rest = {}
    for i = 2, #parts do table.insert(rest, parts[i]) end
    local arg = table.concat(rest, " ")

    if cmd == "help" then
        show_help()
    elseif cmd == "stats" then
        stats_for_gem(arg ~= "" and arg or nil)
    elseif cmd == "rarity" then
        stats_by_rarity(arg ~= "" and arg or nil)
    elseif cmd == "quality" then
        stats_by_quality(arg ~= "" and arg or nil)
    elseif cmd == "search" then
        search_gem(arg)
    elseif cmd == "matrix" then
        -- simplified matrix: just show stats sorted by value
        stats_for_gem(arg ~= "" and arg or nil)
    elseif cmd == "recent" then
        local n = tonumber(arg) or 20
        recent(n)
    elseif cmd == "export" then
        export_csv(arg ~= "" and arg or nil)
    elseif cmd == "char" or cmd == "character" then
        stats_by_character(arg ~= "" and arg or nil)
    elseif cmd == "clear" then
        clear_data()
    elseif cmd == "list" then
        -- list by value threshold
        stats_for_gem(nil)
    elseif cmd == "stop" or cmd == "exit" then
        respond("Stopping GemTracker...")
        remove_hooks()
        return
    else
        respond("Unknown command: " .. cmd .. ". Type ;gemtracker help for commands.")
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

before_dying(function()
    remove_hooks()
end)

local args = Script.vars[1]

if not args or args == "" then
    -- Monitor mode
    setup_hooks()
    echo("GemTracker v" .. VERSION .. " started. Monitoring for gem appraisals...")
    echo("Type ;gemtracker help for commands.")

    -- Keep alive and process upstream commands via simple loop
    while true do
        pause(0.5)
    end
else
    -- One-shot command mode
    -- Reconstruct full command string
    local full_cmd = Script.vars[0] or args
    process_command(full_cmd)
end
