--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: textsubs
--- version: 2.0.0
--- author: Seped, MikeLC
--- game: dr
--- description: Text substitution engine - replaces game text with enhanced versions (damage ratings, appraisals, guild-specific, spell links, etc)
--- tags: text, substitution, display, damage, appraise
---
--- Original authors:
---   Seped — original textsubs.lic (lich_repo_mirror)
---   MikeLC — 2/15/2025 major refactor with spell links, scroll labels, guild-specific subs (dr-scripts)
---
--- Ported to Revenant Lua — full feature parity with both source files.
---
--- Usage:
---   ;textsubs   - Run in background to apply text substitutions
---
--- YAML settings:
---   textsubs_spell_links: true       # Enable Elanthipedia hyperlinks for spells
---   herb_textsubs: true              # Enable herb abbreviation subs
---   textsubs_use_plat_grouping: true # Enable platinum grouping in coin display
---   private_textsubs:                # Custom substitutions (pattern: replacement)

if no_pause_all then no_pause_all() end
if no_kill_all then no_kill_all() end

-------------------------------------------------------------------------------
-- Module
-------------------------------------------------------------------------------

local TextSubs = {}
local subs = {}

function TextSubs.add(pattern, replacement)
  local ok, re = pcall(Regex.new, pattern)
  if ok then
    table.insert(subs, { re = re, repl = replacement })
  else
    echo("[textsubs] invalid pattern: " .. pattern)
  end
end

function TextSubs.clear()
  subs = {}
end

function TextSubs.elanthipedia(text, pretext, postext, prelink, poslink, preresult, posresult)
  pretext   = pretext   or ""
  postext   = postext   or ""
  prelink   = prelink   or ""
  poslink   = poslink   or ""
  preresult = preresult or "$1"
  posresult = posresult or "$3"
  local hyperlink = prelink .. text:gsub(" ", "_") .. poslink
  local pattern   = "(" .. pretext .. ")(" .. text .. ")(" .. postext .. ")"
  local result    = preresult .. '<a href="https://elanthipedia.play.net/' .. hyperlink .. '">' .. text .. "</a>" .. posresult
  TextSubs.add(pattern, result)
end

-------------------------------------------------------------------------------
-- Downstream hook
-------------------------------------------------------------------------------

DownstreamHook.remove("textsub")
DownstreamHook.add("textsub", function(line)
  for _, sub in ipairs(subs) do
    local ok, result = pcall(function() return sub.re:replace_all(line, sub.repl) end)
    if ok then line = result end
  end
  return line
end)

before_dying(function()
  DownstreamHook.remove("textsub")
end)

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------

local settings = get_settings()

-- Private textsubs from YAML
if type(settings.private_textsubs) == "table" then
  for k, v in pairs(settings.private_textsubs) do
    TextSubs.add(tostring(k), tostring(v))
  end
end

-------------------------------------------------------------------------------
-- Spell Links (conditional: settings.textsubs_spell_links)
-- MikeLC 2/15/2025
-------------------------------------------------------------------------------

if settings.textsubs_spell_links then
  -- 1. Guild Spells
  local guild = DRStats.guild
  if guild then
    TextSubs.add("You recall the spells you have learned from your training.",
      'You recall the spells you have learned from your <a href="https://elanthipedia.play.net/Category:'
      .. guild:gsub(" ", "_") .. '_spells">' .. guild .. "</a> training.")
  end

  -- 2. Magic Feats
  TextSubs.add("You recall proficiency with the magic feats of",
    'You recall proficiency with the <a href="https://elanthipedia.play.net/Magical_feats">magical feats</a>:')

  -- 3. Spellbooks
  local spellbooks = {
    "Analogous Patterns",
    -- Bard
    "Elemental Invocations", "Emotion Control", "Fae Arts", "Sound Manipulation",
    -- Cleric
    "Antinomic Sorcery", "Divine Intervention", "Holy Defense", "Holy Evocations",
    "Metamagic", "Spirit Manipulation",
    -- Empath
    "Body Purification", "Healing", "Life Force Manipulation", "Mental Preparation", "Protection",
    -- Moon Mage
    "Enlightened Geometry", "Moonlight Manipulation", "Perception", "Psychic Projection",
    "Stellar Magic", "Teleologic Sorcery",
    -- Necromancer
    "Anabasis", "Animation", "Blood Magic", "Corruption", "Synthetic Creation",
    "Transcendental Necromancy",
    -- Paladin
    "Inspiration", "Justice", "Sacrifice",
    -- Ranger
    "Animal Abilities", "Nature Manipulation", "Wilderness Survival",
    -- Warrior Mage
    "Aether Manipulation", "Air Manipulation", "Earth Manipulation",
    "Electricity Manipulation", "Fire Manipulation", "Hylomorphic Sorcery", "Water Manipulation",
  }
  for _, name in ipairs(spellbooks) do
    TextSubs.elanthipedia(name, "^", ":", "Category:", "_spellbook")
  end

  -- 4. Spells (Elanthipedia links in spellbook column-format and Active Spells window)
  local SPELL_PRE  = "........\\s\\s|\\S|^"
  local SPELL_POST = "..\\(.*\\)|\\s*Slot"
  local spells = {
    "Abandoned Heart", "Absolution", "Acid Splash", "Adaptive Curing",
    "Aegis of Granite", "Aesandry Darlaeth", "Aesrela Everild", "Aether Cloak",
    "Aether Wolves", "Aethrolysis", "Aggressive Stance", "Air Bubble", "Air Lash",
    "Alamhif's Gift", "Albreda's Balm", "Alkahest Edge", "All-Presence",
    "Alloyage of Self", "Ancestral Arts", "Anther's Call", "Anti-Stun",
    "Arbiter's Stylus", "Arc Light", "Artificer's Eye", "Aspect of the Shark",
    "Aspects of the All-God", "Aspirant's Aegis", "Astral Projection", "Athleticism",
    "Aura of Tongues", "Aura Sight", "Auspice", "Avren Aevareae", "Avtalia Array",
    "Awaken", "Awaken Forest", "Back Alley Tricks", "Banner of Truce",
    "Bear Strength", "Beckon the Naga", "Benediction", "Bespoke Regalia",
    "Bitter Feast", "Blend", "Bless", "Blessing of the Fae", "Blood Burst",
    "Blood Staunching", "Bloodthorns", "Blufmor Garaen", "Blur", "Bond Armaments",
    "Bonegrinder", "Book Burning", "Braun's Conjecture", "Breath of Storms",
    "Burden", "Burn", "Butcher's Eye", "Cage of Light", "Calcified Hide",
    "Calculated Rage", "Call from Beyond", "Call from Within", "Calm", "Caltrops",
    "Caress of the Sun", "Carrion Call", "Centering", "Chain Lightning",
    "Cheetah Swiftness", "Chill Spirit", "Chirurgia", "Circle of Sympathy",
    "Clarity", "Clarity of Thought", "Claws of the Cougar", "Clear Vision",
    "Compel", "Compost", "Conductive Spires", "Confidence of Arms", "Consume Flesh",
    "Contingency", "Convergence", "Courage", "Covetous Rebirth",
    "Crusader's Challenge", "Crystal Burst", "Crystal Dart", "Crystal Spike",
    "Cure Disease", "Curse of the Wilds", "Curse of Zachriedek", "Damaris' Lullaby",
    "Dart", "Dazzle", "Deadfall", "Demrris' Resolve", "Desert's Maelstrom",
    "Destiny Cipher", "Devitalize", "Devolve", "Devour", "Dinazen Olkar",
    "Disassemble", "Dispel", "Distant Gaze", "Divine Armor", "Divine Guidance",
    "Divine Radiance", "Dragon's Breath", "Drums of the Snake", "Eagle's Cry",
    "Earth Meld", "Earth Sense", "Ease Burden", "Ebon Blood of the Scorpion",
    "Echoes of Aether", "Eclipse", "Eillie's Cry", "Electrogenesis",
    "Electrostatic Eddy", "Elementalism", "Elision", "Embed the Cycle",
    "Embrace of the Vela'Tohr", "Empower Moonblade", "Emuin's Candlelight",
    "Enrichment", "Essence of Yew", "Ethereal Fissure", "Ethereal Shield",
    "Expansive Infusions", "Explosive Dart", "Eye of Kertigen", "Eyes of the Blind",
    "Eylhaar's Feast", "Faenella's Grace", "Failure of the Forge", "Fiery Infusions",
    "Finesse", "Fire Ball", "Fire of Ushnish", "Fire Rain", "Fire Shards",
    "Fists of Faenella", "Flame Shockwave", "Fluoresce", "Flush Poisons",
    "Focus Moonbeam", "Footman's Strike", "Forestwalker's Boon", "Fortify",
    "Fortress of Ice", "Fountain of Creation", "Frost Scythe", "Frostbite",
    "Gam Irnan", "Gar Zeng", "Gauge Flow", "Geyser", "Ghost Shroud", "Ghoulflesh",
    "Gift of Life", "Glythtide's Gift", "Glythtide's Joy", "Grizzly Claws",
    "Grounding Field", "Guardian Spirit", "Halo", "Halt", "Hand of Tenemlor",
    "Hands of Bone", "Hands of Justice", "Hands of Lirisa", "Harawep's Bonds",
    "Harm Evil", "Harm Horde", "Harmless", "Harmony", "Heal", "Heal Scars",
    "Heal Wounds", "Heart Link", "Heavenly Fires", "Heighten Pain",
    "Heroic Strength", "Highlight Flaws", "Hodierna's Lilt", "Holy Warrior",
    "Horn of the Black Unicorn", "Huldah's Pall", "Hydra Hex", "Hypnotize",
    "Ice Patch", "Icutu Zaharenela", "Icy Infusions", "Idon's Theft", "Ignite",
    "Ignition Point", "Illusions of Grandeur", "Imbue", "Innocence", "Instinct",
    "Integrity", "Invocation of the Spheres", "Iridius Rod", "Iron Constitution",
    "Isolation", "Ivory Mask", "Iyqaromos Fire-Lens", "Kertigen's Will",
    "Kura-Silma", "Last Gift of Vithwok IV", "Lay Ward", "Lethargy",
    "Lightning Bolt", "Liturgy", "Locate", "Machinist's Touch", "Magnetic Ballista",
    "Major Physical Protection", "Malediction", "Manifest Force", "Mantle of Flame",
    "Mark of Arhat", "Marshal Order", "Mask of the Moons", "Mass Rejuvenation",
    "Membrach's Greed", "Memory of Nature", "Mental Blast", "Mental Focus",
    "Meraud's Cry", "Mind Shout", "Minor Physical Protection", "Mirror Image",
    "Misdirection", "Moonblade", "Moongate", "Murrula's Flames", "Naming of Tears",
    "Nature Control", "Necrotic Reconstruction", "Nexus", "Nissa's Binding",
    "Nonchalance", "Noumena", "Oath of the Firstborn", "Obfuscation",
    "Osrel Meraud", "Paeldryth's Wrath", "Paralysis", "Paranoia",
    "Partial Displacement", "Perseverance of Peri'el", "Persistence of Mana",
    "Petrifying Visions", "Phelim's Sanction", "Phenomena",
    "Philosopher's Preservation", "Phoenix's Pyre", "Piercing Gaze",
    "Piper's Vengeance", "Plague of Scavengers", "Platinum Hands of Kertigen",
    "Programmed Illusion", "Protection from Evil", "Psychic Shield",
    "Quick Infusions", "Quicken the Earth", "Rage of the Clans", "Raise Power",
    "Reactive Barriers", "Read the Ripples", "Rebuke", "Recharge",
    "Redeemer's Pride", "Refractive Field", "Refresh", "Regalia", "Regenerate",
    "Reinforced Infusions", "Rejuvenation", "Relight", "Rend",
    "Researcher's Insight", "Resection", "Resonance", "Resumption", "Resurrection",
    "Revelation", "Reverse Putrefaction", "Riftal Summons", "Righteous Wrath",
    "Rimefang", "Ring of Blessings", "Ring of Spears", "Ripplegate Theory",
    "Rising Mists", "Rite of Contrition", "Rite of Defiance", "Rite of Forbearance",
    "Rite of Grace", "River in the Sky", "Rutilor's Edge", "Saesordian Compass",
    "Sanctify Pattern", "Sanctuary", "Sanyu Lyba", "Seal Cambrinth",
    "See the Wind", "Seer's Sense", "Self Confidence", "Senses of the Tiger",
    "Sentinel's Resolve", "Sever Thread", "Shadewatch Mirror", "Shadow Court",
    "Shadow Servant", "Shadow Web", "Shadowling", "Shadows", "Shape Moonblade",
    "Shatter", "Shear", "Shield of Light", "Shift Moonbeam", "Shocking Infusions",
    "Shockwave", "Sidasas Sedra", "Sidhlot's Flaying", "Siphon Vitality",
    "Skein of Shadows", "Sleep", "Smite Horde", "Solace spell", "Soldier's Prayer",
    "Sorden Singec", "Soul Ablaze", "Soul Attrition", "Soul Bonding", "Soul Shield",
    "Soul Sickness", "Sovereign Destiny", "Spite of Dergati", "Spiteful Rebirth",
    "Sprout", "Sprout Undergrowth", "Stampede", "Starcrash", "Starlight Barricade",
    "Starlight Sphere", "Steady Hands", "Stellar Collector", "Steps of Vuan",
    "Stone Strike", "Strange Arrow", "Stun Foe", "Substratum", "Sure Footing",
    "Swarm", "Swirling Winds", "Syamelyo Kuniyo", "Sylvan Purity", "Tailwind",
    "Tamsine's Kiss", "Tangled Fate", "Teachings of the Verdant Lily",
    "Telekinetic Shield", "Telekinetic Storm", "Telekinetic Throw", "Teleport",
    "Temporal Eddy", "Tenebrous Sense", "Tezirah's Veil", "Thoughtcast",
    "Thunderclap", "Time of the Red Spiral", "Tingle", "Trabe Chalice",
    "Tranquility", "Tremor", "Truffenyi's Rally", "Turmar Illumination", "Uncurse",
    "Universal Solvent", "Unleash", "Veil of Ice", "Vertigo", "Vessel of Salvation",
    "Veteran Insight", "Vigil", "Vigor", "Viscous Solution", "Visions of Darkness",
    "Vitality Healing", "Vivisection", "Voidspell", "Ward Break",
    "Whispers of the Muse", "Whole Displacement", "Will of Winter",
    "Wisdom of the Pack", "Wolf Scent", "Words of the Wind", "Worm's Mist",
    "Y'ntrel Sechra", "Zephyr",
  }
  for _, name in ipairs(spells) do
    TextSubs.elanthipedia(name, SPELL_PRE, SPELL_POST)
  end
end -- settings.textsubs_spell_links

-------------------------------------------------------------------------------
-- Teaching Classes — MikeLC 2/15/2025
-------------------------------------------------------------------------------

TextSubs.add("class on extremely advanced(.*)compared to", "teaching a class on extremely advanced$1more than 130% of")
TextSubs.add("class on advanced(.*)compared to", "teaching a class on advanced$1around 120-130% of")
TextSubs.add("class on intermediate(.*)compared to", "teaching a class on intermediate$1around 110-120% of")
TextSubs.add("class on basic(.*)compared to", "teaching a class on basic$1around 100-110% of")
TextSubs.add("class on simplistic(.*)compared to", "teaching a class on simplistic$1around 90-100% of")
TextSubs.add("class on extremely simplistic(.*)compared to", "teaching a class on extremely simplistic$1less than 90% of")

-------------------------------------------------------------------------------
-- Necromancer Butchery (conditional)
-------------------------------------------------------------------------------

if DRStats.necromancer() then
  local butchery = {
    {"perfect",   "10/10"}, {"flawless",  "9/10"}, {"superior",  "8/10"},
    {"very good", "7/10"},  {"decent",    "6/10"}, {"fair",      "5/10"},
    {"mediocre",  "4/10"},  {"passable",  "3/10"}, {"shoddy",    "2/10"},
    {"poor",      "1/10"},
  }
  for _, e in ipairs(butchery) do
    TextSubs.add("manage to extract a " .. e[1], "manage to extract a " .. e[1] .. " (" .. e[2] .. ")")
  end
end

-------------------------------------------------------------------------------
-- Bard Assessment Part 1 (conditional)
-------------------------------------------------------------------------------

if DRStats.bard() then
  -- Singing assessment (1-7)
  TextSubs.add("unable to remember any more of the song anyway\\.", "unable to remember any more of the song anyway. (1/7)")
  TextSubs.add("but pick it up a moment later and bring it to a strong conclusion\\.", "but pick it up a moment later and bring it to a strong conclusion. (2/7)")
  TextSubs.add("but grin despite that for the ease at which you sang\\.", "but grin despite that for the ease at which you sang. (3/7)")
  TextSubs.add("You bring the song to a close, bowing your head\\.", "You bring the song to a close, bowing your head. (4/7)")
  TextSubs.add(" bowing your head as they come to a close\\.", " bowing your head as they come to a close. (5/7)")
  TextSubs.add("and you raise your chin with pride as it comes to a close\\.", "and you raise your chin with pride as it comes to a close. (6/7)")
  TextSubs.add("you bow your head, your ears ringing in the silence\\.", "you bow your head, your ears ringing in the silence. (7/7)")

  -- Playing assessment (1-10)
  TextSubs.add("the simplest musical phrase in your current state of mind\\.", "the simplest musical phrase in your current state of mind. (1/10)")
  TextSubs.add("feel very sure of your ability to perform just now\\.", "feel very sure of your ability to perform just now. (2/10)")
  TextSubs.add("you give up in exasperation and stop trying to play altogether\\.", "you give up in exasperation and stop trying to play altogether. (3/10)")
  TextSubs.add("you realize that you're not quite up to a true performance\\.", "you realize that you're not quite up to a true performance. (4/10)")
  TextSubs.add("produced from your efforts is both clear and precise\\.", "produced from your efforts is both clear and precise. (5/10)")
  TextSubs.add("displaying the surety you hold in your ability to perform\\.", "displaying the surety you hold in your ability to perform. (6/10)")
  TextSubs.add("adeptness with which you perform your craft is evident in each movement\\.", "adeptness with which you perform your craft is evident in each movement. (7/10)")
  TextSubs.add("skill and confidence of one talented in their craft\\.", "skill and confidence of one talented in their craft. (8/10)")
  TextSubs.add("evocative rhythms you send to float gently upon the air\\.", "evocative rhythms you send to float gently upon the air. (9/10)")
  TextSubs.add("Leth Deriel during the full throes of Spring\\.", "Leth Deriel during the full throes of Spring. (10/10)")

  -- Dancing assessment (1-10)
  TextSubs.add("you decide not to attempt that again, and get back to your feet\\.", "you decide not to attempt that again, and get back to your feet. (1/10)")
  TextSubs.add("but decide that now may not be the best time for dancing\\.", "but decide that now may not be the best time for dancing. (2/10)")
  TextSubs.add("You can't seem to recall what to do next, despite your best efforts\\.", "You can't seem to recall what to do next, despite your best efforts. (3/10)")
  TextSubs.add("entirety of the dance without too much trouble\\.", "entirety of the dance without too much trouble. (4/10)")
  TextSubs.add("dance flawlessly, wrapping up with a flourish\\.", "dance flawlessly, wrapping up with a flourish. (5/10)")
  TextSubs.add("leave you breathless, you wrap up with a flourish\\.", "leave you breathless, you wrap up with a flourish. (6/10)")
  TextSubs.add("reaches its conclusion, a grin lights up your face\\.", "reaches its conclusion, a grin lights up your face. (7/10)")
  TextSubs.add("and when they finally come to rest again, you cannot help but smile\\.", "and when they finally come to rest again, you cannot help but smile. (8/10)")
  TextSubs.add("When you finally come to rest again, you are still smiling\\.", "When you finally come to rest again, you are still smiling. (9/10)")
  TextSubs.add("you wrap up with a flourish and pose, a wide smile upon your face\\.", "you wrap up with a flourish and pose, a wide smile upon your face. (10/10)")
end

-------------------------------------------------------------------------------
-- Moon Mage Shards (conditional)
-------------------------------------------------------------------------------

if DRStats.moon_mage() then
  TextSubs.add("Marendin", "Marendin (Shard)")
  TextSubs.add("Rolagi", "Rolagi (Crossing)")
  TextSubs.add("Asharshpar'i", "Asharshpar'i (Leth Deri'el)")
  TextSubs.add("Dinegavren", "Dinegavren (Therenborough)")
  TextSubs.add("Mintais", "Mintais (Throne City)")
  TextSubs.add("Tamigen", "Tamigen (Raven's Point)")
  TextSubs.add("Taniendar", "Taniendar (Riverhaven)")
  TextSubs.add("Erekinzil", "Erekinzil (Taisgath)")
  TextSubs.add("Auilusi", "Auilusi (Aesry Surlaenis'a)")
  TextSubs.add("Vellano", "Vellano (Fang Cove)")
  TextSubs.add("Tabelrem", "Tabelrem (Muspar'i)")
  TextSubs.add("Dor'na'torna", "Dor'na'torna (Arid Steppe)")
  TextSubs.add("Besoge", "Besoge (Mer'kresh)")
  TextSubs.add("Aevargwem", "Aevargwem (Vela'Tohr Overlook)")
end

-------------------------------------------------------------------------------
-- Herb Substitutions (conditional: settings.herb_textsubs)
-------------------------------------------------------------------------------

if settings.herb_textsubs then
  local herbs = {
    {"nilos",     "abdo-EW"},  {"muljin",    "abdo-IW"},
    {"dioica",    "gen-ES"},   {"belradi",   "gen-IS"},
    {"hulnik",    "back-EW"},  {"junliar",   "back-IW"},
    {"plovik",    "ch-EW"},    {"ithor",     "ch-IW"},
    {"sufil",     "eye-EW"},   {"aevaes",    "eye-IW"},
    {"qun",       "face-ES"},  {"hulij",     "face-IS"},
    {"nemoih",    "head-EW"},  {"eghmok",    "head-IW"},
    {"blocil",    "limb-ES"},  {"jadice",    "limb-ES"},
    {"nuloe",     "limb-IS"},  {"jadice",    "limb-EW"},
    {"yelith",    "limb-IW"},
    {"georin",    "neck-EW"},  {"riolur",    "neck-IW"},
    {"hisan",     "skin-IS"},  {"lujeakave", "skin-IW"},
    {"cebi",      "skin-ES"},  {"aloe",      "skin-EW"},
    {"genich",    "body-ES"},  {"ojhenik",   "body-IS"},
  }
  for _, h in ipairs(herbs) do
    TextSubs.add(h[1], h[1] .. " (" .. h[2] .. ")")
  end
end

-------------------------------------------------------------------------------
-- Social Outrage and Divine Outrage (always active)
-------------------------------------------------------------------------------

TextSubs.add("The citizens of (.*) are growing suspicious of you\\.", "The citizens of $1 are growing suspicious of you. (1/4 - Can still use town services.)")
TextSubs.add("it is widely believed that you are some kind of sorcerer\\.", "it is widely believed that you are some kind of sorcerer. (2/4 - Unable to use most town services. WITHDRAW, SELL, PAY, TRAIN and GET SACK are safe.)")
TextSubs.add("is criminal and the government actively seeks to arrest you\\.", "is criminal and the government actively seeks to arrest you. (3/4 - Unable to use most town services and can be auto-arrested at gates. WITHDRAW, SELL, PAY, TRAIN and GET SACK are safe.)")
TextSubs.add("You are regarded as a monster by the good folk of (.*)\\.", "You are regarded as a monster by the good folk of $1. (4/4 - Unable to use most town services, can be auto-arrested at gates, and posse may hunt you down in province. WITHDRAW, SELL, PAY, TRAIN and GET SACK are safe.)")
TextSubs.add("You feel as if many eyes are judging you and still find you\\.\\.\\. lacking\\.", "You feel as if many eyes are judging you and still find you... lacking. (0/4 - You are still Redeemed.)")
TextSubs.add("As though in response, you are struck by a feeling of insecurity\\.", "As though in response, you are struck by a feeling of insecurity. (1/4 - Low DO)")
TextSubs.add("As though in response, you have a brief, sharp pain in your limbs\\.", "As though in response, you have a brief, sharp pain in your limbs. (2/4 - Medium DO)")
TextSubs.add("As though in response, you feel a deep pain in your chest\\.", "As though in response, you feel a deep pain in your chest. (3/4 - High DO. Slow down on DO generation.)")
TextSubs.add("The experience leaves you feeling naked for all to see\\.", "The experience leaves you feeling naked for all to see. (4/4 - Extreme DO. You are at risk of being smote. Stop generating DO!)")
TextSubs.add("((?:The back of your neck prickles|You feel judged and hated|Muddled thoughts of paranoia nag at you|You are exposed and vulnerable in this place|You have a feeling that you aren't welcome here|You worry for your safety and well-being)\\.)", "$1 (DO gained from being in a Holy area. Move away to avoid this hit.)")
TextSubs.add("(The experience leaves you feeling somehow exposed\\.)", "$1 (Detectable by Moon Mages/Clerics - Use RoC/RoG with enough mana to mask it.)")
TextSubs.add(".*(Joyous corruption seeps into your mind from your own spell, muting your unconscious sense of shame\\.)", "$1 (Your RoC/RoG spell is strong enough to mask your aura from Clerics and Moon Mages.)")
TextSubs.add(".*(You feel a wave of filth wash over you, heralding the renewed health of your internal gauges\\.)", "$1 (You gained some Divine Outrage and your RoC/RoG spell is no longer strong enough to mask your aura from Clerics/Moon Mages. Recast with more mana.)")

-------------------------------------------------------------------------------
-- ASSESS Durability (1-18) — always active
-------------------------------------------------------------------------------

do
  local assess_levels = {
    {"extremely weak and easily damaged",    "1/18"},
    {"very delicate and easily damaged",     "2/18"},
    {"quite fragile and easily damaged",     "3/18"},
    {"rather flimsy and easily damaged",     "4/18"},
    {"particularly weak against damage",     "5/18"},
    {"somewhat unsound against damage",      "6/18"},
    {"appreciably susceptible to damage",    "7/18"},
    {"marginally vulnerable to damage",      "8/18"},
    {"of average construction",              "9/18"},
    {"a bit safeguarded against damage",     "10/18"},
    {"rather reinforced against damage",     "11/18"},
    {"quite guarded against damage",         "12/18"},
    {"highly protected against damage",      "13/18"},
    {"very strong against damage",           "14/18"},
    {"extremely resistant to damage",        "15/18"},
    {"unusually resilient to damage",        "16/18"},
    {"nearly impervious to damage",          "17/18"},
    {"practically invulnerable to damage",   "18/18"},
  }
  for _, e in ipairs(assess_levels) do
    TextSubs.add("Assessing the (.*) durability, you determine (it is|is|they are|are) " .. e[1],
      "Assessing the $1 durability, $2 " .. e[1] .. " (" .. e[2] .. ")")
  end
end

-- Condition % (always active)
do
  local conditions = {
    {"battered and practically destroyed", "0-19%"},
    {"badly damaged",                      "20-29%"},
    {"heavily scratched and notched",      "30-39%"},
    {"several unsightly notches",          "40-49%"},
    {"a few dents and dings",              "50-59%"},
    {"some minor scratches",               "60-69%"},
    {"rather scuffed up",                  "70-79%"},
    {"in good condition",                  "80-89%"},
    {"practically in mint condition",      "90-97%"},
    {"in pristine condition",              "98-100%"},
  }
  for _, e in ipairs(conditions) do
    TextSubs.add(" and (it is|is|they are|are|it has|has|have|contains?) " .. e[1] .. "\\.",
      " and $1 " .. e[1] .. " (" .. e[2] .. ").")
  end
end

-------------------------------------------------------------------------------
-- Appraise Focus Progress (1-4) — always active
-------------------------------------------------------------------------------

TextSubs.add("^You feel like it will be awhile before you make progress\\.", "You feel like it will be awhile before you make progress. (1/4)")
TextSubs.add("^You feel like you have made some progress toward your goal\\.", "You feel like you have made some progress toward your goal. (2/4)")
TextSubs.add("^You feel like you've made good progress toward your goal\\.", "You feel like you've made good progress toward your goal. (3/4)")
TextSubs.add("^You feel like you are on the verge of learning something useful\\.", "You feel like you are on the verge of learning something useful. (4/4)")

-------------------------------------------------------------------------------
-- Hit Quality (0-23) — always active
-- Uses negative lookbehind for glancing blow disambiguation (requires fancy-regex)
-------------------------------------------------------------------------------

TextSubs.add("(a|an) (benign|brushing|gentle|grazing|harmless|ineffective|skimming) (blow|hit|strike)", "$1 $2 (0/23) $3")
-- Correction for "receiving a glancing blow" — don't label that as (0/23)
TextSubs.add("(?<!receiving )(a|an) (glancing) (blow|hit|strike)", "$1 $2 (0/23) $3")
TextSubs.add("a light hit", "a light hit (1/23)")
TextSubs.add("a good hit", "a good hit (2/23)")
TextSubs.add("a good strike", "a good strike (3/23)")
TextSubs.add("a solid hit", "a solid hit (4/23)")
TextSubs.add("a hard hit", "a hard hit (5/23)")
TextSubs.add("a strong hit", "a strong hit (6/23)")
TextSubs.add("a heavy strike", "a heavy strike (7/23)")
TextSubs.add("a very heavy hit", "a very heavy hit (8/23)")
TextSubs.add("an extremely heavy hit", "an extremely heavy hit (9/23)")
TextSubs.add("a powerful strike", "a powerful strike (10/23)")
TextSubs.add("a massive strike", "a massive strike (11/23)")
TextSubs.add("an awesome strike", "an awesome strike (12/23)")
TextSubs.add("a vicious strike", "a vicious strike (13/23)")
TextSubs.add("an earth-shaking strike", "an earth-shaking strike (14/23)")
TextSubs.add("a demolishing hit", "a demolishing hit (15/23)")
TextSubs.add("a spine-rattling strike", "a spine-rattling strike (16/23)")
-- Devastating hit with/without "That'll leave a mark!" (uses negative lookahead)
TextSubs.add("a devastating hit(?! \\(That'll leave a mark!\\))", "a devastating hit (17/23)")
TextSubs.add("a devastating hit \\(That'll leave a mark!\\)", "a devastating hit (That'll leave a mark!) (18/23)")
TextSubs.add("an overwhelming strike", "an overwhelming strike (19/23)")
TextSubs.add("an obliterating hit", "an obliterating hit (20/23)")
TextSubs.add("an annihilating strike", "an annihilating strike (21/23)")
TextSubs.add("a cataclysmic strike", "a cataclysmic strike (22/23)")
TextSubs.add("an apocalyptic strike", "an apocalyptic strike (23/23)")

-------------------------------------------------------------------------------
-- Mana Tuners (conditional: NOT barbarian, thief, moon_mage, or trader)
-------------------------------------------------------------------------------

if not (DRStats.barbarian() or DRStats.thief() or DRStats.moon_mage() or DRStats.trader()) then
  TextSubs.add("streams of cold, white mana chill your core.", "streams of cold, white mana chill your core. (Lunar)")
  TextSubs.add("streams of fiery mana burn through your limbs.", "streams of fiery mana burn through your limbs. (Elemental)")
  TextSubs.add("streams of bluish-white mana flow up your spine.", "streams of bluish-white mana flow up your spine. (Life)")
  TextSubs.add("streams of golden mana echo through your body.", "streams of golden mana echo through your body. (Holy)")
  TextSubs.add("streams of unholy black mana leave you feeling feverish.", "streams of unholy black mana leave you feeling feverish. (Arcane)")
end

-------------------------------------------------------------------------------
-- Cleric Devotion + Osrel Meraud (conditional)
-------------------------------------------------------------------------------

if DRStats.cleric() then
  -- Devotion levels (1-16)
  TextSubs.add("^You feel unclean and unworthy\\.", "You feel unclean and unworthy. (1/16)")
  TextSubs.add("^You close your eyes and start to concentrate\\. In a moment a vision appears of a barren garden, parched and thirsting for nourishment\\. You have an intense desire to tend it\\.", "You close your eyes and start to concentrate. In a moment a vision appears of a barren garden, parched and thirsting for nourishment. You have an intense desire to tend it. (2/16)")
  TextSubs.add("^You call out to your god, but there is no answer\\.", "You call out to your god, but there is no answer. (3/16)")
  TextSubs.add("^After a moment, you sense that your god is barely aware of you\\.", "After a moment, you sense that your god is barely aware of you. (4/16)")
  TextSubs.add("^After a moment, you sense that your efforts have not gone unnoticed\\.", "After a moment, you sense that your efforts have not gone unnoticed. (5/16)")
  TextSubs.add("^After a moment, you sense a distinct link between you and your god\\.", "After a moment, you sense a distinct link between you and your god. (6/16)")
  TextSubs.add("^After a moment, you sense that your god is aware of your devotion\\.", "After a moment, you sense that your god is aware of your devotion. (7/16)")
  TextSubs.add("^After a moment, you sense that your god is pleased with your devotion\\.", "After a moment, you sense that your god is pleased with your devotion. (8/16)")
  TextSubs.add("^After a moment, you sense that your god knows your name\\.", "After a moment, you sense that your god knows your name. (9/16)")
  TextSubs.add("^After a moment, you see a vision of your god, though the visage is cloudy and impossible to make out clearly\\.", "After a moment, you see a vision of your god, though the visage is cloudy and impossible to make out clearly. (10/16)")
  TextSubs.add("^After a moment, you sense a slight pressure on your shoulder, leaving the feeling that your efforts have been acknowledged\\.", "After a moment, you sense a slight pressure on your shoulder, leaving the feeling that your efforts have been acknowledged. (11/16)")
  TextSubs.add("^After a moment, you see a silent vision of your god, radiating forth with a powerful divine brilliance\\.", "After a moment, you see a silent vision of your god, radiating forth with a powerful divine brilliance. (12/16)")
  TextSubs.add('^After a moment, you see a vision of your god who calls to you by name, "Come here, my child, and I will show you things of wonder\\."', 'After a moment, you see a vision of your god who calls to you by name, "Come here, my child, and I will show you things of wonder." (13/16)')
  TextSubs.add('^After a moment, you see a vision of your god who calls to you by name, "My child, though you may not always see my face, I am pleased with thee and thy efforts\\."', 'After a moment, you see a vision of your god who calls to you by name, "My child, though you may not always see my face, I am pleased with thee and thy efforts." (14/16)')
  TextSubs.add('^After a moment, you see a crystal-clear vision of your god who speaks slowly and deliberately, "Your unwavering faith and devotion pleases me greatly, (\\w+)\\.\\s+Go forth and continue your works, and you shall only attain a greater level of purity\\."', 'After a moment, you see a crystal-clear vision of your god who speaks slowly and deliberately, "Your unwavering faith and devotion pleases me greatly, $1.  Go forth, and continue your works and you shall only attain a greater level of purity." (15/16)')
  TextSubs.add("^After a moment, you feel a clear presence like a warm blanket covering you beneath the shade of a giant sana'ati tree\\.", "After a moment, you feel a clear presence like a warm blanket covering you beneath the shade of a giant Sana'ati tree. (16/16)")

  -- Osrel Meraud power (1-10)
  local om_str = "The strength of the sensation evokes the image of"
  local om_power = {
    {"a pile of cold ashes",    "1/10"},
    {"a pile of smoldering ashes", "2/10"},
    {"a nearly burnt-out candle wick", "3/10"},
    {"a half-melted burning candle", "4/10"},
    {"a tall burning candle",   "5/10"},
    {"a blazing torch",         "6/10"},
    {"a small campfire",        "7/10"},
    {"a roaring bonfire",       "8/10"},
    {"flaming magma pouring through a volcanic crevasse", "9/10"},
    {"torrents of fiery rain falling upon Elanthia from the World Dragon's maw", "10/10"},
  }
  for _, e in ipairs(om_power) do
    TextSubs.add("^" .. om_str .. " " .. e[1] .. "\\.", om_str .. " " .. e[1] .. ". (" .. e[2] .. ")")
  end

  -- Osrel Meraud capacity (1-11)
  local om_cap = "The pervasiveness of the sensation evokes the image of"
  local om_capacity = {
    {"a stream in your mind's eye",    "1/11"},
    {"a pond in your mind's eye",      "2/11"},
    {"a river in your mind's eye",     "3/11"},
    {"a lake in your mind's eye",      "4/11"},
    {"a sea in your mind's eye",       "5/11"},
    {"an ocean in your mind's eye",    "6/11"},
    {"Drogor's deeps in your mind's eye", "7/11"},
    {"Elanthia's tides rising toward Katamba in your mind's eye", "8/11"},
    {"the sapphirine planet Merewalda in your mind's eye", "9/11"},
    {"Alamhif's Bridge arching from the cold seas of Death in your mind's eye", "10/11"},
    {"the fathomless ebon abysms of the Starry Road in your mind's eye", "11/11"},
  }
  for _, e in ipairs(om_capacity) do
    TextSubs.add("^" .. om_cap .. " " .. e[1] .. "\\.", om_cap .. " " .. e[1] .. ". (" .. e[2] .. ")")
  end
end

-------------------------------------------------------------------------------
-- Ranger (conditional)
-------------------------------------------------------------------------------

if DRStats.ranger() then
  -- Ranger pace messaging
  TextSubs.add("You glance about the area while pacing back and forth, like a large, stalking mountain cat\\.", "You glance about the area while pacing back and forth, like a large, stalking mountain cat. (extremely wilderness)")
  TextSubs.add("You glide around the area like a crocodile, truly in your element\\.", "You glide around the area like a crocodile, truly in your element. (moderately wilderness)")
  TextSubs.add("You pace back and forth, smiling slightly to yourself at the refreshing familiarity of the area\\.", "You pace back and forth, smiling slightly to yourself at the refreshing familiarity of the area. (moderately wilderness)")
  TextSubs.add("You pace back and forth, scowling slightly at your surroundings\\.", "You pace back and forth, scowling slightly at your surroundings. (moderately urban)")
  TextSubs.add("You pace back and forth like a trapped animal\\.", "You pace back and forth like a trapped animal. (extremely urban)")

  -- Howl (1-15)
  TextSubs.add("^You take in a deep breath to howl, and let loose with a mighty\\.\\.\\. Moo\\?!  The sounds that erupt from within you sound startlingly like the loud bleating of a young heifer giving birth to her first calf\\.", "You take in a deep breath to howl, and let loose with a mighty... Moo?!  The sounds that erupt from within you sound startlingly like the loud bleating of a young heifer giving birth to her first calf. (1/15)")
  TextSubs.add("^You open your mouth to howl, but it sounds more like a dying chicken than anything else\\.", "You open your mouth to howl, but it sounds more like a dying chicken than anything else. (2/15)")
  TextSubs.add("^You give forth a mighty\\.\\.\\. yelp, which sounds more like a domesticated puppy than anything else\\.", "You give forth a mighty... yelp, which sounds more like a domesticated puppy than anything else. (3/15)")
  TextSubs.add("^You open your mouth and roar with everything you've got!  A few soft sounds reminiscent of a baby robin's first song twitter sweetly from within you\\.$", "You open your mouth and roar with everything you've got!  A few soft sounds reminiscent of a baby robin's first song twitter sweetly from within you. (4/15)")
  TextSubs.add('^You open your mouth to howl, but you merely sigh like the softest wind through the trees\\.(\\s+)Sadly, not even a leaf flutters with your "mighty" breath\\.', 'You open your mouth to howl, but you merely sigh like the softest wind through the trees.$1Sadly, not even a leaf flutters with your "mighty" breath. (5/15)')
  TextSubs.add("^You take in a deep breath to howl loudly, but instead cough and choke on the air around you\\.", "You take in a deep breath to howl loudly, but instead cough and choke on the air around you. (6/15)")
  TextSubs.add("^You howl quietly to yourself, echoing a soft, desolate sound that doesn't sound quite right\\.$", "You howl quietly to yourself, echoing a soft, desolate sound that doesn't sound quite right. (7/15)")
  TextSubs.add("^You take in a deep breath to howl, but it comes out as a whimper, like a lost wolf looking for his pack\\.", "You take in a deep breath to howl, but it comes out as a whimper, like a lost wolf looking for his pack. (8/15)")
  TextSubs.add("^You howl meekly, unsure of yourself\\.", "You howl meekly, unsure of yourself. (9/15)")
  TextSubs.add("^You take in a deep breath of air and howl softly\\.", "You take in a deep breath of air and howl softly. (10/15)")
  TextSubs.add("^You open your mouth and throw back your head, howling with a tentative but fairly resonant tone that wavers only slightly\\.", "You open your mouth and throw back your head, howling with a tentative but fairly resonant tone that wavers only slightly. (11/15)")
  TextSubs.add("^You howl like a wolf calling the pack!", "You howl like a wolf calling the pack! (12/15)")
  TextSubs.add("^You inhale and howl strongly, the cacophonous sounds reverberating around you\\.", "You inhale and howl strongly, the cacophonous sounds reverberating around you. (13/15)")
  TextSubs.add("^You howl strongly, like that of a wolf calling its kin to assemble for a hunt\\.(\\s+)The sound echoes commandingly through the area\\.", "You howl strongly, like that of a wolf calling its kin to assemble for a hunt.$1The sound echoes commandingly through the area. (14/15)")
  TextSubs.add("^You inhale deeply, a resounding howl breaking forth from within you, resonating strongly into the distance as if to announce your mastery of the wilds!", "You inhale deeply, a resounding howl breaking forth from within you, resonating strongly into the distance as if to announce your mastery of the wilds! (15/15)")

  -- Silent stock (2-15)
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel like a true master of the wilds!", "Taking silent stock of your connection to the natural world, you feel like a true master of the wilds! (15/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel in command of the wilds.", "Taking silent stock of your connection to the natural world, you feel in command of the wilds. (14/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel strongly connected to the wilds.", "Taking silent stock of your connection to the natural world, you feel strongly connected to the wilds. (13/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel like a wolf among sheep.", "Taking silent stock of your connection to the natural world, you feel like a wolf among sheep. (12/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel your connection to the wilds wavering slightly.", "Taking silent stock of your connection to the natural world, you feel your connection to the wilds wavering slightly. (11/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel a strain in your connection to the wilds.", "Taking silent stock of your connection to the natural world, you feel a strain in your connection to the wilds. (10/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel unsure of yourself.", "Taking silent stock of your connection to the natural world, you feel unsure of yourself. (9/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel like a lost wolf looking for its pack.", "Taking silent stock of your connection to the natural world, you feel like a lost wolf looking for its pack. (8/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel desolate and not quite right.", "Taking silent stock of your connection to the natural world, you feel desolate and not quite right. (7/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel choked by the clutches of civilization.", "Taking silent stock of your connection to the natural world, you feel choked by the clutches of civilization. (6/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel aimless and adrift in life.", "Taking silent stock of your connection to the natural world, you feel aimless and adrift in life. (5/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel as vulnerable as a baby robin, dependent upon others for its security.", "Taking silent stock of your connection to the natural world, you feel as vulnerable as a baby robin, dependent upon others for its security. (4/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel practically domesticated.", "Taking silent stock of your connection to the natural world, you feel practically domesticated. (3/15)")
  TextSubs.add("^Taking silent stock of your connection to the natural world, you feel like just another face in the crowd.", "Taking silent stock of your connection to the natural world, you feel like just another face in the crowd. (2/15)")
end

-------------------------------------------------------------------------------
-- Empath (conditional)
-------------------------------------------------------------------------------

if DRStats.empath() then
  -- Healing levels (1-6)
  TextSubs.add("leaving (.*) slightly healed",      "leaving $1 slightly (1/6) healed")
  TextSubs.add("leaving (.*) moderately healed",     "leaving $1 moderately (2/6) healed")
  TextSubs.add("leaving (.*) considerably healed",   "leaving $1 considerably (3/6) healed")
  TextSubs.add("leaving (.*) greatly healed",        "leaving $1 greatly (4/6) healed")
  TextSubs.add("leaving (.*) immensely healed",      "leaving $1 immensely (5/6) healed")
  TextSubs.add("leaving (.*) completely healed",     "leaving $1 completely (6/6) healed")

  -- Presence sensing
  TextSubs.add("An unidentifiable presence\\.", "An unidentifiable presence. (hidden non-Empath)")
  TextSubs.add("The presence of (\\w+), whose life essence is wavering\\.", "The presence of $1, whose life essence is wavering. (vitality <50%)")
  TextSubs.add("The presence of (\\w+), whose life essence is almost extinguished\\.", "The presence of $1, whose life essence is almost extinguished. (vitality <20%)")
  TextSubs.add("The presence of (\\w+)\\.  You also sense disturbing black streaks about (\\w+) life essence\\.", "The presence of $1.  You also sense disturbing black streaks about $2 life essence. (diseased)")
  TextSubs.add("The presence of (\\w+)\\.  You also sense a faint greenish tinge about (\\w+) life essence\\.", "The presence of $1.  You also sense a faint greenish tinge about $2 life essence. (poisoned)")
  TextSubs.add("The presence of (\\w+), a fellow Empath, whose life essence is wavering\\.", "The presence of $1, a fellow Empath, whose life essence is wavering. (vitality <50%)")
  TextSubs.add("The presence of (\\w+), a fellow Empath, whose life essence is almost extinguished\\.", "The presence of $1, a fellow Empath, whose life essence is almost extinguished. (vitality <20%)")
  TextSubs.add("The presence of (\\w+), a fellow Empath\\.  You also sense disturbing black streaks about (\\w+) life essence\\.", "The presence of $1, a fellow Empath.  You also sense disturbing black streaks about $2 life essence. (diseased)")
  TextSubs.add("The presence of (\\w+), a fellow Empath\\.  You also sense a faint greenish tinge about (\\w+) life essence\\.", "The presence of $1, a fellow Empath.  You also sense a faint greenish tinge about $2 life essence. (poisoned)")
  TextSubs.add("The presence of a secondary shadow about yourself\\.", "The presence of a secondary shadow about yourself. (parasite)")
  TextSubs.add("A relatively healthy presence nearby\\.", "A relatively healthy presence nearby. (critter)")
  TextSubs.add("A wavering life essence nearby\\.", "A wavering life essence nearby. (critter with vitality <50%)")
  TextSubs.add("A malicious presence screeching in the far dark corner of your mind causes you to quickly open your eyes!", "A malicious presence screeching in the far dark corner of your mind causes you to quickly open your eyes! (undead/cursed critter)")

  -- Healing progress (1-7)
  TextSubs.add("^You sense you are just at the beginning of",       "You sense you are just at the beginning of (1/7)")
  TextSubs.add("^You sense you are only a short way through",       "You sense you are only a short way through (2/7)")
  TextSubs.add("^You sense you are a fair portion of the way through with", "You sense you are a fair portion of the way through with (3/7)")
  TextSubs.add("^You sense you are half-way done with",             "You sense you are half-way done with (4/7)")
  TextSubs.add("^You sense you are a good portion of the way through with", "You sense you are a good portion of the way through with (5/7)")
  TextSubs.add("^You sense you are almost done with",               "You sense you are almost done with (6/7)")
  TextSubs.add("^You sense you are on the verge of completing",     "You sense you are on the verge of completing (7/7)")

  -- Damage transfer severity (1-13)
  local damage_transfer = {
    "insignificant", "negligible", "minor", "more than minor", "harmful",
    "very harmful", "damaging", "very damaging", "severe", "very severe",
    "devastating", "very devastating", "useless",
  }
  for i, w in ipairs(damage_transfer) do
    TextSubs.add("\\-\\- " .. w, "-- " .. w .. " (" .. i .. "/13)")
  end

  -- Plant condition (0-5)
  TextSubs.add("^The plant appears to be in good condition", "The plant appears to be in good condition (5/5)")
  TextSubs.add("^The plant has some scrapes and discolorations along the leaves and stem", "The plant has some scrapes and discolorations along the leaves and stem (4/5)")
  TextSubs.add("^The plant has several torn leaves, and the main stem bears some cuts that are leaking green sap", "The plant has several torn leaves, and the main stem bears some cuts that are leaking green sap (3/5)")
  TextSubs.add("^The plant shivers periodically, torn leaves and broken stems hanging limply as sap drips from its wounds", "The plant shivers periodically, torn leaves and broken stems hanging limply as sap drips from its wounds (2/5)")
  TextSubs.add("^The plant has pulled into itself under shredded leaves and oozing stems", "The plant has pulled into itself under shredded leaves and oozing stems (1/5)")
  TextSubs.add("^The plant has coiled itself into a tight ball, the remains of its shredded leaves sticking to sap encrusted stems", "The plant has coiled itself into a tight ball, the remains of its shredded leaves sticking to sap encrusted stems (0/5)")

  -- Companion vitality (0-9)
  TextSubs.add("Your (.*)'s life force is brimming with unblemished vigor!", "Your $1's life force is brimming with unblemished vigor! (0/9)")
  TextSubs.add("Your (.*)'s life force remains unblemished save for a single, tiny deadened speck.", "Your $1's life force remains unblemished save for a single, tiny deadened speck. (1/9)")
  TextSubs.add("Your (.*)'s life force remains largely robust, though several small deadened areas have formed.", "Your $1's life force remains largely robust, though several small deadened areas have formed. (2/9)")
  TextSubs.add("Your (.*)'s life force is still mostly strong, though it shows more than the occasional deadened area.", "Your $1's life force is still mostly strong, though it shows more than the occasional deadened area. (3/9)")
  TextSubs.add("Your (.*)'s life force displays interwoven strands connecting each of the deadened areas within.", "Your $1's life force displays interwoven strands connecting each of the deadened areas within. (4/9)")
  TextSubs.add("Your (.*)'s life force is pulsing between vigor and numbness.", "Your $1's life force is pulsing between vigor and numbness. (5/9)")
  TextSubs.add("Your (.*)'s life force is waning, the strands connecting its deadened areas growing more numerous.", "Your $1's life force is waning, the strands connecting its deadened areas growing more numerous. (6/9)")
  TextSubs.add("Your (.*)'s life force is significantly weakened, with large portions of it numbed and deadened completely.", "Your $1's life force is significantly weakened, with large portions of it numbed and deadened completely. (7/9)")
  TextSubs.add("Your (.*)'s life force is imperceptible.", "Your $1's life force is imperceptible. (8/9)")
  TextSubs.add("You thumb your (.*)\\.", "You thumb your $1. (9/9)")
end

-------------------------------------------------------------------------------
-- Crafting Quality (2-12) — always active
-------------------------------------------------------------------------------

TextSubs.add("(is|are)( of|) masterfully-crafted( quality|)", "$1$2 masterfully-crafted (12/12)$3")
TextSubs.add("(is|are)( of|) outstanding( quality|)", "$1$2 outstanding (11/12)$3")
TextSubs.add("(is|are)( of|) exceptional( quality|[^l]+)", "$1$2 exceptional (10/12)$3")
TextSubs.add("(is|are)( of|) superior( quality|)", "$1$2 superior (9/12)$3")
TextSubs.add("(is|are)( of|) finely-crafted( quality|)", "is finely-crafted (8/12)$3")
TextSubs.add("(is|are)( of|) well-crafted( quality|)", "is well-crafted (7/12)$3")
TextSubs.add("(is|are)( of|) above-average( quality|)", "$1$2 above-average (6/12)$3")
TextSubs.add("(is|are)( of|) about average( quality|)", "$1$2 about average (5/12)$3")
TextSubs.add("(is|are)( of|) mediocre( quality|)", "$1$2 mediocre (4/12)$3")
TextSubs.add("(is|are)( of|) below-average( quality|)", "$1$2 below-average (3/12)$3")
TextSubs.add("(is|are)( of|) poorly-crafted( quality|)", "is poorly-crafted (2/12)$3")
-- TextSubs.add("(is|are)( of|) dismal( quality|)", "$1$2 dismal (1/12)$3")  -- commented in original

-------------------------------------------------------------------------------
-- Crafting Speed (1-11) — always active
-------------------------------------------------------------------------------

do
  local speed = {
    {"tremendously effective",   "11/11"}, {"extremely effective",     "10/11"},
    {"exceptionally effective",  "9/11"},  {"very effective",          "8/11"},
    {"rather effective",         "7/11"},  {"sort of effective",       "6/11"},
    {"not very effective",       "5/11"},  {"very ineffective",        "4/11"},
    {"extremely ineffective",    "3/11"},  {"tremendously ineffective","2/11"},
    {"completely ineffective",   "1/11"},
  }
  for _, e in ipairs(speed) do
    TextSubs.add("be " .. e[1] .. " at increasing crafting speed", "be " .. e[1] .. " (" .. e[2] .. ") at increasing crafting speed")
  end
end

-------------------------------------------------------------------------------
-- Mining/Lumberjacking Resources (0-5) — always active
-------------------------------------------------------------------------------

TextSubs.add("enormous (quantity|number) remains to be found", "enormous $1 (5/5) remains to be found")
TextSubs.add("substantial (quantity|number) remains to be found", "substantial $1 (4/5) remains to be found")
TextSubs.add("good (quantity|number) remains to be found", "good $1 (3/5) remains to be found")
TextSubs.add("decent (quantity|number) remains to be found", "decent $1 (2/5) remains to be found")
TextSubs.add("small (quantity|number) remains to be found", "small $1 (1/5) remains to be found")
TextSubs.add("scattering of (resources|trees) remains to be found", "scattering of $1 (0/5) remains to be found")

-------------------------------------------------------------------------------
-- Encumbrance (0-11) — always active
-------------------------------------------------------------------------------

do
  local enc = {
    {"None",                       "0/11"},  {"Light Burden",              "1/11"},
    {"Somewhat Burdened",          "2/11"},  {"Burdened",                  "3/11"},
    {"Heavy Burden",               "4/11"},  {"Very Heavy Burden",         "5/11"},
    {"Overburdened",               "6/11"},  {"Very Overburdened",         "7/11"},
    {"Extremely Overburdened",     "8/11"},  {"Tottering Under Burden",    "9/11"},
    {"Are you even able to move?", "10/11"},
  }
  for _, e in ipairs(enc) do
    TextSubs.add("Encumbrance : " .. e[1], "Encumbrance : " .. e[1] .. " (" .. e[2] .. ")")
  end
  TextSubs.add("Encumbrance : It's amazing you aren't squashed!", "Encumbrance : It's amazing you aren't squashed! (11/11)")
end

-------------------------------------------------------------------------------
-- Combat Inspiration (0-3) — always active
-------------------------------------------------------------------------------

TextSubs.add("You feel completely empty and unable to grasp inspiration\\.", "You feel completely empty and unable to grasp inspiration (0/3).")
TextSubs.add("You feel depleted and less than inspired\\.", "You feel depleted and less than inspired (1/3).")
TextSubs.add("You feel worn but still ready to meet a challenge\\.", "You feel worn but still ready to meet a challenge (2/3).")
TextSubs.add("You feel ready to defeat all challengers\\.", "You feel ready to defeat all challengers (3/3).")

-------------------------------------------------------------------------------
-- Thief (conditional)
-------------------------------------------------------------------------------

if DRStats.thief() then
  -- Steal difficulty (1-13)
  local steal = {
    "it would be taking candy from a baby",
    "it would be stealable even with your eyes closed",
    "it should be trivial for one of your skills",
    "it should be an easy target for you",
    "it should not prove difficult for you",
    "it should be more likely liftable than not",
    "it should be about even odds",
    "it may give you some difficulty to lift",
    "it may be troublesome to lift",
    "you don't think well of your chances to lift it",
    "it may be quite the struggle to nab",
    "it would likely be futile to bother",
    "you can already feel the taste of bitter failure",
  }
  for i, w in ipairs(steal) do
    TextSubs.add(w .. "\\.", w .. " (" .. i .. "/13).")
  end

  -- Conceal difficulty (1-13)
  local conceal = {
    "nobody will ever miss it",
    "you could just waltz on out with it",
    "it should be trivial to avoid attention",
    "it should be easy to avoid attention",
    "it should not prove too difficult",
    "it should be possible",
    "it's about even odds",
    "perhaps it's a little risky",
    "it'll be troublesome to be unnoticed",
    "it's somewhat of a long shot",
    "you're pretty sure you'll be caught",
    "the shopkeep is paying far too much attention to it",
    "the heavy *THUD* of a judge's gavel echoes through your mind",
  }
  for i, w in ipairs(conceal) do
    TextSubs.add(w .. "\\.", w .. " (" .. i .. "/13).")
  end

  -- Shopkeep attention (1-6)
  local shopkeep = {
    "shouldn't really affect you",
    "hinders your chances slightly",
    "has closer eye on you",
    "looks your way suspiciously",
    "looking for an excuse to call the guards",
    "beyond foolish to keep at it",
  }
  for i, w in ipairs(shopkeep) do
    TextSubs.add(w .. "\\.", w .. " (" .. i .. "/6).")
  end

  -- Confidence (-5 to 5)
  TextSubs.add("don't see how things could get any worse\\.", "don't see how things could get any worse (-5/5).")
  TextSubs.add("but you know you aren't fooling anyone\\.", "but you know you aren't fooling anyone (-4/5).")
  TextSubs.add("but cannot shake the thoughts of your recent screw-ups\\.", "but cannot shake the thoughts of your recent screw-ups (-3/5).")
  TextSubs.add("but have to force it\\.", "but have to force it (-2/5).")
  TextSubs.add("but feel slightly uncomfortable\\.", "but feel slightly uncomfortable (-1/5).")
  TextSubs.add("but can only muster up average confidence\\.", "but can only muster up average confidence (0/5).")
  TextSubs.add("feeling a little above average\\.", "feeling a little above average (1/5).")
  TextSubs.add("feeling rather confident about things\\.", "feeling rather confident about things (2/5).")
  TextSubs.add("feeling quite good about how you're doing\\.", "feeling quite good about how you're doing (3/5).")
  TextSubs.add("the way only a stylish Thief can\\.", "the way only a stylish Thief can (4/5).")
  TextSubs.add("knowing you are at the absolute top of your game\\.", "knowing you are at the absolute top of your game (5/5).")
end

-------------------------------------------------------------------------------
-- Warrior Mage (conditional)
-------------------------------------------------------------------------------

if DRStats.warrior_mage() then
  -- Elemental conditions/surroundings (-5 to 5)
  local wm_cond = {
    {"overwhelmingly favorable",    "5/5"},  {"strongly favorable",          "4/5"},
    {"favorable",                   "3/5"},  {"moderately favorable",        "2/5"},
    {"slightly favorable",          "1/5"},  {"neutral",                     "0/5"},
    {"overwhelmingly detrimental", "-5/5"},  {"strongly detrimental",       "-4/5"},
    {"detrimental",                "-3/5"},  {"moderately detrimental",     "-2/5"},
    {"slightly detrimental",       "-1/5"},
  }
  for _, e in ipairs(wm_cond) do
    TextSubs.add("(conditions|surroundings) are " .. e[1], "$1 are " .. e[1] .. " (" .. e[2] .. ")")
  end
  -- Cold-based Water spells conditions
  for _, e in ipairs(wm_cond) do
    TextSubs.add("cold-based Water spells and " .. e[1], "cold-based Water spells and " .. e[1] .. " (" .. e[2] .. ")")
  end

  -- Charge levels (1-12)
  TextSubs.add("You sense nothing out of the ordinary\\.  Only magic could detect the useless trace of (.*) still in your system\\.", "You sense nothing out of the ordinary. Only magic could detect the useless trace of $1 still in your system. (1/12)")
  TextSubs.add("A small charge lingers within your body, just above the threshold of perception\\.", "A small charge lingers within your body, just above the threshold of perception. (2/12)")
  TextSubs.add("A small charge lingers within your body\\.", "A small charge lingers within your body. (3/12)")
  TextSubs.add("A charge dances through your body\\.", "A charge dances through your body. (4/12)")
  TextSubs.add("A charge dances just below the threshold of discomfort\\.", "A charge dances just below the threshold of discomfort. (5/12)")
  TextSubs.add("A charge circulates through your body, causing a low hum to vibrate through your bones\\.", "A charge circulates through your body, causing a low hum to vibrate through your bones. (6/12)")
  TextSubs.add("Elemental essence floats freely within your body, leaving little untouched\\.", "Elemental essence floats freely within your body, leaving little untouched. (7/12)")
  TextSubs.add("Elemental essence has infused every inch of your body\\.  While you could contain more, you'd do so at the risk of your health\\.", "Elemental essence has infused every inch of your body.  While you could contain more, you'd do so at the risk of your health. (8/12)")
  TextSubs.add("Extraplanar power crackles within your body, leaving you feeling mildly feverish\\.", "Extraplanar power crackles within your body, leaving you feeling mildly feverish. (9/12)")
  TextSubs.add("Extraplanar power crackles within your body, leaving you feeling acutely ill\\.", "Extraplanar power crackles within your body, leaving you feeling acutely ill. (10/12)")
  TextSubs.add("Your body sings and crackles with a barely contained charge, destroying what little cenesthesia you had left\\.", "Your body sings and crackles with a barely contained charge, destroying what little cenesthesia you had left. (11/12)")
  TextSubs.add("You have reached the limits of your body's capacity to store a charge\\.  The laws of the Elemental Plane of (.*) scream demands upon your physiology, threatening your life\\.", "You have reached the limits of your body's capacity to store a charge.  The laws of the Elemental Plane of $1 scream demands upon your physiology, threatening your life. (12/12)")
end

-------------------------------------------------------------------------------
-- Paladin (conditional)
-------------------------------------------------------------------------------

if DRStats.paladin() then
  -- Soul State
  TextSubs.add("gleams brightly with a pristine luminescence!", "gleams brightly with a pristine luminescence (7/7)!")
  TextSubs.add("emits a pure white light!", "emits a pure white light (6/7)!")
  TextSubs.add("turns a steady white hue!", "turns a steady white hue (5/7)!")
  TextSubs.add("dull, chalky color\\.", "dull, chalky color (4/7).")
  TextSubs.add("pallid grey", "pallid grey (3/7)")
  TextSubs.add("sinister black streaks\\.", "sinister black streaks (2/7).")

  -- Soul Pool (1-11)
  TextSubs.add("It brightens with a powerful inner light that, somehow, manages to not cast shadows\\.", "It brightens with a powerful inner light that, somehow, manages to not cast shadows (11/11).")
  TextSubs.add("It brightens with a powerful inner light, which lingers before returning to its normal state\\.", "It brightens with a powerful inner light, which lingers before returning to its normal state (10/11).")
  TextSubs.add("It brightens with an inner light, which lingers for a few moments before returning to its normal state\\.", "It brightens with an inner light, which lingers for a few moments before returning to its normal state (9/11).")
  TextSubs.add("It brightens with an inner light, which lingers for a moment\\.", "It brightens with an inner light, which lingers for a moment (8/11).")
  TextSubs.add("It pulses rapidly with an inner light\\.", "It pulses rapidly with an inner light. (7/11).")
  TextSubs.add("It pulses with an inner light\\.", "It pulses with an inner light (6/11).")
  TextSubs.add("It pulses briefly with an inner light\\.", "It pulses briefly with an inner light (5/11).")
  TextSubs.add("It flickers with an inner light\\.", "It flickers with an inner light (4/11).")
  TextSubs.add("It briefly flickers with an inner light\\.", "It briefly flickers with an inner light (3/11).")
  TextSubs.add("You catch the faintest flicker of light\\.", "You catch the faintest flicker of light. (2/11).")
  TextSubs.add("You believe you catch the faintest flicker of light. You might have imagined it\\.", "You believe you catch the faintest flicker of light. You might have imagined it (1/11).")
end

-------------------------------------------------------------------------------
-- Bard Assessment Part 2 (conditional)
-------------------------------------------------------------------------------

if DRStats.bard() then
  TextSubs.add("You stop only after those first few lines, however, unable to remember any more\\.", "You stop only after those first few lines, however, unable to remember any more (1/7).")
  TextSubs.add("Your voice cracks on the second line, however, and you stop, unable to remember any more of the song anyway\\.", "Your voice cracks on the second line, however, and you stop, unable to remember any more of the song anyway (1/7).")
  TextSubs.add("At one point you hesitate as you mentally grasp for the next line of the song, and stop in confusion, but pick it up a moment later and bring it to a strong conclusion\\.", "At one point you hesitate as you mentally grasp for the next line of the song, and stop in confusion, but pick it up a moment later and bring it to a strong conclusion (2/7).")
  TextSubs.add("You feel a bit tired as you finish, but grin despite that for the ease at which you sang\\.", "You feel a bit tired as you finish, but grin despite that for the ease at which you sang (3/7).")
  TextSubs.add("You bring the song to a close, bowing your head\\.", "You bring the song to a close, bowing your head (4/7).")
  TextSubs.add("Your voice carries strongly on the air as you effortlessly recite the Common words so that all may hear, bowing your head as they come to a close\\.", "Your voice carries strongly on the air as you effortlessly recite the Common words so that all may hear, bowing your head as they come to a close (5/7).")
  TextSubs.add("Tears fill your eyes as the emotion of your ancient aire grips you, and you raise your chin with pride as it comes to a close\\.", "Tears fill your eyes as the emotion of your ancient aire grips you, and you raise your chin with pride as it comes to a close (6/7).")
  TextSubs.add("When the song finally comes to a close, you bow your head, your ears ringing in the silence\\.", "When the song finally comes to a close, you bow your head, your ears ringing in the silence (7/7).")
end

-------------------------------------------------------------------------------
-- Spell Recognition (~240 entries) — always active
-------------------------------------------------------------------------------

do
  local SR = "^(You recognize the familiar mnemonics|You decipher the telltale signs) of the"
  local spell_rec = {
    -- Analogous Patterns
    {"Strange Arrow", "Analogous Patterns: introductory targeted"},
    {"Burden", "Analogous Patterns: introductory debilitation"},
    {"Lay Ward|Manifest Force", "Analogous Patterns: basic warding"},
    {"Ease Burden", "Analogous Patterns: introductory augmentation"},
    {"Dispel|Imbue", "Analogous Patterns: intermediate utility"},
    {"Seal Cambrinth|Gauge Flow", "Analogous Patterns: basic utility"},
    -- Cleric (Divine Intervention)
    {"Glythtide's Gift", "Cleric (Divine Intervention): basic augmentation"},
    {"Aesrela Everild", "signature Cleric (Divine Intervention): intermediate targeted"},
    {"Fire of Ushnish", "signature Cleric (Divine Intervention): advanced targeted"},
    {"Resurrection", "signature Cleric (Divine Intervention): intermediate utility"},
    {"Murrula's Flames", "signature Cleric (Divine Intervention): advanced utility"},
    -- Cleric (Holy Defense)
    {"Protection from Evil|Minor Physical Protection|Soul Shield", "Cleric (Holy Defense): basic warding"},
    {"Ghost Shroud", "Cleric (Holy Defense): intermediate warding"},
    {"Major Physical Protection", "Cleric (Holy Defense): basic augmentation"},
    {"Halo", "signature Cleric (Holy Defense): advanced debilitation/warding"},
    {"Sanyu Lyba", "signature Cleric (Holy Defense): advanced warding"},
    {"Benediction", "signature Cleric (Holy Defense): intermediate augmentation"},
    {"Shield of Light", "signature Cleric (Holy Defense): intermediate augmentation/utility"},
    -- Cleric (Holy Evocations)
    {"Harm Evil|Horn of the Black Unicorn|Fists of Faenella", "Cleric (Holy Evocations): basic targeted"},
    {"Hand of Tenemlor", "Cleric (Holy Evocations): intermediate targeted"},
    {"Phelim's Sanction|Curse of Zachriedek|Malediction", "Cleric (Holy Evocations): intermediate debilitation"},
    {"Bless", "Cleric (Holy Evocations): introductory utility"},
    {"Divine Radiance", "Cleric (Holy Evocations): basic utility"},
    {"Harm Horde", "signature Cleric (Holy Evocations): intermediate targeted"},
    {"Hydra Hex", "signature Cleric (Holy Evocations): advanced debilitation"},
    -- Cleric (Metamagic)
    {"Huldah's Pall", "Cleric (Metamagic): basic debilitation"},
    {"Sanctify Pattern", "Cleric (Metamagic): basic augmentation"},
    {"Uncurse", "Cleric (Metamagic): basic utility"},
    {"Meraud's Cry", "signature Cleric (Metamagic): intermediate debilitation"},
    {"Spite of Dergati", "signature Cleric (Metamagic): advanced debilitation/warding"},
    {"Idon's Theft", "signature Cleric (Metamagic): advanced debilitation/utility"},
    {"Persistence of Mana", "signature Cleric (Metamagic): intermediate augmentation"},
    {"Osrel Meraud", "signature Cleric (Metamagic): advanced utility"},
    -- Cleric (Spirit Manipulation)
    {"Chill Spirit", "Cleric (Spirit Manipulation): intermediate targeted"},
    {"Soul Sickness", "Cleric (Spirit Manipulation): basic debilitation"},
    {"Auspice", "Cleric (Spirit Manipulation): basic augmentation"},
    {"Centering", "Cleric (Spirit Manipulation): introductory augmentation"},
    {"Vigil", "Cleric (Spirit Manipulation): basic utility"},
    {"Revelation", "Cleric (Spirit Manipulation): intermediate utility"},
    {"Soul Attrition", "signature Cleric (Spirit Manipulation): intermediate targeted"},
    {"Soul Bonding", "signature Cleric (Spirit Manipulation): basic debilitation"},
    {"Rejuvenation", "signature Cleric (Spirit Manipulation): basic utility"},
    {"Mass Rejuvenation|Eylhaar's Feast", "signature Cleric (Spirit Manipulation): intermediate utility"},
    {"Bitter Feast", "signature Cleric (Metamagic): advanced utility"},
    -- Paladin (Inspiration)
    {"Soldier's Prayer", "Paladin (Inspiration): intermediate warding"},
    {"Courage|Righteous Wrath|Divine Guidance|Sentinel's Resolve", "Paladin (Inspiration): basic augmentation"},
    {"Heroic Strength", "Paladin (Inspiration): introductory augmentation"},
    {"Anti-Stun", "Paladin (Inspiration): intermediate utility"},
    {"Marshal Order", "signature Paladin (Inspiration): intermediate augmentation"},
    {"Truffenyi's Rally", "signature Paladin (Inspiration): advanced augmentation/utility"},
    {"Divine Armor|Bond Armaments", "signature Paladin (Inspiration): intermediate utility"},
    -- Paladin (Justice)
    {"Rebuke", "Paladin (Justice): intermediate targeted"},
    {"Smite Horde", "Paladin (Justice): advanced targeted"},
    {"Footman's Strike", "Paladin (Justice): basic targeted"},
    {"Halt|Shatter", "Paladin (Justice): basic debilitation"},
    {"Stun Foe", "Paladin (Justice): introductory debilitation"},
    {"Clarity", "Paladin (Justice): intermediate augmentation"},
    {"Hands of Justice", "Paladin (Justice): basic utility"},
    {"Rutilor's Edge", "Paladin (Justice): intermediate utility"},
    {"Holy Warrior", "signature Paladin (Justice): advanced warding/utility"},
    {"Banner of Truce", "signature Paladin (Justice): intermediate utility"},
    -- Paladin (Sacrifice)
    {"Aspirant's Aegis", "Paladin (Sacrifice): introductory warding"},
    {"Crusader's Challenge", "signature Paladin (Sacrifice): advanced augmentation/utility"},
    {"Alamhif's Gift", "signature Paladin (Sacrifice): advanced utility"},
    {"Vessel of Salvation", "signature Paladin (Sacrifice): basic utility"},
    -- Empath (Body Purification)
    {"Blood Staunching", "Empath (Body Purification): basic utility"},
    {"Flush Poisons|Cure Disease|Heart Link|Absolution", "signature Empath (Body Purification): intermediate utility"},
    -- Empath (Healing)
    {"Vitality Healing", "signature Empath (Healing): basic utility"},
    {"Heal Wounds|Heal Scars", "signature Empath (Healing): introductory utility"},
    {"Heal", "signature Empath (Healing): intermediate utility"},
    {"Regenerate|Fountain of Creation", "signature Empath (Healing): advanced utility"},
    -- Empath (Life Force Manipulation)
    {"Paralysis", "Empath (Life Force Manipulation): basic targeted"},
    {"Lethargy", "Empath (Life Force Manipulation): basic debilitation"},
    {"Refresh", "Empath (Life Force Manipulation): introductory augmentation"},
    {"Gift of Life", "Empath (Life Force Manipulation): basic augmentation"},
    {"Vigor", "Empath (Life Force Manipulation): intermediate augmentation"},
    {"Raise Power", "Empath (Life Force Manipulation): intermediate utility"},
    -- Empath (Mental Preparation)
    {"Compel", "Empath (Mental Preparation): intermediate debilitation"},
    {"Mental Focus", "Empath (Mental Preparation): basic augmentation"},
    {"Awaken", "Empath (Mental Preparation): intermediate utility"},
    {"Nissa's Binding", "signature Empath (Mental Preparation): intermediate debilitation"},
    {"Circle of Sympathy", "signature Empath (Mental Preparation): intermediate utility"},
    -- Empath (Protection)
    {"Iron Constitution", "Empath (Protection): basic warding"},
    {"Aggressive Stance", "Empath (Protection): basic augmentation"},
    {"Aesandry Darlaeth", "Empath (Protection): advanced augmentation/utility"},
    {"Innocence", "Empath (Protection): basic utility"},
    {"Perseverance of Peri'el", "signature Empath (Protection): advanced warding"},
    {"Guardian Spirit", "signature Empath (Protection): advanced utility"},
    {"Tranquility", "Empath (Protection; Mental Preparation): intermediate warding/augmentation"},
    -- Ranger (Animal Abilities)
    {"Grizzly Claws", "Ranger (Animal Abilities): intermediate debilitation"},
    {"Wolf Scent|Instinct|Senses of the Tiger", "Ranger (Animal Abilities): basic augmentation"},
    {"See the Wind", "Ranger (Animal Abilities): introductory augmentation"},
    {"Wisdom of the Pack", "Ranger (Animal Abilities): intermediate augmentation"},
    {"Cheetah Swiftness", "signature Ranger (Animal Abilities): advanced augmentation"},
    {"Claws of the Cougar", "signature Ranger (Animal Abilities): intermediate augmentation"},
    {"Bear Strength", "signature Ranger (Animal Abilities): advanced augmentation/utility"},
    -- Ranger (Nature Manipulation)
    {"Eagle's Cry", "Ranger (Nature Manipulation): introductory targeted"},
    {"Devitalize", "Ranger (Nature Manipulation): intermediate targeted"},
    {"Stampede|Carrion Call", "Ranger (Nature Manipulation): basic targeted"},
    {"Swarm", "Ranger (Nature Manipulation): intermediate debilitation"},
    {"Harawep's Bonds|Deadfall", "Ranger (Nature Manipulation): basic debilitation"},
    {"Curse of the Wilds", "Ranger (Nature Manipulation): advanced debilitation"},
    {"Compost", "Ranger (Nature Manipulation): introductory utility"},
    {"Devolve", "signature Ranger (Nature Manipulation): intermediate debilitation"},
    {"Awaken Forest", "signature Ranger (Nature Manipulation): advanced utility"},
    -- Ranger (Wilderness Survival)
    {"Essence of Yew", "Ranger (Wilderness Survival): basic warding"},
    {"Forestwalker's Boon", "Ranger (Wilderness Survival): intermediate warding"},
    {"Hands of Lirisa|Athleticism", "Ranger (Wilderness Survival): basic augmentation"},
    {"Oath of the Firstborn", "Ranger (Wilderness Survival): intermediate augmentation"},
    {"Earth Meld", "Ranger (Wilderness Survival): basic augmentation/utility"},
    {"Skein of Shadows", "signature Ranger (Wilderness Survival): intermediate augmentation/utility"},
    {"Blend", "signature Ranger (Wilderness Survival): intermediate utility"},
    {"Memory of Nature", "signature Ranger (Wilderness Survival): advanced utility"},
    -- Warrior Mage (Aether Manipulation)
    {"Ward Break", "Warrior Mage (Aether Manipulation): basic debilitation"},
    {"Ethereal Shield", "Warrior Mage (Aether Manipulation): introductory warding"},
    {"Substratum", "Warrior Mage (Aether Manipulation): basic augmentation"},
    {"Aether Cloak", "signature Warrior Mage (Aether Manipulation): advanced warding"},
    {"Ethereal Fissure", "signature Warrior Mage (Aether Manipulation): intermediate utility"},
    -- Warrior Mage (Air Manipulation)
    {"Paeldryth's Wrath", "Warrior Mage (Air Manipulation): intermediate targeted"},
    {"Shockwave", "Warrior Mage (Air Manipulation): advanced targeted"},
    {"Air Lash", "Warrior Mage (Air Manipulation): introductory targeted"},
    {"Vertigo|Thunderclap", "Warrior Mage (Air Manipulation): intermediate debilitation"},
    {"Tailwind|Swirling Winds", "Warrior Mage (Air Manipulation): basic augmentation"},
    {"Y'ntrel Sechra", "Warrior Mage (Air Manipulation): intermediate augmentation"},
    {"Zephyr|Air Bubble", "Warrior Mage (Air Manipulation): basic utility"},
    {"Blufmor Garaen", "signature Warrior Mage (Air Manipulation): advanced targeted"},
    -- Warrior Mage (Earth Manipulation)
    {"Stone Strike", "Warrior Mage (Earth Manipulation): introductory targeted"},
    {"Tremor", "Warrior Mage (Earth Manipulation): intermediate debilitation"},
    {"Anther's Call", "Warrior Mage (Earth Manipulation): basic debilitation"},
    {"Sure Footing", "Warrior Mage (Earth Manipulation): basic augmentation"},
    {"Magnetic Ballista", "signature Warrior Mage (Earth Manipulation): intermediate targeted"},
    {"Ring of Spears", "signature Warrior Mage (Earth Manipulation): advanced targeted"},
    {"Aegis of Granite", "signature Warrior Mage (Earth Manipulation): advanced augmentation"},
    -- Warrior Mage (Electricity Manipulation)
    {"Lightning Bolt", "Warrior Mage (Electricity Manipulation): intermediate targeted"},
    {"Gar Zeng", "Warrior Mage (Electricity Manipulation): introductory targeted"},
    {"Arc Light", "Warrior Mage (Electricity Manipulation): basic debilitation"},
    {"Tingle", "Warrior Mage (Electricity Manipulation): intermediate debilitation"},
    {"Chain Lightning", "signature Warrior Mage (Electricity Manipulation): intermediate targeted"},
    {"Electrostatic Eddy", "signature Warrior Mage (Electricity Manipulation): intermediate debilitation"},
    {"Grounding Field", "signature Warrior Mage (Electricity Manipulation): advanced warding"},
    -- Warrior Mage (Fire Manipulation)
    {"Fire Shards", "Warrior Mage (Fire Manipulation): introductory targeted"},
    {"Fire Ball", "Warrior Mage (Fire Manipulation): intermediate targeted"},
    {"Flame Shockwave", "Warrior Mage (metamagic): advanced targeted"},
    {"Ignite", "Warrior Mage (Fire Manipulation): basic utility"},
    {"Dragon's Breath", "signature Warrior Mage (Fire Manipulation): intermediate targeted"},
    {"Fire Rain", "signature Warrior Mage (Fire Manipulation): advanced targeted"},
    {"Mark of Arhat", "signature Warrior Mage (Fire Manipulation): basic debilitation"},
    {"Mantle of Flame", "signature Warrior Mage (Fire Manipulation): advanced augmentation"},
    -- Warrior Mage (Water Manipulation)
    {"Geyser", "Warrior Mage (Water Manipulation): introductory targeted"},
    {"Frost Scythe", "Warrior Mage (Water Manipulation): intermediate targeted"},
    {"Frostbite", "Warrior Mage (Water Manipulation): intermediate debilitation"},
    {"Ice Patch", "Warrior Mage (Water Manipulation): basic debilitation"},
    {"Rising Mists", "Warrior Mage (Water Manipulation): intermediate utility"},
    {"Rimefang", "signature Warrior Mage (Water Manipulation): advanced targeted"},
    {"Veil of Ice", "signature Warrior Mage (Water Manipulation): intermediate warding"},
    {"Fortress of Ice", "signature Warrior Mage (Water Manipulation): advanced utility"},
    -- Bard (Elemental Invocations)
    {"Breath of Storms", "Bard (Elemental Invocations): basic targeted"},
    {"Echoes of Aether|Will of Winter", "Bard (Elemental Invocations): intermediate augmentation"},
    {"Words of the Wind", "Bard (Elemental Invocations): basic augmentation"},
    {"Soul Ablaze", "Bard (Elemental Invocations): advanced augmentation"},
    {"Phoenix's Pyre", "signature Bard (Elemental Invocations): advanced targeted"},
    {"Desert's Maelstrom", "signature Bard (Elemental Invocations): advanced debilitation"},
    {"Caress of the Sun", "signature Bard (Elemental Invocations): introductory utility"},
    -- Bard (Emotion Control)
    {"Misdirection", "Bard (Emotion Control): intermediate debilitation/augmentation"},
    {"Redeemer's Pride", "Bard (Emotion Control): basic warding"},
    {"Whispers of the Muse", "Bard (Emotion Control): basic augmentation"},
    {"Rage of the Clans", "Bard (Emotion Control): intermediate augmentation"},
    {"Abandoned Heart", "signature Bard (Emotion Control): advanced targeted"},
    {"Damaris' Lullaby", "signature Bard (Emotion Control): basic debilitation"},
    {"Albreda's Balm", "signature Bard (Emotion Control): advanced debilitation/utility"},
    {"Faenella's Grace", "signature Bard (Emotion Control): introductory augmentation"},
    -- Bard (Fae Arts)
    {"Nexus", "Bard (Fae Arts): advanced utility"},
    {"Beckon the Naga", "signature Bard (Fae Arts): advanced targeted"},
    {"Aether Wolves", "signature Bard (Fae Arts): introductory debilitation"},
    {"Glythtide's Joy", "signature Bard (Fae Arts): basic warding"},
    {"Blessing of the Fae", "signature Bard (Fae Arts): intermediate augmentation"},
    {"Eye of Kertigen", "signature Bard (Fae Arts): intermediate utility"},
    {"Sanctuary", "signature Bard (Fae Arts): advanced utility"},
    -- Bard (Sound Manipulation)
    {"Demrris' Resolve", "Bard (Sound Manipulation): basic debilitation"},
    {"Drums of the Snake", "Bard (Sound Manipulation): intermediate augmentation"},
    {"Eillie's Cry", "Bard (Sound Manipulation): introductory augmentation"},
    {"Resonance", "Bard (Sound Manipulation): intermediate utility"},
    {"Aura of Tongues", "Bard (Sound Manipulation): introductory utility"},
    {"Naming of Tears", "signature Bard (Sound Manipulation): advanced warding"},
    {"Harmony", "signature Bard (Sound Manipulation): advanced augmentation"},
    {"Hodierna's Lilt", "signature Bard (Sound Manipulation): basic utility"},
    -- Moon Mage (Enlightened Geometry)
    {"Partial Displacement", "Moon Mage (Enlightened Geometry): basic targeted"},
    {"Whole Displacement", "signature Moon Mage (Enlightened Geometry): basic warding"},
    {"Shadowling|Braun's Conjecture|Contingency", "signature Moon Mage (Enlightened Geometry): intermediate utility"},
    {"Shadow Servant|Moongate", "signature Moon Mage (Enlightened Geometry): advanced utility"},
    {"Teleport", "signature Moon Mage (Enlightened Geometry): basic utility"},
    {"Riftal Summons", "signature Moon Mage (Enlightened Geometry): esoteric utility"},
    -- Moon Mage (Moonlight Manipulation)
    {"Burn", "Moon Mage (Moonlight Manipulation): intermediate targeted"},
    {"Dinazen Olkar", "Moon Mage (Moonlight Manipulation): basic targeted"},
    {"Dazzle", "Moon Mage (Moonlight Manipulation): basic debilitation"},
    {"Cage of Light", "Moon Mage (Moonlight Manipulation): intermediate warding"},
    {"Shadows", "Moon Mage (Moonlight Manipulation): introductory augmentation"},
    {"Focus Moonbeam", "signature Moon Mage (Moonlight Manipulation): introductory utility"},
    {"Refractive Field", "signature Moon Mage (Moonlight Manipulation): basic utility"},
    {"Steps of Vuan|Moonblade|Shift Moonbeam", "signature Moon Mage (Moonlight Manipulation): intermediate utility"},
    -- Moon Mage (Perception)
    {"Clear Vision", "Moon Mage (Perception): introductory augmentation"},
    {"Machinist's Touch", "Moon Mage (Perception): intermediate augmentation"},
    {"Artificer's Eye|Aura Sight|Tenebrous Sense", "Moon Mage (Perception): basic augmentation"},
    {"Piercing Gaze", "Moon Mage (Perception): basic utility"},
    {"Unleash", "Moon Mage (Perception): intermediate utility"},
    {"Seer's Sense", "signature Moon Mage (Perception): intermediate augmentation/utility"},
    {"Locate|Distant Gaze", "signature Moon Mage (Perception): intermediate utility"},
    {"Destiny Cipher", "signature Moon Mage (Perception): basic utility"},
    -- Moon Mage (Psychic Projection)
    {"Telekinetic Throw", "Moon Mage (Psychic Projection): introductory targeted"},
    {"Telekinetic Storm", "Moon Mage (Psychic Projection): intermediate targeted"},
    {"Calm", "Moon Mage (Psychic Projection): introductory debilitation"},
    {"Sleep", "Moon Mage (Psychic Projection): basic debilitation"},
    {"Rend", "Moon Mage (Psychic Projection): basic debilitation/utility"},
    {"Psychic Shield", "Moon Mage (Psychic Projection): basic warding"},
    {"Shear", "Moon Mage (Psychic Projection): advanced warding"},
    {"Thoughtcast", "Moon Mage (Psychic Projection): intermediate utility"},
    {"Mental Blast|Mind Shout", "signature Moon Mage (Psychic Projection): advanced debilitation"},
    -- Moon Mage (Stellar Magic)
    {"Starlight Sphere", "signature Moon Mage (Stellar Magic): advanced targeted"},
    {"Invocation of the Spheres", "signature Moon Mage (Stellar Magic): advanced augmentation"},
    {"Shadewatch Mirror|Read the Ripples", "signature Moon Mage (Stellar Magic): advanced utility"},
    -- Moon Mage (Teleologic Sorcery)
    {"Sever Thread", "signature Moon Mage (Teleologic Sorcery): basic debilitation"},
    {"Sovereign Destiny", "signature Moon Mage (Teleologic Sorcery): intermediate debilitation"},
    {"Tangled Fate", "signature Moon Mage (Teleologic Sorcery): basic debilitation/utility"},
    {"Tezirah's Veil", "signature Moon Mage (Teleologic Sorcery): intermediate augmentation"},
    -- Necromancer (Animation)
    {"Reverse Putrefaction", "signature Necromancer (Animation): intermediate augmentation"},
    {"Call from Beyond|Necrotic Reconstruction", "signature Necromancer (Animation): intermediate utility"},
    {"Quicken the Earth", "signature Necromancer (Animation): basic utility"},
    -- Necromancer (Blood Magic)
    {"Blood Burst|Siphon Vitality", "Necromancer (Blood Magic): intermediate targeted"},
    {"Heighten Pain", "Necromancer (Blood Magic): introductory debilitation"},
    {"Consume Flesh", "signature Necromancer (Blood Magic): intermediate utility"},
    {"Devour", "signature Necromancer (Blood Magic): advanced utility"},
    -- Necromancer (Corruption)
    {"Visions of Darkness", "Necromancer (Corruption): intermediate debilitation"},
    {"Petrifying Visions", "Necromancer (Corruption): basic debilitation"},
    {"Obfuscation", "Necromancer (Corruption): introductory augmentation"},
    {"Rite of Contrition|Rite of Grace", "Necromancer (Corruption): intermediate utility"},
    {"Eyes of the Blind", "signature Necromancer (Corruption): basic utility"},
    -- Necromancer (Synthetic Creation)
    {"Acid Splash", "Necromancer (Synthetic Creation): introductory targeted"},
    {"Viscous Solution", "Necromancer (Synthetic Creation): intermediate debilitation"},
    {"Researcher's Insight", "Necromancer (Synthetic Creation): intermediate augmentation"},
    {"Vivisection|Universal Solvent", "signature Necromancer (Synthetic Creation): advanced targeted"},
    -- Necromancer (Transcendental Necromancy)
    {"Calcified Hide", "signature Necromancer (Transcendental Necromancy): intermediate warding"},
    {"Worm's Mist", "signature Necromancer (Transcendental Necromancy): advanced warding"},
    {"Butcher's Eye|Philosopher's Preservation|Kura-Silma|Ivory Mask", "signature Necromancer (Transcendental Necromancy): basic augmentation"},
  }
  for _, e in ipairs(spell_rec) do
    TextSubs.add(SR .. " (" .. e[1] .. ") spell\\.", "$1 of the $2 spell. [" .. e[2] .. "]")
  end
end

-------------------------------------------------------------------------------
-- Trader Aura (conditional)
-------------------------------------------------------------------------------

if DRStats.trader() then
  local trader_aura = {
    {"The smallest hint of starlight flickers within your aura.", "0/9"},
    {"A bare flicker of starlight plays within your aura.", "1/9"},
    {"A faint amount of starlight illuminates your aura.", "2/9"},
    {"Your aura pulses slowly with starlight.", "3/9"},
    {"A steady pulse of starlight runs through your aura.", "4/9"},
    {"Starlight dances vividly across the confines of your aura.", "5/9"},
    {"Strong pulses of starlight flare within your aura.", "6/9"},
    {"Your aura seethes with brilliant starlight.", "7/9"},
    {"Your aura is blinding!", "8/9"},
    {"The power contained in your aura defies visual metaphor.", "9/9"},
  }
  for _, e in ipairs(trader_aura) do
    TextSubs.add(e[1], e[1]:sub(1, -2) .. " (" .. e[2] .. ")" .. e[1]:sub(-1))
  end
end

-------------------------------------------------------------------------------
-- Moon Mage Celestial + Prediction (conditional)
-------------------------------------------------------------------------------

if DRStats.moon_mage() then
  local celestial = {
    {"no",          "0%"},    {"feeble",      "1-11%"},
    {"weak",        "12-22%"}, {"fledgling",   "23-33%"},
    {"modest",      "34-44%"}, {"decent",      "45-55%"},
    {"significant", "56-66%"}, {"potent",      "67-77%"},
    {"insightful",  "78-88%"}, {"powerful",    "89-99%"},
    {"complete",    "100%"},
  }
  for _, e in ipairs(celestial) do
    TextSubs.add("You have (.*" .. e[1] .. ") understanding of the celestial influences over (.*)\\.",
      "You have $1 understanding of the celestial influences over $2 (" .. e[2] .. ").")
  end

  -- Prediction polarity
  local pred_power = "translucent|flickering|quivering|solid|undulating|vivid|luminous"
  local pred_skill = "moonblade|shield|spellbook|tome|tree|amorphous .*"
  TextSubs.add("A (" .. pred_power .. ") (aquamarine|azure|cerulean|sapphire|sky blue) (" .. pred_skill .. ") that", "A $1 $2 (good polarity) $3 that")
  TextSubs.add("A (" .. pred_power .. ") (grey|pale|white) (" .. pred_skill .. ") that", "A $1 $2 (neutral polarity) $3 that")
  TextSubs.add("A (" .. pred_power .. ") (crimson|fiery|molten|ruby|scarlet) (" .. pred_skill .. ") that", "A $1 $2 (bad polarity) $3 that")

  -- Fog/Zenith
  TextSubs.add("Your skill in (.*) has fogged over\\.", "Your skill in $1 has fogged over (-15%).")
  TextSubs.add("Your skill in (.*) is at a zenith of enlightenment\\.", "Your skill in $1 is at a zenith of enlightenment (+15%).")
end

-------------------------------------------------------------------------------
-- Barbarian Inner Fire (conditional)
-------------------------------------------------------------------------------

if DRStats.barbarian() then
  local inner_fire = {
    {"a dim glow as if a flame lurked just out of sight", "1/13"},
    {"a tiny aura of beautiful flames", "2/13"},
    {"a small aura of beautiful flames", "3/13"},
    {"a bright aura of beautiful flames\\.", "4/13"},
    {"a bright aura of beautiful flames extending a quarter of your height above you", "5/13"},
    {"a bright aura of beautiful flames extending out around you just beyond the reach of your arms", "6/13"},
    {"a brilliant aura of beautiful flames extending out around you about half again your height", "7/13"},
    {"a brilliant aura of beautiful flames extending a little over half your height again above you", "8/13"},
    {"a brilliant aura of flames that extends nearly your full height again above you", "9/13"},
    {"a brilliant aura of flames that extends over your height again above you", "10/13"},
    {"a brilliant aura of beautiful flames extending a little more than one and half times your height above your body", "11/13"},
    {"a brilliant aura of beautiful flames extending nearly twice your height above your body", "12/13"},
    {"a brilliant aura of pristine quality burning outward at twice your height", "13/13"},
  }
  for _, e in ipairs(inner_fire) do
    TextSubs.add(e[1], e[1] .. " (" .. e[2] .. ")")
  end
end

-------------------------------------------------------------------------------
-- Coin Patterns (conditional: settings.textsubs_use_plat_grouping)
-------------------------------------------------------------------------------

if settings.textsubs_use_plat_grouping then
  TextSubs.add("(?!.*>)\\d{1,3}(?=((\\d{3})*(\\d{4}))(?!\\d)(?! platinum).*(Kronar|Dokora|Lirum))", "$0,")
  TextSubs.add("(?!.*>)\\d{1,3}(?=(\\d{3})+(?!\\d) platinum.*(Kronar|Dokora|Lirum))", "$0,")
else
  TextSubs.add("(?!.*>)\\d{1,3}(?=(\\d{3})+(?!\\d).*(Kronar|Dokora|Lirum))", "$0,")
end

-------------------------------------------------------------------------------
-- Scroll Labels (~320 entries) — always active
-------------------------------------------------------------------------------

do
  local SL = "^(It is labeled)"
  local scrolls = {
    -- Analogous Patterns
    {"Strange Arrow", "Analogous Patterns"}, {"Burden", "Analogous Patterns"},
    {"Lay Ward", "Analogous Patterns"}, {"Manifest Force", "Analogous Patterns"},
    {"Ease Burden", "Analogous Patterns"}, {"Dispel", "Analogous Patterns"},
    {"Imbue", "Analogous Patterns"}, {"Seal Cambrinth", "Analogous Patterns"},
    {"Gauge Flow", "Analogous Patterns"},
    -- Cleric
    {"Aesrela Everild", "Cleric"}, {"Fire of Ushnish", "Cleric"},
    {"Resurrection", "Cleric"}, {"Murrula's Flames", "Cleric"},
    {"Glythtide's Gift", "Cleric"}, {"Protection from Evil", "Cleric"},
    {"Minor Physical Protection", "Cleric"}, {"Soul Shield", "Cleric"},
    {"Ghost Shroud", "Cleric"}, {"Major Physical Protection", "Cleric"},
    {"Halo", "Cleric"}, {"Sanyu Lyba", "Cleric"}, {"Benediction", "Cleric"},
    {"Shield of Light", "Cleric"}, {"Harm Evil", "Cleric"},
    {"Horn of the Black Unicorn", "Cleric"}, {"Fists of Faenella", "Cleric"},
    {"Hand of Tenemlor", "Cleric"}, {"Phelim's Sanction", "Cleric"},
    {"Curse of Zachriedek", "Cleric"}, {"Malediction", "Cleric"},
    {"Bless", "Cleric"}, {"Divine Radiance", "Cleric"}, {"Harm Horde", "Cleric"},
    {"Hydra Hex", "Cleric"}, {"Huldah's Pall", "Cleric"},
    {"Sanctify Pattern", "Cleric"}, {"Uncurse", "Cleric"},
    {"Meraud's Cry", "Cleric"}, {"Spite of Dergati", "Cleric"},
    {"Idon's Theft", "Cleric"}, {"Persistence of Mana", "Cleric"},
    {"Osrel Meraud", "Cleric"}, {"Chill Spirit", "Cleric"},
    {"Soul Sickness", "Cleric"}, {"Auspice", "Cleric"}, {"Centering", "Cleric"},
    {"Vigil", "Cleric"}, {"Revelation", "Cleric"}, {"Soul Attrition", "Cleric"},
    {"Soul Bonding", "Cleric"}, {"Rejuvenation", "Cleric"},
    {"Mass Rejuvenation", "Cleric"}, {"Eylhaar's Feast", "Cleric"},
    {"Bitter Feast", "Cleric"}, {"Heavenly Fires", "Cleric"},
    {"Aspects of the All-God", "Cleric"},
    -- Paladin
    {"Soldier's Prayer", "Paladin"}, {"Courage", "Paladin"},
    {"Righteous Wrath", "Paladin"}, {"Divine Guidance", "Paladin"},
    {"Sentinel's Resolve", "Paladin"}, {"Heroic Strength", "Paladin"},
    {"Anti-Stun", "Paladin"}, {"Marshal Order", "Paladin"},
    {"Truffenyi's Rally", "Paladin"}, {"Divine Armor", "Paladin"},
    {"Bond Armaments", "Paladin"}, {"Rebuke", "Paladin"},
    {"Smite Horde", "Paladin"}, {"Footman's Strike", "Paladin"},
    {"Halt", "Paladin"}, {"Shatter", "Paladin"}, {"Stun Foe", "Paladin"},
    {"Clarity", "Paladin"}, {"Hands of Justice", "Paladin"},
    {"Rutilor's Edge", "Paladin"}, {"Holy Warrior", "Paladin"},
    {"Banner of Truce", "Paladin"}, {"Aspirant's Aegis", "Paladin"},
    {"Crusader's Challenge", "Paladin"}, {"Alamhif's Gift", "Paladin"},
    {"Vessel of Salvation", "Paladin"},
    -- Empath
    {"Blood Staunching", "Empath"}, {"Flush Poisons", "Empath"},
    {"Cure Disease", "Empath"}, {"Heart Link", "Empath"},
    {"Absolution", "Empath"}, {"Vitality Healing", "Empath"},
    {"Heal Wounds", "Empath"}, {"Heal Scars", "Empath"}, {"Heal", "Empath"},
    {"Regenerate", "Empath"}, {"Fountain of Creation", "Empath"},
    {"Paralysis", "Empath"}, {"Lethargy", "Empath"}, {"Refresh", "Empath"},
    {"Gift of Life", "Empath"}, {"Vigor", "Empath"}, {"Raise Power", "Empath"},
    {"Compel", "Empath"}, {"Mental Focus", "Empath"}, {"Awaken", "Empath"},
    {"Nissa's Binding", "Empath"}, {"Circle of Sympathy", "Empath"},
    {"Iron Constitution", "Empath"}, {"Aggressive Stance", "Empath"},
    {"Aesandry Darlaeth", "Empath"}, {"Innocence", "Empath"},
    {"Perseverance of Peri'el", "Empath"}, {"Guardian Spirit", "Empath"},
    {"Tranquility", "Empath"}, {"Icutu Zaharenela", "Empath"},
    {"Adaptive Curing", "Empath"},
    -- Ranger
    {"Grizzly Claws", "Ranger"}, {"Wolf Scent", "Ranger"},
    {"Instinct", "Ranger"}, {"Senses of the Tiger", "Ranger"},
    {"See the Wind", "Ranger"}, {"Wisdom of the Pack", "Ranger"},
    {"Cheetah Swiftness", "Ranger"}, {"Claws of the Cougar", "Ranger"},
    {"Bear Strength", "Ranger"}, {"Eagle's Cry", "Ranger"},
    {"Devitalize", "Ranger"}, {"Stampede", "Ranger"},
    {"Carrion Call", "Ranger"}, {"Swarm", "Ranger"},
    {"Harawep's Bonds", "Ranger"}, {"Deadfall", "Ranger"},
    {"Curse of the Wilds", "Ranger"}, {"Compost", "Ranger"},
    {"Devolve", "Ranger"}, {"Awaken Forest", "Ranger"},
    {"Essence of Yew", "Ranger"}, {"Forestwalker's Boon", "Ranger"},
    {"Hands of Lirisa", "Ranger"}, {"Athleticism", "Ranger"},
    {"Oath of the Firstborn", "Ranger"}, {"Earth Meld", "Ranger"},
    {"Skein of Shadows", "Ranger"}, {"Blend", "Ranger"},
    {"Memory of Nature", "Ranger"}, {"River in the Sky", "Ranger"},
    -- Warrior Mage
    {"Ward Break", "Warrior Mage"}, {"Ethereal Shield", "Warrior Mage"},
    {"Substratum", "Warrior Mage"}, {"Aether Cloak", "Warrior Mage"},
    {"Ethereal Fissure", "Warrior Mage"}, {"Paeldryth's Wrath", "Warrior Mage"},
    {"Shockwave", "Warrior Mage"}, {"Air Lash", "Warrior Mage"},
    {"Vertigo", "Warrior Mage"}, {"Thunderclap", "Warrior Mage"},
    {"Tailwind", "Warrior Mage"}, {"Swirling Winds", "Warrior Mage"},
    {"Y'ntrel Sechra", "Warrior Mage"}, {"Zephyr", "Warrior Mage"},
    {"Air Bubble", "Warrior Mage"}, {"Blufmor Garaen", "Warrior Mage"},
    {"Stone Strike", "Warrior Mage"}, {"Tremor", "Warrior Mage"},
    {"Anther's Call", "Warrior Mage"}, {"Sure Footing", "Warrior Mage"},
    {"Magnetic Ballista", "Warrior Mage"}, {"Ring of Spears", "Warrior Mage"},
    {"Aegis of Granite", "Warrior Mage"}, {"Lightning Bolt", "Warrior Mage"},
    {"Gar Zeng", "Warrior Mage"}, {"Arc Light", "Warrior Mage"},
    {"Tingle", "Warrior Mage"}, {"Chain Lightning", "Warrior Mage"},
    {"Electrostatic Eddy", "Warrior Mage"}, {"Grounding Field", "Warrior Mage"},
    {"Fire Shards", "Warrior Mage"}, {"Fire Ball", "Warrior Mage"},
    {"Ignite", "Warrior Mage"}, {"Dragon's Breath", "Warrior Mage"},
    {"Fire Rain", "Warrior Mage"}, {"Mark of Arhat", "Warrior Mage"},
    {"Mantle of Flame", "Warrior Mage"}, {"Geyser", "Warrior Mage"},
    {"Frost Scythe", "Warrior Mage"}, {"Frostbite", "Warrior Mage"},
    {"Ice Patch", "Warrior Mage"}, {"Rising Mists", "Warrior Mage"},
    {"Rimefang", "Warrior Mage"}, {"Veil of Ice", "Warrior Mage"},
    {"Fortress of Ice", "Warrior Mage"}, {"Flame Shockwave", "Warrior Mage"},
    {"Aethrolysis", "Warrior Mage"}, {"Gam Irnan", "Warrior Mage"},
    -- Bard
    {"Breath of Storms", "Bard"}, {"Echoes of Aether", "Bard"},
    {"Will of Winter", "Bard"}, {"Words of the Wind", "Bard"},
    {"Soul Ablaze", "Bard"}, {"Phoenix's Pyre", "Bard"},
    {"Desert's Maelstrom", "Bard"}, {"Caress of the Sun", "Bard"},
    {"Misdirection", "Bard"}, {"Redeemer's Pride", "Bard"},
    {"Rage of the Clans", "Bard"}, {"Abandoned Heart", "Bard"},
    {"Damaris's Lullaby", "Bard"}, {"Albreda's Balm", "Bard"},
    {"Faenella's Grace", "Bard"}, {"Nexus", "Bard"},
    {"Beckon the Naga", "Bard"}, {"Aether Wolves", "Bard"},
    {"Glythtide's Joy", "Bard"}, {"Blessing of the Fae", "Bard"},
    {"Eye of Kertigen", "Bard"}, {"Sanctuary", "Bard"},
    {"Drums of the Snake", "Bard"}, {"Eillie's Cry", "Bard"},
    {"Resonance", "Bard"}, {"Aura of Tongues", "Bard"},
    {"Naming of Tears", "Bard"}, {"Harmony", "Bard"},
    {"Hodierna's Lilt", "Bard"}, {"Whispers of the Muse", "Bard"},
    {"Demrris' Resolve", "Bard"},
    -- Moon Mage
    {"Partial Displacement", "Moon Mage"}, {"Whole Displacement", "Moon Mage"},
    {"Shadowling", "Moon Mage"}, {"Braun's Conjecture", "Moon Mage"},
    {"Contingency", "Moon Mage"}, {"Shadow Servant", "Moon Mage"},
    {"Moongate", "Moon Mage"}, {"Teleport", "Moon Mage"},
    {"Riftal Summons", "Moon Mage"}, {"Burn", "Moon Mage"},
    {"Dinazen Olkar", "Moon Mage"}, {"Dazzle", "Moon Mage"},
    {"Cage of Light", "Moon Mage"}, {"Shadows", "Moon Mage"},
    {"Focus Moonbeam", "Moon Mage"}, {"Refractive Field", "Moon Mage"},
    {"Steps of Vuan", "Moon Mage"}, {"Moonblade", "Moon Mage"},
    {"Shift Moonbeam", "Moon Mage"}, {"Clear Vision", "Moon Mage"},
    {"Machinist's Touch", "Moon Mage"}, {"Artificer's Eye", "Moon Mage"},
    {"Aura Sight", "Moon Mage"}, {"Tenebrous Sense", "Moon Mage"},
    {"Piercing Gaze", "Moon Mage"}, {"Unleash", "Moon Mage"},
    {"Seer's Sense", "Moon Mage"}, {"Locate", "Moon Mage"},
    {"Distant Gaze", "Moon Mage"}, {"Destiny Cipher", "Moon Mage"},
    {"Telekinetic Throw", "Moon Mage"}, {"Telekinetic Shield", "Moon Mage"},
    {"Telekinetic Storm", "Moon Mage"}, {"Calm", "Moon Mage"},
    {"Sleep", "Moon Mage"}, {"Rend", "Moon Mage"},
    {"Psychic Shield", "Moon Mage"}, {"Shear", "Moon Mage"},
    {"Thoughtcast", "Moon Mage"}, {"Mental Blast", "Moon Mage"},
    {"Mind Shout", "Moon Mage"}, {"Starlight Sphere", "Moon Mage"},
    {"Invocation of the Spheres", "Moon Mage"},
    {"Shadewatch Mirror", "Moon Mage"}, {"Read the Ripples", "Moon Mage"},
    {"Sever Thread", "Moon Mage"}, {"Sovereign Destiny", "Moon Mage"},
    {"Tangled Fate", "Moon Mage"}, {"Tezirah's Veil", "Moon Mage"},
    {"Iyqaromos Fire-Lens", "Moon Mage"}, {"Saesordian Compass", "Moon Mage"},
    -- Necromancer
    {"Reverse Putrefaction", "Necromancer"}, {"Call from Beyond", "Necromancer"},
    {"Necrotic Reconstruction", "Necromancer"}, {"Quicken the Earth", "Necromancer"},
    {"Blood Burst", "Necromancer"}, {"Siphon Vitality", "Necromancer"},
    {"Heighten Pain", "Necromancer"}, {"Consume Flesh", "Necromancer"},
    {"Devour", "Necromancer"}, {"Visions of Darkness", "Necromancer"},
    {"Petrifying Visions", "Necromancer"}, {"Obfuscation", "Necromancer"},
    {"Rite of Contrition", "Necromancer"}, {"Rite of Grace", "Necromancer"},
    {"Eyes of the Blind", "Necromancer"}, {"Acid Splash", "Necromancer"},
    {"Viscous Solution", "Necromancer"}, {"Researcher's Insight", "Necromancer"},
    {"Vivisection", "Necromancer"}, {"Universal Solvent", "Necromancer"},
    {"Calcified Hide", "Necromancer"}, {"Worm's Mist", "Necromancer"},
    {"Butcher's Eye", "Necromancer"}, {"Philosopher's Preservation", "Necromancer"},
    {"Kura-Silma", "Necromancer"}, {"Ivory Mask", "Necromancer"},
    {"Liturgy", "Necromancer"}, {"Alkahest Edge", "Necromancer"},
    -- Trader
    {"Trabe Chalice", "Trader"}, {"Turmar Illumination", "Trader"},
    {"Avren Aevareae", "Trader"}, {"Crystal Dart", "Trader"},
    {"Nonchalance", "Trader"}, {"Regalia", "Trader"},
    {"Membrach's Greed", "Trader"}, {"Fluoresce", "Trader"},
    -- Lay Necromancy
    {"Sidhlot's Flaying", "Lay Necromancy"},
  }
  for _, s in ipairs(scrolls) do
    TextSubs.add(SL .. ' "' .. s[1] .. '."', '$1 "' .. s[1] .. '." (' .. s[2] .. ")")
  end
end

-------------------------------------------------------------------------------
-- Mysanda (always active)
-------------------------------------------------------------------------------

TextSubs.add("gath mysanda", "gath mysanda (harness)")
TextSubs.add("kirm mysanda", "kirm mysanda (vitality)")
TextSubs.add("lyba mysanda", "lyba mysanda (spirit)")
TextSubs.add("mishar mysanda", "mishar mysanda (concentration)")
TextSubs.add("morlam mysanda", "morlam mysanda (fatigue)")

-------------------------------------------------------------------------------
-- Sigil Hunting Mini-Game (always active)
-------------------------------------------------------------------------------

do
  for i = 0, 20 do
    local stars  = string.rep("\\*", i)
    local dashes = string.rep("-", 20 - i)
    TextSubs.add(":\\s+" .. stars .. dashes, ":  " .. i .. "/20")
  end
end

-------------------------------------------------------------------------------
-- Challenge Rating (always active)
-------------------------------------------------------------------------------

TextSubs.add("\\.\\.\\.a trivial",        "...a trivial (1/5)")
TextSubs.add("\\.\\.\\.a straightforward", "...a straightforward (2/5)")
TextSubs.add("\\.\\.\\.a formidable",      "...a formidable (3/5)")
TextSubs.add("\\.\\.\\.a challenging",     "...a challenging (4/5)")
TextSubs.add("\\.\\.\\.a difficult",       "...a difficult (5/5)")

-------------------------------------------------------------------------------
-- Runestones (Sierack's Reagents shop in Shard)
-------------------------------------------------------------------------------

do
  local runes = {
    {"Electrum",   "Eagle's Cry"},          {"Topaz",      "Protection from Evil"},
    {"Quartz",     "Refresh"},              {"Axinite",    "Glythtide's Gift"},
    {"Azurite",    "Shadows"},              {"Calavarite", "Arc Light"},
    {"Celestite",  "Geyser"},               {"Elbaite",    "Bless"},
    {"Rhodonite",  "Fire Shards"},          {"Selenite",   "Athleticism"},
    {"Xibaryl",    "Calm"},                 {"Imnera",     "Zephyr"},
    {"Asketine",   "Compost"},              {"Avaes",      "Clear Vision"},
  }
  for _, r in ipairs(runes) do
    TextSubs.add("^ " .. r[1] .. " Runestone", " " .. r[1] .. " Runestone (" .. r[2] .. ")")
  end
end

-------------------------------------------------------------------------------
-- Crafting Prestige (0-14) — always active
-------------------------------------------------------------------------------

do
  local prestige = {
    {"unknown",     "0/14"},  {"familiar",     "1/14"},
    {"recognized",  "2/14"},  {"reputable",    "3/14"},
    {"professional","4/14"},  {"well-known",   "5/14"},
    {"noteworthy",  "6/14"},  {"renowned",     "7/14"},
    {"prominent",   "8/14"},  {"honored",      "9/14"},
    {"acclaimed",   "10/14"}, {"famous",       "11/14"},
    {"peerless",    "12/14"}, {"illustrious",  "13/14"},
    {"legendary",   "14/14"},
  }
  for _, e in ipairs(prestige) do
    TextSubs.add("ability has made you (a|an) " .. e[1] .. " crafter within the Society",
      "ability has made you $1 " .. e[1] .. " (" .. e[2] .. ") crafter within the Society")
  end
end

-------------------------------------------------------------------------------
-- Metal Ingots (always active)
-------------------------------------------------------------------------------

do
  local ingot_sizes = {
    {"tiny",     "1"},   {"small",    "2"},   {"medium",   "3"},
    {"large",    "4"},   {"huge",     "5"},   {"massive",  "10"},
  }
  local ingot_sizes_an = {
    {"enormous", "20"},  {"immense",  "50"},
  }
  local ingot_sizes_a2 = {
    {"gigantic", "100"}, {"colossal", "200"},
  }
  -- Single-digit ordinal
  for _, e in ipairs(ingot_sizes) do
    TextSubs.add("^(\\d)\\)\\.  a " .. e[1] .. " (\\w+) (ingot|nugget)(\\.+) ([\\d,]+) (\\w+)",
      "$1).   a    (" .. e[2] .. ") " .. e[1] .. " $2 $3$4 $5 $6")
  end
  for _, e in ipairs(ingot_sizes_an) do
    TextSubs.add("^(\\d)\\)\\.  an " .. e[1] .. " (\\w+) (ingot|nugget)(\\.+) ([\\d,]+) (\\w+)",
      "$1).   an  (" .. e[2] .. ") " .. e[1] .. " $2 $3$4. $5 $6")
  end
  for _, e in ipairs(ingot_sizes_a2) do
    TextSubs.add("^(\\d)\\)\\.  a " .. e[1] .. " (\\w+) (ingot|nugget)(\\.+) ([\\d,]+) (\\w+)",
      "$1).   a  (" .. e[2] .. ") " .. e[1] .. " $2 $3$4 $5 $6")
  end
  -- Double-digit ordinal
  for _, e in ipairs(ingot_sizes) do
    TextSubs.add("^(\\d\\d)\\)\\.  a " .. e[1] .. " (\\w+) (ingot|nugget)(\\.+) ([\\d,]+) (\\w+)",
      "$1).  a    (" .. e[2] .. ") " .. e[1] .. " $2 $3$4. $5 $6")
  end
  for _, e in ipairs(ingot_sizes_an) do
    TextSubs.add("^(\\d\\d)\\)\\.  an " .. e[1] .. " (\\w+) (ingot|nugget)(\\.+) ([\\d,]+) (\\w+)",
      "$1).  an  (" .. e[2] .. ") " .. e[1] .. " $2 $3$4.. $5 $6")
  end
  for _, e in ipairs(ingot_sizes_a2) do
    TextSubs.add("^(\\d\\d)\\)\\.  a " .. e[1] .. " (\\w+) (ingot|nugget)(\\.+) ([\\d,]+) (\\w+)",
      "$1).  a  (" .. e[2] .. ") " .. e[1] .. " $2 $3$4. $5 $6")
  end
end

-------------------------------------------------------------------------------
-- Weapon Damage Ratings (from Seped/lich_repo_mirror)
-- Plain, Affinity, and Resonating forms
-------------------------------------------------------------------------------

do
  -- Common damage levels used across all three weapon damage forms
  -- Each entry: {pattern_word, rating, replacement_word (optional, defaults to pattern_word)}
  local weapon_levels = {
    {"no",                "0/27"},
    {"dismal",            "1/27"},
    {"poor",              "2/27"},
    {"low",               "3/27"},
    {"somewhat fair",     "4/27"},
    {"fair",              "5/27"},
    {"somewhat moderate", "6/27"},
    {"moderate",          "7/27"},
    {"somewhat heavy",    "8/27"},
    {"heavy",             "9/27"},
    {"very heavy",        "10/27"},
    {"great",             "11/27"},
    {"very great",        "12/27"},
    {"severe",            "13/27"},
    {"very severe",       "14/27"},
    {"extreme",           "15/27"},
    {"very extreme",      "16/27"},
    {"mighty",            "17/27"},
    {"very mighty",       "18/27"},
    {"bone-crushing",     "19/27"},
    {"very bone-crushing","20/27"},
    {"dev[ae]stating",      "21/27", "devastating"},
    {"very dev[ae]stating", "22/27", "very devastating"},
    {"overwhelming",      "23/27"},
    {"annihilating",      "24/27"},
    {"obliterating",      "25/27"},
    {"demolishing",       "26/27"},
    {"catastrophic",      "27/27"},
  }

  local DMG_TYPES  = "puncture|slice|impact|fire|cold|electric"
  local AFFI_TYPES = "fire|cold|electric"
  local AFFI_FOR   = "puncture|slice|impact|random"

  -- Plain weapon damage (all 28 levels, 0-27)
  for _, e in ipairs(weapon_levels) do
    local pat, num, repl = e[1], e[2], e[3] or e[1]
    TextSubs.add("^(\\s+)" .. pat .. " (" .. DMG_TYPES .. ") damage",
      "$1" .. repl .. " (" .. num .. ") $2 damage")
  end

  -- Affinity weapon damage (levels 1-27, no "no" level)
  for i = 2, #weapon_levels do
    local e = weapon_levels[i]
    local pat, num, repl = e[1], e[2], e[3] or e[1]
    TextSubs.add("^(\\s+)" .. pat .. " (" .. AFFI_TYPES .. ") damage with affinity for (" .. AFFI_FOR .. ") attacks",
      "$1" .. repl .. " (" .. num .. ") $2 damage with affinity for $3 attacks")
  end

  -- Resonating weapon damage (levels 1-27)
  for i = 2, #weapon_levels do
    local e = weapon_levels[i]
    local pat, num, repl = e[1], e[2], e[3] or e[1]
    TextSubs.add("^(\\s+)" .. pat .. " (" .. DMG_TYPES .. ") damage\\.(\\s+)The (.+) (point|edge|face) seems to resonate with violent energy\\.",
      "$1" .. repl .. " (" .. num .. ") $2 damage.$3The $4 $5 seems to resonate with violent energy.")
  end
end

-------------------------------------------------------------------------------
-- Force of Attacks (0-17) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local force = {
    {"not",              "0/17"},
    {"terribly",         "1/17"},
    {"dismally",         "2/17"},
    {"poorly",           "3/17"},
    {"inadequately",     "4/17"},
    {"fairly",           "5/17"},
    {"decently",         "6/17"},
    {"reasonably",       "7/17"},
    {"soundly",          "8/17"},
    {"well",             "9/17"},
    {"very well",        "10/17"},
    {"extremely well",   "11/17"},
    {"excellently",      "12/17"},
    {"superbly",         "13/17"},
    {"incredibly",       "14/17"},
    {"amazingly",        "15/17"},
    {"unbelieve?ably",   "16/17", "unbelievably"},
    {"perfectly",        "17/17"},
  }
  for _, e in ipairs(force) do
    local pat, num, repl = e[1], e[2], e[3] or e[1]
    TextSubs.add("(is|are) " .. pat .. " designed for improving the force of your attacks\\.",
      "$1 " .. repl .. " (" .. num .. ") designed for improving the force of your attacks.")
  end
end

-------------------------------------------------------------------------------
-- Balance/Suited (0-17) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local balance = {
    {"not",              "0/17"},
    {"terribly",         "1/17"},
    {"dismally",         "2/17"},
    {"poorly",           "3/17"},
    {"inadequately",     "4/17"},
    {"fairly",           "5/17"},
    {"decently",         "6/17"},
    {"reasonably",       "7/17"},
    {"soundly",          "8/17"},
    {"well",             "9/17"},
    {"very well",        "10/17"},
    {"extremely well",   "11/17"},
    {"excellently",      "12/17"},
    {"superbly",         "13/17"},
    {"incredibly",       "14/17"},
    {"amazingly",        "15/17"},
    {"unbelieve?ably",   "16/17", "unbelievably"},
    {"perfectly",        "17/17"},
  }
  for _, e in ipairs(balance) do
    local pat, num, repl = e[1], e[2], e[3] or e[1]
    TextSubs.add("(is|are) " .. pat .. " (balanced and|suited)",
      "$1 " .. repl .. " (" .. num .. ") $2")
  end
end

-------------------------------------------------------------------------------
-- Bow Draw Strength (1-8) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local draw = {
    {"extremely low",      "1/8"}, {"very low",           "2/8"},
    {"somewhat low",       "3/8"}, {"average",            "4/8"},
    {"somewhat high",      "5/8"}, {"very high",          "6/8"},
    {"exceptionally high", "7/8"}, {"extremely high",     "8/8"},
  }
  for _, e in ipairs(draw) do
    TextSubs.add("^The (.+) appears set for a draw strength that is " .. e[1] .. " for a bow of this type\\.",
      "The $1 appears set for a draw strength that is " .. e[1] .. " (" .. e[2] .. ") for a bow of this type.")
  end
end

-------------------------------------------------------------------------------
-- Maneuvering/Stealth Hindrance (0-15) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local hind = {
    {"no",            "0/15"},
    {"insignificant", "1/15"},
    {"trivial",       "2/15"},
    {"light",         "3/15"},
    {"minor",         "4/15"},
    {"fair",          "5/15"},
    {"mild",          "6/15"},
    {"moderate",      "7/15"},
    {"noticeable",    "8/15"},
    {"high",          "9/15"},
    -- 10/15 handled separately (leading \s to avoid matching "insignificant")
    {"great",         "11/15"},
    {"extreme",       "12/15"},
    {"debilitating",  "13/15"},
    {"overwhelming",  "14/15"},
    {"insane",        "15/15"},
  }
  for _, e in ipairs(hind) do
    TextSubs.add(e[1] .. " (maneuvering|stealth) hindrance",
      e[1] .. " (" .. e[2] .. ") $1 hindrance")
  end
  -- "significant" needs leading \s to disambiguate from "insignificant"
  TextSubs.add("\\ssignificant (maneuvering|stealth) hindrance", " significant (10/15) $1 hindrance")
end

-------------------------------------------------------------------------------
-- "If you were only wearing" Maneuvering (0-14) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local MAN_PRE = "^If you were only wearing (.+) (your maneuvering would be|you could expect your maneuvering to be) "
  local MAN_SUF = " and your stealth (would|to) be"

  -- Level 0: unhindered (no "hindered" suffix)
  TextSubs.add(MAN_PRE .. "unhindered" .. MAN_SUF,
    "If you were only wearing $1 $2 unhindered (0/14) and your stealth $3 be")

  local maneuver = {
    {"barely",          "1/14"},  {"minimally",       "2/14"},
    {"insignificantly", "3/14"},  {"lightly",         "4/14"},
    {"fairly",          "5/14"},  {"somewhat",        "6/14"},
    {"moderately",      "7/14"},  {"rather",          "8/14"},
    {"very",            "9/14"},  {"highly",          "10/14"},
    {"greatly",         "11/14"}, {"extremely",       "12/14"},
    {"overwhelmingly",  "13/14"}, {"insanely",        "14/14"},
  }
  for _, e in ipairs(maneuver) do
    TextSubs.add(MAN_PRE .. e[1] .. " hindered" .. MAN_SUF,
      "If you were only wearing $1 $2 " .. e[1] .. " (" .. e[2] .. ") hindered and your stealth $3 be")
  end
end

-------------------------------------------------------------------------------
-- Stealth "would/to be X hindered" (0-14) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  TextSubs.add("and your stealth (would|to) be unhindered\\.", "and your stealth $1 be unhindered (0/14).")
  local stealth_wt = {
    {"barely",          "1/14"},  {"minimally",       "2/14"},
    {"insignificantly", "3/14"},  {"lightly",         "4/14"},
    {"fairly",          "5/14"},  {"somewhat",        "6/14"},
    {"moderately",      "7/14"},  {"rather",          "8/14"},
    {"very",            "9/14"},  {"highly",          "10/14"},
    {"greatly",         "11/14"}, {"extremely",       "12/14"},
    {"overwhelmingly",  "13/14"}, {"insanely",        "14/14"},
  }
  for _, e in ipairs(stealth_wt) do
    TextSubs.add("and your stealth (would|to) be " .. e[1] .. " hindered\\.",
      "and your stealth $1 be " .. e[1] .. " (" .. e[2] .. ") hindered.")
  end
end

-------------------------------------------------------------------------------
-- "But considering" Currently Hindered (0-14) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local BC_PRE = "^But considering all the armor and shields you are wearing or carrying, you are currently "
  local BC_SUF = " and your stealth is"

  TextSubs.add(BC_PRE .. "unhindered" .. BC_SUF,
    "But considering all the armor and shields you are wearing or carrying, you are currently unhindered (0/14) and your stealth is")

  local bc_levels = {
    {"barely",          "1/14"},  {"minimally",       "2/14"},
    {"insignificantly", "3/14"},  {"lightly",         "4/14"},
    {"fairly",          "5/14"},  {"somewhat",        "6/14"},
    {"moderately",      "7/14"},  {"rather",          "8/14"},
    {"very",            "9/14"},  {"highly",          "10/14"},
    {"greatly",         "11/14"}, {"extremely",       "12/14"},
    {"overwhelmingly",  "13/14"}, {"insanely",        "14/14"},
  }
  for _, e in ipairs(bc_levels) do
    TextSubs.add(BC_PRE .. e[1] .. " hindered" .. BC_SUF,
      "But considering all the armor and shields you are wearing or carrying, you are currently " .. e[1] .. " (" .. e[2] .. ") hindered and your stealth is")
  end
end

-------------------------------------------------------------------------------
-- "and your stealth is X hindered" (0-14) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  TextSubs.add("and your stealth is unhindered\\.", "and your stealth is unhindered (0/14) .")
  local stealth_is = {
    {"barely",          "1/14"},  {"minimally",       "2/14"},
    {"insignificantly", "3/14"},  {"lightly",         "4/14"},
    {"fairly",          "5/14"},  {"somewhat",        "6/14"},
    {"moderately",      "7/14"},  {"rather",          "8/14"},
    {"very",            "9/14"},  {"highly",          "10/14"},
    {"greatly",         "11/14"}, {"extremely",       "12/14"},
    {"overwhelmingly",  "13/14"}, {"insanely",        "14/14"},
  }
  for _, e in ipairs(stealth_is) do
    TextSubs.add("and your stealth is " .. e[1] .. " hindered\\.",
      "and your stealth is " .. e[1] .. " (" .. e[2] .. ") hindered.")
  end
end

-------------------------------------------------------------------------------
-- Protection Offers (0-26) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local prot = {
    {"no",                "0/26"},  {"extremely terrible", "1/26"},
    {"terrible",          "2/26"},  {"dismal",             "3/26"},
    {"very poor",         "4/26"},  {"poor",               "5/26"},
    {"rather low",        "6/26"},  {"low",                "7/26"},
    {"fair",              "8/26"},  {"better than fair",   "9/26"},
    {"moderate",          "10/26"}, {"moderately good",    "11/26"},
    {"good",              "12/26"}, {"very good",          "13/26"},
    {"high",              "14/26"}, {"very high",          "15/26"},
    {"great",             "16/26"}, {"very great",         "17/26"},
    {"exceptional",       "18/26"}, {"very exceptional",   "19/26"},
    {"impressive",        "20/26"}, {"very impressive",    "21/26"},
    {"amazing",           "22/26"}, {"incredible",         "23/26"},
    {"tremendous",        "24/26"}, {"unbelievable",       "25/26"},
    {"god-like",          "26/26"},
  }
  for _, e in ipairs(prot) do
    TextSubs.add("(offers|to) " .. e[1] .. " (to|protection\\.)",
      "$1 " .. e[1] .. " (" .. e[2] .. ") $2")
  end
end

-------------------------------------------------------------------------------
-- Short Protection (1-15) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local short_prot = {
    {"poor",           "1/15"},  {"low",             "2/15"},
    {"fair",           "3/15"},  {"moderate",         "4/15"},
    {"good",           "5/15"},  {"very good",        "6/15"},
    {"high",           "7/15"},  {"very high",        "8/15"},
    {"great",          "9/15"},  {"very great",       "10/15"},
    {"extreme",        "11/15"}, {"exceptional",      "12/15"},
    {"incredible",     "13/15"}, {"amazing",          "14/15"},
    {"unbelieve?able", "15/15", "unbelievable"},
  }
  for _, e in ipairs(short_prot) do
    local repl = e[3] or e[1]
    TextSubs.add("^(\\s+)" .. e[1] .. " protection and",
      "$1" .. repl .. " (" .. e[2] .. ") protection and")
  end
end

-------------------------------------------------------------------------------
-- Damage Absorption (1-18) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local absorb = {
    {"very poor",     "1/18"},  {"poor",          "2/18"},
    {"low",           "3/18"},  {"somewhat fair",  "4/18"},
    {"fair",          "5/18"},  {"moderate",       "6/18"},
    {"good",          "7/18"},  {"very good",      "8/18"},
    {"high",          "9/18"},  {"very high",      "10/18"},
    {"great",         "11/18"}, {"very great",     "12/18"},
    {"extreme",       "13/18"}, {"exceptional",    "14/18"},
    {"incredible",    "15/18"}, {"outstanding",    "16/18"},
    {"amazing",       "17/18"}, {"unbelievable",   "18/18"},
  }
  for _, e in ipairs(absorb) do
    TextSubs.add("protection and " .. e[1] .. " damage absorption",
      "protection and " .. e[1] .. " (" .. e[2] .. ") damage absorption")
  end
end

-------------------------------------------------------------------------------
-- Item Durability is/are form (1-18) — from lich_repo_mirror
-------------------------------------------------------------------------------

do
  local dur = {
    {"extremely weak and easily damaged",          "1/18"},
    {"very delicate and easily damaged",           "2/18"},
    {"quite fragile and easily damaged",           "3/18"},
    {"rather flimsy and easily damaged",           "4/18"},
    {"particularly weak against damage",           "5/18"},
    {"somewhat unsound against damage",            "6/18"},
    {"appreciably sus?ceptible to damage",         "7/18", "appreciably susceptible to damage"},
    {"marginally vulnerable to damage",            "8/18"},
    {"of average construction",                    "9/18"},
    {"a bit safeguarded against damage",           "10/18"},
    {"rather reinforced against damage",           "11/18"},
    {"quite guarded against damage",               "12/18"},
    {"highly protected against damage",            "13/18"},
    {"very strong against damage",                 "14/18"},
    {"extremely resistant to damage",              "15/18"},
    {"unusually resilient to damage",              "16/18"},
    {"nearly impervious to damage",                "17/18"},
    {"practically invulnerable to damage",         "18/18"},
  }
  for _, e in ipairs(dur) do
    local repl = e[3] or e[1]
    TextSubs.add("(is|are) " .. e[1] .. ", and (is|are|has|have|contains?)",
      "$1 " .. repl .. " (" .. e[2] .. "), and $2")
  end
end

-------------------------------------------------------------------------------
-- Mana Sensing (from lich_repo_mirror)
-------------------------------------------------------------------------------

do
  -- Weak senses (3 levels)
  local weak = { {"dim", "1/3"}, {"glowing", "2/3"}, {"bright", "3/3"} }
  for _, e in ipairs(weak) do
    TextSubs.add("your weak senses and (see|hear) " .. e[1] .. " (streams|mana)",
      "your weak senses and $1 " .. e[1] .. " (" .. e[2] .. ") $2")
  end

  -- Developing senses (5 levels)
  local developing = { {"faint","1/5"}, {"muted","2/5"}, {"glowing","3/5"}, {"luminous","4/5"}, {"bright","5/5"} }
  for _, e in ipairs(developing) do
    TextSubs.add("your developing senses and (see|hear) " .. e[1] .. " (streams|mana)",
      "your developing senses and $1 " .. e[1] .. " (" .. e[2] .. ") $2")
  end

  -- Improving senses (9 levels)
  local improving = {
    {"faint","1/9"}, {"hazy","2/9"}, {"flickering","3/9"}, {"shimmering","4/9"},
    {"glowing","5/9"}, {"lambent","6/9"}, {"shining","7/9"}, {"fulgent","8/9"}, {"glaring","9/9"},
  }
  for _, e in ipairs(improving) do
    TextSubs.add("your improving senses and (see|hear) " .. e[1] .. " (streams|mana)",
      "your improving senses and $1 " .. e[1] .. " (" .. e[2] .. ") $2")
  end

  -- Base senses (21 levels) — also used for "to the X" and "above/below" forms
  local base21 = {
    "faint", "dim", "hazy", "dull", "muted", "dusky", "pale",
    "flickering", "shimmering", "pulsating", "glowing", "lambent",
    "shining", "luminous", "radiant", "fulgent", "brilliant",
    "flaring", "glaring", "blazing", "blinding",
  }
  for i, w in ipairs(base21) do
    local num = i .. "/21"
    -- "your senses" form
    TextSubs.add("your senses and (see|hear) " .. w .. " (streams|mana)",
      "your senses and $1 " .. w .. " (" .. num .. ") $2")
    -- "mana to the X" form
    TextSubs.add(w .. " mana to the (\\w*)(,|\\.)",
      w .. " (" .. num .. ") mana to the $1$2")
    -- "mana above/below you" form
    TextSubs.add(w .. " mana (above|below) you(,|\\.)",
      w .. " (" .. num .. ") mana $1 you$2")
  end
end

-------------------------------------------------------------------------------
-- Done loading
-------------------------------------------------------------------------------

echo("TextSubs loaded with " .. #subs .. " substitution rules.")
echo("Monitoring game output for text replacements...")

-- Keep script alive
while true do
  pause(60)
end
