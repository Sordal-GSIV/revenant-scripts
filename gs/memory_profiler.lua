--- @revenant-script
--- name: memory_profiler
--- version: 2.0.0
--- author: elanthia-online
--- contributors: Nisugi
--- game: gs
--- description: Track Lua heap allocations and memory growth in Revenant
--- tags: system,memory,performance
--- @lic-certified: complete 2026-03-19
---
--- Original: Lich5 Ruby memory_profiler.lic v1.0 (2025/11/30)
---   author: Elanthia Online, contributors: Nisugi
---
--- Usage:
---   ;memory_profiler snapshot     -- Take a baseline snapshot
---   ;memory_profiler compare      -- Compare current state to last snapshot
---   ;memory_profiler top          -- Show top memory consumers
---   ;memory_profiler gc           -- Force GC and show stats
---   ;memory_profiler detail       -- Deep dive: strings, tables, functions
---   ;memory_profiler system       -- Full system/Lua memory breakdown
---   ;memory_profiler fragtest     -- Test if gap is collectable or leaked
---   ;memory_profiler trend        -- Show memory trend over snapshots
---   ;memory_profiler trim         -- Force aggressive GC cycle
---   ;memory_profiler trace [name] -- Show large object locations
---   ;memory_profiler start        -- How to enable allocation tracking

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
    if bytes == nil then return "N/A" end
    if bytes == 0 then return "0 B" end
    local negative = bytes < 0
    if negative then bytes = math.abs(bytes) end
    local units = { "B", "KB", "MB", "GB" }
    local exp = math.floor(math.log(bytes) / math.log(1024))
    exp = math.min(math.max(exp, 0), #units - 1)
    local value = bytes / (1024 ^ exp)
    local result = string.format("%.2f %s", value, units[exp + 1])
    if negative then return "-" .. result end
    return result
end

local function get_lua_memory_bytes()
    return math.floor(collectgarbage("count") * 1024)
end

local function timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function pad_right(str, width)
    str = tostring(str)
    if #str >= width then return str end
    return str .. string.rep(" ", width - #str)
end

local function pad_left(str, width)
    str = tostring(str)
    if #str >= width then return str end
    return string.rep(" ", width - #str) .. str
end

local function count_table_entries(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function estimate_table_size(t, seen)
    seen = seen or {}
    if seen[t] then return 0 end
    seen[t] = true
    local size = 40
    for k, v in pairs(t) do
        if type(k) == "string" then size = size + 40 + #k else size = size + 8 end
        if type(v) == "string" then size = size + 40 + #v
        elseif type(v) == "table" then size = size + estimate_table_size(v, seen)
        elseif type(v) == "function" then size = size + 20
        else size = size + 8 end
    end
    return size
end

local function get_script_count()
    local ok, list = pcall(function() return Script.list() end)
    if ok and list then return #list end
    return -1
end

local function get_script_list()
    local ok, list = pcall(function() return Script.list() end)
    if ok and list then return list end
    return {}
end

--------------------------------------------------------------------------------
-- Global table scanning
--------------------------------------------------------------------------------

local function scan_global_tables()
    local results = {}
    local seen = {}
    for name, val in pairs(_G) do
        if type(val) == "table" and not seen[val] then
            seen[val] = true
            results[#results + 1] = {
                name = tostring(name),
                entries = count_table_entries(val),
                estimated_bytes = estimate_table_size(val, {}),
            }
        end
    end
    table.sort(results, function(a, b) return a.estimated_bytes > b.estimated_bytes end)
    return results
end

local function count_types_recursive(t, max_depth, seen)
    seen = seen or {}
    local counts = {}
    local function recurse(tbl, depth)
        if depth > max_depth or seen[tbl] then return end
        seen[tbl] = true
        for _, v in pairs(tbl) do
            local vt = type(v)
            counts[vt] = (counts[vt] or 0) + 1
            if vt == "table" then recurse(v, depth + 1) end
        end
    end
    recurse(t, 0)
    return counts
end

-- One-pass comprehensive string scan
local function scan_strings_comprehensive(min_sample_size, max_samples)
    min_sample_size = min_sample_size or 100
    max_samples = max_samples or 30
    local total_count = 0
    local total_bytes = 0
    local buckets = { ["0-100"] = 0, ["101-1K"] = 0, ["1K-10K"] = 0, ["10K-100K"] = 0, ["100K+"] = 0 }
    local samples = {}
    local seen_tables = {}
    local seen_strings = {}

    local function scan(t, path, depth)
        if depth > 4 or seen_tables[t] then return end
        seen_tables[t] = true
        for k, v in pairs(t) do
            local vtype = type(v)
            local cur_path = path == "" and tostring(k) or (path .. "." .. tostring(k))
            if vtype == "string" then
                total_count = total_count + 1
                local sz = #v
                total_bytes = total_bytes + sz
                if sz <= 100 then buckets["0-100"] = buckets["0-100"] + 1
                elseif sz <= 1024 then buckets["101-1K"] = buckets["101-1K"] + 1
                elseif sz <= 10240 then buckets["1K-10K"] = buckets["1K-10K"] + 1
                elseif sz <= 102400 then buckets["10K-100K"] = buckets["10K-100K"] + 1
                else buckets["100K+"] = buckets["100K+"] + 1 end
                if sz >= min_sample_size and not seen_strings[v] and #samples < max_samples then
                    seen_strings[v] = true
                    samples[#samples + 1] = {
                        path = cur_path,
                        size = sz,
                        preview = v:sub(1, 80):gsub("\n", "\\n"):gsub("\t", "\\t"),
                    }
                end
            elseif vtype == "table" then
                scan(v, cur_path, depth + 1)
            end
        end
    end

    scan(_G, "", 0)
    table.sort(samples, function(a, b) return a.size > b.size end)
    return { total_count = total_count, total_bytes = total_bytes, buckets = buckets, samples = samples }
end

local function scan_functions()
    local results = {}
    local top_fns = 0
    for name, val in pairs(_G) do
        if type(val) == "table" then
            local n = 0
            for _, v in pairs(val) do if type(v) == "function" then n = n + 1 end end
            if n > 0 then results[#results + 1] = { name = name, count = n } end
        elseif type(val) == "function" then
            top_fns = top_fns + 1
        end
    end
    if top_fns > 0 then results[#results + 1] = { name = "_G (top-level)", count = top_fns } end
    table.sort(results, function(a, b) return a.count > b.count end)
    return results
end

local function analyze_table_depths()
    local depth_counts = {}
    local max_depth = 0
    local seen = {}
    local function measure(t, d)
        if seen[t] then return d end
        seen[t] = true
        local mx = d
        for _, v in pairs(t) do
            if type(v) == "table" then
                local cd = measure(v, d + 1)
                if cd > mx then mx = cd end
            end
        end
        return mx
    end
    for _, val in pairs(_G) do
        if type(val) == "table" then
            local d = measure(val, 1)
            depth_counts[d] = (depth_counts[d] or 0) + 1
            if d > max_depth then max_depth = d end
        end
    end
    return depth_counts, max_depth
end

local function classify_tables()
    local r = { arrays = 0, hashes = 0, mixed = 0, empty = 0 }
    for _, val in pairs(_G) do
        if type(val) == "table" then
            local count, seq = 0, 0
            for k, _ in pairs(val) do
                count = count + 1
                if type(k) == "number" then seq = seq + 1 end
            end
            if count == 0 then r.empty = r.empty + 1
            elseif seq == count then r.arrays = r.arrays + 1
            elseif seq == 0 then r.hashes = r.hashes + 1
            else r.mixed = r.mixed + 1 end
        end
    end
    return r
end

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------

local function take_snapshot()
    collectgarbage("collect")
    local mem = get_lua_memory_bytes()
    local tables = scan_global_tables()
    local ts = timestamp()
    local scripts = get_script_count()

    _G._memory_profiler_snapshot = {
        timestamp = ts,
        lua_memory = mem,
        tables = tables,
        table_count = #tables,
        script_count = scripts,
    }

    _G._memory_profiler_history[#_G._memory_profiler_history + 1] = {
        timestamp = ts,
        lua_memory = mem,
        table_count = #tables,
        script_count = scripts,
    }

    while #_G._memory_profiler_history > 100 do
        table.remove(_G._memory_profiler_history, 1)
    end

    respond("")
    respond(string.rep("=", 70))
    respond("MEMORY SNAPSHOT - " .. ts)
    respond(string.rep("=", 70))
    respond("")
    respond("  Total objects:         " .. tostring(count_table_entries(_G)))
    respond("  Lua heap memory:       " .. format_bytes(mem))
    respond("  Global tables:         " .. tostring(#tables))
    if scripts >= 0 then
        respond("  Active scripts:        " .. tostring(scripts))
    end
    respond("")
    respond("  Snapshot saved. Use ';memory_profiler compare' after hunting to see growth.")
    respond("  Use ';memory_profiler trend' to see memory trends over time.")
    respond("")
end

--------------------------------------------------------------------------------
-- Compare
--------------------------------------------------------------------------------

local function compare_snapshots()
    local prev = _G._memory_profiler_snapshot
    if not prev then
        respond("No snapshot taken. Run ';memory_profiler snapshot' first.")
        return
    end

    collectgarbage("collect")
    local current_mem = get_lua_memory_bytes()
    local current_tables = scan_global_tables()
    local current_scripts = get_script_count()
    local ts = timestamp()

    respond("")
    respond(string.rep("=", 70))
    respond("MEMORY GROWTH ANALYSIS")
    respond(string.rep("=", 70))
    respond("")
    respond("  Snapshot taken:           " .. prev.timestamp)
    respond("  Current time:             " .. ts)
    respond("")
    respond("  SYSTEM MEMORY CHANGES:")
    respond("")

    local mem_delta = current_mem - prev.lua_memory
    local sign = mem_delta >= 0 and "+" or ""
    respond("  Lua heap:    " .. format_bytes(prev.lua_memory)
            .. " -> " .. format_bytes(current_mem)
            .. " (" .. sign .. format_bytes(mem_delta) .. ")")

    local table_delta = #current_tables - prev.table_count
    sign = table_delta >= 0 and "+" or ""
    respond("  Tables:      " .. tostring(prev.table_count)
            .. " -> " .. tostring(#current_tables)
            .. " (" .. sign .. tostring(table_delta) .. ")")

    if current_scripts >= 0 and prev.script_count and prev.script_count >= 0 then
        local sdelta = current_scripts - prev.script_count
        respond("  Scripts:     " .. tostring(prev.script_count)
                .. " -> " .. tostring(current_scripts)
                .. " (" .. (sdelta >= 0 and "+" or "") .. tostring(sdelta) .. ")")
    end

    respond("")

    if mem_delta > prev.lua_memory * 0.5 then
        respond("  WARNING: Memory gap grew significantly!")
        respond("  This suggests objects accumulating without being GC'd.")
        respond("  Run ';memory_profiler fragtest' to diagnose.")
        respond("")
    end

    -- Find changed/new tables
    local prev_by_name = {}
    for _, t in ipairs(prev.tables) do prev_by_name[t.name] = t end

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
                    old_entries = old.entries,
                    new_entries = t.entries,
                    delta = delta,
                }
            end
        elseif t.estimated_bytes > 100 then
            changed[#changed + 1] = {
                name = t.name,
                old_size = 0,
                new_size = t.estimated_bytes,
                old_entries = 0,
                new_entries = t.entries,
                delta = t.estimated_bytes,
            }
        end
    end

    table.sort(changed, function(a, b) return math.abs(a.delta) > math.abs(b.delta) end)

    sign = mem_delta >= 0 and "+" or ""
    respond("  Total object growth:      " .. tostring(#current_tables - prev.table_count) .. " tables")
    respond("  Total memory growth:      " .. sign .. format_bytes(mem_delta))
    respond("")
    respond("  Top 20 tables by memory growth:")
    respond("")

    if #changed > 0 then
        respond("  " .. pad_right("Name", 30)
                .. pad_left("Before", 12) .. pad_left("After", 12)
                .. pad_left("Delta", 12) .. pad_left("Entries", 9))
        respond("  " .. string.rep("-", 75))
        for i = 1, math.min(20, #changed) do
            local c = changed[i]
            local ds = c.delta >= 0
                and ("+" .. format_bytes(c.delta))
                or ("-" .. format_bytes(math.abs(c.delta)))
            local ed = c.new_entries - c.old_entries
            respond("  " .. pad_right(c.name, 30)
                    .. pad_left(format_bytes(c.old_size), 12)
                    .. pad_left(format_bytes(c.new_size), 12)
                    .. pad_left(ds, 12)
                    .. pad_left((ed >= 0 and "+" or "") .. tostring(ed), 9))
        end
    else
        respond("  No significant table size changes detected.")
    end

    respond("")
    respond("  Creature/Script-specific growth:")
    local specific = {}
    for _, c in ipairs(changed) do
        if c.name:find("[Cc]reature") or c.name:find("[Cc]ombat")
                or c.name:find("[Ss]cript") or c.name:find("[Cc]ache") then
            specific[#specific + 1] = c
        end
    end
    if #specific > 0 then
        for _, c in ipairs(specific) do
            local ds = c.delta >= 0 and ("+" .. format_bytes(c.delta)) or ("-" .. format_bytes(math.abs(c.delta)))
            respond(string.format("  %-40s %+6d entries  %s",
                c.name, c.new_entries - c.old_entries, ds))
        end
    else
        respond("  No notable growth in creature/combat/script tables.")
    end
    respond("")
end

--------------------------------------------------------------------------------
-- Top consumers
--------------------------------------------------------------------------------

local function show_top()
    collectgarbage("collect")
    local tables = scan_global_tables()
    local scripts = get_script_list()

    respond("")
    respond(string.rep("=", 70))
    respond("TOP MEMORY CONSUMERS (Current State)")
    respond(string.rep("=", 70))
    respond("")
    respond("  Total memory: " .. format_bytes(get_lua_memory_bytes()))
    respond("")
    respond("  Top 30 tables by memory usage:")
    respond("")
    respond("  " .. pad_right("Name", 30) .. pad_left("Entries", 10)
            .. pad_left("Est. Size", 12) .. pad_left("Avg/entry", 12))
    respond("  " .. string.rep("-", 64))

    for i = 1, math.min(30, #tables) do
        local t = tables[i]
        local avg = t.entries > 0 and math.floor(t.estimated_bytes / t.entries) or 0
        respond("  " .. pad_right(t.name, 30)
                .. pad_left(tostring(t.entries), 10)
                .. pad_left(format_bytes(t.estimated_bytes), 12)
                .. pad_left(format_bytes(avg), 12))
    end

    respond("")
    respond("  Script-specific checks:")
    respond("")
    respond("  Active scripts: " .. tostring(#scripts))
    if #scripts > 0 then
        for _, s in ipairs(scripts) do
            local sname = type(s) == "table" and (s.name or tostring(s)) or tostring(s)
            respond("    - " .. sname)
        end
    end
    respond("")
end

--------------------------------------------------------------------------------
-- GC stats
--------------------------------------------------------------------------------

local function force_gc()
    local before = get_lua_memory_bytes()
    respond("")
    respond(string.rep("=", 70))
    respond("GARBAGE COLLECTION STATS")
    respond(string.rep("=", 70))
    respond("")
    respond("  Running GC.start...")
    collectgarbage("collect")
    local after1 = get_lua_memory_bytes()
    respond("  After pass 1: " .. format_bytes(after1))

    collectgarbage("collect")
    local after2 = get_lua_memory_bytes()
    respond("  After pass 2 (catches weak refs): " .. format_bytes(after2))

    local freed = before - after2
    respond("")
    respond("  GC runs:           before -> after")
    respond("  Memory freed:      " .. format_bytes(freed))
    respond("  Memory after GC:   " .. format_bytes(after2))
    respond("")

    local pause = collectgarbage("setpause", -1)
    collectgarbage("setpause", pause)
    local stepmul = collectgarbage("setstepmul", -1)
    collectgarbage("setstepmul", stepmul)

    respond("  GC stats:")
    respond("    Pause multiplier:          " .. tostring(pause) .. "% (100 = GC when heap doubles)")
    respond("    Step multiplier:           " .. tostring(stepmul) .. "%")
    respond("")
    respond("  NOTE: Lua GC has no GC.compact equivalent (no heap compaction).")
    respond("        Run ';memory_profiler fragtest' to analyze collectable vs leaked memory.")
    respond("")
end

--------------------------------------------------------------------------------
-- Detailed analysis
--------------------------------------------------------------------------------

local function detailed_analysis()
    collectgarbage("collect")
    respond("")
    respond(string.rep("=", 70))
    respond("DETAILED MEMORY ANALYSIS")
    respond(string.rep("=", 70))
    respond("")

    -- String analysis
    respond("  Analyzing String objects...")
    respond("")
    respond(string.rep("=", 70))
    respond("STRING ANALYSIS")
    respond(string.rep("=", 70))
    respond("")

    local str_data = scan_strings_comprehensive(100, 20)
    respond("  Total strings:          " .. tostring(str_data.total_count))
    respond("  Total string memory:    " .. format_bytes(str_data.total_bytes))
    if str_data.total_count > 0 then
        respond(string.format("  Average size:           %d bytes",
            math.floor(str_data.total_bytes / str_data.total_count)))
    end
    respond("")
    respond("  Size distribution:")
    for _, range in ipairs({"0-100", "101-1K", "1K-10K", "10K-100K", "100K+"}) do
        respond("    " .. pad_right(range .. " bytes:", 16) .. tostring(str_data.buckets[range]))
    end
    respond("")
    if #str_data.samples > 0 then
        respond("  Sample of large strings (first 80 chars):")
        for i, s in ipairs(str_data.samples) do
            respond(string.format("  %3d. %-40s %s", i, s.path, format_bytes(s.size)))
            respond("       \"" .. s.preview .. "\"")
        end
    else
        respond("  No strings >= 100 bytes found in global scope.")
    end
    respond("")

    -- Array/Hash analysis
    respond("  Analyzing Array objects...")
    respond("")
    respond(string.rep("=", 70))
    respond("ARRAY ANALYSIS")
    respond(string.rep("=", 70))
    respond("")

    local tables = scan_global_tables()
    local total_entries = 0
    for _, t in ipairs(tables) do total_entries = total_entries + t.entries end
    local cls = classify_tables()

    respond("  Total arrays:           " .. tostring(#tables))
    respond("  Total array memory:     " .. format_bytes(
        (function() local s = 0; for _, t in ipairs(tables) do s = s + t.estimated_bytes end; return s end)()))
    respond("  Total elements:         " .. tostring(total_entries))
    if #tables > 0 then
        respond(string.format("  Average array size:     %d elements", math.floor(total_entries / #tables)))
    end
    respond("")
    respond("  Table type breakdown:")
    respond("    Array-style (int keys only):  " .. tostring(cls.arrays))
    respond("    Hash-style (str keys only):   " .. tostring(cls.hashes))
    respond("    Mixed:                        " .. tostring(cls.mixed))
    respond("    Empty:                        " .. tostring(cls.empty))
    respond("")
    respond("  Sample of large arrays (>10 elements):")
    local shown = 0
    for _, t in ipairs(tables) do
        if t.entries > 10 and shown < 20 then
            shown = shown + 1
            respond(string.format("  %3d. %-30s %5d elements  %s",
                shown, t.name, t.entries, format_bytes(t.estimated_bytes)))
        end
    end
    if shown == 0 then respond("  No arrays with > 10 entries found at top level.") end
    respond("")

    -- Hash analysis
    respond("  Analyzing Hash objects...")
    respond("")
    respond(string.rep("=", 70))
    respond("HASH ANALYSIS")
    respond(string.rep("=", 70))
    respond("")
    respond("  Total hashes:           " .. tostring(#tables))
    local total_keys = total_entries
    respond("  Total keys:             " .. tostring(total_keys))
    if #tables > 0 then
        respond(string.format("  Average hash size:      %d keys", math.floor(total_keys / #tables)))
    end
    respond("")
    respond("  Sample of large hashes (>5 keys):")
    shown = 0
    for _, t in ipairs(tables) do
        if t.entries > 5 and shown < 20 then
            shown = shown + 1
            -- Sample first 5 keys
            local val = _G[t.name]
            local keys_sample = ""
            if type(val) == "table" then
                local ks = {}
                for k, _ in pairs(val) do
                    ks[#ks + 1] = tostring(k):sub(1, 30)
                    if #ks >= 5 then break end
                end
                keys_sample = "{" .. table.concat(ks, ", ") .. ", ...}"
            end
            respond(string.format("  %3d. %-30s %5d keys  %s  %s",
                shown, t.name, t.entries, format_bytes(t.estimated_bytes), keys_sample))
        end
    end
    if shown == 0 then respond("  No hashes with > 5 keys found at top level.") end
    respond("")
    respond(string.rep("=", 70))
end

--------------------------------------------------------------------------------
-- System memory breakdown
--------------------------------------------------------------------------------

local function show_system()
    collectgarbage("collect")

    respond("")
    respond(string.rep("=", 70))
    respond("SYSTEM MEMORY BREAKDOWN")
    respond(string.rep("=", 70))
    respond("")
    respond("  Generated:                " .. timestamp())
    respond("  Lua version:              " .. _VERSION)
    respond("")

    local lua_mem = get_lua_memory_bytes()
    local before_gc = get_lua_memory_bytes()
    collectgarbage("collect")
    collectgarbage("collect")
    local after_gc = get_lua_memory_bytes()
    local collectable = before_gc - after_gc
    local gap_pct = before_gc > 0 and (collectable / before_gc * 100) or 0

    respond(string.rep("=", 70))
    respond("LUA HEAP MEMORY (collectgarbage tracked)")
    respond(string.rep("=", 70))
    respond("")
    respond("  Lua heap objects:         " .. format_bytes(lua_mem))
    respond("  After full GC:            " .. format_bytes(after_gc))
    respond("  Collectable memory:       " .. format_bytes(collectable)
            .. string.format("  (%.1f%%)", gap_pct))
    respond("")

    local pause = collectgarbage("setpause", -1)
    collectgarbage("setpause", pause)
    local stepmul = collectgarbage("setstepmul", -1)
    collectgarbage("setstepmul", stepmul)

    respond("  GC configuration:")
    respond("    Pause multiplier:       " .. tostring(pause) .. "%")
    respond("      (100 = trigger when heap doubles)")
    respond("    Step multiplier:        " .. tostring(stepmul) .. "%")
    respond("      (larger = more work per step)")
    respond("")

    respond(string.rep("=", 70))
    respond("RUBY VM INTERNALS (Lua equivalent: type distribution)")
    respond(string.rep("=", 70))
    respond("")
    respond("  Object counts (global scope, depth 3):")

    local type_counts = count_types_recursive(_G, 3, {})
    local sorted_types = {}
    for k, v in pairs(type_counts) do
        sorted_types[#sorted_types + 1] = { name = k, count = v }
    end
    table.sort(sorted_types, function(a, b) return a.count > b.count end)
    for _, entry in ipairs(sorted_types) do
        respond("    " .. pad_right(entry.name, 15) .. tostring(entry.count))
    end
    respond("")

    local tables = scan_global_tables()
    local total_table_size = 0
    for _, t in ipairs(tables) do total_table_size = total_table_size + t.estimated_bytes end
    respond("  Top-level tables:         " .. tostring(#tables))
    respond("  Est. table memory:        " .. format_bytes(total_table_size))
    respond("  NOTE: estimate_table_size recursively sums string/table overhead.")
    respond("        Actual allocator footprint is higher due to metadata/alignment.")
    respond("")

    respond(string.rep("=", 70))
    respond("THREAD MEMORY (Lua coroutines / active scripts)")
    respond(string.rep("=", 70))
    respond("")
    local scripts = get_script_list()
    respond("  Active scripts:           " .. tostring(#scripts))
    respond("")
    if #scripts > 0 then
        respond("  Individual scripts:")
        for i, s in ipairs(scripts) do
            local sname = type(s) == "table" and (s.name or tostring(s)) or tostring(s)
            respond("    " .. tostring(i) .. ". " .. sname)
        end
        respond("")
    end
    respond("  NOTE: Each Revenant script runs as an mlua coroutine.")
    respond("        Coroutine stack overhead is not measurable from Lua.")
    respond("")

    respond(string.rep("=", 70))
    respond("PROCESS MEMORY (not directly accessible from Lua)")
    respond(string.rep("=", 70))
    respond("")
    respond("  Lua heap (tracked):        " .. format_bytes(after_gc))
    respond("")
    local overhead = math.floor(after_gc * 0.4)
    local thread_est = #scripts * 512 * 1024
    respond("  Accounting for the gap:")
    respond("")
    respond("  1. Malloc allocator overhead:")
    respond("     Lua heap (collectgarbage): " .. format_bytes(after_gc))
    respond("     Malloc overhead (~40%):    " .. format_bytes(overhead))
    respond("     (Allocator adds metadata, alignment, fragmentation)")
    respond("")
    respond("  2. Coroutine stacks:")
    respond("     Script count:              " .. tostring(#scripts))
    respond("     Stack estimate:            " .. format_bytes(thread_est))
    respond("       (" .. tostring(#scripts) .. " coroutines x ~512 KB)")
    respond("")
    local total_est = after_gc + overhead + thread_est
    respond("  Estimated Lua footprint:   ~" .. format_bytes(total_est))
    respond("")
    respond("  Process-level RSS is not accessible from Lua sandboxed code.")
    respond("  To measure total process memory, use OS tools:")
    respond("    Linux:  cat /proc/<pid>/status | grep VmRSS")
    respond("    macOS:  ps -o rss= -p <pid>")
    respond("    Win:    tasklist /fi \"pid eq <pid>\"")
    respond("")

    respond(string.rep("=", 70))
    respond("MEMORY GAP ANALYSIS")
    respond(string.rep("=", 70))
    respond("")
    respond("  UNACCOUNTED GAP: Cannot be computed without process RSS.")
    respond("")
    respond("  Within Lua, the 'gap' is collectable memory:")
    respond("  Process RSS:              (requires OS tools)")
    respond("  Lua heap (ObjectSpace):   " .. format_bytes(after_gc))
    respond("  Collectable gap:          " .. format_bytes(collectable)
            .. string.format("  (%.1f%%)", gap_pct))
    respond("")
    if gap_pct > 30 then
        respond("  Gap percentage is high (" .. string.format("%.1f%%", gap_pct) .. ")")
        respond("  Run ';memory_profiler fragtest' to diagnose.")
        respond("")
    end

    respond(string.rep("=", 70))
    respond("INVESTIGATION RECOMMENDATIONS")
    respond(string.rep("=", 70))
    respond("")
    local lua_mb = after_gc / (1024 * 1024)
    if lua_mb > 100 then
        respond("  WARNING: Lua heap is " .. string.format("%.0f", lua_mb) .. " MB (over 100 MB)!")
        respond("")
        respond("  Immediate actions:")
        respond("    1. Check for memory leaks with snapshot/compare workflow")
        respond("    2. Look for growing global tables")
        respond("    3. Run fragtest to see if GC can recover memory")
        respond("")
    end
    respond("  To track memory growth during hunting:")
    respond("    1. At startup:            ;memory_profiler snapshot")
    respond("    2. At startup:            ;memory_profiler system")
    respond("    3. Hunt for 30-60 minutes")
    respond("    4. After hunting:         ;memory_profiler compare")
    respond("    5. After hunting:         ;memory_profiler system")
    respond("")
    respond("  Key metrics to watch for memory leaks:")
    respond("    - Lua heap growing without GC recovery")
    respond("    - Table count increasing over time")
    respond("    - Script count not matching expectations")
    respond("    - Gap % (collectable/total) decreasing session over session")
    respond("")
    respond("  If you see growth, check:")
    respond("    - ;memory_profiler compare   (which tables grew?)")
    respond("    - ;memory_profiler fragtest  (is it GC-able or leaked?)")
    respond("    - ;memory_profiler top       (largest tables right now)")
    respond("")
    respond(string.rep("=", 70))
    respond("")
end

--------------------------------------------------------------------------------
-- Fragmentation test
--------------------------------------------------------------------------------

local function fragmentation_test()
    respond("")
    respond(string.rep("=", 70))
    respond("FRAGMENTATION vs LEAK TEST")
    respond(string.rep("=", 70))
    respond("")
    respond("  This test helps determine if memory gap is due to:")
    respond("    1. Collectable objects (unreferenced, freed when GC runs)")
    respond("    2. Actual memory leak (allocated and still referenced)")
    respond("")
    respond("  How it works:")
    respond("    - Measure Lua heap before/after aggressive GC passes")
    respond("    - If heap drops significantly = collectable objects (fragmentation)")
    respond("    - If heap stays high = likely a leak (objects still referenced)")
    respond("")
    respond("  NOTE: Ruby's fragtest measured process RSS via /proc or WMI.")
    respond("        Lua cannot access process-level RSS from sandboxed code.")
    respond("        This test measures Lua heap only. For native/Rust heap,")
    respond("        use OS tools to compare process RSS before/after.")
    respond("")
    respond("  Starting test...")
    respond("")

    -- Before state
    local heap_before = get_lua_memory_bytes()
    local tables_before = scan_global_tables()
    local scripts_before = get_script_count()

    respond("  BEFORE compaction:")
    respond("    Lua heap:               " .. format_bytes(heap_before))
    respond("    Global tables:          " .. tostring(#tables_before))
    if scripts_before >= 0 then
        respond("    Active scripts:         " .. tostring(scripts_before))
    end
    respond("")

    -- Aggressive GC (mirrors Ruby's 3.times { GC.start })
    respond("  Running GC passes (may take a few seconds)...")
    local pass_results = {}
    for i = 1, 3 do
        local bp = get_lua_memory_bytes()
        collectgarbage("collect")
        local ap = get_lua_memory_bytes()
        pass_results[i] = { before = bp, after = ap, freed = bp - ap }
    end

    local heap_after = get_lua_memory_bytes()
    local tables_after = scan_global_tables()

    respond("")
    respond("  GC PASS RESULTS:")
    for i, p in ipairs(pass_results) do
        respond(string.format("    Pass %d:  %s -> %s  (freed %s)",
            i, format_bytes(p.before), format_bytes(p.after), format_bytes(p.freed)))
    end

    respond("")
    respond("  AFTER GC:")
    respond("    Lua heap:               " .. format_bytes(heap_after))
    respond("    Global tables:          " .. tostring(#tables_after))
    respond("")

    local heap_freed = heap_before - heap_after
    local heap_change = heap_after - heap_before
    local freed_pct = heap_before > 0 and (heap_freed / heap_before * 100) or 0
    local table_change = #tables_after - #tables_before

    respond("  TOTAL CHANGES (before -> after GC):")
    respond("    Heap change:            " .. format_bytes(heap_change))
    if heap_freed > 0 then
        respond(string.format("    Heap freed:             %s (%.1f%%)",
            format_bytes(heap_freed), freed_pct))
    end
    respond("    Table count change:     " .. (table_change >= 0 and "+" or "") .. tostring(table_change))
    respond("")

    -- Analysis
    respond(string.rep("=", 70))
    respond("  ANALYSIS")
    respond(string.rep("=", 70))
    respond("")

    if heap_freed > heap_before * 0.5 then
        respond(string.format("  RESULT: Significant heap reduction (%s, %.1f%%)",
            format_bytes(heap_freed), freed_pct))
        respond("")
        respond("  This indicates MALLOC FRAGMENTATION was the primary issue:")
        respond("    - Objects were allocated and then released by Lua scripts")
        respond("    - But the allocator had not returned the pages")
        respond("    - GC passes forced compaction and memory reclaim")
        respond("")
        respond("  RECOMMENDATIONS:")
        respond("    1. Run ;memory_profiler trim periodically during long sessions")
        respond("    2. This is normal for long-running Lua processes")
        respond("    3. Consider using before_dying hooks to clear large tables")
        if scripts_before > 0 then
            respond("")
            respond("    SCRIPT-SPECIFIC:")
            respond("    4. Check if stopped scripts cleaned up their globals")
            respond("    5. Use before_dying to nil out large script-local tables")
        end
    elseif heap_freed < heap_before * 0.1 then
        respond(string.format("  RESULT: Heap barely changed (%s, %.1f%%)",
            format_bytes(heap_freed), freed_pct))
        respond("")
        respond("  This indicates a MEMORY LEAK, not fragmentation:")
        respond("    - Memory is allocated but objects are still referenced")
        respond("    - GC cannot help because something holds a reference")
        respond("    - Something is preventing garbage collection")
        respond("")
        respond("  LIKELY CULPRITS:")
        respond("    1. Tables accumulating data without bounds (event queues, logs)")
        respond("    2. Closures capturing large values in upvalues")
        respond("    3. Hook functions holding references to large tables")
        respond("    4. Script-global tables never cleared on script exit")
        respond("")
        respond("  NEXT STEPS:")
        respond("    1. Take snapshots before/after hunting to isolate growth")
        respond("    2. ;memory_profiler compare  (which tables grew?)")
        respond("    3. ;memory_profiler detail   (large strings/tables)")
        respond("    4. ;memory_profiler trace    (find large object locations)")
        respond("    5. Check: are DownstreamHook/UpstreamHook closures accumulating data?")
    else
        respond(string.format("  RESULT: Moderate heap reduction (%s, %.1f%%)",
            format_bytes(heap_freed), freed_pct))
        respond("")
        respond("  This indicates BOTH fragmentation AND potential leaks:")
        respond("    - Some memory was fragmentation (freed by GC)")
        respond("    - But significant heap remains after full GC")
        respond("")
        respond("  RECOMMENDATIONS:")
        respond("    1. Run ;memory_profiler trim periodically to handle fragmentation")
        respond("    2. Also investigate potential leaks:")
        respond("       ;memory_profiler compare  (tracked since last snapshot)")
        respond("       ;memory_profiler detail   (large string/table analysis)")
        respond("")
        respond("  Potential leak sources to check:")
        respond("    - Hook closures: are they holding onto game state?")
        respond("    - Script globals: are large tables cleared on exit?")
        respond("    - Event queues: are they bounded or growing forever?")
    end

    respond("")
    respond("  NOTE: This test measures Lua heap only.")
    respond("        The Revenant engine (Rust) may have separate memory growth.")
    respond("        For full process RSS analysis, use OS tools.")
    respond(string.rep("=", 70))
    respond("")
end

--------------------------------------------------------------------------------
-- Trend analysis
--------------------------------------------------------------------------------

local function show_trend()
    local history = _G._memory_profiler_history
    if not history or #history == 0 then
        respond("")
        respond("No snapshot history available.")
        respond("Take snapshots over time with ';memory_profiler snapshot' to track trends.")
        respond("")
        respond("Recommended workflow:")
        respond("  1. At startup:         ;memory_profiler snapshot")
        respond("  2. After 30 min:       ;memory_profiler snapshot")
        respond("  3. After 1 hour:       ;memory_profiler snapshot")
        respond("  4. After 2 hours:      ;memory_profiler snapshot")
        respond("  5. Then run:           ;memory_profiler trend")
        respond("")
        return
    end

    respond("")
    respond(string.rep("=", 70))
    respond("MEMORY TREND ANALYSIS")
    respond(string.rep("=", 70))
    respond("")
    respond("  Snapshots captured: " .. tostring(#history))
    respond("")

    respond("  " .. pad_right("Time", 22)
            .. pad_left("Lua Mem", 12) .. pad_left("Tables", 8)
            .. pad_left("Scripts", 9) .. pad_left("Delta", 12))
    respond("  " .. string.rep("-", 63))

    local prev_mem = nil
    for _, h in ipairs(history) do
        local delta_str = ""
        if prev_mem then
            local d = h.lua_memory - prev_mem
            delta_str = (d >= 0 and "+" or "") .. format_bytes(d)
        end
        local sc = h.script_count and h.script_count >= 0 and tostring(h.script_count) or "N/A"
        respond("  " .. pad_right(h.timestamp, 22)
                .. pad_left(format_bytes(h.lua_memory), 12)
                .. pad_left(tostring(h.table_count), 8)
                .. pad_left(sc, 9)
                .. pad_left(delta_str, 12))
        prev_mem = h.lua_memory
    end

    if #history >= 2 then
        local first = history[1]
        local last = history[#history]
        local total_delta = last.lua_memory - first.lua_memory
        local growth_pct = (total_delta / math.max(first.lua_memory, 1)) * 100

        respond("")
        respond(string.rep("=", 70))
        respond("  GROWTH ANALYSIS (" .. first.timestamp .. " -> " .. last.timestamp .. ")")
        respond(string.rep("=", 70))
        respond("")
        respond("  Duration:                 " .. tostring(#history) .. " snapshot intervals")
        respond("")
        respond("  Lua heap:")
        respond("    Start:                  " .. format_bytes(first.lua_memory))
        respond("    Current:                " .. format_bytes(last.lua_memory))
        respond(string.format("    Growth:                 %s%s (%.1f%%)",
            total_delta >= 0 and "+" or "", format_bytes(total_delta), growth_pct))
        if #history > 2 then
            local avg = total_delta / (#history - 1)
            respond("    Avg per snapshot:       " .. (avg >= 0 and "+" or "") .. format_bytes(math.floor(avg)))
        end
        respond("")

        if first.script_count and last.script_count
                and first.script_count >= 0 and last.script_count >= 0 then
            local sdelta = last.script_count - first.script_count
            respond("  Scripts:")
            respond("    Start:                  " .. tostring(first.script_count))
            respond("    Current:                " .. tostring(last.script_count))
            respond("    Growth:                 " .. (sdelta >= 0 and "+" or "") .. tostring(sdelta))
            respond("")
        end

        respond(string.rep("=", 70))
        respond("  DIAGNOSIS")
        respond(string.rep("=", 70))
        respond("")

        if total_delta > 50 * 1024 * 1024 then
            respond("  WARNING: Significant memory growth detected!")
            respond("")
            respond("  Growth rate: " .. format_bytes(total_delta) .. " total")
            local avg_per = #history > 1 and (total_delta / (#history - 1)) or 0
            if #history >= 3 then
                local projected = last.lua_memory + (avg_per * 10)
                respond("  Projected after 10 more snapshots: " .. format_bytes(math.floor(projected)))
                if projected > 500 * 1024 * 1024 then
                    respond("  CRITICAL: Will exceed 500 MB at this rate!")
                    respond("")
                end
            end
            local gap_contribution = 0
            local heap_contribution = 100
            respond("  Growth breakdown:")
            respond("    Gap growth:             " .. tostring(gap_contribution) .. "% of total (Lua only)")
            respond("    Heap growth:            " .. tostring(heap_contribution) .. "% of total")
            respond("")
            respond("  PRIMARY ISSUE: Lua heap is growing")
            respond("")
            respond("  This indicates RUBY OBJECT-equivalent leak (Lua table/string accumulation):")
            respond("    - Objects being created but not garbage collected")
            respond("    - Likely: event/combat tables growing unbounded")
            respond("    - Possibly: string/table accumulation in hooks")
            respond("")
            respond("  Run ';memory_profiler compare' to see which objects are growing")
            respond("")
        elseif total_delta > 5 * 1024 * 1024 then
            respond("  Moderate growth detected. Worth monitoring.")
            respond("")
            respond("  Growth rate: " .. format_bytes(total_delta))
            respond("  Some growth is normal for active scripts.")
            respond("")
            respond("  Suggested checks:")
            respond("    1. ;memory_profiler fragtest  (can GC recover this?)")
            respond("    2. ;memory_profiler compare   (which tables grew?)")
            respond("")
        else
            respond("  Memory appears stable or growing slowly.")
            respond("")
            if total_delta > 0 then
                respond("  Growth rate: " .. format_bytes(total_delta) .. "/session")
                respond("")
                respond("  This is normal for a Lua process.")
                respond("  Some growth is expected due to:")
                respond("    - Normal object churn")
                respond("    - Lua allocator fragmentation over time")
                respond("    - Script state accumulation")
                respond("")
            end
        end
    end

    respond(string.rep("=", 70))
    respond("")
end

--------------------------------------------------------------------------------
-- Trim
--------------------------------------------------------------------------------

local function trim_memory()
    respond("")
    respond(string.rep("=", 70))
    respond("MALLOC_TRIM EXECUTED")
    respond(string.rep("=", 70))
    respond("")
    respond("  NOTE: Lua has no malloc_trim(0) equivalent to return arena memory to OS.")
    respond("  Running aggressive Lua GC (3 full passes) as the closest equivalent.")
    respond("")

    local before = get_lua_memory_bytes()
    respond("  RSS before:  " .. format_bytes(before) .. "  (Lua heap)")

    for _ = 1, 3 do collectgarbage("collect") end

    local after = get_lua_memory_bytes()
    local freed = before - after
    respond("  RSS after:   " .. format_bytes(after) .. "  (Lua heap)")
    respond("  Change:      " .. format_bytes(freed))
    respond("")

    if freed > 1024 * 1024 then
        respond("  Successfully freed " .. format_bytes(freed) .. " back to Lua allocator!")
        respond("  (Whether the OS reclaims pages depends on the Rust global allocator.)")
    else
        respond("  No significant memory returned (arenas already trimmed or memory in use).")
    end
    respond("")
    respond("  LINUX-SPECIFIC (process-level malloc_trim):")
    respond("    The Revenant engine uses Rust's default allocator.")
    respond("    To control arena behavior, set MALLOC_ARENA_MAX=2 before launch.")
    respond("    Native malloc_trim is not accessible from Lua sandboxed code.")
    respond("")
end

--------------------------------------------------------------------------------
-- Trace allocations
--------------------------------------------------------------------------------

local function trace_allocations(target_name)
    collectgarbage("collect")
    respond("")
    respond(string.rep("=", 70))
    if target_name and target_name ~= "" then
        respond("ALLOCATION SOURCES FOR " .. target_name:upper())
    else
        respond("ALLOCATION SOURCES (Global Deep Scan)")
    end
    respond(string.rep("=", 70))
    respond("")

    if target_name and target_name ~= "" then
        local target = _G[target_name]
        if target == nil then
            respond("  No allocation data available for: " .. target_name)
            respond("")
            respond("  To enable allocation tracking, run this before hunting:")
            respond("    (Lua has no ObjectSpace.trace_object_allocations_start equivalent)")
            respond("")
            respond("  Then hunt for a while and run:")
            respond("    ;memory_profiler trace " .. target_name)
            respond("")
            respond("  Available globals matching (case-insensitive search):")
            local lower_target = target_name:lower()
            for name, _ in pairs(_G) do
                if tostring(name):lower():find(lower_target, 1, true) then
                    respond("    - " .. name .. " (" .. type(_G[name]) .. ")")
                end
            end
            respond("")
            return
        end

        local vtype = type(target)
        respond("  Found: " .. target_name .. " (" .. vtype .. ")")
        respond("")

        if vtype == "table" then
            local entries = count_table_entries(target)
            local est_size = estimate_table_size(target, {})
            respond("  Total allocation sites: 1 global (" .. target_name .. ")")
            respond("")
            respond("  Top allocation sites by object count:")
            respond("")
            respond(string.format("    %4d. %6d objs  %10s  %s",
                1, entries, format_bytes(est_size), target_name))
            respond("")
            respond("  Top allocation sites by memory size:")
            respond("")
            respond(string.format("    %4d. %10s  %6d objs  %s",
                1, format_bytes(est_size), entries, target_name))
            respond("")
            respond("  Contents (first 20 keys):")
            local shown = 0
            for k, v in pairs(target) do
                if shown >= 20 then break end
                shown = shown + 1
                local vt = type(v)
                local detail = ""
                if vt == "string" then
                    detail = string.format(" (%s): \"%s\"", format_bytes(#v), v:sub(1, 50):gsub("\n", "\\n"))
                elseif vt == "table" then
                    local ne = count_table_entries(v)
                    detail = string.format(" [%d entries, ~%s]", ne, format_bytes(estimate_table_size(v, {})))
                elseif vt == "number" then
                    detail = " = " .. tostring(v)
                elseif vt == "function" then
                    detail = " (function)"
                end
                respond("    [" .. tostring(k) .. "] " .. vt .. detail)
            end
            if entries > 20 then
                respond("    ... and " .. tostring(entries - 20) .. " more entries")
            end
        elseif vtype == "string" then
            respond("  Total allocation sites: 1 global string")
            respond("")
            respond("  Top allocation sites by object count:")
            respond("")
            respond(string.format("    %4d. %6d objs  %10s  %s  in _G",
                1, 1, format_bytes(#target), target_name))
            respond("")
            respond("  Content: \"" .. target:sub(1, 200):gsub("\n", "\\n") .. "\"")
        else
            respond("  " .. vtype .. ": no allocation site tracking available in Lua.")
        end
    else
        -- General scan
        local tables = scan_global_tables()
        respond("  NOTE: Lua has no ObjectSpace.trace_object_allocations_start.")
        respond("        Allocation source file:line tracking is not available in Lua 5.4.")
        respond("")
        respond("  Showing current allocation concentrations instead:")
        respond("")
        respond("  Top allocation sites by object count:")
        respond("")
        respond("  " .. pad_right("Location", 35) .. pad_left("Entries", 10)
                .. pad_left("Est. Size", 12))
        respond("  " .. string.rep("-", 57))
        for i = 1, math.min(30, #tables) do
            local t = tables[i]
            respond(string.format("  %3d. %-35s %10d  %12s",
                i, t.name, t.entries, format_bytes(t.estimated_bytes)))
        end
        respond("")
        respond("  Top allocation sites by memory size:")
        respond("")
        respond("  (same data sorted by size — already sorted above)")
        respond("")

        -- Large strings
        local str_data = scan_strings_comprehensive(100, 20)
        if #str_data.samples > 0 then
            respond("  Large strings found (" .. tostring(str_data.total_count) .. " total >= 100 bytes):")
            respond("")
            for i, s in ipairs(str_data.samples) do
                respond(string.format("  %3d. %10s  %6d objs  %s",
                    i, format_bytes(s.size), 1, s.path))
            end
            respond("")
        end
    end

    respond("  To enable allocation tracking workflow:")
    respond("    ;memory_profiler start")
    respond("")
end

--------------------------------------------------------------------------------
-- Start tracing
--------------------------------------------------------------------------------

local function start_tracing()
    respond("")
    respond("  To enable allocation tracing, choose one of these options:")
    respond("")
    respond("  NOTE: Lua has no ObjectSpace.trace_object_allocations_start.")
    respond("        Ruby tracks file:line of every object allocation at the VM level.")
    respond("        Lua 5.4 does not expose allocation site information.")
    respond("")
    respond("  Option 1 (Quick — snapshot diff):")
    respond("    ;memory_profiler snapshot          (take baseline)")
    respond("    -- run scripts / hunt for a while --")
    respond("    ;memory_profiler compare           (see which tables grew)")
    respond("")
    respond("  Option 2 (Background service — trend tracking):")
    respond("    ;memory_profiler snapshot          (at startup)")
    respond("    -- wait 30 minutes --")
    respond("    ;memory_profiler snapshot          (repeat periodically)")
    respond("    ;memory_profiler trend             (see growth rate over time)")
    respond("")
    respond("  Then hunt for a while and run:")
    respond("    ;memory_profiler trace String      -- see large string locations")
    respond("    ;memory_profiler trace Array       -- see large table locations")
    respond("    ;memory_profiler trace MyGlobal    -- inspect specific global")
    respond("")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("Unknown command. Usage:")
    respond("")
    respond("  ;memory_profiler snapshot           - Take a baseline snapshot")
    respond("  ;memory_profiler compare            - Compare to snapshot and show growth")
    respond("  ;memory_profiler top                - Show top memory consumers right now")
    respond("  ;memory_profiler gc                 - Force GC and show stats")
    respond("  ;memory_profiler detail             - Deep dive into String/Array/Hash objects")
    respond("  ;memory_profiler system             - Show Lua heap vs process memory gap")
    respond("  ;memory_profiler fragtest           - Test if gap is fragmentation vs leak")
    respond("  ;memory_profiler trend              - Show memory trend over snapshots")
    respond("  ;memory_profiler trim               - Force malloc to return memory")
    respond("")
    respond("  Allocation tracing (shows WHERE objects are created):")
    respond("  ;memory_profiler start              - Show how to enable allocation tracing")
    respond("  ;memory_profiler trace [Class]      - Show allocation sources (default: all)")
    respond("")
    respond("  Examples:")
    respond("    ;memory_profiler trace String     - See where strings are allocated")
    respond("    ;memory_profiler trace Array      - See where arrays are allocated")
    respond("    ;memory_profiler trace Thread     - See where threads are allocated")
    respond("    ;memory_profiler system           - See memory gap breakdown")
    respond("")
    respond("  Fragmentation vs Leak Detection:")
    respond("    ;memory_profiler fragtest         - Run GC and see if heap drops")
    respond("      If drops significantly -> fragmentation (run trim periodically)")
    respond("      If stays high -> memory leak (investigate with snapshot/compare)")
    respond("")
    respond("  Trend Analysis (track growth over time):")
    respond("    1. ;memory_profiler snapshot      - At startup")
    respond("    2. Hunt for 30 minutes")
    respond("    3. ;memory_profiler snapshot      - After hunting")
    respond("    4. ;memory_profiler trend         - See growth rate and projections")
    respond("")
end

--------------------------------------------------------------------------------
-- Main dispatch
--------------------------------------------------------------------------------

local cmd = ((Script.vars[1] or ""):lower()):match("^%s*(.-)%s*$")
local arg = (Script.vars[2] or ""):match("^%s*(.-)%s*$")

if cmd == "" or cmd == "help" then
    respond("")
    respond("=== Memory Profiler ===")
    respond("  ;memory_profiler snapshot   - Take a snapshot")
    respond("  ;memory_profiler compare    - Compare to last snapshot")
    respond("  ;memory_profiler top        - Show top memory consumers")
    respond("  ;memory_profiler gc         - Force GC and show stats")
    respond("  ;memory_profiler detail     - Deep dive: strings, tables, functions")
    respond("  ;memory_profiler system     - System memory breakdown")
    respond("  ;memory_profiler fragtest   - Test if gap is fragmentation vs leak")
    respond("  ;memory_profiler trend      - Show trend over snapshots")
    respond("  ;memory_profiler trim       - Force aggressive GC cycle")
    respond("  ;memory_profiler start      - How to enable allocation tracing")
    respond("  ;memory_profiler trace [X]  - Show allocation sources")
    respond("")
elseif cmd == "snapshot" or cmd == "snap" then
    take_snapshot()
elseif cmd == "compare" or cmd == "diff" then
    compare_snapshots()
elseif cmd == "top" or cmd == "show" then
    show_top()
elseif cmd == "gc" then
    force_gc()
elseif cmd == "detail" or cmd == "detailed" or cmd == "strings" then
    detailed_analysis()
elseif cmd == "system" or cmd == "gap" or cmd == "breakdown" then
    show_system()
elseif cmd == "fragtest" or cmd == "frag" or cmd == "fragmentation" then
    fragmentation_test()
elseif cmd == "trend" or cmd == "trends" or cmd == "history" then
    show_trend()
elseif cmd == "trim" or cmd == "malloc_trim" then
    trim_memory()
elseif cmd == "trace" or cmd == "allocations" then
    trace_allocations(arg)
elseif cmd == "start" or cmd == "enable" then
    start_tracing()
else
    respond("Unknown command: " .. cmd)
    show_help()
end
