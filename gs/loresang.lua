--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: loresang
--- version: 2.0.0
--- author: Kyrandos
--- contributors: EduBarbarian
--- game: gs
--- description: Bard loresinging utility — single item (right hand) or bulk
---   container-to-container loresinging with custom songs, mana checks, value
---   threshold alerts, room announcements, CSV export, Discord webhook alerts,
---   and GUI setup via Gui.* API.
--- tags: utility,economy,bard,loresong,loresing,csv,export
---
--- Changelog (from Lich5 loresang.lic v1.2.1):
---   v2.0.0 (2026-03-18): Full Revenant rewrite — no GTK/Ruby deps, uses
---     Revenant primitives (fput, waitrt, reget, CharSettings, Gui.*, Json, File).
---     Discord webhook via lib/webhooks. CSV export via File.write.
---     HTML report replaced with CSV export + webhook.
---   v1.2.1 (Lich5): Updated HTML output directory
---   v1.2.0 (Lich5): HTML report output with localStorage pinning
---   v1.1.0 (Lich5): Detect weak song / insufficient power, mana recovery
---   v1.0.x (Lich5): Initial release by Kyrandos
---
--- Usage:
---   ;loresang               - Sing all items from Sing Container to Sung Container
---   ;loresang hand           - Sing item in right hand until complete
---   ;loresang setup          - Open configuration GUI window
---   ;loresang log            - Show CSV log path and summary
---   ;loresang help           - Show this help

local VERSION = "2.0.0"

--------------------------------------------------------------------------------
-- Settings (CharSettings-backed, JSON-serialized hash)
--------------------------------------------------------------------------------

local DEFAULTS = {
    use_guildspeak       = false,
    announce_successes   = false,
    max_cycles           = 10,
    verse1               = "",
    verse2               = "",
    low_mana_enabled     = false,
    low_mana_text        = "",
    low_mana_pct         = 15,
    rt_skew_enabled      = false,
    rt_skew              = "0",
    value_alert_enabled  = false,
    value_threshold      = "",
    sing_container       = "",
    sung_container       = "",
    tag_clothing         = false,
    tag_weapons          = false,
    tag_armor            = false,
    tag_jewelry          = false,
    tag_containers       = false,
    tag_magic            = false,
    csv_export_enabled   = false,
    webhook_enabled      = false,
    webhook_name         = "",
}

local function load_settings()
    local raw = CharSettings.loresang
    if raw and raw ~= "" then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then
            -- Merge with defaults
            for k, v in pairs(DEFAULTS) do
                if data[k] == nil then data[k] = v end
            end
            return data
        end
    end
    -- Return a copy of defaults
    local s = {}
    for k, v in pairs(DEFAULTS) do s[k] = v end
    return s
end

local function save_settings(settings)
    CharSettings.loresang = Json.encode(settings)
end

local settings = load_settings()

local VERSE1_DEFAULT = "that I hold in my hand; Tell your secrets and don't be bland;Share your power and make it grand; I seek the knowledge lost in the sand"
local VERSE2_DEFAULT = "of power that I hold;Speak of secrets left untold; Show me now for I am bold;Spare no detail don't leave me cold"

local function get_verse1()
    local v = settings.verse1 or ""
    if v:match("^%s*$") then return VERSE1_DEFAULT end
    return v
end

local function get_verse2()
    local v = settings.verse2 or ""
    if v:match("^%s*$") then return VERSE2_DEFAULT end
    return v
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function msg(text)
    respond("[Loresang] " .. text)
end

local function checkmana()
    return GameState.mana or 0
end

local function maxmana()
    return GameState.max_mana or 100
end

local function clear_hands()
    local rh = GameObj.right_hand()
    if rh and rh.name and rh.name ~= "Empty" then
        local rtype = rh.type or ""
        if string.find(string.lower(rtype), "shield") then
            fput("store shield")
        elseif string.find(string.lower(rtype), "weapon") then
            fput("store weapon")
        else
            fput("stow right")
        end
        pause(0.5)
    end

    local lh = GameObj.left_hand()
    if lh and lh.name and lh.name ~= "Empty" then
        local ltype = lh.type or ""
        if string.find(string.lower(ltype), "shield") then
            fput("store shield")
        elseif string.find(string.lower(ltype), "weapon") then
            fput("store weapon")
        else
            fput("stow left")
        end
        pause(0.5)
    end
end

local function format_silver(value)
    local s = tostring(value)
    -- Insert commas
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        if count > 0 and count % 3 == 0 then
            result = "," .. result
        end
        result = s:sub(i, i) .. result
        count = count + 1
    end
    return result
end

local function parse_item_value(recall_text)
    if not recall_text then return 0 end
    local value_str = string.match(recall_text, "estimated to be worth about ([%d,]+) silvers")
    if value_str then
        return tonumber((string.gsub(value_str, ",", ""))) or 0
    end
    return 0
end

local function already_unlocked(recall_text)
    if not recall_text then return false end
    local text = string.lower(recall_text)

    -- Not unlocked indicators
    if string.find(text, "must reveal the entire loresong", 1, true) then return false end
    if string.find(text, "you have not yet unlocked", 1, true) then return false end
    if string.find(text, "needs to be unlocked", 1, true) then return false end

    -- Unlocked indicators
    return string.find(text, "permanently unlocked", 1, true) ~= nil
        or string.find(text, "has a permanently unlocked loresong", 1, true) ~= nil
        or string.find(text, "harmonies reveal nothing", 1, true) ~= nil
        or string.find(text, "the loresong is complete", 1, true) ~= nil
        or string.find(text, "nothing more to learn", 1, true) ~= nil
        or string.find(text, "already learned", 1, true) ~= nil
        or string.find(text, "fully unlocked", 1, true) ~= nil
end

local function matches_filter(item)
    local item_type = string.lower(item.type or "")
    local should_sing = false
    if settings.tag_clothing and string.find(item_type, "clothing") then should_sing = true end
    if settings.tag_weapons and string.find(item_type, "weapon") then should_sing = true end
    if settings.tag_armor and string.find(item_type, "armor") then should_sing = true end
    if settings.tag_jewelry and string.find(item_type, "jewelry") then should_sing = true end
    if settings.tag_containers and string.find(item_type, "container") then should_sing = true end
    if settings.tag_magic and string.find(item_type, "magic") then should_sing = true end
    return should_sing
end

--------------------------------------------------------------------------------
-- Webhook support (optional, via lib/webhooks)
--------------------------------------------------------------------------------

local webhooks = nil
local function try_load_webhooks()
    local ok2, mod = pcall(require, "lib/webhooks")
    if ok2 then webhooks = mod end
end
try_load_webhooks()

local function send_webhook(message, event)
    if not settings.webhook_enabled or not webhooks then return end
    local name = settings.webhook_name
    if name and name ~= "" then
        webhooks.send_to(name, message, event or "loresang")
    else
        webhooks.send(message, event or "loresang")
    end
end

--------------------------------------------------------------------------------
-- CSV Export
--------------------------------------------------------------------------------

local function csv_log_path()
    File.mkdir("data/loresang")
    return "data/loresang/" .. string.lower(GameState.name or "character") .. "_loresang.csv"
end

local function csv_escape(str)
    if not str then return "" end
    str = tostring(str)
    if string.find(str, '[,"\n\r]') then
        return '"' .. string.gsub(str, '"', '""') .. '"'
    end
    return str
end

local function append_csv_row(item_name, noun, status, value, recall_text)
    local path = csv_log_path()
    local needs_header = not File.exists(path)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")

    local row = table.concat({
        csv_escape(timestamp),
        csv_escape(item_name),
        csv_escape(noun),
        csv_escape(status),
        csv_escape(value and tostring(value) or ""),
        csv_escape(recall_text or ""),
    }, ",")

    local content = ""
    if needs_header then
        content = "Timestamp,Name,Noun,Status,Value,Recall\n"
    end
    content = content .. row .. "\n"

    if File.exists(path) then
        local existing = File.read(path) or ""
        File.write(path, existing .. content)
    else
        File.write(path, content)
    end
end

--------------------------------------------------------------------------------
-- Mana management
--------------------------------------------------------------------------------

local function wait_for_mana()
    if checkmana() >= 5 then return end

    msg("Mana is below 5. Pausing until mana reaches 20...")
    local last_feedback = os.time()

    while checkmana() < 20 do
        if os.time() - last_feedback >= 120 then
            msg("Still waiting for mana... Current mana: " .. checkmana() .. "/20")
            last_feedback = os.time()
        end
        pause(5)
    end
    msg("Mana restored to " .. checkmana() .. ". Resuming...")
end

local function wait_for_mana_recovery()
    local target = math.max(math.floor(maxmana() * 0.1), 45)
    msg("Waiting for mana recovery (need " .. target .. "/" .. maxmana() .. ")...")
    local last_feedback = os.time()

    while checkmana() < target do
        if os.time() - last_feedback >= 30 then
            msg("Still waiting for mana... " .. checkmana() .. "/" .. maxmana() .. " (need " .. target .. ")")
            last_feedback = os.time()
        end
        pause(3)
    end
    msg("Mana at " .. checkmana() .. "/" .. maxmana() .. ". Resuming loresong...")
end

--------------------------------------------------------------------------------
-- Core singing logic
--------------------------------------------------------------------------------

local high_value_items = {}
local report_items = {}
local last_recall_text = nil
local last_item_value = nil

local function check_item_value(noun, item_name, items_remaining)
    fput("recall " .. noun)
    waitrt()
    pause(0.8)

    local recall_lines = reget(35) or {}
    -- Find the start of recall text
    local start_idx = nil
    for i = #recall_lines, 1, -1 do
        if string.find(recall_lines[i], "As you recall your song") then
            start_idx = i + 1
            break
        end
    end

    local recall_text = ""
    if start_idx then
        local parts = {}
        for i = start_idx, #recall_lines do
            table.insert(parts, recall_lines[i])
        end
        recall_text = table.concat(parts, "\n")
    else
        recall_text = table.concat(recall_lines, "\n")
    end

    last_recall_text = recall_text
    local raw_val = parse_item_value(recall_text)
    last_item_value = raw_val > 0 and raw_val or nil

    local threshold_str = settings.value_threshold or ""
    threshold_str = string.gsub(threshold_str, ",", "")
    local threshold = tonumber(threshold_str)

    if settings.value_alert_enabled and threshold and raw_val >= threshold then
        local formatted = format_silver(raw_val)
        local message = "Item " .. item_name .. " worth " .. formatted .. " silvers - over your threshold!"
        if items_remaining then
            message = message .. " " .. items_remaining .. " items to go!"
        end
        msg(message)

        if settings.announce_successes then
            fput("speak common")
            pause(0.5)
            fput("say " .. message)
            pause(0.5)
        end

        table.insert(high_value_items, { name = item_name, value = raw_val })

        -- Send webhook alert
        send_webhook(message, "high_value_item")
    end
end

local function sing_item(item_name, noun, items_remaining)
    msg("Starting loresong for " .. noun .. "...")

    -- Low mana callout
    if settings.low_mana_enabled and settings.low_mana_text ~= "" then
        local mana_pct = (checkmana() / maxmana()) * 100
        if mana_pct < (settings.low_mana_pct or 15) then
            fput("speak common")
            pause(0.5)
            fput("say " .. settings.low_mana_text)
            pause(0.5)
            if settings.use_guildspeak then
                fput("speak bard")
                pause(0.5)
            end
            msg("Low mana alert triggered (" .. string.format("%.1f", mana_pct) .. "% < " .. settings.low_mana_pct .. "%).")
        end
    end

    if settings.use_guildspeak then
        fput("speak bard")
        pause(1)
    end

    local rt_skew = 0
    if settings.rt_skew_enabled then
        rt_skew = tonumber(settings.rt_skew) or 0
    end

    local cycle_count = 0
    local completed = false
    local max_cycles = settings.max_cycles or 10

    while true do
        wait_for_mana()

        cycle_count = cycle_count + 1
        msg("Cycle " .. cycle_count .. "/" .. max_cycles .. " - singing...")
        if items_remaining then
            msg("Progress: Sing Container Items Left: " .. items_remaining)
        end

        if cycle_count > max_cycles then
            msg("Max cycles reached - putting item back.")
            break
        end

        local rh = GameObj.right_hand()
        if not rh or rh.name == "Empty" then
            msg("Item no longer in right hand - aborting this item.")
            break
        end

        -- Verse 1
        local actual_verse1 = string.gsub(get_verse1(), "#{item%.noun}", noun)
        fput("loresing " .. noun .. " " .. actual_verse1)
        pause(1)

        local response = reget(12) or {}
        local line = string.lower(table.concat(response, " "))

        if string.find(line, "permanently unlocked")
            or string.find(line, "reached the end of .* song")
            or string.find(line, "learn nothing new")
            or string.find(line, "nothing new about") then
            completed = true
            local rt_str = string.match(line, "roundtime: (%d+)")
            local rt_sec = tonumber(rt_str) or 5
            pause(math.max(rt_sec + 1 + rt_skew, 0))
            check_item_value(noun, item_name, items_remaining)
            msg("Loresong Completed, " .. noun .. " fully identified.")
            if items_remaining then
                msg("Progress: Sing Container Items Left: " .. items_remaining)
            end
            break
        elseif string.find(line, "sufficient power") or string.find(line, "song is weak") then
            local rt_str = string.match(line, "roundtime: (%d+)")
            if rt_str then
                pause(math.max(tonumber(rt_str) + 1 + rt_skew, 0))
            end
            msg("Insufficient mana (" .. checkmana() .. "/" .. maxmana() .. ") after verse 1 - waiting for recovery...")
            cycle_count = cycle_count - 1
            wait_for_mana_recovery()
            -- Continue to next iteration (retry)
        elseif string.find(line, "falters and fades") then
            msg("Song faltered - no loresong or fully identified.")
            break
        elseif string.find(line, "roundtime: (%d+)") then
            local rt_str = string.match(line, "roundtime: (%d+)")
            local rt = tonumber(rt_str) or 3
            msg("Waiting " .. tostring(math.floor(rt + 1 + rt_skew)) .. " seconds...")
            pause(math.max(rt + 1 + rt_skew, 0))
        else
            msg("Verse 1 resonated with no new info - trying verse 2...")
            pause(3)
        end

        -- Only do verse 2 if we didn't loop back from insufficient mana
        if string.find(line, "sufficient power") or string.find(line, "song is weak") then
            -- Skip verse 2, loop back
        else
            -- Verse 2
            local actual_verse2 = string.gsub(get_verse2(), "#{item%.noun}", noun)
            fput("loresing " .. noun .. " " .. actual_verse2)
            pause(1)

            response = reget(12) or {}
            line = string.lower(table.concat(response, " "))

            if string.find(line, "permanently unlocked")
                or string.find(line, "reached the end of .* song")
                or string.find(line, "learn nothing new")
                or string.find(line, "nothing new about") then
                completed = true
                local rt_str2 = string.match(line, "roundtime: (%d+)")
                local rt_sec2 = tonumber(rt_str2) or 5
                pause(math.max(rt_sec2 + 1 + rt_skew, 0))
                check_item_value(noun, item_name, items_remaining)
                msg("Loresong Completed, " .. noun .. " fully identified.")
                if items_remaining then
                    msg("Progress: Sing Container Items Left: " .. items_remaining)
                end
                break
            elseif string.find(line, "sufficient power") or string.find(line, "song is weak") then
                local rt_str2 = string.match(line, "roundtime: (%d+)")
                if rt_str2 then
                    pause(math.max(tonumber(rt_str2) + 1 + rt_skew, 0))
                end
                msg("Insufficient mana (" .. checkmana() .. "/" .. maxmana() .. ") after verse 2 - waiting for recovery...")
                cycle_count = cycle_count - 1
                wait_for_mana_recovery()
                -- Loop back
            elseif string.find(line, "falters and fades") then
                msg("Song faltered - no loresong or fully identified.")
                break
            elseif string.find(line, "roundtime: (%d+)") then
                local rt_str2 = string.match(line, "roundtime: (%d+)")
                local rt = tonumber(rt_str2) or 3
                msg("Waiting " .. tostring(math.floor(rt + 1 + rt_skew)) .. " seconds...")
                pause(math.max(rt + 1 + rt_skew, 0))
            else
                msg("Verse 2 resonated with no new info - cycling back...")
                pause(3)
            end
        end
    end

    if settings.use_guildspeak then
        fput("speak common")
        pause(0.5)
    end

    if not completed and cycle_count <= max_cycles then
        msg("No clear identification after verses - item may be fully unlocked or non-loresing.")
    end

    return completed
end

--------------------------------------------------------------------------------
-- Announce high-value summary
--------------------------------------------------------------------------------

local function announce_high_value_summary()
    if #high_value_items == 0 then return end
    local parts = {}
    for _, item in ipairs(high_value_items) do
        table.insert(parts, item.name .. "(" .. format_silver(item.value) .. ")")
    end
    local summary = #high_value_items .. " valuable items found! " .. table.concat(parts, ", ")
    msg(summary)

    if settings.announce_successes then
        fput("speak common")
        pause(0.5)
        fput("say " .. summary)
        pause(0.5)
    end

    send_webhook(summary, "session_summary")
end

--------------------------------------------------------------------------------
-- Hand mode
--------------------------------------------------------------------------------

local function run_hand_mode()
    local item = GameObj.right_hand()
    if not item or item.name == "Empty" then
        msg("Nothing in right hand!")
        return
    end

    local item_name = item.name
    local noun = item.noun
    msg("Starting loresinging on " .. noun .. "...")

    last_recall_text = nil
    last_item_value = nil

    local ok2, completed = pcall(sing_item, item_name, noun, nil)
    if not ok2 then
        msg("Error during singing: " .. tostring(completed))
        completed = false
    end

    if settings.use_guildspeak then
        fput("speak common")
        pause(0.5)
    end

    -- CSV export
    if settings.csv_export_enabled then
        local status = completed and "completed" or "failed"
        append_csv_row(item_name, noun, status, last_item_value, last_recall_text)
    end

    -- Report item for summary
    table.insert(report_items, {
        name = item_name,
        noun = noun,
        status = completed and "completed" or "failed",
        recall_text = last_recall_text,
        value = last_item_value,
    })

    msg(completed and "Finished." or "Did not complete.")
    announce_high_value_summary()
end

--------------------------------------------------------------------------------
-- Container mode
--------------------------------------------------------------------------------

local function open_containers(sing_container, sung_container)
    for _, cont in ipairs({ sing_container, sung_container }) do
        fput("look in #" .. cont.id)
        pause(0.6)
        -- Check if closed
        local recent = reget(5) or {}
        for _, rline in ipairs(recent) do
            if string.find(rline, "closed") then
                fput("open #" .. cont.id)
                pause(0.8)
                fput("look in #" .. cont.id)
                pause(0.6)
                break
            end
        end
    end
end

local function run_container_mode()
    local sing_name = settings.sing_container or ""
    local sung_name = settings.sung_container or ""

    if sing_name:match("^%s*$") or sung_name:match("^%s*$") then
        msg("Container mode requires both Sing Container and Sung Container to be set in setup!")
        msg("Run ;loresang setup and enter valid worn container names.")
        return
    end

    -- Find containers in inventory
    local sing_container = nil
    local sung_container = nil
    local inv = GameObj.inv()
    for _, obj in ipairs(inv) do
        if not sing_container and string.find(string.lower(obj.name), string.lower(sing_name), 1, true) then
            sing_container = obj
        end
        if not sung_container and string.find(string.lower(obj.name), string.lower(sung_name), 1, true) then
            sung_container = obj
        end
    end

    if not sing_container then
        msg("Sing container '" .. sing_name .. "' not found (must be worn).")
        return
    end
    if not sung_container then
        msg("Sung container '" .. sung_name .. "' not found (must be worn).")
        return
    end

    clear_hands()
    open_containers(sing_container, sung_container)

    -- Get items to sing (filtered by type tags)
    local items_to_sing = {}
    if sing_container.contents then
        for _, item in ipairs(sing_container.contents) do
            if matches_filter(item) then
                table.insert(items_to_sing, item)
            end
        end
    end

    if #items_to_sing == 0 then
        msg("No matching items found in " .. sing_name .. ".")
        return
    end

    local failed_items = {}
    local items_remaining = #items_to_sing
    local successfully_unlocked = 0
    local already_unlocked_count = 0

    for _, item in ipairs(items_to_sing) do
        fput("get #" .. item.id .. " from #" .. sing_container.id)
        pause(0.8)

        -- Check if it ended up in left hand instead
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (not rh or rh.name == "Empty") and lh and lh.id == item.id then
            fput("swap")
            pause(0.5)
            rh = GameObj.right_hand()
        end

        -- Verify item is in right hand
        rh = GameObj.right_hand()
        if not rh or rh.id ~= item.id then
            msg("Could not get " .. item.name .. " into right hand. Skipping.")
            goto continue_item
        end

        local item_name = item.name
        local noun = item.noun

        -- Check if already unlocked via recall
        fput("recall " .. noun)
        waitrt()
        pause(0.8)

        local recall_lines = reget(35) or {}
        local start_idx = nil
        for i = #recall_lines, 1, -1 do
            if string.find(recall_lines[i], "As you recall your song") then
                start_idx = i + 1
                break
            end
        end
        local recall_text = ""
        if start_idx then
            local parts = {}
            for i = start_idx, #recall_lines do
                table.insert(parts, recall_lines[i])
            end
            recall_text = table.concat(parts, "\n")
        else
            recall_text = table.concat(recall_lines, "\n")
        end

        if already_unlocked(recall_text) then
            -- Check value even for already-unlocked items
            local threshold_str = string.gsub(settings.value_threshold or "", ",", "")
            local threshold = tonumber(threshold_str)
            if settings.value_alert_enabled and threshold then
                local item_value = parse_item_value(recall_text)
                if item_value >= threshold then
                    local formatted = format_silver(item_value)
                    local message = "Item " .. item_name .. " worth " .. formatted .. " silvers - over your threshold! " .. items_remaining .. " items to go!"
                    msg(message)
                    if settings.announce_successes then
                        fput("speak common")
                        pause(0.5)
                        fput("say " .. message)
                        pause(0.5)
                    end
                    table.insert(high_value_items, { name = item_name, value = item_value })
                    send_webhook(message, "high_value_item")
                end
            end

            if settings.csv_export_enabled then
                local raw_val = parse_item_value(recall_text)
                append_csv_row(item_name, noun, "already_unlocked", raw_val > 0 and raw_val or nil, recall_text)
            end

            table.insert(report_items, {
                name = item_name, noun = noun, status = "already_unlocked",
                recall_text = recall_text, value = parse_item_value(recall_text) > 0 and parse_item_value(recall_text) or nil,
            })

            msg(noun .. " already fully unlocked - moving to sung container.")
            fput("put #" .. item.id .. " in #" .. sung_container.id)
            pause(0.6)
            items_remaining = items_remaining - 1
            already_unlocked_count = already_unlocked_count + 1
            msg("Progress: Sing Container Items Left: " .. items_remaining)
            goto continue_item
        end

        -- Sing the item
        last_recall_text = nil
        last_item_value = nil
        local sing_ok, completed = pcall(sing_item, item_name, noun, items_remaining)
        if not sing_ok then
            msg("Error singing " .. noun .. ": " .. tostring(completed))
            completed = false
        end

        if completed then
            if settings.csv_export_enabled then
                append_csv_row(item_name, noun, "completed", last_item_value, last_recall_text)
            end
            table.insert(report_items, {
                name = item_name, noun = noun, status = "completed",
                recall_text = last_recall_text, value = last_item_value,
            })
            fput("put #" .. item.id .. " in #" .. sung_container.id)
            items_remaining = items_remaining - 1
            successfully_unlocked = successfully_unlocked + 1
        else
            if settings.csv_export_enabled then
                append_csv_row(item_name, noun, "failed", nil, nil)
            end
            table.insert(report_items, {
                name = item_name, noun = noun, status = "failed",
                recall_text = nil, value = nil,
            })
            fput("put #" .. item.id .. " in #" .. sing_container.id)
            table.insert(failed_items, item.name)
        end
        pause(0.6)

        ::continue_item::
    end

    if settings.use_guildspeak then
        fput("speak common")
        pause(0.5)
    end

    if #failed_items > 0 then
        msg("Failed items (returned to " .. sing_name .. "):")
        for _, n in ipairs(failed_items) do
            msg("  - " .. n)
        end
    end

    msg("Batch loresinging complete! " .. successfully_unlocked .. " items successfully unlocked and " ..
        already_unlocked_count .. " items already found unlocked. All moved to " .. sung_name .. "!")

    announce_high_value_summary()

    -- Session webhook summary
    if #report_items > 0 then
        send_webhook(
            "Session complete: " .. successfully_unlocked .. " unlocked, " ..
            already_unlocked_count .. " already done, " .. #failed_items .. " failed.",
            "session_complete"
        )
    end

    msg("Script finished.")
end

--------------------------------------------------------------------------------
-- GUI Setup (Gui.* API)
--------------------------------------------------------------------------------

local function show_setup()
    local win = Gui.window("Loresang Setup", { width = 700, height = 680, resizable = true })
    local root = Gui.vbox()

    -- Header
    local header = Gui.label("Loresang Configuration\nSettings for container mode mostly; some apply to hand mode too.")
    root:add(header)
    root:add(Gui.separator())

    -- General settings card
    local general_card = Gui.card({ title = "General" })
    local general_box = Gui.vbox()

    local guildspeak_cb = Gui.checkbox("Use guildspeak to loresing?", settings.use_guildspeak)
    general_box:add(guildspeak_cb)

    local csv_cb = Gui.checkbox("Enable CSV log export?", settings.csv_export_enabled)
    general_box:add(csv_cb)

    local webhook_cb = Gui.checkbox("Enable Discord webhook alerts?", settings.webhook_enabled)
    general_box:add(webhook_cb)

    local webhook_row = Gui.hbox()
    webhook_row:add(Gui.label("Webhook name: "))
    local webhook_input = Gui.input({ text = settings.webhook_name or "", placeholder = "webhook name from lib/webhooks" })
    webhook_row:add(webhook_input)
    general_box:add(webhook_row)

    general_card:add(general_box)
    root:add(general_card)

    -- Mana card
    local mana_card = Gui.card({ title = "Mana Management" })
    local mana_box = Gui.vbox()

    local low_mana_row = Gui.hbox()
    local low_mana_cb = Gui.checkbox("Say something when mana drops below %:", settings.low_mana_enabled)
    low_mana_row:add(low_mana_cb)
    local low_mana_pct_input = Gui.input({ text = tostring(settings.low_mana_pct or 15), placeholder = "15" })
    low_mana_row:add(low_mana_pct_input)
    mana_box:add(low_mana_row)

    local low_mana_text_input = Gui.input({ text = settings.low_mana_text or "", placeholder = "What to say when mana is low" })
    mana_box:add(low_mana_text_input)

    mana_card:add(mana_box)
    root:add(mana_card)

    -- Value alert card
    local value_card = Gui.card({ title = "Value Alerts" })
    local value_box = Gui.vbox()

    local value_row = Gui.hbox()
    local value_cb = Gui.checkbox("Alert for value threshold?", settings.value_alert_enabled)
    value_row:add(value_cb)
    local value_input = Gui.input({ text = settings.value_threshold or "", placeholder = "Silver threshold" })
    value_row:add(value_input)
    value_box:add(value_row)

    local announce_cb = Gui.checkbox("Announce valuable items to room?", settings.announce_successes)
    value_box:add(announce_cb)

    value_card:add(value_box)
    root:add(value_card)

    -- Roundtime card
    local rt_card = Gui.card({ title = "Roundtime" })
    local rt_box = Gui.vbox()

    local rt_row = Gui.hbox()
    local rt_cb = Gui.checkbox("Roundtime skew:", settings.rt_skew_enabled)
    rt_row:add(rt_cb)
    local rt_input = Gui.input({ text = settings.rt_skew or "0", placeholder = "+/-seconds" })
    rt_row:add(rt_input)
    rt_box:add(rt_row)

    local max_row = Gui.hbox()
    max_row:add(Gui.label("Max cycles before abort: "))
    local max_input = Gui.input({ text = tostring(settings.max_cycles or 10), placeholder = "10" })
    max_row:add(max_input)
    rt_box:add(max_row)

    rt_card:add(rt_box)
    root:add(rt_card)

    -- Container card
    local cont_card = Gui.card({ title = "Containers" })
    local cont_box = Gui.vbox()

    local sing_row = Gui.hbox()
    sing_row:add(Gui.label("Sing Container: "))
    local sing_input = Gui.input({ text = settings.sing_container or "", placeholder = "worn container with items to sing" })
    sing_row:add(sing_input)
    cont_box:add(sing_row)

    local sung_row = Gui.hbox()
    sung_row:add(Gui.label("Sung Container: "))
    local sung_input = Gui.input({ text = settings.sung_container or "", placeholder = "worn container for completed items" })
    sung_row:add(sung_input)
    cont_box:add(sung_row)

    cont_card:add(cont_box)
    root:add(cont_card)

    -- Custom verses card
    local verse_card = Gui.card({ title = "Custom Verses (blank = default)" })
    local verse_box = Gui.vbox()

    verse_box:add(Gui.label("Verse 1:"))
    local v1_input = Gui.input({ text = settings.verse1 or "", placeholder = "Custom first verse (use {noun} for item noun)" })
    verse_box:add(v1_input)

    verse_box:add(Gui.label("Verse 2:"))
    local v2_input = Gui.input({ text = settings.verse2 or "", placeholder = "Custom second verse" })
    verse_box:add(v2_input)

    verse_card:add(verse_box)
    root:add(verse_card)

    -- Item type filters card
    local filter_card = Gui.card({ title = "Item Types to Sing (container mode)" })
    local filter_box = Gui.vbox()

    local filter_row1 = Gui.hbox()
    local cb_clothing = Gui.checkbox("Clothing", settings.tag_clothing)
    local cb_weapons = Gui.checkbox("Weapons", settings.tag_weapons)
    local cb_armor = Gui.checkbox("Armor", settings.tag_armor)
    filter_row1:add(cb_clothing)
    filter_row1:add(cb_weapons)
    filter_row1:add(cb_armor)
    filter_box:add(filter_row1)

    local filter_row2 = Gui.hbox()
    local cb_jewelry = Gui.checkbox("Jewelry", settings.tag_jewelry)
    local cb_containers = Gui.checkbox("Containers", settings.tag_containers)
    local cb_magic = Gui.checkbox("Magic", settings.tag_magic)
    filter_row2:add(cb_jewelry)
    filter_row2:add(cb_containers)
    filter_row2:add(cb_magic)
    filter_box:add(filter_row2)

    filter_card:add(filter_box)
    root:add(filter_card)

    -- Buttons
    local btn_row = Gui.hbox()
    local save_btn = Gui.button("Save & Close")
    save_btn:on_click(function()
        settings.use_guildspeak = guildspeak_cb:get_checked()
        settings.csv_export_enabled = csv_cb:get_checked()
        settings.webhook_enabled = webhook_cb:get_checked()
        settings.webhook_name = webhook_input:get_text() or ""
        settings.low_mana_enabled = low_mana_cb:get_checked()
        settings.low_mana_text = low_mana_text_input:get_text() or ""
        local pct_text = low_mana_pct_input:get_text() or "15"
        local pct_val = tonumber(pct_text)
        if pct_val then
            settings.low_mana_pct = math.max(1, math.min(100, pct_val))
        else
            settings.low_mana_pct = 15
        end
        settings.value_alert_enabled = value_cb:get_checked()
        settings.value_threshold = value_input:get_text() or ""
        settings.announce_successes = announce_cb:get_checked() and value_cb:get_checked()
        settings.rt_skew_enabled = rt_cb:get_checked()
        settings.rt_skew = rt_input:get_text() or "0"

        local max_text = max_input:get_text() or "10"
        local max_val = tonumber(max_text)
        settings.max_cycles = (max_val and max_val > 0) and max_val or 10

        settings.sing_container = sing_input:get_text() or ""
        settings.sung_container = sung_input:get_text() or ""
        settings.verse1 = v1_input:get_text() or ""
        settings.verse2 = v2_input:get_text() or ""
        settings.tag_clothing = cb_clothing:get_checked()
        settings.tag_weapons = cb_weapons:get_checked()
        settings.tag_armor = cb_armor:get_checked()
        settings.tag_jewelry = cb_jewelry:get_checked()
        settings.tag_containers = cb_containers:get_checked()
        settings.tag_magic = cb_magic:get_checked()

        save_settings(settings)
        msg("Settings saved.")
        win:close()
    end)
    btn_row:add(save_btn)

    local cancel_btn = Gui.button("Cancel")
    cancel_btn:on_click(function()
        win:close()
    end)
    btn_row:add(cancel_btn)

    root:add(btn_row)

    win:set_root(Gui.scroll(root))
    win:show()
    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- Show CSV log info
--------------------------------------------------------------------------------

local function show_log()
    local path = csv_log_path()
    if File.exists(path) then
        msg("CSV log path: " .. path)
        local content = File.read(path) or ""
        local line_count = 0
        for _ in string.gmatch(content, "[^\n]+") do
            line_count = line_count + 1
        end
        -- Subtract header row
        msg("Total entries: " .. math.max(0, line_count - 1))
    else
        msg("No CSV log found yet. Run ;loresang to create one.")
        msg("Expected path: " .. path)
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    msg("Loresang v" .. VERSION .. " by Kyrandos")
    respond("")
    msg("Commands:")
    msg("  ;loresang               - Sing all items from Sing Container to Sung Container")
    msg("  ;loresang hand          - Sing item in right hand until complete")
    msg("  ;loresang setup         - Open configuration GUI window")
    msg("  ;loresang log           - Show CSV log path and summary")
    msg("  ;loresang help          - This help")
    respond("")
    msg("Container mode requires setup first (;loresang setup).")
    msg("  Set Sing Container (source) and Sung Container (destination).")
    msg("  Enable item type filters (clothing, weapons, armor, jewelry, containers, magic).")
    respond("")
    msg("Features:")
    msg("  - Custom song verses (verse 1 and verse 2)")
    msg("  - Mana checks and low-mana callout")
    msg("  - Value threshold alerts (chat + optional room announcement)")
    msg("  - Discord webhook alerts via lib/webhooks")
    msg("  - CSV export of all results")
    msg("  - Roundtime skew adjustment")
    msg("  - Guildspeak mode (speak bard/common)")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local arg = string.lower(Script.vars[1] or "")

if arg == "setup" then
    show_setup()
elseif arg == "help" then
    show_help()
elseif arg == "log" then
    show_log()
elseif arg == "hand" then
    run_hand_mode()
else
    run_container_mode()
end
