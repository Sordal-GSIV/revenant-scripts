--- @revenant-script
--- name: reap
--- version: 1.0.0
--- author: Hexbane
--- game: gs
--- tags: sorcerer, shadow, essence, sacrifice, reap
--- description: Check shadow essence and sacrifice a susceptible target if under max
---
--- Original Lich5 authors: Hexbane
--- Ported to Revenant Lua from reap.lic
---
--- Usage: ;reap

local MAX_ESSENCE = 5

local GOOD_PATTERNS = {
    "susceptible to manipulation",
    "enticingly frail",
}

local BAD_PATTERNS = {
    "bond .* is indomitable",
    "bond .* is stalwart and formidable",
    "You think .* is suitable for animation",
    "bond .* is firmly bound",
}

local ASSESS_LINE = "You sense that the bond between"
local RESOURCE_LINE = "Accumulated Shadow essence:%s*(%d+)"

local ARM_TRASH_PATTERNS = {
    "(?:putrid|deformed|desiccated|skeletal)%s+arm",
    "pair of%s+(?:putrid|deformed|desiccated|skeletal)%s+arms",
}

local function info(msg)
    echo(msg)
end

local function current_essence(timeout)
    timeout = timeout or 3
    fput("resource")
    local start = os.time()
    while os.time() - start < timeout do
        local line = get()
        if line then
            local val = line:match("Accumulated Shadow essence:%s*(%d+)")
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
        if Regex.test(name, pat) then return false end
    end
    if obj.status and obj.status:lower():find("dead") then return false end
    return true
end

local function assess_target(id, name_for_log, timeout)
    timeout = timeout or 3
    info("[REAP] Assessing " .. (name_for_log or ("#" .. id)) .. "...")
    fput("assess #" .. id)
    local start = os.time()
    while os.time() - start < timeout do
        local line = get()
        if line then
            for _, pat in ipairs(GOOD_PATTERNS) do
                if Regex.test(line, pat) then return "good" end
            end
            if Regex.test(line, ASSESS_LINE) then
                for _, pat in ipairs(BAD_PATTERNS) do
                    if Regex.test(line, pat) then return "bad" end
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
    local result = assess_target(t.id, t.name)
    if result == "good" then
        info("[REAP] FOUND viable target: " .. t.name .. " (#" .. t.id .. ").")
        fput("sacrifice #" .. t.id)
        info("[REAP] Done.")
        return
    end
    wait(0.1)
end

info("[REAP] No susceptible/frail/animatable targets found.")
