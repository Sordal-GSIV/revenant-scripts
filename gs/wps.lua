--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: wps
--- version: 1.4
--- author: Kragdruk
--- game: gs
--- description: WPS smithy service helper — request multiple services from a blacksmith
--- tags: util,ccf,duskruin,festival,merchant,wps,smithy
---
--- Usage:
---   ;wps <count> <crit, damage, or sighting>
---
--- Pauses for confirmation before requesting services.
---
--- changelog:
---   1.4 (2025-11-02)
---     Blacksmith changed pronouns again so updated to accept whatever
---   1.3 (2021-12-27)
---     Blacksmith changed pronouns again so updated to accept whatever
---   1.2 (2021-08-28)
---     Updated blacksmith response recognition for new messaging
---   1.1 (2020-09-01)
---     Fix request response regex for sighting

local SERVICE_TYPES = { "critical", "damage", "sighting" }

local BLACKSMITH_NAMES = {
    ["old dwarven blacksmith"] = true,
    ["ancient vampiric blacksmith"] = true,
}

local function determine_service_type(arg)
    if not arg then return nil end
    arg = arg:lower()
    for _, t in ipairs(SERVICE_TYPES) do
        if t:sub(1, #arg) == arg then return t end
    end
    return nil
end

local function find_blacksmith()
    local npcs = GameObj.npcs()
    if not npcs then return nil end
    for _, npc in ipairs(npcs) do
        if BLACKSMITH_NAMES[npc.name] then return npc end
    end
    return nil
end

local function print_usage()
    respond("")
    respond("  ;wps <count> <crit, damage, or sighting>")
    respond("")
end

local function estimate_regex(service_type)
    if service_type:match("sight") then
        return "(?i)Modified Weighting Type: Sighted"
    else
        return "(?i)Modified \\w+ Type: " .. service_type
    end
end

local function perform_service_request(blacksmith, service_type)
    local result = dothistimeout("ask #" .. blacksmith.id .. " about " .. service_type, 5,
        estimate_regex(service_type))
    if not result then
        echo("Failed to ask blacksmith for service.")
        return false
    end
    return true
end

local function perform_service_confirmation(blacksmith)
    local result = dothistimeout("ask #" .. blacksmith.id .. " about confirm", 5,
        "(?i)quickly returns, idly polishing it with a dirty rag as (?:he|she|it) hands it back to you")
    if not result then
        echo("Failed to confirm service.")
        return false
    end
    return true
end

-- Validate arguments
local count_str = Script.vars[1]
local service_str = Script.vars[2]

if not count_str or not service_str then
    echo("Not enough arguments.")
    print_usage()
    return
end

if not count_str:match("^%d+$") then
    echo("'" .. count_str .. "' is not a valid number.")
    print_usage()
    return
end

local service = determine_service_type(service_str)
if not service then
    echo("'" .. service_str .. "' is not a valid service type.")
    print_usage()
    return
end

local blacksmith = find_blacksmith()
if not blacksmith then
    echo("No blacksmith found in this room.")
    local npcs = GameObj.npcs()
    if npcs then
        local names = {}
        for _, npc in ipairs(npcs) do names[#names + 1] = npc.name end
        echo("NPCs present: " .. table.concat(names, ", "))
    end
    return
end

local count = tonumber(count_str)

respond("")
respond("  Unpause ;wps to request:")
respond("  " .. count .. " " .. service .. " services from " .. blacksmith.name)
respond("")
pause_script()

for _ = 1, count do
    if not perform_service_request(blacksmith, service) then break end
    if not perform_service_confirmation(blacksmith) then break end
end
