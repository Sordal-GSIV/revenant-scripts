--- @revenant-script
--- name: voln_favor
--- version: 1.0.1
--- author: elanthia-online
--- game: gs
--- description: Voln favor tracking using the RESOURCE command
--- tags: voln,favor
---
--- Changelog (from Lich5):
---   v1.0.1 (2023-09-18) - bugfix for resource squelching, remove quiet mode
---   v1.0.0 (2021-10-27) - renamed from asexualfavors, updated regex
---   v0.0.6 (2020-11-11) - Updated to newest Oleani, pushed to EO

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local symbol_favor = tonumber(CharSettings["voln_symbol"]) or 0
local step_favor   = tonumber(CharSettings["voln_step"]) or 0
local initial_done = CharSettings["voln_initial"] == "true"

local function save_settings()
    CharSettings["voln_symbol"]  = tostring(symbol_favor)
    CharSettings["voln_step"]    = tostring(step_favor)
    CharSettings["voln_initial"] = tostring(initial_done)
end

--------------------------------------------------------------------------------
-- Pray messages (vision text -> fraction of step)
--------------------------------------------------------------------------------

local PRAY_MESSAGES = {
    ["vision of a flower that has not yet begun to open"] = 0,
    ["vision of a baby eagle barely hatched from its egg"] = 0.10,
    ["vision of a butterfly drying its wings on a leaf"] = 0.20,
    ["vision of the headwaters of a mighty river"] = 0.30,
    ["vision of a weaver on a loom, nearly half way in the creation of an intricate tapestry"] = 0.40,
    ["brief vision of twin bowls of wine"] = 0.50,
    ["vision of a hiker as he clears the peak of a hill and begins to descend the other side"] = 0.60,
    ["vision of a lute, finely crafted, but missing a third of its strings"] = 0.70,
    ["vision of a rainbow forming as a thunder storm begins to abate"] = 0.80,
    ["vision of a path as it winds its way through a forest and to the edge of a clear pool"] = 0.90,
    ["vision of a pool of clear water"] = 1.0,
}

local UNDEAD_RELEASE_RX = Regex.new("sound like a .+? as a white glow separates")
local RANK_UP_RX = Regex.new("The (?:.*?)monk(?:.*?) concludes ceremoniously.*Go now and continue your work\\.")
local PRAY_RX = Regex.new("^After a few moments of prayer and reflection you see a (.*?)\\.")
local FAVOR_RX = Regex.new("Voln Favor: ([0-9,]+)")

--------------------------------------------------------------------------------
-- Favor calculation
--------------------------------------------------------------------------------

local function favor_to_step()
    local rank = Society.rank or 0
    local level = Char.level or 0
    return (rank * 100) + math.floor(((level * level) * (math.floor((rank + 2) / 3) * 5)) / 3)
end

local function format_number(n)
    local s = tostring(n)
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function update_favor(new_favor)
    local last_favor = symbol_favor
    local change = new_favor - last_favor
    local gain = change > 0 and change or 0

    symbol_favor = new_favor
    step_favor = step_favor + gain

    local step_total = favor_to_step()
    local pct = step_total > 0 and math.floor((step_favor * 100) / step_total) or 0

    if change ~= 0 then
        local msg = "[Total Favor: " .. format_number(symbol_favor) .. " | Change: " .. tostring(change)
        if Society.rank and Society.rank < 26 then
            msg = msg .. " | Step: " .. format_number(step_favor) .. "/" .. format_number(step_total) .. " (" .. pct .. "%)"
        end
        msg = msg .. "]"
        respond(msg)
    end

    save_settings()
end

--------------------------------------------------------------------------------
-- Society check
--------------------------------------------------------------------------------

if not Society.status or not Society.status:find("Voln") then
    fput("society")
    pause(2)
    if not Society.status or not Society.status:find("Voln") then
        echo("You don't seem to be a member of Voln. This script isn't for you.")
        return
    end
end

if not initial_done and Society.rank and Society.rank < 26 then
    echo("FIRST TIME RUNNING NOTICE: Please calibrate voln_favor by praying at a Voln Temple.")
    initial_done = true
    save_settings()
end

--------------------------------------------------------------------------------
-- Downstream hook: capture resource output
--------------------------------------------------------------------------------

local HOOK_NAME = "voln_favor_hook"
local capturing_resource = false

DownstreamHook.add(HOOK_NAME, function(line)
    if not line then return line end

    if line:find("Health: %d+") and capturing_resource then
        -- Start squelching resource output
        return nil
    end

    if line:find('<output class=""') then
        capturing_resource = false
    end

    if capturing_resource then return nil end
    return line
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
    save_settings()
end)

--------------------------------------------------------------------------------
-- Request resource periodically
--------------------------------------------------------------------------------

local function request_resource()
    capturing_resource = true
    put("resource")
end

-- Initial request
request_resource()

--------------------------------------------------------------------------------
-- Upstream hook: catch favor/symbol commands
--------------------------------------------------------------------------------

local UPSTREAM_HOOK_ID = "voln_favor_upstream"

UpstreamHook.add(UPSTREAM_HOOK_ID, function(command)
    local clean = command:gsub("^<c>", ""):lower()
    if clean:match("^favor") or clean:match("^favo") then
        local step_total = favor_to_step()
        local pct = step_total > 0 and math.floor((step_favor * 100) / step_total) or 0
        respond("")
        respond("     Total Favor: " .. format_number(symbol_favor))
        if Society.rank and Society.rank < 26 then
            respond("    Current Step: " .. format_number(step_favor) .. "/" .. format_number(step_total) .. " (" .. pct .. "%)")
        end
        respond("")
        return nil
    end
    if clean:match("^symbol") or clean:match("^sym") then
        -- Trigger a resource refresh after symbol use
        request_resource()
    end
    return command
end)

before_dying(function()
    UpstreamHook.remove(UPSTREAM_HOOK_ID)
end)

--------------------------------------------------------------------------------
-- Main loop: monitor downstream for favor updates
--------------------------------------------------------------------------------

echo("VOLN-FAVOR v1.0.1 running.")

while true do
    local line = get()
    if not line then break end

    -- Undead release -> refresh resource
    if UNDEAD_RELEASE_RX:test(line) then
        request_resource()
    end

    -- Rank up -> reset step
    if RANK_UP_RX:test(line) then
        step_favor = 0
        request_resource()
    end

    -- Prayer vision -> calibrate step
    local pray_match = PRAY_RX:match(line)
    if pray_match then
        local vision = pray_match[1]
        local fraction = PRAY_MESSAGES[vision]
        if fraction then
            local step_total = favor_to_step()
            if fraction == 1 then
                step_favor = step_total
            else
                local floor_f = math.ceil(step_total * fraction)
                local ceil_f  = math.ceil(step_total * (fraction + 0.1))
                if step_favor < floor_f or step_favor > ceil_f then
                    step_favor = floor_f
                end
            end
        end
        request_resource()
    end

    -- Favor line from resource output
    local favor_match = FAVOR_RX:match(line)
    if favor_match then
        local favor_str = favor_match[1]:gsub(",", ""):gsub("%s", "")
        local favor_num = tonumber(favor_str)
        if favor_num then
            update_favor(favor_num)
        end
    end
end
