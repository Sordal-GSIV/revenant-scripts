--- @revenant-script
--- name: flaretracker
--- version: 2.0.0
--- author: ChatGPT (original flaretracker_2.lic), ported by Revenant
--- @lic-certified: complete 2026-03-18
--- game: gs
--- description: Track weapon, spell, lore, and script flares during combat with real-time statistics
--- tags: tracking,item scripts,flares,data,abilities,combat
---
--- Changelog (from Lich5 flaretracker_2.lic):
---   v1.8.4 (2026-02-13): Fixed SanguineSacrifice immediate-damage branch flare output toggle
---   v1.8.3 (2026-02-13): Wrapped in module, added command aliases, robust shutdown, safe sounds
---   v1.8.2: Excluded flares with rate < 1.0% from initial output
---   v1.8.1: Fixed lag when sounds are enabled
---   v1.8.0: Updated for Bloodstone Jewelry flares
---   v1.7.0: Fixed highest combo save, sounds defaulted off
---   v1.6.0: Added toggle combo/flares output
---   v1.5.0: Fixed combo statistics, two-line HolyFire damage
---   v1.4.0: Combo tracking with persistence
---   v1.3.0: Active runtime commands
---   v1.2.0: High-score outlier guard
---   v1.1.0: Flares-per-attack calculation
---   v1.0.0: Initial release, 88 flare types
---
--- Usage (while running):
---   ;flaretracker reset          - Erase all saved statistical data
---   ;flaretracker show           - Show all flare statistics
---   ;flaretracker stats <type>   - Show stats for a specific flare type (partial match)
---   ;flaretracker toggle main    - Switch output to main window
---   ;flaretracker toggle fam     - Switch output to familiar window
---   ;flaretracker toggle combo   - Toggle combo output on/off
---   ;flaretracker toggle flares  - Toggle individual flare output on/off
---
--- Must have Familiar Window open to see output when using familiar mode.

--------------------------------------------------------------------------------
-- Kill protection
--------------------------------------------------------------------------------

no_kill_all()

--------------------------------------------------------------------------------
-- Non-damaging flare patterns
-- Key = flare name, value = Lua pattern string
-- Lua patterns use %( for literal parens, .- for non-greedy, etc.
--------------------------------------------------------------------------------

local NODMG_PATTERNS = {
    Xazkruvrixis                    = "Your xazkruvrixis .+ emits an ominous black%-green glow",
    Wither_LoreBenefit              = "A nebulous haze shimmers into view around .+, plunging inward in a dizzying spiral",
    Warding_Flare                   = "You hear a deafening wail as a ghostly white vapor surrounds you",
    WThorns640_Poison               = "One of the vines surrounding you lashes out at",
    WThorns640_Block                = "The thorny barrier surrounding you blocks the attack from",
    VolnArmor_DSFlare               = "Your .+ hums with spiritual force, filling you with a sense of divine vigilance",
    VialFlare                       = "spits .+ vial out and onto the ground where it lands with a crystalline",
    Untrammel209_LoreBenefit        = "you shifts abruptly, taking on an opalescent sheen that resists the web",
    TwistedArmor_Augmentation       = "The scintillating glow emanating from .+ on your .+ shimmers and intensifies",
    TrollHeart                      = "The .+ inside the necklace beats madly for a second",
    TBlood1125_StunBreak            = "Though you are stunned and reeling, you become aware of your pounding heart",
    TBlood1125_LoreBenefit          = "The scar on your .+ glows faintly white before fading altogether",
    TBlood1125_Healing              = "The bruises around your",
    TotemAnimalistic                 = "flows from it and over your exposed skin, imbuing a sudden rush of power from",
    TotemBestial                     = "the semitransparent figure moving to try to shield you from the attack",
    TotemShifting                    = "the motes encasing your arm in incandescence as a rush of power sinks into you",
    TotemFeral                       = "your vision briefly obscured with a bloody haze as a rush of strength surges",
    Tome_Spellwarden                = "As you stare at the words, you feel the weight of tactical knowledge build in you",
    TWard503_LoreBenefit            = "The glowing specks of .+ surrounding you intensify",
    Terror_Flare                    = "Your .+ releases a distorted black shadow",
    TReversion540                   = "Your surroundings melt away as the air around you shivers with a large flux of mana",
    TVerdict1603_Zealot             = "Your surroundings take on a violet sheen as you burn with zealous fervor",
    SteelSkin_Flare                 = "You exhale in pain as your skin rapidly hardens into a shimmering barrier",
    Sprite_DefensiveFlares          = "The .+ sprite on your shoulder projects a .+ barrier in front of you",
    Spritely_Maneuvering            = "The .+ sprite on your shoulder projects a .+ barrier, shielding you",
    Spritely_Intervention           = "You feel yourself being pulled upright as an .+ barrier appears in front of you",
    SStrike117_LoreBenefit          = "The invisible force draws back to guide you once more",
    Spore_Symbiosis                 = "Energy flows through you as .+ coax power from the symbiotic environs",
    Spore_Environment               = "As though invigorated by the subterranean surroundings",
    Spore_Dispersion                = "The dusty haze also entwines around .+ in a corkscrew",
    SWardingII107_LoreBenefit       = "Starburst patterns of pale blue light sweep forward from your chest",
    SWard319                        = "The evanescent shield shrouding you flares to life",
    Somnis                          = "For a split second, the striations of your",
    SigilStaff_DoubleCast           = "twining into an echo of your last spell",
    Sigil_of_Binding                = "A bolt of energy leaps from your .+ within bands of concentric geometry",
    Sidestep                        = "With a reflexive sidestep, you elude the attack!",
    ShieldCape_Block                = "forms a shield in front of you that turns solid enough to block",
    Rusalkan                        = "Exploding in a tumbling current of frothy foam, a wave of sea water suddenly materializes",
    RangerTrinket_Resistance        = "pulses briefly, deflecting some",
    RangerTrinket_ManaAbsorb        = "The .+ essence is drawn toward your",
    RFire515_NoCooldown             = "Moisture beads on the surface of your skin then evaporates away",
    RFire515_Channel                = "Seeing an opportunity, you accelerate time and empower your spell",
    Parasitic_BloodMatch            = "A cascade of needle%-like appendages puncture your flesh beneath your",
    Parasitic_Bulwark               = "Your .+ glisten as a sudden rush of blood spills across its surface",
    Parasitic_Defense               = "Several .+ reinforce your .+ to defend you against the incoming attack",
    NightshroudCloak_Hide           = "a cyclone of shadows emerge from your .+%.  The shadows swirl around",
    NTouch625_ArcaneReflex          = "Vital energy infuses you, hastening your arcane reflexes",
    NTouch625_PhysicalProwess       = "The vitality of nature bestows you with a burst of strength",
    Mirthbrand_JoyfulHeart          = "Hints of an old, joyful battle song at the edges of your hearing uplift your heart",
    MinorFire906_Ignite             = "Some of the flames from the stream of fire linger around",
    MechanizedArm_Block             = "Just as .+ attacks, your arm suddenly swings out and intercepts it!",
    ManaArmor_ManaShield            = "latticework springs up from the surface of your .+ and shields you",
    ManaArmor_ManaFlares            = "radiates from your .+ and you feel .+ mana surge into you",
    MArmor520_Water                 = "The raw elemental energy surrounding you takes on a watery look",
    MArmor520_Earth                 = "The energy surrounding you condenses into hard stone",
    LuckTalisman_Offensive          = "You hear the soft tinkle of rolling dice, followed by the sound of coins dropping",
    LuckTalisman_Defensive          = "You hear the soft tinkle of rolling dice, followed by a faint lucky feeling",
    LowSteel_HorrificVision         = "you, but freezes momentarily before madly clawing",
    Lathonian                       = "your .+ suddenly begins to glow with a polychromatic light",
    KroderineChains                 = "Your kroderine chains rapidly consume the magical power",
    Kroderine                       = "Your .+ cast%. The magic of the spell is instantly devoured",
    GlovesofTonis                   = "A forceful squall suddenly shoots through your",
    Ghezyte                         = "Cords of plasma%-veined grey mist seep from your",
    ForestArmor_WindGust            = "A spiraling funnel of air bursts from your",
    ForestArmor_LeafSwirl           = "Diamond%-shaped leaves sprout from your",
    ForestArmor_MudSling            = "A thick clump of mud catapults from your",
    ForestArmor_WoodlandEmpathy     = "you suddenly have a clearer understanding of nature",
    FReward115                      = "The dull golden nimbus surrounding you flares into life as it glows brightly",
    FReproach312_WisdomBonus        = "The .+ sphere begins to move in an ever%-increasingly fast circle above your head",
    Fyrswnava_Flares                = "Translucent celadon sap pools into a globular spherule",
    Ethereal_Armor                  = "ethereal chains encase your body against",
    EonakArm_Block                  = "your arm suddenly swings out and intercepts it",
    Ensorcell_Health                = "You feel healed",
    Ensorcell_Mana                  = "You feel empowered",
    Ensorcell_Spirit                = "You feel rejuvenated",
    Ensorcell_Stamina               = "You feel reinvigorated",
    Ensorcell_AS_CS                 = "You feel energized",
    Elven_SpellBarrier              = "Strands of translucent mana swirl about you, creating a protective barrier",
    Elven_SpellAlacrity             = "Your .+ flares with a pale light",
    ElementalDefenderRing           = "The .+ on your .+ flares brightly as it absorbs",
    ETargeting425_LoreBenefit       = "elemental energy energizes you",
    EDeflection507_LoreBenefit      = "A shimmering field of energy flashes around you, reflecting",
    EDefenseIII414_LoreBenefit      = "A heavy barrier of stone momentarily forms around you",
    EBias508_LoreBenefit            = "Your magical awareness grows more acute for an instant",
    EBarrier430_LoreBenefit         = "Your skin hardens for a moment and softens",
    Dramatic_Drapery_Wondorous      = "Branching filaments of power snap outward from your",
    Dramatic_Drapery_Masquerade     = "distorts the air around you, confounding an",
    Dragonclaw1209_Flare            = "As you strike, a deep golden light surrounds your",
    Deciduous_DecayFlare            = "The motes rapidly sink into .+, causing a sickly color to creep over",
    Death_Flare                     = "Your .+ emits an ominous black%-green glow",
    CursedArmor_Calm                = "as your vision burns with hypnotic resolve",
    CursedArmor_DS_TD               = "Dark tendrils lash out from your .+ and form a crimson%-runed shroud",
    CursedArmor_AS_CS               = "Dark tendrils lash out from your .+ and invigorate your resolve",
    Bubble                          = "high%-pitched sound and causes your skin and muscles to",
    Breeze612_Tailwind              = "A favorable tailwind springs up behind you",
    Breeze612_Offensive             = "is buffeted by a burst of wind and pushed back",
    Brace1214_Parry                 = "Using the bone plates surrounding your forearms, you parry the attack",
    Brace1214_Disarm                = "strikes one of the bony protrusions on your forearms and it is wrenched",
    BootsofTonis                    = "a swirling whirlwind bursts into life around your form%. Time seems to slow",
    BShatter1106_LoreBenefit        = "The internal skeletal structure of .+ implodes inward upon itself",
    Blink1215                       = "You find yourself moved several feet from your original position",
    Blink                           = "Your .+ suddenly light.? up with hundreds of tiny blue sparks",
    Benediction307_LoreBenefit      = "Pearly light flares up suddenly from within you, lending strength",
    Barkskin605                     = "The layer of bark on you hardens and absorbs",
    Banshee                         = "emits a deafening wail as a bright red glow erupts from its surface",
    BalanceFrenzy_Flare             = "The .+ flashes a shade of scarlet",
    BalanceFrenzy_DoubleFlare       = "The .+ is suddenly engulfed in scarlet light",
    ASpear1408_Dispel               = "With an opaline flare, the nacreous spear passes through",
    Animalistic_InstinctFlares      = "up from the point of impact, spreading over the chest of your",
    Aganjira                        = "Mana cascades across your .+, causing the fabric to shiver against your skin",
    Adamantine                      = "the incredibly hard surface of your adamantine",
    Arboreal_AgonyFlare             = "Ethereal .+ multiply in a profusion of flora over",
    Acuity_Flare                    = "Your .+ glows intensely with a verdant light",
    BindingShot_GS                  = "Released from the projectile, a slim canister splits in flight and unfurls a net",
    ChameleonShroud_GS              = "A tenebrous shroud stitches itself into existence around you",
    DefensiveDuelist_GS             = "you take the opportunity to jab .+ hard in the wrist",
    DispulsionWard_GS               = "The anti%-magic is blocked by an unseen ward",
    ElementalResonance_GS           = "Elemental currents gather around your fingers, resonating with your spell",
    GrandTheftKobold_GS             = "You feel like you could try that again",
    HW_WardenoftheDamned_GS         = "Glinting golden and silver threads escape from the air around you",
    HuntersAfterimage_GS            = "A radiant afterimage of the arrow appears in your ready hand",
    MephiticBrume_GS                = "A noxious brume, murky and foul%-smelling, erupts from your body",
    MetamorphicShield_GS            = "A distorted ripple of metamorphic energy races across your",
    MirrorImage_GS                  = "Fleeting and insubstantial, a mirror image of you shimmers into view",
    OneShotOneKill_GS               = "With singular precision, you hone in on a critical flaw in",
    SerendipitousHex_GS             = "A deep emerald green mist coils around your forearms as your spell reforms",
    StolenPower_GS                  = "An inky black mist coils around your forearms as your spell reforms",
    TacticalCanny_GS                = "The pain sharpens your senses and you begin to plan around your foe",
    TerrorsTribute_GS               = "Countless phantasms peel away from you and lurch disjointedly outward",
    TetheredStrike_GS               = "is held fast by some unseen force!",
}

--------------------------------------------------------------------------------
-- Damaging flare patterns
--------------------------------------------------------------------------------

local DMG_PATTERNS = {
    Acid_Flare                  = "Your .+ releases? a spray of acid",
    Air_Flare                   = "Your .+ unleashes a blast of air",
    Air_LoreFlare               = "A fierce whirlwind erupts? around .+ encircling",
    Air_LoreFlareDoT            = "The cyclone whirls around .+ anew",
    Air_GEF                     = "A howling gale of steaming air rushes from",
    Animalistic_FuryFlares      = "slender tendrils rising up to coalesce into the ethereal form of",
    Balefire_DemonAttack        = "shudders slightly as chaotic energy is drawn from its form",
    BallSpell_Splash            = "A burst of .+ from your .+ flies off and hits",
    Blessing_LoreFlare          = "A reassuring feeling of mental acuity settles over you",
    Briar                       = "Vines of vicious briars whip out from your",
    ChainSpear                  = "The .+ head of your .+ catches across",
    ChronomageDagger            = "Taking a chance you hurl .+ at .+ again and suddenly everything returns to normal",
    CloakofShadows_Retribution  = "A dark shadowy tendril rises up from your skin",
    Cold_Flare                  = "Your .+ glows? intensely with a cold blue light",
    Cold_GEF                    = "A vortex of razor%-sharp ice gusts from",
    Coraesine_Pure              = "A massive vortex of shrapnel%-laden air coalesces around",
    CoraesineRelic              = "The coraesine relic on your",
    Daybringer_Script           = "A torrent of .+%-colored plasma bursts forth from your",
    Nightbringer_Script         = "coil of .+%-colored energy lashes out from your",
    DayNightbringer_AnomalyFlare = "A .+%-colored beam of light erupts from the .+ light at",
    Demonology_LoreFlare        = "Shadowy claws of pure essence burst from",
    Demonology_LoreFlareDoT     = "Shadowy tendrils coil around .+, swiftly siphoning away ambient energy",
    Disintegration_Flare        = "Your .+ releases? a shimmering beam of disintegration",
    Dispel_Disruption           = "Your .+ glows? brightly for a moment, consuming the magical energies",
    Dispel_FluxCrit             = "fluxes chaotically",
    Disruption_Flare            = "Your .+ releases? a quivering wave of disruption",
    Earth_LoreFlare             = "Chunks of earth violently orbit .+ pelting",
    Earth_LoreFlareDoT          = "The ground trembles violently, pelting .+ again",
    Earth_GEF                   = "A violent explosion of frenetic energy rumbles from",
    Energy_Weapon               = "A beam of .+ energy emits from the tip of your",
    Fire_Flare                  = "Your .+ flares? with a burst of flame",
    Fire_LoreFlare              = "A blazing inferno erupts around .+ scorching everything",
    Fire_LoreFlareDoT           = "The inferno blazing around .+ ignites anew",
    Fire_GEF                    = "Burning orbs of pure flame burst from",
    Firewheel                   = "Your .+ emits a fist%-sized ball of lightning%-suffused flames",
    GlobusElanthias             = "Rising from the .+ that is wedged into your",
    GlobusNaidem                = "Lashing out from your .+, .+ extends one hand and rakes",
    Grapple_Flare               = "Your .+ releases? a twisted tendril of force",
    GreaterBlackOra             = "A low moaning emanates from your .+ as the shadows swirl off",
    GreaterRhimar               = "A suffusion of frost flashes down the length of",
    GuidingLight_2ndFlare       = "Your .+ sprays? with a burst of plasma energy",
    HolyFire                    = "Your .+ bursts alight with leaping tongues of holy fire",
    HolyWater                   = "Your .+ sprays? forth a shower of pure water",
    Ice_GEF                     = "A vortex of razor%-sharp ice gusts? from",
    Impact_Flare                = "Your .+ releases? a blast of vibrating energy",
    Knockout                    = "Your .+ bounce off the head of",
    Lightning_GEF               = "A vicious torrent of crackling lightning surges from",
    Lightning_Flare             = "Your .+ emits? a searing bolt of lightning",
    LowSteel                    = "Your lowsteel .+ unleashes a blast of psychic energy",
    LowSteel_DoT                = "convulses in horrified agony",
    Manipulation_LoreFlare      = "Loose debris tears itself upward around",
    Manipulation_LoreFlareDoT   = "Debris continues to batter .+ from every angle",
    Magma_Flare                 = "Your .+ expels? a glob of molten magma",
    Mana_Flare                  = "Your .+ pulses with a white%-blue light!",
    Mechanical_Flare            = "Your .+ releases a small spring%-loaded",
    MechanicalQuiver            = "The tip of the spiraled arrow suddenly shatters and bursts",
    MindWrack_Flare             = "Your .+ unleashes a blast of psychic energy",
    MinorAcid904_Melt           = "Acid continues to eat away at",
    MinorFire906_Burn           = "The flames around .+ continue to burn",
    MinorShock901_StunShock      = "Tiny arcs of lightning briefly dance across",
    MinorWater903_Soak          = "The water completely drenches",
    Mirthbrand_BraveCompanions  = "One of the spectral combatants rushes at",
    Mirthbrand_GlitterFlare     = "A winking spray of glittering motes erupts from your",
    NebularWeapon               = "Cold as the great void, the silvery power of starlight channels through your",
    Necromancy_LoreFlare        = "A sickly green aura radiates from",
    Necromancy_LoreFlareDoT     = "Small pieces of flesh rot off",
    Nerve                       = "Several thin, fibrous .+ filaments erupt from your",
    Pestilence716_Reactive      = "You exhale a virulent green mist toward",
    Pestilence716_DoT           = "Pus%-filled sores erupt",
    Plasma_Flare                = "Your .+ pulses? with a burst of plasma energy",
    Phytomorphic_PutrescenceFlare = "Silvery vapor%-wreathed .+ lash out at",
    Parasitic_BloodFlares       = "You wince as .+ draws upon your blood as it strikes",
    Pure_Adamantine             = "Your .+ meets .+ with unyielding force!",
    Pure_Drakar                 = "A scorching blast of golden fire blazes forth from your",
    Pure_Drakar_2ndFlare        = "Sparks swirl about .+, spiraling inward to ignite the air",
    Pure_Eonake                 = "Your .+ bursts with radiant silver light",
    Pure_Faewood                = "Crackling like autumn leaves, a conflagration of red%-gold flame leaps from your",
    Pure_Gornar                 = "Your .+ thrums, pulsing a pounding rhythm and battering",
    Pure_Gornar_2ndFlare        = "Reverberating, the thrum intensifies to an ominous rumble",
    Pure_Rhimar                 = "An arctic blast from your .+ in freezing fog",
    Pure_Rhimar_2ndFlare        = "With a crystalline peal, the frigid fog enveloping",
    Pure_Zorchar                = "Frayed forks of blue%-white lightning leap from your",
    Pure_Zorchar_2ndFlare       = "With an echoing thunderclap, an eye%-searing arc of electricity",
    Purified_Sephwir            = "With a crepitant snap, the .+ splinters on impact",
    Religion_LoreFlare          = "Divine flames kindle around .+ leaping forth to engulf",
    Religion_LoreFlareDoT       = "The sacred inferno surrounding .+ ignites anew",
    SanguineSacrifice           = "suffers an additional .+ damage!",
    SanguineSacrifice_Overflow  = "Sanguine brilliance strikes .+ a rupturing blow!",
    ShieldCape_BroochFlare      = "attached to the left shoulder of your .+ suddenly explodes with a brilliant flash",
    ShadowDeathWeapon           = "Ravenous tendrils of shadow burst forth from .+, draining the very life",
    Greater_SD_Darkrasp         = "Ravenous tendrils of tangible shadow rip free from",
    SigilStaff_Dispel           = "Tendrils of .+ energy lash out from your .+ toward .+ and cage",
    Smite302_Infusion           = "With a sudden burst of divine insight, you're able to amplify",
    Smite302_InstantDeath       = "A minuscule blue%-white star slowly ascends from the floor",
    SolarWeapon                 = "Searing hot, the golden power of the sun is channeled through your",
    SonicWeapon_1stFlare        = "Your .+ unleashes a blast of sonic energy at",
    SonicWeapon_2ndFlare        = "With a loud snap, a blast of energy bursts from your",
    Spikes                      = "A spike on your .+ jabs into",
    SpiritGauntlet              = "Your bolt of energy suddenly bursts, scattering into particles",
    Spore_Flare                 = "Nebulous .+ tendrils curl from your .+, enswathing",
    Spore_Burst                 = "The .+ spores churning around simultaneously burst into an explosion",
    SSlayer_240                 = "Abruptly, you sense the attention of your spirit slayer focus upon",
    Steam_Flare                 = "Your .+ erupts? with a plume of steam",
    Steam_GEF                   = "A howling gale of steaming air rushes from",
    Summoning_LoreFlare         = "A radiant mist surrounds .+ unfurling into a whip of plasma",
    Summoning_LoreFlareDoT      = "The whip of plasma continues to wreathe",
    Telepathy_LoreFlare         = "Rippling and half%-seen, strands of psychic power unravel from",
    Telepathy_LoreFlareDoT      = "Locked in mental durance, .+ is assailed by some unseen attack",
    Tome_Spellglider            = "your .+ unleashes a dazzling arcane projectile",
    Tome_Spellweaver            = "Arcane energy streaks toward .+ and collides in a volatile clash",
    Tome_Spellvault             = "is buffeted by the corruscating arcane energy",
    Transformation_LoreFlare    = "Dozens of needle%-like tendrils explode from your forearms",
    TwinWeapon_Detonation       = "Tendrils .+ energy lash out from your",
    Twisted_Flare               = "A scintillating .+ glow shimmers and oscillates across your",
    Unbalance_Flare             = "Your .+ unleashes an invisible burst of force",
    Vacuum_Flare                = "your .+ seems to folds? inward and draws its surroundings closer",
    Valence_LashofLoraetyr      = "Several archaic sigils flash briefly along your",
    Valence_SliceofShientyr     = "A coil of spectral .+ energy bursts? out of thin air",
    Vethinye                    = "it entwines you in night blue wisps of ephemera",
    VibrationChant_Shatter      = "You focus your voice on .+ with perfect resonance, causing it to shatter",
    Void_GEF                    = "A nebulous dome of .+ discharges? from",
    Water_Flare                 = "Your .+ shoots? a blast of water",
    WildfireOil                 = "A swirl of alchemical fire, scintillating blue and orange in hue",
    WebbingCaughtFire           = "The webbing around .+ catches fire",
    WEntropy603_Dot             = "Patches of discolored rot spread further, eating away at",
    FAura1706                   = "The flaming aura surrounding you lashes out at",
    Fervor1618                  = "Your .+ surges with power as .+ coalesces around it",
    ELink1117_Overload          = "An overload of mental energies pulse through your link",
    ELink1117_Propagation       = "Ripples of wavering energy coalesce around",
    MArmor520_Fire              = "The fiery torrent of energy surrounding you flares toward",
    BS_Reckoning                = "With a deafening crack of thunder, a frayed bolt of violet",
    BS_HallowedReprisal         = "Fiery red barbs uncoil from the shadows nearby and lash out at",
    BS_DivineBulwark            = "shield springs into being between you and your attacker to temper the blow",
    FatalAfflares               = "A torrent of thick crimson blood rains down upon",
    QuintonManse                = "Your .+ pulses? with a deep purple and black hue",
    CA_ArachnesBite             = "Afflicted by your .+ reels as the crimson%-swirled poison does its work",
    CA_FoolsDeathwort           = "Afflicted by your .+ reels as the violet%-tinted poison does its work",
    CA_OphidiansKiss            = "Afflicted by your .+ reels as the indigo%-tinted poison does its work",
    CA_RavagersRevenge          = "Afflicted by your .+ reels as the maroon%-swirled poison does its work",
    CA_ShatterlimbPoison        = "Afflicted by your .+ reels as the murky blue poison does its work",
    CA_MajorPoison_Dot          = "wavers with infirmity and pales slightly",
    BloodBoil_GS                = "A fiery aura spirals from your hands",
    BurningBlood_GS             = "Your blood ignites as it sprays through the air",
    EtherFlux_GS                = "Rapidly fluctuating elemental power blooms",
    ChargedPresence_GS          = "A powerful jolt of electricity erupts from your crackling aura",
    ThornsDisruption_GS         = "Light and shadow flicker erratically around you as a wave of pure disruptive force",
    ThornsFrost_GS              = "Frost crystallizes beneath .+ as a howling arctic wind buffets",
    ThornsImpact_GS             = "The air around .+ pulses rapidly with violent oscillations",
    ThornsPlasma_GS             = "Plasmatic tendrils of blinding light radiate from your vicinity",
    Arcane_Sidearm              = "^You .+ with a vapor%-haloed .+ at",
}

--------------------------------------------------------------------------------
-- Attack patterns (for counting total attacks)
--------------------------------------------------------------------------------

local ATTACK_PATTERNS = {
    "You swing a",
    "You thrust with",
    "You slash with",
    "You hurl a",
    "You fire a",
    "You take aim and",
    "You attempt to",
    "You make a precise attempt to",
    "You gesture at",
    "You channel at",
    "You connect",
    "Your .+ connects",
    "You lunge forward",
    "In a fluid whirl, you sweep your",
}

--------------------------------------------------------------------------------
-- Two-line damage flare types (need to read ahead for damage)
--------------------------------------------------------------------------------

local TWO_LINE_DAMAGE_TYPES = {
    DoT = true,
    GEF = true,
    Firewheel = true,
    Greater_Rhimar = true,
    HolyFire = true,
    ELink1117_Propagation = true,
}

--- Flares to ignore for combo counting (defensive, passive, etc.)
local COMBO_IGNORE_TYPES = {
    DoT = true,
    FAura1706 = true,
    Defensive = true,
    Sward319 = true,
    WThorns640 = true,
    VolnArmor = true,
    Untrammel209 = true,
    TwistedArmor_Augmentation = true,
    TrollHeart = true,
    TBlood1125 = true,
}

--- Combo labels by flare count
local COMBO_LABELS = {
    [3]  = "TRIPLE",
    [4]  = "SUPER",
    [5]  = "HYPER",
    [6]  = "BRUTAL",
    [7]  = "MASTER",
    [8]  = "AWESOME",
    [9]  = "BLASTER",
    [10] = "MONSTER",
    [11] = "KING",
    [12] = "KILLER",
    [13] = "KILLER",
    [14] = "KILLER",
    [15] = "KILLER",
    [16] = "KILLER",
    [17] = "KILLER",
    [18] = "KILLER",
    [19] = "KILLER",
    [20] = "ULTRA",
}

--------------------------------------------------------------------------------
-- Helper: check if a flare type name contains any of the combo-ignore keys
--------------------------------------------------------------------------------

local function is_combo_ignored(flare_type)
    for key, _ in pairs(COMBO_IGNORE_TYPES) do
        if string.find(flare_type, key, 1, true) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Helper: check if a flare type is a two-line damage type
--------------------------------------------------------------------------------

local function is_two_line_damage(flare_type)
    for key, _ in pairs(TWO_LINE_DAMAGE_TYPES) do
        if string.find(flare_type, key, 1, true) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Statistics helpers
--------------------------------------------------------------------------------

local function calculate_average(values)
    local sum = 0
    local count = 0
    for _, v in ipairs(values) do
        if type(v) == "number" and v > 0 then
            sum = sum + v
            count = count + 1
        end
    end
    if count == 0 then return 0 end
    return sum / count
end

local function calculate_median(values)
    local nums = {}
    for _, v in ipairs(values) do
        if type(v) == "number" and v > 0 then
            table.insert(nums, v)
        end
    end
    if #nums == 0 then return 0 end
    table.sort(nums)
    local len = #nums
    return (nums[math.floor((len - 1) / 2) + 1] + nums[math.floor(len / 2) + 1]) / 2.0
end

local function calculate_std_deviation(values)
    local nums = {}
    for _, v in ipairs(values) do
        if type(v) == "number" and v > 0 then
            table.insert(nums, v)
        end
    end
    if #nums == 0 then return 0 end
    local mean = calculate_average(values)
    local variance = 0
    for _, v in ipairs(nums) do
        variance = variance + (v - mean) ^ 2
    end
    variance = variance / #nums
    return math.floor(math.sqrt(variance) * 100 + 0.5) / 100
end

local function calculate_appearance_rate(flare_hits, total_flare_hits)
    if total_flare_hits == 0 then return 0 end
    return math.floor((flare_hits / total_flare_hits) * 10000 + 0.5) / 100
end

local function calculate_flares_per_attack(flare_hits, total_attacks)
    if flare_hits == 0 or total_attacks == 0 then return "N/A" end
    return string.format("%.1f", total_attacks / flare_hits)
end

local function calculate_damage_distribution(values)
    local ranges = {
        { label = "0 - 9",   low = 0,   high = 9,   count = 0 },
        { label = "10 - 19", low = 10,  high = 19,  count = 0 },
        { label = "20 - 29", low = 20,  high = 29,  count = 0 },
        { label = "30 - 39", low = 30,  high = 39,  count = 0 },
        { label = "40 - 49", low = 40,  high = 49,  count = 0 },
        { label = "50 - 59", low = 50,  high = 59,  count = 0 },
        { label = "60 - 69", low = 60,  high = 69,  count = 0 },
        { label = "70 - 79", low = 70,  high = 79,  count = 0 },
        { label = "80 - 89", low = 80,  high = 89,  count = 0 },
        { label = "90 - 99", low = 90,  high = 99,  count = 0 },
        { label = "100+",    low = 100, high = 99999, count = 0 },
    }
    for _, v in ipairs(values) do
        if type(v) == "number" then
            for _, r in ipairs(ranges) do
                if v >= r.low and v <= r.high then
                    r.count = r.count + 1
                    break
                end
            end
        end
    end
    local result = {}
    for _, r in ipairs(ranges) do
        if r.count > 0 then
            table.insert(result, { label = r.label, count = r.count })
        end
    end
    return result
end

--- Count total flare events across all types
local function count_all_flare_hits(damage_data)
    local total = 0
    for _, values in pairs(damage_data) do
        total = total + #values
    end
    return total
end

--------------------------------------------------------------------------------
-- Output helpers
--------------------------------------------------------------------------------

local use_familiar_window = false

local function echo_to_familiar(message)
    local fam_begin = "<pushStream id=\"familiar\" ifClosedStyle=\"watching\"/><output class=\"mono\"/>\n"
    local fam_end = "\n<output class=\"\"/><popStream/>\r\n"
    respond(fam_begin .. message .. fam_end)
end

local function echo_flare(message)
    if use_familiar_window then
        echo_to_familiar(message)
    else
        echo(message)
    end
end

local function format_flare_data(flare_type, total_damage, high_score, avg_damage, appearance_rate, flares_per_attack, combo_position)
    local max_len = 27
    local display_name = string.gsub(flare_type, "_", " ")
    if combo_position then
        display_name = combo_position .. ". " .. display_name
    end
    -- Pad or truncate to max_len
    if #display_name < max_len then
        display_name = display_name .. string.rep(" ", max_len - #display_name)
    elseif #display_name > max_len then
        display_name = string.sub(display_name, 1, max_len)
    end

    total_damage = total_damage or 0
    high_score = high_score or 0
    avg_damage = avg_damage or 0
    appearance_rate = appearance_rate or 0
    flares_per_attack = flares_per_attack or "N/A"

    return string.format(
        "%-" .. max_len .. "s | DMG: %3d | HS: %3d | AVG: %3s | RATE: %5.1f%% | 1 per %4s ATTACKS",
        display_name,
        total_damage,
        high_score,
        string.format("%.0f", avg_damage),
        appearance_rate,
        flares_per_attack
    )
end

local function display_flare_data(flare_type, total_damage, high_score, avg_damage, appearance_rate, flares_per_attack, combo_position)
    echo_flare(format_flare_data(flare_type, total_damage, high_score, avg_damage, appearance_rate, flares_per_attack, combo_position))
end

--------------------------------------------------------------------------------
-- Full statistics display
--------------------------------------------------------------------------------

local function display_statistics(damage_data, high_scores, total_attacks, show_explanatory)
    local total_flare_hits = count_all_flare_hits(damage_data)

    -- Separate into nodmg and dmg, then sort alphabetically
    local nodmg_keys = {}
    local dmg_keys = {}
    for flare_type, _ in pairs(damage_data) do
        if NODMG_PATTERNS[flare_type] then
            table.insert(nodmg_keys, flare_type)
        else
            table.insert(dmg_keys, flare_type)
        end
    end
    table.sort(nodmg_keys)
    table.sort(dmg_keys)

    -- Display non-damaging flares
    for _, flare_type in ipairs(nodmg_keys) do
        local values = damage_data[flare_type]
        local total_flares = #values
        local rate = calculate_appearance_rate(total_flares, total_flare_hits)
        if rate >= 1.0 then
            local fpa = calculate_flares_per_attack(total_flares, total_attacks)
            local display_name = string.gsub(flare_type, "_", " ")
            if #display_name < 27 then
                display_name = display_name .. string.rep(" ", 27 - #display_name)
            end
            echo(string.format(
                "\n %-27s | Total: %4d | Rate: %4.1f%% | %11s ATTACKS",
                display_name, total_flares, rate, fpa
            ))
        end
    end

    -- Display damaging flares with full stats
    for _, flare_type in ipairs(dmg_keys) do
        local values = damage_data[flare_type]
        if #values > 0 then
            local avg = calculate_average(values)
            local median = calculate_median(values)
            local std_dev = calculate_std_deviation(values)
            local hs = high_scores[flare_type] or 0
            local total_flares = #values
            local rate = calculate_appearance_rate(total_flares, total_flare_hits)
            if rate >= 1.0 and not (hs == 0 and avg == 0 and median == 0 and std_dev == 0) then
                local fpa = calculate_flares_per_attack(total_flares, total_attacks)
                local display_name = string.gsub(flare_type, "_", " ")
                if #display_name < 27 then
                    display_name = display_name .. string.rep(" ", 27 - #display_name)
                end
                echo(string.format(
                    "\n %-27s | Total: %-4d | Rate: %4.1f%% | %-11s ATTACKS",
                    display_name, total_flares, rate, fpa
                ))
                echo("  High Score: " .. hs)
                echo("  Average Damage: " .. string.format("%.2f", avg))
                echo("  Median Damage: " .. string.format("%.2f", median))
                echo("  Standard Deviation: " .. string.format("%.2f", std_dev))
                local dist = calculate_damage_distribution(values)
                if #dist > 0 then
                    echo("  Damage Distribution:")
                    for _, d in ipairs(dist) do
                        echo("  " .. d.label .. ": " .. d.count)
                    end
                end
            end
        end
    end

    echo("\nTotal Attacks: " .. total_attacks .. "\nEnd of flare type statistical output.")

    if show_explanatory then
        echo("\n\nNote: 'RATE' shows how often each flare type appears specifically for you in combat. " ..
            "It indicates the frequency of each specific flare type when a flare occurs. " ..
            "Both of these statistics are personalized to your playstyle and vary based on " ..
            "factors like your profession, training, gear, and the total number of flare types " ..
            "you can generate.")
    end
end

--------------------------------------------------------------------------------
-- Find closest flare type by partial name match
--------------------------------------------------------------------------------

local function find_closest_flare_type(partial, damage_data)
    local normalized = string.lower(string.gsub(partial, " ", "_"))
    local best_match = nil
    local best_pos = 999999
    for key, _ in pairs(damage_data) do
        local lower_key = string.lower(key)
        local pos = string.find(lower_key, normalized, 1, true)
        if pos and pos < best_pos then
            best_pos = pos
            best_match = key
        end
    end
    return best_match
end

--------------------------------------------------------------------------------
-- Persistence via CharSettings (JSON-serialized)
--------------------------------------------------------------------------------

local function load_data()
    local raw = CharSettings.flaretracker_data
    if raw and raw ~= "" then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then
            -- Ensure sub-tables exist
            data.damage_data = data.damage_data or {}
            data.high_scores = data.high_scores or {}
            data.total_attacks = data.total_attacks or 0
            data.highest_combo = data.highest_combo or { flare_count = 0, label = "NONE" }
            data.prefs = data.prefs or {}
            data.prefs.echo_window = data.prefs.echo_window or "main"
            data.prefs.show_combo_output = (data.prefs.show_combo_output == nil) and true or data.prefs.show_combo_output
            data.prefs.show_flare_output = (data.prefs.show_flare_output == nil) and true or data.prefs.show_flare_output
            return data
        end
    end
    -- Return fresh initial data
    return {
        damage_data = {},
        high_scores = {},
        total_attacks = 0,
        highest_combo = { flare_count = 0, label = "NONE" },
        prefs = {
            echo_window = "main",
            show_combo_output = true,
            show_flare_output = true,
        },
    }
end

local function save_data(data)
    local ok, encoded = pcall(Json.encode, data)
    if ok then
        CharSettings.flaretracker_data = encoded
    else
        echo("FlareTracker: Failed to save data: " .. tostring(encoded))
    end
end

--------------------------------------------------------------------------------
-- Match a line against a table of patterns; return the matched key or nil
--------------------------------------------------------------------------------

local function match_any(line, patterns)
    for name, pattern in pairs(patterns) do
        if string.find(line, pattern) then
            return name
        end
    end
    return nil
end

local function match_attack(line)
    for _, pattern in ipairs(ATTACK_PATTERNS) do
        if string.find(line, pattern) then
            return true
        end
    end
    return false
end

--- Extract damage from a line: "X points of damage!" or "suffers an additional X damage!"
local function extract_damage(line)
    local dmg = string.match(line, "(%d+) points? of damage!")
    if dmg then return tonumber(dmg) end
    dmg = string.match(line, "suffers an additional (%d+) damage!")
    if dmg then return tonumber(dmg) end
    dmg = string.match(line, "You feel (%d+) mana surge into you")
    if dmg then return tonumber(dmg) end
    dmg = string.match(line, "You gain (%d+) mana")
    if dmg then return tonumber(dmg) end
    return nil
end

--- Check if a line is a "break" line (no damage, combat boundary)
local function is_break_line(line)
    if string.find(line, "AS:") and string.find(line, "vs DS:") then return true end
    if string.find(line, "Roundtime") then return true end
    if string.find(line, "CS:") and string.find(line, "vs TD:") then return true end
    if string.find(line, "is unaffected") then return true end
    if string.find(line, "with little effect") then return true end
    if string.find(line, "no effect") then return true end
    if string.find(line, "thorny barrier surrounding .+ blocks") then return true end
    if string.find(line, "blinks and looks around in confusion") then return true end
    if string.find(line, "manages to dodge the licking flames") then return true end
    if string.find(line, "unharmed by the") then return true end
    if string.find(line, "scoffs at the") then return true end
    return false
end

--- Check if a line matches any known flare pattern
local function is_new_flare_pattern(line)
    if match_any(line, NODMG_PATTERNS) then return true end
    if match_any(line, DMG_PATTERNS) then return true end
    return false
end

--------------------------------------------------------------------------------
-- MAIN SCRIPT
--------------------------------------------------------------------------------

local data = load_data()
local damage_data = data.damage_data
local high_scores = data.high_scores
local total_attacks = data.total_attacks
local highest_combo = data.highest_combo
local prefs = data.prefs

use_familiar_window = (prefs.echo_window == "familiar")

-- Display highest combo record on startup
if highest_combo and highest_combo.flare_count and highest_combo.flare_count > 0 and highest_combo.label then
    echo_flare("\n" .. string.rep("=", 37) .. "HIGHEST COMBO RECORD" .. string.rep("=", 37) ..
        "\n" .. string.rep(" ", 37) .. highest_combo.flare_count .. " FLARE " .. highest_combo.label .. " COMBO\n")
else
    echo_flare("No highest combo record found.")
end

-- Display initial statistics
display_statistics(damage_data, high_scores, total_attacks, true)

-- Track events for save batching
local event_counter = 0
local save_interval = 10

-- Flare combo tracking
local flare_events = {}
local COMBO_TIME_WINDOW = 1.5

-- Register cleanup hook
before_dying(function()
    data.damage_data = damage_data
    data.high_scores = high_scores
    data.total_attacks = total_attacks
    data.highest_combo = highest_combo
    data.prefs = prefs
    save_data(data)
    echo_flare("Flare damage data, high scores, and attack counts saved. Exiting script.")
end)

-- Downstream hook for line matching
DownstreamHook.add("flaretracker_hook", function(line)
    -- Pass through; we process via the main get() loop
    return line
end)

before_dying(function()
    DownstreamHook.remove("flaretracker_hook")
end)

--------------------------------------------------------------------------------
-- Main processing loop
--------------------------------------------------------------------------------

local pending_line = nil

while true do
    local line = pending_line or get()
    pending_line = nil

    if not line then
        -- no line available, continue
        goto continue_main
    end

    local stripped = line:match("^%s*(.-)%s*$") or line

    ---------------------------------------------------------------------------
    -- Handle ;flaretracker commands via ;send or upstream
    ---------------------------------------------------------------------------
    -- Commands arrive via Script.vars or ;send mechanism
    -- We check for known command patterns in the line (from send_to_script)
    if string.find(stripped, "^toggle%s+main$") or stripped == "main" then
        use_familiar_window = false
        prefs.echo_window = "main"
        data.prefs = prefs
        save_data(data)
        echo("Echo window set to main.")
        goto continue_main
    elseif string.find(stripped, "^toggle%s+fam") or stripped == "familiar" or stripped == "fam" then
        use_familiar_window = true
        prefs.echo_window = "familiar"
        data.prefs = prefs
        save_data(data)
        echo_to_familiar("Echo window set to familiar.")
        goto continue_main
    elseif string.find(stripped, "^toggle%s+combo") then
        prefs.show_combo_output = not prefs.show_combo_output
        data.prefs = prefs
        save_data(data)
        if prefs.show_combo_output then
            echo_flare("Combo output has been enabled.")
        else
            echo_flare("Combo output has been disabled.")
        end
        goto continue_main
    elseif string.find(stripped, "^toggle%s+flare") then
        prefs.show_flare_output = not prefs.show_flare_output
        data.prefs = prefs
        save_data(data)
        if prefs.show_flare_output then
            echo_flare("Individual flare output has been enabled.")
        else
            echo_flare("Individual flare output has been disabled.")
        end
        goto continue_main
    elseif stripped == "reset" or stripped == "reset data" then
        damage_data = {}
        high_scores = {}
        total_attacks = 0
        highest_combo = { flare_count = 0, label = "NONE" }
        data.damage_data = damage_data
        data.high_scores = high_scores
        data.total_attacks = total_attacks
        data.highest_combo = highest_combo
        save_data(data)
        echo("Combined data has been reset.")
        goto continue_main
    elseif stripped == "show" or stripped == "stats all" then
        display_statistics(damage_data, high_scores, total_attacks, true)
        goto continue_main
    elseif string.find(stripped, "^stats%s+.+") then
        local partial = string.match(stripped, "^stats%s+(.+)$")
        if partial then
            local closest = find_closest_flare_type(partial, damage_data)
            if closest then
                display_statistics(
                    { [closest] = damage_data[closest] },
                    { [closest] = high_scores[closest] },
                    total_attacks,
                    false
                )
            else
                echo("No matching flare type found for '" .. partial .. "'.")
            end
        end
        goto continue_main
    end

    ---------------------------------------------------------------------------
    -- Track attacks
    ---------------------------------------------------------------------------
    if match_attack(line) then
        total_attacks = total_attacks + 1
        event_counter = event_counter + 1
    end

    ---------------------------------------------------------------------------
    -- Match flare patterns (non-damaging first, then damaging)
    ---------------------------------------------------------------------------
    local matched_nodmg = match_any(line, NODMG_PATTERNS)
    local matched_dmg = match_any(line, DMG_PATTERNS)
    local flare_type = matched_nodmg or matched_dmg

    if flare_type then
        local is_ignored = is_combo_ignored(flare_type)
        local now = os.clock()

        table.insert(flare_events, {
            type = flare_type,
            time = now,
            ignored = is_ignored,
            damage = 0,
            avg_damage = 0,
            high_score = 0,
        })

        -- Initialize damage_data for this flare type
        if not damage_data[flare_type] then
            damage_data[flare_type] = {}
        end

        local flare_hits = #damage_data[flare_type]
        local flares_per_attack = calculate_flares_per_attack(flare_hits, total_attacks)

        -----------------------------------------------------------------------
        -- Non-damaging flare: record nil (count only) and display
        -----------------------------------------------------------------------
        if matched_nodmg then
            table.insert(damage_data[flare_type], 0)
            if prefs.show_flare_output then
                local total_flare_hits = count_all_flare_hits(damage_data)
                local rate = calculate_appearance_rate(#damage_data[flare_type], total_flare_hits)
                display_flare_data(flare_type, 0, 0, 0, rate, flares_per_attack)
            end

        -----------------------------------------------------------------------
        -- SanguineSacrifice immediate damage on same line
        -----------------------------------------------------------------------
        elseif flare_type == "SanguineSacrifice" then
            local imm_dmg = string.match(line, "suffers an additional (%d+) damage!")
            if imm_dmg then
                imm_dmg = tonumber(imm_dmg)
                table.insert(damage_data[flare_type], imm_dmg)

                if #damage_data[flare_type] > 0 then
                    local avg = calculate_average(damage_data[flare_type])
                    local std = calculate_std_deviation(damage_data[flare_type])
                    local threshold = avg + 4 * std
                    if imm_dmg <= threshold or #damage_data[flare_type] <= 1 then
                        high_scores[flare_type] = math.max(imm_dmg, high_scores[flare_type] or 0)
                    end
                end

                if prefs.show_flare_output then
                    local total_flare_hits = count_all_flare_hits(damage_data)
                    local rate = calculate_appearance_rate(#damage_data[flare_type], total_flare_hits)
                    local fpa = calculate_flares_per_attack(#damage_data[flare_type], total_attacks)
                    local avg = calculate_average(damage_data[flare_type])
                    display_flare_data(flare_type, imm_dmg, high_scores[flare_type] or 0, avg, rate, fpa)
                end

                -- Update event
                if #flare_events > 0 then
                    flare_events[#flare_events].damage = imm_dmg
                    flare_events[#flare_events].avg_damage = calculate_average(damage_data[flare_type])
                    flare_events[#flare_events].high_score = high_scores[flare_type] or 0
                end
            end

        -----------------------------------------------------------------------
        -- Damaging flare: read ahead for damage lines
        -----------------------------------------------------------------------
        elseif matched_dmg then
            local damage_lines = {}
            local same_line_dmg = extract_damage(line)
            if same_line_dmg then
                table.insert(damage_lines, same_line_dmg)
            end

            local max_lookahead = is_two_line_damage(flare_type) and 5 or 3
            local max_captures = is_two_line_damage(flare_type) and 2 or 1
            local captures = 0

            for _ = 1, max_lookahead do
                if captures >= max_captures and #damage_lines > 0 then break end
                local next_line = get()
                if not next_line then break end

                -- If next line is a new flare pattern, re-queue it
                if is_new_flare_pattern(next_line) or match_attack(next_line) then
                    pending_line = next_line
                    break
                end

                local dmg = extract_damage(next_line)
                if dmg then
                    table.insert(damage_lines, dmg)
                    captures = captures + 1
                    if captures >= max_captures then break end
                elseif is_break_line(next_line) then
                    -- Check for Roundtime to process combos
                    if string.find(next_line, "Roundtime") then
                        pending_line = next_line
                    end
                    break
                end
            end

            -- Record damage
            if #damage_lines > 0 then
                local total_damage = 0
                for _, d in ipairs(damage_lines) do
                    total_damage = total_damage + d
                end

                table.insert(damage_data[flare_type], total_damage)

                -- Update high score with outlier guard
                local avg = calculate_average(damage_data[flare_type])
                local std = calculate_std_deviation(damage_data[flare_type])
                local threshold = avg + 4 * std
                if total_damage <= threshold or #damage_data[flare_type] <= 1 then
                    high_scores[flare_type] = math.max(total_damage, high_scores[flare_type] or 0)
                end

                -- Update event record
                if #flare_events > 0 then
                    flare_events[#flare_events].damage = total_damage
                    flare_events[#flare_events].avg_damage = avg
                    flare_events[#flare_events].high_score = high_scores[flare_type] or 0
                end

                -- Display
                if prefs.show_flare_output then
                    local total_flare_hits = count_all_flare_hits(damage_data)
                    local rate = calculate_appearance_rate(#damage_data[flare_type], total_flare_hits)
                    local fpa = calculate_flares_per_attack(#damage_data[flare_type], total_attacks)
                    display_flare_data(flare_type, total_damage, high_scores[flare_type] or 0, avg, rate, fpa)
                end
            else
                -- No damage captured
                table.insert(damage_data[flare_type], 0)
                if #flare_events > 0 then
                    flare_events[#flare_events].damage = 0
                end
                if prefs.show_flare_output then
                    local total_flare_hits = count_all_flare_hits(damage_data)
                    local rate = calculate_appearance_rate(#damage_data[flare_type], total_flare_hits)
                    display_flare_data(flare_type, 0, 0, 0, rate, flares_per_attack)
                end
            end
        end

        -- Increment save counter
        event_counter = event_counter + 1
        if event_counter >= save_interval then
            data.damage_data = damage_data
            data.high_scores = high_scores
            data.total_attacks = total_attacks
            data.highest_combo = highest_combo
            save_data(data)
            event_counter = 0
        end
    end

    ---------------------------------------------------------------------------
    -- Combo detection on Roundtime
    ---------------------------------------------------------------------------
    if string.find(line, "Roundtime") then
        local current_time = os.clock()

        -- Filter recent non-ignored flare events within the time window
        local recent_flares = {}
        for _, event in ipairs(flare_events) do
            if (current_time - event.time) <= COMBO_TIME_WINDOW and not event.ignored then
                table.insert(recent_flares, event)
            end
        end

        local flare_count = #recent_flares

        if prefs.show_combo_output and flare_count > 2 then
            -- Check for new highest combo
            local label = COMBO_LABELS[flare_count] or COMBO_LABELS[20] or "ULTRA"
            local prev_highest = highest_combo.flare_count or 0

            if flare_count > prev_highest then
                highest_combo = { flare_count = flare_count, label = label }
                data.highest_combo = highest_combo
                save_data(data)
                echo_flare("New highest combo: " .. flare_count .. " FLARE " .. label .. " COMBO!")
            end

            -- Build combo display
            local combo_lines = {}
            table.insert(combo_lines, string.rep("=", 33) .. "!!! " .. flare_count .. " FLARE " .. label .. " COMBO !!! " .. string.rep("=", 33))

            for idx, event in ipairs(recent_flares) do
                local ft = event.type
                local td = event.damage or 0
                local ad = event.avg_damage or 0
                local hs = event.high_score or 0
                local total_flare_hits = count_all_flare_hits(damage_data)
                local rate = 0
                if damage_data[ft] then
                    rate = calculate_appearance_rate(#damage_data[ft], total_flare_hits)
                end
                local fpa = "N/A"
                if damage_data[ft] then
                    fpa = calculate_flares_per_attack(#damage_data[ft], total_attacks)
                end
                table.insert(combo_lines, format_flare_data(ft, td, hs, ad, rate, fpa, idx))
            end

            echo_flare(table.concat(combo_lines, "\n"))
        end

        -- Clear flare events after roundtime
        flare_events = {}
    end

    ::continue_main::
end
