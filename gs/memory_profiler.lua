--- @revenant-script
--- name: memory_profiler
--- version: 1.0.0
--- author: elanthia-online
--- contributors: Nisugi
--- game: gs
--- description: Memory/performance profiling for Revenant Lua scripts
--- tags: system,memory,performance
---
--- Usage:
---   ;memory_profiler snapshot     -- Take a memory snapshot
---   ;memory_profiler compare      -- Compare current state to last snapshot
---   ;memory_profiler top          -- Show top memory consumers
---   ;memory_profiler gc           -- Force GC and show stats
---   ;memory_profiler system       -- System memory breakdown
---   ;memory_profiler trend        -- Show trend over snapshots
---   ;memory_profiler trim         -- Force Lua GC cycle
---
--- Ported from Lich5 Ruby memory_profiler.lic v1.0 (2025/11/30)

--------------------------------------------------------------------------------
-- Persistent state (survives across runs via globals)
--------------------------------------------------------------------------------

if not _G._memory_profiler_snapshot then
    _G._memory_profiler_snapshot = nil
end
if not _G._memory_profiler_history then
    _G._memory_profiler_history = {}
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function format_bytes(bytes)
    if bytes == 0 then return "0 B" end

    local negative = bytes < 0
    if negative then bytes = math.abs(bytes) end

    local units = { "B", "KB", "MB", "GB" }
    local exp = math.floor(math.log(bytes) / math.log(1024))
    exp = math.min(exp, #units - 1)

    local value = bytes / (1024 ^ exp)
    local result = string.format("%.2f %s", value, units[exp + 1])

    if negative then
        return "-" .. result
    end
    return result
end

local function get_lua_memory()
    -- Returns Lua memory usage in KB
    return collectgarbage("count")
end

local function get_lua_memory_bytes()
    return math.floor(get_lua_memory() * 1024)
end

local function timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function pad_right(str, width)
    if #str >= width then return str end
    return str .. string.rep(" ", width - #str)
end

local function pad_left(str, width)
    if #str >= width then return str end
    return string.rep(" ", width - #str) .. str
end

local function count_table_entries(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function estimate_table_size(t, seen)
    seen = seen or {}
    if seen[t] then return 0 end
    seen[t] = true

    local size = 40  -- base table overhead
    for k, v in pairs(t) do
        -- Key cost
        if type(k) == "string" then
            size = size + 40 + #k
        else
            size = size + 8
        end
        -- Value cost
        if type(v) == "string" then
            size = size + 40 + #v
        elseif type(v) == "table" then
            size = size + estimate_table_size(v, seen)
        elseif type(v) == "function" then
            size = size + 20
        else
            size = size + 8
        end
    end
    return size
end

--------------------------------------------------------------------------------
-- Module table tracking
--------------------------------------------------------------------------------

local function scan_global_tables()
    local results = {}
    local seen = {}

    for name, val in pairs(_G) do
        if type(val) == "table" and not seen[val] then
            seen[val] = true
            local entries = count_table_entries(val)
            local est_size = estimate_table_size(val, {})
            results[#results + 1] = {
                name = tostring(name),
                entries = entries,
                estimated_bytes = est_size,
                type_name = "table",
            }
        end
    end

    -- Sort by estimated size descending
    table.sort(results, function(a, b) return a.estimated_bytes > b.estimated_bytes end)
    return results
end

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------

local function take_snapshot()
    collectgarbage("collect")
    local mem = get_lua_memory_bytes()
    local tables = scan_global_tables()
    local ts = timestamp()

    local snap = {
        timestamp = ts,
        lua_memory = mem,
        tables = tables,
        table_count = #tables,
    }

    _G._memory_profiler_snapshot = snap

    -- Add to history
    _G._memory_profiler_history[#_G._memory_profiler_history + 1] = {
        timestamp = ts,
        lua_memory = mem,
        table_count = #tables,
    }

    -- Keep history to last 100 entries
    while #_G._memory_profiler_history > 100 do
        table.remove(_G._memory_profiler_history, 1)
    end

    respond("")
    respond("=== Memory Snapshot @ " .. ts .. " ===")
    respond("  Lua memory: " .. format_bytes(mem))
    respond("  Global tables: " .. tostring(#tables))
    respond("  Snapshot saved. Use 'compare' to diff against this.")
    respond("")
end

--------------------------------------------------------------------------------
-- Compare
--------------------------------------------------------------------------------

local function compare_snapshots()
    local prev = _G._memory_profiler_snapshot
    if not prev then
        respond("No previous snapshot. Run ';memory_profiler snapshot' first.")
        return
    end

    collectgarbage("collect")
    local current_mem = get_lua_memory_bytes()
    local current_tables = scan_global_tables()

    respond("")
    respond("=== Memory Comparison ===")
    respond("  Previous: " .. prev.timestamp)
    respond("  Current:  " .. timestamp())
    respond("")

    local mem_delta = current_mem - prev.lua_memory
    local sign = mem_delta >= 0 and "+" or ""
    respond("  Lua memory: " .. format_bytes(prev.lua_memory) .. " -> " .. format_bytes(current_mem)
            .. " (" .. sign .. format_bytes(mem_delta) .. ")")

    local table_delta = #current_tables - prev.table_count
    sign = table_delta >= 0 and "+" or ""
    respond("  Tables: " .. tostring(prev.table_count) .. " -> " .. tostring(#current_tables)
            .. " (" .. sign .. tostring(table_delta) .. ")")
    respond("")

    -- Find new/grown tables
    local prev_by_name = {}
    for _, t in ipairs(prev.tables) do
        prev_by_name[t.name] = t
    end

    local changed = {}
    for _, t in ipairs(current_tables) do
        local old = prev_by_name[t.name]
        if old then
            local delta = t.estimated_bytes - old.estimated_bytes
            if math.abs(delta) > 100 then
                changed[#changed + 1] = {
                    name = t.name,
                    old_size = old.estimated_bytes,
                    new_size = t.estimated_bytes,
                    delta = delta,
                }
            end
        else
            if t.estimated_bytes > 100 then
                changed[#changed + 1] = {
                    name = t.name,
                    old_size = 0,
                    new_size = t.estimated_bytes,
                    delta = t.estimated_bytes,
                }
            end
        end
    end

    table.sort(changed, function(a, b) return math.abs(a.delta) > math.abs(b.delta) end)

    if #changed > 0 then
        respond("  Significant changes (top 20):")
        respond("  " .. pad_right("Name", 30) .. pad_left("Before", 12)
                .. pad_left("After", 12) .. pad_left("Delta", 12))
        respond("  " .. string.rep("-", 66))
        for i = 1, math.min(20, #changed) do
            local c = changed[i]
            local ds = c.delta >= 0 and ("+" .. format_bytes(c.delta)) or ("-" .. format_bytes(math.abs(c.delta)))
            respond("  " .. pad_right(c.name, 30)
                    .. pad_left(format_bytes(c.old_size), 12)
                    .. pad_left(format_bytes(c.new_size), 12)
                    .. pad_left(ds, 12))
        end
    else
        respond("  No significant table size changes detected.")
    end
    respond("")
end

--------------------------------------------------------------------------------
-- Top
--------------------------------------------------------------------------------

local function show_top()
    collectgarbage("collect")
    local tables = scan_global_tables()

    respond("")
    respond("=== Top Memory Consumers ===")
    respond("  Lua total: " .. format_bytes(get_lua_memory_bytes()))
    respond("")
    respond("  " .. pad_right("Name", 30) .. pad_left("Entries", 10) .. pad_left("Est. Size", 12))
    respond("  " .. string.rep("-", 52))

    for i = 1, math.min(30, #tables) do
        local t = tables[i]
        respond("  " .. pad_right(t.name, 30)
                .. pad_left(tostring(t.entries), 10)
                .. pad_left(format_bytes(t.estimated_bytes), 12))
    end
    respond("")
end

--------------------------------------------------------------------------------
-- GC
--------------------------------------------------------------------------------

local function force_gc()
    local before = get_lua_memory_bytes()
    respond("")
    respond("=== Forcing Garbage Collection ===")
    respond("  Before: " .. format_bytes(before))

    collectgarbage("collect")
    collectgarbage("collect")  -- second pass catches weak refs

    local after = get_lua_memory_bytes()
    local freed = before - after
    respond("  After:  " .. format_bytes(after))
    respond("  Freed:  " .. format_bytes(freed))
    respond("")
end

--------------------------------------------------------------------------------
-- System
--------------------------------------------------------------------------------

local function show_system()
    collectgarbage("collect")

    respond("")
    respond("=== System Memory Breakdown ===")
    respond("  Lua memory: " .. format_bytes(get_lua_memory_bytes()))
    respond("")

    -- Count types in _G
    local type_counts = {}
    local function count_recursive(t, depth, seen)
        if depth > 3 then return end
        seen = seen or {}
        if seen[t] then return end
        seen[t] = true

        for _, v in pairs(t) do
            local vt = type(v)
            type_counts[vt] = (type_counts[vt] or 0) + 1
            if vt == "table" then
                count_recursive(v, depth + 1, seen)
            end
        end
    end

    count_recursive(_G, 0, {})

    respond("  Object counts (global scope, depth 3):")
    local sorted_types = {}
    for k, v in pairs(type_counts) do
        sorted_types[#sorted_types + 1] = { name = k, count = v }
    end
    table.sort(sorted_types, function(a, b) return a.count > b.count end)

    for _, entry in ipairs(sorted_types) do
        respond("    " .. pad_right(entry.name, 15) .. tostring(entry.count))
    end

    -- GC stats
    respond("")
    respond("  GC step multiplier: " .. tostring(collectgarbage("count")))
    respond("")
end

--------------------------------------------------------------------------------
-- Trend
--------------------------------------------------------------------------------

local function show_trend()
    local history = _G._memory_profiler_history
    if not history or #history == 0 then
        respond("No history yet. Take some snapshots first.")
        return
    end

    respond("")
    respond("=== Memory Trend (" .. tostring(#history) .. " snapshots) ===")
    respond("")
    respond("  " .. pad_right("Timestamp", 22) .. pad_left("Lua Mem", 12) .. pad_left("Tables", 8) .. pad_left("Delta", 12))
    respond("  " .. string.rep("-", 54))

    local prev_mem = nil
    for _, h in ipairs(history) do
        local delta_str = ""
        if prev_mem then
            local d = h.lua_memory - prev_mem
            local sign = d >= 0 and "+" or ""
            delta_str = sign .. format_bytes(d)
        end
        respond("  " .. pad_right(h.timestamp, 22)
                .. pad_left(format_bytes(h.lua_memory), 12)
                .. pad_left(tostring(h.table_count), 8)
                .. pad_left(delta_str, 12))
        prev_mem = h.lua_memory
    end

    -- Overall trend
    if #history >= 2 then
        local first = history[1]
        local last = history[#history]
        local total_delta = last.lua_memory - first.lua_memory
        local sign = total_delta >= 0 and "+" or ""
        respond("")
        respond("  Overall: " .. sign .. format_bytes(total_delta)
                .. " over " .. tostring(#history) .. " snapshots")

        if total_delta > 0 and #history > 2 then
            local avg_growth = total_delta / (#history - 1)
            respond("  Avg growth per snapshot: " .. format_bytes(math.floor(avg_growth)))
        end
    end
    respond("")
end

--------------------------------------------------------------------------------
-- Trim (force Lua GC)
--------------------------------------------------------------------------------

local function trim_memory()
    respond("")
    respond("=== Trim: Forcing Lua GC ===")
    local before = get_lua_memory_bytes()
    respond("  Before: " .. format_bytes(before))

    -- Aggressive GC
    for _ = 1, 3 do
        collectgarbage("collect")
    end

    local after = get_lua_memory_bytes()
    respond("  After:  " .. format_bytes(after))
    respond("  Freed:  " .. format_bytes(before - after))
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local cmd = (Script.vars[1] or ""):lower()

if cmd == "" or cmd == "help" then
    respond("")
    respond("=== Memory Profiler ===")
    respond("  ;memory_profiler snapshot   - Take a snapshot")
    respond("  ;memory_profiler compare    - Compare to last snapshot")
    respond("  ;memory_profiler top        - Show top memory consumers")
    respond("  ;memory_profiler gc         - Force GC and show stats")
    respond("  ;memory_profiler system     - System memory breakdown")
    respond("  ;memory_profiler trend      - Show trend over snapshots")
    respond("  ;memory_profiler trim       - Force GC cycle")
    respond("")
elseif cmd == "snapshot" then
    take_snapshot()
elseif cmd == "compare" then
    compare_snapshots()
elseif cmd == "top" then
    show_top()
elseif cmd == "gc" then
    force_gc()
elseif cmd == "system" then
    show_system()
elseif cmd == "trend" then
    show_trend()
elseif cmd == "trim" then
    trim_memory()
else
    respond("Unknown command: " .. cmd .. " -- try ;memory_profiler help")
end
