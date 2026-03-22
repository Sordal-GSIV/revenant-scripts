--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: isigils_with_bandages
--- version: 1.1.0
--- author: unknown
--- game: gs
--- tags: guardians, sunfist, sigils, automation
--- description: Maintain active Guardians of Sunfist sigils automatically
---
--- Original Lich5 authors: unknown
--- Ported to Revenant Lua from isigils_with_bandages.lic
---
--- Usage:
---   ;isigils_with_bandages          - run with current settings
---   ;isigils_with_bandages setup    - configure which sigils to maintain (GUI or text fallback)
---   ;isigils_with_bandages help     - show help

local SIGILS = {
    ["9703"] = "Sigil of Contact: Activates ESP Net",
    ["9704"] = "Sigil of Resolve: Climbing, Swimming, and Survival",
    ["9705"] = "Sigil of Minor Bane: HDW and +5 AS",
    ["9716"] = "Sigil of Bandages: Attack without breaking tended bandages",
    ["9707"] = "Sigil of Defense: +1 DS per rank - 5 minutes",
    ["9708"] = "Sigil of Offense: +1 AS per rank - 5 minutes",
    ["9710"] = "Sigil of Minor Protection: +5 DS and HDP - 1 minute",
    ["9711"] = "Sigil of Focus: +1 TD per rank - 1 minute",
    ["9713"] = "Sigil of Mending: Increases HP recovery by 15, all Herbs eaten in 3 sec - 10 minutes",
    ["9714"] = "Sigil of Concentration: +5 mana regeneration - 10 minutes",
    ["9715"] = "Sigil of Major Bane: Adds +10 AS, HCW (melee/ranged/bolt) - 1 minute",
    ["9719"] = "Sigil of Major Protection: Adds +10 DS, HCP - 1 minute",
}

-- Sorted sigil numbers for consistent display ordering
local SIGIL_NUMS = {}
for num in pairs(SIGILS) do SIGIL_NUMS[#SIGIL_NUMS + 1] = num end
table.sort(SIGIL_NUMS)

local EXCLUSIVE_PAIRS = {
    { "9705", "9715" },  -- minor bane vs major bane
    { "9710", "9719" },  -- minor protection vs major protection
}

-- ── Settings ────────────────────────────────────────────────────────────────

local function load_settings()
    local s = {}
    for num in pairs(SIGILS) do
        local val = CharSettings["isigils_" .. num]
        s[num] = (val == "true")
    end
    return s
end

local function save_settings(s)
    for num in pairs(SIGILS) do
        CharSettings["isigils_" .. num] = s[num] and "true" or "false"
    end
end

-- ── GUI setup ────────────────────────────────────────────────────────────────

local function gui_setup(settings)
    local win = Gui.window("iSigils - Guardians of Sunfist Sigil Upkeep", { width = 500, height = 450, resizable = false })
    local root = Gui.vbox()

    local checkboxes = {}

    -- Checkbox per sigil in sorted order
    for _, num in ipairs(SIGIL_NUMS) do
        local cb = Gui.checkbox(SIGILS[num], settings[num] or false)
        checkboxes[num] = cb
        root:add(cb)
    end

    -- Real-time mutual exclusion (mirrors GTK signal_connect toggled)
    for _, pair in ipairs(EXCLUSIVE_PAIRS) do
        local cb_a = checkboxes[pair[1]]
        local cb_b = checkboxes[pair[2]]
        if cb_a and cb_b then
            cb_a:on_change(function(checked) if checked then cb_b:set_checked(false) end end)
            cb_b:on_change(function(checked) if checked then cb_a:set_checked(false) end end)
        end
    end

    root:add(Gui.separator())

    -- Save button
    local save_btn = Gui.button("Save and Close")
    save_btn:on_click(function()
        for _, num in ipairs(SIGIL_NUMS) do
            settings[num] = checkboxes[num]:get_checked()
        end
        -- Enforce mutual exclusion on save as a safety net
        for _, pair in ipairs(EXCLUSIVE_PAIRS) do
            if settings[pair[1]] and settings[pair[2]] then
                settings[pair[2]] = false
            end
        end
        save_settings(settings)
        echo("Settings saved.")
        win:close()
    end)
    root:add(save_btn)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
end

-- ── Argument handling ────────────────────────────────────────────────────────

local arg1 = (Script.vars[1] or ""):lower()

if arg1 == "help" then
    respond("")
    respond("Usage:")
    respond("   ;" .. Script.name .. "          run with current settings")
    respond("   ;" .. Script.name .. " setup    configure sigils")
    respond("   ;" .. Script.name .. " help     show this message")
    respond("")
    exit()
elseif arg1 == "setup" then
    local settings = load_settings()
    local ok, err = pcall(function()
        gui_setup(settings)
    end)
    if not ok then
        echo("GUI not available (" .. tostring(err) .. ")")
    end
    exit()
end

-- ── Main loop ────────────────────────────────────────────────────────────────

local settings = load_settings()

while true do
    if dead() then exit() end

    for _, num in ipairs(SIGIL_NUMS) do
        if settings[num] then
            local spell = Spell[tonumber(num)]
            if spell and spell.known and not spell.active and spell:affordable() then
                spell:cast()
                waitrt()
                waitcastrt()
            end
        end
    end

    pause(1)
end
