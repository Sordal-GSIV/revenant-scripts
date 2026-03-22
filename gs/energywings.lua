--- @revenant-script
--- @lic-audit: validated 2026-03-18
--- name: energywings
--- version: 1.4.6
--- author: ChatGPT
--- game: gs
--- tags: combat, automation, wing pin, cooldowns, aoe, claim, dueling sands
--- description: Automates Wing Pin combat abilities based on room context, NPC status, cooldowns, and enemy spell prep detection
---
--- Original Lich5 authors: ChatGPT
--- Ported to Revenant Lua from energywings.lic
---
--- Changelog (from Lich5):
---   v1.4.6 (2026-02-25): Fixed autostart disconnect when dead
---   v1.4.5 (2026-02-19): Simplified spell gating to Spell[num].available
---   v1.4.4 (2026-02-19): Simplified hidden guards
---   v1.4.3 (2026-02-19): Switched hidden-state guards to hiding semantics
---   v1.4.2 (2026-02-19): Added hidden-state guard for wing actions
---   v1.4.1 (2026-02-13): Wrapped in module, changed defensive trigger to bleeding
---   v1.4.0 (2026-02-12): Added enemy spell prep detection and reaction
---   v1.3.0 (2026-02-12): Auto-detect worn wing pin dark/light mode
---   v1.2.1 (2026-02-12): GameObj.npcs changed to GameObj.targets
---
--- Usage:
---   ;energywings            - run with auto-detected wing pin mode
---   Wear a dark or pale wing-shaped pin before running.
---
--- Features:
---   - Only activates in your Lich claim or the Dueling Sands
---   - Auto-detects dark/pale wing pin for dark/light mode
---   - Reacts to enemy spell preparation with defensive pull
---   - Dark: Shadow Barb, Barbed Sweep, Rain of Thorns, Carrion Guard, Crawling Shadow
---   - Light: Radiant Pulse, Blast of Brilliance, Blinding Reprisal, Wings of Warding, Prismatic Aegis
---   - Cooldown management via Effects.Cooldowns

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local SCRIPTS_TO_PAUSE = { "bigshot", "hunt3" }

-- Precast commands to run before each wing ability fires.
-- nil = no precast, string = one command, table = multiple commands in order.
local PRECAST_FOR_ABILITY = {
    -- Dark
    ["Shadow Barb"]     = { "incant 118" },
    ["Barbed Sweep"]    = { "incant 110" },
    ["Rain of Thorns"]  = { "invoke 1714 tat", "cast" },
    ["Carrion Guard"]   = nil,
    ["Crawling Shadow"] = nil,
    -- Light
    ["Radiant Pulse"]       = nil,
    ["Blast of Brilliance"] = nil,
    ["Blinding Reprisal"]   = nil,
    ["Wings of Warding"]    = nil,
    ["Prismatic Aegis"]     = nil,
}

-- Creature spell prep patterns (comprehensive list from KSwole and many hunting areas).
-- Each entry is a Lua pattern that matches a creature spell preparation line.
local CREATURE_SPELL_PREPS = {
    -- Atoll and Nelemar
    "^An? .+elemental utters an incantation in an unfamiliar, bubbling language%.",
    "^An? .+fanatic steeples %a+ clawed fingers together, murmuring a quick incantation%.",
    "^An? .+radical steeples %a+ clawed fingers together, murmuring a quick incantation%.",
    "^An? .+siren begins singing a sweet song%.",
    "^An? .+magus makes a subtle gesture, drawing traces of faint blue%-green light into %a+ webbed hands%.",
    "^An? .+warden makes a subtle gesture, drawing traces of faint blue%-green light into %a+ webbed hands%.",
    "^An? .+warlock chants in an incomprehensible language, causing streams of dim grey energy to lash about %a+ ",
    "^An? .+dissembler chants in an incomprehensible language, causing streams of dim grey energy to lash about %a+ ",
    "^An? .+sentry chants in an incomprehensible language, causing streams of dim grey energy to lash about %a+ ",
    "^An? .+psionicist chants in an incomprehensible language, causing streams of dim grey energy to lash about %a+ ",
    -- Bonespear
    "draws an ancient sigil in the air%.",
    -- Bowels
    "^An? .+elder invokes the power of %a+ god, the symbol on %a+ forehead glowing brightly%.",
    "^An? .+jarl traces a simple symbol as %a+ reverently calls upon the power of %a+ god%.",
    -- Citadel
    "^An? .+apprentice whispers a magical incantation, bending the elements to %a+ whim%.",
    "^An? .+herald seethes a forceful chant, commanding the spirits to do %a+ bidding%.",
    -- Confluence
    "glows with a bright blue light%.",
    "rumbles with an inner power%.",
    "utters an incantation in an unfamiliar, bubbling language%.",
    "whispers an incantation into the wind%.",
    "raises a molten appendage",
    "sparks wildly",
    "sizzles with power%.",
    "releases a burst of fiery energy",
    -- Crawling Shore
    "groans out a malevolent series of mystical syllables, causing the surrounding shadows to burn crimson%.",
    "mutters an old, guttural chant as the surroundings grow terribly silent%.",
    -- Den of Rot
    "^An? .+incubus begins singing a softly melodic melody, his lips quirking with cruel amusement%.",
    "^An? .+inciter raises %a+ voice in a ululating chant, surrounding %a+ with wisps of sickly green energy%.",
    "^An? .+vereri sets her lips in a petulant pout%.",
    "^An? .+vision begins buzzing loudly, its corrupt aura turning a deeper shade of bile green%.",
    -- Duskruin Arena
    "utters a guttural, primitive prayer%.",
    "raises %a+ fists to the sky%.",
    "begins to shiver%.",
    "shouts out an arcane phrase of magic%.",
    "whispers a string of delicate words%.",
    "rubs %a+ magical horn%.",
    "barks some odd sounds%.",
    -- Graveyard, Shadow Valley
    "^An? .+shadow mare fades visibly, flicking %a+ tail%.",
    "^An? .+shadow steed shakes %a+ mane%.",
    "^An? .+night mare flares %a+ nostrils%.",
    -- Grimswarm
    "^An? .+witch gestures and utters a phrase of magic%.",
    "^An? .+sorcerer gestures and utters a phrase of magic%.",
    "^An? .+sorceress gestures and utters a phrase of magic%.",
    -- Hidden Plateau
    "^An? .+magus begins rumbling while making mystic gestures through the air%.",
    -- Hinterwilds
    "^An? .+bloodspeaker utters a garbled, sibilant phrase as globules of crimson light spin around %a+ gnarled hands%.",
    "^An? .+golem glows with shimmering incarnadine light that suffuses its monstrous form with power%.",
    "^An? .+wendigo rasps out a dissonant, sing%-song phrase%.",
    "^An? .+skald raises %a+ voice into a reverberating dirge, the surrounding shadows dancing in time with the tune%.",
    "^An? .+shield%-maiden raises a fist to the heavens as her eyes begin to glow like molten gold%.",
    "^An? .+disir raises a hand skyward, suffusing herself with scintillating power%.",
    "^An? .+mutant twitches, %a+ distended cranium pulsing as a look of intense focus stills %a+ face%.",
    "^An? .+disir silently mouths an incantation that does not seem to be in any language you know%.",
    "^An? .+disir focuses her luminous gaze upon you!",
    "^An? .+disciple gestures with one bloody hand, chanting a sibilant prayer%.",
    "^An? .+angargeist lights from within, energy crackling within its chaotic core%.",
    -- Icemule Trace
    "^An? .+vine twirls an appendage in a complex circle%.",
    "^An? .+glacei flares with a deep blue glow%.",
    "^An? .+dirge begins to wail loudly!",
    "^An? .+apparition draws slowly inward!",
    "^An? .+wraith draws inward for a moment!",
    "begins to moan an incantation!",
    "chants an evil incantation%.",
    "begins to shiver violently!",
    "mutters an incantation%.",
    "utters a phrase of arcane magic%.",
    "^An? .+crone mutters a frosty incantation%.",
    "raises its fists to the sky%.",
    "^An? .+plant opens and closes one of its flowers%.",
    -- Moonsedge
    "^An? .+banshee raises her voice in a shrill, eerie song that makes the surrounding mists dance%.",
    "^An? .+grotesque rumbles out a basso incantation, clenching one carved claw as its eyes glow viridian%.",
    "^An? .+knight twists a skeletal hand, uttering a blasphemous chant%.",
    "^An? .+vampire slices a shadowy sigil in the air as %a+ utters an old chant%.",
    "^An? .+conjurer gives a flourish of %a+ spectral arms as %a+ raises %a+ voice in a theatrical chant%.",
    -- OSA
    "snarls as %a+ chants a few words of magic%.",
    -- OTF (incl. Aqueducts)
    "^An? .+being rumbles a series of arcane phrases%.",
    "^An? .+initiate closes %a+ eyes while uttering a hollow, alien chant%.",
    "^An? .+herald starts singing an alien song in a reverberating, sonorous voice%.",
    "^An? .+adept closes %a+ eyes while incanting an alien phrase%.",
    "^An? .+seer closes %a+ eyes and bows %a+ head slightly%.",
    "mutters a phrase of magic%.",
    -- Red Forest
    "^An? .+viper hisses an arcane phrase in an unfamiliar sibilant language%.",
    "^An? .+spirit whistles a soft, malicious tune%.",
    "^An? .+pixie hands begin to glow%.",
    "^An? .+sprite raises a finger to %a+ lips%.",
    "^An? .+druid groans an incantation%.",
    -- Reim
    "glows as %a+ chants a few words of magic%.",
    -- Rift and Scatter
    "^An? .+witch whispers with an ominously soft voice%.",
    "^An? .+seraceris begins to hum%.",
    "^An? .+naisirc glows with an eerie green light%.",
    "^An? .+csetairi waves her four arms in a triangular motion%.",
    "^An? .+warlock pauses a moment as his eyes swim black with anti%-mana%.",
    "^An? .+avenger traces a twisted symbol as %a+ calls upon %a+ inner power%.",
    "^An? .+crusader traces a twisted symbol as %a+ calls upon %a+ inner power%.",
    "^An? .+vaespilon draws an ancient sigil in the air%.",
    "^An? .+soul gestures and utters a phrase of arcane magic%.",
    "^An? .+cerebralite twists and coils its tentacles",
    "^An? .+siphon scythes its bladed arms together",
    "^An? .+master raises its hands while emitting a dissonant sing%-song rhythm",
    "^An? .+lich hisses out an incantation",
    -- Sanctum
    "^An? .+lurk moans out a garbled spell%.",
    "^An? .+sentinel mumbles a silent and sibilant prayer",
    "^An? .+fanatic throws back %a+ head, quickening the air around %a+ with motes of virescent light%.",
    "^An? .+shaper whispers an inhuman entreaty",
    -- The Hive, Zul Logoth
    "^An? .+thrall clumsily twists %a+ palsied hands into a spell form",
    "^An? .+strandweaver weaves complex threads of raw mana with %a+ pale legs%.",
    -- Stormpeak, Titan's Deluge
    "^An? .+herald chants in a low, guttural voice%.",
    "^An? .+fiend thrums with an upswelling of elemental energy%.",
    "^An? .+stormcaller mutters a thunderous chant as she lifts her eyes skyward%.",
    -- Forgotten Vineyard
    "^An? .+sorcerer draws a glowing sigil in the air%.",
    "^An? .+sorceress draws a glowing sigil in the air%.",
    "^An? .+sorcerer extends %a+ finger toward you!",
    "^An? .+sorceress extends %a+ finger toward you!",
    "^An? .+bard begins to growl a guttural melody%.",
    "^An? .+bardesss begins to growl a guttural melody%.",
    "^An? .+bard directs %a+ guttural voice at you!",
    "^An? .+bardesss directs %a+ guttural voice at you!",
    "^An? .+empath quietly growls a phrase of magic%.",
    "^An? .+empath snarls and gestures sharply at you!",
    "^An? .+empath draws a large sign in the air before %a+",
    "^An? .+shaman utters an ancient prayer%.",
    "^An? .+shaman waves a hand dismissively at you!",
    -- Sailor's Grief
    "^An? .+oracle gurgles in a lost tongue",
    "^An? .+merrow croaks deep in %a+ throat",
    "^An? .+buccaneer lifts a rattling voice in an old nautical chanty%.",
    "^An? .+mass pulses grotesquely, sprouting mouths that chant in an ugly arcane tongue%.",
    "^An? .+kelpie emits a strange bluish light as the music of rushing water echoes around %a+%.",
    -- Ta'Vaalor
    "^The .+siren whispers a seductive song%.",
    -- Miscellaneous undead
    "^An? .+revenant draws slowly inward!",
    "^The .+apparition wails with an unearthly cry!",
    "^The .+dirge wails a sad, eerie song!",
    "^The .+darkwoode whispers with a sinister voice carried on the wind!",
    "^An? .+grey orc utters a harsh phrase of magic%.",
    "^An? .+ghoul master mutters a chant!",
    "^An? .+arch wight chants an evil incantation%.",
    "^An? .+niirsha draws a fiery symbol in the air%.",
    "^An? .+centaur ranger intones a low%-pitched chant%.",
    "^An? .+sacristan spirit utters an arcane incantation%.",
    "^An? .+monk utters an arcane incantation%.",
    "^An? .+wood sprite utters an eerie sound%.",
    "^An? .+spectre glows faintly as a spectral mist begins to swirl around %a+%.",
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Check if we are in our Lich claim or the Dueling Sands.
local function in_allowed_room()
    -- Lich::Claim.mine? equivalent
    if Lich and Lich.Claim and Lich.Claim.mine and Lich.Claim.mine() then
        return true
    end
    -- Fallback: check room location for Dueling Sands
    local loc = Room.current and Room.current() and Room.current().location
    if loc and string.find(loc, "Dueling Sands", 1, true) then
        return true
    end
    return false
end

--- Find a living NPC target in the room.
local function living_npc()
    local targets = GameObj.targets and GameObj.targets() or GameObj.npcs()
    for _, npc in ipairs(targets) do
        if npc and npc.status then
            if not string.find(npc.status, "dead") and not string.find(npc.status, "gone") then
                return npc
            end
        elseif npc then
            return npc
        end
    end
    return nil
end

--- Find the wing pin in inventory.
local function find_wing_pin()
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item and item.name then
            local name = string.lower(item.name)
            if (string.find(name, "^dark%s+wing%-shaped%s+pin$") or
                string.find(name, "^pale%s+wing%-shaped%s+pin$")) then
                return item
            end
        end
    end
    return nil
end

--- Determine wing mode from pin name.
local function wing_pin_mode(pin)
    if not pin then return nil end
    local name = string.lower(pin.name)
    if string.find(name, "^dark%s+wing%-shaped%s+pin$") then
        return "dark"
    elseif string.find(name, "^pale%s+wing%-shaped%s+pin$") then
        return "light"
    end
    return nil
end

--- Check if an ability is ready (not on cooldown).
local function ability_ready(name)
    if Effects and Effects.Cooldowns and Effects.Cooldowns.active then
        return not Effects.Cooldowns.active(name)
    end
    return true
end

--- Check if an ability is on cooldown.
local function ability_on_cooldown(name)
    if Effects and Effects.Cooldowns and Effects.Cooldowns.active then
        return Effects.Cooldowns.active(name)
    end
    return false
end

--- Check if a line matches any creature spell prep pattern.
local function matches_spell_prep(line)
    for _, pat in ipairs(CREATURE_SPELL_PREPS) do
        if string.find(line, pat) then
            return true
        end
    end
    return false
end

--- Pause listed scripts if running.
local function pause_scripts()
    for _, name in ipairs(SCRIPTS_TO_PAUSE) do
        if Script.running(name) then
            Script.pause(name)
        end
    end
end

--- Unpause listed scripts if running.
local function unpause_scripts()
    for _, name in ipairs(SCRIPTS_TO_PAUSE) do
        if Script.running(name) then
            Script.unpause(name)
        end
    end
end

--- Run precast commands for a given ability name.
local function run_precast_for(ability_name)
    if hidden() then return end

    local cmds = PRECAST_FOR_ABILITY[ability_name]
    if not cmds then return end

    if type(cmds) == "string" then
        cmds = { cmds }
    end

    for _, cmd in ipairs(cmds) do
        if cmd and cmd ~= "" then
            -- Check if command is an incant/prep with a spell number
            local spell_num = string.match(cmd, "^[Ii]ncant%s+(%d+)")
            if not spell_num then
                spell_num = string.match(cmd, "^[Pp]rep%s+(%d+)")
            end
            if spell_num then
                local snum = tonumber(spell_num)
                if snum and Spell[snum] and not Spell[snum].available then
                    goto continue
                end
            end

            waitrt()
            waitcastrt()
            dothistimeout(cmd, 5, "^You gesture")
            waitrt()
            waitcastrt()
            pause(0.25)
        end
        ::continue::
    end
end

--- Fire a wing ability command with script pausing and precast.
local function fire_wing_ability(command, ability_name)
    if hidden() then return end

    pause_scripts()
    local ok, err = pcall(function()
        waitrt()
        waitcastrt()
        run_precast_for(ability_name)
        fput(command)
        pause(0.5)
    end)
    unpause_scripts()
    if not ok then
        echo("energywings: error firing " .. ability_name .. ": " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- Spell prep reaction (defensive pull)
--------------------------------------------------------------------------------

local function react_to_enemy_prep(mode)
    if not in_allowed_room() then return end
    if hidden() then return end
    if stunned() then return end

    local npc = living_npc()
    if not npc then return end

    if mode == "dark" then
        if not ability_ready("Crawling Shadow") then return end

        pause_scripts()
        local ok, _ = pcall(function()
            waitrt()
            waitcastrt()
            pause(0.25)
            local result = dothistimeout("pull my wing pin", 2,
                "You draw your umbrous wings close as shadows seep outward")
            pause(0.5)
            if result and type(result) == "string" then
                echo(string.rep(" ", 10) .. "CRAWLING SHADOW {!}")
            end
        end)
        unpause_scripts()
    else
        if not ability_ready("Prismatic Aegis") then return end

        pause_scripts()
        local ok, _ = pcall(function()
            waitrt()
            waitcastrt()
            pause(0.25)
            dothistimeout("pull my wing pin", 2,
                "You draw your luminous wings inward and then snap them wide")
            pause(0.5)
            echo(string.rep(" ", 10) .. "PRISMATIC AEGIS {!}")
        end)
        unpause_scripts()
    end
end

--------------------------------------------------------------------------------
-- Combat actions
--------------------------------------------------------------------------------

local function do_combat_actions(mode, npc)
    if hidden() then return end

    local single, multi, aoe, guard

    if mode == "dark" then
        single = "Shadow Barb"
        multi  = "Barbed Sweep"
        aoe    = "Rain of Thorns"
        guard  = "Carrion Guard"
    else
        single = "Radiant Pulse"
        multi  = "Blast of Brilliance"
        aoe    = "Blinding Reprisal"
        guard  = "Wings of Warding"
    end

    -- Single target when ready
    if ability_ready(single) then
        while not ability_on_cooldown(single) do
            if npc.status and (string.find(npc.status, "dead") or string.find(npc.status, "gone")) then
                break
            end
            fire_wing_ability("turn my wing pin", single)
        end
        echo(string.rep(" ", 10) .. string.upper(single) .. " {!}")
    end

    -- Multi-target (3+ targets) when ready
    local targets = GameObj.targets and GameObj.targets() or GameObj.npcs()
    if #targets > 2 and ability_ready(multi) then
        while not ability_on_cooldown(multi) do
            if npc.status and (string.find(npc.status, "dead") or string.find(npc.status, "gone")) then
                break
            end
            fire_wing_ability("knock my wing pin", multi)
        end
        echo(string.rep(" ", 10) .. string.upper(multi) .. " {!}")
    end

    -- AOE (6+ targets) when ready
    targets = GameObj.targets and GameObj.targets() or GameObj.npcs()
    if #targets > 5 and ability_ready(aoe) then
        while not ability_on_cooldown(aoe) do
            if npc.status and (string.find(npc.status, "dead") or string.find(npc.status, "gone")) then
                break
            end
            fire_wing_ability("fold my wing pin", aoe)
        end
        echo(string.rep(" ", 10) .. string.upper(aoe) .. " {!}")
    end

    -- Defensive AOE (bleeding and targets present)
    if bleeding() and ability_ready(guard) then
        while not ability_on_cooldown(guard) do
            if npc.status and (string.find(npc.status, "dead") or string.find(npc.status, "gone")) then
                break
            end
            fire_wing_ability("push my wing pin", guard)
        end
        echo(string.rep(" ", 10) .. string.upper(guard) .. " {!}")
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local function run()
    -- Startup: auto-detect mode from worn pin
    local pin = find_wing_pin()
    local mode = wing_pin_mode(pin)

    if not pin or not mode then
        echo("Usage: Wear a dark or pale wing-shaped pin, then run ;energywings")
        echo("No dark/pale wing-shaped pin found in inventory.")
        local inv = GameObj.inv()
        for _, item in ipairs(inv) do
            if item and item.name and string.find(string.lower(item.name), "pin") then
                echo("INV: " .. item.name .. " #" .. tostring(item.id))
            end
        end
        return
    end

    echo("===============================================")
    echo("  ENERGYWINGS AUTO MODE: " .. string.upper(mode))
    echo("  PIN: " .. pin.name .. " #" .. tostring(pin.id))
    echo("===============================================")

    -- Register cleanup hook
    before_dying(function()
        unpause_scripts()
    end)

    -- Start the line listener for spell prep detection in a downstream hook
    DownstreamHook.add("energywings_prep_listener", function(line)
        -- Kill self if dead
        if dead() then
            Script.kill(Script.name)
            return line
        end

        -- Auto-switch if wing pin changed
        local new_pin = find_wing_pin()
        local new_mode = wing_pin_mode(new_pin)
        if new_pin and new_mode and (new_mode ~= mode or new_pin.id ~= pin.id) then
            mode = new_mode
            pin = new_pin
            echo("===============================================")
            echo("  ENERGYWINGS MODE SWITCHED: " .. string.upper(mode))
            echo("  PIN: " .. pin.name .. " #" .. tostring(pin.id))
            echo("===============================================")
        end

        -- Check for creature spell preps
        if matches_spell_prep(line) then
            react_to_enemy_prep(mode)
        end

        return line
    end)

    before_dying(function()
        DownstreamHook.remove("energywings_prep_listener")
    end)

    -- Main combat loop: evaluate combat conditions every 0.5 seconds
    while true do
        pause(0.5)

        if not in_allowed_room() then
            goto continue
        end

        local npc = living_npc()
        if not npc then
            goto continue
        end

        do_combat_actions(mode, npc)

        ::continue::
    end
end

run()
