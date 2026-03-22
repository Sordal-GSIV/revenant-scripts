--- DRCH — DR Common Healing utilities.
-- Ported from Lich5 common-healing.rb + common-healing-data.rb (module DRCH).
-- Provides health checking, wound parsing, tending, and healing prioritization.
-- @module lib.dr.common_healing
local M = {}

-------------------------------------------------------------------------------
-- Constants: bleed rates, wound severity, lodged severity
-------------------------------------------------------------------------------

--- Maps bleed rate text from HEALTH to severity and tending skill requirements.
-- https://elanthipedia.play.net/Damage#Bleeding_Levels
M.BLEED_RATE_TO_SEVERITY = {
  ["tended"]                   = { severity = 1,  bleeding = false, skill_to_tend = nil, skill_to_tend_internal = nil },
  ["(tended)"]                 = { severity = 1,  bleeding = false, skill_to_tend = nil, skill_to_tend_internal = nil },
  ["clotted"]                  = { severity = 2,  bleeding = false, skill_to_tend = nil, skill_to_tend_internal = nil },
  ["clotted(tended)"]          = { severity = 3,  bleeding = false, skill_to_tend = nil, skill_to_tend_internal = nil },
  ["slight"]                   = { severity = 3,  bleeding = true,  skill_to_tend = 30,  skill_to_tend_internal = 600 },
  ["slight(tended)"]           = { severity = 4,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["light"]                    = { severity = 4,  bleeding = true,  skill_to_tend = 40,  skill_to_tend_internal = 600 },
  ["light(tended)"]            = { severity = 5,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["moderate"]                 = { severity = 5,  bleeding = true,  skill_to_tend = 50,  skill_to_tend_internal = 600 },
  ["moderate(tended)"]         = { severity = 6,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["bad"]                      = { severity = 6,  bleeding = true,  skill_to_tend = 60,  skill_to_tend_internal = 620 },
  ["bad(tended)"]              = { severity = 7,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["very bad"]                 = { severity = 7,  bleeding = true,  skill_to_tend = 75,  skill_to_tend_internal = 620 },
  ["very bad(tended)"]         = { severity = 8,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["heavy"]                    = { severity = 8,  bleeding = true,  skill_to_tend = 90,  skill_to_tend_internal = 640 },
  ["heavy(tended)"]            = { severity = 9,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["very heavy"]               = { severity = 9,  bleeding = true,  skill_to_tend = 105, skill_to_tend_internal = 640 },
  ["very heavy(tended)"]       = { severity = 10, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["severe"]                   = { severity = 10, bleeding = true,  skill_to_tend = 120, skill_to_tend_internal = 660 },
  ["severe(tended)"]           = { severity = 11, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["very severe"]              = { severity = 11, bleeding = true,  skill_to_tend = 140, skill_to_tend_internal = 660 },
  ["very severe(tended)"]      = { severity = 12, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["extremely severe"]         = { severity = 12, bleeding = true,  skill_to_tend = 160, skill_to_tend_internal = 700 },
  ["extremely severe(tended)"] = { severity = 13, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["profuse"]                  = { severity = 13, bleeding = true,  skill_to_tend = 180, skill_to_tend_internal = 800 },
  ["profuse(tended)"]          = { severity = 14, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["very profuse"]             = { severity = 14, bleeding = true,  skill_to_tend = 205, skill_to_tend_internal = 800 },
  ["very profuse(tended)"]     = { severity = 15, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["massive"]                  = { severity = 15, bleeding = true,  skill_to_tend = 230, skill_to_tend_internal = 850 },
  ["massive(tended)"]          = { severity = 16, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["gushing"]                  = { severity = 16, bleeding = true,  skill_to_tend = 255, skill_to_tend_internal = 850 },
  ["gushing(tended)"]          = { severity = 17, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["massive stream"]           = { severity = 17, bleeding = true,  skill_to_tend = 285, skill_to_tend_internal = 1000 },
  ["massive stream(tended)"]   = { severity = 18, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["gushing fountain"]         = { severity = 18, bleeding = true,  skill_to_tend = 285, skill_to_tend_internal = 1200 },
  ["gushing fountain(tended)"] = { severity = 19, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["uncontrollable"]           = { severity = 19, bleeding = true,  skill_to_tend = 400, skill_to_tend_internal = 1400 },
  ["uncontrollable(tended)"]   = { severity = 20, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["unbelievable"]             = { severity = 20, bleeding = true,  skill_to_tend = 500, skill_to_tend_internal = 1600 },
  ["unbelievable(tended)"]     = { severity = 21, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["beyond measure"]           = { severity = 21, bleeding = true,  skill_to_tend = 600, skill_to_tend_internal = 1750 },
  ["beyond measure(tended)"]   = { severity = 22, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["death awaits"]             = { severity = 22, bleeding = true,  skill_to_tend = 700, skill_to_tend_internal = 1750 },
}

--- Lodged item depth to severity.
M.LODGED_SEVERITY = {
  ["loosely hanging"] = 1,
  ["shallowly"]       = 2,
  ["firmly"]          = 3,
  ["deeply"]          = 4,
  ["savagely"]        = 5,
}

--- Wound severity descriptions from PERCEIVE HEALTH.
M.WOUND_SEVERITY = {
  insignificant    = 1,
  negligible       = 2,
  minor            = 3,
  ["more than minor"]  = 4,
  harmful          = 5,
  ["very harmful"] = 6,
  damaging         = 7,
  ["very damaging"]= 8,
  severe           = 9,
  ["very severe"]  = 10,
  devastating      = 11,
  ["very devastating"] = 12,
  useless          = 13,
}

-------------------------------------------------------------------------------
-- Regex constants (ported from common-healing-data.rb)
-------------------------------------------------------------------------------

--- Parasite types (regex patterns).
-- https://elanthipedia.play.net/Damage#Parasites
M.PARASITES_REGEX = {
  "(?:small|large) (?:black|red) blood mite",
  "(?:black|red|albino) (?:sand|forest) leech",
  "(?:green|red) blood worm",
  "retch maggot",
}

--- Perceived health severity regex (from PERCEIVE HEALTH output).
M.PERCEIVE_HEALTH_SEVERITY_REGEX = "(?<freshness>Fresh|Scars) (?<location>External|Internal).+--\\s+(?<severity>insignificant|negligible|minor|more than minor|harmful|very harmful|damaging|very damaging|severe|very severe|devastating|very devastating|useless)\\b"

--- Body part regex components.
M.BODY_PART_REGEX = "(?<part>(?:l\\.|r\\.|left|right)?\\s?(?:\\w+))"

--- Wound body part regex (includes optional "inside" prefix).
M.WOUND_BODY_PART_REGEX = "(?:inside)?\\s?" .. M.BODY_PART_REGEX

--- Lodged body part regex.
M.LODGED_BODY_PART_REGEX = "lodged .* into your " .. M.BODY_PART_REGEX

--- Parasite body part regex.
M.PARASITE_BODY_PART_REGEX = "on your " .. M.BODY_PART_REGEX

--- Bleeder line regex (matches body part lines in HEALTH bleeder table).
M.BLEEDER_LINE_REGEX = "^\\b(inside\\s+)?((l\\.|r\\.|left|right)\\s+)?(head|eye|neck|chest|abdomen|back|arm|hand|leg|tail|skin)\\b"

--- Wound comma separator (protects compound descriptions from splitting).
M.WOUND_COMMA_SEPARATOR = "(?<=swollen|bruised|scarred|painful),(?=\\s(?:swollen|bruised|mangled|inflamed))"

-------------------------------------------------------------------------------
-- WOUND_SEVERITY_REGEX_MAP — all 114 entries from common-healing-data.rb
-- https://elanthipedia.play.net/Damage#Wounds
-------------------------------------------------------------------------------

M.WOUND_SEVERITY_REGEX_MAP = {
  -- insignificant (severity 1)
  { pattern = "minor abrasions to the " .. M.WOUND_BODY_PART_REGEX,                                                                    severity = 1, internal = false, scar = false },
  { pattern = "a few nearly invisible scars along the " .. M.WOUND_BODY_PART_REGEX,                                                    severity = 1, internal = false, scar = true },
  -- negligible (severity 2)
  { pattern = "some tiny scars (?:across|along) the " .. M.WOUND_BODY_PART_REGEX,                                                      severity = 2, internal = false, scar = true },
  { pattern = "(?:light|tiny) scratches to the " .. M.WOUND_BODY_PART_REGEX,                                                           severity = 2, internal = false, scar = false },
  -- minor / more than minor (severity 3)
  { pattern = "a bruised (?<part>head)",                                                                                                severity = 3, internal = true,  scar = false },
  { pattern = "(?<skin>a small skin rash)",                                                                                             severity = 3, internal = false, scar = false },
  { pattern = "(?<skin>loss of skin tone)",                                                                                             severity = 3, internal = false, scar = true },
  { pattern = "(?<skin>some minor twitching)",                                                                                          severity = 3, internal = true,  scar = false },
  { pattern = "(?<skin>slight difficulty moving your fingers and toes)",                                                                severity = 3, internal = true,  scar = true },
  { pattern = "cuts and bruises about the " .. M.WOUND_BODY_PART_REGEX,                                                                severity = 3, internal = false, scar = false },
  { pattern = "minor scar\\w+ (?:about|along|across) the " .. M.WOUND_BODY_PART_REGEX,                                                 severity = 3, internal = false, scar = true },
  { pattern = "minor swelling and bruising (?:around|in) the " .. M.WOUND_BODY_PART_REGEX,                                             severity = 3, internal = true,  scar = false },
  { pattern = "occasional twitch\\w* (?:on|in) the " .. M.WOUND_BODY_PART_REGEX,                                                       severity = 3, internal = true,  scar = true },
  { pattern = "a black and blue " .. M.WOUND_BODY_PART_REGEX,                                                                          severity = 3, internal = false, scar = false },
  -- harmful / very harmful (severity 4)
  { pattern = "a deeply bruised (?<part>head)",                                                                                         severity = 4, internal = true,  scar = false },
  { pattern = "(?<skin>a large skin rash)",                                                                                             severity = 4, internal = false, scar = false },
  { pattern = "(?<skin>minor skin discoloration)",                                                                                      severity = 4, internal = false, scar = true },
  { pattern = "(?<skin>some severe twitching)",                                                                                         severity = 4, internal = true,  scar = false },
  { pattern = "(?<skin>slight numbness in your arms and legs)",                                                                         severity = 4, internal = true,  scar = true },
  { pattern = "deep cuts (?:about|across) the " .. M.WOUND_BODY_PART_REGEX,                                                            severity = 4, internal = false, scar = false },
  { pattern = "severe scarring (?:across|along|about) the " .. M.WOUND_BODY_PART_REGEX,                                                severity = 4, internal = false, scar = true },
  { pattern = "a severely swollen and\\s?(?:deeply)? bruised " .. M.WOUND_BODY_PART_REGEX,                                             severity = 4, internal = true,  scar = false },
  { pattern = "(?:occasional|constant) twitch\\w* (?:on|in) the " .. M.WOUND_BODY_PART_REGEX,                                          severity = 4, internal = true,  scar = true },
  { pattern = "a bruised and swollen (?<part>(?:right|left) (?:eye))",                                                                  severity = 4, internal = false, scar = false },
  -- damaging / very damaging (severity 5)
  { pattern = "some deep slashes and cuts about the (?<part>head)",                                                                     severity = 5, internal = false, scar = false },
  { pattern = "severe scarring and ugly gashes about the " .. M.WOUND_BODY_PART_REGEX,                                                 severity = 5, internal = false, scar = true },
  { pattern = "major swelling and bruising around the (?<part>head)",                                                                   severity = 5, internal = true,  scar = false },
  { pattern = "an occasional twitch on the fore(?<part>head)",                                                                          severity = 5, internal = true,  scar = true },
  { pattern = "a bruised,* swollen and bleeding " .. M.WOUND_BODY_PART_REGEX,                                                          severity = 5, internal = false, scar = false },
  { pattern = "deeply scarred gashes across the " .. M.WOUND_BODY_PART_REGEX,                                                          severity = 5, internal = false, scar = true },
  { pattern = "a severely swollen, bruised and crossed " .. M.WOUND_BODY_PART_REGEX,                                                   severity = 5, internal = true,  scar = false },
  { pattern = "a constant twitching in the " .. M.WOUND_BODY_PART_REGEX,                                                               severity = 5, internal = true,  scar = true },
  { pattern = "deep slashes across the " .. M.WOUND_BODY_PART_REGEX,                                                                   severity = 5, internal = false, scar = false },
  { pattern = "a severely swollen and deeply bruised " .. M.WOUND_BODY_PART_REGEX,                                                     severity = 5, internal = true,  scar = false },
  { pattern = "severely swollen and bruised " .. M.WOUND_BODY_PART_REGEX,                                                              severity = 5, internal = true,  scar = false },
  { pattern = "a constant twitching in the (?<part>chest) area and difficulty breathing",                                               severity = 5, internal = true,  scar = true },
  { pattern = "(?<abdomen>a somewhat emaciated look)",                                                                                  severity = 5, internal = true,  scar = true },
  { pattern = "a constant twitching in the " .. M.WOUND_BODY_PART_REGEX .. " and difficulty moving in general",                         severity = 5, internal = true,  scar = true },
  { pattern = "(?<skin>a body rash)",                                                                                                   severity = 5, internal = false, scar = false },
  { pattern = "severe (?<part>skin) discoloration",                                                                                     severity = 5, internal = false, scar = true },
  { pattern = "(?<skin>difficulty controlling actions)",                                                                                severity = 5, internal = true,  scar = false },
  { pattern = "(?<skin>numbness in your fingers and toes)",                                                                             severity = 5, internal = true,  scar = true },
  -- severe / very severe (severity 6)
  { pattern = "(?<head>a cracked skull with deep slashes)",                                                                             severity = 6, internal = false, scar = false },
  { pattern = "missing chunks out of the (?<part>head)",                                                                                severity = 6, internal = false, scar = true },
  { pattern = "a bruised, swollen and slashed " .. M.WOUND_BODY_PART_REGEX,                                                            severity = 6, internal = false, scar = false },
  { pattern = "a punctured and shriveled " .. M.WOUND_BODY_PART_REGEX,                                                                 severity = 6, internal = false, scar = true },
  { pattern = "a severely swollen,* bruised and cloudy " .. M.WOUND_BODY_PART_REGEX,                                                   severity = 6, internal = true,  scar = false },
  { pattern = "a clouded " .. M.WOUND_BODY_PART_REGEX,                                                                                 severity = 6, internal = true,  scar = true },
  { pattern = "gaping holes in the " .. M.WOUND_BODY_PART_REGEX,                                                                       severity = 6, internal = false, scar = false },
  { pattern = "a broken " .. M.WOUND_BODY_PART_REGEX .. " with gaping holes",                                                          severity = 6, internal = false, scar = false },
  { pattern = "severe scarring and ugly gashes about the " .. M.WOUND_BODY_PART_REGEX,                                                 severity = 6, internal = false, scar = true },
  { pattern = "severe scarring and chunks of flesh missing from the " .. M.WOUND_BODY_PART_REGEX,                                      severity = 6, internal = false, scar = true },
  { pattern = "a severely swollen and deeply bruised " .. M.WOUND_BODY_PART_REGEX .. " with odd protrusions under the skin",            severity = 6, internal = true,  scar = false },
  { pattern = "a severely swollen and deeply bruised (?<part>chest) area with odd protrusions under the skin",                          severity = 6, internal = true,  scar = false },
  { pattern = "a partially paralyzed " .. M.WOUND_BODY_PART_REGEX,                                                                     severity = 6, internal = true,  scar = true },
  { pattern = "a painful " .. M.WOUND_BODY_PART_REGEX .. " and difficulty moving without pain",                                         severity = 6, internal = true,  scar = true },
  { pattern = "a painful (?<part>chest) area and difficulty getting a breath without pain",                                             severity = 6, internal = true,  scar = true },
  { pattern = "a severely bloated and discolored " .. M.WOUND_BODY_PART_REGEX .. " with strange round lumps under the skin",            severity = 6, internal = true,  scar = false },
  { pattern = "(?<abdomen>a definite greenish pallor and emaciated look)",                                                              severity = 6, internal = true,  scar = true },
  { pattern = "(?<skin>a painful,* inflamed body rash)",                                                                                severity = 6, internal = false, scar = false },
  { pattern = "(?<skin>a painful,* enflamed body rash)",                                                                                severity = 6, internal = false, scar = false },
  { pattern = "some shriveled and oddly folded (?<part>skin)",                                                                          severity = 6, internal = false, scar = true },
  { pattern = "(?<skin>partial paralysis of the entire body)",                                                                          severity = 6, internal = true,  scar = false },
  { pattern = "(?<skin>numbness in your arms and legs)",                                                                                severity = 6, internal = true,  scar = true },
  -- devastating / very devastating (severity 7)
  { pattern = "(?<head>a crushed skull with horrendous wounds)",                                                                        severity = 7, internal = false, scar = false },
  { pattern = "a mangled and malformed (?<part>head)",                                                                                  severity = 7, internal = false, scar = true },
  { pattern = "a ghastly bloated (?<part>head) with bleeding from the ears",                                                            severity = 7, internal = true,  scar = false },
  { pattern = "a confused look with sporadic twitching of the fore(?<part>head)",                                                       severity = 7, internal = true,  scar = true },
  { pattern = "a bruised,* swollen and shattered " .. M.WOUND_BODY_PART_REGEX,                                                         severity = 7, internal = false, scar = false },
  { pattern = "a painfully mangled and malformed " .. M.WOUND_BODY_PART_REGEX .. " in a shattered eye socket",                          severity = 7, internal = false, scar = true },
  { pattern = "a severely swollen,* bruised and blind " .. M.WOUND_BODY_PART_REGEX,                                                    severity = 7, internal = true,  scar = false },
  { pattern = "severely scarred,* mangled and malformed " .. M.WOUND_BODY_PART_REGEX,                                                  severity = 7, internal = false, scar = true },
  { pattern = "a completely clouded " .. M.WOUND_BODY_PART_REGEX,                                                                       severity = 7, internal = true,  scar = true },
  { pattern = "a shattered " .. M.WOUND_BODY_PART_REGEX .. " with gaping wounds",                                                      severity = 7, internal = false, scar = false },
  { pattern = "shattered (?<part>chest) area with gaping wounds",                                                                       severity = 7, internal = false, scar = false },
  { pattern = "a severely swollen and deeply bruised " .. M.WOUND_BODY_PART_REGEX .. " with bones protruding out from the skin",        severity = 7, internal = true,  scar = false },
  { pattern = "a severely swollen and deeply bruised " .. M.WOUND_BODY_PART_REGEX .. " with ribs or vertebrae protruding out from the skin", severity = 7, internal = true,  scar = false },
  { pattern = "a severely paralyzed " .. M.WOUND_BODY_PART_REGEX,                                                                      severity = 7, internal = true,  scar = true },
  { pattern = "a severely painful " .. M.WOUND_BODY_PART_REGEX .. " with significant problems moving",                                 severity = 7, internal = true,  scar = true },
  { pattern = "a severely painful (?<part>chest) area with significant problems breathing",                                             severity = 7, internal = true,  scar = true },
  { pattern = M.WOUND_BODY_PART_REGEX .. " deeply gouged with gaping wounds",                                                          severity = 7, internal = false, scar = false },
  { pattern = "a severely bloated and discolored " .. M.WOUND_BODY_PART_REGEX .. " with strange round lumps under the skin",            severity = 7, internal = true,  scar = false },
  { pattern = "(?<abdomen>a severely yellow pallor and a look of starvation)",                                                          severity = 7, internal = true,  scar = true },
  { pattern = "boils and sores around the (?<part>skin)",                                                                               severity = 7, internal = false, scar = false },
  { pattern = "severely stiff and shriveled (?<part>skin) that seems to be peeling off the body",                                       severity = 7, internal = false, scar = true },
  { pattern = "(?<skin>severe paralysis of the entire body)",                                                                           severity = 7, internal = true,  scar = false },
  { pattern = "(?<skin>general numbness all over)",                                                                                     severity = 7, internal = true,  scar = true },
  -- useless (severity 8)
  { pattern = "pulpy stump for a (?<part>head)",                                                                                        severity = 8, internal = false, scar = false },
  { pattern = "a stump for a (?<part>head)",                                                                                            severity = 8, internal = false, scar = true },
  { pattern = "an ugly stump for a " .. M.WOUND_BODY_PART_REGEX,                                                                       severity = 8, internal = false, scar = false },
  { pattern = "a grotesquely bloated (?<part>head) with bleeding from the eyes and ears",                                               severity = 8, internal = true,  scar = false },
  { pattern = "(?<head>a blank stare)",                                                                                                 severity = 8, internal = true,  scar = true },
  { pattern = "a pulpy cavity for a " .. M.WOUND_BODY_PART_REGEX,                                                                      severity = 8, internal = false, scar = false },
  { pattern = "an empty " .. M.WOUND_BODY_PART_REGEX .. " socket overgrown with bits of odd shaped flesh",                              severity = 8, internal = false, scar = true },
  { pattern = "a severely swollen,* bruised and blind " .. M.WOUND_BODY_PART_REGEX,                                                    severity = 8, internal = true,  scar = false },
  { pattern = "a blind " .. M.WOUND_BODY_PART_REGEX,                                                                                   severity = 8, internal = true,  scar = true },
  { pattern = "a completely useless " .. M.WOUND_BODY_PART_REGEX .. " with nearly all flesh and bone torn away",                        severity = 8, internal = false, scar = false },
  { pattern = "a completely destroyed " .. M.WOUND_BODY_PART_REGEX .. " with nearly all flesh and bone torn away revealing a gaping hole", severity = 8, internal = false, scar = false },
  { pattern = "an ugly flesh stump for a " .. M.WOUND_BODY_PART_REGEX,                                                                 severity = 8, internal = false, scar = true },
  { pattern = "an ugly flesh stump for a " .. M.WOUND_BODY_PART_REGEX .. " with little left to support the head",                      severity = 8, internal = false, scar = true },
  { pattern = "a severely swollen and shattered " .. M.WOUND_BODY_PART_REGEX .. " which appears completely useless",                    severity = 8, internal = true,  scar = false },
  { pattern = "a severely swollen and shattered " .. M.WOUND_BODY_PART_REGEX .. " which appears useless to hold up the head",           severity = 8, internal = true,  scar = false },
  { pattern = "a completely paralyzed " .. M.WOUND_BODY_PART_REGEX,                                                                    severity = 8, internal = true,  scar = true },
  { pattern = "a mostly non-existent " .. M.WOUND_BODY_PART_REGEX .. " filled with ugly chunks of scarred flesh",                      severity = 8, internal = false, scar = true },
  { pattern = "a severely swollen (?<part>chest) area with a shattered rib cage",                                                       severity = 8, internal = true,  scar = false },
  { pattern = "an extremely painful " .. M.WOUND_BODY_PART_REGEX .. " while gasping for breath in short shallow bursts",                severity = 8, internal = true,  scar = true },
  { pattern = "a severely bloated and discolored " .. M.WOUND_BODY_PART_REGEX .. " which appears oddly rearranged",                     severity = 8, internal = true,  scar = false },
  { pattern = "(?<abdomen>a death pallor and extreme loss of weight)",                                                                  severity = 8, internal = true,  scar = true },
  { pattern = "a severely swollen " .. M.WOUND_BODY_PART_REGEX .. " with a shattered spinal cord",                                     severity = 8, internal = true,  scar = false },
  { pattern = "an extremely painful and bizarrely twisted " .. M.WOUND_BODY_PART_REGEX .. " making it nearly impossible to move",       severity = 8, internal = true,  scar = true },
  { pattern = "open and bleeding sores all over the (?<part>skin)",                                                                     severity = 8, internal = false, scar = false },
  { pattern = "severe (?<part>skin) loss exposing bone and internal organs",                                                            severity = 8, internal = false, scar = true },
  { pattern = "(?<skin>complete paralysis of the entire body)",                                                                         severity = 8, internal = true,  scar = false },
  { pattern = "(?<skin>general numbness all over and have difficulty thinking)",                                                        severity = 8, internal = true,  scar = true },
}

--- Tend success patterns.
M.TEND_SUCCESS = {
  "You work carefully at tending",
  "You work carefully at binding",
  "That area has already been tended to",
  "That area is not bleeding",
}

--- Tend failure patterns.
M.TEND_FAILURE = {
  "You fumble",
  "too injured for you to do that",
  "TEND allows for the tending of wounds",
  "^You must have a hand free",
}

--- Tend dislodge patterns.
M.TEND_DISLODGE = {
  "^You \\w+ remove (?:a|the|some) .* from",
  "^As you reach for the clay fragment",
}

-------------------------------------------------------------------------------
-- Wound data class
-------------------------------------------------------------------------------

--- Create a new Wound record.
-- @param opts table { body_part, severity, bleeding_rate, is_internal, is_scar, is_parasite, is_lodged_item }
-- @return table Wound object
function M.Wound(opts)
  opts = opts or {}
  return {
    body_part     = opts.body_part and opts.body_part:lower() or nil,
    severity      = opts.severity,
    bleeding_rate = opts.bleeding_rate and opts.bleeding_rate:lower() or nil,
    is_internal   = opts.is_internal or false,
    is_scar       = opts.is_scar or false,
    is_parasite   = opts.is_parasite or false,
    is_lodged_item = opts.is_lodged_item or false,

    bleeding = function(self)
      return self.bleeding_rate ~= nil
        and self.bleeding_rate ~= ""
        and self.bleeding_rate ~= "(tended)"
    end,

    tendable = function(self)
      if self.is_parasite then return true end
      if self.is_lodged_item then return true end
      if self.body_part and self.body_part:find("skin") then return false end
      if not self:bleeding() then return false end
      if self.bleeding_rate and Regex.test("tended|clotted", self.bleeding_rate) then
        return false
      end
      return M.skilled_to_tend_wound(self.bleeding_rate, self.is_internal)
    end,

    internal = function(self) return self.is_internal end,
    scar = function(self) return self.is_scar end,
    parasite = function(self) return self.is_parasite end,
    lodged_item = function(self) return self.is_lodged_item end,
    location = function(self) return self.is_internal and "internal" or "external" end,
    wound_type = function(self) return self.is_scar and "scar" or "wound" end,
  }
end

-------------------------------------------------------------------------------
-- HealthResult data class
-------------------------------------------------------------------------------

--- Create a new HealthResult record.
-- @param opts table { wounds, bleeders, parasites, lodged, poisoned, diseased, score, dead }
-- @return table HealthResult
function M.HealthResult(opts)
  opts = opts or {}
  return {
    wounds    = opts.wounds or {},
    bleeders  = opts.bleeders or {},
    parasites = opts.parasites or {},
    lodged    = opts.lodged or {},
    poisoned  = opts.poisoned or false,
    diseased  = opts.diseased or false,
    score     = opts.score or 0,
    dead      = opts.dead or false,
    vitality  = opts.vitality or 100,

    injured = function(self)
      return self.score > 0
    end,

    bleeding = function(self)
      for _, wounds in pairs(self.bleeders) do
        for _, w in ipairs(wounds) do
          if w:bleeding() then return true end
        end
      end
      return false
    end,

    has_tendable_bleeders = function(self)
      for _, wounds in pairs(self.bleeders) do
        for _, w in ipairs(wounds) do
          if w:tendable() then return true end
        end
      end
      return false
    end,
  }
end

-------------------------------------------------------------------------------
-- Internal helpers
-------------------------------------------------------------------------------

--- Extract body part from regex captures, handling named groups.
-- Named captures like (?<skin>...) mean body_part IS "skin".
-- Named captures like (?<head>...) mean body_part IS "head".
-- Named captures like (?<abdomen>...) mean body_part IS "abdomen".
-- Named capture (?<part>...) means use the captured text as body_part.
-- @param caps table Regex captures table
-- @return string|nil body part name
local function extract_body_part(caps)
  if not caps then return nil end
  -- Check for specific named body part overrides
  if caps.skin then return "skin" end
  if caps.head then return "head" end
  if caps.abdomen then return "abdomen" end
  -- Use the generic 'part' capture
  if caps.part then return caps.part end
  return nil
end

-------------------------------------------------------------------------------
-- Health checking
-------------------------------------------------------------------------------

--- Check health using the HEALTH command.
-- @return HealthResult
function M.check_health()
  put("health")
  local lines = {}
  local timeout_at = os.time() + 15  -- Increased from 5s; Lich5 has no hard timeout
  local collecting = false
  while os.time() < timeout_at do
    local line = get_noblock and get_noblock() or get()
    if line then
      if Regex.test("^Your body feels", line) then
        collecting = true
      end
      if collecting then
        lines[#lines + 1] = DRC.strip_xml(line)
      end
      if line:find("<prompt") then break end
    else
      pause(0.1)
    end
  end
  if #lines == 0 then
    echo("DRCH: Failed to capture HEALTH output (timeout)")
  end
  return M.parse_health_lines(lines)
end

--- Parse stripped HEALTH command output into a HealthResult.
-- @param health_lines table Array of plain text lines
-- @return HealthResult
function M.parse_health_lines(health_lines)
  local poisoned = false
  local diseased = false
  local wounds = {}    -- keyed by severity
  local bleeders = {}
  local parasites = {}
  local lodged = {}

  -- Build combined parasites regex
  local parasites_pattern = table.concat(M.PARASITES_REGEX, "|")

  local wounds_line = nil
  local parasites_line = nil
  local lodged_line = nil

  for _, line in ipairs(health_lines) do
    -- Skip non-diagnostic lines
    if Regex.test("^Your body feels\\b|^Your spirit feels\\b|^You are .*fatigued|^You feel fully rested", line) then
      -- skip
    -- Disease
    elseif Regex.test("^You have a dormant infection|^Your wounds are infected|^Your body is covered in open oozing sores", line) then
      diseased = true
    -- Poison
    elseif Regex.test("^You have .* poison(?:ed)?|^You feel somewhat tired and seem to be having trouble breathing", line) then
      poisoned = true
    -- Parasites
    elseif Regex.test(parasites_pattern, line) or Regex.test("^You have a .* on your", line) then
      parasites_line = line
    -- Lodged items
    elseif Regex.test("lodged .* in(?:to)? your", line) then
      lodged_line = line
    -- Wounds line: "You have ..." but NOT "no significant injuries", NOT lodged, NOT infection, NOT poison, NOT parasites
    elseif Regex.test("^You have ", line)
      and not Regex.test("no significant injuries", line)
      and not Regex.test("lodged .* in(?:to)? your", line)
      and not Regex.test("infection", line)
      and not Regex.test("poison", line)
      and not Regex.test(parasites_pattern, line) then
      wounds_line = line
    end
  end

  -- Parse wound descriptions from the "You have ..." line
  if wounds_line then
    -- Remove comma separators inside compound wound descriptions
    local cleaned = Regex.new(M.WOUND_COMMA_SEPARATOR):replace_all(wounds_line, "")
    -- Strip "You have " prefix and trailing period
    cleaned = Regex.new("^You have\\s+"):replace(cleaned, "")
    cleaned = Regex.new("\\.$"):replace(cleaned, "")
    -- Split on commas
    local fragments = Regex.split(",", cleaned)
    for _, frag in ipairs(fragments) do
      frag = frag:match("^%s*(.-)%s*$") -- trim whitespace
      if frag ~= "" then
        for _, entry in ipairs(M.WOUND_SEVERITY_REGEX_MAP) do
          local re = Regex.new(entry.pattern)
          local caps = re:captures(frag)
          if caps then
            local body_part = extract_body_part(caps)
            if not wounds[entry.severity] then wounds[entry.severity] = {} end
            wounds[entry.severity][#wounds[entry.severity] + 1] = M.Wound({
              body_part = body_part,
              severity = entry.severity,
              is_internal = entry.internal,
              is_scar = entry.scar,
            })
            break
          end
        end
      end
    end
  end

  -- Parse bleeder table lines
  local bleeder_re = Regex.new(M.BLEEDER_LINE_REGEX)
  local in_bleeders = false
  for _, line in ipairs(health_lines) do
    if bleeder_re:captures(line) then
      in_bleeders = true
      local bp_re = Regex.new(M.WOUND_BODY_PART_REGEX)
      local bp_caps = bp_re:captures(line)
      local body_part = extract_body_part(bp_caps)
      if body_part then
        body_part = body_part:gsub("l%.", "left"):gsub("r%.", "right")
      end
      -- Extract bleed rate: everything after the body part keyword
      local rate_caps = Regex.new("(?:head|eye|neck|chest|abdomen|back|arm|hand|leg|tail|skin)\\s+(?<rate>.+)"):captures(line)
      if rate_caps and rate_caps.rate then
        local bleed_rate = rate_caps.rate:match("^%s*(.-)%s*$") -- trim
        local bleed_info = M.BLEED_RATE_TO_SEVERITY[bleed_rate]
        if bleed_info then
          if not bleeders[bleed_info.severity] then bleeders[bleed_info.severity] = {} end
          bleeders[bleed_info.severity][#bleeders[bleed_info.severity] + 1] = M.Wound({
            body_part = body_part,
            severity = bleed_info.severity,
            bleeding_rate = bleed_rate,
            is_internal = line:find("^inside") ~= nil,
          })
        end
      end
    elseif in_bleeders then
      break -- end of bleeder table
    end
  end

  -- Parse parasites
  if parasites_line then
    local cleaned = Regex.new("^You have\\s+"):replace(parasites_line, "")
    cleaned = Regex.new("\\.$"):replace(cleaned, "")
    local frags = Regex.split(",", cleaned)
    for _, frag in ipairs(frags) do
      frag = frag:match("^%s*(.-)%s*$")
      local bp_caps = Regex.new(M.PARASITE_BODY_PART_REGEX):captures(frag)
      local bp = extract_body_part(bp_caps)
      if not parasites[1] then parasites[1] = {} end
      parasites[1][#parasites[1] + 1] = M.Wound({ body_part = bp, severity = 1, is_parasite = true })
    end
  end

  -- Parse lodged items
  if lodged_line then
    local cleaned = Regex.new("^You have\\s+"):replace(lodged_line, "")
    cleaned = Regex.new("\\.$"):replace(cleaned, "")
    local frags = Regex.split(",", cleaned)
    for _, frag in ipairs(frags) do
      frag = frag:match("^%s*(.-)%s*$")
      local bp_caps = Regex.new(M.LODGED_BODY_PART_REGEX):captures(frag)
      local bp = extract_body_part(bp_caps)
      -- Determine lodged depth
      local depth_caps = Regex.new("lodged\\s+(?<depth>.+?)\\s+in(?:to)? your"):captures(frag)
      local sev = 1
      if depth_caps and depth_caps.depth then
        sev = M.LODGED_SEVERITY[depth_caps.depth] or 1
      end
      if not lodged[sev] then lodged[sev] = {} end
      lodged[sev][#lodged[sev] + 1] = M.Wound({ body_part = bp, severity = sev, is_lodged_item = true })
    end
  end

  local score = M.calculate_score(wounds)
  return M.HealthResult({
    wounds    = wounds,
    bleeders  = bleeders,
    parasites = parasites,
    lodged    = lodged,
    poisoned  = poisoned,
    diseased  = diseased,
    score     = score,
  })
end

--- Parse PERCEIVE HEALTH / TOUCH output into a HealthResult.
-- Different format from HEALTH — shows perceived wound severity and vitality.
-- @param lines table Array of stripped text lines
-- @return HealthResult
function M.parse_perceived_health_lines(lines)
  local wounds = {}
  local parasites = {}
  local poisoned = false
  local diseased = false
  local dead = false
  local vitality = 100
  local wound_body_part = nil

  -- Build combined parasites regex
  local parasites_pattern = table.concat(M.PARASITES_REGEX, "|")

  local perceive_re = Regex.new(M.PERCEIVE_HEALTH_SEVERITY_REGEX)
  local dead_re = Regex.new("^(?:He|She) is dead")
  local poisons_re = Regex.new("has a .* poison|having trouble breathing|Cyanide poison")
  local diseases_re = Regex.new("wounds are (?:badly )?infected|has a dormant infection|(?:body|skin) is covered (?:in|with) open oozing sores")

  for _, line in ipairs(lines) do
    line = line:match("^%s*(.-)%s*$") -- trim

    -- Dead check (third-person: "He is dead" / "She is dead")
    if dead_re:captures(line) then
      dead = true
    end

    -- Vitality parsing
    local vit = line:match("has (%d+)%% vitality remaining")
    if vit then
      vitality = tonumber(vit)
    end

    -- Disease
    if diseases_re:captures(line) then
      diseased = true
    end

    -- Poison
    if poisons_re:captures(line) then
      poisoned = true
    end

    -- Parasites (using PARASITES_REGEX patterns)
    if Regex.test(parasites_pattern, line) then
      local bp_caps = Regex.new("on (?:his|her|your) (?<part>[\\w\\s]*)"):captures(line)
      local bp = bp_caps and bp_caps.part or nil
      if not parasites[1] then parasites[1] = {} end
      parasites[1][#parasites[1] + 1] = M.Wound({ body_part = bp, severity = 1, is_parasite = true })
    end

    -- Wound body part header: "Wounds to the <part>:"
    local part_header = line:match("^Wounds to the (.+):")
    if part_header then
      wound_body_part = part_header
    end

    -- Perceived wound severity lines: "Fresh External: ... -- severity"
    local caps = perceive_re:captures(line)
    if caps and wound_body_part then
      local severity = M.WOUND_SEVERITY[caps.severity]
      if severity then
        if not wounds[severity] then wounds[severity] = {} end
        wounds[severity][#wounds[severity] + 1] = M.Wound({
          body_part = wound_body_part,
          severity = severity,
          is_internal = caps.location == "Internal",
          is_scar = caps.freshness == "Scars",
        })
      end
    end
  end

  -- Remove any string-keyed body part header entries (they were tracking state)
  local clean_wounds = {}
  for k, v in pairs(wounds) do
    if type(k) == "number" then
      clean_wounds[k] = v
    end
  end

  local score = M.calculate_score(clean_wounds)

  return M.HealthResult({
    wounds = clean_wounds,
    bleeders = {},
    parasites = parasites,
    lodged = {},
    poisoned = poisoned,
    diseased = diseased,
    score = score,
    dead = dead,
    vitality = vitality,
  })
end

--- Perceive own health (empath ability).
-- @return HealthResult|nil
function M.perceive_health()
  if DRStats and DRStats.empath and not DRStats.empath() then
    echo("DRCH: perceive_health requires empath")
    return nil
  end
  local result = DRC.bput("perceive health self",
    "injuries include", "feel only an aching emptiness",
    "You don't have the ability to do that")
  if not result or result:find("don't have the ability") then return nil end
  if result:find("aching emptiness") then
    if waitrt then waitrt() end
    return M.check_health()
  end
  -- Collect perceived health output (Lich5 uses issue_command which captures all lines;
  -- reget is a best-effort buffer that may truncate for heavily-wounded characters)
  local output = reget(50)
  local perceived = M.parse_perceived_health_lines(output)
  local health = M.check_health()
  if waitrt then waitrt() end
  return M.HealthResult({
    wounds = perceived.wounds,
    bleeders = health.bleeders,
    parasites = health.parasites,
    lodged = health.lodged,
    poisoned = health.poisoned,
    diseased = health.diseased,
    score = perceived.score,
    dead = perceived.dead,
    vitality = perceived.vitality,
  })
end

--- Perceive another's health via TOUCH (empath ability).
-- @param target string Character name
-- @return HealthResult|nil
function M.perceive_health_other(target)
  if DRStats and DRStats.empath and not DRStats.empath() then
    echo("DRCH: perceive_health_other requires empath")
    return nil
  end
  local result = DRC.bput("touch " .. target,
    "between you and", "Touch what",
    "feels cold",
    "avoids your touch", "You quickly recoil")
  if not result or result:find("Touch what") or result:find("cold")
    or result:find("avoids") or result:find("recoil") then
    echo("DRCH: Unable to perceive health of " .. target)
    return nil
  end
  -- Extract canonical target name from link confirmation
  local canonical = result:match("between you and (%w+)")
  if canonical then target = canonical end
  -- Collect perceived health output (Lich5 uses issue_command which captures all lines;
  -- reget is a best-effort buffer that may truncate for heavily-wounded characters)
  local output = reget(50)
  return M.parse_perceived_health_lines(output)
end

--- Check if character has tendable bleeders.
-- @return boolean
function M.has_tendable_bleeders()
  return M.check_health():has_tendable_bleeders()
end

-------------------------------------------------------------------------------
-- Tending
-------------------------------------------------------------------------------

--- Bind (tend) a wound on a body part.
-- @param body_part string Body part to tend
-- @param person string|nil "my" or a player name (default "my")
-- @return boolean true if successfully tended
function M.bind_wound(body_part, person)
  person = person or "my"
  local all = {}
  for _, p in ipairs(M.TEND_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.TEND_FAILURE) do all[#all + 1] = p end
  for _, p in ipairs(M.TEND_DISLODGE) do all[#all + 1] = p end

  local result = DRC.bput("tend " .. person .. " " .. body_part, unpack(all))
  if waitrt then waitrt() end

  -- Dislodge: dispose of the item and re-tend
  for _, p in ipairs(M.TEND_DISLODGE) do
    if Regex.test(p, result) then
      local dislodge_caps = Regex.new("^You \\w+ remove (?:a|the|some) (?<item>.+) from"):captures(result)
      if dislodge_caps and dislodge_caps.item and DRCI and DRCI.dispose_trash then
        local worn_tc = UserVars and UserVars.worn_trashcan or nil
        local worn_verb = UserVars and UserVars.worn_trashcan_verb or nil
        DRCI.dispose_trash(dislodge_caps.item, worn_tc, worn_verb)
      end
      return M.bind_wound(body_part, person)
    end
  end

  -- Check failure
  for _, p in ipairs(M.TEND_FAILURE) do
    if Regex.test(p, result) then return false end
  end

  return true
end

--- Unwrap bandages from a body part.
-- @param body_part string
-- @param person string|nil "my" or player name
function M.unwrap_wound(body_part, person)
  person = person or "my"
  DRC.bput("unwrap " .. person .. " " .. body_part,
    "You unwrap .* bandages", "That area is not tended",
    "You may undo the affects")
  if waitrt then waitrt() end
end

--- Check if the character has enough First Aid skill to tend a bleed rate.
-- @param bleed_rate string Bleed rate text
-- @param internal boolean Whether it's an internal bleeder
-- @return boolean
function M.skilled_to_tend_wound(bleed_rate, internal)
  if not bleed_rate then return false end
  local info = M.BLEED_RATE_TO_SEVERITY[bleed_rate]
  if not info then return false end

  local skill_key = internal and "skill_to_tend_internal" or "skill_to_tend"
  local min_skill = info[skill_key]
  if not min_skill then return false end

  if DRSkill and DRSkill.getrank then
    return DRSkill.getrank("First Aid") >= min_skill
  end
  return false
end

--- Compute a weighted summary score from wounds by severity.
-- Higher severity wounds contribute quadratically more.
-- @param wounds_by_severity table { severity => { Wound, ... } }
-- @return number Score
function M.calculate_score(wounds_by_severity)
  local score = 0
  for severity, wound_list in pairs(wounds_by_severity) do
    score = score + (severity * severity) * #wound_list
  end
  return score
end

return M
