--- @revenant-script
--- name: guidebook
--- version: 1.0.8
--- author: elanthia-online
--- contributors: Tysong
--- game: gs
--- description: EG Guidebook Companion — friendly formatted merchant/raffle display
--- tags: eg,ebon gate,guidebook,merchant,raffle
---
--- Usage:
---   ;guidebook                      show merchants and raffles
---   ;guidebook merchant             show only merchants
---   ;guidebook raffle               show only raffles
---   ;guidebook help                 show help
---
--- Requires guidebook on character, readable, flipped to epilogue.

local TableRender = require("lib/table_render")
local Messaging = require("lib/messaging")

local function show_help()
    echo("EG Guidebook Companion")
    echo("")
    echo("  ;guidebook            show merchants and raffles")
    echo("  ;guidebook m[erchant] show only merchants")
    echo("  ;guidebook r[affle]   show only raffles")
    echo("")
    echo("Requires guidebook on character, flipped to epilogue (Chapter 14).")
end

local function parse_guidebook()
    local output = quiet_command("read guidebook", "You can't do that|Epilogue", 5)
    if not output then
        echo("Could not read guidebook. Make sure it is accessible and on the epilogue.")
        return nil, nil
    end

    local full_text = table.concat(output, "\n")
    if full_text:find("You can't do that") or not full_text:find("Epilogue") then
        echo("Guidebook not readable or not on the epilogue page.")
        return nil, nil
    end

    local merchants = {}
    local raffles = {}

    for _, line in ipairs(output) do
        -- Merchant pattern: #N  Name   Room   [Shop Entrance]
        local m_name, m_room = line:match("#%d+%s+(.-)%s%s+(.-)%s%s+.*%[Shop Entrance%]")
        if m_name then
            merchants[#merchants + 1] = {
                name = m_name:match("^%s*(.-)%s*$"),
                room = m_room:match("^%s*(.-)%s*$"),
            }
        end

        -- Raffle pattern: #N  Name  Room  DateTime  Cost
        local r_name, r_room, r_datetime, r_cost = line:match(
            "#%d+%s+(%w+)%s+(.-)%s+(%d+/%d+/%d+ %d+:%d+:%d+) %w+%s+([%d,]+)")
        if r_name then
            raffles[#raffles + 1] = {
                name = r_name,
                room = r_room:match("^%s*(.-)%s*$"),
                datetime = r_datetime,
                cost = r_cost,
            }
        end
    end

    return merchants, raffles
end

local function show_merchants(merchants)
    if not merchants or #merchants == 0 then
        respond("No merchants working currently!")
        return
    end

    local tbl = TableRender.new({"Merchant", "Room"})
    for _, m in ipairs(merchants) do
        tbl:add_row({m.name, m.room})
    end
    tbl:add_separator()
    tbl:add_row({"Total: " .. #merchants .. " Merchant(s)", ""})
    Messaging.mono(tbl:render())
end

local function show_raffles(raffles)
    if not raffles or #raffles == 0 then
        respond("No raffles currently!")
        return
    end

    local tbl = TableRender.new({"Merchant", "Room", "DateTime", "Cost"})
    for _, r in ipairs(raffles) do
        tbl:add_row({r.name, r.room, r.datetime, r.cost})
    end
    tbl:add_separator()
    tbl:add_row({"Total: " .. #raffles .. " Raffle(s)", "", "", ""})
    Messaging.mono(tbl:render())
end

-- Main
local action = Script.vars[1]

if action and action:lower() == "help" then
    show_help()
    return
end

local merchants, raffles = parse_guidebook()
if not merchants and not raffles then return end

local show_m = true
local show_r = true

if action then
    local a = action:lower()
    if a:match("^m") then show_r = false end
    if a:match("^r") then show_m = false end
end

if show_m then show_merchants(merchants) end
if show_r then show_raffles(raffles) end
