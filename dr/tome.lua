--- @revenant-script
--- name: tome
--- version: 1.0.0
--- author: LostRanger (original), Ported to Revenant
--- game: dr
--- description: Study a tome/book to train Scholarship. Supports passive and active modes with configurable scholarship limits.
--- tags: scholarship, training, tome, book, passive
--- @lic-certified: complete 2026-03-19
---
--- Ported from tome.lic (Lich5 dr-scripts) to Revenant Lua.
---
--- Original authors/changelog preserved from tome.lic.
---
--- Settings (in your character's setup JSON under "tome_settings"):
---   tome_name        - Name of the tome/book item (required)
---   scholarship_limit - XP threshold to stop studying (default: 34)
---   passive          - true: only study when a passive_script is running
---   passive_scripts  - list of script names that trigger passive studying
---   quit_early       - true: stop reading at the penultimate page
---   second_to_last_page - custom regex pattern for penultimate page detection
---
--- Usage:
---   ;tome          - Run in passive mode (per settings)
---   ;tome active   - Force active mode (ignore passive setting)
---   ;tome debug    - Enable verbose debug output

-- Arg parsing: support "active" and "debug" flags
local arg_active = false
local arg_debug  = false
for _, v in ipairs(Script.vars or {}) do
    local l = v:lower()
    if l == "active" then arg_active = true end
    if l == "debug"  then arg_debug  = true end
end

local settings      = get_settings()
local tome_settings = settings.tome_settings or {}

local tome_name        = tome_settings.tome_name
local quit_early       = tome_settings.quit_early
local penultimate_page = tome_settings.second_to_last_page
local scholarship_limit = tonumber(tome_settings.scholarship_limit) or 34
local passive_scripts  = tome_settings.passive_scripts or {}
local passive          = arg_active and false or (tome_settings.passive == true)
local no_use_rooms     = settings.sanowret_no_use_rooms or {}

-- Validate required setting
if not tome_name or tome_name == "" then
    DRC.message("[tome] ERROR: tome_settings.tome_name is not set in your character's setup JSON.")
    DRC.message("[tome] The script will now abort.")
    return
end

-- Warn if tome is not listed in gear
local gear = settings.gear or {}
local tome_in_gear = false
for _, item in ipairs(gear) do
    if type(item) == "table" then
        local adj  = item.adjective or ""
        local noun = item.name or ""
        local pat  = (adj ~= "" and (adj .. "%s*" .. noun) or noun):lower()
        if Regex.test(pat, tome_name:lower()) then
            tome_in_gear = true
            break
        end
    end
end
if not tome_in_gear then
    DRC.message("[tome] WARNING: Your tome is not listed in your gear: settings.")
    DRC.message("[tome] Tome: " .. tome_name)
    DRC.message("[tome] Items held in-hand could be lost if not in gear:. Add it to your setup JSON.")
    DRC.message("[tome] The script will now abort.")
    return
end

-- Penultimate page patterns by known tome name
local penultimate_pages = {
    ["tel'athi treatise"]      = "Most S'Kra, whether they call them such or not, are familiar with the Eight Gifts",
    ["mikkhalbamar manuscript"] = "In both cases the rituals involving consignment are nearly identical",
    ["spiritwood tome"]         = "Faenella is the goddess of creativity, revelry, and pride.",
    ["field guide"]             = "Sacred to Harawep, wildling spiders are a sentient race that is associated with the cult of the Spidersworn",
    ["brinewood book"]          = "While Merelew observed the stars and the moons crown,",
    ["kuwinite codex"]          = "But, she is a great warrior with the fury of a mother",
    ["smokewood codex"]         = "Rumor also has it that the Empire had great powers of magic or technology",
    ["togball manual"]          = "A team may not enter the opposing team's Blood Zone",
    ["weathered book"]          = "\"There he is!\" Grundgy turned to see half a dozen of the guards hacking through the briars and reed",
    ["worn book"]               = "I was unsure a little of whether dragons drank wine,",
    ["Dwarven codex"]           = "The Rituals of Consignment",
    ["radiant treatise"]        = "VIII. Vice and Error",
    ["ox-hide memoir"]          = "Finally, I noticed that on my path to Truffenyi's side",
    ["songsilk memoir"]         = "What I didn't account for was how drastic of an effect the influence of the Heralds had on my memory",
    ["modest-sized biography"]  = "At a quiet vigil, Miraena spoke of remorse",
    ["research journal"]        = "To address this imbalance, Liraxes asserted itself",
    ["demonbone grimoire"]      = "Skairelden, the Forge",
    ["darkspine grimoire"]      = "Gwulach, the Drinker of Minds",
}

-- Set up study-complete flag
if quit_early and penultimate_page then
    Flags.add("study-complete", penultimate_page)
elseif quit_early then
    local pat = penultimate_pages[tome_name]
    if pat then
        Flags.add("study-complete", pat)
    else
        DRC.message("[tome] WARNING: quit_early is set but no penultimate page pattern found for tome: " .. tome_name)
        Flags.add("study-complete", "^Having finished your studies,")
    end
else
    Flags.add("study-complete", "^Having finished your studies,")
end

if arg_debug then
    echo("[tome] Settings: " .. Json.encode(tome_settings))
    echo("[tome] passive=" .. tostring(passive) .. " limit=" .. tostring(scholarship_limit))
end

-- Scripts that were paused for tome usage (for safe unpause on resume)
local scripts_to_unpause = nil

-------------------------------------------------------------------------------
-- should_train: returns true if conditions are right to study
-------------------------------------------------------------------------------
local function should_train()
    if DRSkill.getxp("Scholarship") >= scholarship_limit then return false end
    if not passive then return true end
    -- Passive checks
    if hidden() or invisible() then return false end
    -- Don't study if both hands occupied and tome isn't in hand
    if DRC.left_hand() and DRC.right_hand() and not DRCI.in_hands(tome_name) then return false end
    -- Don't study in excluded rooms
    local room_title = GameState.room_name or ""
    local room_id    = tostring(GameState.room_id or "")
    for _, name in ipairs(no_use_rooms) do
        if room_title:find(name) or tostring(name) == room_id then return false end
    end
    -- Only study while a passive trigger script is running
    for _, name in ipairs(passive_scripts) do
        if running(name) then
            if arg_debug then echo("[tome] Passive script running: " .. name) end
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- pause_scripts: pause all pausable scripts
-------------------------------------------------------------------------------
local function pause_scripts()
    scripts_to_unpause = DRC.safe_pause_list()
end

-------------------------------------------------------------------------------
-- unpause_scripts: unpause scripts saved by pause_scripts
-------------------------------------------------------------------------------
local function unpause_scripts()
    if scripts_to_unpause then
        DRC.safe_unpause_list(scripts_to_unpause)
        scripts_to_unpause = nil
    end
end

-------------------------------------------------------------------------------
-- pause_safely: wait for duration seconds while monitoring should_train
-- Returns true if duration elapsed, false if should_train became false
-------------------------------------------------------------------------------
local function pause_safely(duration)
    local end_time = os.time() + duration
    while os.time() < end_time do
        if not should_train() then
            if passive then pause_scripts() end
            DRCI.stow_item(tome_name)
            unpause_scripts()
            return false
        end
        pause(1)
    end
    return true
end

-------------------------------------------------------------------------------
-- Main monitor loop
-------------------------------------------------------------------------------
local function monitor_routine()
    while true do
        -- Active mode: exit when scholarship is capped
        if DRSkill.getxp("Scholarship") >= scholarship_limit and not passive then
            DRC.fix_standing()
            return
        end

        Flags.reset("study-complete")

        -- Active mode: sit down before studying
        if not passive then
            if not sitting() and not Script.running("safe-room") then
                DRC.bput("sit",
                    "You sit", "You are already sitting", "You rise",
                    "While swimming?")
            end
        end

        -- Wait until concentration is full and conditions are right
        while not (should_train() and percentconcentration() == 100) do
            pause(10)
        end

        if not should_train() then goto continue end

        -- Pause other scripts if in passive mode
        if passive then pause_scripts() end

        -- Retrieve the tome
        if not DRCI.get_item(tome_name) then
            unpause_scripts()
            goto continue
        end

        -- Attempt to study
        local result = DRC.bput("study my " .. tome_name,
            "^You immerse yourself in the wisdom of your",
            "^You are unable to focus on studying your",
            "^You must complete or cancel your current magical research project",
            "^Considering that you are in combat",
            "^Are you sure you want to do that%?  You'll interrupt your research",
            "^However, you find that you lack the concentration to focus on your studies",
            "^This is not a good place for that")

        unpause_scripts()

        -- Handle failure responses — stow and wait
        if result:find("^You are unable to focus on studying your")
            or result:find("^Are you sure you want to do that")
            or result:find("^You must complete or cancel")
            or result:find("^Considering that you are in combat")
            or result:find("^However, you find that you lack the concentration")
            or result:find("^This is not a good place for that")
        then
            if passive then pause_scripts() end
            DRCI.stow_item(tome_name)
            unpause_scripts()
            pause(10)
            goto continue
        end

        -- Wait at least one page read before checking completion
        if not pause_safely(10) then goto continue end

        -- Wait until study completes, should_train becomes false, or concentration resets
        -- (Concentration hitting max again means we somehow finished without catching the flag,
        --  e.g., another script stowed the book)
        while not Flags["study-complete"]
            and should_train()
            and percentconcentration() < 100
        do
            pause(1)
        end

        if passive then pause_scripts() end
        DRCI.stow_item(tome_name)
        unpause_scripts()

        ::continue::
    end
end

-------------------------------------------------------------------------------
-- Cleanup on script exit
-------------------------------------------------------------------------------
before_dying(function()
    Flags.delete("study-complete")
    if not Script.running("safe-room") then
        DRC.fix_standing()
    end
    if tome_name and DRCI.in_hands(tome_name) then
        DRCI.stow_item(tome_name)
    end
end)

-------------------------------------------------------------------------------
-- Start
-------------------------------------------------------------------------------
monitor_routine()
