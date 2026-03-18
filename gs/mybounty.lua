--- @revenant-script
--- @lic-audit: validated 2026-03-17
--- name: mybounty
--- version: 3.6
--- author: Luxelle
--- game: gs
--- description: Bounty Boost picker -- cycles bounties until you get the one you want
--- tags: bounty,gems,herbs,skins,escort,heirloom,boost-bounty
---
--- Credits: GTK GUI from Bigshot & Dreavening (Azanoth, SpiffyJr, Tillmen, Dreaven)
--- Thanks: Doug, Mice, Selandriel, Atanamir, Ondrein, Pukk
---
--- Changelog (from Lich5):
---   v3.6 (2025-05-28) - HW herbalist/healer task removal support
---   v3.5 (2025-04-24) - HW herbalist/healer tasks
---   v3.4 (2024-01-04) - HW taskmaster name Halfwhistle
---   v3.3 (2021-09-13) - GTK 3 support
---   v3.2 (2021-07-28) - PSM 3 update fix
---   v3.0 (2021-04-22) - Auto run to advguild, improved flow

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function bold_message(msg)
    respond("<pushBold/>")
    respond(msg)
    respond("<popBold/>")
end

local function load_mybounty_settings()
    local raw = UserVars.mybounty
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save_mybounty_settings(settings)
    UserVars.mybounty = Json.encode(settings)
end

local function is_yes(val)
    return val and type(val) == "string" and val:lower():find("yes") ~= nil
end

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function run_setup()
    local settings = load_mybounty_settings()

    local win = Gui.window("MyBounty Setup", { width = 350, height = 400 })
    local root = Gui.vbox()

    local fields = {
        { label = "Gems",             key = "gems_setup" },
        { label = "Forage",           key = "forage_setup" },
        { label = "Furrier",          key = "furrier_setup" },
        { label = "Rescue Child",     key = "kidrescue_setup" },
        { label = "Creature Problem", key = "creature_setup" },
        { label = "Bandits",          key = "bandit_setup" },
        { label = "Escorts",          key = "escort_setup" },
        { label = "Heirloom",         key = "heirloom_setup" },
    }

    local inputs = {}
    for _, f in ipairs(fields) do
        local hbox = Gui.hbox()
        hbox:add(Gui.label(f.label .. ":"))
        local input = Gui.input({ text = settings[f.key] or "", placeholder = "YES or blank" })
        inputs[f.key] = input
        hbox:add(input)
        root:add(hbox)
    end

    root:add(Gui.separator())
    root:add(Gui.label("Enter YES to enable a bounty type, leave blank to skip."))

    local save_btn = Gui.button("Save & Close")
    save_btn:on_click(function()
        for _, f in ipairs(fields) do
            settings[f.key] = inputs[f.key]:get_text():match("^%s*(.-)%s*$"):lower()
        end
        save_mybounty_settings(settings)
        echo("Settings saved!")
        win:close()
    end)
    root:add(save_btn)

    win:set_root(Gui.scroll(root))
    win:show()
    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- Usage
--------------------------------------------------------------------------------

local function show_usage()
    respond("")
    respond("Use this script to find only the bounties you want with BOOST BOUNTY active.")
    respond("Set your desired bounties first with: ;mybounty setup")
    respond("")
    respond("Usage: ;mybounty          (run the bounty picker)")
    respond("       ;mybounty setup    (configure bounty preferences)")
    respond("       ;mybounty help     (show this help)")
    respond("")
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]

if arg1 == "setup" then
    run_setup()
    return
elseif arg1 == "help" or arg1 == "?" then
    show_usage()
    return
elseif arg1 and arg1 ~= "" then
    bold_message("Usage: ;mybounty setup | ;mybounty help | ;mybounty")
    return
end

--------------------------------------------------------------------------------
-- Check Bounty Boost
--------------------------------------------------------------------------------

local boost_active = false
if Effects and Effects.Buffs and Effects.Buffs.active then
    boost_active = Effects.Buffs.active("Bounty Boost")
else
    -- Fallback: check via active spells
    local active_spells = Spell.active() or {}
    for _, sp in ipairs(active_spells) do
        if sp.name and sp.name:find("Bounty Boost") then
            boost_active = true
            break
        end
    end
end

if not boost_active then
    echo("Use a BOOST BOUNTY and call me back, kay?")
    return
end

--------------------------------------------------------------------------------
-- Load settings and validate
--------------------------------------------------------------------------------

local settings = load_mybounty_settings()

local gems      = is_yes(settings.gems_setup)
local forage    = is_yes(settings.forage_setup)
local furrier   = is_yes(settings.furrier_setup)
local kidrescue = is_yes(settings.kidrescue_setup)
local creature  = is_yes(settings.creature_setup)
local bandit    = is_yes(settings.bandit_setup)
local escort    = is_yes(settings.escort_setup)
local heirloom  = is_yes(settings.heirloom_setup)

local has_any = gems or forage or furrier or kidrescue or creature or bandit or escort or heirloom

if not has_any then
    bold_message("You have nothing setup! Run ;mybounty setup first.")
    return
end

if gems then bold_message("Gems: Yes") end
if forage then bold_message("Forage: Yes") end
if furrier then bold_message("Furrier: Yes") end
if kidrescue then bold_message("Kidrescue: Yes") end
if creature then bold_message("Creature: Yes") end
if bandit then bold_message("Bandit: Yes") end
if escort then bold_message("Escort: Yes") end
if heirloom then bold_message("Heirloom: Yes") end

--------------------------------------------------------------------------------
-- Navigate to adventurer's guild if needed
--------------------------------------------------------------------------------

local room = Room.current()
local tags = room and room.tags or {}
local at_advguild = false
for _, tag in ipairs(tags) do
    if tag == "advguild" then at_advguild = true; break end
end

if not at_advguild then
    echo("Taking you to the advguild.")
    Script.run("go2", "advguild")
    wait_while(function() return running("go2") end)
end

--------------------------------------------------------------------------------
-- Determine task NPC name
--------------------------------------------------------------------------------

local task_npc = "Taskmaster"
local room_obj = Room.current()
if room_obj and room_obj.uid then
    local uid_list = room_obj.uid
    if type(uid_list) == "table" then
        for _, uid in ipairs(uid_list) do
            if uid == 7503207 then
                task_npc = "Halfwhistle"
                break
            end
        end
    elseif uid_list == 7503207 then
        task_npc = "Halfwhistle"
    end
end

--------------------------------------------------------------------------------
-- Remove current bounty if any
--------------------------------------------------------------------------------

if Bounty.task ~= "You are not currently assigned a task." then
    fput("ask " .. task_npc .. " for remov")
    fput("ask " .. task_npc .. " for remov")
end

--------------------------------------------------------------------------------
-- Helper: ask NPC about bounty at a location
--------------------------------------------------------------------------------

local NPC_FILTER_BASE = Regex.new("\\b(?:familiar|companion|passive|skin)\\b")
local NPC_FILTER_BANDIT = Regex.new("\\b(?:familiar|companion|passive|skin|aggressive)\\b")

local function ask_npcs_about_bounty(opts)
    opts = opts or {}
    local filter = opts.exclude_aggressive and NPC_FILTER_BANDIT or NPC_FILTER_BASE
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if not npc.type or not filter:test(npc.type) then
            fput("ask " .. npc.noun .. " about bounty")
        end
    end
    pause(0.1)
end

local function go_to_guard_and_ask()
    Script.run("go2", "advguard")
    wait_while(function() return running("go2") end)
    pause(0.2)
    ask_npcs_about_bounty()

    -- Check if we need to go to a second guard
    if Bounty.task and Bounty.task:find("Go report to") then
        respond("Trying to find the guard at the other location for you.")
        Script.run("go2", "advguard2")
        wait_while(function() return running("go2") end)
        pause(0.2)
        ask_npcs_about_bounty()
    end
end

--------------------------------------------------------------------------------
-- Bounty-type patterns and their destinations
--------------------------------------------------------------------------------

local BOUNTY_TYPES = {
    { pattern = "bandit",          wanted = bandit,    dest = "advguard", exclude_aggressive = true },
    { pattern = "creature problem", wanted = creature, dest = "advguard" },
    { pattern = "urgently needs",  wanted = kidrescue, dest = "advguard" },
    { pattern = "lost heirloom",   wanted = heirloom,  dest = "advguard" },
    { pattern = "local furrier",   wanted = furrier,   dest = "furrier" },
    { pattern = "gem dealer",      wanted = gems,      dest = "gemshop" },
    { pattern = "protective escort", wanted = escort,  dest = "advpickup" },
}

local FORAGE_PATTERN = Regex.new("local herbalist|local healer|local(?: halfling)? alchemist")

--------------------------------------------------------------------------------
-- Main bounty cycle
--------------------------------------------------------------------------------

fput("ask " .. task_npc .. " for bounty")

while true do
    local line = get()
    if not line then break end

    -- Check each bounty type
    local matched = false

    for _, bt in ipairs(BOUNTY_TYPES) do
        if string.find(line, bt.pattern) then
            if bt.wanted then
                local npc_opts = bt.exclude_aggressive and { exclude_aggressive = true } or nil
                echo("Got your " .. bt.pattern .. " right here!")
                Script.run("go2", bt.dest)
                wait_while(function() return running("go2") end)
                pause(0.2)
                ask_npcs_about_bounty(npc_opts)

                -- Check for redirect
                if Bounty.task and Bounty.task:find("Go report to") then
                    if bt.dest == "advguard" then
                        respond("Trying to find the guard at the other location for you.")
                        Script.run("go2", "advguard2")
                        wait_while(function() return running("go2") end)
                        pause(0.2)
                        ask_npcs_about_bounty(npc_opts)
                    end
                end
                return  -- Done!
            else
                echo("Refusing this bounty ...")
                pause(0.2)
                fput("ask " .. task_npc .. " for remov")
                fput("ask " .. task_npc .. " for remov")
                pause(4)
                fput("ask " .. task_npc .. " for bounty")
                matched = true
                break
            end
        end
    end

    -- Check forage separately (regex pattern)
    if not matched and FORAGE_PATTERN:test(line) then
        if forage then
            echo("Got your foraging task right here!")
            -- Determine forage destination based on nearest town area
            local nearest_town = Room.find_nearest_by_tag("town")
            local town_room = nearest_town and nearest_town.id and Map.find_room(nearest_town.id)
            local location = (town_room and town_room.location) or ""
            if location:find("Icemule") or location:find("Wehnimer") then
                Script.run("go2", "npchealer")
            else
                Script.run("go2", "herbalist")
            end
            wait_while(function() return running("go2") end)
            pause(0.4)
            ask_npcs_about_bounty()
            return
        else
            echo("Refusing this bounty ...")
            pause(0.2)
            fput("ask " .. task_npc .. " for remov")
            fput("ask " .. task_npc .. " for remov")
            pause(4)
            fput("ask " .. task_npc .. " for bounty")
        end
    end

    -- Taskmaster annoyed cooldown
    if not matched and string.find(line, "annoyed and says") then
        pause(2)
        fput("ask " .. task_npc .. " for bounty")
    end
end
