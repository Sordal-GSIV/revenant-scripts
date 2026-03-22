--- @revenant-script
--- name: isigns_new
--- version: 3.1.1
--- author: Ifor Get
--- maintainer: Kaldonis
--- game: gs
--- tags: council of light, signs, upkeep, automation
--- description: Council of Light Signs upkeep with GUI setup support
---
--- Original Lich5 authors: Ifor Get, Kaldonis, Doug
--- Ported to Revenant Lua from isigns_new.lic v3.1
---
--- @lic-certified: complete 2026-03-19
---
--- Changelog:
---   02 Nov 2025 (v3.1): Added CharSettings.load and before_dying wrapper for proper persistence
---                        Removed GTK2 compatibility, cleaned up code
---   27 Jan 2018: Kaldonis as new maintainer
---     Includes feature to autopause in anti-magic room, code robbed from Drafix's old ;haste
---   30 March 2021: Doug gives update for GTK3 / lich5
---
--- Usage:
---   ;isigns_new          - run sign upkeep
---   ;isigns_new setup    - configure which signs to maintain (GUI)
---   ;isigns_new help     - show help

-- ── Sign definitions ──────────────────────────────────────────────────────────

-- Ordered list matches original GTK checkbox order
local SIGN_ORDER = { "9903", "9904", "9905", "9906", "9907", "9908", "9909", "9910", "9912", "9913", "9914" }

local SIGNS = {
    ["9903"] = { label = "Sign of Warding: +5 to DS",                        cost = "1 Mana" },
    ["9904"] = { label = "Sign of Striking: +5 to AS",                       cost = "1 Mana" },
    ["9905"] = { label = "Sign of Clotting: Stops all bleeding",              cost = "1 Mana" },
    ["9906"] = { label = "Sign of Thought: Amunet",                          cost = "1 Mana" },
    ["9907"] = { label = "Sign of Defending: +10 to DS",                     cost = "2 Mana" },
    ["9908"] = { label = "Sign of Smiting: +10 to AS",                       cost = "2 Mana" },
    ["9909"] = { label = "Sign of Staunching: Stops bleeding, 2x duration",  cost = "1 Mana" },
    ["9910"] = { label = "Sign of Deflection: +20 Bolt DS",                  cost = "3 Mana" },
    ["9912"] = { label = "Sign of Swords: +20 AS",                           cost = "1 Spirit, drained at end" },
    ["9913"] = { label = "Sign of Shields: +20 DS",                          cost = "1 Spirit, drained at end" },
    ["9914"] = { label = "Sign of Dissipation: +15 TD",                      cost = "1 Spirit, drained at end" },
}

-- CharSettings key prefix
local PREFIX = "isigns_"

-- ── Settings ──────────────────────────────────────────────────────────────────

local function load_settings()
    local s = {}
    for _, num in ipairs(SIGN_ORDER) do
        s[num] = CharSettings[PREFIX .. num] == "true"
    end
    return s
end

local function save_settings(s)
    for num, active in pairs(s) do
        CharSettings[PREFIX .. num] = active and "true" or nil
    end
end

-- ── Help ──────────────────────────────────────────────────────────────────────

local function show_help()
    respond("")
    respond("Usage:")
    respond("   ;isigns_new          run sign upkeep")
    respond("   ;isigns_new setup    configure signs (GUI)")
    respond("   ;isigns_new help     show this message")
    respond("")
    respond("Signs managed:")
    for _, num in ipairs(SIGN_ORDER) do
        local sign = SIGNS[num]
        respond(string.format("  %s  %-45s (%s)", num, sign.label, sign.cost))
    end
    respond("")
end

-- ── GUI setup ─────────────────────────────────────────────────────────────────

local function gui_setup(settings)
    local win = Gui.window("iSigns 3.1 - Council of Light Sign Upkeep",
        { width = 480, height = 420, resizable = false })
    local root = Gui.vbox()

    -- Checkboxes — label includes mana/spirit cost (mirrors original tooltips)
    local checks = {}
    for _, num in ipairs(SIGN_ORDER) do
        local sign = SIGNS[num]
        local label = sign.label .. "  (" .. sign.cost .. ")"
        local cb = Gui.checkbox(label, settings[num])
        checks[num] = cb
        root:add(cb)
    end

    -- Mutual exclusion: Clotting and Staunching cannot both be active
    -- (mirrors Lich5 GTK signal_connect toggled)
    checks["9905"]:on_change(function(checked)
        if checked then checks["9909"]:set_checked(false) end
    end)
    checks["9909"]:on_change(function(checked)
        if checked then checks["9905"]:set_checked(false) end
    end)

    root:add(Gui.separator())

    local save_btn = Gui.button("Save and Close")
    save_btn:on_click(function()
        for _, num in ipairs(SIGN_ORDER) do
            settings[num] = checks[num]:get_checked()
        end
        save_settings(settings)
        echo("Settings saved.")
        win:close()
    end)
    root:add(save_btn)

    before_dying(function() win:close() end)
    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
    undo_before_dying()
end

-- ── Text-mode setup fallback ──────────────────────────────────────────────────

local function text_setup(settings)
    respond("Current sign configuration:")
    respond("")
    for _, num in ipairs(SIGN_ORDER) do
        local sign = SIGNS[num]
        local state = settings[num] and "ON" or "off"
        respond(string.format("  %s [%3s]  %-45s (%s)", num, state, sign.label, sign.cost))
    end
    respond("")
    respond("Enter sign number to toggle, or 'done' to save and exit:")

    while true do
        local input = get()
        if not input then break end
        input = input:match("^%s*(.-)%s*$")
        if input == "done" then break end
        if SIGNS[input] then
            settings[input] = not settings[input]
            -- Enforce mutual exclusion
            if input == "9905" and settings[input] then settings["9909"] = false end
            if input == "9909" and settings[input] then settings["9905"] = false end
            local state = settings[input] and "ON" or "off"
            respond(string.format("  %s [%3s]  %s", input, state, SIGNS[input].label))
        else
            respond("Unknown sign number. Enter a sign number or 'done'.")
        end
    end

    save_settings(settings)
    echo("Settings saved.")
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────

local arg1 = (Script.vars[1] or ""):lower()

if arg1 == "help" then
    show_help()
    exit()
elseif arg1 == "setup" or arg1 == "options" then
    local settings = load_settings()
    local ok, err = pcall(function()
        gui_setup(settings)
    end)
    if not ok then
        echo("GUI not available (" .. tostring(err) .. "), using text mode.")
        text_setup(settings)
    end
    exit()
end

-- ── Main upkeep loop ──────────────────────────────────────────────────────────

local settings = load_settings()

while true do
    if dead() then exit() end

    -- Anti-Paladin 9012 (Grand Poohbah) suppresses all CoL signs
    if Spell[9012].active then
        echo("The Grand Poohbah is still mad at you.")
        exit()
    end

    for _, num in ipairs(SIGN_ORDER) do
        if settings[num] then
            local spell = Spell[tonumber(num)]
            if spell and spell.known and not spell.active and spell:affordable() then
                spell:cast()

                -- Check for anti-magic zone: sign power dissipating is the tell
                local recent = reget(10)
                local anti_magic = false
                for _, line in ipairs(recent or {}) do
                    if line:find("The power from your sign dissipates into the air") then
                        anti_magic = true
                        break
                    end
                end

                if anti_magic then
                    local room = Room.id
                    while room == Room.id do
                        echo("*** You are in an ANTI-MAGIC zone ***")
                        echo("*** " .. Script.name .. " will restart in 10 seconds ***")
                        echo("*** and only if you leave this room ***")
                        pause(10)
                    end
                end

                waitrt()
                waitcastrt()
            end
        end
    end

    pause(1)
end
