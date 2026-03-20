--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: kswole
--- version: 1.1.6
--- author: elanthia-online
--- contributors: Nidal, Tysong, FFNG, H2U, Phocosoen, Dissonance
--- game: gs
--- description: Automate Feat Absorb/Dispel for Kroderine Soul; Shield Mind fallback
--- tags: kroderine-soul,feat-absorb,feat-dispel
---
--- Changelog (from Lich5):
---   v1.1.6 (2026-02-03) - Added preps for WL Graveyard's Shadow Valley
---   v1.1.5 (2026-01-06) - Added preps for Ta'Vaalor areas
---   v1.1.4 (2025-09-07) - Add additional Frozen Bramble prep
---   v1.1.3 (2025-09-01) - Nelemar/Atoll regex corrections
---   v1.1.2 (2025-07-18) - Regex optimizations
---   v1.1.1 (2025-07-14) - Add Sailor's Grief
---   v1.1.0 (2025-05-08) - Shield Mind support
---   v1.0.0 (2023-08-26) - Migration from Nidal to EO

--------------------------------------------------------------------------------
-- Creature spell prep patterns (combined regex)
--------------------------------------------------------------------------------

local CREATURE_SPELL_PREPS = Regex.new(table.concat({
    -- Atoll and Nelemar
    "^An? (?:.*)\\belemental utters an incantation in an unfamiliar, bubbling language\\.",
    "^An? (?:.*)\\b(?:fanatic|radical) steeples (?:his|her) clawed fingers together, murmuring a quick incantation\\.",
    "^An? (?:.*)\\bsiren begins singing a sweet song\\.",
    "^An? (?:.*)\\b(?:magus|warden) makes a subtle gesture, drawing traces of faint blue-green light into (?:his|her) webbed hands\\.",
    "^An? (?:.*)\\b(?:warlock|dissembler|sentry|psionicist) chants in an incomprehensible language, causing streams of dim grey energy to lash about (?:his|her) (?:hands|golden claws)\\.",
    -- Bonespear
    "^(?:.*) draws an ancient sigil in the air\\.",
    -- Bowels
    "^An? (?:.*)\\belder invokes the power of (?:his|her) god, the symbol on (?:his|her) forehead glowing brightly\\.",
    "^An? (?:.*)\\bjarl traces a simple symbol as (?:he|she) reverently calls upon the power of (?:his|her) god\\.",
    -- Citadel
    "^An? (?:.*)\\bapprentice whispers a magical incantation, bending the elements to (?:his|her) whim\\.",
    "^An? (?:.*)\\bherald seethes a forceful chant, commanding the spirits to do (?:his|her) bidding\\.",
    -- Confluence
    "^(?:.*) glows with a bright blue light\\.",
    "^(?:.*) rumbles with an inner power\\.",
    "^(?:.*) utters an incantation in an unfamiliar, bubbling language\\.",
    "^(?:.*) whispers an incantation into the wind\\.",
    "^(?:.*) raises a molten appendage",
    "^(?:.*) sparks wildly",
    "^(?:.*) sizzles with power\\.",
    "^(?:.*) releases a burst of fiery energy",
    -- Crawling Shore
    "^(?:.*) groans out a malevolent series of mystical syllables, causing the surrounding shadows to burn crimson\\.",
    "^(?:.*) mutters an old, guttural chant as the surroundings grow terribly silent\\.",
    -- Den of Rot
    "^An? (?:.*)\\bincubus begins singing a softly melodic melody, his lips quirking with cruel amusement\\.",
    "^An? (?:.*)\\binciter raises (?:his|her) voice in a ululating chant, surrounding (?:himself|herself) with wisps of sickly green energy\\.",
    "^An? (?:.*)\\bvereri sets her lips in a petulant pout\\.",
    "^An? (?:.*)\\bvision begins buzzing loudly, its corrupt aura turning a deeper shade of bile green\\.",
    -- Duskruin Arena
    "^(?:.*) utters a guttural, primitive prayer\\.",
    "^(?:.*) raises (?:his|her) fists to the sky\\.",
    "^(?:.*) begins to shiver\\.",
    "^(?:.*) shouts out an arcane phrase of magic\\.",
    "^(?:.*) whispers a string of delicate words\\.",
    "^(?:.*) rubs (?:his|her) magical horn\\.",
    "^(?:.*) barks some odd sounds\\.",
    -- Graveyard, Shadow Valley
    "^An? (?:.*)\\bshadow mare fades visibly, flicking (?:his|her) tail\\.\\.\\.",
    "^An? (?:.*)\\bshadow steed shakes (?:his|her) mane\\.",
    "^An? (?:.*)\\bnight mare flares (?:his|her) nostrils\\.",
    -- Grimswarm
    "^An? (?:.*)\\b(?:witch|sorcerer|sorceress) gestures and utters a phrase of magic\\.",
    -- Hidden Plateau
    "^An? (?:.*)\\bmagus begins rumbling while making mystic gestures through the air\\.",
    -- Hinterwilds
    "^An? (?:.*)\\bbloodspeaker utters a garbled, sibilant phrase as globules of crimson light spin around (?:his|her) gnarled hands\\.",
    "^An? (?:.*)\\bgolem glows with shimmering incarnadine light that suffuses its monstrous form with power\\.",
    "^An? (?:.*)\\bwendigo rasps out a dissonant, sing-song phrase\\.",
    "^An? (?:.*)\\bskald raises (?:his|her) voice into a reverberating dirge, the surrounding shadows dancing in time with the tune\\.",
    "^An? (?:.*)\\bshield-maiden raises a fist to the heavens as her eyes begin to glow like molten gold\\.",
    "^An? (?:.*)\\bdisir raises a hand skyward, suffusing herself with scintillating power\\.",
    "^An? (?:.*)\\bmutant twitches, (?:his|her) distended cranium pulsing as a look of intense focus stills (?:his|her) face\\.",
    "^An? (?:.*)\\bdisir silently mouths an incantation that does not seem to be in any language you know\\.",
    "^An? (?:.*)\\bdisir focuses her luminous gaze upon you!",
    "^An? (?:.*)\\bdisciple gestures with one bloody hand, chanting a sibilant prayer\\.",
    "^An? (?:.*)\\bangargeist lights from within, energy crackling within its chaotic core\\.",
    -- Icemule Trace
    "^An? (?:.*)\\bvine twirls an appendage in a complex circle\\.",
    "^An? (?:.*)\\bglacei flares with a deep blue glow\\.",
    "^An? (?:.*)\\bdirge begins to wail loudly!",
    "^An? (?:.*)\\bapparition draws slowly inward!",
    "^An? (?:.*)\\bwraith draws inward for a moment!",
    "^(?:.*) begins to moan an incantation!",
    "^(?:.*) chants an evil incantation\\.",
    "^(?:.*) begins to shiver violently!",
    "^(?:.*) begins to shiver\\.",
    "^(?:.*) mutters an incantation\\.",
    "^(?:.*) utters a phrase of arcane magic\\.",
    "^An? (?:.*)\\bcrone mutters a frosty incantation\\.",
    "^(?:.*) raises its fists to the sky\\.",
    "^An? (?:.*)\\bplant opens and closes one of its flowers\\.",
    -- Moonsedge
    "^An? (?:.*)\\bbanshee raises her voice in a shrill, eerie song that makes the surrounding mists dance\\.",
    "^An? (?:.*)\\bgrotesque rumbles out a basso incantation, clenching one carved claw as its eyes glow viridian\\.",
    "^An? (?:.*)\\bknight twists a skeletal hand, uttering a blasphemous chant\\.",
    "^An? (?:.*)\\bvampire slices a shadowy sigil in the air as (?:he|she) utters an old chant\\.",
    "^An? (?:.*)\\bconjurer gives a flourish of (?:his|her) spectral arms as (?:he|she) raises (?:his|her) voice in a theatrical chant\\.",
    -- OSA
    "^(?:.*) snarls as (?:he|she) chants a few words of magic\\.",
    -- OTF (incl. Aqueducts)
    "^An? (?:.*)\\bbeing rumbles a series of arcane phrases\\.",
    "^An? (?:.*)\\binitiate closes (?:his|her) eyes while uttering a hollow, alien chant\\.",
    "^An? (?:.*)\\bherald starts singing an alien song in a reverberating, sonorous voice\\.",
    "^An? (?:.*)\\badept closes (?:his|her) eyes while incanting an alien phrase\\.",
    "^An? (?:.*)\\bseer closes (?:his|her) eyes and bows (?:his|her) head slightly\\.",
    "^(?:.*) mutters a phrase of magic\\.",
    -- Red Forest
    "^An? (?:.*)\\bviper hisses an arcane phrase in an unfamiliar sibilant language\\.",
    "^An? (?:.*)\\bspirit whistles a soft, malicious tune\\.",
    "^An? (?:.*)\\bpixie hands begin to glow\\.",
    "^An? (?:.*)\\bsprite raises a finger to (?:his|her) lips\\.",
    "^An? (?:.*)\\bdruid groans an incantation\\.",
    -- Reim
    "^(?:.*) glows as (?:he|she) chants a few words of magic\\.",
    -- Rift and Scatter
    "^An? (?:.*)\\bwitch whispers with an ominously soft voice\\.",
    "^An? (?:.*)\\bseraceris begins to hum\\.",
    "^An? (?:.*)\\bnaisirc glows with an eerie green light\\.",
    "^An? (?:.*)\\bcsetairi waves her four arms in a triangular motion\\.",
    "^An? (?:.*)\\bwarlock pauses a moment as his eyes swim black with anti-mana\\.",
    "^An? (?:.*)\\b(?:avenger|crusader) traces a twisted symbol as (?:he|she) calls upon (?:his|her) inner power\\.",
    "^An? (?:.*)\\bvaespilon draws an ancient sigil in the air\\.",
    "^An? (?:.*)\\bsoul gestures and utters a phrase of arcane magic\\.",
    "^An? (?:.*)\\bcerebralite twists and coils its tentacles, sending tendrils of electricity crawling along the surface of its brain-like form\\.",
    "^An? (?:.*)\\bsiphon scythes its bladed arms together, creating a strident grating sound\\.",
    "^An? (?:.*)\\bmaster raises its hands while emitting a dissonant sing-song rhythm, causing the tattoos along its forearms and hands to flare to life with a dark light\\.",
    "^An? (?:.*)\\blich hisses out an incantation, (?:his|her) raspy breath (?:distorting|marking) the air with (?:a shimmer|hazy clouds)\\.",
    -- Sanctum
    "^An? (?:.*)\\blurk moans out a garbled spell\\.",
    "^An? (?:.*)\\bsentinel mumbles a silent and sibilant prayer, channeling blue-green energy down (?:his|her) arms\\.",
    "^An? (?:.*)\\bfanatic throws back (?:his|her) head, quickening the air around (?:him|her) with motes of virescent light\\.",
    "^An? (?:.*)\\bshaper whispers an inhuman entreaty, and the shadows grow frenized and green-tinged around (?:him|her)\\.",
    -- The Hive, Zul Logoth
    "^An? (?:.*)\\bthrall clumsily twists (?:her|his) palsied hands into a spell form, (?:her|his) fingers trailing waves of psionic energy\\.",
    "^An? (?:.*)\\bstrandweaver weaves complex threads of raw mana with (?:her|his) pale legs\\.",
    -- Stormpeak, Titan's Deluge
    "^An? (?:.*)\\bherald chants in a low, guttural voice\\.",
    "^An? (?:.*)\\bfiend thrums with an upswelling of elemental energy\\.",
    "^An? (?:.*)\\bstormcaller mutters a thunderous chant as she lifts her eyes skyward\\.",
    -- Forgotten Vineyard
    "^An? (?:.*)\\b(?:sorcerer|sorceress) draws a glowing sigil in the air\\.",
    "^An? (?:.*)\\b(?:sorcerer|sorceress) extends (?:her|his) finger toward you!",
    "^An? (?:.*)\\b(?:bard|bardesss) begins to growl a guttural melody\\.",
    "^An? (?:.*)\\b(?:bard|bardesss) directs (?:her|his) guttural voice at you!",
    "^An? (?:.*)\\bempath quietly growls a phrase of magic\\.",
    "^An? (?:.*)\\bempath snarls and gestures sharply at you!",
    "^An? (?:.*)\\bempath draws a large sign in the air before (?:her|his)\\.\\.\\.",
    "^An? (?:.*)\\bshaman utters an ancient prayer\\.",
    "^An? (?:.*)\\bshaman waves a hand dismissively at you!",
    -- Sailor's Grief
    "^An? (?:.*)\\boracle gurgles in a lost tongue, crackles of blue-green energy tangling over (?:his|her) misshapen limbs\\.",
    "^An? (?:.*)\\bmerrow croaks deep in (?:his|her) throat, channeling a torrent of shimmering energy down one squamous arm\\.",
    "^An? (?:.*)\\bbuccaneer lifts a rattling voice in an old nautical chanty\\.",
    "^An? (?:.*)\\bmass pulses grotesquely, sprouting mouths that chant in an ugly arcane tongue\\.",
    "^An? (?:.*)\\bkelpie emits a strange bluish light as the music of rushing water echoes around (?:him|her)\\.",
    -- Ta'Vaalor
    "^The (?:.*)\\bsiren whispers a seductive song\\.",
    "^An? (?:.*)\\brevenant draws slowly inward!",
    "^The (?:.*)\\bapparition wails with an unearthly cry!",
    "^The (?:.*)\\bdirge wails a sad, eerie song!",
    "^The (?:.*)\\bdarkwoode whispers with a sinister voice carried on the wind!",
    "^An? (?:.*)\\bgrey orc utters a harsh phrase of magic\\.",
    "^An? (?:.*)\\bghoul master mutters a chant!",
    "^An? (?:.*)\\barch wight chants an evil incantation\\.",
    "^An? (?:.*)\\bniirsha draws a fiery symbol in the air\\.",
    "^An? (?:.*)\\bcentaur ranger intones a low-pitched chant\\.",
    "^An? (?:.*)\\bsacristan spirit utters an arcane incantation\\.",
    "^An? (?:.*)\\bmonk utters an arcane incantation\\.",
    "^An? (?:.*)\\bwood sprite utters an eerie sound\\.",
    "^An? (?:.*)\\bspectre glows faintly as a spectral mist begins to swirl around (?:her|him)\\.",
}, "|"))

--------------------------------------------------------------------------------
-- Dispelable debuffs
--------------------------------------------------------------------------------

local DISPELABLE_DEBUFFS = {
    "Web", "Calm", "Interference", "Bind", "Frenzy", "Condemn",
    "Weapon Deflection", "Elemental Saturation", "Slow", "Cold Snap",
    "Stone Fist", "Immolation", "Wild Entropy", "Sounds",
    "Holding Song", "Song of Depression", "Song of Rage",
    "Vertigo", "Confusion", "Thought Lash", "Mindwipe",
    "Pious Trial", "Aura of the Arkati",
}

local SCRIPTS_TO_PAUSE = { "bigshot" }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function has_debuff()
    for _, debuff in ipairs(DISPELABLE_DEBUFFS) do
        if Effects.Debuffs.active(debuff) then
            return true
        end
    end
    return false
end

local function pause_scripts()
    for _, name in ipairs(SCRIPTS_TO_PAUSE) do
        if running(name) then Script.pause(name) end
    end
end

local function unpause_scripts()
    for _, name in ipairs(SCRIPTS_TO_PAUSE) do
        if running(name) then Script.unpause(name) end
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("| KSwole will automatically use Feat Absorb and Feat Dispel for Kroderine Soul characters.")
    respond("| If Feat Absorb is unavailable or unknown, it will use Shield Mind for Shield Mind specialists.")
    respond("| The script depends on a library of creature spell prep messaging.")
    respond("|   https://github.com/elanthia-online/scripts")
    respond("|")
    respond("| Hunting areas currently supported:")
    respond("|   Atoll/Nelemar, Bonespear, Bowels, Citadel, Confluence, Crawling Shore, Den of Rot,")
    respond("|   Duskruin Arena, Faethyl Bog, Forgotten Vineyard, Grimswarm, Hidden Plateau,")
    respond("|   Hinterwilds, Moonsedge, OSA (partial), OTF (incl. Aqueducts), Red Forest, Reim,")
    respond("|   Rift/Scatter, Sailor's Grief, Sanctum of Scales, Stormpeak/Titan's Deluge,")
    respond("|   Icemule Trace (partial), Ta'Vaalor (partial), The Hive,")
    respond("|   WL Graveyard/Shadow Valley.")
    respond("|")
    respond("| Usage:")
    respond("|   ;kswole")
    respond("|   ;kswole help")
end

--------------------------------------------------------------------------------
-- Prerequisites check
--------------------------------------------------------------------------------

local function check_prerequisites()
    local has_ks = Feat.known("Kroderine Soul") or (Feat.known("Absorb Magic") and Feat.known("Dispel Magic"))
    local has_sm = Shield.known("Shield Mind")
    if not has_ks and not has_sm then
        respond("| ERROR: This script requires Kroderine Soul feats or Shield Mind specialization.")
        respond("| If you recently fixskilled into Kroderine Soul, type FEAT LIST ALL and try again.")
        respond("| If you recently fixskilled into Shield Mind, type SHIELD LIST ALL and try again.")
        return false
    end
    respond("| KSwole active. Monitoring for creature spell preps...")
    return true
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

local function run()
    if not check_prerequisites() then return end

    while true do
        local line = get()
        if not line then break end

        if dead() then return end

        if CREATURE_SPELL_PREPS:test(line) then
            if not stunned() and not Effects.Debuffs.active("Sympathy") then
                if Feat.available("Absorb Magic") and not Effects.Cooldowns.active("Absorb Magic") then
                    -- Feat Absorb available and off cooldown
                    waitcastrt()
                    local absorb = dothistimeout("feat absorb", 2, {
                        "You open yourself to the ravenous void",
                        "You strain, but the void within remains stubbornly out of reach",
                    })
                    if absorb and string.find(absorb, "You strain") then
                        -- Cooldown hit unexpectedly; wait for availability then retry
                        wait_until(function() return Feat.available("Absorb Magic") end)
                        fput("feat absorb")
                    end
                elseif Shield.available("Shield Mind") then
                    -- Feat Absorb unavailable; fall back to Shield Mind
                    waitcastrt()
                    waitrt()
                    pause_scripts()
                    local sm = dothistimeout("shield mind", 2, {
                        "thereby forcing any incoming attacks against your mind or soul to penetrate your",
                        "You must be wielding a shield",
                        "You cannot muster the necessary focus to shield your mind and soul quite so soon",
                    })
                    unpause_scripts()
                    -- If on cooldown, skip (next iteration)
                end
            end
        elseif has_debuff() then
            if not stunned() then
                if Feat.available("Dispel Magic") then
                    -- Try Feat Dispel
                    waitcastrt()
                    local dispel = dothistimeout("feat dispel", 2, {
                        "You reach for the emptiness within",
                        "You are unable to reach past the twisting tension",
                    })
                    if dispel and string.find(dispel, "You are unable") then
                        -- Dispel on cooldown; fall through to Mental Dispel
                        if Feat.known("Mental Acuity") and Spell[1218].known and Spell[1218]:affordable() and not muckled() then
                            pause_scripts()
                            Spell[1218]:force_channel(GameState.name)
                            pause(0.5)
                            unpause_scripts()
                        end
                    end
                elseif Feat.known("Mental Acuity") and Spell[1218].known and Spell[1218]:affordable() and not muckled() then
                    -- Feat Dispel not available; try Mental Dispel (1218) directly
                    pause_scripts()
                    Spell[1218]:force_channel(GameState.name)
                    pause(0.5)
                    unpause_scripts()
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]
if arg1 and string.lower(arg1) == "help" then
    show_help()
else
    run()
end
