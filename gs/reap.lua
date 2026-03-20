--- @revenant-script
--- name: reap
--- version: 1.1.0
--- author: Hexbane
--- game: gs
--- tags: sorcerer, shadow, essence, sacrifice, reap
--- description: Check shadow essence and sacrifice a susceptible target if under max
---
--- Original Lich5 authors: Hexbane
--- Ported to Revenant Lua from reap.lic
---
--- @lic-certified: complete 2026-03-19
---
--- Usage: ;reap

local Msg = require("lib/messaging")

local MAX_ESSENCE = 5

-- PCRE patterns with (?i) case-insensitive flag matching original /i regexes
local GOOD_PATTERNS = {
    "(?i)susceptible to manipulation",
    "(?i)enticingly frail",
}

local BAD_PATTERNS = {
    "(?i)bond .* is indomitable",
    "(?i)bond .* is stalwart and formidable",
    "(?i)You think .* is suitable for animation",
    "(?i)bond .* is firmly bound",
}

local ASSESS_LINE   = "(?i)You sense that the bond between"
local RESOURCE_LINE = "Accumulated Shadow essence:%s*(%d+)"

-- 709 Grasp of the Grave arm patterns — PCRE with word boundaries and \s whitespace class
local ARM_TRASH_PATTERNS = {
    "(?i)\\b(?:putrid|deformed|desiccated|skeletal)\\s+arm\\b",
    "(?i)\\bpair of\\s+(?:putrid|deformed|desiccated|skeletal)\\s+arms\\b",
}

local function info(msg)
    Msg.msg("info", msg)
end

local function current_essence(timeout)
    timeout = timeout or 3
    fput("resource")
    local start = os.clock()
    while os.clock() - start < timeout do
        local line = get()
        if line then
            local val = line:match(RESOURCE_LINE)
            if val then return tonumber(val) end
        end
    end
    return nil
end

local function alive_npc(obj)
    if not obj or not obj.id then return false end
    local name = obj.name or ""
    if name == "" then return false end
    for _, pat in ipairs(ARM_TRASH_PATTERNS) do
        if Regex.test(pat, name) then return false end
    end
    if obj.status and obj.status:lower():find("dead") then return false end
    return true
end

local function find_obj_by_id(id)
    for _, o in ipairs(GameObj.targets()) do
        if o.id == id then return o end
    end
    return nil
end

local function assess_target(id, name_for_log, timeout)
    timeout = timeout or 3
    local obj = find_obj_by_id(id)
    if not alive_npc(obj) then return "gone" end

    info("[REAP] Assessing " .. (name_for_log or ("#" .. id)) .. "...")
    fput("assess #" .. id)

    local start = os.clock()
    while os.clock() - start < timeout do
        local line = get()
        if line then
            for _, pat in ipairs(GOOD_PATTERNS) do
                if Regex.test(pat, line) then return "good" end
            end
            if Regex.test(ASSESS_LINE, line) then
                for _, pat in ipairs(BAD_PATTERNS) do
                    if Regex.test(pat, line) then return "bad" end
                end
                return "unknown"
            end
        end
    end
    return "timeout"
end

info("[REAP] Starting...")

local ess = current_essence()
if ess and ess >= MAX_ESSENCE then
    info("[REAP] Shadow essence is full (" .. ess .. "/" .. MAX_ESSENCE .. "). Exiting.")
    return
end

local targets = {}
for _, obj in ipairs(GameObj.targets()) do
    if alive_npc(obj) then
        targets[#targets + 1] = obj
    end
end

if #targets == 0 then
    info("[REAP] No valid living creatures detected.")
    return
end

for _, t in ipairs(targets) do
    if alive_npc(find_obj_by_id(t.id)) then
        local result = assess_target(t.id, t.name)
        if result == "good" then
            info("[REAP] FOUND viable target: " .. t.name .. " (#" .. t.id .. ").")
            fput("sacrifice #" .. t.id)
            info("[REAP] Done.")
            return
        end
        pause(0.10)
    end
end

info("[REAP] No susceptible/frail/animatable targets found.")
