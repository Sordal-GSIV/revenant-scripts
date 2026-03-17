--- @revenant-script
--- name: locker_get
--- version: 1.0.0
--- author: Xanlin
--- game: gs
--- tags: utility, locker, inventory, runners
--- description: Search locker manifest and retrieve items using runners
---
--- Original Lich5 authors: Xanlin
--- Ported to Revenant Lua from locker-get.lic v0
---
--- Usage: ;locker_get <item name>

local use_boosts = true

local function nearest_manifest_town()
    local room_id = Room.current.id
    local town_room = Room.find_nearest_by_tag(room_id, "town")
    if not town_room then return "Landing" end
    local location = Room[town_room].location or "Landing"
    if location:find("Isle of Four Winds") then return "Mist Harbor" end
    return location:gsub("the ", ""):gsub(",.*$", ""):match("^%s*(.-)%s*$")
end

local function client_command(command, start_pattern)
    return quiet_command(command, start_pattern)
end

local function manifest_search(inp)
    local town = nearest_manifest_town()
    local command = "locker manifest " .. town
    local lines = client_command(command, "Thinking back, you recall|Looking in front of you")
    local matches = {}
    for _, line in ipairs(lines or {}) do
        if Regex.test(line, inp) then
            local ordinal = line:match("<d.->(d+)</d>")
            if ordinal and tonumber(ordinal) > 0 then
                matches[#matches + 1] = { line = line, ordinal = ordinal }
            end
        end
    end
    return matches
end

local function clear_hands()
    if checkleft() or checkright() then
        fput("store all")
    end
    if checkleft() or checkright() then
        empty_hands()
    end
end

local function unpackage(command, retry_on_fail)
    if retry_on_fail == nil then retry_on_fail = true end
    clear_hands()

    local result = dothistimeout(command, 3, 'right exist="|no contract with')
    if result and result:find("no contract with") then
        if use_boosts then
            fput("boost runner locker")
        end
        if retry_on_fail then
            return unpackage(command, false)
        else
            echo("No more runners or boosts.")
            return false
        end
    end
    if not result then return false end

    dothistimeout("open my package", 3, "You open")
    wait(0.3)

    local pkg = GameObj.right_hand()
    if pkg and pkg.contents and #pkg.contents > 0 then
        dothistimeout("get #" .. pkg.contents[1].id .. " from package", 3, "You remove")
    end

    dothistimeout("drop my package", 3, "You toss aside")
    fput("swap")
    return true
end

local inp = Script.current.vars[0]
if not inp or inp == "" then
    echo("Usage: ;locker_get <item name>")
    return
end

local matches = manifest_search(inp)
if #matches == 0 then
    respond("no matches for '" .. inp .. "'")
    return
end

if #matches > 1 then
    respond("'" .. inp .. "' matches " .. #matches .. " manifest lines")
    for _, m in ipairs(matches) do
        respond("  " .. m.line)
    end
    return
end

local ordinal = matches[1].ordinal
if ordinal then
    unpackage("locker get " .. ordinal)
end
