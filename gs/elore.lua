--- @revenant-script
--- name: elore
--- version: 2.1.1
--- author: elanthia-online
--- contributors: DrunkenDurfin, Tysong, Nisugi
--- game: gs
--- description: Modernized loresinging automation for bards
--- tags: bard,loresing,loresong,magic
---
--- Changelog (from Lich5):
---   v2.1.1 (2026-03-12): force open/look in on nil/empty container contents
---   v2.1.0 (2026-03-11): detect RECALL unlocked items, skip singing
---   v2.0.0 (2026-01-12): 2-line fast verses default, 4-line optional, retry logic,
---     container processing, removed logging
---
--- Usage:
---   ;elore              - Sing to item in right hand (2-line, fast)
---   ;elore power        - Sing with 4-line verses (more powerful, slower)
---   ;elore target <noun>           - Sing to item in room
---   ;elore target <noun> power     - Sing to room item with 4-line verses
---   ;elore bot                     - Service mode (accept items from players)
---   ;elore container <noun>        - Process all items in container
---   ;elore settings                - Show current settings
---   ;elore set <key> <value>       - Change a setting
---   ;elore help                    - Show this message

local ELore = {}

---------------------------------------------------------------------------
-- Verse templates
---------------------------------------------------------------------------
-- Fast 2-line verses (~3-5s RT)
local VERSES_FAST = {
    value   = "%s that I hold;let your value now be told",
    purpose = "%s that I hold;let your purpose now be told",
    magic   = "%s that I hold;let your magic now be told",
    special = "%s that I hold;let your special ability now be told",
}

-- Power 4-line verses (~11-12s RT)
local VERSES_POWER = {
    value   = {"%s that I hold in my hand","Let your value be scanned","Tell me what you're truly worth","From your origin and birth"},
    purpose = {"%s that I hold in my hand","Let your purpose now expand","Tell me why you were made","And the role that you have played"},
    magic   = {"%s that I hold in my hand","Let your magic be unmanned","Show the power that you wield","Let your enchantments be revealed"},
    special = {"%s that I hold in my hand","Let your secrets now be fanned","Special powers you possess","I command you to confess"},
}

-- Room target fast verses
local VERSES_ROOM_FAST = {
    value   = "%s I now see;let your value sing to me",
    purpose = "%s I now see;let your purpose sing to me",
    magic   = "%s I now see;let your magic sing to me",
    special = "%s I now see;let your secrets sing to me",
}

-- Room target power verses
local VERSES_ROOM_POWER = {
    value   = {"%s that I see before me now","Let your value take a bow","Tell me what you're truly worth","From your origin and birth"},
    purpose = {"%s that I see before me now","Your purpose you must avow","Tell me why you were made","And the role that you have played"},
    magic   = {"%s that I see before me now","Your magic I must know how","Show the power that you wield","Let your enchantments be revealed"},
    special = {"%s that I see before me now","To my song you must bow","Special powers you possess","I command you to confess"},
}

local VERSE_TYPES = {"value", "purpose", "magic", "special"}

-- State
local power_mode = false
local target_mode = false

---------------------------------------------------------------------------
-- Settings via CharSettings
---------------------------------------------------------------------------
local SETTING_KEYS = {
    pause = {type = "string",  default = nil,   desc = "Script to pause in bot mode"},
    retry = {type = "integer", default = 3,     desc = "Max retries per verse"},
    mana  = {type = "integer", default = 50,    desc = "Min mana before singing"},
    power = {type = "boolean", default = false,  desc = "Use 4-line verses by default"},
}

local function get_setting(key)
    local raw = CharSettings["elore_" .. key]
    if raw == nil or raw == "" then
        return SETTING_KEYS[key] and SETTING_KEYS[key].default
    end
    local info = SETTING_KEYS[key]
    if info and info.type == "integer" then
        return tonumber(raw) or info.default
    elseif info and info.type == "boolean" then
        return raw == "true"
    end
    return raw
end

local function set_setting(key, value)
    if not SETTING_KEYS[key] then
        echo("Unknown setting: " .. key)
        echo("Valid settings: pause, retry, mana, power")
        return false
    end
    if value == nil or value == "none" or value == "clear" then
        CharSettings["elore_" .. key] = nil
        echo(key .. " cleared (will use default)")
        return true
    end
    CharSettings["elore_" .. key] = tostring(value)
    echo(key .. " set to: " .. tostring(value))
    return true
end

local function max_retries()   return get_setting("retry") or 3 end
local function mana_threshold() return get_setting("mana") or 50 end
local function pause_script_name() return get_setting("pause") end

---------------------------------------------------------------------------
-- Verse building
---------------------------------------------------------------------------
local function build_verse(verse_type, item_noun)
    local cap_noun = item_noun:sub(1,1):upper() .. item_noun:sub(2)

    if target_mode then
        if power_mode then
            local lines = VERSES_ROOM_POWER[verse_type]
            local result = {}
            for _, line in ipairs(lines) do
                table.insert(result, string.format(line, cap_noun))
            end
            return table.concat(result, ";")
        else
            return string.format(VERSES_ROOM_FAST[verse_type], cap_noun)
        end
    else
        if power_mode then
            local lines = VERSES_POWER[verse_type]
            local result = {}
            for _, line in ipairs(lines) do
                table.insert(result, string.format(line, cap_noun))
            end
            return table.concat(result, ";")
        else
            return string.format(VERSES_FAST[verse_type], cap_noun)
        end
    end
end

---------------------------------------------------------------------------
-- Mana waiting
---------------------------------------------------------------------------
local function wait_for_mana()
    local threshold = mana_threshold()
    if GameState.mana >= threshold then return end
    echo("Waiting for mana (" .. tostring(GameState.mana) .. "/" .. tostring(threshold) .. ")...")
    wait_until(function() return GameState.mana >= threshold end)
end

---------------------------------------------------------------------------
-- Singing
---------------------------------------------------------------------------
local function sing_verse(item_noun, verse_type, item_id)
    wait_for_mana()
    waitrt()
    waitcastrt()

    local verse = build_verse(verse_type, item_noun)
    local command
    if target_mode and item_id then
        command = "loresing ::#" .. item_id .. ":: " .. verse
    elseif target_mode then
        command = "loresing ::" .. item_noun .. ":: " .. verse
    else
        command = "loresing " .. verse
    end

    fput(command)
    local line = waitforre("Roundtime|has more to share|falters and fades|failed to resonate|simply resonates|%.%.%.wait %d+")

    if not line then
        return "timeout"
    elseif line:find("%.%.%.wait %d+") then
        return "wait_rt"
    elseif line:find("falters and fades") or line:find("failed to resonate") then
        return "cannot_loresing"
    elseif line:find("has more to share") then
        return "needs_retry"
    else
        return "success"
    end
end

local function sing_verse_with_retry(item_noun, verse_type, item_id)
    local retries = 0

    while true do
        local result = sing_verse(item_noun, verse_type, item_id)

        if result == "success" then
            waitrt()
            waitcastrt()
            return true
        elseif result == "cannot_loresing" then
            echo("Item cannot be loresung - skipping")
            return false
        elseif result == "needs_retry" then
            retries = retries + 1
            if retries >= max_retries() then
                echo("Max retries (" .. tostring(max_retries()) .. ") reached for " .. verse_type .. " verse")
                waitrt()
                waitcastrt()
                return true
            end
            echo("Retry " .. tostring(retries) .. "/" .. tostring(max_retries()) .. " for " .. verse_type .. " verse...")
            waitrt()
            waitcastrt()
            pause(0.5)
        elseif result == "timeout" then
            echo("Timeout waiting for loresong response")
            return false
        elseif result == "wait_rt" then
            waitrt()
            waitcastrt()
            -- continues loop
        end
    end
end

---------------------------------------------------------------------------
-- Recall check
---------------------------------------------------------------------------
local function recall_unlocked(item_noun, item_id)
    local cmd = item_id and ("recall #" .. item_id) or ("recall my " .. item_noun)
    fput(cmd)
    local line = waitforre("permanently unlocked loresong|You are unable to recall")
    if line and line:find("permanently unlocked loresong") then
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Full loresong sequence
---------------------------------------------------------------------------
local function full_loresong(item_noun, item_id)
    if recall_unlocked(item_noun, item_id) then
        echo("Item has permanently unlocked loresong - skipping")
        return
    end

    local mode_str = power_mode and "4-line power" or "2-line fast"
    echo("Loresinging with " .. mode_str .. " verses...")

    fput("speak bard")
    pause(0.3)

    for _, verse_type in ipairs(VERSE_TYPES) do
        local ok = sing_verse_with_retry(item_noun, verse_type, item_id)
        if not ok then break end
    end

    fput("speak common")
end

---------------------------------------------------------------------------
-- Container processing
---------------------------------------------------------------------------
local function find_container(name)
    local name_lower = name:lower()

    -- Check left hand
    local lh = GameObj.left_hand()
    if lh and lh.name:lower():find(name_lower, 1, true) then
        return lh
    end

    -- Check inventory
    local inv = GameObj.inv()
    if inv then
        for _, item in ipairs(inv) do
            if item.name:lower():find(name_lower, 1, true) and item.contents then
                return item
            end
        end
    end

    -- Check room loot
    local loot = GameObj.loot()
    if loot then
        for _, item in ipairs(loot) do
            if item.name:lower():find(name_lower, 1, true) then
                if not item.contents then
                    fput("look in #" .. item.id)
                    pause(0.5)
                end
                if item.contents then return item end
            end
        end
    end

    return nil
end

local function process_container(container)
    local rh = GameObj.right_hand()
    if rh then
        echo("ERROR: Right hand must be empty (currently holding: " .. (rh.name or "something") .. ")")
        return
    end

    if not container.contents or #container.contents == 0 then
        fput("open #" .. container.id)
        fput("look in #" .. container.id)
        pause(0.5)
    end

    if not container.contents or #container.contents == 0 then
        echo("Container is empty or contents not visible.")
        return
    end

    local item_count = #container.contents
    local mode_str = power_mode and "4-line power" or "2-line fast"
    echo("Processing " .. tostring(item_count) .. " items from " .. container.name .. " (" .. mode_str .. " mode)...")

    for i, item in ipairs(container.contents) do
        echo("--- Item " .. tostring(i) .. "/" .. tostring(item_count) .. ": " .. item.name .. " ---")

        fput("get #" .. item.id)
        local line = waitforre("You remove|You get|You pick up|could not find")
        if not line or line:find("could not find") then
            echo("Failed to get item, skipping...")
            goto continue
        end

        full_loresong(item.noun, nil)

        fput("put #" .. item.id .. " in #" .. container.id)
        pause(0.5)

        ::continue::
    end

    echo("Container processing complete!")
end

---------------------------------------------------------------------------
-- Bot mode
---------------------------------------------------------------------------
local function bot_mode()
    local pause_name = pause_script_name()
    local mode_str = power_mode and "4-line power" or "2-line fast"

    echo("Bot mode activated (" .. mode_str .. ") - waiting for item offers...")
    echo("Pause script: " .. (pause_name or "none"))

    while true do
        local offer_line = waitforre("offers you")
        local customer = offer_line and offer_line:match("^(%S+) offers you")

        if pause_name and running(pause_name) then
            Script.pause(pause_name)
        end

        fput("accept")
        pause(1)

        local rh = GameObj.right_hand()
        if not rh then
            echo("No item received, continuing...")
            if pause_name then Script.unpause(pause_name) end
            goto continue
        end

        full_loresong(rh.noun, nil)

        -- Return item to customer
        if customer then
            fput("give " .. customer)
            local result = waitforre("has accepted|has declined|has expired")
            if not result or not result:find("has accepted") then
                echo(tostring(customer) .. " did not accept - trying again...")
                fput("whisper " .. customer .. " Your item is ready! Please ACCEPT my offer.")
                fput("give " .. customer)
                result = waitforre("has accepted|has declined|has expired")
            end
            if not result or not result:find("has accepted") then
                echo(tostring(customer) .. " appears unresponsive - please handle manually")
                while GameObj.right_hand() do
                    pause(5)
                end
            end
        end

        if pause_name then Script.unpause(pause_name) end

        ::continue::
    end
end

---------------------------------------------------------------------------
-- Settings display
---------------------------------------------------------------------------
local function show_settings()
    respond("")
    respond("ELore Settings (Character: " .. GameState.name .. ")")
    respond(string.rep("-", 50))
    for key, info in pairs(SETTING_KEYS) do
        local current = get_setting(key)
        local display = current ~= nil and tostring(current) or ("(default: " .. tostring(info.default or "none") .. ")")
        respond(string.format("   %-16s = %s", key, display))
        respond(string.format("   %s%s", string.rep(" ", 16), info.desc))
    end
    respond("")
    respond("To change: ;" .. Script.name .. " set <key> <value>")
    respond("")
end

---------------------------------------------------------------------------
-- Help
---------------------------------------------------------------------------
local function show_help()
    respond([[

ELore - Modernized Loresinging Script

Usage:
   ;elore              - Sing to item in hand (2-line, fast)
   ;elore power        - Sing to item in hand (4-line, powerful)
   ;elore target <noun>           - Sing to item in room
   ;elore target <noun> power     - Sing to room item (4-line)
   ;elore bot                     - Service mode (2-line)
   ;elore bot power               - Service mode (4-line)
   ;elore container <noun>        - Process container (2-line)
   ;elore container <noun> power  - Process container (4-line)
   ;elore settings                - Show current settings
   ;elore set <key> <value>       - Change a setting
   ;elore help                    - Show this message

Verse Modes:
   2-line (default): Fast (~3-5s RT per verse)
   4-line (power):   More powerful (~11-12s RT per verse)

Settings:
   pause  - Script to pause in bot mode (default: none)
   retry  - Max retries per verse (default: 3)
   mana   - Min mana before singing (default: 50)
   power  - Use 4-line verses by default (default: false)
    ]])
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------

-- Check for 'power' in any arg position
for i = 1, #Script.vars do
    if Script.vars[i] and Script.vars[i]:lower() == "power" then
        power_mode = true
    end
end

-- Default power from settings
if not power_mode and get_setting("power") then
    power_mode = true
end

local cmd = Script.vars[1]
if cmd then cmd = cmd:lower() end

if not cmd or cmd == "" then
    -- Single item mode
    local rh = GameObj.right_hand()
    if not rh then
        echo("ERROR: No item in right hand!")
        echo("Usage: ;" .. Script.name .. " help")
        return
    end
    full_loresong(rh.noun, nil)

elseif cmd == "power" then
    local rh = GameObj.right_hand()
    if not rh then
        echo("ERROR: No item in right hand!")
        return
    end
    full_loresong(rh.noun, nil)

elseif cmd == "bot" then
    bot_mode()

elseif cmd == "container" then
    local parts = {}
    for i = 2, #Script.vars do
        local v = Script.vars[i]
        if v and v:lower() ~= "power" then
            table.insert(parts, v)
        end
    end
    local container_name = table.concat(parts, " ")
    if container_name == "" then
        echo("ERROR: Please specify a container name")
        return
    end
    local container = find_container(container_name)
    if not container then
        echo("ERROR: Could not find container matching '" .. container_name .. "'")
        return
    end
    process_container(container)

elseif cmd == "target" then
    local target_noun = Script.vars[2]
    if not target_noun or target_noun == "" or target_noun:lower() == "power" then
        echo("ERROR: Please specify an item noun")
        return
    end

    -- Look up item in room
    local target_id = nil
    local loot = GameObj.loot() or {}
    local room_desc = GameObj.room_desc() or {}
    for _, item in ipairs(loot) do
        if item.noun:lower():find(target_noun:lower(), 1, true) then
            target_id = item.id
            break
        end
    end
    if not target_id then
        for _, item in ipairs(room_desc) do
            if item.noun:lower():find(target_noun:lower(), 1, true) then
                target_id = item.id
                break
            end
        end
    end

    target_mode = true
    full_loresong(target_noun, target_id)

elseif cmd == "help" then
    show_help()

elseif cmd == "settings" then
    show_settings()

elseif cmd == "set" then
    local key = Script.vars[2]
    local value = Script.vars[3]
    if not key or key == "" then
        echo("ERROR: Please specify a setting key")
        return
    end
    set_setting(key:lower(), value)

else
    echo("Unknown command: " .. tostring(cmd))
    echo("Use ;" .. Script.name .. " help for usage information.")
end
