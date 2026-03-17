--- @revenant-script
--- name: portkey
--- version: 1.1.0
--- author: elanthia-online
--- game: gs
--- description: Automated chronomage day pass usage between towns
--- tags: chronomage,day pass,travel,go2
---
--- Changelog (from Lich5):
---   v1.1.0 (2025-03-05) - Ta'Illistim <-> Ta'Vaalor support, silver check, inventory fix

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PASS_NAME = "Chronomage day pass"
local DEPARTURES = { "8635", "15619", "1276", "13779" }
local CHRONOMAGES = { "8634", "8916", "5883", "13169" }

local TELEPORT_RX = Regex.new("whirlwind of color subsides")
local EXPIRED_RX  = Regex.new("pass is expired|not valid for departures")
local TOSSED_RX   = Regex.new("As you let go")
local BOUGHT_RX   = Regex.new("quickly hands")
local WITHDRAW_RX = Regex.new("carefully records|through the books")
local POOR_RX     = Regex.new("don't have enough")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function go2(dest)
    Script.run("go2", tostring(dest))
    wait_while(function() return running("go2") end)
end

local function opposite_town()
    local room = Room.current()
    if not room or not room.location then
        echo("Unknown location")
        return nil
    end
    local loc = room.location:lower()
    if loc:find("mule") then return "wehnimer's landing" end
    if loc:find("landing") then return "icemule" end
    if loc:find("victory") then return "ta'illistim" end
    if loc:find("lost home") then return "ta'vaalor" end
    echo("Unhandled location: " .. loc)
    return nil
end

local function find_nearest(room_list)
    local room = Room.current()
    if not room then return nil end
    return room:find_nearest(room_list)
end

--------------------------------------------------------------------------------
-- Pass management
--------------------------------------------------------------------------------

local function find_pass_in_inventory()
    -- Check hands first
    local lh = GameObj.left_hand()
    local rh = GameObj.right_hand()
    if lh and lh.name == PASS_NAME then return lh end
    if rh and rh.name == PASS_NAME then return rh end

    -- Check containers
    local containers = GameObj.inv()
    if containers then
        for _, container in ipairs(containers) do
            local contents = container.contents
            if contents then
                for _, item in ipairs(contents) do
                    if item.name == PASS_NAME then return item end
                end
            end
        end
    end
    return nil
end

local function buy_pass()
    local opp = opposite_town()
    if not opp then return nil end

    -- Check if we need silver
    if Char.silver < 5000 then
        go2("bank")
        fput("withdraw 5000 silver")
    end

    -- Go to chronomage
    local nearest = find_nearest(CHRONOMAGES)
    if nearest then go2(nearest) end

    -- Ask for a pass
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if npc.name and Regex.test("halfling|clerk|attendant|agent", npc.name) then
            fput("ask #" .. npc.id .. " for " .. opp)
            pause(0.5)
            fput("ask #" .. npc.id .. " for " .. opp)
            break
        end
    end

    pause(1)
    return find_pass_in_inventory()
end

local function use_pass(pass)
    if not pass then return false end

    -- Get it in hand
    fput("get #" .. pass.id)
    pause(0.5)

    local result = dothistimeout("raise #" .. pass.id, 5, {
        "whirlwind of color subsides",
        "pass is expired",
        "not valid for departures",
    })

    if result and (result:find("expired") or result:find("not valid")) then
        fput("drop #" .. pass.id)
        return false  -- Need to buy a new one
    end

    return true
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

wait_while(function() return running("go2") end)

-- Find or buy a pass
local pass = find_pass_in_inventory()
if not pass then
    pass = buy_pass()
end

if not pass then
    echo("Could not find or buy a chronomage day pass.")
    return
end

if hidden() then fput("unhide") end

-- Go to nearest departure annex
local annex = find_nearest(DEPARTURES)
if annex then go2(annex) end

-- Use the pass
local success = use_pass(pass)
if not success then
    -- Expired, buy a new one and retry
    pass = buy_pass()
    if pass then
        local annex2 = find_nearest(DEPARTURES)
        if annex2 then go2(annex2) end
        use_pass(pass)
    end
end

-- Navigate to the requested destination if provided
local dest = Script.vars[1]
if dest and dest ~= "" then
    go2(dest)
end
