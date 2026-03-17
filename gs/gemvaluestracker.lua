--- @revenant-script
--- name: gemvaluestracker
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Track gem appraisal values and compute averages over time
--- tags: gems, appraise, tracker, value
---
--- Usage:
---   ;gemvaluestracker         - start tracking (runs in background)
---   ;gemvaluestracker reset   - clear cached gem prices
---   ;gemvaluestracker list    - display all tracked gem data

no_pause_all()
no_kill_all()

-- Persistent gem price storage (global table, survives across script restarts in same session)
if not _G.gem_prices then
    _G.gem_prices = {}
end

local function main_loop()
    while true do
        local line = get()
        if line then
            -- Match gemcutter offer patterns
            local gem_name, gem_value_str

            -- Pattern: "The gemcutter takes the X and inspects it carefully...give you N silvers"
            gem_name, gem_value_str = line:match("The gemcutter takes the (.-) and inspects it carefully.-give you ([%d,]+) silvers")

            -- Pattern: "The gemcutter Zirconia takes the X, gives it a careful examination and hands you N silver for it."
            if not gem_name then
                gem_name, gem_value_str = line:match("The gemcutter Zirconia takes the (.-), gives it a careful examination and hands you ([%d,]+) silver")
            end

            if gem_name and gem_value_str then
                gem_name = gem_name:match("^%s*(.-)%s*$")
                local gem_value = tonumber((gem_value_str:gsub(",", "")))

                if gem_value and gem_value > 0 then
                    if _G.gem_prices[gem_name] then
                        _G.gem_prices[gem_name].count = _G.gem_prices[gem_name].count + 1
                        _G.gem_prices[gem_name].total = _G.gem_prices[gem_name].total + gem_value
                    else
                        _G.gem_prices[gem_name] = { count = 1, total = gem_value }
                    end

                    _G.gem_prices[gem_name].average = math.floor(
                        _G.gem_prices[gem_name].total / _G.gem_prices[gem_name].count + 0.5
                    )

                    echo("[gemvaluestracker: *** Saved value: " .. gem_name .. " => " .. gem_value .. " silvers]")
                    echo("[gemvaluestracker: Seen " .. _G.gem_prices[gem_name].count .. "x | Average: " .. _G.gem_prices[gem_name].average .. " silvers]")
                end
            end
        end
    end
end

local arg1 = Script.vars[1]

if arg1 and arg1:match("reset") then
    _G.gem_prices = {}
    echo("[gemvaluestracker: Gem prices cache reset.]")
elseif arg1 and arg1:match("list") then
    if not _G.gem_prices or not next(_G.gem_prices) then
        echo("[gemvaluestracker: No gem data recorded yet.]")
    else
        for name, data in pairs(_G.gem_prices) do
            echo(string.format("  %s: count=%d, total=%d, avg=%d", name, data.count, data.total, data.average))
        end
    end
else
    main_loop()
end
