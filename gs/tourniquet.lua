--- @revenant-script
--- name: tourniquet
--- version: 1.1.1
--- author: elanthia-online
--- contributors: Dissonance
--- game: gs
--- description: Manage bleeding using society abilities (Voln/Sunfist/CoL)
--- tags: health,bleeding,society
---
--- Changelog (from Lich5):
---   v1.1.1 (2025-05-21) - refined voln handling for bleeding/bloodloss
---   v1.1.0 (2025-05-10) - added Sign of Healing from CoL
---   v1.0.0 (2025-04-30) - created

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function load_int(key, default)
    local v = tonumber(CharSettings[key])
    return v or default
end

local function load_bool(key, default)
    local v = CharSettings[key]
    if v == nil or v == "" then return default end
    return v == "true"
end

local data = {
    start_healing      = load_int("tourniquet_start", 65),
    stop_healing       = load_int("tourniquet_stop", 95),
    min_heal           = load_int("tourniquet_min", 20),
    debug              = load_bool("tourniquet_debug", false),
    use_col_healing    = load_bool("tourniquet_col", false),
    min_spirit         = load_int("tourniquet_spirit", (Char.max_spirit or 10) - 2),
    start_sign_healing = load_int("tourniquet_sign_start", 65),
}

local function save_settings()
    CharSettings["tourniquet_start"]      = tostring(data.start_healing)
    CharSettings["tourniquet_stop"]       = tostring(data.stop_healing)
    CharSettings["tourniquet_min"]        = tostring(data.min_heal)
    CharSettings["tourniquet_debug"]      = tostring(data.debug)
    CharSettings["tourniquet_col"]        = tostring(data.use_col_healing)
    CharSettings["tourniquet_spirit"]     = tostring(data.min_spirit)
    CharSettings["tourniquet_sign_start"] = tostring(data.start_sign_healing)
end

before_dying(function() save_settings() end)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function dbg(msg)
    if data.debug then echo("[tourniquet] " .. msg) end
end

local function stop_healing()
    local low_heal = (Char.max_health - Char.health) <= data.min_heal
    local high_pct = Char.percent_health >= data.stop_healing
    return low_heal or high_pct or dead()
end

local function still_bleeding()
    return (checkreallybleeding() or checkpoison() or checkdisease()) and not dead()
end

local function check_society_ability()
    local spells = {
        "Symbol of Restoration", "Sigil of Mending", "Sigil of Health",
        "Sign of Staunching", "Sign of Clotting", "Sign of Healing"
    }
    for _, name in ipairs(spells) do
        local sp = Spell[name]
        if sp and sp.known then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Society-specific healing
--------------------------------------------------------------------------------

local function use_restoration()
    local sp = Spell["Symbol of Restoration"]
    if not sp or not sp.known then return end

    -- Wait until health drops to threshold or bleeding stops
    while Char.percent_health >= data.start_healing and still_bleeding() do
        pause(0.5)
    end

    if Char.percent_health < data.start_healing then
        dbg("Using Symbol of Restoration...")
        while not stop_healing() do
            if sp.affordable then
                fput("symbol of restoration")
            end
            pause(0.5)
        end
    end
end

local function use_col_staunching()
    local staunch = Spell["Sign of Staunching"]
    local clot = Spell["Sign of Clotting"]

    if staunch and staunch.known and staunch.affordable and not staunch.active then
        dbg("Using Sign of Staunching...")
        fput("sign of staunching")
    elseif clot and clot.known and clot.affordable and not clot.active then
        dbg("Using Sign of Clotting...")
        fput("sign of clotting")
    end
end

local function use_col_healing()
    local sp = Spell["Sign of Healing"]
    if not sp or not sp.known or not sp.affordable then return end
    if Char.spirit < data.min_spirit or Char.spirit < 3 then return end

    if Char.percent_health <= data.start_sign_healing then
        dbg("Using Sign of Healing...")
        fput("sign of healing")
    end
end

local function use_mending_and_health()
    local mending = Spell["Sigil of Mending"]
    if mending and mending.known and mending.affordable and not mending.active then
        dbg("Using Sigil of Mending...")
        fput("sigil of mending")
    end

    if Char.percent_health < data.start_healing then
        local health = Spell["Sigil of Health"]
        if health and health.known then
            while not stop_healing() and health.affordable do
                fput("sigil of health")
                pause(0.5)
            end
        end
    end
end

local function wait_for_bloodloss()
    dbg("Waiting for bloodloss...")
    while true do
        if dead() then
            pause(0.75)
        elseif (checkreallybleeding() or checkpoison() or checkdisease()) and Char.percent_health < data.stop_healing then
            break
        elseif Char.percent_health < data.start_healing then
            break
        end
        pause(0.25)
    end
    respond("[Tourniquet] You're losing blood...")
end

local function wait_special_room()
    while checkroom("The Belly of the Beast") or checkroom("Ooze, Innards") or checkroom("Temporal Rift") or dead() do
        pause(1)
    end
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

local function main()
    if not check_society_ability() then
        echo("No applicable society ability found.")
        return
    end

    echo("Tourniquet active. Watching for health loss...")

    while true do
        wait_special_room()

        local society = Society.member or ""
        if society:lower():find("voln") then
            wait_for_bloodloss()
            use_restoration()
        elseif society:lower():find("sunfist") then
            wait_for_bloodloss()
            use_mending_and_health()
        elseif society:lower():find("council") then
            wait_for_bloodloss()
            use_col_staunching()
            if data.use_col_healing then
                use_col_healing()
            end
        else
            echo("Unknown society: " .. society)
            pause(5)
        end

        pause(0.25)
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("Tourniquet - Bleeding management via society abilities")
    respond("")
    respond("  ;tourniquet start              Run the script")
    respond("  ;tourniquet help               Show this help")
    respond("  ;tourniquet settings            Show current settings")
    respond("  ;tourniquet health_min=N        Start healing at N% health")
    respond("  ;tourniquet health_max=N        Stop healing at N% health")
    respond("  ;tourniquet min_heal=N          Minimum HP to heal")
    respond("  ;tourniquet use_col_healing=on  Enable CoL Sign of Healing")
    respond("  ;tourniquet reset              Reset to defaults")
    respond("  ;tourniquet debug              Toggle debug mode")
    respond("")
end

local function set_value(key, val)
    if val == "on" or val == "true" then
        data[key] = true
    elseif val == "off" or val == "false" then
        data[key] = false
    elseif tonumber(val) then
        data[key] = tonumber(val)
    else
        echo("Invalid value: " .. tostring(val))
        return
    end
    echo(key .. " set to " .. tostring(data[key]))
    save_settings()
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]

if not arg1 or arg1 == "" then
    show_help()
elseif arg1:lower():find("start") then
    main()
elseif arg1:lower():find("help") then
    show_help()
elseif arg1:lower():find("health_min") then
    set_value("start_healing", arg1:match("(%d+)"))
elseif arg1:lower():find("health_max") then
    set_value("stop_healing", arg1:match("(%d+)"))
elseif arg1:lower():find("min_heal") then
    set_value("min_heal", arg1:match("(%d+)"))
elseif arg1:lower():find("use_col") then
    local val = arg1:match("=%s*(%w+)")
    set_value("use_col_healing", val)
elseif arg1:lower():find("min_spirit") then
    set_value("min_spirit", arg1:match("(%d+)"))
elseif arg1:lower():find("settings") then
    respond("Current Settings: " .. Json.encode(data))
elseif arg1:lower():find("reset") then
    data.start_healing = 65
    data.stop_healing = 95
    data.min_heal = 20
    data.use_col_healing = false
    data.min_spirit = (Char.max_spirit or 10) - 2
    data.debug = false
    data.start_sign_healing = 65
    save_settings()
    respond("Settings reset to defaults.")
elseif arg1:lower():find("debug") then
    data.debug = not data.debug
    save_settings()
    echo("Debug mode: " .. tostring(data.debug))
else
    show_help()
end
