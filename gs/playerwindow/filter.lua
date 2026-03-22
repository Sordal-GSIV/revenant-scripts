-- Downstream spam/animal/flare/combat filter and player movement tracker.
-- All pattern regexes are pre-compiled at require time for performance.

local state = require("state")

local M = {}

-- ============================================================
-- BLOCKED ANIMAL NOUNS (set for O(1) lookup)
-- ============================================================
local BLOCKED_NOUNS = {}
for _, n in ipairs({
    "albatross", "badger", "bandicoot", "banishara", "bat", "baza", "bear", "beetle",
    "bloodhound", "boar", "boarrat", "bobcat", "bush", "bushwag", "buzzard",
    "caiverine", "caligos", "caracara", "caraval", "canid", "capybara", "castorides",
    "cat", "catamount", "cheetah", "chameleon", "cockatiel", "colocolo", "condor",
    "cougar", "coydog", "coyote", "crow", "culpeo", "curhound", "curwolf", "cygnet",
    "deerhound", "dhole", "dog", "dobrem", "elf-owl", "eagle", "falcon", "fennec",
    "ferret", "fishing", "fox", "foxhound", "frog", "fossa", "giraffe", "goshawk",
    "graiphel", "groundhog", "gryfalcon", "gannet", "hare", "harpy", "harrier",
    "hedgehog", "heron", "howler", "hound", "hawk", "hawk-eagle", "hispid",
    "hummingbird", "hyena", "iguana", "jackal", "jabady", "jaguar", "jaguarundi",
    "jungle", "karet", "kingfisher", "kite", "kodkod", "ledisa", "lemur", "leopard",
    "lion", "lizard", "loper", "lugger", "lynx", "macaw", "magpie", "maned", "margay",
    "marmot", "marmoset", "mastiff", "melomys", "merlin", "mink", "mongoose", "monkey",
    "mole", "mouse", "mudcat", "muskrat", "muzzlerat", "narmo", "nutria", "ocicat",
    "ocelot", "oncilla", "opossum", "osprey", "owl", "panther", "parakeet", "parrot",
    "passo", "pelican", "penguin", "peregrine", "petrel", "phantom", "phantasma",
    "pigeonhawk", "pitohui", "porcupine", "pterosaur", "puppet", "puma", "puppy",
    "pygmy-parrot", "rabbit", "raccoon", "raptor", "rasper", "rat", "raven", "redtail",
    "ringtail", "rockrat", "rodent", "rowl", "sandrat", "samoyed", "saker",
    "screech-owl", "seal", "seagull", "seahawk", "sealion", "seal-pup", "serpent",
    "serval", "shrika", "shrike", "skua", "sloth", "snowcat", "snow-owl",
    "sparrowhawk", "spirit", "spider", "squirrel", "stratis", "swift", "tanuki",
    "tamarin", "tarsier", "tigrina", "tiger", "toad", "tothis", "toucan", "trakel",
    "tunnelcat", "turtle", "vole", "vulture", "warthog", "weasel", "whale",
    "whiskrat", "wildcat", "wolf", "wolfhound", "wolverine", "woodchuck", "woodpecker",
    "woodshrew", "wombat", "wyrdling", "viper", "mandrake", "lamb", "scarab",
    "teadragon", "kitten",
}) do
    BLOCKED_NOUNS[n] = true
end

-- ============================================================
-- PRE-COMPILED REGEX PATTERNS
-- ============================================================

-- Death messages
local DEATH_RE = Regex.new(
    "(?i)collapses to the ground, dead\\.|succumbs to death\\.|form goes still\\.|surrendering to death\\." ..
    "|life goes out of|as the power animating| collapses, life|, lifeless\\.|animation departs?" ..
    "|collapses into a puddle|talons and feathers\\.|many eyes close\\.|death claims" ..
    "|ground, still\\.|goes still in death\\.|ground, unmoving\\." ..
    "|begins (?:to lose|losing) cohesion\\.|at last going still\\.|sags, lifeless," ..
    "|becoming completely still\\.|, then goes still\\.|the ground, motionless\\." ..
    "|side and dies\\.|and goes still,|before expiring\\.|dissolve from the bottom up!" ..
    "|the life fading from|movement completely ceases\\.|and collapses into the water\\." ..
    "|and into nothingness!|a silhouette onto the ground beneath")

-- Decay messages (after loot/search)
local DECAY_RE = Regex.new(
    "(?i)goes still in death|immense form decays away into a mound of" ..
    "|crumbles and decays away\\.|sublimates rapidly into luminous mist that swiftly disperses into the air" ..
    "|seep into the ground and vanish" ..
    "|collapsing into a lightless sphere that erupts soundlessly, bathing the area in momentary darkness" ..
    "|falls away to reveal only crumbling bones|quickly decays away" ..
    "|flesh crumbles to reveal the corpse of|Traceries of mold race to reclaim" ..
    "|Rivulets of golden light blush beneath the skin of|Shadows coil around the broken form of" ..
    "|body rots away, leaving only a small stain on the ground" ..
    "|decays away, leaving behind little more than dust|finally stops twitching and decays away" ..
    "|body, leaving little behind\\.|corpse succumbs to rot|Creeping decay races across" ..
    "|collapses into a pile of tangled wool and huge bones" ..
    "|remnants rapidly dissolving into the air\\.|dissolve away, leaving nothing behind\\." ..
    "|decays into compost\\.|quickly scattering and dissolving out of sight\\." ..
    "|body crumbles until only a pile of rubble marks|then fades from view like a dissipating phantom" ..
    "|decays into a pile|bony form as fingers of rust race to consume" ..
    "|collapses into blanched powder and blows away\\.|dance before drifting away\\." ..
    "|leaving little but brittle bones\\.|breaking into fine black powder\\." ..
    "|yellowing bones and stinking effluvia\\.|the remaining folds of skin\\." ..
    "|into shards of inert ice\\.|ruined meat and patchy bristles\\." ..
    "|and soon nothing more than a grim| pile of reddish-black grit\\." ..
    "|surrenders to decay\\.|erupts into a cloud of dust!" ..
    "|fades into nothingness,|body crumbles|, leaving nothing behind\\.|leaves no corpse behind\\.")

-- Spell falloff (hardcoded common patterns; Spell.downmsgs not exposed in Revenant)
local SPELL_FALLOFF_RE = Regex.new(
    "(?i)The constricting bands surrounding .* shatter into nothingness\\." ..
    "|ground beneath .* suddenly calms\\.?" ..
    "|The guiding force leaves .*\\." ..
    "|.* seems to lose an aura of confidence\\." ..
    "|illuminated mantle protecting .* begins to falter.*fades away\\.?")

-- Critical rank line (fallback; CritRanks module not available in Revenant)
local CRIT_RANK_RE = Regex.new(
    "(?i)^(?:Minor|Light|Moderate|Heavy|Hard|Massive|Severe)\\b.*\\b(?:to|strike to|blow to|hit to)\\b")

-- Certain "You" lines to suppress
local CERTAIN_YOU_RE = Regex.new(
    "(?i)You are blinded momentarily by a flash of intense light\\." ..
    "|You notice .* moving stealthily" ..
    "|You hear someone reciting a series of mystical phrases" ..
    "|You hear someone calling upon the powers of the elements" ..
    "|You hear someone chanting an arcane phrase" ..
    "|You feel more refreshed" ..
    "|You hear a distant song that lifts your spirits and touches memories of revelry long past" ..
    "|As your sight returns, you realize" ..
    "|You see a blur out of the corner of your eye, and .* suddenly appears\\." ..
    "|You hear very soft footsteps\\." ..
    "|You hear someone deeply intoning a sonorous mantra" ..
    "|You see a golden ripple of light out of the corner of your eye that is reminiscent of a forge" ..
    "|You notice quicksilver seeping up from a nearby crack in the ground," ..
    "|You hear someone preparing a spell nearby" ..
    "|^You hear a slight crackling sound as .* slides .* into .*\\." ..
    "|Rising on the air, the sound of horses' clip-clopping hooves greets your ears, and within seconds you" ..
    "|^A veritable horde of butterflies descends on the area from every direction," ..
    "|^Pale, swirling mist begins to billow out from nothingness before you, and quickly coalesces into a small orb of shifting essence\\." ..
    "|^A large iridescent bubble floats into view and drifts down to the ground," ..
    "|^A greenish pulsing glow builds around" ..
    "|^A whirling bluish-gray mist quickly coalesces nearby" ..
    "|^Shattered pieces of porcelain arrive on an errant breeze and begin to assemble themselves before your very eyes" ..
    "|^You feel .* protection extend to you as an incandescent veil coalesces around you" ..
    "|^You discard the .*? useless equipment\\." ..
    "|^You twinge slightly as your Empathic Link to" ..
    "|^You feel the unnatural surge of necrotic power wane away" ..
    "|^You are now in an offensive stance" ..
    "|^You currently have no valid target")

-- Gesture pattern (triggers skip_next_line)
local GESTURE_RE = Regex.new(
    "(?i)<a [^>]+>[^<]+</a> gestures at <a [^>]+>[^<]+</a>\\." ..
    "|<a [^>]+>[^<]+</a> gestures at a" ..
    "|<a [^>]+>[^<]+</a> makes a complex gesture at <a [^>]+>[^<]+</a>\\." ..
    "|(?:gestures\\.|makes a complex gesture\\.|continues to wax\\." ..
    "|skillfully begins to weave another verse into|sings a melody\\." ..
    "|gestures into the air\\.)")

-- Custom spell prep (huge alternation — faithfully ported from original)
local CUSTOM_SPELL_PREP_RE = Regex.new(
    "(?i)rips the ethereal image asunder, the motes coalescing at the tips of" ..
    "|rests a hand on .* chest, eyes closed, as a faint hum slowly builds in the air nearby\\." ..
    "|begins to make sinuous gestures with both hands\\." ..
    "|^Weaving .* hands in a complicated pattern," ..
    "|.* murmurs words of power into the air, summoning the elements to do .* bidding\\." ..
    "|.* intones a mystical orison, petitioning for the aid of .* patron\\." ..
    "|.* murmurs soft words into the air, the liquid syllables summoning the spirits to .* aid\\." ..
    "|.* traces a burning rune into the air, melding the spiritual and elemental powers by sheer force of will\\." ..
    "|.* whispers quietly into the wind, summoning the forces of nature to .* call\\." ..
    "|.* raises .* voice in rhythmic song, commanding the aid of the elements\\." ..
    "|.* lifts .* voice in a rallying cry, calling confidently on the power of .* patron for aid\\." ..
    "|.* weaves .* hands through the air, streamers of elemental mana twisting between .* fingers\\." ..
    "|.* raises .* clasped hands, fervently calling on the guidance of .* patron\\." ..
    "|.* outlines a luminous rune in the air, summoning the spirits to .* aid\\." ..
    "|.* scribes a hazy, dark sigil into the air, fusing elemental and spiritual power\\." ..
    "|.* casts .* voice into the air, causing the spirits to swirl around (?:him|her|them) with a sound like rustling leaves\\." ..
    "|.* lifts .* voice in song, skillfully twining elemental mana into .* harmony\\." ..
    "|.* traces .* patron's holy symbol in the air, using it to focus .* invocation\\." ..
    "|.* quickly intones a battle chant, imploring .* patron to lend (?:him|her|them) aid\\." ..
    "|.* melds a climactic chord into .* melody, .* voice rising in a crescendo\\." ..
    "|.* murmurs a twisting phrase, commanding both the elements and spirits together\\." ..
    "|.* invokes a short blessing, .* hands clasped in prayer\\." ..
    "|.* chants a short phrase, embers leaping from .* fingertips, as .* clenches .* hand into a smoke-shrouded fist\\." ..
    "|.* intones a mystical phrase, .* words flowing in a burst of speed, as .* hands move rapidly\\." ..
    "|.* chants a reverent prayer, imploring .* patron for aid in restoring the fallen to life\\." ..
    "|.* whispers a mystical phrase, as a nebulous haze shimmers into view around .* hands, casting them in murky shadows\\." ..
    "|.* whispers a mystical phrase, as pearlescent energy builds around .* hands, casting them in an opalescent silhouette\\." ..
    "|.* utters a sharp phrase, tiny thorns rippling across .* arms in a wave that moves toward .* hands\\." ..
    "|.* tucks .* hand behind .* back for a moment before moving it back to .* side\\." ..
    "|.* shower of sparks cascade from .* hands as .* intones a few words\\." ..
    "|.* gallimaufry of sounds pours from .* mouth as .* stumbles over some words\\." ..
    "|.* utters a plaintive plea to .*\\." ..
    "|.* lips move soundlessly\\." ..
    "|.* whispers a short prayer to .* followed by a soft incantation\\." ..
    "|.* fingertips momentarily glow a deep sanguine red as .* murmurs a few words\\." ..
    "|Looking bored, .* drones out a few words in a monotone\\." ..
    "|.* steeples .* fingers together and touches .* forehead to .* thumbs as .* prepares a spell\\." ..
    "|.* makes small, intricately twisting movements with .* hands at .* chest before projecting them outward abruptly\\." ..
    "|Inky shadows and twinkling lights commix around .* in a hypnotic eddy\\." ..
    "|.* rasps out a few words as tendrils of white smoke slither from .* mouth\\." ..
    "|Seven phantom tentacles sprout from the base of .* spine, wrapping .* in a binding embrace\\." ..
    "|.* gestures and quietly utters a phrase of magic\\." ..
    "|.* whispers something softly, and a whirlwind of flower petals envelops (?:him|her|them) before fading away into nothingness\\." ..
    "|Crystalline snowflakes drift softly down upon .* as .* says a few words\\." ..
    "|The scent of mournblooms fills the air as .* speaks a few words\\." ..
    "|A loud ticking sound emanates from .* as .* murmurs a short phrase\\." ..
    "|.* invokes the fury of a storm as .* prepares a spell\\." ..
    "|Anguished whispers amplify into a cacophony of sound that nearly drowns out .* attempts to prepare a spell\\." ..
    "|.* sketches a tart symbol and mutters an invocation to an unintelligible arkati followed by cheerful recitation\\." ..
    "|As .* slowly chants, swirls of tea-scented steam twist about .* before fading to nothingness\\." ..
    "|hands over the ground, and a sudden chill fills the air as shadows rise to" ..
    "|chants in an arcane language which causes" ..
    "|face suddenly darkens as a ghostly death mask pinches" ..
    "|calling the forces of nature to aid" ..
    "|A swarm of ethereal crimson butterflies circle around" ..
    "|Polychromatic tentacles wrap about .* as .* chants a magical phrase\\." ..
    "|wrists and condenses into thrice-wrapped coils as" ..
    "|face twisted with pain as if .* very bones are aflame" ..
    "|upturned palms and drift upwards as they build in intensity" ..
    "|traces a series of glowing runes along" ..
    "|whispers a quiet invocation\\." ..
    "|intones a sonorous mantra and shifts" ..
    "|Reciting the mystical phrases of" ..
    "|skin is suffused with a subtle gold glow as" ..
    "|pulses with a white-blue light!" ..
    "|murmurs a brief incantation with a casual gesture\\." ..
    "|A soft, white glow briefly surrounds" ..
    "|A strange cracking noise cuts across" ..
    "|hums an ancient hymnal that causes the shadows to str(?:e|e)tch towards" ..
    "|intones a soft prayer and the patterns, which now dance like eels beneath waves" ..
    "|Calling out to the powers of chaos and life" ..
    "|Mystical phrases fill the air" ..
    "|whispers and a strawberry-hued wisp is summoned, flitting around" ..
    "|murmurs a prayer to the spirits of the" ..
    "|eyes to the heavens as the fading image of Liabo appears behind" ..
    "|quickly growing in size as numerous sinuous misty tentacles reach out from within their untold depths" ..
    "|Someone begins singing|As someone sings|Someone unseen begins singing" ..
    "|eyes in concentration, the runes on" ..
    "|murmurs a prayer to the dead that is an entreaty for aid" ..
    "|renews .* songs|stops singing\\." ..
    "|shaped vortex of air moves|releases upon .* a flurry of abjurations" ..
    "|Suddenly, a small bolt of energy arcs between them" ..
    "|eyes, looking slightly drained\\.|strains, but nothing happens\\." ..
    "|The powerful look leaves|The light blue glow leaves|The very powerful look leaves" ..
    "|The white light leaves|The deep blue glow leaves" ..
    "|an eerie white glow blurring the outline of the bones beneath" ..
    "|Grating out an incomprehensible phrase" ..
    "|asking to be empassioned and have his desires fulfilled\\." ..
    "|fingers weave gossamer threads of energy into a weblike sigil\\." ..
    "|quickly intones a battle chant, imploring" ..
    "|beseeches a reverent phrase while manifesting the elements\\." ..
    "|eyes flare and then emanate an amalgamation of elemental energy" ..
    "|With a sudden burst of enthusiasm, the sparks jump into .*? seems to glow with power\\." ..
    "|A vibrant stream of rainbow colors burst forth, streaming alongside .*? motions before dispersing into an imperceptible mist\\." ..
    "|languidly traces a rune in the air\\." ..
    "|patron as sunlit gold radiance begins to take form, swirling violently around" ..
    "|removes one of the chords from .*? harmony while maintaining the symmetry of those that remain\\." ..
    "|fingers\\.\\.\\. but little else happens\\.|gestures discreetly while murmuring a quiet incantation" ..
    "|stirring fingers through the ephemeral wings on" ..
    "|plucks two illusory strands out of the air and knots them together\\." ..
    "|gestures and utters a phrase of magic\\.|prepares to sing\\." ..
    "|skillfully begins to weave another verse into" ..
    "|sings, a squall of wind briefly swirls about" ..
    "|gestures while calling upon the lesser spirits for aid" ..
    "|A caliginous power manifests around" ..
    "|completes several complex gestures while an incantation tumbles from" ..
    "|intonation carrying a somber but determined quality\\." ..
    "|hums an ancient hymnal that causes the shadows to stretch towards" ..
    "|A salty sea breeze stirs as .* chants an old sailor's ditty" ..
    "|invokes the spirits of the harvest|sings a melody, directing the sound of" ..
    "|hums a nearly inaudible tune\\.|hand through the air, cutting invisible runes\\." ..
    "|skillfully weaves another verse into|hisses a magical phrase at an incomprehensibly rapid pace\\." ..
    "|^Flickers of verdant green light emanate from" ..
    "|whispers arcane incantations, and the air about" ..
    "|eyes glow crimson as a swarm of ethereal crimson-eyed scarabs envelop" ..
    "|invokes the virtues of the stars, swirls of constellations appearing momentarily beneath" ..
    "|^The branches of .* sprout fresh green leaves in harmony with .* magical incantations\\." ..
    "|^The folds of .* float for a moment, drifting in the currents of a phantom wind as .* calls the spirits to his aid\\." ..
    "|^As .* begins .* incantations, the .* encircling .* begin to brighten as the fire lashes out, engulfing" ..
    "|head, reciting a quiet prayer of reverence as divine energy radiates from" ..
    "|^A vereri mirage briefly materializes to embrace" ..
    "|ripples with multihued elemental mana, slowly unfurling into wispy tendrils of colorful light")

-- Effects beginning
local EFFECTS_BEGINNING_RE = Regex.new(
    "(?i)is surrounded by a white light\\.|energy flicker restlessly about" ..
    "|A shimmering aura surrounds|form seems to momentarily waver and blend with the shadows\\." ..
    "|form shifts back from the shadows\\.|With a crackling and splintering sound, a latticework" ..
    "|vines dotted with crimson-tipped thorns wrap eagerly about" ..
    "|carefully recombining the two halves of|body seems to glow with an internal strength\\." ..
    "|Wisps of blue flame crackle like static around|appears considerably more powerful\\." ..
    "|The barrier of thorns surrounding|gains a look of renewed cognition of" ..
    "|assumes a stern, rough countenance, though|A faint blue glow surrounds" ..
    "|As the fragrant haze settles over .*? looks revitalized\\.|blurs before your eyes\\." ..
    "|exhibits a much more regal air, power coursing through|appears to be keenly aware of" ..
    "|A faint .*? haze briefly tints the air about|appearance shimmers briefly\\." ..
    "|A brilliant aura surrounds|stands tall and appears more confident\\." ..
    "|as the violet flames surrounding it gain new life" ..
    "|causing violet flames to spring to life around it|A fiery aura envelops" ..
    "|stops shimmering\\.|The evanescent shield shrouding" ..
    "|Granules of cobalt light coalesce and dance around" ..
    "|Motes of .*? light appear and begin to swirl around" ..
    "|A sphere of snapping and crackling ethereal ripples expands outward from" ..
    "|Bolts of electricity dance restlessly around|The tempest of electricity swirls violently around" ..
    "|The sanguine liquid is visible for only an instant before it sinks into" ..
    "|Strands of translucent mana swirl about .*? in a protective barrier\\." ..
    "|You hear a loud \\*POP\\* come from .*? muscles!" ..
    "|A churning spectral aura suddenly materializes around" ..
    "|appears filled with a confident and fearless composure\\." ..
    "|Dark red droplets seep out of .*? skin and evaporate\\." ..
    "|body suddenly grows darker\\.|stands taller, as if bolstered with a sense of confidence\\." ..
    "|body is surrounded by a dim dancing aura\\." ..
    "|is surrounded by a shimmering field of energy\\.|appears somehow changed\\." ..
    "|is again\\.  Perhaps it was a trick of the light\\." ..
    "|muscles seem to strain for an instant\\.  A sense of loss can be seen in" ..
    "|face takes on a curiously blank expression\\.|gives .*? arms a quick shake\\." ..
    "|sings something in Guildspeak that you don't understand\\." ..
    "|The .*? seems to respond to the magic of .*? song\\." ..
    "|A look of intense focus comes over|seems to blend into the surroundings better" ..
    "|The air about .*? shimmers slightly\\.|looks more aware of the surroundings\\." ..
    "|eyes begin to shine with an inner strength\\.|is surrounded by an aura of natural confidence\\." ..
    "|begins to move with cat-like grace\\.|suddenly looks much more dextrous\\." ..
    "|looks charged with power\\.|basks in a divine force that suddenly surrounds" ..
    "|and it dissolves into a puff of emerald-hued smoke\\.  A verdant mist seeps from" ..
    "|the gem appears to improve in quality and color\\.|sparkles a little more and is void of some natural imperfections\\." ..
    "|is surrounded by an aura of natural confidence\\.")

-- Effects ending
local EFFECTS_ENDING_RE = Regex.new(
    "(?i)seems hesitant, looking unsure of|seems slightly different" ..
    "|air stops shimmering around|spirits are no longer lifted" ..
    "|undulate and grow stronger|slow down and become less nimble" ..
    "|slow down and become a bit less nimble|energy fades from around" ..
    "|gleam fades from|creaks and twists briefly before disintegrating" ..
    "|returns to its natural state|look of grim determination" ..
    "|slowly exhales as|suddenly appears less powerful" ..
    "|appears less powerful\\.|seems somewhat less buoyant" ..
    "|posture becomes noticeably more relaxed" ..
    "|The bright luminescence fades from around|appears to be less protected" ..
    "|appears to lose some confidence|The shimmering aura fades from around" ..
    "|loses some awareness\\.|seems a bit less imposing\\.|appears slightly less composed\\." ..
    "|The wall of force disappears from around|The mote of white light next to" ..
    "|becomes unbalanced for a second, then recovers\\." ..
    "|appears to lose some internal strength\\.|The appearance of great calm leaves" ..
    "|The brilliant aura fades away from|The faint blue glow fades from around" ..
    "|complexion returns to normal\\.|dull golden nimbus fades from around" ..
    "|look of renewed cognition fades\\.|seems to thin slightly\\.|becomes solid again\\." ..
    "|aura suddenly vanishes from around|undulate and fade away\\." ..
    "|movements no longer appear to be influenced by a divine power" ..
    "|seems less resolute\\.|chest slows before dying away with a final burst of energy" ..
    "|blood shield shrivel and dry|doesn't seem quite the same as" ..
    "|The lust for blood fades from" ..
    "|flare up one last time before vanishing with a staticky crackle\\." ..
    "|suddenly stops moving light-footedly|is no longer moving so silently\\." ..
    "|no longer moving so silently\\.|A few withered tendrils of .*? fall away from" ..
    "|body, swiftly dissipating into the air\\.|relaxes a little\\." ..
    "|seems to lose some dexterity\\.|returns to normal color\\." ..
    "|The brilliant luminescence fades from around|regal air swiftly drifts away\\." ..
    "|Cobalt light separates itself from" ..
    "|Slowly evaporating, a faint hint of brine is all that remains upon" ..
    "|falls away, unraveling as it fades\\." ..
    "|ethereal censer fades away, leaving only a faint lingering scent of incense\\." ..
    "|The .*? fades from .*? eyes\\.|The misty halo fades from|The focused look leaves" ..
    "|A blue-green aura briefly flares up .*? before dissipating into nothingness\\." ..
    "|An incandescent veil fades from|The shimmering multicolored sphere fades from around" ..
    "|The tingling sensation and sense of security leaves" ..
    "|The silvery luminescence fades from around" ..
    "|glances around, looking a bit less confident\\.|surge of empowerment fades\\." ..
    "|posture relaxes briefly\\.|The sparking electricity surrounding" ..
    "|hazy and indistinct form returns to normal\\.|appears somehow different\\." ..
    "|is no longer protected by the shimmering field of energy\\." ..
    "|no longer bristles with energy\\.|The layer of raw elemental energy surrounding" ..
    "|spell falters as it takes hold on|one last time before fading entirely\\." ..
    "|The swirling whirlwind around|A faint silvery glow fades from around" ..
    "|The forceful strain in|glistening faintly before stilling to normalcy" ..
    "|looks less calm and refreshed than a moment ago\\." ..
    "|skin withdraw, submerging out of sight|appears less dazed and confused\\." ..
    "|The rage fades from|The fiery aura surrounding" ..
    "|The ineffable aura of allure fades from|A look of concentration briefly passes across" ..
    "|loses .*? murky complexion\\.|skin settles into quiescence\\." ..
    "|tension abates somewhat\\.|suddenly shoot off in all directions, then quickly fade away\\." ..
    "|appears less confident\\.|begins to breathe less deeply\\." ..
    "|The dim aura fades from around|Deep blue motes swirl away from" ..
    "|The opalescent aura fades from around|The air calms down around" ..
    "|A silvery fog coalesces around|stance, no longer braced for impact" ..
    "|barrier flashes rapidly and the sound of breaking crystal can be heard as it cascades down around" ..
    "|sloughing away with a faint shimmer\\.|The scant motes of darkness clinging to" ..
    "|The subtle nimbus that radiates from|The blood red haze dissipates from around" ..
    "|Swirls of mana encircling .*? slowly dissipate|seems to lose some internal strength\\." ..
    "|flickers once and shudders before fading completely\\." ..
    "|Dim steel grey lines of energy flicker one last time about" ..
    "|The radiant golden light that fills" ..
    "|As abruptly as it began, the tailwind embracing .*? goes still\\." ..
    "|looks slightly less tense than he did a moment ago\\." ..
    "|intense rage dwindles away\\.|appears less secure\\." ..
    "|The pure white radiance swirling around|shimmers and flickers briefly before fading\\." ..
    "|^An ethereal golden collection bowl drifts out of")

-- Scripted items
local SCRIPTED_ITEMS_RE = Regex.new(
    "(?i)idly spins the base of|and adopts a nefarious expression\\." ..
    "|center-most crystal winks briefly, but nothing else happens" ..
    "|A ripple of .*? light shimmers over the surface of the" ..
    "|A brief shimmer of .*? light erupts from inside the" ..
    "|A fiery plume of hissing smoke trails" ..
    "|then sets to work on each piece, meticulously checking the shaft, fletching, and tips for damage" ..
    "|the illumination of its sigils slowly ebbs away" ..
    "|touch, a number of sigils worked into its grain take on a faint luminescence" ..
    "|tracing the outline of an arcane sigil before sinking away|armoire" ..
    "|and the .*? flying above .*? shoulder glow slightly\\." ..
    "|shoulder places its hands out in front of itself|shoulder whispers something to" ..
    "|single .*? tentacle rises from its surface" ..
    "|at the top of .* disappearing back into the|The .*? flying over .*? shoulder says" ..
    "|and removes the silky strands that were binding it to" ..
    "|pushes the heel of .*? empty hand against" ..
    "|Fibrous tendrils of mana coalesce from the surroundings and coats" ..
    "|ear as the magical ward protecting|ripples faintly with contained energy\\." ..
    "|burst into baneful white flames" ..
    "|Impenetrable darkness erupts midair for a moment before vanishing into nothingness\\." ..
    "|separates the weapon into two halves\\." ..
    "|appears incorporated into some of the decorations on the" ..
    "|their rhythmic movement an ever-shifting constellation" ..
    "|The distorted surface begins to mend as glyphs appear and fade across its surface" ..
    "|shoulder vanishes in a brief, white flash of light\\." ..
    "|eyes glow brightly for a moment and .*? appears energized!" ..
    "|and adopts a grim look of empowerment\\.|burst into pure white flames!" ..
    "|Several sigils incised along .*? flicker briefly with" ..
    "|A low thrumming \\*BOOM\\* fills the area as ethereal motes form into a small pile of flickering sand that collects at" ..
    "|by the loop on the end of its handle\\." ..
    "|The latticework of .*? surrounding the" ..
    "|murmured invocation, the sigil's power blazes forth in trails of pale energy and surges into" ..
    "|gently taps and strokes the vines wrapped around .*? and the vines recede" ..
    "|A wayward .*? shoulder and drifts to the floor\\." ..
    "|glimmers of .*? energy flicker away from its billowing fabric like sparks and swirl around" ..
    "|runes scribed into the grain of its pole flare bright and fade in sequence one after another in a pattern reminiscent of tumbling embers" ..
    "|and an impenetrable darkness erupts around" ..
    "|fist, a faint flicker of energy dances about" ..
    "|with a flash of .*?  A powerful burst of .*? lingers briefly in the air\\." ..
    "|hand drags itself by dint of arm strength and sheer will up" ..
    "|A low crackling sound accompanies the momentary flare of a sigil on" ..
    "|The mirror-like clones of the .*? fade away\\." ..
    "|flying over .*? shoulder says|skin painfully rip away, vines quickly retreating\\." ..
    "|the shroud of misty white thorns coalescing around it part slightly" ..
    "|causing the coraesine relic bound to hilt to take on|invokes the .*? name of the gods" ..
    "|light\\.  A low rumble lingers briefly in the air\\." ..
    "|bracer twice in quick succession, opening a small spring-loaded compartment" ..
    "|easily plucks .*? out of it and twists the end cap back into place\\." ..
    "|With a quick flourish .*? notes the foraged item with a few strokes of chalk before placing the writing instrument back into the" ..
    "|Bending over .*? and plucks it free from|^A lump bulges the skin of" ..
    "|opening its lid and shaking a|into a series of straps on the back of" ..
    "|A hissing cloud of green necrotic haze trails|^With careful precision," ..
    "|^With a sudden cross-body motion toward|lifts the sheer gauze veil on" ..
    "|dramatically brushes .* fingers lightly across .* case, causing a spark to ignite across the surface\\." ..
    "|^A .* energy trails .* as .* stows it in" ..
    "|^Ribbons of bluish-green light burn into existence and swirl around" ..
    "|^An ethereal bluish-green light swirls around the blade of" ..
    "|^A haze of virescent fumes dissipates from around .* as .* slings it over .* shoulder\\." ..
    "|glyph winks briefly, but nothing else happens\\.")

-- Selling interaction
local SELLING_RE = Regex.new(
    "(?i)<a [^>]*?noun=\"([^\"]+)\">[^<]*</a>\\s*?(?:steps)|glances at it briefly, then hands <a [^>]*?noun=\"[^\"]+\">(?:him|her)</a>" ..
    "|^[A-Z][a-z]+ asks .* if .* would like to buy.*" ..
    "|^[A-Z][a-z]+ asks .* to appraise" ..
    "|and says, \"I don't have that much spare silver, so I will have to give you a" ..
    "|and says, \"That's not quite my field," ..
    "|then returns .*? to|touches .*? as .*? asks .* a question\\." ..
    "|^[A-Z][a-z]+ steps aside to talk with .*? about" ..
    "|takes .*?, examines it, and quickly returns it to .*? with a shrug\\." ..
    "|asks .*? (?:to appraise|if he would like to buy)" ..
    "|Grundael takes .*?\\.  Realizing it's empty, his face reddens and he returns it\\." ..
    "|Grundael frowns and says, \"Oh no no\\.\\.\\." ..
    "|hesitantly before paying .* some silvers\\." ..
    "|hands it back to .* along with some silver\\." ..
    "|exclaims, \"Quit wasting my time .*!\"")

-- Inventory interaction
local INVENTORY_RE = Regex.new(
    "(?i)^<a [^>]*?noun=\"([^\"]+)\">[^<]*</a>\\s*?(?:absent-mindedly drops|adjusts|attaches|brushes|carefully adds" ..
    "|carefully eyes|carefully hangs|carefully pins|carefully places|carefully pours|carefully removes" ..
    "|carefully secures|carefully unpins|carefully straps|casually tosses|deftly removes|digs" ..
    "|discreetly stows|discreetly removes|drapes|draws|equips|fiddles with the|flips" ..
    "|flutters out from inside .*? dropping|gently layers|grabs|hangs|is admiring" ..
    "|just opened|just closed|passes|pops|pours|presses|produces|pulls|pulls back|pulls on|pushes|puts" ..
    "|put .*? in|quickly whips|raises|reaches|removes|retrieves|rummages|searches through" ..
    "|secures|securely attaches|seizes|sheathes|slides|slings|slips|stows|summons a swarm" ..
    "|swaps|takes|throws|traces|tosses|tries|tucks|twists|unsheathes|vanishes|withdraws|works" ..
    "|opens the various containers on|closes the various containers on)" ..
    "|reaches toward the|slides out a|With a slight roll of .*? shoulder" ..
    "|vanishes into the depths of|seemingly floats up out of" ..
    "|^Slipping its loop from" ..
    "|^Flicking .*? opens the blades of .*? in one smooth, silent motion\\." ..
    "|^As .*? draws a|from a series of straps on the back of" ..
    "|then suddenly several articles of clothing fly out of the" ..
    "|one of the smaller compartments inside" ..
    "|squeezes .*? with all of .*? might and it shatters apart, revealing" ..
    "|carefully applies dollops of .*? poison to key areas of" ..
    "|picks at the knot holding|ties .*? shut tightly\\.")

-- Drinking, eating, healing
local HEALING_RE = Regex.new(
    "(?i)takes a drink|takes a bite|concentrates" ..
    "|gradually fades, forming on|dwarf empath tattoo" ..
    "|begins to look better as the cuts on" ..
    "|focuses on .* with intense concentration" ..
    "|The cuts on .*? close and the bruises fade" ..
    "|The scar on .*? glows faintly white before fading altogether" ..
    "|The bruises around .*? fade\\.|begins to look a little better\\." ..
    "|appears entirely restored\\.|looks much more calm and refreshed\\." ..
    "|veins stand out briefly\\.|begins to look better" ..
    "|gradually fades, affecting|fingertips using a gentle, circular motion\\." ..
    "|pours a dose|flesh as dark essence restores" ..
    "|wavers with sudden fatigue|looks better\\.|skin looks healthier\\." ..
    "|loses some of .*? pallor\\.|bears the wound in|gobbles down a big bite" ..
    "|in one enormous bite|There is a bright flash and" ..
    "|flinches visibly in pain as|with an air of determination\\." ..
    "|An image of Liabo reflects in" ..
    "|is bathed in a column of silver moonlight, invigorating" ..
    "|is bathed in a column of silver moonlight, fully restored at" ..
    "|own keeping, leaving behind new-grown flesh\\." ..
    "|Golden-green warmth extends from|looks a little better\\." ..
    "|forages around briefly|forages briefly and manages to find" ..
    "|A swarm of scarabs erupts below .*? removing" ..
    "|^Crimson mist seeps from" ..
    "|skin takes on a slight flush as" ..
    "|wounds begin to mend as the argent cocoon pulses with light" ..
    "|then dissolves into thousands of tiny lights before fading away" ..
    "|mouth open, and pours in a small amount of")

-- Lockpicking
local LOCKPICKING_RE = Regex.new(
    "(?i)^<a [^>]*?noun=\"([^\"]+)\">[^<]*</a>\\s*?(?:begins to meticulously examine|detaches a" ..
    "|settles into the difficult task of picking the lock on" ..
    "|appears extremely focused|looks up with a big grin on" ..
    "|goes about disarming|no longer appears focused|speaks briefly with" ..
    "|fiddles with .*? for a moment|gets .*? stuck in the lock" ..
    "|carefully pushes a small wad of cotton into the lock mechanism\\." ..
    "|removes a pair of metal grips from|refines .*? a bit\\.)" ..
    "|Then\\.\\.\\.CLICK!  It opens!" ..
    "|and slips it into the crack between the lid and the base, apparently cutting something within" ..
    "|and carefully reaches into the locking mechanism" ..
    "|The scintillating light fades from .*? hands\\." ..
    "|Using a pair of metal grips|peers thoughtfully into the lock mechanism of" ..
    "|Taking a small lump of putty from")

-- Magic items
local MAGIC_ITEM_1_RE = Regex.new(
    "rubs a.*?<a [^>]*?noun=\"[^\"]+\">[^<]+</a>.*?in <a [^>]*?noun=\"[^\"]+\">(?:his|her)</a> hand\\.")
local MAGIC_ITEM_2_RE = Regex.new(
    "rubs <a [^>]*?noun=\"[^\"]+\">(?:his|her)</a> <a [^>]*?noun=\"[^\"]+\">[^<]+</a>")

-- Environment ambients
local ENVIRONMENT_RE = Regex.new(
    "(?i)^A swirling current tugs .*? gently back and forth\\." ..
    "|^The sand shifts beneath .*? feet, sending up small clouds of sea bottom\\." ..
    "|^Something silver and swift darts between .*? ankles\\." ..
    "|^A crab scuttles sideways across a rock carpeted in mossy growth before darting away from" ..
    "|^Shifting currents set .*? hair aswirl in a slow .*? cloud about .*? head and face\\." ..
    "|^Tiny bubbles drift upward from a hidden fissure in the seabed, floating around .*? before disappearing into the depths\\." ..
    "|^A swell of turbulence sends .*? drifting off to one side\\." ..
    "|^A tiny bubble escapes .*? mustache\\." ..
    "|^A sub-surface swell bobs .*? lightly up and down\\." ..
    "|almost loses its content as it sways about in the water\\." ..
    "|^A wee bubble of air escapes .*? beard\\.")

-- NPC ambients
local NPC_RE = Regex.new(
    "(?i)stops to speak with|confers quietly with|lumbers in, swathed in darkness\\." ..
    "|falls deeper into bloodthirst, the darkness swathing" ..
    "|lumbers .*? desiccated tendons in .*? legs popping as he goes\\." ..
    "|slack lips release a tormented moan\\." ..
    "|missing ears as if beset by voices only" ..
    "|taking on monstrous proportions before diminishing back to its original shape\\." ..
    "|decaying teeth in a horrible parody of a warrior's snarl\\." ..
    "|glowing tattoos pulses once, brightening precipitously before returning to normal\\." ..
    "|scampers up to .*? on its wooden legs\\.")

-- Movement fluff (fancy arrival/departure descriptions to suppress)
local MOVEMENT_FLUFF_RE = Regex.new(
    "(?i)just arrived\\.|just left\\." ..
    "|Motes of .*? light flow in and resolve into" ..
    "|A softly scented breeze begins to swirl around" ..
    "|figure partially obscured by the flickering form" ..
    "|the shadows retreat back into the surroundings" ..
    "|belongings into a pile of dust that is swiftly borne away on the wind" ..
    "|tied to a red ribbon jingling follows" ..
    "|the door slams shut and vanishes, leaving no traces of its existence" ..
    "|slowly fades into view with a gasp of breath and a slightly disoriented look" ..
    "|just moved quietly .* group following closely\\." ..
    "|flounces in amidst a diffuse cloud of .*? glitter\\." ..
    "|The unmistakable scents of sulphur, ether, and brimstone rise from the ground near you\\." ..
    "|The faint sound of .*? tied to a red ribbon jingling touts" ..
    "|body grows more and more translucent until you realize" ..
    "|leaving a fading trail of multicolored footprints behind\\." ..
    "|suddenly appears out of nowhere, one hand moving away from" ..
    "|You see a blur out of the corner of your eye" ..
    "|dissolves into motes of .*? light that flow" ..
    "|suddenly appears in a flash of .*? light\\.")

-- ============================================================
-- HELPERS
-- ============================================================

local function debug_filter(reason, line)
    if state.debug_filter_enabled then
        echo("*** FILTERED by " .. reason .. ": " .. tostring(line))
    end
end

local function is_self_line(line)
    local plain = line:gsub("<[^>]*>", " "):match("^%s*(.-)%s*$") or ""
    return plain:match("^You[^%a]") ~= nil or plain:match("^Your[^%a]") ~= nil
end

local function center_text(text, width)
    width = width or 45
    local t = (text or ""):match("^%s*(.-)%s*$") or ""
    if #t == 0 then return t end
    local pad = math.max(math.floor((width - #t) / 2), 0)
    return string.rep(" ", pad) .. t
end

local function extract_noun_from_line(line)
    local last_noun = nil
    for noun in line:gmatch('noun="([^"]+)"') do last_noun = noun end
    if last_noun then return last_noun end
    local plain = line:gsub("<[^>]*>", " "):match("^%s*(.-)%s*$") or ""
    return plain:match("[Aa]n?%s+([%a][%a'' %-]+)")
end

-- ============================================================
-- MOVEMENT TRACKING
-- ============================================================

local function process_movement(line)
    -- Suppress fancy arrival/departure fluff
    if MOVEMENT_FLUFF_RE:test(line) then
        debug_filter("MOVEMENT", line)
        return nil
    end

    -- Detect own movement (suppress pending state so we don't mis-attribute)
    if line:match("^<nav rm='%d+'/>") or
       line:match("^<d cmd='go %w+'>%w+</d>") or
       line:match("^You (?:go|walk|move) %w+") then
        state.recent_self_movement = true
        state.pending_joins   = {}
        state.pending_leavers = {}
        return line
    end

    -- Room players component: parse who is now in the room
    local players_content = line:match("<component id='room players'>(.-)</component>")
    if players_content then
        local current_players = {}
        local seen = {}
        for noun in players_content:gmatch('noun="([^"]+)"') do
            local cap = noun:sub(1, 1):upper() .. noun:sub(2):lower()
            if not seen[cap] then
                seen[cap] = true
                current_players[#current_players + 1] = cap
            end
        end

        if not state.recent_self_movement then
            local now = os.time()

            -- Build lookup sets for fast membership tests
            local last_set    = {}; for _, n in ipairs(state.last_seen_players)  do last_set[n]    = true end
            local current_set = {}; for _, n in ipairs(current_players)           do current_set[n] = true end

            -- Schedule new arrivals for delayed announcement
            for _, name in ipairs(current_players) do
                if not last_set[name] then
                    state.pending_joins[name] = now
                end
            end

            -- Schedule departures
            local new_leavers = {}
            for _, name in ipairs(state.confirmed_players) do
                if last_set[name] and not current_set[name] and name ~= Char.name then
                    new_leavers[#new_leavers + 1] = name
                end
            end

            -- Prune confirmed list of those who left
            local new_confirmed = {}
            for _, name in ipairs(state.confirmed_players) do
                if not last_set[name] or current_set[name] then
                    new_confirmed[#new_confirmed + 1] = name
                end
            end
            state.confirmed_players = new_confirmed
            state.pending_leavers   = new_leavers
        else
            state.pending_leavers = {}
        end

        state.skip_next_after_player_component = true
        state.group_dirty          = true
        state.last_seen_players    = current_players
        state.recent_self_movement = false
        debug_filter("ROOM PLAYERS", line)
        return nil
    end

    -- Announce delayed joins (3-second hold)
    local now    = os.time()
    local joined = {}
    local keep   = {}
    for name, first_seen in pairs(state.pending_joins) do
        if now - first_seen >= 3 then
            -- Verify still present
            for _, n in ipairs(state.last_seen_players) do
                if n == name then
                    joined[#joined + 1] = name
                    -- Add to confirmed if not already there
                    local already = false
                    for _, c in ipairs(state.confirmed_players) do
                        if c == name then already = true; break end
                    end
                    if not already then
                        state.confirmed_players[#state.confirmed_players + 1] = name
                    end
                    break
                end
            end
        else
            keep[name] = first_seen
        end
    end
    state.pending_joins = keep

    if #joined == 1 then
        respond(joined[1] .. " enters.")
    elseif #joined > 1 then
        respond(joined[#joined] .. "'s group enters.")
    end

    -- Handle the line immediately after a room-players component
    if state.skip_next_after_player_component then
        -- Let AS:/CS: combat lines through
        if line:match("AS%s*:") or line:match("CS%s*:") then
            return line
        end

        state.skip_next_after_player_component = false

        -- Allow stance-change lines (stand/sit/kneel/lie)
        if line:match("^<a [^>]+>[^<]+</a>%s+(?:kneels|stands|sits|lies)") then
            return line
        end

        -- Directional leave
        local noun, direction = line:match('<a [^>]+noun="([^"]+)">[^<]+</a> just went <d cmd=[\'"]go (%w+)[\'"]>')
        if not noun then
            noun, direction = line:match('<a [^>]+noun="([^"]+)">[^<]+</a> just went through a <a [^>]+>(.-)</a>')
        end
        if noun then
            local cap_name = noun:sub(1, 1):upper() .. noun:sub(2):lower()
            local is_pending = false
            for _, n in ipairs(state.pending_leavers) do
                if n == cap_name then is_pending = true; break end
            end
            if is_pending then
                local dir = direction and direction:lower() or "away"
                respond(cap_name .. " leaves " .. dir .. ".")
                local new_leavers = {}
                for _, n in ipairs(state.pending_leavers) do
                    if n ~= cap_name then new_leavers[#new_leavers + 1] = n end
                end
                state.pending_leavers = new_leavers
                return nil
            end
        end

        -- Plain leave
        if #state.pending_leavers > 0 then
            local name = table.remove(state.pending_leavers, 1)
            respond(name .. " leaves.")
        end
        state.pending_leavers = {}
        return nil
    end

    return line
end

-- ============================================================
-- MAIN FILTER FUNCTION
-- Called from the DownstreamHook; returns line or nil.
-- ============================================================

function M.filter(line)
    line = tostring(line or "")
    local plain_line = line:gsub("<[^>]*>", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""

    -- Always pass through prompt/nav/timing XML (core client signals)
    if line:find("<prompt time=", 1, true) then return line end
    if line:find("<roundTime value=", 1, true) then return line end
    if line:find("<castTime value=", 1, true) then return line end
    if line:match("^<nav rm='") or line:match("^<d cmd='go ") then
        state.skip_next_after_player_component = false
        return line
    end

    -- Early "You feel more refreshed" suppression (spam filter, pre-XML check)
    if state.filter_spam and plain_line:find("You feel more refreshed.", 1, true) then
        debug_filter("CERTAIN YOU LINE", line)
        return nil
    end

    -- ========== ANIMAL FILTER ==========
    if state.filter_animals then
        local nouns = {}
        for noun in line:gmatch('noun="([^"]+)"') do
            nouns[#nouns + 1] = noun:lower()
        end
        if #nouns > 0 then
            -- Pass: loot category headers
            if line:match("^<pushBold/>%(Weapons|Armor|Containers|Wands|Magic Items|Scrolls|Clothing|Special%) %[") then
                goto after_animal
            end
            -- Pass: room component data
            if line:match("<(component|compDef) id='room") then goto after_animal end
            -- Pass: talking animals
            if line:match("says,") or line:match("asks,") or line:match("exclaims,") or
               line:match("shouts,") or line:match("mutters,") then goto after_animal end
            -- Pass: "You also see"
            if line:match("You also see") then goto after_animal end
            -- Pass: uncap wand
            if line:match("Uncapping the base of") then goto after_animal end
            -- Block if a blocked animal noun is present
            for _, noun in ipairs(nouns) do
                if BLOCKED_NOUNS[noun] then
                    debug_filter("ANIMAL", line)
                    return nil
                end
            end
            -- Block animated objects
            if line:match("<a [^>]*>[^<]*animated[^<]*</a>") then
                debug_filter("ANIMAL (animated)", line)
                return nil
            end
        end
        ::after_animal::
    end

    -- ========== FLARE FILTER ==========
    if state.filter_flares and #state.flare_patterns > 0 then
        for _, pattern in ipairs(state.flare_patterns) do
            if pattern:test(line) then
                debug_filter("FLARE", line)
                return nil
            end
        end
    end

    -- Always keep direct hit-damage lines even in filtered mode
    if line:find("and hit for", 1, true) and line:find("points of damage!", 1, true) then
        return line
    end

    -- ========== COMBAT MATH FILTER ==========
    local is_combat_math = (
        line:match("^%s*AS:") or line:match("^%s*CS:") or
        line:match("^%s*%[SSR result:") or line:match("^%s*%[SMR result:") or
        plain_line:match("^%s*AS:") or plain_line:match("^%s*CS:") or
        plain_line:match("^%s*%[SSR result:") or plain_line:match("^%s*%[SMR result:")
    )
    if state.filter_combat_math and (is_combat_math or CRIT_RANK_RE:test(plain_line)) then
        debug_filter("COMBAT MATH", line)
        return nil
    end

    -- Suppress blank lines when any filter is active
    local any_filter = state.filter_spam or state.filter_animals or
                       state.filter_flares or state.filter_combat_math
    if any_filter and line:match("^%s*$") then return nil end

    -- Pass through if spam filter is off
    if not state.filter_spam then
        if state.show_movement then return process_movement(line) end
        return line
    end

    -- ========== SPAM FILTER ==========

    -- Death messaging (condensed output)
    if DEATH_RE:test(line) then
        local death_noun = extract_noun_from_line(line)
        if death_noun and death_noun:lower() ~= Char.name:lower() then
            respond(center_text(death_noun:upper() .. " DIES {?}", 45))
            return nil
        end
    end

    -- Spell falloff suppression (not for self lines)
    if not is_self_line(line) then
        if SPELL_FALLOFF_RE:test(line) or SPELL_FALLOFF_RE:test(plain_line) then
            debug_filter("SPELL FALLOFF", line)
            return nil
        end
    end

    -- Looting noise
    if (line:find("didn't carry any silver.", 1, true)) then
        debug_filter("No Silver (loot)", line)
        return nil
    end
    if (line:find("had nothing of interest", 1, true) or
        line:find("had nothing else of value", 1, true)) then
        debug_filter("Nothing of Interest (loot)", line)
        return nil
    end

    -- Decay / corpse messages
    if DECAY_RE:test(line) then
        debug_filter("Decay Message", line)
        return nil
    end

    -- Always pass core XML state signals
    if line:find("<indicator ", 1, true)               then return line end
    if line:match("^<compDef id='room exits'>")         then return line end
    if line:match("^<spell exist")                      then return line end
    if line:match("^<compass>")                         then return line end
    if line:match("^<pushBold/>%(Weapons|Armor|Containers|Wands|Magic Items|Scrolls|Clothing|Special%) %[") then return line end
    if line:match("^<right%s")                          then return line end
    if line:match("^<left%s")                           then return line end
    if line:match("^<dialogData id='combat'")           then return line end
    if line:match("^<dialogData id='minivitals'")       then return line end
    if line:match("^<dialogData id='injuries'")         then return line end
    if line:match("^<dialogData id='stance'")           then return line end
    if line:match("^<dialogData id='Buffs'")            then return line end
    if line:match("^<dialogData id='encum'")            then return line end
    if line:match('<style id="roomName"')               then return line end
    if line:match('<style id="roomDesc"')               then return line end
    if line:match("^Also here:")                        then return line end
    if line:find("<style id=") and line:find("You also see") then return line end
    if line:match("^Obvious (?:paths|players):")        then return line end
    if line:find("<preset id=\"speech\">", 1, true)     then return line end
    if line:find("Speaking in") and
       line:find("you don't understand", 1, true)       then return line end
    if line:find("Borne on threads of spun magic", 1, true) then return line end

    -- Suppress specific "You" lines (but NOT all self lines)
    if CERTAIN_YOU_RE:test(line) then
        debug_filter("CERTAIN YOU LINE", line)
        return nil
    end

    -- Pass through all remaining self lines
    if line:match("^You") or line:find("You prepare to cast", 1, true) then return line end
    if line:match("^Your")                            then return line end
    if line:lower():find("%byou%b") and
       line:lower():find("%byour%b")                  then return line end

    -- Second-line skip state machine (follows gesture/heal/magic item triggers)
    if state.skip_next_line then
        state.skip_next_line = false
        debug_filter("SKIPPING SECOND LINE", line)
        return nil
    end

    -- Gesture detection
    if line:find("gestures at you.", 1, true) then
        state.skip_next_line = false
    elseif GESTURE_RE:test(line) then
        debug_filter("GESTURE", line)
        state.skip_next_line = true
        return nil
    end

    -- Standard spell prep (ends in "...")
    if not line:match("^You[^%a]") and not line:match("^Your[^%a]") and
       not line:find(Char.name, 1, true) and line:match("%.%.%.%s*$") then
        debug_filter("STANDARD SPELL PREP", line)
        return nil
    end

    -- Custom spell prep (massive alternation pattern)
    if not line:find(Char.name, 1, true) and CUSTOM_SPELL_PREP_RE:test(line) then
        debug_filter("CUSTOM SPELL PREP", line)
        return nil
    end

    -- Effects beginning
    if not line:find(Char.name, 1, true) and EFFECTS_BEGINNING_RE:test(line) then
        debug_filter("EFFECTS BEGINNING", line)
        return nil
    end

    -- Effects ending
    if not line:find(Char.name, 1, true) and EFFECTS_ENDING_RE:test(line) then
        debug_filter("EFFECTS ENDING", line)
        return nil
    end

    -- Scripted items
    if not line:find(Char.name, 1, true) and SCRIPTED_ITEMS_RE:test(line) then
        debug_filter("SCRIPTED ITEM", line)
        return nil
    end

    -- Selling interaction
    if not line:find(Char.name, 1, true) and SELLING_RE:test(line) then
        debug_filter("SELLING", line)
        return nil
    end

    -- Inventory interaction
    if not line:find(Char.name, 1, true) and INVENTORY_RE:test(line) then
        debug_filter("INVENTORY", line)
        return nil
    end

    -- Drinking, eating, healing (triggers skip_next_line for the cure text)
    if not line:find(Char.name, 1, true) and HEALING_RE:test(line) then
        state.skip_next_line = true
        return nil
    end

    -- Lockpicking
    if not line:find(Char.name, 1, true) and LOCKPICKING_RE:test(line) then
        debug_filter("LOCKPICKING", line)
        return nil
    end

    -- Magic items
    if MAGIC_ITEM_1_RE:test(line) then
        debug_filter("MAGIC ITEM", line)
        state.skip_next_line = true
        return nil
    elseif MAGIC_ITEM_2_RE:test(line) then
        debug_filter("MAGIC ITEM", line)
        state.skip_next_line = true
        return nil
    elseif not line:match("^Your .* suddenly disintegrates") and
           line:find("suddenly disintegrates!", 1, true) then
        debug_filter("MAGIC ITEM (disintegrate)", line)
        return nil
    end

    -- Disks
    if line:find("goes off in search of its master.", 1, true) or
       line:find("arrives in the room, shivering violently.  It then disintegrates.", 1, true) then
        debug_filter("DISK", line)
        return nil
    end

    -- Player ambients
    if line:find("A feral golden gleam flashes through", 1, true) and
       line:find("eyes.", 1, true) then
        debug_filter("PLAYER AMBIENTS", line)
        return nil
    end

    -- Environment ambients
    if ENVIRONMENT_RE:test(line) then
        debug_filter("ENVIRONMENT", line)
        return nil
    end

    -- NPCs
    if NPC_RE:test(line) then
        debug_filter("NPC", line)
        return nil
    end

    -- Duskruin
    if line:find("An announcer shouts,", 1, true) and
       line:find("Our next combatant", 1, true) then
        debug_filter("Duskruin", line)
        return nil
    end

    -- Player movement tracking (at end, after all other filters)
    if state.show_movement then
        return process_movement(line)
    end

    return line
end

return M
