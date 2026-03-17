local data = require("data")
local inventory = require("inventory")

local M = {}

function M.sell_gemshop(state)
    Script.run("go2", "gemshop")
    pause(0.5)

    -- Sell gems from sell container
    local container = state.sell_container or state.overflow_container or ""
    if container == "" then
        respond("[eloot] No sell container configured")
        return 0
    end

    local sold = 0
    -- Get items from container, sell each gem
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item:type_p("gem") or item:type_p("valuable") then
            local dominated = false
            for _, excl in ipairs(state.sell_exclude or {}) do
                if item.name:lower():find(excl:lower(), 1, true) then dominated = true; break end
            end
            if not dominated then
                waitrt()
                fput("sell #" .. item.id)
                sold = sold + 1
            end
        end
    end

    respond("[eloot] Sold " .. sold .. " gems")
    return sold
end

function M.sell_furrier(state)
    Script.run("go2", "furrier")
    pause(0.5)

    local sold = 0
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item:type_p("skin") then
            local dominated = false
            for _, excl in ipairs(state.sell_exclude or {}) do
                if item.name:lower():find(excl:lower(), 1, true) then dominated = true; break end
            end
            if not dominated then
                waitrt()
                fput("sell #" .. item.id)
                sold = sold + 1
            end
        end
    end

    respond("[eloot] Sold " .. sold .. " skins")
    return sold
end

function M.sell_pawnshop(state)
    Script.run("go2", "pawnshop")
    pause(0.5)

    local sold = 0
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item:type_p("wand") or item:type_p("scroll") then
            -- Check scroll keep list
            local dominated = false
            for _, excl in ipairs(state.sell_exclude or {}) do
                if item.name:lower():find(excl:lower(), 1, true) then dominated = true; break end
            end
            for _, keep_num in ipairs(state.sell_keep_scrolls or {}) do
                if item.name:find(tostring(keep_num)) then dominated = true; break end
            end
            if not dominated then
                waitrt()
                fput("sell #" .. item.id)
                sold = sold + 1
            end
        end
    end

    respond("[eloot] Sold " .. sold .. " items at pawnshop")
    return sold
end

function M.appraise(item, state)
    fput("appraise #" .. item.id)
    local line = waitfor("worth", 3)
    if line then
        local value = line:match("(%d[%d,]*) silvers")
        if value then
            return tonumber(value:gsub(",", "")) or 0
        end
    end
    return 0
end

function M.deposit(state)
    Script.run("go2", "bank")
    pause(0.5)
    fput("deposit all")
    respond("[eloot] Deposited all silver")
end

function M.sell_cycle(state)
    local start_room = Map.current_room()
    local total_sold = 0

    respond("[eloot] Starting sell cycle...")

    -- Check what we have to sell
    local has_gems = false
    local has_skins = false
    local has_scrolls = false
    local inv = GameObj.inv()

    for _, item in ipairs(inv) do
        if item:type_p("gem") or item:type_p("valuable") then has_gems = true end
        if item:type_p("skin") then has_skins = true end
        if item:type_p("wand") or item:type_p("scroll") then has_scrolls = true end
    end

    -- Sell at each shop that has matching items
    if has_gems then total_sold = total_sold + M.sell_gemshop(state) end
    if has_skins then total_sold = total_sold + M.sell_furrier(state) end
    if has_scrolls then total_sold = total_sold + M.sell_pawnshop(state) end

    -- Deposit
    M.deposit(state)

    -- Return
    if start_room then
        Script.run("go2", tostring(start_room))
    end

    respond("[eloot] Sell cycle complete. Sold " .. total_sold .. " items.")
    return total_sold
end

return M
