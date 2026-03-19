--- Inventory helpers for bounty item lookup and manipulation.

local M = {}

-- NPC patterns for bounty turn-in validation
M.BOUNTY_TURNIN_NPC_PATTERN = "brother Barnstel|scarred Agarnil kris|healer|herbalist|merchant Kelph|famed baker Leaftoe|Akrash|old Mistress Lomara|dwarven clerk|gem dealer|jeweler|Zirconia|town guard|Gate guard|sergeant|city guardsman|Guardsman|purser|Belle|furrier|Guild Taskmaster|sentry luthrek|fur trader Delosa|bramblefist|Halfwhistle|tavernkeeper|tavern|brindlestoat|Libram Greenleaf|Sparkfinger|Maraene|alchemist"
M.GEM_TURNIN_NPC_PATTERN = "gem dealer|jeweler|brindlestoat|zirconia"

local bounty_npc_re = Regex.new(M.BOUNTY_TURNIN_NPC_PATTERN .. "|" .. M.GEM_TURNIN_NPC_PATTERN)
local gem_npc_re = Regex.new(M.GEM_TURNIN_NPC_PATTERN)

-- Blocked gemshop room IDs and UIDs
M.BLOCKED_GEMSHOP_ROOM_IDS = { [3845] = true }
M.BLOCKED_GEMSHOP_UIDS = { ["3201285"] = true }
M.BLOCKED_GEMSHOP_TITLE_PATTERN = Regex.new("Etaenia's Jewels")

M.GEMSHOP_UID_BY_TOWN = {
    ["Cold River"] = "u7503259",
}

M.IGNORED_GEM_CONTAINERS = {
    ["rectangular green crystal bottle"] = true,
    ["squat pale blue crystal bottle"] = true,
    ["squat pale grey crystal bottle"] = true,
}

M.TURNIN_SCRIPTS_TO_STOP = {
    bigshot = true, eloot = true, go2 = true, hunt3 = true, hunt3_v2 = true,
}

--- Check if an NPC is an invalid turn-in target (dead, companion, familiar, etc.).
function M.npc_is_invalid(npc)
    if not npc then return true end
    local status = (npc.status or ""):lower()
    local ntype = (npc.type or ""):lower()
    local name = (npc.name or ""):lower()

    if status:find("dead") or status:find("gone") then return true end
    if ntype:find("companion") or ntype:find("familiar") or ntype:find("pet") then return true end
    if name:find("familiar") then return true end
    if name:find("animated") and not name:find("animated slush") then return true end
    return false
end

--- Find an NPC matching the bounty turn-in pattern.
function M.find_bounty_npc()
    for _, npc in ipairs(GameObj.npcs()) do
        if not M.npc_is_invalid(npc) and bounty_npc_re:test(npc.name or "") then
            return npc
        end
    end
    return nil
end

--- Find the Guild Taskmaster NPC.
function M.find_guild_taskmaster()
    for _, npc in ipairs(GameObj.npcs()) do
        if not M.npc_is_invalid(npc) then
            local name = npc.name or ""
            if name:find("Guild Taskmaster") or name:find("taskmaster") then
                return npc
            end
        end
    end
    return nil
end

--- Find an adventurer guard NPC.
function M.find_advguard_npc(turnin_npc_name)
    -- Try specific NPC name first
    if turnin_npc_name and turnin_npc_name ~= "" then
        for _, npc in ipairs(GameObj.npcs()) do
            if not M.npc_is_invalid(npc) and (npc.name or ""):lower():find(turnin_npc_name:lower(), 1, true) then
                return npc
            end
        end
    end

    -- Try guard patterns
    local guard_re = Regex.new("(?:^|\\s)(?:town guard|gate guard|sergeant|city guardsman|guardsman|sentry|tavernkeeper)")
    for _, npc in ipairs(GameObj.npcs()) do
        if not M.npc_is_invalid(npc) and guard_re:test(npc.name or "") then
            return npc
        end
    end

    -- Fallback to taskmaster
    return M.find_guild_taskmaster()
end

--- Find a furrier NPC.
function M.find_furrier_npc()
    local re = Regex.new("furrier|fur trader|Bramblefist|Delosa|Dagresar")
    for _, npc in ipairs(GameObj.npcs()) do
        if not M.npc_is_invalid(npc) and re:test(npc.name or "") then
            return npc
        end
    end
    return nil
end

--- Find a healer/herbalist NPC.
function M.find_healer_npc()
    local re = Regex.new("alchemist|healer|herbalist|Sparkfinger|Maraene")
    for _, npc in ipairs(GameObj.npcs()) do
        if not M.npc_is_invalid(npc) and re:test(npc.name or "") then
            return npc
        end
    end
    return nil
end

--- Find a gem dealer NPC.
function M.find_gem_npc()
    for _, npc in ipairs(GameObj.npcs()) do
        if not M.npc_is_invalid(npc) and gem_npc_re:test(npc.name or "") then
            return npc
        end
    end
    -- Fallback to general bounty NPC
    return M.find_bounty_npc()
end

--- Normalize a bounty item name for comparison.
function M.normalize_name(name)
    if not name or name == "" then return "" end
    local s = name:lower()
    s = s:gsub("[^%w%s'%-]", " ")
    s = s:gsub("^a%s+", ""):gsub("^an%s+", ""):gsub("^some%s+", "")
    s = s:gsub("^piece%s+of%s+", ""):gsub("^handful%s+of%s+", "")
    s = s:gsub("%s+", " ")
    return s:match("^%s*(.-)%s*$") or ""
end

--- Check if an item name matches a bounty name.
function M.item_matches_bounty(item_name, bounty_name)
    local ni = M.normalize_name(item_name)
    local nb = M.normalize_name(bounty_name)
    if ni == "" or nb == "" then return false end
    if ni:find(nb, 1, true) or nb:find(ni, 1, true) then return true end

    -- Skin bounty: dropped adjective (e.g. "niveous warg pelts" vs "bundle of warg pelts")
    local suffix = nb:match("^%w+%s+(.+%s*pelts?%s*)$") or nb:match("^%w+%s+(.+%s*skins?%s*)$")
                or nb:match("^%w+%s+(.+%s*scales?%s*)$") or nb:match("^%w+%s+(.+%s*plumes?%s*)$")
                or nb:match("^%w+%s+(.+%s*manes?%s*)$") or nb:match("^%w+%s+(.+%s*hides?%s*)$")
                or nb:match("^%w+%s+(.+%s*trunks?%s*)$")
    if suffix and ni:find(suffix, 1, true) then return true end

    -- Token matching: all bounty tokens must appear in item name
    local all_match = true
    for token in nb:gmatch("%S+") do
        if not ni:find(token, 1, true) then
            all_match = false
            break
        end
    end
    return all_match
end

--- Get stack count for an item.
function M.item_stack_count(item)
    -- Check name for "(N)" suffix
    local qty = (item.name or ""):match("%((%d+)%)%s*$")
    if qty then return tonumber(qty) end
    return 1
end

--- Check if item is a gem container (jar/bottle).
function M.is_gem_container(item)
    if not item then return false end
    if M.is_ignored_gem_container(item) then return false end
    local noun = (item.noun or ""):lower()
    local name = (item.name or ""):lower()
    return noun:find("jar") ~= nil or noun:find("bottle") ~= nil
        or name:find("jar") ~= nil or name:find("bottle") ~= nil
end

--- Check if item is in the ignored gem container list.
function M.is_ignored_gem_container(item)
    if not item then return false end
    local raw = (item.name or ""):lower()
    local stripped = raw:gsub("^a%s+", ""):gsub("^an%s+", ""):gsub("^some%s+", "")
    for ignored, _ in pairs(M.IGNORED_GEM_CONTAINERS) do
        if raw:find(ignored, 1, true) or stripped:find(ignored, 1, true) then
            return true
        end
    end
    return false
end

--- Check if item is an inventory container.
function M.is_inv_container(item)
    if not item then return false end
    local name = (item.name or ""):lower()
    return Regex.test("\\b(?:pack|cloak|satchel|sack|bag|pouch|backpack|rucksack|case|kit|basket|coffer|chest|box|trunk)\\b", name)
end

--- Collect all inventory items recursively.
function M.collect_all_inv(items, depth)
    items = items or GameObj.inv()
    depth = depth or 0
    if depth > 3 then return {} end

    local result = {}
    for _, item in ipairs(items) do
        result[#result + 1] = item
        if item.contents then
            local sub = M.collect_all_inv(item.contents, depth + 1)
            for _, s in ipairs(sub) do
                result[#result + 1] = s
            end
        end
    end
    return result
end

--- Collect all inventory items with parent tracking.
function M.collect_all_inv_with_parent(items, parent, depth)
    items = items or GameObj.inv()
    depth = depth or 0
    if depth > 3 then return {} end

    local result = {}
    for _, item in ipairs(items) do
        result[#result + 1] = { item = item, parent = parent }
        if item.contents then
            local sub = M.collect_all_inv_with_parent(item.contents, item, depth + 1)
            for _, s in ipairs(sub) do
                result[#result + 1] = s
            end
        end
    end
    return result
end

--- Stop active scripts that interfere with bounty turn-in workflows.
function M.stop_turnin_scripts()
    for _, scr in ipairs(Script.list()) do
        if scr.name ~= Script.name and M.TURNIN_SCRIPTS_TO_STOP[scr.name:lower()] then
            Script.kill(scr.name)
        end
    end
end

--- Hydrate inventory containers by issuing "look in" for each to populate contents.
function M.hydrate_containers()
    for _, item in ipairs(GameObj.inv()) do
        if M.is_inv_container(item) then
            dothistimeout("look in #" .. item.id, 4,
                "In the ", "There is nothing in the", "That is closed", "What were you referring to", "I could not find")
            pause(0.1)
        end
    end
end

--- Try to get a gem container from inventory using direct get commands.
--- Returns {item=, parent_id=} or nil.
function M.try_get_gem_container(gem_name)
    if not gem_name or gem_name == "" then return nil end

    local commands = {
        { cmd = "get my bottle containing " .. gem_name, parent_id = nil },
        { cmd = "get my jar containing " .. gem_name, parent_id = nil },
    }

    for _, container in ipairs(GameObj.inv()) do
        if M.is_inv_container(container) then
            table.insert(commands, { cmd = "get my bottle containing " .. gem_name .. " from #" .. container.id, parent_id = container.id })
            table.insert(commands, { cmd = "get my jar containing " .. gem_name .. " from #" .. container.id, parent_id = container.id })
            table.insert(commands, { cmd = "get my bottle from #" .. container.id, parent_id = container.id })
            table.insert(commands, { cmd = "get my jar from #" .. container.id, parent_id = container.id })
        end
    end

    -- Deduplicate
    local seen = {}
    for _, entry in ipairs(commands) do
        if not seen[entry.cmd] then
            seen[entry.cmd] = true
            dothistimeout(entry.cmd, 4,
                "You ", "Get what", "I could not find", "What were you referring to")
            -- Check if we're now holding a gem container
            for _, hand_fn in ipairs({GameObj.right_hand, GameObj.left_hand}) do
                local held = hand_fn()
                if held and M.is_gem_container(held) then
                    return { item = held, parent_id = entry.parent_id }
                end
            end
        end
    end

    return nil
end

--- Find the origin turn-in NPC by stored ID, noun, or pattern fallback.
function M.find_origin_turnin_npc(origin_npc_id, origin_npc_noun)
    -- Try by stored ID first
    if origin_npc_id then
        for _, npc in ipairs(GameObj.npcs()) do
            if not M.npc_is_invalid(npc) and npc.id == origin_npc_id then
                return npc
            end
        end
    end
    -- Try by stored noun
    if origin_npc_noun and origin_npc_noun ~= "" then
        for _, npc in ipairs(GameObj.npcs()) do
            if not M.npc_is_invalid(npc) and (npc.noun or ""):lower() == origin_npc_noun:lower() then
                return npc
            end
        end
    end
    -- Fallback to pattern
    return M.find_bounty_npc()
end

--- Check if current room is a blocked gemshop.
function M.blocked_gemshop_room()
    local room_id = GameState.room_id
    if room_id and M.BLOCKED_GEMSHOP_ROOM_IDS[room_id] then return true end
    local room = Room.current()
    if room and room.uid then
        local uids = type(room.uid) == "table" and room.uid or { room.uid }
        for _, u in ipairs(uids) do
            local uid_str = tostring(u):gsub("^[Uu]", "")
            if M.BLOCKED_GEMSHOP_UIDS[uid_str] then return true end
        end
    end
    if room and room.title and M.BLOCKED_GEMSHOP_TITLE_PATTERN:test(tostring(room.title)) then
        return true
    end
    return false
end

return M
