--- @revenant-script
--- name: attunecheck
--- version: 1.0.0
--- author: elanthia-online
--- game: gs
--- description: Scan worn items and containers for attuned/account-restricted items
--- tags: items,attuned
---
--- Changelog (from Lich5):
---   v1.0.0 (2026-01-06)
---     - initial release

--------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------

local ATTUNED_PATTERN           = "^    This item is restricted to use by "
local ACCOUNT_RESTRICTED_PATTERN = " is restricted to this account%."
local LORESONG_PATTERN          = "^It has a permanently unlocked loresong by "

local RECALL_RESPONSES = {
    "^You are unable to recall ",
    "^As you recall ",
}

local ANALYZE_RESPONSES = {
    "^You analyze ",
}

local CONTAINER_SKIP_TYPES_RE = Regex.new("\\b(?:gem|box)\\b")
local CONTAINER_INVALID_TYPES_RE = Regex.new("\\b(?:jewelry|weapon|armor|uncommon)\\b")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local attuned_items = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

local function any_line_matches(lines, pattern)
    for _, line in ipairs(lines) do
        if string.find(line, pattern) then
            return true
        end
    end
    return false
end

--- Issue a command and collect lines until a terminator pattern is seen.
local function issue_command(cmd, terminators)
    clear()
    put(cmd)
    local lines = {}
    local deadline = os.time() + 5
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            lines[#lines + 1] = line
            for _, term in ipairs(terminators) do
                if string.find(line, term) then
                    return lines
                end
            end
        else
            pause(0.05)
        end
    end
    return lines
end

--------------------------------------------------------------------------------
-- Attunement checks
--------------------------------------------------------------------------------

local function check_recall_attunement(item)
    waitrt()
    local results = issue_command("recall #" .. item.id, RECALL_RESPONSES)

    if any_line_matches(results, ATTUNED_PATTERN) then
        if not table_contains(attuned_items, item) then
            attuned_items[#attuned_items + 1] = item
        end
        return true
    end

    -- If loresong, skip further analysis
    if any_line_matches(results, LORESONG_PATTERN) then
        return true
    end

    return false
end

local function check_analyze_attunement(item)
    waitrt()
    local results = issue_command("analyze #" .. item.id, ANALYZE_RESPONSES)

    if any_line_matches(results, ACCOUNT_RESTRICTED_PATTERN) then
        if not table_contains(attuned_items, item) then
            attuned_items[#attuned_items + 1] = item
        end
        return true
    end

    return false
end

local function check_item_attunement(item)
    if check_recall_attunement(item) then return end
    check_analyze_attunement(item)
end

--------------------------------------------------------------------------------
-- Container handling
--------------------------------------------------------------------------------

local function skip_container(item)
    if not item.type or item.type == "" then return true end
    if CONTAINER_INVALID_TYPES_RE:test(item.type) then return true end
    return false
end

local function populate_container(item)
    -- Try to open it
    waitrt()
    local open_lines = issue_command("open #" .. item.id, {
        "That is already open",
        "There doesn't seem to be any way to do that%.",
        "exposeContainer",
        "container",
    })
    for _, line in ipairs(open_lines) do
        if string.find(line, "There doesn't seem to be any way to do that") then
            return
        end
    end

    -- Look inside to populate contents
    waitrt()
    issue_command("look in #" .. item.id, {
        "exposeContainer",
        "dialogData",
        "container",
        "you glance",
        "There is nothing",
    })

    -- Wait briefly for contents to propagate
    pause(0.5)
end

--------------------------------------------------------------------------------
-- Main scan
--------------------------------------------------------------------------------

-- Scan worn inventory items
local inv = GameObj.inv()
echo("Scanning " .. #inv .. " inventory items...")

for _, item in ipairs(inv) do
    if item then
        check_item_attunement(item)
    end
end

-- Populate containers
echo("Populating containers...")
for _, item in ipairs(inv) do
    if not skip_container(item) then
        -- Only populate if contents not already known
        if not item.contents then
            populate_container(item)
        end
    end
end
echo("Containers populated!")

-- Scan container contents
for _, item in ipairs(inv) do
    local contents = item.contents
    if contents and type(contents) == "table" then
        echo("Scanning " .. #contents .. " items in " .. item.name .. "...")
        for _, child_item in ipairs(contents) do
            if child_item and child_item.type then
                if not CONTAINER_SKIP_TYPES_RE:test(child_item.type) then
                    check_item_attunement(child_item)
                end
            end
        end
    end
end

-- Display results
echo("Found " .. #attuned_items .. " attuned item(s):")
for _, item in ipairs(attuned_items) do
    local in_inv = false
    for _, inv_item in ipairs(inv) do
        if inv_item.id == item.id then
            in_inv = true
            break
        end
    end

    if in_inv then
        respond("Attuned: " .. item.name .. " - <d cmd='remove #" .. item.id .. "'>remove</d>")
    else
        respond("Attuned: " .. item.name .. " - <d cmd='get #" .. item.id .. "'>get</d>")
    end
end
