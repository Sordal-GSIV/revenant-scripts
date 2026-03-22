--- @revenant-script
--- name: gemtracker
--- version: 1.1.0
--- author: Nisugi
--- game: gs
--- description: Gem appraisal value tracking with statistics, purify comparison, and Google Sheets export
--- tags: gems,appraisal,tracking,utility
--- @lic-certified: complete 2026-03-18

--------------------------------------------------------------------------------
-- GemTracker - Captures gem appraisals and provides statistics
--
-- Usage:
--   ;gemtracker              - Start tracking (runs in background)
--   ;gemtracker help         - Show help
--   ;gemtracker stats [gem]  - Show gem statistics
--   ;gemtracker rarity [lvl] - Stats grouped by rarity (per-gem detail when filtered)
--   ;gemtracker quality [q]  - Stats grouped by quality (per-gem detail when filtered)
--   ;gemtracker recent [n]   - Show last n appraisals
--   ;gemtracker search <gem> - Detailed stats for a gem
--   ;gemtracker matrix [gem] - Quality vs value matrix (alphabetical)
--   ;gemtracker matrix -v [gem]    - Matrix sorted by avg value (low to high)
--   ;gemtracker matrix -vd [gem]   - Matrix sorted by avg value (high to low)
--   ;gemtracker matrix -export     - Export matrix to CSV
--   ;gemtracker list -v N    - Gems with avg value >= N
--   ;gemtracker list -vd N   - Gems with avg value <= N
--   ;gemtracker purify [gem] - Compare raw vs purified gem values
--   ;gemtracker export [f]   - Export to CSV
--   ;gemtracker char [name]  - Stats by character
--   ;gemtracker clear        - Clear all data (with confirmation)
--   ;gemtracker sheets ...   - Google Sheets integration (see ;gemtracker sheets help)
--
-- Shorthand: Once tracking, use ;gem instead of ;gemtracker
--   Example: ;gem stats, ;gem matrix, ;gem purify, ;gem sheets push
--------------------------------------------------------------------------------

local VERSION = "1.1.0"

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

-- PCRE regex via Revenant Regex module (Lua patterns cannot express non-capturing groups)
local APPRAISAL_RE = Regex.new("You estimate that the (.+?) is (?:an? )?(.+?) gemstone of (.+?) quality and worth approximately ([\\d,]+) silvers?")

local HOOK_NAME = "gemtracker_" .. tostring(os.time())
local UPSTREAM_HOOK_NAME = "gemtracker_upstream_" .. tostring(os.time())

-- Purified gem tracking (for loresinging integration)
local mark_next_purified = false

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

-- Compute stats (count, min, max, avg) for a list of numeric values
local function compute_stats(vals)
    if #vals == 0 then return nil end
    local min_v, max_v = vals[1], vals[1]
    local sum = 0
    for _, v in ipairs(vals) do
        if v < min_v then min_v = v end
        if v > max_v then max_v = v end
        sum = sum + v
    end
    return {
        count = #vals,
        min   = min_v,
        max   = max_v,
        avg   = math.floor(sum / #vals),
    }
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

local function record_appraisal(gem_name, rarity, quality, value, gem_id)
    local purified = mark_next_purified
    mark_next_purified = false

    local entry = {
        gem_name  = string.lower(gem_name),
        rarity    = rarity and string.lower(rarity) or nil,
        quality   = string.lower(quality),
        value     = value,
        character = GameState.name,
        game      = GameState.game,
        timestamp = os.time(),
        purified  = purified,
        gem_id    = gem_id,
    }
    table.insert(appraisals, entry)
    save_data(appraisals)

    local purified_str = purified and " [PURIFIED]" or ""
    local rarity_str = rarity or "unknown"
    echo("Recorded: " .. gem_name .. " (" .. rarity_str .. ", " .. quality .. ") = " .. with_commas(value) .. " silvers" .. purified_str)
end

--- Look up the most common rarity for a gem name.
--- @param gem_name string
--- @return string|nil the most common rarity, or nil if none found
local function lookup_rarity(gem_name)
    if not gem_name or gem_name == "" then return nil end

    local data = filter_by_game(appraisals)
    local counts = {}
    local target = string.lower(gem_name)
    for _, a in ipairs(data) do
        if a.gem_name == target and a.rarity then
            counts[a.rarity] = (counts[a.rarity] or 0) + 1
        end
    end

    local best_rarity, best_count = nil, 0
    for r, c in pairs(counts) do
        if c > best_count then
            best_rarity = r
            best_count = c
        end
    end
    return best_rarity
end

--- Public API for other scripts (like purify integration).
--- @param opts table with gem_id, gem_name, quality, value, purified fields
local function record_loresing(opts)
    mark_next_purified = opts.purified or false
    local rarity = lookup_rarity(opts.gem_name)
    record_appraisal(opts.gem_name, rarity, opts.quality, opts.value, opts.gem_id)
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
        local s = compute_stats(gems[name])
        respond(pad_right(name, 30) .. pad_left(tostring(s.count), 8) .. pad_left(with_commas(s.min), 12) .. pad_left(with_commas(s.max), 12) .. pad_left(with_commas(s.avg), 12))
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
        local s = compute_stats(groups[k])
        respond(pad_right(k, 22) .. pad_left(tostring(s.count), 8) .. pad_left(with_commas(s.min), 12) .. pad_left(with_commas(s.max), 12) .. pad_left(with_commas(s.avg), 12))
    end
    respond("")

    -- Per-gem detail when a rarity filter is provided
    if rarity_filter and rarity_filter ~= "" then
        local gem_groups = {}
        for _, a in ipairs(data) do
            if not gem_groups[a.gem_name] then gem_groups[a.gem_name] = {} end
            table.insert(gem_groups[a.gem_name], a.value)
        end

        local gem_names = {}
        for name in pairs(gem_groups) do table.insert(gem_names, name) end
        table.sort(gem_names, function(a, b)
            local avg_a = table_sum(gem_groups[a]) / #gem_groups[a]
            local avg_b = table_sum(gem_groups[b]) / #gem_groups[b]
            return avg_a > avg_b
        end)

        respond("Gems with '" .. rarity_filter .. "' rarity:")
        respond(pad_right("Gem", 30) .. pad_left("Count", 8) .. pad_left("Min", 12) .. pad_left("Max", 12) .. pad_left("Average", 12))
        respond(string.rep("-", 74))
        for _, name in ipairs(gem_names) do
            local s = compute_stats(gem_groups[name])
            respond(pad_right(name, 30) .. pad_left(tostring(s.count), 8) .. pad_left(with_commas(s.min), 12) .. pad_left(with_commas(s.max), 12) .. pad_left(with_commas(s.avg), 12))
        end
        respond("")
    end
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
        local s = compute_stats(groups[k])
        respond(pad_right(k, 22) .. pad_left(tostring(s.count), 8) .. pad_left(with_commas(s.min), 12) .. pad_left(with_commas(s.max), 12) .. pad_left(with_commas(s.avg), 12))
    end
    respond("")

    -- Per-gem detail when a quality filter is provided
    if quality_filter and quality_filter ~= "" then
        local gem_groups = {}
        for _, a in ipairs(data) do
            if not gem_groups[a.gem_name] then gem_groups[a.gem_name] = {} end
            table.insert(gem_groups[a.gem_name], a.value)
        end

        local gem_names = {}
        for name in pairs(gem_groups) do table.insert(gem_names, name) end
        table.sort(gem_names, function(a, b)
            local avg_a = table_sum(gem_groups[a]) / #gem_groups[a]
            local avg_b = table_sum(gem_groups[b]) / #gem_groups[b]
            return avg_a > avg_b
        end)

        respond("Gems with '" .. quality_filter .. "' quality:")
        respond(pad_right("Gem", 30) .. pad_left("Count", 8) .. pad_left("Min", 12) .. pad_left("Max", 12) .. pad_left("Average", 12))
        respond(string.rep("-", 74))
        for _, name in ipairs(gem_names) do
            local s = compute_stats(gem_groups[name])
            respond(pad_right(name, 30) .. pad_left(tostring(s.count), 8) .. pad_left(with_commas(s.min), 12) .. pad_left(with_commas(s.max), 12) .. pad_left(with_commas(s.avg), 12))
        end
        respond("")
    end
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

--------------------------------------------------------------------------------
-- Matrix view: quality-vs-gem-name grid showing count/average per cell
--------------------------------------------------------------------------------

local QUALITY_SHORT = {
    ["extremely common"] = "ext com",
    ["very common"]      = "v com",
    ["below average"]    = "below avg",
    ["above average"]    = "above avg",
    ["very poor"]        = "v poor",
    ["very good"]        = "v good",
    ["very cheap"]       = "v cheap",
}

local function matrix_view(gem_filter, sort_mode, do_export)
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
        respond("No appraisals found" .. (gem_filter and (" for gems matching '" .. gem_filter .. "'") or "") .. ".")
        return
    end

    -- Collect all quality levels present
    local quality_set = {}
    local all_qualities = {}
    for _, a in ipairs(data) do
        if a.quality and not quality_set[a.quality] then
            quality_set[a.quality] = true
            table.insert(all_qualities, a.quality)
        end
    end
    table.sort(all_qualities, function(a, b) return quality_key(a) < quality_key(b) end)

    -- Group by gem name
    local gems = {}
    for _, a in ipairs(data) do
        if not gems[a.gem_name] then gems[a.gem_name] = {} end
        table.insert(gems[a.gem_name], a)
    end

    -- Compute average value per gem
    local gem_avg = {}
    for name, entries in pairs(gems) do
        local sum = 0
        for _, e in ipairs(entries) do sum = sum + e.value end
        gem_avg[name] = sum / #entries
    end

    -- Sort gem names
    local sorted_names = {}
    for name in pairs(gems) do table.insert(sorted_names, name) end
    if sort_mode == "value_asc" then
        table.sort(sorted_names, function(a, b) return gem_avg[a] < gem_avg[b] end)
    elseif sort_mode == "value_desc" then
        table.sort(sorted_names, function(a, b) return gem_avg[a] > gem_avg[b] end)
    else
        table.sort(sorted_names)
    end

    -- Build rows: [name, rarity, avg_value, quality1_range, quality2_range, ...]
    local rows = {}
    for _, name in ipairs(sorted_names) do
        local entries = gems[name]

        -- Most common rarity
        local rarity_counts = {}
        for _, a in ipairs(entries) do
            if a.rarity then
                rarity_counts[a.rarity] = (rarity_counts[a.rarity] or 0) + 1
            end
        end
        local best_rarity, best_count = "-", 0
        for r, c in pairs(rarity_counts) do
            if c > best_count then best_rarity = r; best_count = c end
        end

        local avg_val = math.floor(gem_avg[name])
        local row = { name, best_rarity, avg_val }

        for _, q in ipairs(all_qualities) do
            local matching = {}
            for _, a in ipairs(entries) do
                if a.quality == q then table.insert(matching, a.value) end
            end
            if #matching == 0 then
                table.insert(row, "-")
            else
                local s = compute_stats(matching)
                if s.min == s.max then
                    table.insert(row, do_export and tostring(s.min) or with_commas(s.min))
                else
                    if do_export then
                        table.insert(row, tostring(s.min) .. "-" .. tostring(s.max))
                    else
                        table.insert(row, with_commas(s.min) .. "-" .. with_commas(s.max))
                    end
                end
            end
        end

        table.insert(rows, row)
    end

    -- Export to CSV
    if do_export then
        local filename = "gemtracker_matrix_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
        local csv_headers = { '"gem_name"', '"rarity"', '"avg_value"' }
        for _, q in ipairs(all_qualities) do
            table.insert(csv_headers, '"' .. q .. '"')
        end
        local lines = { table.concat(csv_headers, ",") }
        for _, row in ipairs(rows) do
            local csv_row = {}
            for i, cell in ipairs(row) do
                if i == 3 then
                    table.insert(csv_row, tostring(cell))
                else
                    table.insert(csv_row, '"' .. tostring(cell) .. '"')
                end
            end
            table.insert(lines, table.concat(csv_row, ","))
        end
        File.write("data/" .. filename, table.concat(lines, "\n"))
        respond("Exported matrix (" .. #rows .. " gems x " .. #all_qualities .. " qualities) to: data/" .. filename)
        return
    end

    -- Display table
    local headers = { "Gem", "Rarity", "Avg Value" }
    for _, q in ipairs(all_qualities) do
        table.insert(headers, QUALITY_SHORT[q] or q)
    end

    -- Compute column widths
    local col_widths = {}
    for i, h in ipairs(headers) do col_widths[i] = #h end
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            local s = (i == 3) and with_commas(cell) or tostring(cell)
            if #s > (col_widths[i] or 0) then col_widths[i] = #s end
        end
    end

    -- Print header
    respond("")
    local header_parts = {}
    for i, h in ipairs(headers) do
        if i <= 2 then
            table.insert(header_parts, pad_right(h, col_widths[i] + 1))
        else
            table.insert(header_parts, pad_left(h, col_widths[i] + 1))
        end
    end
    respond(table.concat(header_parts))

    local total_width = 0
    for _, w in ipairs(col_widths) do total_width = total_width + w + 1 end
    respond(string.rep("-", total_width))

    -- Print rows
    for _, row in ipairs(rows) do
        local parts = {}
        for i, cell in ipairs(row) do
            local s = (i == 3) and with_commas(cell) or tostring(cell)
            if i <= 2 then
                table.insert(parts, pad_right(s, col_widths[i] + 1))
            else
                table.insert(parts, pad_left(s, col_widths[i] + 1))
            end
        end
        respond(table.concat(parts))
    end
    respond("")
    respond("Legend: Values show min-max range for each gem/quality combination.")
    respond("Columns are quality levels, sorted from lowest to highest.")
end

--------------------------------------------------------------------------------
-- Purify comparison: raw vs purified gem values
--------------------------------------------------------------------------------

local function purify_stats(gem_filter)
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

    -- Split into raw and purified
    local raw_by_gem     = {}
    local purified_by_gem = {}
    for _, a in ipairs(data) do
        if a.purified then
            if not purified_by_gem[a.gem_name] then purified_by_gem[a.gem_name] = {} end
            table.insert(purified_by_gem[a.gem_name], a.value)
        else
            if not raw_by_gem[a.gem_name] then raw_by_gem[a.gem_name] = {} end
            table.insert(raw_by_gem[a.gem_name], a.value)
        end
    end

    -- Check for any purified data at all
    local has_purified = false
    for _ in pairs(purified_by_gem) do has_purified = true; break end

    if not has_purified then
        respond("No purified gem data yet. Run ;purify with GemTracker active to collect data.")
        return
    end

    -- Find gems with both raw and purified data
    local rows = {}
    local all_gems = {}
    local seen = {}
    for name in pairs(raw_by_gem)     do if not seen[name] then seen[name]=true; table.insert(all_gems, name) end end
    for name in pairs(purified_by_gem) do if not seen[name] then seen[name]=true; table.insert(all_gems, name) end end
    table.sort(all_gems)

    for _, name in ipairs(all_gems) do
        local raw = raw_by_gem[name]
        local pur = purified_by_gem[name]
        if not (raw and pur) then goto continue end

        local rs = compute_stats(raw)
        local ps = compute_stats(pur)
        local gain     = ps.avg - rs.avg
        local gain_pct = rs.avg > 0 and ((gain / rs.avg) * 100) or 0

        table.insert(rows, {
            name     = name,
            raw_cnt  = rs.count,
            raw_min  = rs.min,
            raw_max  = rs.max,
            raw_avg  = rs.avg,
            pur_cnt  = ps.count,
            pur_min  = ps.min,
            pur_max  = ps.max,
            pur_avg  = ps.avg,
            gain     = gain,
            gain_pct = gain_pct,
        })
        ::continue::
    end

    if #rows == 0 then
        respond("No gems found with both raw and purified data" .. (gem_filter and (" matching '" .. gem_filter .. "'") or "") .. ".")
        respond("Keep running ;purify with GemTracker active to collect comparison data.")
        return
    end

    -- Sort by gain% descending
    table.sort(rows, function(a, b) return a.gain_pct > b.gain_pct end)

    respond("")
    respond("Raw vs Purified Gem Value Comparison")
    respond("=====================================")
    respond("")
    respond(
        pad_right("Gem", 28) ..
        pad_left("Raw#",  5) .. "  " ..
        pad_left("Raw Range",   16) ..
        pad_left("Raw Avg",     10) .. "  " ..
        pad_left("Pur#",  5) .. "  " ..
        pad_left("Pur Range",   16) ..
        pad_left("Pur Avg",     10) .. "  " ..
        "Gain"
    )
    respond(string.rep("-", 120))

    local total_gain_pct = 0
    for _, r in ipairs(rows) do
        local raw_range = with_commas(r.raw_min) .. "-" .. with_commas(r.raw_max)
        local pur_range = with_commas(r.pur_min) .. "-" .. with_commas(r.pur_max)
        local gain_str  = string.format("+%s (+%.1f%%)", with_commas(r.gain), r.gain_pct)
        respond(
            pad_right(r.name, 28) ..
            pad_left(tostring(r.raw_cnt),      5) .. "  " ..
            pad_left(raw_range,               16) ..
            pad_left(with_commas(r.raw_avg),  10) .. "  " ..
            pad_left(tostring(r.pur_cnt),      5) .. "  " ..
            pad_left(pur_range,               16) ..
            pad_left(with_commas(r.pur_avg),  10) .. "  " ..
            gain_str
        )
        total_gain_pct = total_gain_pct + r.gain_pct
    end

    respond("")
    respond(string.format("Summary: Purification provides ~%.1f%% average value increase across %d gems.", total_gain_pct / #rows, #rows))
    respond("")
end

--------------------------------------------------------------------------------
-- List by value threshold
--------------------------------------------------------------------------------

local function list_by_value(threshold, mode)
    local data = filter_by_game(appraisals)
    if #data == 0 then
        respond("No appraisals found.")
        return
    end

    -- Group by gem name and compute averages
    local gems = {}
    for _, a in ipairs(data) do
        if not gems[a.gem_name] then gems[a.gem_name] = {} end
        table.insert(gems[a.gem_name], a.value)
    end

    local gem_avg = {}
    for name, vals in pairs(gems) do
        gem_avg[name] = table_sum(vals) / #vals
    end

    -- Filter by threshold
    local filtered = {}
    for name, avg in pairs(gem_avg) do
        if mode == "gte" and avg >= threshold then
            table.insert(filtered, { name = name, avg = avg, count = #gems[name] })
        elseif mode == "lte" and avg <= threshold then
            table.insert(filtered, { name = name, avg = avg, count = #gems[name] })
        end
    end

    if #filtered == 0 then
        local op = mode == "gte" and ">=" or "<="
        respond("No gems found with average value " .. op .. " " .. with_commas(threshold) .. ".")
        return
    end

    -- Sort: gte ascending, lte descending
    if mode == "gte" then
        table.sort(filtered, function(a, b) return a.avg < b.avg end)
    else
        table.sort(filtered, function(a, b) return a.avg > b.avg end)
    end

    local op = mode == "gte" and ">=" or "<="
    respond("")
    respond("Gems with avg value " .. op .. " " .. with_commas(threshold) .. " (" .. #filtered .. " found):")
    respond(pad_right("Gem", 30) .. pad_left("Count", 8) .. pad_left("Average", 12))
    respond(string.rep("-", 50))
    for _, entry in ipairs(filtered) do
        respond(pad_right(entry.name, 30) .. pad_left(tostring(entry.count), 8) .. pad_left(with_commas(math.floor(entry.avg)), 12))
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

    local lines = { "gem_name,rarity,quality,value,character,timestamp,purified" }
    for _, a in ipairs(data) do
        table.insert(lines, string.format('"%s","%s","%s",%d,"%s","%s","%s"',
            a.gem_name or "", a.rarity or "", a.quality or "",
            a.value or 0, a.character or "", tostring(a.timestamp or ""),
            a.purified and "Yes" or "No"))
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
        local s = compute_stats(vals)
        local total = table_sum(vals)
        respond(pad_right(name, 18) .. pad_left(tostring(s.count), 8) .. pad_left(with_commas(total), 14) .. pad_left(with_commas(s.min), 12) .. pad_left(with_commas(s.max), 12) .. pad_left(with_commas(s.avg), 12))
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

--------------------------------------------------------------------------------
-- Google Sheets integration
-- Uses service account JWT authentication (RS256) via the Sheets REST API v4.
-- Config stored in UserVars: gemtracker_sheets_keyfile, gemtracker_sheets_id, gemtracker_sheets_last_push
--------------------------------------------------------------------------------

local GoogleSheets = {}

local SHEETS_TOKEN_URL = "https://oauth2.googleapis.com/token"
local SHEETS_SCOPE     = "https://www.googleapis.com/auth/spreadsheets"
local SHEETS_API_BASE  = "https://sheets.googleapis.com/v4/spreadsheets"

-- Build a Google OAuth2 JWT and exchange it for an access token.
-- Returns: access_token string or nil, error string
local function google_get_access_token(keyfile_path)
    -- Read and parse the service account JSON
    if not File.exists(keyfile_path) then
        return nil, "key file not found: " .. keyfile_path
    end
    local raw = File.read(keyfile_path)
    local key_data, jerr = Json.decode(raw)
    if not key_data then
        return nil, "failed to parse key file: " .. tostring(jerr)
    end
    if key_data.type ~= "service_account" then
        return nil, "key file is not a service_account type"
    end

    local client_email = key_data.client_email
    local private_key  = key_data.private_key
    if not client_email or not private_key then
        return nil, "key file missing client_email or private_key"
    end

    -- Build JWT: header.payload (base64url, no padding)
    local now = os.time()
    local header  = Crypto.base64url_encode('{"alg":"RS256","typ":"JWT"}')
    local payload = Crypto.base64url_encode(Json.encode({
        iss   = client_email,
        scope = SHEETS_SCOPE,
        aud   = SHEETS_TOKEN_URL,
        iat   = now,
        exp   = now + 3600,
    }))
    local signing_input = header .. "." .. payload

    local sig, sign_err = Crypto.rsa_sign_pkcs1v15_sha256(private_key, signing_input)
    if not sig then
        return nil, "RSA sign failed: " .. tostring(sign_err)
    end

    local jwt = signing_input .. "." .. sig

    -- Exchange JWT for access token
    local body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" .. jwt
    local resp, herr = Http.post(SHEETS_TOKEN_URL, body, {
        ["Content-Type"] = "application/x-www-form-urlencoded",
    })
    if not resp then
        return nil, "token request failed: " .. tostring(herr)
    end
    if resp.status ~= 200 then
        return nil, "token endpoint returned HTTP " .. resp.status .. ": " .. (resp.body or "")
    end
    local token_data, terr = Json.decode(resp.body)
    if not token_data or not token_data.access_token then
        return nil, "failed to parse token response: " .. tostring(terr)
    end
    return token_data.access_token, nil
end

-- Ensure the named sheet tabs exist in the spreadsheet.
local function sheets_ensure_tabs(token, spreadsheet_id, names)
    -- Get current sheets
    local url = SHEETS_API_BASE .. "/" .. spreadsheet_id .. "?fields=sheets.properties.title"
    local resp, err = Http.request("GET", url, nil, {
        Authorization = "Bearer " .. token,
    })
    if not resp or resp.status ~= 200 then
        return nil, "could not list sheets: " .. tostring(err or resp and resp.status)
    end
    local info, jerr = Json.decode(resp.body)
    if not info then return nil, "parse error: " .. tostring(jerr) end

    local existing = {}
    for _, sheet in ipairs(info.sheets or {}) do
        existing[sheet.properties.title] = true
    end

    local requests = {}
    for _, name in ipairs(names) do
        if not existing[name] then
            table.insert(requests, {
                addSheet = { properties = { title = name } }
            })
        end
    end

    if #requests == 0 then return true, nil end

    local batch_url = SHEETS_API_BASE .. "/" .. spreadsheet_id .. ":batchUpdate"
    local batch_resp, berr = Http.post_json(batch_url, { requests = requests }, {
        Authorization = "Bearer " .. token,
    })
    if not batch_resp or batch_resp.status < 200 or batch_resp.status >= 300 then
        return nil, "batchUpdate failed: " .. tostring(berr or batch_resp and batch_resp.status)
    end
    return true, nil
end

-- Write a 2D array of values to a sheet tab (clears first).
local function sheets_write(token, spreadsheet_id, tab_name, rows)
    -- Clear
    local clear_url = SHEETS_API_BASE .. "/" .. spreadsheet_id .. "/values/" .. tab_name .. "!A:ZZ:clear"
    Http.post_json(clear_url, {}, { Authorization = "Bearer " .. token })

    -- Write
    local update_url = SHEETS_API_BASE .. "/" .. spreadsheet_id ..
        "/values/" .. tab_name .. "!A1?valueInputOption=RAW"
    local resp, err = Http.request("PUT", update_url,
        Json.encode({ values = rows }),
        {
            Authorization  = "Bearer " .. token,
            ["Content-Type"] = "application/json",
        }
    )
    if not resp or resp.status < 200 or resp.status >= 300 then
        return nil, "write failed for " .. tab_name .. ": " .. tostring(err or resp and resp.status)
    end
    return true, nil
end

-- Build the matrix data table (2D array for Sheets)
local function build_matrix_rows()
    local data = filter_by_game(appraisals)
    if #data == 0 then return nil end

    local quality_set = {}
    local all_qualities = {}
    for _, a in ipairs(data) do
        if a.quality and not quality_set[a.quality] then
            quality_set[a.quality] = true
            table.insert(all_qualities, a.quality)
        end
    end
    table.sort(all_qualities, function(a, b) return quality_key(a) < quality_key(b) end)

    local gems = {}
    for _, a in ipairs(data) do
        if not gems[a.gem_name] then gems[a.gem_name] = {} end
        table.insert(gems[a.gem_name], a)
    end

    local gem_avg = {}
    for name, entries in pairs(gems) do
        local sum = 0
        for _, e in ipairs(entries) do sum = sum + e.value end
        gem_avg[name] = sum / #entries
    end

    local sorted_names = {}
    for name in pairs(gems) do table.insert(sorted_names, name) end
    table.sort(sorted_names, function(a, b) return gem_avg[a] > gem_avg[b] end)

    local headers = { "Gem Name", "Rarity", "Avg Value" }
    for _, q in ipairs(all_qualities) do table.insert(headers, q) end

    local rows = { headers }
    for _, name in ipairs(sorted_names) do
        local entries = gems[name]
        local rarity_counts = {}
        for _, a in ipairs(entries) do
            if a.rarity then rarity_counts[a.rarity] = (rarity_counts[a.rarity] or 0) + 1 end
        end
        local best_rarity, best_count = "", 0
        for r, c in pairs(rarity_counts) do
            if c > best_count then best_rarity = r; best_count = c end
        end

        local row = { name, best_rarity, math.floor(gem_avg[name]) }
        for _, q in ipairs(all_qualities) do
            local vals = {}
            for _, a in ipairs(entries) do
                if a.quality == q then table.insert(vals, a.value) end
            end
            if #vals == 0 then
                table.insert(row, "")
            else
                local s = compute_stats(vals)
                table.insert(row, s.min == s.max and s.min or (tostring(s.min) .. "-" .. tostring(s.max)))
            end
        end
        table.insert(rows, row)
    end
    return rows
end

-- Build the raw appraisals data table
local function build_raw_rows()
    local data = filter_by_game(appraisals)
    if #data == 0 then return nil end

    -- Sort by timestamp ascending
    table.sort(data, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)

    local rows = { { "Gem Name", "Rarity", "Quality", "Value", "Character", "Date", "Purified" } }
    for _, a in ipairs(data) do
        table.insert(rows, {
            a.gem_name or "",
            a.rarity or "",
            a.quality or "",
            a.value or 0,
            a.character or "",
            a.timestamp and os.date("%Y-%m-%d %H:%M:%S", a.timestamp) or "",
            a.purified and "Yes" or "No",
        })
    end
    return rows
end

-- Build the summary stats data table
local function build_stats_rows()
    local data = filter_by_game(appraisals)
    if #data == 0 then return nil end

    local gems = {}
    for _, a in ipairs(data) do
        if not gems[a.gem_name] then gems[a.gem_name] = {} end
        table.insert(gems[a.gem_name], a.value)
    end

    local gem_list = {}
    for name, vals in pairs(gems) do
        local s = compute_stats(vals)
        table.insert(gem_list, { name = name, count = s.count, min = s.min, max = s.max, avg = s.avg })
    end
    table.sort(gem_list, function(a, b) return a.avg > b.avg end)

    local rows = { { "Gem Name", "Count", "Min Value", "Max Value", "Avg Value" } }
    for _, g in ipairs(gem_list) do
        table.insert(rows, { g.name, g.count, g.min, g.max, g.avg })
    end
    return rows
end

function GoogleSheets.configured()
    return UserVars.gemtracker_sheets_keyfile ~= nil and UserVars.gemtracker_sheets_id ~= nil
end

function GoogleSheets.show_status()
    respond("")
    respond("=== Google Sheets Status ===")
    respond("")
    respond("Keyfile:        " .. (UserVars.gemtracker_sheets_keyfile or "(not set)"))
    if UserVars.gemtracker_sheets_keyfile then
        respond("  File exists:  " .. (File.exists(UserVars.gemtracker_sheets_keyfile) and "Yes" or "No"))
    end
    respond("Spreadsheet ID: " .. (UserVars.gemtracker_sheets_id or "(not set)"))
    respond("Last Push:      " .. (UserVars.gemtracker_sheets_last_push or "(never)"))
    respond("Configured:     " .. (GoogleSheets.configured() and "Yes" or "No"))
    respond("")
end

function GoogleSheets.set_keyfile(path)
    if not path or path == "" then
        respond("Usage: ;gem sheets keyfile <path_to_json_file>")
        return
    end
    path = path:match('^["\'](.-)["\']$') or path
    if not File.exists(path) then
        respond("File not found: " .. path)
        return
    end
    -- Validate it looks like a service account key
    local ok, key_data = pcall(function() return Json.decode(File.read(path)) end)
    if not ok or type(key_data) ~= "table" or key_data.type ~= "service_account" or not key_data.client_email then
        respond("Error: File does not appear to be a valid service account JSON key.")
        return
    end
    UserVars.gemtracker_sheets_keyfile = path
    respond("Keyfile set: " .. path)
    respond("Service account email: " .. key_data.client_email)
    respond("Share your spreadsheet with this email address (Editor access).")
    if UserVars.gemtracker_sheets_id then
        respond("Spreadsheet already configured. Use ';gem sheets test' to verify the connection.")
    else
        respond("Next: ;gem sheets spreadsheet <spreadsheet_url_or_id>")
    end
end

function GoogleSheets.set_spreadsheet(input)
    if not input or input == "" then
        respond("Usage: ;gem sheets spreadsheet <url_or_id>")
        return
    end
    input = input:match('^["\'](.-)["\']$') or input
    -- Extract ID from URL if needed
    local id = input:match("/spreadsheets/d/([a-zA-Z0-9_%-]+)") or input
    UserVars.gemtracker_sheets_id = id
    respond("Spreadsheet ID set: " .. id)
    if UserVars.gemtracker_sheets_keyfile and File.exists(UserVars.gemtracker_sheets_keyfile) then
        respond("Use ';gem sheets test' to verify the connection.")
    else
        respond("Next: ;gem sheets keyfile <path_to_json_file>")
    end
end

function GoogleSheets.clear_config()
    UserVars.gemtracker_sheets_keyfile  = nil
    UserVars.gemtracker_sheets_id       = nil
    UserVars.gemtracker_sheets_last_push = nil
    respond("Google Sheets configuration cleared.")
end

function GoogleSheets.test_and_report()
    if not GoogleSheets.configured() then
        respond("Google Sheets not fully configured.")
        if not UserVars.gemtracker_sheets_keyfile then respond("  Need: ;gem sheets keyfile <path>") end
        if not UserVars.gemtracker_sheets_id       then respond("  Need: ;gem sheets spreadsheet <id>") end
        return
    end
    respond("Testing connection...")
    local token, terr = google_get_access_token(UserVars.gemtracker_sheets_keyfile)
    if not token then
        respond("Authentication failed: " .. terr)
        return
    end
    -- Try to read the spreadsheet title
    local url = SHEETS_API_BASE .. "/" .. UserVars.gemtracker_sheets_id .. "?fields=properties.title"
    local resp, err = Http.request("GET", url, nil, { Authorization = "Bearer " .. token })
    if not resp or resp.status ~= 200 then
        respond("Connection failed: HTTP " .. tostring(resp and resp.status) .. " " .. tostring(err or ""))
        return
    end
    local info = Json.decode(resp.body)
    local title = info and info.properties and info.properties.title or "(unknown)"
    respond("Connected to: " .. title)
    local _, tab_err = sheets_ensure_tabs(token, UserVars.gemtracker_sheets_id, {"Matrix","Appraisals","Stats"})
    if tab_err then respond("Warning: could not ensure sheet tabs: " .. tab_err) end
    respond("Setup complete! Use ';gem sheets push' to upload data.")
end

function GoogleSheets.push(push_type)
    if not GoogleSheets.configured() then
        respond("Google Sheets not configured. Run ';gem sheets setup' first.")
        return
    end
    push_type = (push_type or "all"):lower()
    local valid = { all=true, matrix=true, raw=true, stats=true }
    if not valid[push_type] then
        respond("Invalid type '" .. push_type .. "'. Valid: all, matrix, raw, stats")
        return
    end

    respond("Authenticating with Google Sheets...")
    local token, terr = google_get_access_token(UserVars.gemtracker_sheets_keyfile)
    if not token then
        respond("Authentication failed: " .. terr)
        return
    end

    local sid = UserVars.gemtracker_sheets_id
    local pushed = {}

    if push_type == "all" or push_type == "matrix" then
        local rows = build_matrix_rows()
        if rows and #rows > 1 then
            sheets_ensure_tabs(token, sid, {"Matrix"})
            local ok, err = sheets_write(token, sid, "Matrix", rows)
            if ok then
                table.insert(pushed, "Matrix (" .. (#rows - 1) .. " gems)")
            else
                respond("Matrix push failed: " .. tostring(err))
            end
        else
            respond("No matrix data to push.")
        end
    end

    if push_type == "all" or push_type == "raw" then
        local rows = build_raw_rows()
        if rows and #rows > 1 then
            sheets_ensure_tabs(token, sid, {"Appraisals"})
            local ok, err = sheets_write(token, sid, "Appraisals", rows)
            if ok then
                table.insert(pushed, "Appraisals (" .. (#rows - 1) .. " records)")
            else
                respond("Appraisals push failed: " .. tostring(err))
            end
        else
            respond("No appraisal data to push.")
        end
    end

    if push_type == "all" or push_type == "stats" then
        local rows = build_stats_rows()
        if rows and #rows > 1 then
            sheets_ensure_tabs(token, sid, {"Stats"})
            local ok, err = sheets_write(token, sid, "Stats", rows)
            if ok then
                table.insert(pushed, "Stats (" .. (#rows - 1) .. " gems)")
            else
                respond("Stats push failed: " .. tostring(err))
            end
        else
            respond("No stats data to push.")
        end
    end

    if #pushed > 0 then
        UserVars.gemtracker_sheets_last_push = os.date("%Y-%m-%d %H:%M:%S")
        respond("")
        respond("Pushed to Google Sheets:")
        for _, p in ipairs(pushed) do respond("  - " .. p) end
        respond("Timestamp: " .. UserVars.gemtracker_sheets_last_push)
    end
end

function GoogleSheets.help()
    respond("")
    respond("Google Sheets Commands:")
    respond("========================")
    respond("")
    respond("Setup Commands:")
    respond("  ;gem sheets keyfile <path>     - Set service account JSON key file")
    respond("  ;gem sheets spreadsheet <id>   - Set spreadsheet (ID or full URL)")
    respond("  ;gem sheets status             - Show current configuration")
    respond("  ;gem sheets test               - Test the connection")
    respond("  ;gem sheets clear              - Clear all configuration")
    respond("")
    respond("Push Commands:")
    respond("  ;gem sheets push               - Push all data (matrix + raw + stats)")
    respond("  ;gem sheets push matrix        - Push matrix view only")
    respond("  ;gem sheets push raw           - Push all appraisals only")
    respond("  ;gem sheets push stats         - Push summary stats only")
    respond("")
    respond("Help Commands:")
    respond("  ;gem sheets setup              - Show detailed setup guide")
    respond("  ;gem sheets help               - Show this help")
    respond("")
end

function GoogleSheets.setup_guide()
    respond("")
    respond("=== GOOGLE SHEETS SETUP GUIDE ===")
    respond("")
    respond("Step 1: Create Google Cloud Project")
    respond("  a. Go to https://console.cloud.google.com/")
    respond("  b. Click 'Select a project' > 'New Project'")
    respond("  c. Enter project name (e.g., 'GemTracker') and click 'Create'")
    respond("")
    respond("Step 2: Enable Google Sheets API")
    respond("  a. Navigate to 'APIs & Services' > 'Library'")
    respond("  b. Search for 'Google Sheets API' and click 'Enable'")
    respond("")
    respond("Step 3: Create Service Account")
    respond("  a. Go to 'APIs & Services' > 'Credentials'")
    respond("  b. Click 'CREATE CREDENTIALS' > 'Service Account'")
    respond("  c. Enter a name, click 'Create and Continue'")
    respond("  d. Skip optional steps, click 'Done'")
    respond("  e. Click on the service account > 'Keys' tab")
    respond("  f. 'Add Key' > 'Create new key' > 'JSON'")
    respond("  g. Save the downloaded JSON file somewhere accessible")
    respond("")
    respond("Step 4: Create & Share Spreadsheet")
    respond("  a. Create a new Google Spreadsheet")
    respond("  b. Share it with the service account email (Editor access)")
    respond("  c. Copy the spreadsheet ID from the URL")
    respond("")
    respond("Step 5: Configure GemTracker")
    respond("  ;gem sheets keyfile C:/path/to/service-account.json")
    respond("  ;gem sheets spreadsheet <id_or_url>")
    respond("")
    respond("Step 6: Test & Push")
    respond("  ;gem sheets test")
    respond("  ;gem sheets push")
    respond("")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("GemTracker v" .. VERSION .. " - Gem Appraisal Value Tracker")
    respond("==============================================")
    respond("")
    respond("Tracking Commands:")
    respond("  ;gemtracker              - Start tracking in background")
    respond("  ;gem stop                - Stop background tracking")
    respond("")
    respond("SHORTHAND: Once tracking is running, use ';gem' instead of ';gemtracker'")
    respond("Example: ;gem stats, ;gem matrix, ;gem purify")
    respond("")
    respond("Statistics Commands:")
    respond("  ;gem stats [gem]         - Show min/max/avg for all gems")
    respond("  ;gem rarity [lvl]        - Stats grouped by rarity")
    respond("  ;gem quality [q]         - Stats grouped by quality")
    respond("  ;gem search <gem>        - Detailed breakdown for a gem")
    respond("  ;gem matrix [gem]        - Quality vs value matrix (alphabetical)")
    respond("  ;gem matrix -v [gem]     - Matrix sorted by avg value (low to high)")
    respond("  ;gem matrix -vd [gem]    - Matrix sorted by avg value (high to low)")
    respond("  ;gem matrix -export      - Export matrix to CSV")
    respond("  ;gem list -v <N>         - List gems with avg value >= N")
    respond("  ;gem list -vd <N>        - List gems with avg value <= N")
    respond("  ;gem char [name]         - Stats by character")
    respond("  ;gem purify [gem]        - Compare raw vs purified gem values")
    respond("")
    respond("Other Commands:")
    respond("  ;gem recent [n]          - Show last n appraisals (default 20)")
    respond("  ;gem export [f]          - Export to CSV file")
    respond("  ;gem clear               - Clear all data (with confirmation)")
    respond("  ;gem help                - Show this help")
    respond("")
    respond("Google Sheets Commands:")
    respond("  ;gem sheets setup        - Show detailed setup guide")
    respond("  ;gem sheets help         - Show all sheets commands")
    respond("  ;gem sheets push         - Push all data to Google Sheets")
    respond("")
end

--------------------------------------------------------------------------------
-- Hooks and main loop
--------------------------------------------------------------------------------

local UPSTREAM_RE = Regex.new("^(?:<c>)?;gem(?:tracker)?\\s*(.*)$", "i")

-- Forward declaration (process_command defined below)
local process_command

local function setup_hooks()
    -- Downstream hook: capture appraisals from game output
    DownstreamHook.add(HOOK_NAME, function(line)
        local stripped = string.gsub(line, "<.->", "")
        local m = APPRAISAL_RE:match(stripped)
        if m then
            local gem = m[1]
            local rarity = m[2]
            local quality = m[3]
            local value_str = m[4]
            local value = tonumber(string.gsub(value_str, ",", ""))
            if value then
                record_appraisal(gem, rarity, quality, value)
            end
        end
        return line
    end)

    -- Upstream hook: intercept ;gem and ;gemtracker commands
    UpstreamHook.add(UPSTREAM_HOOK_NAME, function(client_string)
        local um = UPSTREAM_RE:match(client_string)
        if um then
            local command_str = um[1] or ""
            command_str = command_str:match("^%s*(.-)%s*$") or ""
            process_command(command_str)
            return nil  -- consume the command, don't send to server
        end
        return client_string
    end)
end

local function remove_hooks()
    DownstreamHook.remove(HOOK_NAME)
    UpstreamHook.remove(UPSTREAM_HOOK_NAME)
end

process_command = function(cmd_str)
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

    local ok, err = pcall(function()
        if cmd == "help" or cmd == "-h" or cmd == "--help" then
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
            local sort_mode = "alpha"
            local do_export = false
            local gem_filter_parts = {}
            for i = 2, #parts do
                local p = parts[i]
                if p == "-vd" then
                    sort_mode = "value_desc"
                elseif p == "-v" then
                    sort_mode = "value_asc"
                elseif p == "-export" then
                    do_export = true
                else
                    table.insert(gem_filter_parts, p)
                end
            end
            local gem_filter = #gem_filter_parts > 0 and table.concat(gem_filter_parts, " ") or nil
            matrix_view(gem_filter, sort_mode, do_export)
        elseif cmd == "recent" then
            local n = tonumber(arg) or 20
            recent(n)
        elseif cmd == "export" then
            export_csv(arg ~= "" and arg or nil)
        elseif cmd == "char" or cmd == "character" then
            stats_by_character(arg ~= "" and arg or nil)
        elseif cmd == "purify" or cmd == "purified" then
            purify_stats(arg ~= "" and arg or nil)
        elseif cmd == "clear" then
            clear_data()
        elseif cmd == "list" then
            local mode = "gte"
            local threshold_str = nil
            for i = 2, #parts do
                local p = parts[i]
                if p == "-vd" then
                    mode = "lte"
                elseif p == "-v" then
                    mode = "gte"
                else
                    threshold_str = p
                end
            end
            local threshold = tonumber(threshold_str)
            if not threshold then
                respond("Usage: ;gem list -v <value> or ;gem list -vd <value>")
            else
                list_by_value(threshold, mode)
            end
        elseif cmd == "sheets" or cmd == "google" then
            local subcmd = string.lower(parts[2] or "")
            local subargs = table.concat(rest, " "):match("^%S+%s*(.-)%s*$") or ""
            -- subargs = everything after the subcommand word
            local sub2 = {}
            for i = 3, #parts do table.insert(sub2, parts[i]) end
            local subarg2 = table.concat(sub2, " ")

            if subcmd == "keyfile" or subcmd == "key" then
                GoogleSheets.set_keyfile(subarg2)
            elseif subcmd == "spreadsheet" or subcmd == "sheet" or subcmd == "id" then
                GoogleSheets.set_spreadsheet(subarg2)
            elseif subcmd == "push" then
                local push_type = parts[3] and string.lower(parts[3]) or "all"
                GoogleSheets.push(push_type)
            elseif subcmd == "status" then
                GoogleSheets.show_status()
            elseif subcmd == "test" then
                GoogleSheets.test_and_report()
            elseif subcmd == "clear" then
                GoogleSheets.clear_config()
            elseif subcmd == "setup" or subcmd == "guide" then
                GoogleSheets.setup_guide()
            else
                GoogleSheets.help()
            end
        elseif cmd == "stop" or cmd == "exit" or cmd == "quit" then
            respond("Stopping GemTracker...")
            remove_hooks()
            return
        else
            respond("Unknown command: " .. cmd .. ". Type ;gem help for commands.")
        end
    end)

    if not ok then
        respond("GemTracker error: " .. tostring(err))
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
    echo("Type ;gem help for commands, or ;gemtracker help.")

    -- Keep alive
    while true do
        pause(0.5)
    end
else
    -- One-shot command mode
    local full_cmd = Script.vars[0] or args
    process_command(full_cmd)
end
