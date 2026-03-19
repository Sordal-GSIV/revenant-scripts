--- Combat pattern definitions.
--- All attack, damage, status, UCS, and target extraction patterns in one file.
--- Uses Regex.new() for complex PCRE patterns, string.find for simple substrings.

local M = {}

---------------------------------------------------------------------------
-- Attack patterns (player → creature)
---------------------------------------------------------------------------
M.ATTACKS = {
    { name = "attack", patterns = {
        Regex.new([[You(?: take aim and)? swing .+? at (.+?)!]]),
    }},
    { name = "fire", patterns = {
        Regex.new([[You(?: take aim and)? fire .+? at (.+?)!]]),
    }},
    { name = "grapple", patterns = {
        Regex.new([[You(?: make a precise)? attempt to grapple (.+?)!]]),
    }},
    { name = "jab", patterns = {
        Regex.new([[You(?: make a precise)? attempt to jab (.+?)!]]),
    }},
    { name = "kick", patterns = {
        Regex.new([[You(?: make a precise)? attempt to kick (.+?)!]]),
    }},
    { name = "punch", patterns = {
        Regex.new([[You(?: make a precise)? attempt to punch (.+?)!]]),
    }},
    -- Spell attacks
    { name = "balefire", patterns = {
        Regex.new([[You hurl a ball of greenish-black flame at (.+?)!]]),
    }},
    { name = "natures_fury", patterns = {
        Regex.new([[The surroundings advance upon (.+?) with relentless fury!]]),
    }},
    { name = "sunburst", patterns = {
        Regex.new([[The dazzling solar blaze flashes before (.+?)!]]),
    }},
    { name = "searing_light", patterns = {
        Regex.new([[The radiant burst of light engulfs (.+?)!]]),
    }},
    { name = "web", patterns = {
        Regex.new([[Cloudy wisps swirl about (.+?)\.]]),
    }},
    { name = "ewave", patterns = {
        Regex.new([[(?:An?|Some) (.+?) is buffeted by the \w+ ethereal waves]]),
    }},
}

---------------------------------------------------------------------------
-- Damage patterns
---------------------------------------------------------------------------
M.DAMAGE_PATTERNS = {
    Regex.new([[\.\.\. and hit for (\d+) points? of damage!]]),
    Regex.new([[\.\.\. (\d+) points? of damage!]]),
    Regex.new([[\.\.\. hits for (\d+) points? of damage!]]),
    Regex.new([[causing (\d+) points? of damage!]]),
    Regex.new([[is ravaged for (\d+) points? of damage!]]),
}

---------------------------------------------------------------------------
-- Status effect add patterns
---------------------------------------------------------------------------
M.STATUS_ADD = {
    { name = "stunned", patterns = {
        Regex.new([[(?:The |A |An )(.+?) is stunned!]]),
    }},
    { name = "prone", patterns = {
        Regex.new([[It is knocked to the ground!]]),
        Regex.new([[(.+?) is knocked to the ground!]]),
        Regex.new([[(.+?) falls to the ground!]]),
    }},
    { name = "blind", patterns = {
        Regex.new([[You blinded (.+?)!]]),
    }},
    { name = "webbed", patterns = {
        Regex.new([[(.+?) becomes ensnared in thick strands of webbing!]]),
    }},
    { name = "sleeping", patterns = {
        Regex.new([[(.+?) falls into a deep slumber\.]]),
        Regex.new([[(.+?) falls asleep\.]]),
    }},
    { name = "immobilized", patterns = {
        Regex.new([[(.+?) form is entangled]]),
        Regex.new([[(.+?) shakes in utter terror!]]),
    }},
    { name = "sunburst", patterns = {
        Regex.new([[(.+?) reels and stumbles under the intense flare!]]),
    }},
    { name = "calm", patterns = {
        Regex.new([[A calm washes over (.+?)\.]]),
    }},
    { name = "poisoned", patterns = {
        Regex.new([[(.+?) appears to be suffering from a poison\.]]),
    }},
}

---------------------------------------------------------------------------
-- Status effect remove patterns
---------------------------------------------------------------------------
M.STATUS_REMOVE = {
    { name = "stunned", patterns = {
        Regex.new([[(.+?) shakes off the stun]]),
        Regex.new([[(.+?) regains .+? composure]]),
        Regex.new([[(.+?) is no longer stunned]]),
    }},
    { name = "prone", patterns = {
        Regex.new([[(.+?) stands back up]]),
        Regex.new([[(.+?) gets back to]]),
        Regex.new([[(.+?) rises to]]),
        Regex.new([[(.+?) stands up]]),
    }},
    { name = "blind", patterns = {
        Regex.new([[(.+?) vision clears]]),
    }},
    { name = "webbed", patterns = {
        Regex.new([[(.+?) breaks free of the webs]]),
        Regex.new([[(.+?) struggles free of the webs]]),
        Regex.new([[(.+?) tears through the webbing]]),
        Regex.new([[The webs dissolve from around (.+?)\.]]),
    }},
    { name = "sleeping", patterns = {
        Regex.new([[(.+?) wakes up]]),
        Regex.new([[(.+?) awakens]]),
        Regex.new([[(.+?) opens .+? eyes]]),
    }},
    { name = "immobilized", patterns = {
        Regex.new([[(.+?) movements no longer appear hampered]]),
        Regex.new([[The restricting force enveloping (.+?) fades away]]),
    }},
    { name = "sunburst", patterns = {
        Regex.new([[(.+?) blinks a few times, regaining a sense of balance]]),
    }},
    { name = "calm", patterns = {
        Regex.new([[The calmed look leaves (.+?)\.]]),
        Regex.new([[(.+?) is enraged by your attack!]]),
    }},
    { name = "poisoned", patterns = {
        Regex.new([[(.+?) looks much better\.]]),
        Regex.new([[(.+?) recovers from the poison\.]]),
    }},
}

---------------------------------------------------------------------------
-- UCS (Unarmed Combat System) patterns
---------------------------------------------------------------------------
M.UCS_POSITION  = Regex.new([[^You have (decent|good|excellent) positioning against]])
M.UCS_TIERUP    = Regex.new([[Strike leaves foe vulnerable to a followup (jab|grapple|punch|kick) attack!]])
M.UCS_SMITE_ON  = Regex.new([[A crimson mist suddenly surrounds]])
M.UCS_SMITE_OFF = Regex.new([[The crimson mist surrounding .+ returns to an ethereal state]])

---------------------------------------------------------------------------
-- Target extraction from XML links
---------------------------------------------------------------------------
M.TARGET_LINK   = Regex.new([[<a exist="([^"]+)" noun="([^"]+)">([^<]+)</a>]])
M.BOLD_WRAPPER  = Regex.new([[<pushBold/>.*?<a exist="[^"]+"[^>]+>[^<]+</a>.*?<popBold/>]])

return M
