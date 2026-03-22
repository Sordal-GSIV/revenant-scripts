--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: librarian
--- version: 0.30.0
--- author: Bhuryn
--- game: gs
--- description: Grimoire helper for managing grimoires and scroll containers
--- tags: grimoire,spellbook,utility,scrolls
---
--- Changelog (from Lich5):
---   v0.30 - Made clean auto-confirm when the grimoire returns the standard repeat-to-confirm prompt
---   v0.29 - Added a configurable default grimoire noun setting for books that do not use the standard grimoire noun
---   v0.28 - Saves the grimoire noun and falls back to GET by noun when the saved grimoire id has changed on logout
---   v0.27 - Auto-refreshes the saved grimoire id when the same held grimoire is found by name after its GameObj id changes
---   v0.26 - Fixed get book so it can retrieve the saved grimoire by id even when Lich has not mapped it properly
---   v0.25 - Updated page scanning so it supports 1-X pages properly
---   v0.24 - Expanded help output with an initial setup block for saving the grimoire and scroll container
---   v0.23 - Made charge all continue recharging spells while matching regular scrolls remain
---   v0.22 - Fixed live charge so the source scroll stays in hand through the second transfer confirmation
---   v0.21 - Made scroll reads use a scroll-specific capture pattern and deduped repeated spell hits
---   v0.20 - Added a persisted testmode command
---   v0.19 - Re-enabled live charge confirmation; duplicate spell targeting prefers highest non-full copy
---   v0.18 - Added charge all
---   v0.17 - Returns the source scroll to the saved scroll container after charge attempts
---   v0.16 - Made charge test mode stop after the confirmation prompt
---   v0.15 - Removed incorrect drag fallback from item retrieval
---   v0.14 - Added sellskscrolls
---   v0.13 - Temporarily disabled second transfer confirmation for charge testing
---   v0.12 - Fixed charge transfer confirmation handling
---   v0.11 - Added charge <spell number>
---   v0.10 - Switched retrieval to live get/drag commands with hand verification
---   v0.9  - Made scroll source names clickable in scroll summaries
---   v0.8  - Added get book, get scroll, and get skscroll commands
---   v0.7  - Added scroll container scanning
---   v0.6  - Added saved scroll container support via ;librarian scrollcontainer
---   v0.5  - Recognizes the grimoire clean cooldown messaging
---   v0.4  - Made clean capture and report the grimoire response
---   v0.3  - Fixed command capture, added scan alias, saved grimoire id via ;librarian add
---   v0.2  - Added a memory dump command
---   v0.1  - Initial release

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_GRIMOIRE_CHARGES = 40
local DEFAULT_CHARGE_TEST_MODE = false
local GRIMOIRE_NOUN = "grimoire"

-- CharSettings keys
local GRIMOIRE_ID_SETTING           = "librarian_grimoire_id"
local GRIMOIRE_NAME_SETTING         = "librarian_grimoire_name"
local GRIMOIRE_NOUN_SETTING         = "librarian_grimoire_noun"
local DEFAULT_GRIMOIRE_NOUN_SETTING = "librarian_default_grimoire_noun"
local SCROLL_CONTAINER_ID_SETTING   = "librarian_scroll_container_id"
local SCROLL_CONTAINER_NAME_SETTING = "librarian_scroll_container_name"
local CHARGE_TEST_MODE_SETTING      = "librarian_charge_test_mode"

-- Pattern strings for matching game output
local PAGE_START_PAT         = "You glance down at your .* and carefully study page %d+"
local PAGE_NUMBER_PAT        = "carefully study page (%d+)"
local SLOT_SPELL_PAT         = "^(%d+)%.%s+The (.-)%s+%((%d+)%) spell with (%d+) charges remaining%.$"
local SLOT_BLANK_PAT         = "^(%d+)%.%s+This section is blank%.$"
local PONDER_START_PAT       = "You ponder over your .*grimoire, shifting your attention"
local CLEAN_COOLDOWN_PAT     = "runes seem to shift and elude your understanding"
local SCROLL_READ_START_PAT  = "^It takes you a moment to focus on the .+%.$"
local SCROLL_READ_HEADER_PAT = "^On the .+ you see$"
local SCROLL_SPELL_LINE_PAT  = "^%((%d+)%)%s+(.+)$"
local VIBRANT_INK_SUFFIX     = " in vibrant ink"
local TRANSFER_CONFIRM_PAT   = "Repeat this command within 30 seconds to confirm"
local TRANSFER_SUCCESS_PAT   = "Working diligently, you trace over the runes inscribed in your .*grimoire"
local TRANSFER_SUCCESS_PAT2  = "their ink seems to become darker and sharper"
local TRANSFER_FAILURE_PATS  = {
    "What were you referring to",
    "You can't",
    "You cannot",
    "You must",
    "already fully charged",
    "not currently holding",
    "don't seem to be holding",
    "nothing happens",
    "unable to transfer",
}

--------------------------------------------------------------------------------
-- Helpers: string utilities
--------------------------------------------------------------------------------

local function strip(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function lower(s)
    return s and string.lower(s) or ""
end

local function contains(s, sub)
    return string.find(s, sub, 1, true) ~= nil
end

local function starts_with(s, prefix)
    return s:sub(1, #prefix) == prefix
end

local function split_args(s)
    local parts = {}
    for word in s:gmatch("%S+") do
        table.insert(parts, word)
    end
    return parts
end

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

local function is_digit_string(s)
    return s:match("^%d+$") ~= nil
end

local function fail_with(msg)
    error(msg, 0)
end

--------------------------------------------------------------------------------
-- Settings persistence helpers
--------------------------------------------------------------------------------

local function configured_grimoire_id()
    local val = CharSettings[GRIMOIRE_ID_SETTING]
    if not val or val == "" then return nil end
    return tostring(val)
end

local function configured_grimoire_name()
    return CharSettings[GRIMOIRE_NAME_SETTING]
end

local function configured_grimoire_noun()
    return CharSettings[GRIMOIRE_NOUN_SETTING]
end

local function configured_default_grimoire_noun()
    local val = CharSettings[DEFAULT_GRIMOIRE_NOUN_SETTING]
    local s = strip(tostring(val or ""))
    if s == "" then return GRIMOIRE_NOUN end
    return s
end

local function save_default_grimoire_noun(noun)
    CharSettings[DEFAULT_GRIMOIRE_NOUN_SETTING] = lower(strip(noun))
end

local function save_grimoire(item)
    CharSettings[GRIMOIRE_ID_SETTING]   = tostring(item.id)
    CharSettings[GRIMOIRE_NAME_SETTING] = tostring(item.name)
    CharSettings[GRIMOIRE_NOUN_SETTING] = tostring(item.noun)
end

local function save_scroll_container(item)
    CharSettings[SCROLL_CONTAINER_ID_SETTING]   = tostring(item.id)
    CharSettings[SCROLL_CONTAINER_NAME_SETTING] = tostring(item.name)
end

local function configured_scroll_container_id()
    local val = CharSettings[SCROLL_CONTAINER_ID_SETTING]
    if not val or val == "" then return nil end
    return tostring(val)
end

local function configured_scroll_container_name()
    return CharSettings[SCROLL_CONTAINER_NAME_SETTING]
end

local function charge_test_mode_enabled()
    local val = CharSettings[CHARGE_TEST_MODE_SETTING]
    if not val or val == "" then return DEFAULT_CHARGE_TEST_MODE end
    local s = lower(strip(tostring(val)))
    return s == "true" or s == "on" or s == "1" or s == "yes" or s == "enabled"
end

local function save_charge_test_mode(enabled)
    CharSettings[CHARGE_TEST_MODE_SETTING] = enabled and "true" or "false"
end

--------------------------------------------------------------------------------
-- Item access helpers
--------------------------------------------------------------------------------

local function held_items()
    local items = {}
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh and rh.id then table.insert(items, rh) end
    if lh and lh.id then table.insert(items, lh) end
    return items
end

local function inventory_items()
    local items = {}
    local inv = GameObj.inv()
    if inv then
        for _, item in ipairs(inv) do
            if item and item.id then
                table.insert(items, item)
            end
        end
    end
    return items
end

local function find_held_item(query)
    local items = held_items()
    if #items == 0 then return nil end

    if (not query or strip(query) == "") and #items == 1 then
        return items[1]
    end

    local downcased = lower(strip(query or ""))
    local matches = {}
    for _, item in ipairs(items) do
        if contains(lower(tostring(item.name)), downcased) or
           contains(lower(tostring(item.noun)), downcased) then
            table.insert(matches, item)
        end
    end

    if #matches == 1 then return matches[1] end
    if #matches == 0 then return nil end
    fail_with("More than one held item matched '" .. (query or "") .. "'.")
end

local function find_inventory_item(query)
    local s = strip(query or "")
    if s == "" then
        fail_with("Usage: ;librarian scrollcontainer <item name>")
    end

    local downcased = lower(s)
    local matches = {}
    for _, item in ipairs(inventory_items()) do
        if contains(lower(tostring(item.name)), downcased) or
           contains(lower(tostring(item.noun)), downcased) then
            table.insert(matches, item)
        end
    end

    if #matches == 1 then return matches[1] end
    if #matches == 0 then fail_with("No inventory item matched '" .. query .. "'.") end
    fail_with("Multiple inventory items matched '" .. query .. "'. Refine the name.")
end

local function current_grimoire()
    local saved_id = configured_grimoire_id()
    if saved_id then
        -- Look for exact id match in hands
        for _, item in ipairs(held_items()) do
            if tostring(item.id) == saved_id then return item end
        end

        -- Fall back to exact name match
        local saved_name = lower(strip(configured_grimoire_name() or ""))
        if saved_name ~= "" then
            local name_matches = {}
            for _, item in ipairs(held_items()) do
                if lower(strip(tostring(item.name))) == saved_name then
                    table.insert(name_matches, item)
                end
            end
            if #name_matches == 1 then
                save_grimoire(name_matches[1])
                return name_matches[1]
            end
        end

        -- Fall back to default noun match
        local fallback_noun = configured_default_grimoire_noun()
        local noun_matches = {}
        for _, item in ipairs(held_items()) do
            if lower(tostring(item.noun)) == lower(fallback_noun) then
                table.insert(noun_matches, item)
            end
        end
        if #noun_matches == 1 then
            save_grimoire(noun_matches[1])
            return noun_matches[1]
        end

        local name_hint = configured_grimoire_name()
        fail_with("Saved grimoire #" .. saved_id ..
            (name_hint and (" (" .. name_hint .. ")") or "") ..
            " is not currently held. Use ;librarian add while holding the book.")
    end

    -- No saved id: try noun match
    local default_noun = configured_default_grimoire_noun()
    for _, item in ipairs(held_items()) do
        if lower(tostring(item.noun)) == lower(default_noun) then
            return item
        end
    end

    fail_with("Hold your " .. default_noun ..
        " in either hand before using librarian, or set it with ;librarian add <held item name>.")
end

local function current_scroll_container()
    local saved_id = configured_scroll_container_id()
    if not saved_id then
        fail_with("No scroll container is saved. Use ;librarian scrollcontainer <item name>.")
    end

    for _, item in ipairs(inventory_items()) do
        if tostring(item.id) == saved_id then return item end
    end

    local name_hint = configured_scroll_container_name()
    fail_with("Saved scroll container #" .. saved_id ..
        (name_hint and (" (" .. name_hint .. ")") or "") ..
        " is not currently in inventory.")
end

local function grimoire_ref()
    return "#" .. tostring(current_grimoire().id)
end

--------------------------------------------------------------------------------
-- Game command helpers
--------------------------------------------------------------------------------

-- Drain the per-script line buffer after fput() has returned.
-- After fput() (prompt-wait), all game response lines should already be queued
-- in the buffer. We drain until 3 consecutive empty reads (~150ms idle) once
-- we have received at least one line, or until the timeout expires.
local function collect_lines_after_fput(timeout)
    local lines = {}
    local deadline = os.time() + (timeout or 5)
    local idle = 0

    while os.time() <= deadline do
        local line = get_noblock()
        if line then
            idle = 0
            table.insert(lines, line)
        else
            pause(0.05)
            idle = idle + 1
            if #lines > 0 and idle >= 3 then break end
        end
    end

    return lines
end

local function issue_grimoire_command(command, timeout)
    timeout = timeout or 5
    waitrt()
    clear()
    fput(command)

    local all_lines = collect_lines_after_fput(timeout)

    -- Filter: collect from PAGE_START_PAT onwards
    local lines = {}
    local found_start = false
    for _, line in ipairs(all_lines) do
        if not found_start then
            if string.find(line, PAGE_START_PAT) then
                found_start = true
                table.insert(lines, line)
            end
        else
            table.insert(lines, line)
        end
    end

    if #lines == 0 then
        fail_with("No grimoire output matched for '" .. command .. "'.")
    end

    return lines
end

local function capture_command_output(command, timeout)
    timeout = timeout or 5
    waitrt()
    clear()
    fput(command)
    return collect_lines_after_fput(timeout)
end

local function read_scroll_lines(item_id, timeout)
    waitrt()
    clear()
    fput("read #" .. tostring(item_id))

    local lines = {}
    local deadline = os.time() + (timeout or 6)
    local idle = 0

    while os.time() <= deadline do
        local line = get_noblock()
        if line then
            idle = 0
            table.insert(lines, line)
            -- Stop early on known failure patterns
            if line:match("^Read what%?$") or
               line:match("^What were you referring to%?$") or
               line:match("^You can't read that%.$") or
               line:match("^You cannot read that%.$") then
                break
            end
        else
            pause(0.05)
            idle = idle + 1
            if #lines > 0 and idle >= 3 then break end
        end
    end

    return lines
end

local function get_item_by_id(item_id, container_id, label)
    local item_id_text = tostring(item_id)

    -- Already held?
    for _, item in ipairs(held_items()) do
        if tostring(item.id) == item_id_text then
            echo("Already holding " .. label .. ".")
            return item
        end
    end

    local command
    if container_id then
        command = "get #" .. item_id_text .. " from #" .. tostring(container_id)
    else
        command = "get #" .. item_id_text
    end

    local result = fput(command,
        "You pick up", "You remove", "You pull", "You reach", "You grab",
        "You carefully remove", "You need", "You are already", "You can't",
        "Get what", "What were you referring to", "You have to empty your hands",
        "You are too injured", "You should unload")

    -- Wait for item to appear in hands
    for _ = 1, 20 do
        for _, item in ipairs(held_items()) do
            if tostring(item.id) == item_id_text then return item end
        end
        pause(0.1)
    end

    fail_with("Could not get " .. label .. ": the item did not move to hand.")
end

local function get_item_by_noun(noun, label)
    local stripped_noun = strip(noun or "")
    if stripped_noun == "" then
        fail_with("Could not get " .. label .. ": no saved noun is available.")
    end

    -- Already held?
    for _, item in ipairs(held_items()) do
        if lower(tostring(item.noun)) == lower(stripped_noun) then
            return item
        end
    end

    fput("get " .. stripped_noun,
        "You pick up", "You remove", "You pull", "You reach", "You grab",
        "You retrieve", "You carefully remove", "You need", "You are already",
        "You can't", "Get what", "What were you referring to",
        "You have to empty your hands", "You are too injured", "You should unload")

    -- Wait for item to appear in hands
    for _ = 1, 20 do
        for _, item in ipairs(held_items()) do
            if lower(tostring(item.noun)) == lower(stripped_noun) then return item end
        end
        pause(0.1)
    end

    fail_with("Could not get " .. label .. " by noun '" .. stripped_noun .. "': the item did not move to hand.")
end

local function put_item_in_container(item_id, container_id, container_name, label)
    fput("put #" .. tostring(item_id) .. " in #" .. tostring(container_id),
        "You put", "You slip", "You tuck", "You drop",
        "Put what", "What were you referring to",
        "You can't", "You cannot", "You need", "You must", "You have to")

    -- Poll until the item appears in the container (or timeout)
    local item_id_str = tostring(item_id)
    local container_id_str = tostring(container_id)
    for _ = 1, 20 do
        local all_containers = GameObj.containers()
        local c = all_containers[container_id_str]
        if c then
            for _, obj in ipairs(c) do
                if tostring(obj.id) == item_id_str then return true end
            end
        end
        pause(0.1)
    end
    -- Best-effort: item may still be on its way
    return true
end

--------------------------------------------------------------------------------
-- Grimoire page parsing
--------------------------------------------------------------------------------

local function parse_page(lines)
    local page_number = nil
    for _, line in ipairs(lines) do
        local pn = line:match(PAGE_NUMBER_PAT)
        if pn then
            page_number = tonumber(pn)
            break
        end
    end

    if not page_number then
        fail_with("Could not determine the current grimoire page from READ/TURN output.")
    end

    local slots = {}
    for _, raw_line in ipairs(lines) do
        local line = raw_line
        local selected = false

        -- Check for selection marker
        local stripped = line:match("^>%s*(.+)$") or line:match("^&gt;%s*(.+)$")
        if stripped then
            line = stripped
            selected = true
        end

        -- Try spell slot pattern
        local slot_num, spell_name, spell_num, charges = line:match(SLOT_SPELL_PAT)
        if slot_num then
            table.insert(slots, {
                page     = page_number,
                slot     = tonumber(slot_num),
                selected = selected,
                blank    = false,
                name     = spell_name,
                number   = tonumber(spell_num),
                charges  = tonumber(charges),
            })
        else
            -- Try blank slot pattern
            local blank_num = line:match(SLOT_BLANK_PAT)
            if blank_num then
                table.insert(slots, {
                    page     = page_number,
                    slot     = tonumber(blank_num),
                    selected = selected,
                    blank    = true,
                })
            end
        end
    end

    if #slots == 0 then
        fail_with("Could not parse spell slots on grimoire page " .. page_number .. ".")
    end

    local selected_slot = nil
    for _, slot in ipairs(slots) do
        if slot.selected then
            selected_slot = slot.slot
            break
        end
    end

    return {
        page          = page_number,
        slots         = slots,
        selected_slot = selected_slot,
    }
end

local function read_current_page()
    return parse_page(issue_grimoire_command("read " .. grimoire_ref()))
end

local function turn_page(page_number)
    local command
    if page_number then
        command = "turn " .. grimoire_ref() .. " to " .. tostring(page_number)
    else
        command = "turn " .. grimoire_ref()
    end
    return parse_page(issue_grimoire_command(command))
end

--------------------------------------------------------------------------------
-- Grimoire scanning
--------------------------------------------------------------------------------

local function build_spell_indices(all_slots)
    local by_number = {}
    local by_name   = {}

    for _, slot in ipairs(all_slots) do
        if not slot.blank then
            if not by_number[slot.number] then by_number[slot.number] = {} end
            table.insert(by_number[slot.number], slot)

            local lname = lower(slot.name)
            if not by_name[lname] then by_name[lname] = {} end
            table.insert(by_name[lname], slot)
        end
    end

    return by_number, by_name
end

local function scan_grimoire()
    current_grimoire() -- validate we have it

    local first_page = read_current_page()
    local page_map = {}
    page_map[first_page.page] = first_page.slots

    while true do
        local page_data = turn_page()
        if page_data.page == first_page.page then break end

        if page_map[page_data.page] then
            fail_with("Encountered grimoire page " .. page_data.page ..
                " twice before returning to page " .. first_page.page .. ".")
        end

        page_map[page_data.page] = page_data.slots
    end

    -- Collect page numbers sorted
    local page_numbers = {}
    for pn, _ in pairs(page_map) do
        table.insert(page_numbers, pn)
    end
    table.sort(page_numbers)

    -- Flatten all slots in page order
    local all_slots = {}
    for _, pn in ipairs(page_numbers) do
        for _, slot in ipairs(page_map[pn]) do
            table.insert(all_slots, slot)
        end
    end

    local by_number, by_name = build_spell_indices(all_slots)

    return {
        current_page          = first_page.page,
        current_selected_slot = first_page.selected_slot,
        page_map              = page_map,
        page_numbers          = page_numbers,
        slots                 = all_slots,
        spells_by_number      = by_number,
        spells_by_name        = by_name,
    }
end

--------------------------------------------------------------------------------
-- Slot listing / display
--------------------------------------------------------------------------------

local function list_slots(slots, header)
    echo(header)
    -- Sort by page then slot
    local sorted = {}
    for _, s in ipairs(slots) do table.insert(sorted, s) end
    table.sort(sorted, function(a, b)
        if a.page ~= b.page then return a.page < b.page end
        return a.slot < b.slot
    end)

    for _, slot in ipairs(sorted) do
        local marker = slot.selected and ">" or " "
        if slot.blank then
            echo(string.format("%s page %-2d slot %-2d Blank", marker, slot.page, slot.slot))
        else
            echo(string.format("%s page %-2d slot %-2d %-28s (%4d) %2d/%d",
                marker, slot.page, slot.slot, slot.name, slot.number, slot.charges, MAX_GRIMOIRE_CHARGES))
        end
    end
end

--------------------------------------------------------------------------------
-- Find / match helpers
--------------------------------------------------------------------------------

local function find_matches(state, query)
    local s = strip(query or "")
    if s == "" then return {} end

    if is_digit_string(s) then
        local num = tonumber(s)
        local matches = state.spells_by_number[num] or {}
        local sorted = {}
        for _, m in ipairs(matches) do table.insert(sorted, m) end
        table.sort(sorted, function(a, b)
            if a.page ~= b.page then return a.page < b.page end
            return a.slot < b.slot
        end)
        return sorted
    else
        local downcased = lower(s)
        local matches = {}
        for _, slot in ipairs(state.slots) do
            if not slot.blank and contains(lower(slot.name), downcased) then
                table.insert(matches, slot)
            end
        end
        table.sort(matches, function(a, b)
            if a.page ~= b.page then return a.page < b.page end
            return a.slot < b.slot
        end)
        return matches
    end
end

local function choose_find_target(matches, query)
    if #matches == 0 then return nil end
    if #matches == 1 then return matches[1] end

    local downcased = lower(strip(query or ""))
    if is_digit_string(downcased) then return nil end

    local exact_matches = {}
    for _, slot in ipairs(matches) do
        if lower(slot.name) == downcased then
            table.insert(exact_matches, slot)
        end
    end
    if #exact_matches == 1 then return exact_matches[1] end

    return nil
end

local function choose_grimoire_charge_target(state, spell_number)
    local matches = state.spells_by_number[spell_number] or {}
    if #matches == 0 then
        fail_with("Spell " .. spell_number .. " was not found in the grimoire.")
    end

    -- Sort by page, slot
    local sorted = {}
    for _, s in ipairs(matches) do table.insert(sorted, s) end
    table.sort(sorted, function(a, b)
        if a.page ~= b.page then return a.page < b.page end
        return a.slot < b.slot
    end)

    -- Find highest non-full charges (prefer highest charges, then lowest page/slot)
    local target = nil
    for _, slot in ipairs(sorted) do
        if slot.charges < MAX_GRIMOIRE_CHARGES then
            if not target or slot.charges > target.charges then
                target = slot
            end
        end
    end

    if not target then
        fail_with("Spell " .. spell_number .. " is already fully charged in every matching slot.")
    end

    return sorted, target
end

--------------------------------------------------------------------------------
-- Navigation within grimoire
--------------------------------------------------------------------------------

local function navigate_to_spell(target, cur_page)
    local page_data
    if cur_page == target.page then
        page_data = read_current_page()
    else
        page_data = turn_page(target.page)
    end

    local selected_slot = page_data.selected_slot
    if not selected_slot then
        fail_with("Could not determine the selected slot on page " .. target.page .. ".")
    end

    local slots_on_page = 0
    for _, slot in ipairs(page_data.slots) do
        if slot.slot > slots_on_page then slots_on_page = slot.slot end
    end
    if slots_on_page == 0 then
        fail_with("Could not determine slot count for page " .. target.page .. ".")
    end

    local ponders_needed = (target.slot - selected_slot) % slots_on_page
    for _ = 1, ponders_needed do
        waitrt()
        fput("ponder " .. grimoire_ref(), "You ponder over your")
    end

    -- Verify selection
    local verification = read_current_page()
    if verification.page ~= target.page or verification.selected_slot ~= target.slot then
        fail_with("Failed to select " .. target.name .. " (" .. target.number ..
            ") on page " .. target.page .. ", slot " .. target.slot .. ".")
    end

    return verification
end

--------------------------------------------------------------------------------
-- Scroll container scanning
--------------------------------------------------------------------------------

local function refresh_scroll_container_contents()
    local container = current_scroll_container()

    clear()
    fput("look in #" .. tostring(container.id))
    local look_lines = collect_lines_after_fput(4)

    -- Check if container is closed
    local is_closed = false
    for _, line in ipairs(look_lines) do
        if line:match("That is closed%.") then
            is_closed = true
            break
        end
    end

    if is_closed then
        waitrt()
        fput("open #" .. tostring(container.id),
            "You open", "That is already open", "You carefully open", "You unwrap", "You loosen")

        clear()
        fput("look in #" .. tostring(container.id))
        look_lines = collect_lines_after_fput(4)
    end

    -- Check if empty
    local is_empty = false
    for _, line in ipairs(look_lines) do
        if line:match("There is nothing in there%.") then
            is_empty = true
            break
        end
    end

    if is_empty then return container, {} end

    -- Wait for GameObj.containers() to reflect the look-in response
    local contents = nil
    for _ = 1, 20 do
        local all_containers = GameObj.containers()
        local c = all_containers[tostring(container.id)]
        if c and type(c) == "table" and #c > 0 then
            contents = c
            break
        end
        pause(0.1)
    end

    if not contents then contents = {} end

    return container, contents
end

local function parse_scroll_read(item, lines)
    local has_start = false
    local has_header = false
    for _, line in ipairs(lines) do
        if line:match(SCROLL_READ_START_PAT) then has_start = true end
        if line:match(SCROLL_READ_HEADER_PAT) then has_header = true end
    end

    if not has_start or not has_header then return nil end

    local spells = {}
    for _, line in ipairs(lines) do
        local num, rest = line:match(SCROLL_SPELL_LINE_PAT)
        if num then
            local vibrant = rest:find(VIBRANT_INK_SUFFIX, 1, true) ~= nil
            local name
            if vibrant then
                name = strip(rest:sub(1, #rest - #VIBRANT_INK_SUFFIX))
            else
                name = strip(rest:gsub("%.%s*$", ""))
            end
            table.insert(spells, {
                number          = tonumber(num),
                name            = name,
                spell_knowledge = vibrant,
            })
        end
    end

    if #spells == 0 then return nil end

    return {
        id     = tostring(item.id),
        name   = tostring(item.name),
        noun   = tostring(item.noun),
        spells = spells,
    }
end

local function scan_scroll_container()
    local container, contents = refresh_scroll_container_contents()
    local scanned_scrolls = {}
    local skipped_items = {}

    for _, item in ipairs(contents) do
        local lines = read_scroll_lines(item.id, 6)
        local parsed = parse_scroll_read(item, lines)
        if parsed then
            table.insert(scanned_scrolls, parsed)
        else
            table.insert(skipped_items, item)
        end
    end

    -- Build spell indices
    local regular = {}
    local spell_knowledge = {}

    for _, scroll in ipairs(scanned_scrolls) do
        for _, spell in ipairs(scroll.spells) do
            local target_map = spell.spell_knowledge and spell_knowledge or regular
            if not target_map[spell.number] then
                target_map[spell.number] = { count = 0, name = nil, scrolls = {} }
            end
            local entry = target_map[spell.number]
            entry.count = entry.count + 1
            entry.name = spell.name

            local already_has = false
            for _, s in ipairs(entry.scrolls) do
                if s.id == scroll.id then already_has = true; break end
            end
            if not already_has then
                table.insert(entry.scrolls, { id = scroll.id, name = scroll.name })
            end
        end
    end

    return {
        container             = container,
        scanned_scrolls       = scanned_scrolls,
        skipped_items         = skipped_items,
        regular_spells        = regular,
        spell_knowledge_spells = spell_knowledge,
    }
end

-- container_id is optional; when provided, scroll names become clickable command links.
local function echo_spell_table(title, spells, container_id)
    echo(title)
    -- Check if table is empty
    local has_any = false
    for _ in pairs(spells) do has_any = true; break end
    if not has_any then
        echo("  none")
        return
    end

    -- Collect and sort spell numbers
    local numbers = {}
    for num in pairs(spells) do table.insert(numbers, num) end
    table.sort(numbers)

    for _, number in ipairs(numbers) do
        local spell = spells[number]
        if container_id and Messaging and Messaging.make_cmd_link then
            -- Build clickable links for each source scroll
            local scroll_links = {}
            for _, s in ipairs(spell.scrolls) do
                local cmd = "get #" .. s.id .. " from #" .. tostring(container_id)
                table.insert(scroll_links, Messaging.make_cmd_link(s.name, cmd))
            end
            -- xml_encode the plain text portions; embed raw link XML between them
            local prefix = xml_encode(string.format("  (%4d) %-28s x%-2d [",
                number, spell.name, spell.count))
            local suffix = xml_encode("]")
            echo(prefix .. table.concat(scroll_links, ", ") .. suffix)
        else
            local scroll_names = {}
            for _, s in ipairs(spell.scrolls) do
                table.insert(scroll_names, s.name)
            end
            echo(string.format("  (%4d) %-28s x%-2d [%s]",
                number, spell.name, spell.count, table.concat(scroll_names, ", ")))
        end
    end
end

local function scroll_spell_entries(scanned_scrolls, is_spell_knowledge)
    local entries = {}
    for _, scroll in ipairs(scanned_scrolls) do
        for _, spell in ipairs(scroll.spells) do
            if spell.spell_knowledge == is_spell_knowledge then
                table.insert(entries, {
                    scroll_id    = scroll.id,
                    scroll_name  = scroll.name,
                    spell_number = spell.number,
                    spell_name   = spell.name,
                })
            end
        end
    end
    table.sort(entries, function(a, b)
        local la = lower(a.spell_name)
        local lb = lower(b.spell_name)
        if la ~= lb then return la < lb end
        local sa = lower(a.scroll_name)
        local sb = lower(b.scroll_name)
        if sa ~= sb then return sa < sb end
        return a.spell_number < b.spell_number
    end)
    return entries
end

local function find_scroll_spell_matches(entries, query)
    local s = strip(query or "")
    if s == "" then return {} end

    if is_digit_string(s) then
        local num = tonumber(s)
        local matches = {}
        for _, entry in ipairs(entries) do
            if entry.spell_number == num then
                table.insert(matches, entry)
            end
        end
        return matches
    else
        local downcased = lower(s)
        local matches = {}
        for _, entry in ipairs(entries) do
            if contains(lower(entry.spell_name), downcased) then
                table.insert(matches, entry)
            end
        end
        return matches
    end
end

local function dedupe_scroll_spell_matches(matches)
    local seen = {}
    local unique = {}
    for _, entry in ipairs(matches) do
        if not seen[entry.scroll_id] then
            seen[entry.scroll_id] = true
            table.insert(unique, entry)
        end
    end
    return unique
end

local function choose_scroll_spell_target(matches, query)
    if #matches == 0 then return nil end
    if #matches == 1 then return matches[1] end

    local downcased = lower(strip(query or ""))
    if is_digit_string(downcased) then return matches[1] end

    for _, entry in ipairs(matches) do
        if lower(entry.spell_name) == downcased then return entry end
    end

    return matches[1]
end

--------------------------------------------------------------------------------
-- Chargeable spell targets (for charge all)
--------------------------------------------------------------------------------

local function chargeable_spell_targets(state, scroll_result)
    local entries = scroll_spell_entries(scroll_result.scanned_scrolls, false)
    local seen_numbers = {}
    local available_numbers = {}
    for _, entry in ipairs(entries) do
        if not seen_numbers[entry.spell_number] then
            seen_numbers[entry.spell_number] = true
            table.insert(available_numbers, entry.spell_number)
        end
    end

    local targets = {}
    for _, spell_number in ipairs(available_numbers) do
        local matches = state.spells_by_number[spell_number]
        if matches and #matches > 0 then
            local best = nil
            for _, slot in ipairs(matches) do
                if slot.charges < MAX_GRIMOIRE_CHARGES then
                    if not best or slot.charges > best.charges then
                        best = slot
                    end
                end
            end
            if best then table.insert(targets, best) end
        end
    end

    table.sort(targets, function(a, b)
        if a.page ~= b.page then return a.page < b.page end
        if a.slot ~= b.slot then return a.slot < b.slot end
        return a.number < b.number
    end)

    return targets
end

--------------------------------------------------------------------------------
-- Command handlers
--------------------------------------------------------------------------------

local function handle_list()
    local state = scan_grimoire()
    list_slots(state.slots, "Scanned " .. #state.page_numbers .. " grimoire page(s).")
end

local function handle_find(query)
    if strip(query) == "" then
        fail_with("Usage: ;librarian find <partial spell name or number>")
    end

    local state = scan_grimoire()
    local matches = find_matches(state, query)
    local target = choose_find_target(matches, query)

    if #matches == 0 then
        fail_with("No grimoire spell matched '" .. query .. "'.")
    elseif not target then
        list_slots(matches, "Multiple grimoire spells matched '" .. query .. "'.")
        fail_with("Refine the spell name or use the exact spell number.")
    end

    navigate_to_spell(target, state.current_page)
    echo("Selected " .. target.name .. " (" .. target.number .. ") on page " ..
        target.page .. ", slot " .. target.slot .. " with " .. target.charges .. " charges.")
end

local function handle_clean(spell_number_text)
    if not spell_number_text or not is_digit_string(strip(spell_number_text)) then
        fail_with("Usage: ;librarian clean <spell number>")
    end

    local spell_number = tonumber(spell_number_text)
    local state = scan_grimoire()
    local matches, target = choose_grimoire_charge_target(state, spell_number)

    if #matches > 1 then
        echo("Found " .. #matches .. " copies of spell " .. spell_number ..
            "; targeting page " .. target.page .. ", slot " .. target.slot ..
            " at " .. target.charges .. " charges.")
    end

    navigate_to_spell(target, state.current_page)
    local before_charges = target.charges

    -- Issue clean command
    local clean_command = "clean " .. grimoire_ref()
    local clean_output = capture_command_output(clean_command, 8)
    local clean_text = table.concat(clean_output, " ")

    -- Check for confirm prompt
    if string.find(clean_text, TRANSFER_CONFIRM_PAT, 1, true) then
        local confirm_output = capture_command_output(clean_command, 8)
        local confirm_text = table.concat(confirm_output, " ")
        if confirm_text ~= "" then
            clean_text = clean_text .. " " .. confirm_text
        end
    end

    -- Rescan to verify
    local updated_state = scan_grimoire()
    local updated_slot = nil
    local updated_matches = updated_state.spells_by_number[spell_number] or {}
    for _, slot in ipairs(updated_matches) do
        if slot.page == target.page and slot.slot == target.slot then
            updated_slot = slot
            break
        end
    end

    if not updated_slot then
        fail_with("Unable to verify the updated charges for spell " .. spell_number .. ".")
    end

    if updated_slot.charges > before_charges then
        echo("Cleaned " .. updated_slot.name .. " (" .. spell_number .. ") on page " ..
            updated_slot.page .. ", slot " .. updated_slot.slot ..
            ": " .. before_charges .. " -> " .. updated_slot.charges .. " charges.")
        if clean_text ~= "" then echo(clean_text) end
    else
        if string.find(clean_text, CLEAN_COOLDOWN_PAT, 1, true) then
            echo("Clean is on cooldown: " .. clean_text)
        elseif string.find(lower(clean_text), "already") or
               string.find(lower(clean_text), "again tomorrow") or
               string.find(lower(clean_text), "once per day") or
               string.find(lower(clean_text), "daily") or
               string.find(lower(clean_text), "used") or
               string.find(lower(clean_text), "today") then
            echo("Clean appears to be unavailable right now for " ..
                updated_slot.name .. " (" .. spell_number .. "): " .. clean_text)
        elseif clean_text == "" then
            echo("No charge change detected for " .. updated_slot.name ..
                " (" .. spell_number .. ") on page " .. updated_slot.page ..
                ", slot " .. updated_slot.slot ..
                ". Clean may be on cooldown or the grimoire output may have changed.")
        else
            echo("No charge change detected for " .. updated_slot.name ..
                " (" .. spell_number .. ") on page " .. updated_slot.page ..
                ", slot " .. updated_slot.slot .. ": " .. clean_text)
        end
    end
end

local function charge_single_spell(spell_number)
    local test_mode = charge_test_mode_enabled()
    local state = scan_grimoire()
    local matches, target = choose_grimoire_charge_target(state, spell_number)

    if #matches > 1 then
        echo("Found " .. #matches .. " copies of spell " .. spell_number ..
            "; targeting page " .. target.page .. ", slot " .. target.slot ..
            " at " .. target.charges .. " charges.")
    end

    navigate_to_spell(target, state.current_page)
    local before_charges = target.charges

    -- Scan scroll container for matching regular scrolls
    local scroll_result = scan_scroll_container()
    local entries = scroll_spell_entries(scroll_result.scanned_scrolls, false)
    local scroll_matches = dedupe_scroll_spell_matches(
        find_scroll_spell_matches(entries, tostring(spell_number)))

    if #scroll_matches == 0 then
        fail_with("No regular scroll matched spell " .. spell_number ..
            " in " .. tostring(scroll_result.container.name) .. ".")
    end

    local scroll_target = choose_scroll_spell_target(scroll_matches, tostring(spell_number))
    if #scroll_matches > 1 then
        echo("Found " .. #scroll_matches .. " regular scroll entries for " ..
            scroll_target.spell_name .. " (" .. spell_number ..
            "); getting " .. scroll_target.scroll_name .. ".")
    end

    local scroll_container = scroll_result.container
    get_item_by_id(scroll_target.scroll_id, scroll_container.id, scroll_target.scroll_name)

    local transfer_command = "transfer " .. spell_number .. " " .. grimoire_ref()
    local outcome = nil

    -- Use pcall to ensure scroll is returned even on error
    local ok, err = pcall(function()
        -- First transfer attempt
        local confirmation_lines = capture_command_output(transfer_command, 8)
        local confirmation_text = table.concat(confirmation_lines, " ")

        if confirmation_text == "" then
            fail_with("Transfer setup failed for spell " .. spell_number ..
                ": no matching transfer response was captured.")
        end

        if string.find(confirmation_text, TRANSFER_CONFIRM_PAT, 1, true) then
            if test_mode then
                echo("Charge test mode: would now confirm transfer with '" .. transfer_command .. "'.")
                outcome = "test_mode"
                return
            end

            -- Confirm the transfer
            local second_lines = capture_command_output(transfer_command, 8)
            local second_text = table.concat(second_lines, " ")

            if second_text == "" then
                fail_with("Transfer confirmation failed for spell " .. spell_number ..
                    ": no matching transfer response was captured.")
            end

            -- Check confirmation response for failures
            for _, pat in ipairs(TRANSFER_FAILURE_PATS) do
                if string.find(second_text, pat, 1, true) then
                    echo("Transfer confirmation failed for spell " .. spell_number .. ": " .. second_text)
                    outcome = "no_change"
                    return
                end
            end
        end

        -- Check for failure patterns in first response
        for _, pat in ipairs(TRANSFER_FAILURE_PATS) do
            if string.find(confirmation_text, pat, 1, true) then
                echo("Transfer failed for spell " .. spell_number .. ": " .. confirmation_text)
                outcome = "no_change"
                return
            end
        end

        if outcome == "test_mode" then return end

        -- Rescan to verify
        local updated_state = scan_grimoire()
        local updated_slot = nil
        local updated_matches = updated_state.spells_by_number[spell_number] or {}
        for _, slot in ipairs(updated_matches) do
            if slot.page == target.page and slot.slot == target.slot then
                updated_slot = slot
                break
            end
        end

        if not updated_slot then
            fail_with("Unable to verify the updated charges for spell " .. spell_number .. ".")
        end

        if updated_slot.charges > before_charges then
            echo("Charged " .. updated_slot.name .. " (" .. spell_number .. ") on page " ..
                updated_slot.page .. ", slot " .. updated_slot.slot ..
                ": " .. before_charges .. " -> " .. updated_slot.charges .. " charges.")
            outcome = "charged"
        else
            echo("No charge change detected for " .. updated_slot.name ..
                " (" .. spell_number .. ") during transfer.")
            outcome = "no_change"
        end
    end)

    -- Return scroll to container regardless of outcome
    local held_scroll = nil
    for _, item in ipairs(held_items()) do
        if tostring(item.id) == tostring(scroll_target.scroll_id) then
            held_scroll = item
            break
        end
    end
    if held_scroll then
        put_item_in_container(scroll_target.scroll_id,
            scroll_container.id, tostring(scroll_container.name),
            scroll_target.scroll_name)
    end

    if not ok then error(err, 0) end

    return outcome
end

local function handle_charge_all()
    local test_mode = charge_test_mode_enabled()
    local results = { charged = 0, test_mode = 0, no_change = 0, failed = 0 }
    local blocked_numbers = {}
    local guard = 0
    local started = false

    while true do
        guard = guard + 1
        if guard > 100 then
            fail_with("Charge all stopped after 100 attempts. The charge loop did not converge.")
        end

        local state = scan_grimoire()
        local scroll_result = scan_scroll_container()
        local targets = chargeable_spell_targets(state, scroll_result)

        -- Remove blocked spell numbers
        local filtered = {}
        for _, t in ipairs(targets) do
            if not blocked_numbers[t.number] then
                table.insert(filtered, t)
            end
        end
        targets = filtered

        if not started then
            if #targets == 0 then
                echo("No grimoire spells are both under " .. MAX_GRIMOIRE_CHARGES ..
                    " charges and available on regular scrolls in " ..
                    tostring(scroll_result.container.name) .. ".")
                return
            end
            if test_mode then
                echo("Attempting one test charge per eligible spell number.")
            else
                echo("Attempting to charge eligible spells until matching regular scrolls run out or the book slots are full.")
            end
            started = true
        end

        if #targets == 0 then break end

        local t = targets[1]
        local charge_ok, charge_err = pcall(function()
            local out = charge_single_spell(t.number)
            results[out or "no_change"] = (results[out or "no_change"] or 0) + 1
            if out ~= "charged" then
                blocked_numbers[t.number] = true
            end
        end)

        if not charge_ok then
            results.failed = results.failed + 1
            blocked_numbers[t.number] = true
            echo("Charge failed for " .. (t.name or "?") .. " (" .. t.number .. "): " ..
                tostring(charge_err))
        end
    end

    echo("Charge all complete: " .. results.charged .. " charged, " ..
        results.test_mode .. " test-only, " .. results.no_change ..
        " no change, " .. results.failed .. " failed.")
end

local function handle_charge(spell_number_text)
    local s = lower(strip(spell_number_text or ""))
    if s == "all" then
        handle_charge_all()
        return
    end

    if not is_digit_string(s) then
        fail_with("Usage: ;librarian charge <spell number>|all")
    end

    charge_single_spell(tonumber(s))
end

local function handle_testmode(arg)
    local s = lower(strip(arg or ""))

    if s == "" or s == "status" then
        echo("Charge test mode is " .. (charge_test_mode_enabled() and "ON" or "OFF") .. ".")
    elseif s == "on" or s == "true" or s == "1" or s == "enable" or s == "enabled" then
        save_charge_test_mode(true)
        echo("Charge test mode enabled.")
    elseif s == "off" or s == "false" or s == "0" or s == "disable" or s == "disabled" then
        save_charge_test_mode(false)
        echo("Charge test mode disabled.")
    elseif s == "toggle" then
        local enabled = not charge_test_mode_enabled()
        save_charge_test_mode(enabled)
        echo("Charge test mode " .. (enabled and "enabled" or "disabled") .. ".")
    else
        fail_with("Usage: ;librarian testmode <on|off|status|toggle>")
    end
end

local function handle_booknoun(arg)
    local s = lower(strip(arg or ""))

    if s == "" or s == "status" then
        echo("Default grimoire noun is '" .. configured_default_grimoire_noun() .. "'.")
        return
    end

    save_default_grimoire_noun(s)
    echo("Default grimoire noun set to '" .. s .. "'.")
end

local function handle_add(query)
    local item = find_held_item(query)
    if not item then
        fail_with("Hold the grimoire first, then run ;librarian add <held item name>.")
    end

    save_grimoire(item)
    echo("Saved " .. tostring(item.name) .. " as librarian grimoire #" .. tostring(item.id) .. ".")
end

local function handle_scrollcontainer(query)
    local item = find_inventory_item(query)
    save_scroll_container(item)
    echo("Saved " .. tostring(item.name) .. " as librarian scroll container #" .. tostring(item.id) .. ".")
end

local function handle_scrolls()
    local result = scan_scroll_container()
    local container = result.container

    echo("Scanned " .. #result.scanned_scrolls .. " readable scroll(s) in " .. tostring(container.name) .. ".")
    echo_spell_table("Regular scroll spells:", result.regular_spells, container.id)
    echo_spell_table("Spell knowledge scroll spells:", result.spell_knowledge_spells, container.id)

    if #result.skipped_items > 0 then
        local names = {}
        local seen = {}
        for _, item in ipairs(result.skipped_items) do
            local n = tostring(item.name)
            if not seen[n] then
                seen[n] = true
                table.insert(names, n)
            end
        end
        table.sort(names)
        echo("Skipped non-scroll or unreadable items: " .. table.concat(names, ", "))
    end
end

local function handle_sell_sk_scrolls()
    local result = scan_scroll_container()
    local container = result.container

    local sk_scrolls = {}
    for _, scroll in ipairs(result.scanned_scrolls) do
        for _, spell in ipairs(scroll.spells) do
            if spell.spell_knowledge then
                table.insert(sk_scrolls, scroll)
                break
            end
        end
    end

    table.sort(sk_scrolls, function(a, b)
        return lower(a.name) < lower(b.name)
    end)

    if #sk_scrolls == 0 then
        echo("No spell knowledge scrolls found in " .. tostring(container.name) .. ".")
        return
    end

    echo("Selling " .. #sk_scrolls .. " spell knowledge scroll(s) from " .. tostring(container.name) .. ".")

    for _, scroll in ipairs(sk_scrolls) do
        get_item_by_id(scroll.id, container.id, scroll.name)
        local sell_lines = capture_command_output("sell #" .. scroll.id, 6)
        local sell_text = table.concat(sell_lines, " ")
        if sell_text ~= "" then
            echo(scroll.name .. ": " .. sell_text)
        else
            echo(scroll.name .. ": (no sell response)")
        end
    end
end

local function handle_get(args)
    local noun = lower(args[1] or "")

    if noun == "book" or noun == "grimoire" or noun == "grim" then
        local saved_id = configured_grimoire_id()
        if not saved_id then
            fail_with("No grimoire is saved. Use ;librarian add <held item name>.")
        end

        local label = configured_grimoire_name() or "saved grimoire"

        -- Find which container holds the grimoire (if any)
        local grimoire_container_id = nil
        local all_containers = GameObj.containers()
        for cid, items in pairs(all_containers) do
            for _, obj in ipairs(items) do
                if tostring(obj.id) == tostring(saved_id) then
                    grimoire_container_id = cid
                    break
                end
            end
            if grimoire_container_id then break end
        end

        local get_ok, get_err = pcall(function()
            get_item_by_id(saved_id, grimoire_container_id, label)
        end)

        if not get_ok then
            -- Fall back to noun-based retrieval
            local fallback_noun = strip(configured_grimoire_noun() or "")
            if fallback_noun == "" then
                fallback_noun = configured_default_grimoire_noun()
            end

            local item = get_item_by_noun(fallback_noun, label)
            if item then save_grimoire(item) end
        end

        echo("Got " .. label .. ".")

    elseif noun == "scroll" or noun == "skscroll" then
        local query_parts = {}
        for i = 2, #args do table.insert(query_parts, args[i]) end
        local query = table.concat(query_parts, " ")

        if strip(query) == "" then
            fail_with("Usage: ;librarian get " .. noun .. " <partial spell name or number>")
        end

        local result = scan_scroll_container()
        local is_sk = noun == "skscroll"
        local entries = scroll_spell_entries(result.scanned_scrolls, is_sk)
        local scroll_matches = dedupe_scroll_spell_matches(find_scroll_spell_matches(entries, query))

        if #scroll_matches == 0 then
            fail_with("No " .. (is_sk and "spell knowledge" or "regular") ..
                " scroll matched '" .. query .. "'.")
        end

        local scroll_target = choose_scroll_spell_target(scroll_matches, query)
        if #scroll_matches > 1 then
            echo("Found " .. #scroll_matches .. " matching " ..
                (is_sk and "spell knowledge" or "regular") ..
                " scroll entries; getting " .. scroll_target.scroll_name ..
                " for " .. scroll_target.spell_name ..
                " (" .. scroll_target.spell_number .. ").")
        end

        get_item_by_id(scroll_target.scroll_id, result.container.id, scroll_target.scroll_name)
        echo("Got " .. scroll_target.scroll_name ..
            " for " .. scroll_target.spell_name ..
            " (" .. scroll_target.spell_number .. ").")

    else
        fail_with("Usage: ;librarian get book | ;librarian get scroll <spell> | ;librarian get skscroll <spell>")
    end
end

local function handle_memory_dump()
    local state = scan_grimoire()
    echo("In-memory grimoire state:")
    echo("Pages: " .. table.concat(state.page_numbers, ", "))
    echo("Total slots: " .. #state.slots)
    for _, slot in ipairs(state.slots) do
        if slot.blank then
            echo(string.format("  page %d slot %d: blank", slot.page, slot.slot))
        else
            echo(string.format("  page %d slot %d: %s (%d) %d charges%s",
                slot.page, slot.slot, slot.name, slot.number, slot.charges,
                slot.selected and " [SELECTED]" or ""))
        end
    end
    local sc_id = CharSettings[SCROLL_CONTAINER_ID_SETTING]
    local sc_name = CharSettings[SCROLL_CONTAINER_NAME_SETTING]
    if sc_id then
        echo("Saved scroll container: " .. (sc_name or "?") .. " #" .. sc_id)
    end
    echo("Charge test mode: " .. (charge_test_mode_enabled() and "ON" or "OFF"))
end

local function show_help()
    echo("Usage:")
    echo("Setup:")
    echo("  1. Hold your grimoire.")
    echo("  2. ;librarian add <held item name>")
    echo("  3. ;librarian scrollcontainer <item name>")
    echo("  4. ;librarian scrolls")
    echo("  5. Optional: ;librarian testmode on")
    echo(";librarian")
    echo(";librarian list")
    echo(";librarian scan")
    echo(";librarian find <partial spell name or number>")
    echo(";librarian clean <spell number>")
    echo(";librarian charge <spell number>")
    echo(";librarian charge all")
    echo(";librarian testmode <on|off|status|toggle>")
    echo(";librarian booknoun <noun|status>")
    echo(";librarian add <held item name>")
    echo(";librarian scrollcontainer <item name>")
    echo(";librarian scrolls")
    echo(";librarian sellskscrolls")
    echo(";librarian get book")
    echo(";librarian get scroll <partial spell name or number>")
    echo(";librarian get skscroll <partial spell name or number>")
    echo(";librarian memory")
    echo(";librarian dump")
    echo("The script expects the saved grimoire to be held in either hand.")
end

--------------------------------------------------------------------------------
-- Main dispatch
--------------------------------------------------------------------------------

local args = split_args(Script.vars[0] or "")
-- Remove script name from args if present
if #args > 0 and lower(args[1]) == "librarian" then
    table.remove(args, 1)
end

local command = lower(args[1] or "")

local function rest_args(start_idx)
    local parts = {}
    for i = start_idx, #args do
        table.insert(parts, args[i])
    end
    return table.concat(parts, " ")
end

local ok, err = pcall(function()
    if command == "" or command == "list" or command == "scan" then
        handle_list()
    elseif command == "add" then
        handle_add(rest_args(2))
    elseif command == "scrollcontainer" then
        handle_scrollcontainer(rest_args(2))
    elseif command == "scrolls" then
        handle_scrolls()
    elseif command == "sellskscrolls" then
        handle_sell_sk_scrolls()
    elseif command == "get" then
        local sub_args = {}
        for i = 2, #args do table.insert(sub_args, args[i]) end
        handle_get(sub_args)
    elseif command == "find" then
        handle_find(rest_args(2))
    elseif command == "clean" then
        handle_clean(args[2])
    elseif command == "charge" then
        handle_charge(rest_args(2))
    elseif command == "testmode" then
        handle_testmode(args[2])
    elseif command == "booknoun" then
        handle_booknoun(rest_args(2))
    elseif command == "memory" or command == "dump" then
        handle_memory_dump()
    elseif command == "help" or command == "--help" or command == "-h" then
        show_help()
    else
        fail_with("Unknown librarian command '" .. command .. "'. Try ';librarian help'.")
    end
end)

if not ok then
    echo(tostring(err))
end
