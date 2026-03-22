--- @revenant-script
--- name: osacombat
--- version: 4.1.2
--- author: Peggyanne (Bait#4376)
--- contributors: Revenant port by elanthia-online
--- game: gs
--- description: OSA automated combat script — configurable combat routines for living and undead creatures
--- tags: osa, combat, hunting, spells, gemstones
--- @lic-certified: complete 2026-03-19
---
--- Changelog (from original Lich5 version):
---   v4.1.2 (2026-02-27) Fixed targeting issue, undead default targeting, upstream hook fix
---   v4.1.1 (2026-02-21) Upstream hooks for help/setup, converted dropdowns to strings
---   v4.1.0 (2026-02-16) Energy Wings offensive abilities
---   v4.0.0 (2026-02-13) AI-assisted YAML/GTK3 rewrite, min stamina/mana/enemy thresholds
---   ... (earlier changelog entries)

local Config   = require("gs.osacombat.config")
local Combat   = require("gs.osacombat.combat")
local Spells   = require("gs.osacombat.spells")
local Health   = require("gs.osacombat.health")
local GuiSetup = require("gs.osacombat.gui")

local VERSION = "4.1.2 (February 27, 2026)"

--------------------------------------------------------------------------------
-- Help display
--------------------------------------------------------------------------------

local function help_display()
    respond("")
    respond("                             ud$$$**$$$$$$$bc.")
    respond("                          u@**\"        4$$$$$$$Nu")
    respond("                        J                \"\"#$$$$$$r")
    respond("                       @                       $$$$b")
    respond("                     .F                        ^*3$$$")
    respond("                    :% 4                         J$$$N")
    respond("                    $  :F                       :$$$$$")
    respond("                   4F  9                       J$$$$$$$")
    respond("                   4$   k             4$$$$bed$$$$$$$$$")
    respond("                   $$r  'F            $$$$$$$$$$$$$$$$$r")
    respond("                   $$$   b.           $$$$$$$$$$$$$$$$$N")
    respond("                   $$$$$k 3eeed$$b    $$$Euec.\"$$$$$$$$$")
    respond("    .@$**N.        $$$$$\" $$$$$$F'L $$$$$$$$$$$  $$$$$$$")
    respond("    :$$L  'L       $$$$$ 4$$$$$$  * $$$$$$$$$$F  $$$$$$F         edNc")
    respond("   @$$$$N  ^k      $$$$$  3$$$$*%   $F4$$$$$$$   $$$$$\"        d\"  z$N")
    respond("   $$$$$$   ^k     '$$$\"   #$$$F   .$  $$$$$c.u@$$$          J\"  @$$$$r")
    respond("   $$$$$$$b   *u    ^$L            $$  $$$$$$$$$$$$u@       $$  d$$$$$$")
    respond("    ^$$$$$$.    \"NL   \"N. z@*     $$$  $$$$$$$$$$$$$P      $P  d$$$$$$$")
    respond("       ^\"*$$$$b   '*L   9$E      4$$$  d$$$$$$$$$$$\"     d*   J$$$$$r")
    respond("            ^$$$$u  '$.  $$$L     \"#\" d$$$$$$\".@$$    .@$\"  z$$$$*\"")
    respond("              ^$$$$. ^$N.3$$$       4u$$$$$$$ 4$$$  u$*\" z$$$\"")
    respond("                '*$$$$$$$$ *$b      J$$$$$$$b u$$P $\"  d$$P")
    respond("                   #$$$$$$ 4$ 3*$\"$*$ $\"$'c@@$$$$ .u@$$$P")
    respond("                     \"$$$$  \"\"F~$ $uNr$$$^&J$$$$F $$$$#")
    respond("                       \"$$    \"$$$bd$.$W$$$$$$$$F $$\"")
    respond("                         ?k         ?$$$$$$$$$$$F'*")
    respond("                          9$$bL     z$$$$$$$$$$$F")
    respond("                           $$$$    $$$$$$$$$$$$$")
    respond("                            '#$$c  '$$$$$$$$$\"")
    respond("                             .@\"#$$$$$$$$$$$$b")
    respond("                           z*      $$$$$$$$$$$$N.")
    respond("                         e\"      z$$\"  #$$$k  '*$$.")
    respond("                     .u*      u@$P\"      '#$$c   \"$$c")
    respond("              u@$*\"\"\"       d$$\"            \"$$$u  ^*$$b.")
    respond("            :$F           J$P\"                ^$$$c   '\"$$$$$$bL")
    respond("           d$$  ..      @$#                      #$$b         '#$")
    respond("           9$$$$$$b   4$$                          ^$$k         '$")
    respond("            \"$$6\"\"$b u$$                             '$    d$$$$$P")
    respond("              '$F $$$$$\"                              ^b  ^$$$$b$")
    respond("               '$W$$$$\"                                'b@$$$$\"")
    respond("                                                        ^$$$*")
    respond("")
    respond("-----------------------------------------------------------------------")
    respond("            OSACombat Version: " .. VERSION)
    respond("")
    respond("   Usage:")
    respond("")
    respond("   osacombat setup                       Opens the setup window to configure combat routines.")
    respond("   osacombat help                        Opens the help window (This window).")
    respond("   osacombat ?                           Opens the help window (This window).")
    respond("")
    respond("   * Note: All commands can be initiated while the script is running.")
    respond("           (Do not use semi-colon for commands while running OSACombat)")
    respond("")
    respond("   OSACombat is an automated combat script.")
    respond("   Enjoy ")
    respond("")
    respond("   ~Peggyanne ")
    respond("")
    respond("   PS: feel free to send me any bugs via discord Bait#4376 and I'll try my best to fix them.")
    respond("")
    respond("   Change Log:")
    respond("")
    respond("            May 24, 2025 - Improved Targeting Logic, Removed Attack Types and Added Use Archery and Use UAC W/O Weapons Checkboxs")
    respond("            June 7, 2025 - Removed Anti Effect methods, Ecleanse does this much better. Also fixed logic for assaults.")
    respond("           June 19, 2025 - Resolved Lag and Redundancy Issues. Also Added Support for Paladin Feat Excoriate.")
    respond("           June 22, 2025 - Adjusted Opener Spell Logic, Added Opener Support For Cold Snap And Added A Second Opener Spell.")
    respond("           June 23, 2025 - Fixed Targeting Error In Second Spell Opener.")
    respond("           July 19, 2025 - Fixed Issue With Unstun Method That Was Causing Lag.")
    respond("           July 20, 2025 - Fixed Issue With Mob Count If Statements.")
    respond("           July 26, 2025 - Adjusted Assaults And Removed Spell Active Check.")
    respond("           July 30, 2025 - Added 611 To Openers Check.")
    respond("          August 3, 2025 - Added 1650 Armor For Emergency Use And 1650 Zeal To Support Tab.")
    respond("         August 18, 2025 - Added Second AOE And Assaults, Support For Flare Gloves Pound Feature And Added Auto Looting")
    respond("                           Depending On Weekly/Monthly Gemstone Finds (Uses Killtracker).")
    respond("")
    respond("         August 23, 2025 - Added Self Cast Versions Of Barkskin And Added Self And Group Celerity To Buffs.")
    respond("         August 31, 2025 - Added Checkbox For 330 Evoke For Both Hands And Improved Anti-Poaching Logic.")
    respond("       September 6, 2025 - Fixed Minor Error In Anti-Poaching Logic.")
    respond("      September 21, 2025 - Yet Again More Changes To Anti-Poaching and Hiding Group Member Logic.")
    respond("      September 25, 2025 - Even More Anti-Poaching Fixes.")
    respond("      September 26, 2025 - Removed Unnecessary Targeting, Changed Default Healing Room and Added Stance Dancing Toggle.")
    respond("        December 6, 2025 - Added Gemstone Support, Removed Vars Dependancy, Added Yaml Support, Added Tooltips and Added Default Values.")
    respond("        December 8, 2025 - Bug Fixes On Surge Of Strength and Warcry Targeting.")
    respond("       December 13, 2025 - Fixed Upstream Toggle and Error Message.")
    respond("       December 28, 2025 - Fixed Targeting Issue With Unearthly Chains and Evanescent Possession.")
    respond("         January 2, 2026 - Fixed Minor Error In RT Management For Some Cmans.")
    respond("        January 12, 2026 - Fixed Minor Logic Error In Buff Startup.")
    respond("        January 17, 2026 - Added Stomp and Pound Options For 909.")
    respond("        January 25, 2026 - Added Anti-Poaching Command For Toggle and Changed Name of Setup Method To Prevent Cross Script Errors.")
    respond("         February 1, 2026 - Update Yaml Read/Write Methods To Include FLOCK Operations To Prevent Data Corruption.")
    respond("        February 13, 2026 - Gave In To The Hype And Rewrote YAML config and GTK3 Using AI. Also Added Min Stamina And Mana As Well As Maximum Enemy Count")
    respond("                            Thresholds. Please Be Sure To Set These.")
    respond("")
    respond("        February 16, 2026 - Added Support For Energy Wings Offensive Abilities.")
    respond("        February 21, 2026 - Added Upstream Hooks for Help and Setup As Well As Future Command Functions And Converted All Dropdowns To Strings")
    respond("                            Instead Of Integers For Ease Of Future Additions.")
    respond("")
    respond("        February 27, 2026 - Fixed Targetting Issue, Targetting Will Default To Undead Routine If Any Undead Are Present. Upstream Hook Parsing Issue Resolved")
    respond("")
end

--------------------------------------------------------------------------------
-- Parse script arguments
--------------------------------------------------------------------------------

local args = Script.vars or {}
local arg1 = args[1]

if arg1 == "?" or arg1 == "help" then
    help_display()
    return
end

-- Load configuration early so setup/living/undead commands work
Config.load()

if arg1 == "setup" then
    GuiSetup.show_setup(Config)
    return
end

if arg1 == "version" then
    respond("")
    respond("OSACombat Version " .. VERSION)
    respond("")
    return
end

if arg1 == "living" then
    Config.set("enemy_type", "living")
    Config.save()
    respond("")
    respond("Setting Creature Type to Living")
    respond("")
end

if arg1 == "undead" then
    Config.set("enemy_type", "undead")
    Config.save()
    respond("")
    respond("Setting Creature Type to Undead")
    respond("")
end

--------------------------------------------------------------------------------
-- Initialize first-cast flags
-- On a ship, suppress first-casts (cast only on enemy deck).
-- On land, cast immediately.
--------------------------------------------------------------------------------

local on_ship = false
local room = Room.current()
if room and room.location and tostring(room.location):find("Ships") then
    on_ship = true
end

local first_cast_value = not on_ship -- true on land, false on ship

-- Group buff first-cast flags
local first_cast = {
    mana_focus                = first_cast_value,
    bravery                   = first_cast_value,
    group_celerity            = first_cast_value,
    celerity                  = first_cast_value,
    rapid_fire                = first_cast_value,
    heroism                   = first_cast_value,
    group_barkskin            = first_cast_value,
    barkskin                  = first_cast_value,
    song_of_tonis             = first_cast_value,
    beacon_of_courage         = first_cast_value,
    wall_of_force             = first_cast_value,
    faith_shield              = first_cast_value,
}

-- Society/warcry first-cast flags
local society_firstcast           = first_cast_value
local warcry_shout_first_cry      = first_cast_value
local warcry_holler_first_use     = first_cast_value

-- Shield/CMan first-use flags
local shield_steely_first_use                       = first_cast_value
local cman_surge_of_strength_cooldown_first_use     = first_cast_value
local cman_surge_of_strength_no_cooldown_first_use  = first_cast_value

-- Gemstone ability first-activate flags
local gemstone_first_activate = {
    witchhunters_ascendancy    = first_cast_value,
    unearthly_chains           = first_cast_value,
    spirit_wellspring          = first_cast_value,
    spellblades_fury           = first_cast_value,
    reckless_precision         = first_cast_value,
    mana_wellspring            = first_cast_value,
    mana_shield                = first_cast_value,
    geomancers_spite           = first_cast_value,
    force_of_will              = first_cast_value,
    evanescent_possession      = first_cast_value,
    blood_wellspring           = first_cast_value,
    blood_siphon               = first_cast_value,
    blood_boil                 = first_cast_value,
    arcanists_will             = first_cast_value,
    arcanists_blade            = first_cast_value,
    arcanists_ascendancy       = first_cast_value,
    arcane_aegis               = first_cast_value,
}

-- Export first-cast tables to Config for submodule access
Config.first_cast              = first_cast
Config.society_firstcast       = society_firstcast
Config.warcry_shout_first_cry  = warcry_shout_first_cry
Config.warcry_holler_first_use = warcry_holler_first_use
Config.shield_steely_first_use                      = shield_steely_first_use
Config.cman_surge_cooldown_first_use                = cman_surge_of_strength_cooldown_first_use
Config.cman_surge_no_cooldown_first_use             = cman_surge_of_strength_no_cooldown_first_use
Config.gemstone_first_activate = gemstone_first_activate

--------------------------------------------------------------------------------
-- Anti-poaching and tracking state
--------------------------------------------------------------------------------

-- Shared mutable state table (modules read/write Config.state.poaching etc.)
Config.state = {
    poaching       = false,
    pc_hiding_room = nil,
    pc_hiding      = false,
}
Config.group_members    = {}
Config.hidden_members   = {}
Config.room_creatures   = {}
Config.empathic_link    = {}
Config.empathic_link2   = {}

--------------------------------------------------------------------------------
-- Setup phase
--------------------------------------------------------------------------------

Health.determine_group_members(Config)
Spells.mana_share(Config)

-- Mind Over Body (1213)
if Config.get("mob") and Spell[1213].known and Spell[1213]:affordable() then
    Spell[1213]:cast()
end

-- Focus Barrier (1216)
if Config.get("focus") and Spell[1216].known and Spell[1216]:affordable() then
    Spell[1216]:cast()
end

-- Stow both hands
fput("store both")

-- Gird weapons (unless UAC no weapons)
if not Config.get("nouacweapons") then
    fput("gird")
end

-- Sanctify hands (330)
if Spell[330].known and Spell[330]:affordable() then
    pause(1)
    if Config.get("sanctrighthand") and GameObj.right_hand() and GameObj.right_hand().id then
        pause(0.2)
        fput("prep 330")
        fput("evoke #" .. tostring(GameObj.right_hand().id))
        waitcastrt()
    end
    if Config.get("sanctlefthand") and GameObj.left_hand() and GameObj.left_hand().id then
        pause(0.2)
        fput("prep 330")
        fput("evoke #" .. tostring(GameObj.left_hand().id))
        waitcastrt()
    end
end

-- Mstrike setup
Combat.mstrike_setup(Config)

-- Holy Weapon conserve (1625)
if Spell[1625].known and Stats.level >= 29 and GameObj.right_hand() and GameObj.right_hand().id then
    pause(0.5)
    fput("beseech #" .. tostring(GameObj.right_hand().id) .. " conserve")
end

-- Companion settings (630)
if Spell[630].known then
    fput("tell comp return")
    pause(0.5)
    fput("tell comp behave offensive")
end

-- Warn about empty opener spells
if not Config.get("spellopen") or Config.get("spellopen") == "" then
    echo("------==== No Opener Spell Designated ==== ------")
end
if not Config.get("undeadspellopen") or Config.get("undeadspellopen") == "" then
    echo("------==== No Undead Opener Spell Designated ==== ------")
end

-- Enable brief combat flags
if Config.get("usebriefcombat") then
    fput("flag combatbrief on")
    fput("flag combatnonumbers on")
    fput("flag combatselffull off")
end

--------------------------------------------------------------------------------
-- Upstream hook for in-game commands
--------------------------------------------------------------------------------

local hook_name = "osacombat_hook"
UpstreamHook.remove(hook_name)

UpstreamHook.add(hook_name, function(line)
    if not line then return line end
    local cmd = line:lower():match("^%s*(.-)%s*$")
    if cmd == "osacombat setup" then
        GuiSetup.show_setup(Config)
        return nil
    elseif cmd == "osacombat help" or cmd == "osacombat ?" then
        help_display()
        return nil
    end
    return line
end)

--------------------------------------------------------------------------------
-- Cleanup on exit
--------------------------------------------------------------------------------

before_dying(function()
    UpstreamHook.remove(hook_name)
    if not dead() then
        -- Wait for eloot to finish
        wait_while(function() return running("eloot") end)
        -- Infuse weapon (1625)
        if Spell[1625].known and Stats.level >= 29 and GameObj.right_hand() and GameObj.right_hand().id then
            Spells.infuse_weapon(Config)
        end
        -- Infuse shield (1604)
        if Spell[1604].known and GameObj.left_hand() and GameObj.left_hand().id then
            pause(0.2)
            Spells.infuse_shield(Config)
        end
        -- Companion defensive (630)
        if Spell[630].known then
            fput("tell comp behave defensive")
        end
        -- Stow
        fput("store both")
        -- Disable brief combat flags
        if Config.get("usebriefcombat") then
            fput("flag combatbrief off")
            fput("flag combatnonumbers off")
            fput("flag combatselffull on")
        end
    end
end)

--------------------------------------------------------------------------------
-- Initial creature type detection
--------------------------------------------------------------------------------

local cc = Config.creature_type()

--------------------------------------------------------------------------------
-- Main combat loop
--------------------------------------------------------------------------------

while true do
    Combat.stance_defensive()
    Health.health_monitor(Config, cc)
    Spells.groupeffects(Config)
    Spells.gemstone_effects(Config)
    Spells.mana_leech(Config)
    Health.looter(Config)
    Health.check_dead()

    if #GameObj.targets() > 0 and not dead() then
        cc = Config.creature_type()
        Combat.reactive(Config, cc)

        -----------------------------------------------------------------------
        -- Full combat sequence (order matches original exactly)
        -----------------------------------------------------------------------

        -- 1. Prep reset
        Combat.prep_reset()

        -- 2. Poach check -> reactive -> spell opener 1
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.spell_opener ~= "" then
            cc = Config.creature_type()
            Combat.can_cast_opener(Config, cc)
        end

        -- 3. Poach check -> reactive -> spell opener 2
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.spell_opener2 ~= "" then
            cc = Config.creature_type()
            Combat.can_cast_opener2(Config, cc)
        end

        -- 4. Poach check -> reactive -> setup attack 1
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.setup_attack ~= 0 then
            cc = Config.creature_type()
            Combat.att_openers(Config, cc)
        end

        -- 5. Poach check -> reactive -> setup attack 2
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.setup_attack2 ~= 0 then
            cc = Config.creature_type()
            Combat.att_openers2(Config, cc)
        end

        -- 6. Poach check -> reactive -> aoe 1
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.aoe_attack ~= 0 then
            cc = Config.creature_type()
            Combat.aoe_att(Config, cc)
        end

        -- 7. Poach check -> reactive -> aoe 2
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.aoe_attack2 ~= 0 then
            cc = Config.creature_type()
            Combat.aoe_att2(Config, cc)
        end

        -- 8. Poach check -> kneel check
        Health.health_monitor(Config, cc)
        waitrt()
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("use_kneel") then
            Combat.kneel_check(Config, cc)
        end

        -- 9. Poach check -> reactive -> assault 1
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.assault ~= 0 then
            cc = Config.creature_type()
            Combat.assault_att(Config, cc)
        end
        Health.health_monitor(Config, cc)
        waitrt()

        -- 10. Poach check -> reactive -> assault 2
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("use_kneel") then
            Combat.kneel_check(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.assault2 ~= 0 then
            cc = Config.creature_type()
            Combat.assault_att2(Config, cc)
        end
        Health.health_monitor(Config, cc)
        waitrt()

        -- 11. Poach check -> mstrike
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching then
            Combat.mstrike_routine(Config, cc)
        end
        Health.health_monitor(Config, cc)
        waitrt()

        -- 12. Poach check -> reactive -> special 1
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.special_attack ~= 0 then
            cc = Config.creature_type()
            Combat.special_att(Config, cc)
        end

        -- 13. Poach check -> reactive -> special 2
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.special_attack2 ~= 0 then
            cc = Config.creature_type()
            Combat.secondspecial_att(Config, cc)
        end
        Health.health_monitor(Config, cc)
        waitrt()

        -- 14. Poach check -> kneel check (second)
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("use_kneel") then
            Combat.kneel_check(Config, cc)
        end

        -- 15. Poach check -> hide
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("use_stealth") then
            Combat.hide_time(Config, cc)
        end

        -- 16. Poach check -> basic attack
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("noattack") then
            if Config.get("osaarcher") then
                Combat.chicken_fire(Config, cc)
            elseif Config.get("nouacweapons") then
                Combat.uac_round(Config, cc)
            else
                Combat.chicken_attack(Config, cc)
            end
        end
        Health.health_monitor(Config, cc)
        waitrt()

        -- 17. Prep reset (second)
        Combat.prep_reset()

        -- 18. Poach check -> reactive -> attack spells 1-5
        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.attack_spell ~= "" then
            cc = Config.creature_type()
            Combat.can_cast(Config, cc)
        end
        Health.health_monitor(Config, cc)

        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.attack_spell2 ~= "" then
            cc = Config.creature_type()
            Combat.can_cast2(Config, cc)
        end
        Health.health_monitor(Config, cc)

        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.attack_spell3 ~= "" then
            cc = Config.creature_type()
            Combat.can_cast3(Config, cc)
        end
        Health.health_monitor(Config, cc)

        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.attack_spell4 ~= "" then
            cc = Config.creature_type()
            Combat.can_cast4(Config, cc)
        end
        Health.health_monitor(Config, cc)

        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end
        Health.check_for_poaching(Config)
        if not Config.state.poaching and cc.attack_spell5 ~= "" then
            cc = Config.creature_type()
            Combat.can_cast5(Config, cc)
        end
        Health.health_monitor(Config, cc)

        Health.check_for_poaching(Config)
        if not Config.state.poaching and Config.get("reactive") then
            Combat.reactive(Config, cc)
        end

        -- 19. Looter
        Health.looter(Config)
        Health.check_for_poaching(Config)
    end

    pause(0.1)
end
