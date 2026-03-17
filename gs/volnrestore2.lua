--- @revenant-script
--- name: volnrestore2
--- version: 1.4.1
--- author: Kyrandos
--- game: gs
--- tags: voln, symbol, restoration, heal
--- description: Improved Voln Symbol of Restoration with death handling and configurable thresholds
---
--- Original Lich5 authors: Kyrandos
--- Ported to Revenant Lua from volnrestore2.lic v1.4.1
---
--- Usage:
---   ;volnrestore2              - start monitoring
---   ;volnrestore2 set          - show current settings
---   ;volnrestore2 set key val  - change a setting

local DEFAULTS = {
    low_threshold = 65,
    heal_target = 95,
    max_casts = 3,
    pause_between = 0.5,
}

local config = UserVars.load("volnrestore") or {}

local function setting(key)
    return config[key] or DEFAULTS[key]
end

local function show_settings()
    echo("VolnRestore2 current settings:")
    echo("  low_threshold:  " .. setting("low_threshold") .. "%")
    echo("  heal_target:    " .. setting("heal_target") .. "%")
    echo("  max_casts:      " .. setting("max_casts"))
    echo("  pause_between:  " .. setting("pause_between"))
    echo("")
    echo("Change with: ;volnrestore2 set <key> <value>")
end

local function percent_hp()
    local max = GameState.max_health or 0
    if max <= 0 then return 100 end
    return math.floor((GameState.health / max) * 100)
end

local function heal()
    local hp = percent_hp()
    echo("*** HP critical (" .. hp .. "%)! Invoking Symbol of Restoration ***")

    local casts = 0
    while percent_hp() < setting("heal_target") and not checkdead() and casts < setting("max_casts") do
        local result = fput("symbol restoration", "You feel|while dead|You cannot")
        if not result or checkdead() or (result and Regex.test(result, "while dead|You cannot")) then
            break
        end
        waitrt()
        casts = casts + 1
        if casts < setting("max_casts") then
            wait(setting("pause_between"))
        end
    end

    if checkdead() then
        echo("*** Died mid-restore! Pausing until alive. ***")
        wait_until(function() return not checkdead() end)
        echo("Revived! Resuming monitoring.")
    else
        echo("Restore cycle complete. Current HP: " .. percent_hp() .. "% (" .. casts .. " casts used)")
    end
end

before_dying(function() echo("VolnRestore2 stopped.") end)

local args = Script.current.vars

if args[1] == "set" then
    if not args[2] then
        show_settings()
    else
        local i = 2
        local changed = false
        while i <= #args do
            local key = args[i]
            local val = args[i + 1]
            if val and val:match("^%d+%.?%d*$") then
                if DEFAULTS[key] then
                    config[key] = tonumber(val)
                    echo("Set volnrestore[" .. key .. "] = " .. val)
                    changed = true
                    i = i + 2
                else
                    echo("Unknown setting: " .. key)
                    i = i + 1
                end
            else
                echo("Invalid format - expected: set <key> <number>")
                break
            end
        end
        if changed then
            UserVars.save("volnrestore", config)
            echo("Settings saved.")
        end
    end
    return
end

echo("VolnRestore2 started. Monitoring HP via polling...")
echo("Low threshold: " .. setting("low_threshold") .. "% | Heal to: " .. setting("heal_target") .. "%")
echo("Max casts per trigger: " .. setting("max_casts") .. " | Pause between casts: " .. setting("pause_between") .. "s")

while true do
    if not checkdead() and percent_hp() < setting("low_threshold") then
        heal()
    end
    wait(1)
end
