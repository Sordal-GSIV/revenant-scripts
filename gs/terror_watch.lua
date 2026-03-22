--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: terror_watch
--- version: 1.2.5
--- author: Ensayn
--- game: gs
--- description: Monitor eerie cry effects and display enemy IDs with SSR results and TTL
--- tags: monitoring, combat, targeting, terror
--- changelog:
---   v1.2.5 - 2025-09-23 - Updated TTL to show tenths of seconds precision (e.g., 12.3s)
---   v1.2.4 - 2025-09-23 - Added before_dying hook to ensure cleanup works with ;kill command
---   v1.2.3 - 2025-09-23 - Added cleanup command to remove orphaned hooks manually
---   v1.2.2 - 2025-09-23 - Added proper downstream hook cleanup on script exit
---   v1.2.1 - 2025-09-23 - Fixed data_dir compatibility issue for older Lich versions
---   v1.2.0 - 2025-09-23 - Added CSV logging functionality and log viewing commands
---   v1.1.3 - 2025-09-23 - Added support for 'himself' in recovery messages
---   v1.1.2 - 2025-09-23 - Fixed regex to handle both 'itself' and 'herself' in recovery messages
---   v1.1.1 - 2025-09-23 - Added SSR result display to shakes off fear line
---   v1.1.0 - 2025-09-23 - Fixed regex to handle 'itself' in separate XML tag
---   v1.0.0 - 2025-09-23 - Initial implementation
---
--- Usage: ;terror_watch [help|log|log<N>|cleanup]

local CSV_FILE = "data/terror_log.csv"

-- Initialize CSV with headers if it doesn't exist
if not File.exists(CSV_FILE) then
    File.write(CSV_FILE, "Timestamp,Name,ID,SSR,TTL\n")
end

-- Append a row to the CSV (read + append + write since File.write overwrites)
local function log_terror_recovery(creature_name, creature_id, ssr, ttl)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local ssr_val = ssr or "N/A"
    local line = string.format("%s,%s,%s,%s,%.1f\n", timestamp, creature_name, creature_id, ssr_val, ttl)
    local content = File.read(CSV_FILE) or "Timestamp,Name,ID,SSR,TTL\n"
    File.write(CSV_FILE, content .. line)
end

-- Show last N entries from the CSV log
local function show_recent_entries(count)
    count = count or 10
    if not File.exists(CSV_FILE) then
        respond("No terror log file found.")
        return
    end
    local content, err = File.read(CSV_FILE)
    if not content then
        respond("Could not read terror log: " .. (err or "unknown"))
        return
    end
    local lines = {}
    for line in content:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    local header = lines[1] or "Timestamp,Name,ID,SSR,TTL"
    local entries = {}
    for i = 2, #lines do entries[#entries + 1] = lines[i] end
    if #entries == 0 then
        respond("No terror entries recorded yet.")
        return
    end
    local start_idx = math.max(1, #entries - count + 1)
    local recent = {}
    for i = start_idx, #entries do recent[#recent + 1] = entries[i] end
    respond("\n=== RECENT TERROR LOG (Last " .. #recent .. " entries) ===")
    respond(header)
    respond(string.rep("-", 60))
    for _, line in ipairs(recent) do respond(line) end
    respond("=== END LOG ===")
end

-- Escape a string for use in a Lua pattern
local function escape_pattern(s)
    return s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

-- Parse command arguments
local arg1 = Script.vars[1]
if arg1 then
    local lower = arg1:lower()
    if lower == "help" then
        respond("\nUSAGE: ;terror_watch [help|log|log<N>|cleanup]")
        respond("\nDESCRIPTION:")
        respond("  Monitors for eerie cry effects and shows enemy IDs")
        respond("  when creatures are affected by terror.")
        respond("\nTRIGGER:")
        respond("  'You let loose an eerie, modulating cry!'")
        respond("\nOUTPUT:")
        respond("  Shows GameObj ID, SSR result, and TTL in creature lines")
        respond("\nCOMMANDS:")
        respond("  ;terror_watch                Start monitoring")
        respond("  ;terror_watch help           Show this help")
        respond("  ;terror_watch log            Show last 10 terror log entries")
        respond("  ;terror_watch log25          Show last 25 terror log entries")
        respond("  ;terror_watch cleanup        Remove orphaned hooks")
        respond("\nCSV LOG:")
        respond("  Terror recovery data is automatically logged to: " .. CSV_FILE)
        exit()
    elseif lower == "log" then
        show_recent_entries(10)
        exit()
    elseif lower:match("^log(%d+)$") then
        local n = tonumber(lower:match("^log(%d+)$"))
        show_recent_entries(n)
        exit()
    elseif lower == "cleanup" then
        DownstreamHook.remove("terror_watch")
        respond("Removed orphaned terror_watch hook (if present).")
        exit()
    end
end

-- State (upvalues captured by the hook closure)
local watching    = false   -- currently in the 10s terror monitoring window
local terror_start = 0      -- time_f() when eerie cry was detected
local current_ssr = nil     -- SSR from most recent [SSR result: N] line (persists across calls)
local terror_times = {}     -- {creature_id => time_f()} when first terrified
local terror_ssr   = {}     -- {creature_id => ssr_string}

echo("Terror Watch started - monitoring for eerie cry effects...")
echo("Use ;kill terror_watch to stop monitoring")

add_hook("downstream", "terror_watch", function(xml)
    local now = time_f()

    -- Trigger: eerie, modulating cry cast
    if xml:find("You let loose an eerie, modulating cry!", 1, true) then
        watching = true
        terror_start = now
        current_ssr = nil
    end

    -- Expire stale terror_times entries (> 60 seconds)
    for id, t in pairs(terror_times) do
        if now - t > 60 then
            terror_times[id] = nil
            terror_ssr[id] = nil
        end
    end

    -- Close the monitoring window after 10 seconds
    if watching and (now - terror_start > 10) then
        watching = false
        current_ssr = nil
    end

    -- Capture SSR result — persists until consumed by the next terror hit
    local ssr_cap = xml:match("%[SSR result: (%d+)")
    if ssr_cap then
        current_ssr = ssr_cap
    end

    -- ── Terror hit: "looks at you in utter terror!" ──────────────────────────

    if xml:find("looks at you in utter terror", 1, true) then
        local id = xml:match('exist="(%d+)"')

        if id then
            -- Record time (first occurrence only)
            terror_times[id] = terror_times[id] or now
            -- Record SSR and consume it
            if current_ssr then
                terror_ssr[id] = current_ssr
                current_ssr = nil
            end

            local suffix
            if terror_ssr[id] then
                suffix = string.format("(ID:%s)(SSR:%s)", id, terror_ssr[id])
            else
                suffix = string.format("(ID:%s)", id)
            end

            -- Try to find name in <a>...</a> tag
            local name = xml:match(">([^<]+)</a>.-looks at you in utter terror")
            if name then
                return xml:gsub(">" .. escape_pattern(name) .. "</a>",
                    ">" .. name .. " " .. suffix .. "</a>", 1)
            end
            -- Fallback: any closing tag
            name = xml:match(">([^<]+)</.->.-looks at you in utter terror")
            if name then
                return xml:gsub(">" .. escape_pattern(name) .. "<",
                    ">" .. name .. " " .. suffix .. "<", 1)
            end

        else
            -- No exist= attribute: look up by name via GameObj.npcs()
            local clean = xml:gsub("<[^>]+>", ""):match("^%s*(.-)%s*$")
            local creature_name = clean and clean:match("^(.-)%s+looks at you in utter terror")
            if creature_name and creature_name ~= "" then
                local match_npc, match_count = nil, 0
                for _, npc in ipairs(GameObj.npcs()) do
                    if npc.name == creature_name then
                        match_npc = npc
                        match_count = match_count + 1
                    end
                end
                if match_count == 1 then
                    local npc_id = match_npc.id
                    terror_times[npc_id] = terror_times[npc_id] or now
                    if current_ssr then
                        terror_ssr[npc_id] = current_ssr
                        current_ssr = nil
                    end
                    local suffix
                    if terror_ssr[npc_id] then
                        suffix = string.format("(ID:%s)(SSR:%s)", npc_id, terror_ssr[npc_id])
                    else
                        suffix = string.format("(ID:%s)", npc_id)
                    end
                    return xml:gsub(">" .. escape_pattern(creature_name) .. "<",
                        ">" .. creature_name .. " " .. suffix .. "<", 1)
                end
            end
        end
    end

    -- ── Fear recovery: "gathers … and shakes off the fear" ───────────────────

    if xml:find("shakes off the fear", 1, true) then
        local id = xml:match('exist="(%d+)"')

        if id and terror_times[id] then
            local ttl     = now - terror_times[id]
            local ssr_val = terror_ssr[id]
            local suffix
            if ssr_val then
                suffix = string.format("(ID:%s)(SSR:%s)(TTL:%.1fs)", id, ssr_val, ttl)
            else
                suffix = string.format("(ID:%s)(TTL:%.1fs)", id, ttl)
            end

            -- Try <a>...</a> tag first
            local name = xml:match(">([^<]+)</a>.-gathers.-shakes off the fear")
            if name then
                log_terror_recovery(name, id, ssr_val, ttl)
                terror_times[id] = nil
                terror_ssr[id]   = nil
                return xml:gsub(">" .. escape_pattern(name) .. "</a>",
                    ">" .. name .. " " .. suffix .. "</a>", 1)
            end
            -- Fallback: any closing tag
            name = xml:match(">([^<]+)</.->.-gathers.-shakes off the fear")
            if name then
                log_terror_recovery(name, id, ssr_val, ttl)
                terror_times[id] = nil
                terror_ssr[id]   = nil
                return xml:gsub(">" .. escape_pattern(name) .. "<",
                    ">" .. name .. " " .. suffix .. "<", 1)
            end
            -- Tracked but couldn't enhance — still log and clear
            log_terror_recovery("unknown", id, ssr_val, ttl)
            terror_times[id] = nil
            terror_ssr[id]   = nil

        else
            -- No exist= attribute: fall back to GameObj.npcs()
            local clean = xml:gsub("<[^>]+>", ""):match("^%s*(.-)%s*$")
            local creature_name = clean and clean:match("^(.-)%s+gathers")
            if creature_name and creature_name ~= "" then
                local match_npc, match_count = nil, 0
                for _, npc in ipairs(GameObj.npcs()) do
                    if npc.name == creature_name then
                        match_npc = npc
                        match_count = match_count + 1
                    end
                end
                if match_count == 1 then
                    local npc_id = match_npc.id
                    if terror_times[npc_id] then
                        local ttl     = now - terror_times[npc_id]
                        local ssr_val = terror_ssr[npc_id]
                        local suffix
                        if ssr_val then
                            suffix = string.format("(ID:%s)(SSR:%s)(TTL:%.1fs)", npc_id, ssr_val, ttl)
                        else
                            suffix = string.format("(ID:%s)(TTL:%.1fs)", npc_id, ttl)
                        end
                        log_terror_recovery(creature_name, npc_id, ssr_val, ttl)
                        terror_times[npc_id] = nil
                        terror_ssr[npc_id]   = nil
                        return xml:gsub(">" .. escape_pattern(creature_name) .. "<",
                            ">" .. creature_name .. " " .. suffix .. "<", 1)
                    end
                end
            end
        end
    end

    return xml
end)

before_dying(function()
    DownstreamHook.remove("terror_watch")
    echo("Terror Watch stopped")
end)

while true do pause(1) end
