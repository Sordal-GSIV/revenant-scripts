--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: flarewindow
--- version: 2.0.0
--- author: Codex
--- contributors: ClaudeCode, Phocosoen
--- game: gs
--- description: Real-time flare tracking window — combo capture, streak tracking,
---   per-flare stats, Discord webhook file upload, clipboard export, persistent
---   data via JSON. Uses flare_patterns.lua for pattern matching.
--- tags: wrayth, frontend, flares, tracking, window, combos
---
--- Original Lich5 authors: Codex, ClaudeCode, Phocosoen
--- Ported to Revenant Lua from flarewindow.lic (v1.0.0)
---
--- Changelog (from Lich5 flarewindow.lic v1.0.0):
---   v2.0.0 (2026-03-19): Full Revenant rewrite — YAML→JSON persistence via
---     File/Json API, Ruby Regexp→Regex.new(), Stormfront XML dialogs via put(),
---     net/http→Http.post() for Discord webhooks, clipboard via System.copy_to_clipboard(),
---     Lich::Claim→Claim.mine(), Effects::Buffs→Effects.Buffs. All original functionality
---     preserved: display modes (none/full/top N), combo capture, high scores export,
---     Discord file upload, flaretracker_2 import, persistent data with auto-save.
---
--- Usage:
---   ;flarewindow               - Start with persisted data (display mode COMBOS ONLY)
---   ;flarewindow none          - Display COMBOS ONLY (default)
---   ;flarewindow full          - Display FLARES ONLY (all flares)
---   ;flarewindow top5          - Display FLARES ONLY (top 5 flares)
---   ;flarewindow top <N>       - Display FLARES ONLY (top N flares)
---   ;flarewindow import        - Import/merge flaretracker_2 data
---   ;flarewindow reset         - Clear persisted data, then start fresh
---   ;flarewindow delete        - Delete persisted data file, then start fresh
---
--- Runtime ;send commands (while running):
---   ;send fwstats              - Output all individual flare stats
---   ;send fwstats top<N>       - Output top N individual flare stats
---   ;send fwcombo              - Copy most recent combo to clipboard
---   ;send fwcombo NUMBER       - Copy combo 2, 3, 4, etc from Recent Combo History
---   ;send fwcombo highest      - Copy highest-ever combo to clipboard
---   ;send fwcombo reset        - Reset highest combo record
---   ;send fwdiscord set <URL>  - Set Discord webhook URL
---   ;send fwdiscord status     - Show Discord webhook status
---   ;send fwdiscord off        - Disable Discord and clear saved webhook

no_kill_all()

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WINDOW_ID      = "FlareWindow"
local WINDOW_TITLE   = "Flares"
local SAVE_INTERVAL  = 15        -- seconds
local SAVE_THRESHOLD = 20        -- events
local MAX_COMBOS     = 100
local RENDER_THROTTLE = 0.15     -- seconds
local COMBO_TIME_WINDOW = 1.5    -- seconds
local MIN_COMBO_CAPTURE = 3
local MAX_ATTACK_LINES  = 240
local PRE_ATTACK_CONTEXT_SECS = 1.0

local KI_COMBO_LABELS = {
    [3]  = "TRIPLE",
    [4]  = "SUPER",
    [5]  = "HYPER",
    [6]  = "BRUTAL",
    [7]  = "MASTER",
    [8]  = "AWESOME",
    [9]  = "BLASTER",
    [10] = "MONSTER",
    [11] = "KING",
    [12] = "KILLER",
    [13] = "ULTRA",
    [14] = "FLAWLESS",
    [15] = "MASTERWORK",
    [16] = "PERFECT",
    [17] = "BRILLIANT",
    [18] = "RESPLENDENT",
    [19] = "MAGNIFICIENT",
    [20] = "SPECTACULAR",
    [21] = "TRANSCENDENT",
    [22] = "AVALUKA",
    [23] = "KENSTROM",
    [24] = "MARSTREFORN",
    [25] = "ZISSU",
    [26] = "NAIKEN",
    [27] = "NYXUS",
    [28] = "ESTILD",
    [29] = "RETSER",
    [30] = "WYROM",
}

local COMBO_IGNORE_TOKENS = {
    "DoT", "FAura1706", "Defensive", "SWard319", "WThorns640",
    "VolnArmor", "Untrammel209", "TwistedArmor_Augmentation",
    "TrollHeart", "TBlood1125",
}

--------------------------------------------------------------------------------
-- Load flare patterns
--------------------------------------------------------------------------------

local script_dir = File.is_dir("gs/flarewindow") and "gs/flarewindow" or "flarewindow"
local ok_fp, fp = pcall(dofile, script_dir .. "/flare_patterns.lua")
if not ok_fp or not fp then
    echo("flarewindow: failed to load flare_patterns.lua — " .. tostring(fp))
    return
end

local NODMG   = fp.NODMGFLARE_PATTERNS
local DMG     = fp.DMGFLARE_PATTERNS
local ATTACKS = fp.ATTACK_PATTERNS

if not NODMG or not DMG or not ATTACKS then
    echo("flarewindow: required flare pattern constants are missing.")
    return
end

-- Build combined pattern table (no-damage + damage + attack)
local combined_patterns = {}
for k, v in pairs(NODMG)   do combined_patterns[k] = v end
for k, v in pairs(DMG)     do combined_patterns[k] = v end
for k, v in pairs(ATTACKS) do combined_patterns[k] = v end

--------------------------------------------------------------------------------
-- Persistence helpers (JSON + File API)
--------------------------------------------------------------------------------

local function data_dir()
    local game = GameState.game or "GS3"
    local name = GameState.name or "Unknown"
    local base = "data/" .. game
    if not File.is_dir(base) then File.mkdir(base) end
    local dir = base .. "/" .. name
    if not File.is_dir(dir) then File.mkdir(dir) end
    return dir
end

local function persist_path()
    return data_dir() .. "/flarewindow_data.json"
end

local function flaretracker_path()
    return data_dir() .. "/flaredata.json"
end

local function initial_data()
    return {
        damage_data            = {},
        total_attacks          = 0,
        highest_as             = 0,
        highest_cs             = 0,
        total_combos           = 0,
        combo_count_sum        = 0,
        total_combo_damage     = 0,
        current_flare_streak   = 0,
        highest_flare_streak   = 0,
        signature_combo_counts = {},
        highest_flare_combo    = 0,
        combo_history          = {},
        highest_combo_event    = {},
    }
end

local function load_persisted(path)
    if not File.exists(path) then return initial_data() end
    local raw = File.read(path)
    if not raw or raw == "" then return initial_data() end
    local ok2, data = pcall(Json.decode, raw)
    if not ok2 or type(data) ~= "table" then return initial_data() end
    local base = initial_data()
    for k, v in pairs(base) do
        if data[k] == nil then data[k] = v end
    end
    -- Trim combo history
    local h = data.combo_history
    if type(h) == "table" and #h > MAX_COMBOS then
        local trimmed = {}
        for i = #h - MAX_COMBOS + 1, #h do trimmed[#trimmed + 1] = h[i] end
        data.combo_history = trimmed
    end
    return data
end

local function save_persisted(path, state)
    local payload = {
        damage_data            = state.damage_data or {},
        total_attacks          = state.total_attacks or 0,
        highest_as             = state.highest_as or 0,
        highest_cs             = state.highest_cs or 0,
        total_combos           = state.total_combos or 0,
        combo_count_sum        = state.combo_count_sum or 0,
        total_combo_damage     = state.total_combo_damage or 0,
        current_flare_streak   = state.current_flare_streak or 0,
        highest_flare_streak   = state.highest_flare_streak or 0,
        signature_combo_counts = type(state.signature_combo_counts) == "table" and state.signature_combo_counts or {},
        highest_flare_combo    = state.highest_flare_combo or 0,
        combo_history          = {},
        highest_combo_event    = type(state.highest_combo_event) == "table" and state.highest_combo_event or {},
    }
    -- Trim combo history
    local ch = state.combo_history or {}
    local start = #ch > MAX_COMBOS and (#ch - MAX_COMBOS + 1) or 1
    for i = start, #ch do payload.combo_history[#payload.combo_history + 1] = ch[i] end

    local ok3, json_str = pcall(Json.encode, payload)
    if not ok3 then
        echo("flarewindow: save failed — " .. tostring(json_str))
        return
    end
    -- Atomic write via temp file
    local tmp = path .. ".tmp"
    local wok, werr = pcall(File.write, tmp, json_str)
    if not wok then
        echo("flarewindow: save failed — " .. tostring(werr))
        pcall(File.remove, tmp)
        return
    end
    pcall(File.replace, tmp, path)
end

local function save_if_needed(path, state, last_save_at, event_counter, force)
    local now = os.time()
    local should = force or event_counter >= SAVE_THRESHOLD or (now - last_save_at) >= SAVE_INTERVAL
    if not should then return last_save_at, event_counter end
    save_persisted(path, state)
    return now, 0
end

--------------------------------------------------------------------------------
-- Import from flaretracker_2 data
--------------------------------------------------------------------------------

local function import_flaretracker(existing)
    local src = flaretracker_path()
    if not File.exists(src) then
        return nil, "flarewindow: flaretracker source not found at " .. src .. "."
    end
    local raw = File.read(src)
    if not raw or raw == "" then
        return nil, "flarewindow: flaretracker file is empty."
    end
    local ok2, src_data = pcall(Json.decode, raw)
    if not ok2 or type(src_data) ~= "table" then
        return nil, "flarewindow: flaretracker data is invalid."
    end
    local src_damage = src_data.damage_data
    if type(src_damage) ~= "table" then
        return nil, "flarewindow: flaretracker data missing damage_data."
    end

    local merged = initial_data()
    if type(existing) == "table" then
        for k, v in pairs(existing) do merged[k] = v end
    end
    merged.damage_data = merged.damage_data or {}

    local imported_rows = 0
    for k, v in pairs(src_damage) do
        local key = tostring(k)
        if not merged.damage_data[key] then merged.damage_data[key] = {} end
        if type(v) == "table" then
            for _, val in ipairs(v) do
                merged.damage_data[key][#merged.damage_data[key] + 1] = val
                imported_rows = imported_rows + 1
            end
        end
    end

    merged.total_attacks = (merged.total_attacks or 0) + (src_data.total_attacks or 0)
    local imported_combo = 0
    if type(src_data.highest_combo) == "table" then
        imported_combo = src_data.highest_combo.flare_count or 0
    end
    merged.highest_flare_combo = math.max(merged.highest_flare_combo or 0, imported_combo)

    return merged, "flarewindow: imported " .. imported_rows .. " flare records from flaretracker_2."
end

--------------------------------------------------------------------------------
-- Startup option parsing
--------------------------------------------------------------------------------

local function parse_startup_options()
    local args = {}
    local raw = Script.vars[0] or ""
    for word in raw:gmatch("%S+") do
        args[#args + 1] = word:lower()
    end

    local options = {
        action = nil,
        display_mode = "none",
        top_n = nil,
        unknown = {},
    }

    local idx = 1
    while idx <= #args do
        local token = args[idx]
        if token == "reset" or token == "delete" or token == "import" then
            options.action = token
        elseif token == "none" then
            options.display_mode = "none"
            options.top_n = nil
        elseif token == "full" then
            options.display_mode = "full"
            options.top_n = nil
        elseif token:match("^top(%d+)$") then
            local n = tonumber(token:match("^top(%d+)$"))
            if n and n > 0 then
                options.display_mode = "top"
                options.top_n = n
            else
                options.unknown[#options.unknown + 1] = token
            end
        elseif token == "top" then
            local nxt = args[idx + 1]
            if nxt and nxt:match("^%d+$") then
                local n = tonumber(nxt)
                if n and n > 0 then
                    options.display_mode = "top"
                    options.top_n = n
                else
                    options.unknown[#options.unknown + 1] = "top " .. nxt
                end
                idx = idx + 1
            else
                options.unknown[#options.unknown + 1] = token
            end
        else
            options.unknown[#options.unknown + 1] = token
        end
        idx = idx + 1
    end

    return options
end

--------------------------------------------------------------------------------
-- Utility functions
--------------------------------------------------------------------------------

local function sanitize_xml(value)
    local s = tostring(value)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub("'", "&apos;")
    s = s:gsub('"', "&quot;")
    return s
end

local function fmt_int(value)
    local n = tostring(math.floor(tonumber(value) or 0))
    -- Insert commas
    local result = ""
    local len = #n
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. n:sub(i, i)
    end
    return result
end

local function calc_rate(flare_hits, total_flare_hits)
    if total_flare_hits <= 0 then return 0.0 end
    return math.floor((flare_hits / total_flare_hits) * 1000 + 0.5) / 10
end

local function calc_fpa(flare_hits, total_attacks)
    if flare_hits <= 0 or total_attacks <= 0 then return "NA" end
    return string.format("%.1f", total_attacks / flare_hits)
end

local function calc_overall_rate(total_flares, total_attacks)
    if total_attacks <= 0 then return 0.0 end
    return math.floor((total_flares / total_attacks) * 1000 + 0.5) / 10
end

local function combo_label_for(count)
    return KI_COMBO_LABELS[tonumber(count) or 0]
end

local function combo_display_text(count)
    local label = combo_label_for(count)
    if label then return count .. " " .. label .. " Combo" end
    return count .. " Combo"
end

local function short_flare_name(flare_type)
    return tostring(flare_type):gsub("_", " "):sub(1, 26)
end

local function combo_ignored(flare_type)
    local ft = tostring(flare_type)
    for _, tok in ipairs(COMBO_IGNORE_TOKENS) do
        if ft:find(tok, 1, true) then return true end
    end
    return false
end

local function count_table(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function table_values_total_size(damage_data)
    local total = 0
    for _, v in pairs(damage_data) do
        if type(v) == "table" then total = total + #v end
    end
    return total
end

local re_as = Regex.new("\\bAS:\\s*\\+?(-?\\d+)")
local re_cs = Regex.new("\\bCS:\\s*\\+?(-?\\d+)")

local function parse_as_cs(line)
    local as_val, cs_val = nil, nil
    local as_caps = re_as:captures(line)
    if as_caps and as_caps[1] then as_val = tonumber(as_caps[1]) end
    local cs_caps = re_cs:captures(line)
    if cs_caps and cs_caps[1] then cs_val = tonumber(cs_caps[1]) end
    return as_val, cs_val
end

local function claim_owned_room()
    local ok2, result = pcall(function()
        return Claim and Claim.mine and Claim.mine()
    end)
    if ok2 then return result end
    return false
end

local re_damage_pts = Regex.new("(\\d+) points? of damage!")
local re_additional = Regex.new("suffers an additional (\\d+) damage!")
local re_mana_gain  = Regex.new("You feel (\\d+) mana surge into you|You gain (\\d+) mana")
local re_roundtime  = Regex.new("(?i)Roundtime")

-- Patterns that signal end-of-damage-lookahead
local re_stop_lookahead = Regex.new("(?i)AS:\\s*.* vs DS:\\s*.* with AvD|Roundtime|CS:\\s*.* vs TD:\\s*.* \\+ CvA|is unaffected|with little effect|no effect|thorny barrier surrounding .* blocks|blinks and looks around in confusion for a moment|manages to dodge the licking flames|unharmed by the|scoffs at the")

-- Flare types that need extended (5-line) lookahead
local EXTENDED_LOOKAHEAD_TOKENS = {
    "DoT", "GEF", "Firewheel", "Greater_Rhimar", "HolyFire", "ELink1117_Propagation",
}

local function needs_extended_lookahead(flare_type)
    local ft = tostring(flare_type)
    for _, tok in ipairs(EXTENDED_LOOKAHEAD_TOKENS) do
        if ft:find(tok, 1, true) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Discord webhook
--------------------------------------------------------------------------------

local function discord_webhook_url()
    local raw = CharSettings.flarewindow_discord_webhook
    if not raw or raw == "" then return "" end
    local text = raw:match("^%s*(.-)%s*$") or ""
    if text == "" then return "" end
    -- Check for parenthesized URL
    local paren = text:match("%(https?://discord[a-z]*%.com/api/webhooks/[^%)%s]+%)")
    if paren then return paren:sub(2, -2) end
    return text
end

local function discord_enabled()
    return discord_webhook_url() ~= ""
end

local function set_discord_webhook(value)
    CharSettings.flarewindow_discord_webhook = tostring(value or "")
end

local function send_combo_to_discord(combo_text, combo_event)
    local url = discord_webhook_url()
    if url == "" then return "not_configured" end

    local file_name = "flare_combo_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local char_name = GameState.name or "Unknown"

    local boundary = "----FlareWindowBoundary" .. tostring(math.random(1000000000))
    local payload_json = Json.encode({ username = char_name .. " FlareWindow" })

    local body = "--" .. boundary .. "\r\n"
        .. 'Content-Disposition: form-data; name="payload_json"\r\n'
        .. "Content-Type: application/json\r\n\r\n"
        .. payload_json .. "\r\n"
        .. "--" .. boundary .. "\r\n"
        .. 'Content-Disposition: form-data; name="file"; filename="' .. file_name .. '"\r\n'
        .. "Content-Type: text/plain\r\n\r\n"
        .. tostring(combo_text) .. "\r\n"
        .. "--" .. boundary .. "--\r\n"

    local ok2, resp = pcall(Http.post, url, body, {
        ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
    })
    if not ok2 then return "error: " .. tostring(resp) end
    if type(resp) == "table" and resp.status and resp.status >= 200 and resp.status < 300 then
        return "ok"
    elseif type(resp) == "table" then
        return "HTTP " .. tostring(resp.status or "?")
    end
    return "unknown error"
end

--------------------------------------------------------------------------------
-- Clipboard
--------------------------------------------------------------------------------

local function copy_to_clipboard(text)
    local ok2, err = System.copy_to_clipboard(tostring(text))
    return ok2 == true
end

--------------------------------------------------------------------------------
-- Stormfront window rendering
--------------------------------------------------------------------------------

local function open_window()
    put("<closeDialog id='" .. WINDOW_ID .. "'/><openDialog type='dynamic' id='" .. WINDOW_ID .. "' title='" .. WINDOW_TITLE .. "' target='" .. WINDOW_ID .. "' scroll='manual' location='main' justify='3' height='120' resident='true'><dialogData id='" .. WINDOW_ID .. "'></dialogData></openDialog>")
end

local function close_window()
    put("<closeDialog id='" .. WINDOW_ID .. "'/>")
end

local function render_window(state, display_mode, top_n, last_combo_notice)
    local dd = state.damage_data
    local total_attacks = state.total_attacks
    local total_combos = state.total_combos
    local combo_count_sum = state.combo_count_sum
    local current_flare_streak = state.current_flare_streak
    local combo_history = state.combo_history
    local highest_combo_event = state.highest_combo_event

    local total_flares = table_values_total_size(dd)
    local overall_rate = calc_overall_rate(total_flares, total_attacks)
    local combos_only = (display_mode == "none")

    local output = "<dialogData id='" .. WINDOW_ID .. "' clear='t'>"
    local top = 0
    local left_col = 0
    local right_col = 100
    local row_h = 20

    -- Summary rows
    output = output .. "<label id='sum_l_1' value='Overall Rate' justify='left' left='" .. left_col .. "' top='" .. top .. "' />"
    output = output .. "<label id='sum_r_1' value='" .. sanitize_xml(overall_rate .. " pct") .. "' justify='left' left='" .. right_col .. "' top='" .. top .. "' />"
    top = top + row_h
    output = output .. "<label id='sum_l_2' value='Total Attacks' justify='left' left='" .. left_col .. "' top='" .. top .. "' />"
    output = output .. "<label id='sum_r_2' value='" .. sanitize_xml(fmt_int(total_attacks)) .. "' justify='left' left='" .. right_col .. "' top='" .. top .. "' />"
    top = top + row_h
    output = output .. "<label id='sum_l_3' value='Total Flares' justify='left' left='" .. left_col .. "' top='" .. top .. "' />"
    output = output .. "<label id='sum_r_3' value='" .. sanitize_xml(fmt_int(total_flares)) .. "' justify='left' left='" .. right_col .. "' top='" .. top .. "' />"
    top = top + row_h

    local combo_rate = "0.00 pct"
    if total_attacks > 0 then
        combo_rate = string.format("%.2f pct", (total_combos / total_attacks) * 100.0)
    end
    output = output .. "<label id='sum_l_4' value='Combo Rate' justify='left' left='" .. left_col .. "' top='" .. top .. "' />"
    output = output .. "<label id='sum_r_4' value='" .. sanitize_xml(combo_rate) .. "' justify='left' left='" .. right_col .. "' top='" .. top .. "' />"
    top = top + row_h
    output = output .. "<label id='sum_l_5' value='Total Combos' justify='left' left='" .. left_col .. "' top='" .. top .. "' />"
    output = output .. "<label id='sum_r_5' value='" .. sanitize_xml(fmt_int(total_combos)) .. "' justify='left' left='" .. right_col .. "' top='" .. top .. "' />"
    top = top + row_h
    output = output .. "<label id='sum_l_6' value='Flare Streak' justify='left' left='" .. left_col .. "' top='" .. top .. "' />"
    output = output .. "<label id='sum_r_6' value='" .. sanitize_xml(fmt_int(current_flare_streak)) .. "' justify='left' left='" .. right_col .. "' top='" .. top .. "' />"
    top = top + row_h

    if combos_only then
        -- High scores link
        output = output .. "<label id='highscore_sep_top' value='-----------------------------------' justify='left' left='0' top='" .. top .. "' />"
        top = top + row_h
        output = output .. "<link id='highscore_link' value='Click - High Scores' cmd=';send fwcombo highest' echo='Sending High Scores List...' justify='left' left='0' top='" .. top .. "' />"
        top = top + row_h
        output = output .. "<label id='highscore_sep_bottom' value='-----------------------------------' justify='left' left='0' top='" .. top .. "' />"
        top = top + row_h

        -- Recent combos
        local recent = {}
        local ch = combo_history or {}
        local start_idx = math.max(1, #ch - 9)
        for i = #ch, start_idx, -1 do
            recent[#recent + 1] = ch[i]
        end

        if #recent > 0 then
            output = output .. "<label id='combo_hdr' value='Click - Recent Combos' justify='left' left='0' top='" .. top .. "' />"
            top = top + 20
            for idx, evt in ipairs(recent) do
                local ts_val = tonumber(evt.timestamp) or 0
                local ts_str = ts_val > 0 and os.date("%H:%M", ts_val) or "??:??"
                local label = ts_str .. " - " .. combo_display_text(tonumber(evt.count) or 0)
                output = output .. "<link id='combo_link_" .. idx .. "' value='" .. sanitize_xml(label) .. "' cmd=';send fwcombo " .. idx .. "' echo='Copying combo " .. idx .. " to clipboard...' justify='left' left='0' top='" .. top .. "' />"
                top = top + 20
            end
        end

        output = output .. "</dialogData>"
        put(output)
        return
    end

    -- Flare stats display (full or top N)
    local ordered = {}
    for flare_type, vals in pairs(dd) do
        ordered[#ordered + 1] = { type = flare_type, count = type(vals) == "table" and #vals or 0 }
    end
    table.sort(ordered, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.type < b.type
    end)

    if display_mode == "top" and top_n and top_n > 0 then
        local trimmed = {}
        for i = 1, math.min(top_n, #ordered) do trimmed[i] = ordered[i] end
        ordered = trimmed
    end

    local total_flare_hits = table_values_total_size(dd)
    local stats = {}
    for _, entry in ipairs(ordered) do
        local ft = entry.type
        local hits = entry.count
        stats[#stats + 1] = {
            flare = ft,
            name = short_flare_name(ft),
            total = hits,
            pct = calc_rate(hits, total_flare_hits),
            fpa = calc_fpa(hits, total_attacks),
        }
    end

    local row_height = 20
    local col_left = 0
    local col_right = 260

    if #stats == 0 then
        output = output .. "<label id='empty' value='No flares tracked yet.' justify='left' left='0' top='" .. top .. "' />"
    else
        local row = 0
        for i = 1, #stats, 2 do
            for col = 0, 1 do
                local s = stats[i + col]
                if s then
                    local left = col == 0 and col_left or col_right
                    local value = s.name .. ": " .. fmt_int(s.total)
                    output = output .. "<label id='ft_" .. row .. "_" .. col .. "' value='" .. sanitize_xml(value) .. "' justify='left' left='" .. left .. "' top='" .. (top + row * row_height * 2) .. "' />"
                    local detail = s.pct .. " pct equals 1 per " .. s.fpa .. " atks"
                    output = output .. "<label id='rp_" .. row .. "_" .. col .. "' value='" .. sanitize_xml(detail) .. "' justify='left' left='" .. left .. "' top='" .. (top + row * row_height * 2 + row_height) .. "' />"
                end
            end
            row = row + 1
        end
    end

    output = output .. "</dialogData>"
    put(output)
end

--------------------------------------------------------------------------------
-- Stats and combo export formatters
--------------------------------------------------------------------------------

local function build_individual_stats_lines(damage_data, total_attacks, limit)
    local ordered = {}
    for ft, vals in pairs(damage_data) do
        ordered[#ordered + 1] = { type = ft, count = type(vals) == "table" and #vals or 0 }
    end
    table.sort(ordered, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.type < b.type
    end)

    local total_flare_hits = table_values_total_size(damage_data)
    local lines = {}
    local max_lines = (limit and limit > 0) and limit or #ordered

    for i = 1, math.min(max_lines, #ordered) do
        local e = ordered[i]
        local pct = calc_rate(e.count, total_flare_hits)
        if pct >= 0.1 then
            local name = short_flare_name(e.type)
            local fpa = calc_fpa(e.count, total_attacks)
            lines[#lines + 1] = name .. ": " .. fmt_int(e.count) .. " | " .. pct .. " pct equals 1 per " .. fpa .. " atks"
        end
    end

    if #lines == 0 then lines[#lines + 1] = "No flares tracked yet above 0.1 pct." end
    return lines
end

local function format_combo_export(combo_event)
    local lines = {}
    lines[#lines + 1] = "Flare Combo Capture"
    lines[#lines + 1] = "Time: " .. tostring(combo_event.time or "")
    lines[#lines + 1] = "Character: " .. (GameState.name or "Unknown")
    local count = tonumber(combo_event.count) or 0
    local label = combo_label_for(count)
    lines[#lines + 1] = "Combo: " .. (label and (count .. " " .. label) or tostring(count))
    local flare_names = combo_event.flare_names or {}
    lines[#lines + 1] = "Flares: " .. table.concat(flare_names, ", ")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Parsed Flare Lines:"
    local parsed = combo_event.parsed_lines or {}
    if #parsed == 0 then
        lines[#lines + 1] = "  (none)"
    else
        for _, l in ipairs(parsed) do lines[#lines + 1] = "  " .. l end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Attack Transcript:"
    local atk = combo_event.attack_lines or {}
    if #atk == 0 then
        lines[#lines + 1] = "  (none)"
    else
        for _, l in ipairs(atk) do lines[#lines + 1] = "  " .. l end
    end
    return table.concat(lines, "\n")
end

local function build_high_scores_export(state)
    local dd = state.damage_data
    local total_attacks = state.total_attacks
    local total_combos = state.total_combos
    local combo_count_sum = state.combo_count_sum
    local total_combo_damage = state.total_combo_damage
    local highest_as = state.highest_as
    local highest_cs = state.highest_cs
    local highest_flare_streak = state.highest_flare_streak
    local current_flare_streak = state.current_flare_streak
    local signature_combo_counts = state.signature_combo_counts or {}
    local combo_history = state.combo_history or {}
    local highest_combo_event = state.highest_combo_event or {}

    local lines = {}
    lines[#lines + 1] = "Flarewindow High Scores List"
    lines[#lines + 1] = "Generated: " .. os.date("%Y-%m-%d %H:%M:%S %Z")
    lines[#lines + 1] = "Character: " .. (GameState.name or "Unknown")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Highest AS: " .. fmt_int(highest_as)
    lines[#lines + 1] = "Highest CS: " .. fmt_int(highest_cs)
    lines[#lines + 1] = ""

    -- Most Valuable Flare
    local mvf_type, mvf_hits = nil, 0
    for k, v in pairs(dd) do
        local sz = type(v) == "table" and #v or 0
        if sz > mvf_hits then mvf_type = k; mvf_hits = sz end
    end
    local mvf_name = mvf_type and short_flare_name(mvf_type) or "N/A"
    lines[#lines + 1] = "Most Valuable Flare (MVF): " .. mvf_name .. " (" .. fmt_int(mvf_hits) .. " procs)"

    -- Combo Level
    local combo_level = total_combos > 0 and (combo_count_sum / total_combos) or 0.0
    lines[#lines + 1] = "Combo Level: " .. string.format("%.2f", combo_level)
    local avg_combo_damage = total_combos > 0 and (total_combo_damage / total_combos) or 0.0
    lines[#lines + 1] = "Average Combo Damage: " .. string.format("%.2f", avg_combo_damage)
    lines[#lines + 1] = "Best Flare Streak: " .. fmt_int(highest_flare_streak)

    -- Most Common Combo
    if #combo_history > 0 then
        local mode_counts = {}
        for _, evt in ipairs(combo_history) do
            local c = tonumber(evt.count) or 0
            mode_counts[c] = (mode_counts[c] or 0) + 1
        end
        local mode_combo, mode_freq = 0, 0
        for c, freq in pairs(mode_counts) do
            if freq > mode_freq or (freq == mode_freq and c > mode_combo) then
                mode_combo = c; mode_freq = freq
            end
        end
        local mlabel = combo_label_for(mode_combo)
        local combo_text = mlabel and (mode_combo .. " " .. mlabel) or tostring(mode_combo)
        lines[#lines + 1] = "Most Common Combo: " .. combo_text .. " (" .. fmt_int(mode_freq) .. " times)"
    else
        lines[#lines + 1] = "Most Common Combo: N/A"
    end

    -- Top Damage Flare
    local top_dmg_type, top_dmg_sum = nil, 0
    for k, v in pairs(dd) do
        if type(v) == "table" then
            local sum = 0
            for _, val in ipairs(v) do
                if type(val) == "number" then sum = sum + val end
            end
            if sum > top_dmg_sum then top_dmg_type = k; top_dmg_sum = sum end
        end
    end
    if top_dmg_type then
        lines[#lines + 1] = "Top Damage Flare: " .. short_flare_name(top_dmg_type) .. " (" .. fmt_int(top_dmg_sum) .. " total damage)"
    else
        lines[#lines + 1] = "Top Damage Flare: N/A"
    end

    -- Highest Single-Hit
    local hs_type, hs_val = nil, 0
    for k, v in pairs(dd) do
        if type(v) == "table" then
            for _, val in ipairs(v) do
                if type(val) == "number" and val > hs_val then
                    hs_type = k; hs_val = val
                end
            end
        end
    end
    if hs_type then
        lines[#lines + 1] = "Highest Single-Hit Flare: " .. short_flare_name(hs_type) .. " (" .. fmt_int(hs_val) .. ")"
    else
        lines[#lines + 1] = "Highest Single-Hit Flare: N/A"
    end

    -- Signature Combo
    if type(signature_combo_counts) == "table" and count_table(signature_combo_counts) > 0 then
        local sig, sig_count = nil, 0
        for k, v in pairs(signature_combo_counts) do
            local vn = tonumber(v) or 0
            if vn > sig_count then sig = k; sig_count = vn end
        end
        lines[#lines + 1] = "Signature Combo: " .. tostring(sig) .. " (" .. fmt_int(sig_count) .. " times)"
    else
        lines[#lines + 1] = "Signature Combo: N/A"
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "--------------------------------"
    lines[#lines + 1] = "Highest Combo (Detailed)"
    lines[#lines + 1] = "--------------------------------"
    if type(highest_combo_event) == "table" and (tonumber(highest_combo_event.count) or 0) > 0 then
        lines[#lines + 1] = format_combo_export(highest_combo_event)
    else
        lines[#lines + 1] = "(no combo recorded)"
    end
    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------

local p_path = persist_path()
local startup = parse_startup_options()
local action = startup.action
local display_mode = startup.display_mode
local top_n = startup.top_n

-- Handle startup actions
if action == "reset" then
    save_persisted(p_path, initial_data())
    echo("flarewindow: persisted data reset on startup.")
elseif action == "delete" then
    if File.exists(p_path) then File.remove(p_path) end
    echo("flarewindow: persisted data file deleted on startup.")
elseif action == "import" then
    local existing = load_persisted(p_path)
    local imported, msg = import_flaretracker(existing)
    echo(msg)
    if imported then
        save_persisted(p_path, imported)
    end
end

if #startup.unknown > 0 then
    echo("flarewindow: unknown startup option(s): " .. table.concat(startup.unknown, ", "))
    echo("flarewindow: valid options include import, reset, delete, none, full, top#")
end

local mode_label
if display_mode == "none" then
    mode_label = "COMBOS ONLY"
elseif display_mode == "full" then
    mode_label = "FLARES ONLY"
elseif display_mode == "top" then
    mode_label = "FLARES ONLY (TOP " .. tostring(top_n) .. ")"
else
    mode_label = "COMBOS ONLY"
end
echo("flarewindow: display mode " .. mode_label .. ".")
if action then echo("flarewindow: startup action " .. action .. ".") end
if discord_enabled() then
    echo("flarewindow: Discord combo send ON.")
else
    echo("flarewindow: Discord combo send OFF.")
    echo("flarewindow: setup -> ;send fwdiscord set https://discord.com/api/webhooks/ID/TOKEN")
end

-- Load persisted data into state table
local persisted = load_persisted(p_path)
local state = {
    damage_data            = {},
    total_attacks          = persisted.total_attacks or 0,
    highest_as             = persisted.highest_as or 0,
    highest_cs             = persisted.highest_cs or 0,
    total_combos           = persisted.total_combos or 0,
    combo_count_sum        = persisted.combo_count_sum or 0,
    total_combo_damage     = persisted.total_combo_damage or 0,
    current_flare_streak   = persisted.current_flare_streak or 0,
    highest_flare_streak   = persisted.highest_flare_streak or 0,
    signature_combo_counts = type(persisted.signature_combo_counts) == "table" and persisted.signature_combo_counts or {},
    highest_flare_combo    = persisted.highest_flare_combo or 0,
    combo_history          = type(persisted.combo_history) == "table" and persisted.combo_history or {},
    highest_combo_event    = type(persisted.highest_combo_event) == "table" and persisted.highest_combo_event or {},
}

-- Restore damage_data (keys may have been stringified by JSON)
if type(persisted.damage_data) == "table" then
    for k, v in pairs(persisted.damage_data) do
        state.damage_data[tostring(k)] = type(v) == "table" and v or {}
    end
end

-- Reconstruct derived fields from combo_history if needed
if state.total_combos <= 0 and #state.combo_history > 0 then
    state.total_combos = #state.combo_history
    local sum = 0
    for _, evt in ipairs(state.combo_history) do sum = sum + (tonumber(evt.count) or 0) end
    state.combo_count_sum = sum
end
if state.total_combo_damage <= 0 and #state.combo_history > 0 then
    local sum = 0
    for _, evt in ipairs(state.combo_history) do sum = sum + (tonumber(evt.combo_damage) or 0) end
    state.total_combo_damage = sum
end
if count_table(state.signature_combo_counts) == 0 and #state.combo_history > 0 then
    for _, evt in ipairs(state.combo_history) do
        local sig = evt.signature or ""
        if sig ~= "" then
            state.signature_combo_counts[sig] = (state.signature_combo_counts[sig] or 0) + 1
        end
    end
end

-- Attack tracking state
local attack_open = false
local cur_flare_count = 0
local cur_combo_damage = 0
local cur_attack_lines = {}
local cur_parsed = {}
local cur_flare_names = {}
local flare_events = {}
local claim_active = claim_owned_room()
local pre_attack_context = {}

-- Rendering/saving state
local dirty = true
local last_render = 0
local last_save_at = os.time()
local event_counter = 0
local last_combo_notice = nil

--------------------------------------------------------------------------------
-- Combo copy handler
--------------------------------------------------------------------------------

local function handle_combo_copy(index_text)
    local evt = nil
    if index_text:lower() == "highest" then
        if type(state.highest_combo_event) == "table" and (tonumber(state.highest_combo_event.count) or 0) > 0 then
            evt = state.highest_combo_event
        end
        if not evt then
            echo("flarewindow: highest combo record not found.")
            return
        end
    else
        local idx = tonumber(index_text)
        if not idx or idx <= 0 then
            echo("flarewindow: invalid combo index.")
            return
        end
        local ch = state.combo_history
        local recent = {}
        local start_idx = math.max(1, #ch - 9)
        for i = #ch, start_idx, -1 do recent[#recent + 1] = ch[i] end
        evt = recent[idx]
        if not evt then
            echo("flarewindow: combo index " .. idx .. " not found.")
            return
        end
    end

    local combo_text
    if index_text:lower() == "highest" then
        combo_text = build_high_scores_export(state)
    else
        combo_text = format_combo_export(evt)
    end

    local copied = copy_to_clipboard(combo_text)
    local discord_result = send_combo_to_discord(combo_text, evt)
    local ts_val = tonumber(evt.timestamp) or 0
    local ts_str = ts_val > 0 and os.date("%Y-%m-%d %H:%M:%S %Z", ts_val) or (evt.time or "")
    local clip_msg = copied and "copied to clipboard" or "available in json (clipboard copy failed)"
    local discord_msg
    if discord_result == "ok" then
        discord_msg = "sent to Discord"
    elseif discord_result == "not_configured" then
        discord_msg = "Discord not configured"
    else
        discord_msg = "Discord send failed (" .. tostring(discord_result) .. ")"
    end
    echo("flarewindow: combo from " .. ts_str .. " " .. clip_msg .. "; " .. discord_msg .. ".")
end

--------------------------------------------------------------------------------
-- Finalize attack (resolve combo on Roundtime)
--------------------------------------------------------------------------------

local function finalize_attack(reason)
    if not attack_open and cur_flare_count <= 0 then
        flare_events = {}
        return
    end

    if cur_flare_count > 0 then
        state.current_flare_streak = state.current_flare_streak + 1
        if state.current_flare_streak > state.highest_flare_streak then
            state.highest_flare_streak = state.current_flare_streak
        end
    else
        state.current_flare_streak = 0
    end

    if cur_flare_count >= MIN_COMBO_CAPTURE then
        -- Build unique flare names list
        local seen_names = {}
        local unique_names = {}
        for _, name in ipairs(cur_flare_names) do
            if not seen_names[name] then
                seen_names[name] = true
                unique_names[#unique_names + 1] = name
            end
        end
        table.sort(unique_names)
        local combo_signature = table.concat(unique_names, " + ")

        local combo_event = {
            time = os.date("%Y-%m-%d %H:%M:%S %Z"),
            timestamp = os.time(),
            count = cur_flare_count,
            combo_damage = cur_combo_damage,
            signature = combo_signature,
            reason = reason,
            flare_names = unique_names,
            parsed_lines = {},
            attack_lines = {},
        }
        for _, v in ipairs(cur_parsed) do combo_event.parsed_lines[#combo_event.parsed_lines + 1] = v end
        for _, v in ipairs(cur_attack_lines) do combo_event.attack_lines[#combo_event.attack_lines + 1] = v end

        state.combo_history[#state.combo_history + 1] = combo_event
        while #state.combo_history > MAX_COMBOS do table.remove(state.combo_history, 1) end

        state.total_combos = state.total_combos + 1
        state.combo_count_sum = state.combo_count_sum + cur_flare_count
        state.total_combo_damage = state.total_combo_damage + cur_combo_damage
        state.signature_combo_counts[combo_signature] = (state.signature_combo_counts[combo_signature] or 0) + 1

        last_combo_notice = os.date("%Y-%m-%d %H:%M:%S %Z") .. " - " .. combo_display_text(cur_flare_count) .. " captured. Click recent combo link to copy."
        echo("flarewindow: captured " .. combo_display_text(cur_flare_count) .. ".")
        event_counter = event_counter + 1
        dirty = true
    end

    state.highest_flare_combo = math.max(state.highest_flare_combo, cur_flare_count)
    if cur_flare_count >= MIN_COMBO_CAPTURE and cur_flare_count >= state.highest_flare_combo then
        local unique_names2 = {}
        local seen2 = {}
        for _, name in ipairs(cur_flare_names) do
            if not seen2[name] then
                seen2[name] = true
                unique_names2[#unique_names2 + 1] = name
            end
        end
        state.highest_combo_event = {
            time = os.date("%Y-%m-%d %H:%M:%S %Z"),
            timestamp = os.time(),
            count = cur_flare_count,
            reason = reason,
            flare_names = unique_names2,
            parsed_lines = {},
            attack_lines = {},
        }
        for _, v in ipairs(cur_parsed) do state.highest_combo_event.parsed_lines[#state.highest_combo_event.parsed_lines + 1] = v end
        for _, v in ipairs(cur_attack_lines) do state.highest_combo_event.attack_lines[#state.highest_combo_event.attack_lines + 1] = v end
    end

    attack_open = false
    cur_flare_count = 0
    cur_attack_lines = {}
    cur_parsed = {}
    cur_flare_names = {}
    cur_combo_damage = 0
    flare_events = {}
    dirty = true
end

--------------------------------------------------------------------------------
-- Buffer attack line helper
--------------------------------------------------------------------------------

local function buffer_attack_line(text)
    if not text or text == "" then return end
    if #cur_attack_lines > 0 and cur_attack_lines[#cur_attack_lines] == text then return end
    cur_attack_lines[#cur_attack_lines + 1] = text
    while #cur_attack_lines > MAX_ATTACK_LINES do table.remove(cur_attack_lines, 1) end
end

--------------------------------------------------------------------------------
-- Open window and do initial render
--------------------------------------------------------------------------------

open_window()
render_window(state, display_mode, top_n, last_combo_notice)

before_dying(function()
    save_persisted(p_path, state)
    close_window()
end)

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

local pending_line = nil

while true do
    local line = pending_line or get()
    pending_line = nil
    local stripped = (line or ""):match("^%s*(.-)%s*$") or ""
    local now = os.time()

    -- ── Runtime send commands ──────────────────────────────────────────

    -- fwstats [topN]
    local stats_match = stripped:match("^fwstats%s*top%s*(%d+)$") or stripped:match("^fwstats%s+(%d+)$")
    if stripped == "fwstats" or stats_match then
        local limit = stats_match and tonumber(stats_match) or nil
        local lines = build_individual_stats_lines(state.damage_data, state.total_attacks, limit)
        local scope = (limit and limit > 0) and ("Top " .. limit) or "All"
        echo("flarewindow: " .. scope .. " Individual Flare Stats")
        for _, l in ipairs(lines) do echo("  " .. l) end
        goto continue
    end

    -- fwcombo reset
    if stripped:lower() == "fwcombo reset" then
        state.highest_flare_combo = 0
        state.highest_combo_event = {}
        last_combo_notice = nil
        last_save_at, event_counter = save_if_needed(p_path, state, last_save_at, event_counter, true)
        echo("flarewindow: highest combo record reset.")
        dirty = true
        goto continue
    end

    -- fwcombo [N|highest]
    local combo_match = stripped:match("^fwcombo%s+(%S+)$")
    if stripped == "fwcombo" or combo_match then
        local target = combo_match or "1"
        handle_combo_copy(target)
        goto continue
    end

    -- fwdiscord off
    if stripped:lower() == "fwdiscord off" then
        set_discord_webhook("")
        echo("flarewindow: Discord webhook cleared (OFF).")
        goto continue
    end

    -- fwdiscord status (or bare fwdiscord)
    if stripped:lower() == "fwdiscord" or stripped:lower() == "fwdiscord status" then
        local url = discord_webhook_url()
        if url == "" then
            echo("flarewindow: Discord status OFF.")
            echo("flarewindow: set with -> ;send fwdiscord set https://discord.com/api/webhooks/ID/TOKEN")
        else
            local masked = url:gsub("(https?://discord[a-z]*%.com/api/webhooks/%d+/).+", "%1[hidden]")
            echo("flarewindow: Discord status ON (" .. masked .. ").")
        end
        goto continue
    end

    -- fwdiscord set (no URL)
    if stripped:lower() == "fwdiscord set" then
        echo("flarewindow: missing webhook URL.")
        echo("flarewindow: example -> ;send fwdiscord set https://discord.com/api/webhooks/ID/TOKEN")
        goto continue
    end

    -- fwdiscord set <URL>
    local discord_set_url = stripped:match("^fwdiscord%s+set%s+(.+)$")
    if discord_set_url then
        local candidate = discord_set_url:match("^%s*(.-)%s*$") or ""
        -- Extract from parentheses if present
        local paren = candidate:match("%(https?://discord[a-z]*%.com/api/webhooks/[^%)%s]+%)")
        if paren then candidate = paren:sub(2, -2) end
        set_discord_webhook(candidate)
        if discord_enabled() then
            echo("flarewindow: Discord webhook saved (ON).")
        else
            echo("flarewindow: Discord webhook not recognized. Use full webhook URL.")
        end
        goto continue
    end

    -- ── Game line processing ───────────────────────────────────────────

    -- Buffer context lines
    if claim_active and attack_open and stripped ~= "" then
        buffer_attack_line(stripped)
    elseif claim_active and not attack_open and stripped ~= "" then
        pre_attack_context[#pre_attack_context + 1] = { time = os.clock(), text = stripped }
        local cutoff = os.clock() - PRE_ATTACK_CONTEXT_SECS
        while #pre_attack_context > 0 and pre_attack_context[1].time < cutoff do
            table.remove(pre_attack_context, 1)
        end
    end

    -- Check claim status change
    local new_claim = claim_owned_room()
    if new_claim ~= claim_active then
        claim_active = new_claim
        if not claim_active then
            attack_open = false
            cur_flare_count = 0
            cur_combo_damage = 0
            cur_attack_lines = {}
            cur_parsed = {}
            cur_flare_names = {}
            flare_events = {}
            pre_attack_context = {}
        end
    end

    if claim_active then
        -- Parse AS/CS
        local as_val, cs_val = parse_as_cs(line)
        if as_val and as_val > state.highest_as then
            state.highest_as = as_val
            event_counter = event_counter + 1
            dirty = true
        end
        if cs_val and cs_val > state.highest_cs then
            state.highest_cs = cs_val
            event_counter = event_counter + 1
            dirty = true
        end

        -- Check for attack pattern
        local is_attack = false
        for _, pattern in pairs(ATTACKS) do
            if pattern:test(line) then
                is_attack = true
                break
            end
        end

        if is_attack then
            state.total_attacks = state.total_attacks + 1
            if not attack_open then
                attack_open = true
                cur_flare_count = 0
                cur_combo_damage = 0
                cur_attack_lines = {}
                for _, ctx in ipairs(pre_attack_context) do
                    cur_attack_lines[#cur_attack_lines + 1] = ctx.text
                end
                cur_parsed = {}
                cur_flare_names = {}
                buffer_attack_line(stripped)
                pre_attack_context = {}
            end
            event_counter = event_counter + 1
            dirty = true
        end

        -- Check for flare patterns
        for flare_type, pattern in pairs(combined_patterns) do
            if not pattern:test(line) then goto next_pattern end

            -- Skip attack patterns in flare parsing pass
            if ATTACKS[flare_type] then goto next_pattern end

            -- Open attack context if not already open (flare before explicit attack)
            if not attack_open then
                attack_open = true
                cur_flare_count = 0
                cur_combo_damage = 0
                cur_attack_lines = {}
                for _, ctx in ipairs(pre_attack_context) do
                    cur_attack_lines[#cur_attack_lines + 1] = ctx.text
                end
                cur_parsed = {}
                cur_flare_names = {}
                pre_attack_context = {}
            end

            -- Record flare event for combo tracking
            flare_events[#flare_events + 1] = {
                type = flare_type,
                time = os.clock(),
                ignored = combo_ignored(flare_type),
                damage = 0,
                flare_name = flare_type:gsub("_", " "),
                parsed = flare_type .. ": no damage captured",
            }

            local is_damaging = DMG[flare_type] ~= nil
            local is_nodmg = NODMG[flare_type] ~= nil
            local damage_lines = {}

            -- Non-damaging flare: gate on Symbol of Dreams
            if is_nodmg and not Effects.Buffs.active("Symbol of Dreams") then
                if not state.damage_data[flare_type] then state.damage_data[flare_type] = {} end
                state.damage_data[flare_type][#state.damage_data[flare_type] + 1] = Json.null
                event_counter = event_counter + 1
                dirty = true
                break
            end

            -- Check for inline damage on this line
            local caps = re_damage_pts:captures(line)
            if caps and caps[1] then
                damage_lines[#damage_lines + 1] = tonumber(caps[1])
            else
                local add_caps = re_additional:captures(line)
                if add_caps and add_caps[1] then
                    damage_lines[#damage_lines + 1] = tonumber(add_caps[1])
                    -- SanguineSacrifice special handling
                    local ss_type = "SanguineSacrifice"
                    if not state.damage_data[ss_type] then state.damage_data[ss_type] = {} end
                    state.damage_data[ss_type][#state.damage_data[ss_type] + 1] = tonumber(add_caps[1])
                    flare_events[#flare_events].type = ss_type
                    flare_events[#flare_events].damage = tonumber(add_caps[1])
                    flare_events[#flare_events].flare_name = "SanguineSacrifice"
                    flare_events[#flare_events].parsed = ss_type .. ": damage " .. add_caps[1]
                    event_counter = event_counter + 1
                    dirty = true
                    goto next_pattern
                end
            end

            -- Lookahead for damage on subsequent lines
            if is_damaging then
                local max_lookahead = needs_extended_lookahead(flare_type) and 5 or 3
                for _ = 1, max_lookahead do
                    local dmg_line = get()
                    local dmg_stripped = (dmg_line or ""):match("^%s*(.-)%s*$") or ""
                    if claim_active and attack_open then buffer_attack_line(dmg_stripped) end

                    -- Check if this line is a new flare/attack pattern
                    local is_new = false
                    for _, pat in pairs(combined_patterns) do
                        if pat:test(dmg_line) then is_new = true; break end
                    end
                    if is_new then
                        pending_line = dmg_line
                        break
                    end

                    local dcaps = re_damage_pts:captures(dmg_line)
                    if dcaps and dcaps[1] then
                        damage_lines[#damage_lines + 1] = tonumber(dcaps[1])
                        if not needs_extended_lookahead(flare_type) then break end
                    elseif re_stop_lookahead:test(dmg_line) then
                        break
                    else
                        local mcaps = re_mana_gain:captures(dmg_line)
                        if mcaps then
                            local mana_val = tonumber(mcaps[1]) or tonumber(mcaps[2])
                            if mana_val then
                                damage_lines[#damage_lines + 1] = mana_val
                                break
                            end
                        end
                    end
                end
            end

            -- Record flare with damage
            if not state.damage_data[flare_type] then state.damage_data[flare_type] = {} end
            if #damage_lines > 0 then
                local total_dmg = 0
                for _, d in ipairs(damage_lines) do total_dmg = total_dmg + d end
                state.damage_data[flare_type][#state.damage_data[flare_type] + 1] = total_dmg
                flare_events[#flare_events].damage = total_dmg
                flare_events[#flare_events].parsed = flare_type .. ": damage " .. total_dmg
            else
                state.damage_data[flare_type][#state.damage_data[flare_type] + 1] = Json.null
                flare_events[#flare_events].parsed = flare_type .. ": no damage captured"
            end

            event_counter = event_counter + 1
            dirty = true
            break

            ::next_pattern::
        end

        -- Roundtime: finalize attack and resolve combo
        if re_roundtime:test(line) then
            local current_clock = os.clock()
            local recent_flares = {}
            for _, event in ipairs(flare_events) do
                if (current_clock - event.time) <= COMBO_TIME_WINDOW and not event.ignored then
                    recent_flares[#recent_flares + 1] = event
                end
            end
            cur_flare_count = #recent_flares
            cur_combo_damage = 0
            cur_flare_names = {}
            cur_parsed = {}
            for _, e in ipairs(recent_flares) do
                cur_combo_damage = cur_combo_damage + (type(e.damage) == "number" and e.damage or 0)
                cur_flare_names[#cur_flare_names + 1] = e.flare_name
                cur_parsed[#cur_parsed + 1] = e.parsed
            end
            finalize_attack("roundtime")
        end
    end

    -- Throttled render
    if dirty and (os.clock() - last_render >= RENDER_THROTTLE) then
        render_window(state, display_mode, top_n, last_combo_notice)
        dirty = false
        last_render = os.clock()
    end

    -- Periodic save
    last_save_at, event_counter = save_if_needed(p_path, state, last_save_at, event_counter)

    ::continue::
end
