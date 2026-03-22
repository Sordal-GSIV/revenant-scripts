--- @revenant-script
--- name: animatekeeper
--- version: 10
--- author: unknown
--- game: gs
--- description: Maintains Animate Dead (730) by monitoring duration and refreshing with sacrifice channel
--- tags: sorcerer, animate dead, necromancer
---
--- Monitors animate duration, stocks essence from stunned creatures, refreshes before expiry

local SAFETY_BUFFER = 60
local CHECK_INTERVAL = 10
local ESSENCE_MAX = 5
local ANIMATE_SPELL = 730

echo("AnimateKeeper started!")
echo("Safety buffer: " .. SAFETY_BUFFER .. "s")

local cached_essence = 0
local last_refresh = 0

local function get_essence(force)
    fput("resource")
    pause(1)
    -- Parse essence from game output
    local line = get()
    if line then
        local n = line:match("(%d+)")
        if n then cached_essence = tonumber(n) end
    end
    return cached_essence
end

local function attempt_refresh()
    fput("sacrifice channel")
    pause(1)
    local result = get()
    if result and result:match("overwhelm") then
        echo("Refresh FAILED")
        return false
    end
    echo("Refreshed animate!")
    return true
end

get_essence(true)
echo("Current essence: " .. cached_essence .. "/" .. ESSENCE_MAX)

while true do
    -- Check for animate and refresh if needed
    local animate_present = false
    for _, npc in ipairs(GameObj.npcs() or {}) do
        if npc.name and npc.name:lower():match("animate") then
            animate_present = true
            break
        end
    end

    -- Stock essence from stunned creatures
    if cached_essence < ESSENCE_MAX then
        for _, npc in ipairs(GameObj.npcs() or {}) do
            if npc.status and npc.status:match("stunned") and not npc.name:lower():match("animate") then
                fput("sacrifice #" .. npc.id)
                pause(3)
                get_essence(true)
                break
            end
        end
    end

    -- Refresh if animate present and spell expiring
    if animate_present and cached_essence > 0 then
        local spell = Spell[ANIMATE_SPELL]
        if spell and spell.active and spell.timeleft then
            local secs = spell.timeleft * 60
            if secs <= SAFETY_BUFFER then
                if attempt_refresh() then
                    last_refresh = os.time()
                    get_essence(true)
                end
            end
        end
    end

    pause(CHECK_INTERVAL)
end
