--- @revenant-script
--- name: keymaster
--- version: 1.0.0
--- author: elanthia-online
--- game: gs
--- description: Scan containers for tier-based locks and keys, match and unlock pairs, collect rewards
--- tags: loot,lock,key
---
--- Changelog (from Lich5):
---   v1.0.0 (2026-01-20)
---     - initial release

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local TIERS = { "vibrant", "radiant" }
local COLORS = { "blood red", "forest green", "frosty white", "royal blue" }
local WILDCARD = "rainbow-hued"

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local rewards = {}
local processed_keys = {}
local processed_locks = {}
local pairs_by_tier = {}
local rewards_by_tier = {}

for _, tier in ipairs(TIERS) do
    pairs_by_tier[tier] = 0
    rewards_by_tier[tier] = {}
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

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
-- Container scanning
--------------------------------------------------------------------------------

local function get_containers()
    waitrt()
    local results = issue_command("inventory containers", { "^You are holding " })

    -- Extract container IDs from the response
    local containers = {}
    local id_re = Regex.new('exist="([^"]+)"')
    for _, line in ipairs(results) do
        local ids = id_re:match_all(line)
        if ids then
            for _, m in ipairs(ids) do
                local obj = GameObj[m[1]]
                if obj then
                    containers[#containers + 1] = obj
                end
            end
        end
    end

    -- Populate contents for containers that need it
    for _, container in ipairs(containers) do
        if not container.contents then
            waitrt()
            issue_command("look in #" .. container.id, {
                "exposeContainer", "dialogData", "container",
                "you glance", "There is nothing", "That is closed",
                "In the ", "I could not find",
            })
            pause(0.3)
        end
    end

    return containers
end

--------------------------------------------------------------------------------
-- Item finding
--------------------------------------------------------------------------------

local function find_items()
    local keys = {}
    local locks = {}

    -- Build valid patterns
    local valid_keys = {}
    local valid_locks = {}
    for _, tier in ipairs(TIERS) do
        for _, color in ipairs(COLORS) do
            valid_keys[tier .. " " .. color .. " key"] = true
            valid_locks[tier .. " " .. color .. " lock"] = true
        end
        valid_keys[tier .. " " .. WILDCARD .. " key"] = true
        valid_locks[tier .. " " .. WILDCARD .. " lock"] = true
    end

    local containers = get_containers()

    for _, container in ipairs(containers) do
        local contents = container.contents
        if contents and type(contents) == "table" then
            for _, item in ipairs(contents) do
                if valid_keys[item.name] then
                    keys[#keys + 1] = item
                end
                if valid_locks[item.name] then
                    locks[#locks + 1] = item
                end
            end
        end
    end

    return keys, locks
end

--------------------------------------------------------------------------------
-- Pair processing
--------------------------------------------------------------------------------

local function matches_pattern(name, tier, color, item_type)
    return name == (tier .. " " .. color .. " " .. item_type)
end

local function unlock_pair(key, lock, tier)
    fput("get #" .. key.id)
    fput("get #" .. lock.id)

    -- Open the lock with the key
    put("open my lock")
    local deadline = os.time() + 5
    local line = waitforre("^You slowly insert ", deadline)

    -- Wait for baubles to appear
    pause(1)
    local bauble_deadline = os.time() + 10
    while os.time() < bauble_deadline do
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (rh and rh.noun == "bauble") or (lh and lh.noun == "bauble") then
            break
        end
        pause(0.5)
    end

    -- Break both baubles
    fput("break my bauble")
    fput("break my bauble")

    -- Wait for baubles to be gone
    pause(1)
    local gone_deadline = os.time() + 10
    while os.time() < gone_deadline do
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local has_bauble = (rh and rh.noun == "bauble") or (lh and lh.noun == "bauble")
        if not has_bauble then break end
        pause(0.5)
    end

    -- Collect rewards
    local lh = GameObj.left_hand()
    if lh and lh.id then
        rewards[#rewards + 1] = lh
        if not rewards_by_tier[tier] then rewards_by_tier[tier] = {} end
        rewards_by_tier[tier][lh.name] = (rewards_by_tier[tier][lh.name] or 0) + 1
    end
    local rh = GameObj.right_hand()
    if rh and rh.id then
        rewards[#rewards + 1] = rh
        if not rewards_by_tier[tier] then rewards_by_tier[tier] = {} end
        rewards_by_tier[tier][rh.name] = (rewards_by_tier[tier][rh.name] or 0) + 1
    end

    fput("stow all")

    processed_keys[#processed_keys + 1] = key.id
    processed_locks[#processed_locks + 1] = lock.id
    pairs_by_tier[tier] = (pairs_by_tier[tier] or 0) + 1
end

local function process_matches(keys, locks, key_tier, key_color, lock_tier, lock_color)
    local available_keys = {}
    for _, k in ipairs(keys) do
        if not table_contains(processed_keys, k.id) and matches_pattern(k.name, key_tier, key_color, "key") then
            available_keys[#available_keys + 1] = k
        end
    end

    local available_locks = {}
    for _, l in ipairs(locks) do
        if not table_contains(processed_locks, l.id) and matches_pattern(l.name, lock_tier, lock_color, "lock") then
            available_locks[#available_locks + 1] = l
        end
    end

    local lock_idx = 1
    for _, key in ipairs(available_keys) do
        if lock_idx > #available_locks then break end
        unlock_pair(key, available_locks[lock_idx], key_tier)
        lock_idx = lock_idx + 1
    end
end

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

local function print_report()
    if #rewards == 0 then return end

    respond("")
    respond(string.rep("=", 60))
    respond("KeyMaster Rewards Summary")
    respond(string.rep("=", 60))

    for _, tier in ipairs(TIERS) do
        if pairs_by_tier[tier] > 0 then
            respond("")
            respond(tier:sub(1, 1):upper() .. tier:sub(2) .. " Tier:")
            respond("  Pairs processed: " .. pairs_by_tier[tier])

            local tier_rewards = rewards_by_tier[tier]
            if tier_rewards then
                local has_any = false
                for _ in pairs(tier_rewards) do has_any = true; break end
                if has_any then
                    respond("  Rewards:")
                    for name, count in pairs(tier_rewards) do
                        respond("    " .. name .. " x" .. count)
                    end
                end
            end
        end
    end

    respond("")
    respond(string.rep("-", 60))
    respond("Total pairs processed: " .. #processed_keys)
    respond("Total rewards: " .. #rewards)
    respond(string.rep("=", 60))
    respond("")
end

--------------------------------------------------------------------------------
-- Main execution
--------------------------------------------------------------------------------

-- Empty hands first
fput("stow all")

local keys, locks = find_items()

-- Phase 1: exact tier+color matches (non-wildcard)
for _, tier in ipairs(TIERS) do
    for _, color in ipairs(COLORS) do
        process_matches(keys, locks, tier, color, tier, color)
    end
end

-- Phase 2: wildcard matches
for _, tier in ipairs(TIERS) do
    for _, color in ipairs(COLORS) do
        process_matches(keys, locks, tier, color, tier, WILDCARD)
    end
    for _, color in ipairs(COLORS) do
        process_matches(keys, locks, tier, WILDCARD, tier, color)
    end
end

print_report()

-- Restore hands
fput("fill hands")
