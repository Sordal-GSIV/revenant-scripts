--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: htsorter
--- version: 1.0.6
--- author: Ensayn
--- contributors: Tillmen
--- game: gs
--- description: Container contents organized by item categories with color coding
--- tags: utility, organization, containers, high_type
---
--- Displays container contents organized by item categories (type-based) with optional
--- column formatting. Integrates with high_type for category-based highlighting via the
--- shared UserVars.types_to_color configuration (stored as JSON). Items without a
--- configured color default to link color.
---
--- Usage:
---   ;htsorter                 - Start the sorter (works without high_type)
---   ;htsorter width=80        - Set window width for column display
---   ;htsorter width=nil       - Disable column formatting
---
--- Changelog (Lich5 → Revenant):
---   v1.0.6 - 2025-09-18 - Fixed dependency version requirement, duplicate bold color handling
---   v1.0.5 - 2025-09-18 - Updated header to match script header template
---   v1.0.4 - 2025-09-14 - Removed old compatibility fallbacks, uses UserVars.types_to_color only
---   v1.0.3 - 2025-09-14 - Added startup wait for high_type dependency
---   v1.0.2 - 2025-09-14 - Default unassigned types to link color (matches linktothefast behavior)
---   v1.0.1 - 2025-09-14 - Fixed coloring issue, restored local color function
---   v0.9   - 2016-08-17 - Fix for the last fix
---   v0.8   - 2016-08-07 - Fix for containers with XML content display
---   v0.7   - 2015-04-16 - Fix display of broken containers on WizardFE

-------------------------------------------------------------------------------
-- Argument handling: width setting
-------------------------------------------------------------------------------

if script.vars[1] then
    local arg = script.vars[1]
    local w_num = arg:match("^width=(%d+)$")
    local w_nil = arg:match("^width=(nil)$")
    if w_num then
        CharSettings["screen_width"] = tonumber(w_num)
        echo("setting saved")
        exit()
    elseif w_nil then
        CharSettings["screen_width"] = nil
        echo("setting saved")
        exit()
    else
        local pad = string.rep(" ", #script.name)
        respond("\n   ;" .. script.name .. " width=<#>     Specify how many characters wide your game window is,")
        respond("   " .. pad .. "               and the script will display container contents in columns.")
        respond("\n   ;" .. script.name .. " width=nil     Clear the setting.\n")
        exit()
    end
end

hide_me()

-------------------------------------------------------------------------------
-- Wait for high_type to be fully active (10s timeout — script works without it)
-------------------------------------------------------------------------------

echo("htsorter starting - waiting for high_type to be fully active...")
local wait_start = os.time()
while not Script.running("high_type") do
    if os.time() - wait_start >= 10 then
        echo("htsorter: high_type not detected after 10s, continuing without color config...")
        break
    end
    sleep(0.5)
end
if Script.running("high_type") then
    echo("htsorter detected high_type running - continuing startup...")
end

-------------------------------------------------------------------------------
-- Color helpers — uses UserVars.types_to_color (shared with high_type, JSON encoded)
-------------------------------------------------------------------------------

-- Load and parse the shared color config from UserVars (returns table or nil)
local function load_color_config()
    local raw = UserVars.types_to_color
    if not raw then return nil end
    local ok, tbl = pcall(Json.decode, raw)
    if ok and type(tbl) == "table" then return tbl end
    return nil
end

-- Find the first matching color for item_types (e.g. "gem,collectible") using regex matching
local function get_item_color(item_types)
    if not item_types then return nil end
    local config = load_color_config()
    if not config then return nil end
    for pattern, color in pairs(config) do
        local ok, re = pcall(Regex.new, pattern)
        if ok and re:is_match(item_types) then
            return color
        end
    end
    return nil
end

-- Apply a named color preset to text. Supports: monsterbold, bold, speech, whisper,
-- thought, link, selectedlink. Unknown/nil defaults to link (matches high_type behavior).
local function apply_color(text, color_type)
    local c = (color_type or "link"):lower()
    if c == "monsterbold" then
        return "<pushBold/>" .. text .. "<popBold/>"
    elseif c == "bold" then
        return '<preset id="bold">' .. text .. '</preset>'
    elseif c == "speech" then
        return '<preset id="speech">' .. text .. '</preset>'
    elseif c == "whisper" then
        return '<preset id="whisper">' .. text .. '</preset>'
    elseif c == "thought" then
        return '<preset id="thought">' .. text .. '</preset>'
    elseif c == "selectedlink" or c == "selected" then
        return '<preset id="selectedLink">' .. text .. '</preset>'
    else
        return '<preset id="link">' .. text .. '</preset>'
    end
end

-- Format items text with the high_type color for a category (falls back to link)
local function format_with_color(text, category_name)
    return apply_color(text, get_item_color(category_name) or "link")
end

-------------------------------------------------------------------------------
-- Column layout — port of Ruby's best_column_count proc
-- Given a list of plain-text names and a screen width, returns optimal column count.
-------------------------------------------------------------------------------

local function best_column_count(names, screen_width)
    local num_columns = 1
    while true do
        local items_per_col = math.ceil(#names / num_columns)
        local total_width = 0
        for col = 0, num_columns - 1 do
            local max_w = 0
            local s = col * items_per_col + 1
            local e = math.min((col + 1) * items_per_col, #names)
            for i = s, e do
                if #names[i] > max_w then max_w = #names[i] end
            end
            total_width = total_width + max_w
        end
        total_width = total_width + (num_columns - 1) * 8
        if total_width > screen_width - 8 then
            num_columns = num_columns - 1
            break
        elseif num_columns >= #names then
            break
        end
        num_columns = num_columns + 1
    end
    return math.max(num_columns, 1)
end

-------------------------------------------------------------------------------
-- Item name cleanup
-- - "a crystalline flask containing X" → strip the prefix
-- - "Y containing Z" → "Y (Z)"
-------------------------------------------------------------------------------

local function clean_item_name(full_name)
    local flask_prefix = "a crystalline flask containing "
    if full_name:sub(1, #flask_prefix) == flask_prefix then
        return full_name:sub(#flask_prefix + 1)
    end
    return (full_name:gsub("containing (.+)$", function(inner) return "(" .. inner .. ")" end))
end

-------------------------------------------------------------------------------
-- Sort comparator: alphabetical by last word (noun)
-------------------------------------------------------------------------------

local function by_noun(a, b)
    local a_noun = a.name:match("%S+$") or a.name
    local b_noun = b.name:match("%S+$") or b.name
    return a_noun < b_noun
end

-------------------------------------------------------------------------------
-- Build sorted_contents from a list of GameObj items
-- Returns sorted category_order[] and sorted_contents{cat → {name → {noun,exist,count}}}
-------------------------------------------------------------------------------

local function build_sorted_contents(items)
    local sorted = {}
    local order = {}
    for _, item in ipairs(items) do
        local cat = item.type or "other"
        local name = clean_item_name(item.full_name or item.name or "")
        if not sorted[cat] then
            sorted[cat] = {}
            table.insert(order, cat)
        end
        local entry = sorted[cat][name]
        if not entry then
            sorted[cat][name] = { noun = item.noun or "", exist = item.id or "", count = 1 }
        else
            entry.count = entry.count + 1
        end
    end
    table.sort(order)
    return order, sorted
end

-- Convert category dict to a noun-sorted list of {name, info} pairs
local function items_sorted(cat_dict)
    local list = {}
    for name, info in pairs(cat_dict) do
        table.insert(list, { name = name, info = info })
    end
    table.sort(list, by_noun)
    return list
end

-- Build a clickable link tag for an item entry
local function make_link(entry)
    if entry.info.count > 1 then
        return string.format('<a exist="%s" noun="%s">%s</a> (%d)',
            entry.info.exist, entry.info.noun, entry.name, entry.info.count)
    end
    return string.format('<a exist="%s" noun="%s">%s</a>',
        entry.info.exist, entry.info.noun, entry.name)
end

-------------------------------------------------------------------------------
-- Render container contents as sorted output (column or linear format)
-------------------------------------------------------------------------------

local function render_sorted(container_label, contents)
    local screen_width = CharSettings["screen_width"]
    local order, sorted = build_sorted_contents(contents)
    local out = {}

    if screen_width then
        table.insert(out, '<output class="mono"/>')
    end
    table.insert(out, container_label .. ":")

    if screen_width then
        -- Column-formatted output (Stormfront monospace)
        for _, cat in ipairs(order) do
            local cat_items = items_sorted(sorted[cat])
            local count = 0
            for _, e in ipairs(cat_items) do count = count + e.info.count end
            table.insert(out, "<pushBold/>" .. cat .. " (" .. count .. "):<popBold/> ")

            -- Column layout
            local names = {}
            for _, e in ipairs(cat_items) do table.insert(names, e.name) end
            local col_count = best_column_count(names, screen_width)
            local row_count = math.ceil(#cat_items / col_count)
            col_count = math.ceil(#cat_items / row_count)

            -- Calculate max plain-name width per column for alignment
            local col_widths = {}
            for col = 0, col_count - 1 do
                local max_w = 0
                local s = col * row_count + 1
                local e = math.min((col + 1) * row_count, #cat_items)
                for i = s, e do
                    if #cat_items[i].name > max_w then max_w = #cat_items[i].name end
                end
                col_widths[col] = max_w
            end

            -- Render each row
            for row = 0, row_count - 1 do
                local row_parts = { "    " }
                for col = 0, col_count - 1 do
                    local idx = col * row_count + row + 1
                    if idx <= #cat_items then
                        local link = make_link(cat_items[idx])
                        if col < col_count - 1 then
                            -- Pad: xml tags add overhead vs plain name; align on content width + 12
                            local tag_overhead = #link - #cat_items[idx].name
                            local pad_to = col_widths[col] + tag_overhead + 12
                            link = link .. string.rep(" ", math.max(0, pad_to - #link))
                        end
                        table.insert(row_parts, link)
                    end
                end
                table.insert(out, table.concat(row_parts))
            end
            table.insert(out, "")  -- blank line between categories
        end
        table.insert(out, '<output class=""/>')
    else
        -- Linear output
        local total = 0
        for _, cat in ipairs(order) do
            local cat_items = items_sorted(sorted[cat])
            local count = 0
            for _, e in ipairs(cat_items) do count = count + e.info.count end
            total = total + count

            local links = {}
            for _, e in ipairs(cat_items) do table.insert(links, make_link(e)) end
            local items_text = table.concat(links, ", ")

            table.insert(out, "<pushBold/>" .. cat .. " (" .. count .. "):<popBold/> "
                .. format_with_color(items_text, cat) .. ".")
        end
        table.insert(out, "<pushBold/>total (" .. total .. ")<popBold/> ")
    end

    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
-- Render container contents sorted by sellable category (show_sellable mode)
-------------------------------------------------------------------------------

local function render_sellable(container_label, contents)
    local sorted = {}
    local order = {}
    for _, item in ipairs(contents) do
        local cat = item.sellable or "nil"
        local name = clean_item_name(item.full_name or item.name or "")
        if not sorted[cat] then
            sorted[cat] = {}
            table.insert(order, cat)
        end
        local entry = sorted[cat][name]
        if not entry then
            sorted[cat][name] = { noun = item.noun or "", exist = item.id or "", count = 1 }
        else
            entry.count = entry.count + 1
        end
    end
    table.sort(order)

    local out = { "\n" .. container_label .. ":" }
    for _, cat in ipairs(order) do
        local cat_items = items_sorted(sorted[cat])
        local count = 0
        for _, e in ipairs(cat_items) do count = count + e.info.count end
        local links = {}
        for _, e in ipairs(cat_items) do table.insert(links, make_link(e)) end
        table.insert(out, "<pushBold/>" .. cat .. " (" .. count .. "):<popBold/> "
            .. table.concat(links, ", ") .. ".")
    end
    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
-- Downstream hook: suppress raw container listing, render sorted output instead
-------------------------------------------------------------------------------

-- show_sellable: when true, also renders a second view sorted by sellable category.
-- Hardcoded off (no flag to enable in original); kept for completeness.
local show_sellable = false

DownstreamHook.add("htsorter", function(line)
    -- Fast-path: skip lines that can't be container listings
    if not line:match("[IO]n the ") and not line:match("Peering into the ") then
        return line
    end
    -- Must start with a container XML tag (has inv attribute)
    if not line:match("^<[^>]*inv>") then return line end
    -- Skip ambiguous lines matching both "In the" and "On the"
    if line:match("In the") and line:match("On the") then return line end

    -- Extract the container label and exist ID
    local container_label
    if line:match("[IO]n the .+ you see") then
        container_label = line:match("([IO]n the .-) you see")
    elseif line:match("Peering into the .+, you see") then
        local base = line:match("(Peering into the .-, you see .-)")
        container_label = base and (base .. " and")
    end
    if not container_label then return line end

    -- The exist ID is embedded in the anchor tag within the container label text
    local container_id = container_label:match('exist="(%d+)"')
        -- Fallback: try the XML opening tag itself
        or line:match('^<[^>]*exist="(%d+)"')
    if not container_id then return line end

    -- Look up container contents from GameObj (populated by XML parser before hook fires)
    local containers = GameObj.containers()
    local contents = containers and containers[container_id]
    if not contents then
        echo("WARNING: Unable to get contents for container #" .. container_id
            .. ". Try looking in it again.")
        return line
    end

    -- Render and display the sorted output
    respond(render_sorted(container_label, contents))
    if show_sellable then
        respond(render_sellable(container_label, contents))
    end

    -- Suppress the raw container listing; pass through any leading XML tag only
    return line:match("^(<[^>]*>)") or ""
end)

before_dying(function()
    DownstreamHook.remove("htsorter")
end)

echo("htsorter active - look in containers to see sorted contents")
while true do get() end
