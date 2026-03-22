--- tpick settings module
-- Manages 60+ user settings with defaults, load/save, profiles, and old format import.
-- Ported from tpick.lic lines 198-718.
local M = {}

---------------------------------------------------------------------------
-- Setting category lists (lines 198-220)
---------------------------------------------------------------------------

M.REQUIRED_SETTINGS = {
    "Vaalin", "Lockpick Container", "Broken Lockpick Container",
    "Scale Weapon Container", "Locksmith's Container", "Scale Trap Weapon",
}

M.ALL_SPINBUTTONS = {
    "Max Lock", "Max Lock Roll", "Trap Roll", "Calibrate Count",
    "Trap Check Count", "Lock Roll", "Vaalin Lock Roll", "Lock Buffer",
    "Unlock (407) Mana", "Percent Mana To Keep", "Number Of 416 Casts",
    "Max Level", "Minimum Tip Start", "Minimum Tip Interval",
    "Minimum Tip Floor", "Time To Wait", "Use 403 On Level",
    "Use 404 On Level",
}

M.ALL_MENUS = {
    "Trick", "Unlock (407)", "Rest At Percent", "Pick At Percent",
    "Lockpick Container", "Broken Lockpick Container", "Wedge Container",
    "Calipers Container", "Scale Weapon Container", "Locksmith's Container",
}

M.ALL_CHECKBOXES = {
    "Trash Boxes", "Calibrate On Startup", "Auto Bundle Vials",
    "Bracer Tier 2", "Bracer Override", "Calibrate Auto",
    "Auto Repair Bent Lockpicks", "Keep Trying", "Open Boxes",
    "Run Silently", "Use Monster Bold", "Don't Show Messages",
    "Don't Show Commands", "Light (205)", "Presence (402)",
    "Celerity (506)", "Rapid Fire (515)", "Self Control (613)",
    "Song of Luck (1006)", "Song of Tonis (1035)", "Use Lmaster Focus",
    "Disarm (408)", "Use Vaalin When Fried", "Phase (704)",
    "Only Disarm Safe", "Pick Enruned", "Lockpick Open", "Lockpick Close",
    "Broken Open", "Broken Close", "Wedge Open", "Wedge Close",
    "Calipers Open", "Calipers Close", "Weapon Open", "Weapon Close",
    "Use Calipers", "Use Loresinging", "Standard Wait",
}

M.LOCKPICK_NAMES = {
    "Detrimental", "Ineffectual", "Copper", "Steel", "Gold", "Silver",
    "Mithril", "Ora", "Glaes", "Laje", "Vultite", "Mein", "Rolaren",
    "Accurate", "Veniom", "Invar", "Alum", "Golvern", "Kelyn", "Vaalin",
}

M.BOX_INFO_LABELS = {
    "Box Name", "Box ID", "Lock Difficulty", "Trap Difficulty",
    "Current Trap", "Tip Amount", "Critter Name", "Critter Level",
    "Putty Remaining", "Cotton Remaining", "Vials Remaining",
    "Window Message",
}

M.REPAIR_NAMES = {
    "Repair Copper", "Repair Brass", "Repair Steel", "Repair Gold",
    "Repair Silver", "Repair Mithril", "Repair Ora", "Repair Laje",
    "Repair Vultite", "Repair Rolaren", "Repair Veniom", "Repair Invar",
    "Repair Alum", "Repair Golvern", "Repair Kelyn", "Repair Vaalin",
}

M.TRAP_NAMES_ALL = {
    "Scarab", "Needle", "Jaws", "Sphere", "Crystal", "Scales", "Sulphur",
    "Cloud", "Acid Vial", "Springs", "Fire Vial", "Spores", "Plate",
    "Glyph", "Rods", "Boomer", "No Trap",
}

M.ROGUE_ONLY_CHECKBOXES = {
    "Wedge Open", "Wedge Close", "Calipers Open", "Calipers Close",
    "Use Calipers", "Calibrate Auto", "Calibrate On Startup",
    "Auto Bundle Vials", "Auto Repair Bent Lockpicks", "Use Lmaster Focus",
}

M.ROGUE_ONLY_ENTRIES = {
    "Wedge Container", "Calipers Container", "Trick", ";rogues Lockpick",
    "Repair Copper", "Repair Brass", "Repair Steel", "Repair Gold",
    "Repair Silver", "Repair Mithril", "Repair Ora", "Repair Laje",
    "Repair Vultite", "Repair Rolaren", "Repair Veniom", "Repair Invar",
    "Repair Alum", "Repair Golvern", "Repair Kelyn", "Repair Vaalin",
}

M.ALL_SPELLS = {
    "Light (205)", "Presence (402)", "Unlock (407)", "Disarm (408)",
    "Celerity (506)", "Rapid Fire (515)", "Self Control (613)",
    "Song of Luck (1006)", "Song of Tonis (1035)",
}

M.SETTINGS_FOR_403 = { "Use 403 On Level", "Lock Pick Enhancement (403)" }
M.SETTINGS_FOR_404 = { "Use 404 On Level", "Disarm Enhancement (404)" }

---------------------------------------------------------------------------
-- Default values (lines 357-413)
---------------------------------------------------------------------------

local CHANGE_ME = "REQUIRED CHANGE ME"

-- Build the full defaults table
M.DEFAULTS = {
    -- Required settings (default to CHANGE_ME)
    ["Vaalin"]                       = CHANGE_ME,
    ["Lockpick Container"]           = CHANGE_ME,
    ["Broken Lockpick Container"]    = CHANGE_ME,
    ["Scale Weapon Container"]       = CHANGE_ME,
    ["Locksmith's Container"]        = CHANGE_ME,
    ["Scale Trap Weapon"]            = CHANGE_ME,

    -- Numeric (spinbutton) settings
    ["Max Lock"]                     = 10000,
    ["Max Lock Roll"]                = 0,
    ["Trap Roll"]                    = 10000,
    ["Calibrate Count"]              = 10,
    ["Trap Check Count"]             = 1,
    ["Lock Roll"]                    = 50,
    ["Vaalin Lock Roll"]             = 80,
    ["Lock Buffer"]                  = 0,
    ["Unlock (407) Mana"]            = 50,
    ["Percent Mana To Keep"]         = -1,
    ["Number Of 416 Casts"]          = 1,
    ["Max Level"]                    = 200,
    ["Minimum Tip Start"]            = 0,
    ["Minimum Tip Interval"]         = 0,
    ["Minimum Tip Floor"]            = 0,
    ["Time To Wait"]                 = 15,
    ["Use 403 On Level"]             = 200,
    ["Use 404 On Level"]             = 200,

    -- Menu settings
    ["Trick"]                        = "pick",
    ["Unlock (407)"]                 = "Never",
    ["Rest At Percent"]              = "Never",
    ["Pick At Percent"]              = "Always",

    -- 403/404 enhancement settings
    ["Lock Pick Enhancement (403)"]  = "never",
    ["Disarm Enhancement (404)"]     = "never",

    -- Checkbox settings defaulting to "Yes"
    ["Use Vaalin When Fried"]        = "Yes",
    ["Phase (704)"]                  = "Yes",
    ["Auto Bundle Vials"]            = "Yes",
    ["Only Disarm Safe"]             = "Yes",
    ["Trash Boxes"]                  = "Yes",
    ["Standard Wait"]                = "Yes",

    -- Window settings
    ["Width"]                        = 500,
    ["Height"]                       = 410,
    ["Horizontal"]                   = 0,
    ["Vertical"]                     = 0,
    ["Scarab Value"]                 = 5000,
    ["Show Window"]                  = "Yes",
    ["Track Loot"]                   = "No",
    ["Close Window/Script"]          = "Yes",
    ["Keep Window Open"]             = "No",
    ["One & Done"]                   = "Yes",
    ["Show Tooltips"]                = "Yes",
    ["Default Mode"]                 = "",
}

-- Settings that default to "" (all_empty, line 409)
local all_empty = {
    "Detrimental", "Ineffectual", "Copper", "Steel", "Gold", "Silver",
    "Mithril", "Ora", "Glaes", "Laje", "Vultite", "Mein", "Rolaren",
    "Accurate", "Veniom", "Invar", "Alum", "Golvern", "Kelyn",
    "Repair Copper", "Repair Brass", "Repair Steel", "Repair Gold",
    "Repair Silver", "Repair Mithril", "Repair Ora", "Repair Laje",
    "Repair Vultite", "Repair Rolaren", "Repair Veniom", "Repair Invar",
    "Repair Alum", "Repair Golvern", "Repair Kelyn", "Repair Vaalin",
    "Wedge Container", "Calipers Container", "Other Containers",
    "Auto Deposit Silvers", "Fossil Charm", "Gnomish Bracer",
    "Bashing Weapon", "Remove Armor", "Ready", "Can't Open Box",
    "Scarab Found", "Scarab Safe", "Rest When Fried", "Picks On Level",
    ";rogues Lockpick", "Picking Options", "Picking Mode", "Tip Amount",
}
for _, name in ipairs(all_empty) do
    M.DEFAULTS[name] = ""
end

-- Settings that default to "No" (all_no, line 410)
local all_no = {
    "Lockpick Open", "Lockpick Close", "Broken Open", "Broken Close",
    "Wedge Open", "Wedge Close", "Calipers Open", "Calipers Close",
    "Weapon Open", "Weapon Close", "Use Calipers", "Use Loresinging",
    "Pick Enruned", "Disarm (408)", "Keep Trying", "Open Boxes",
    "Run Silently", "Use Monster Bold", "Don't Show Messages",
    "Don't Show Commands", "Light (205)", "Presence (402)",
    "Celerity (506)", "Rapid Fire (515)", "Self Control (613)",
    "Song of Luck (1006)", "Song of Tonis (1035)", "Calibrate On Startup",
    "Calibrate Auto", "Auto Repair Bent Lockpicks", "Bracer Tier 2",
    "Bracer Override", "Use Lmaster Focus", "Tip Percent",
}
for _, name in ipairs(all_no) do
    M.DEFAULTS[name] = "No"
end

---------------------------------------------------------------------------
-- Tooltips (lines 231-355)
---------------------------------------------------------------------------

local container_info = "\n\nThis lists all of your currently worn containers. If you don't see your container listed be sure you are wearing it then restart the script."
local spell_info = "Check this box to keep this spell active while disarming and picking boxes.\n\nIf the spell wears off then the script will wait until you have enough mana to recast the spell before continuing."
local min_tip_info = "IMPORTANT: 'Minimum Tip Start', 'Minimum Tip Interval', and 'Minimum Tip Floor' settings are all related.\n\nExample of how these settings work: 'Minimum Tip Start' set to 1000, 'Minimum Tip Interval' set to 40, 'Minimum Tip Floor' set to 500: Script would start asking for 1000+ silver jobs, when none are available it would subtract 40 and start asking for 960+ silver jobs.\nIt would keep doing this until it reached 500 silvers, at which point it would start over again at 1000.\n\nAnother example: Set 'Minimum Tip Start' to 200, 'Minimum Tip Interval' to 0, and 'Minimum Tip Floor' to 0 to always ask for 200+ silver jobs.\n\nSet all 3 settings to 0 to not request a minimum silver job and instead work on any box offered.\n\nDefault value: 0"
local open_info = "Check this box if you want the script to open this container when the script is started."
local close_info = "Check this box if you want the script to close this container before the script exits."
local gnomish_info = "IMPORTANT: The settings 'Gnomish Bracer', 'Bracer Tier 2', and 'Bracer Override' are all related. Be sure to read the tooltips for each and fill them out correctly.\n\n"
local adjust_info = "\n\nWindow will be adjusted as you change this value but the setting won't be saved until you click the 'Save' button."
local default_info = "\n\nDefault value:"
local tip_info = "This setting is related to the 'Drop Off Boxes' option.\n\nIf 'Tip Percent' is checked then the number in 'Tip Amount' is what percent of the box value you are tipping for each box.\n\nIf 'Tip Percent' is unchecked then the number in 'Tip Amount' is how much silver you are tipping for each box."

M.TOOLTIPS = {
    ["Lockpick Tooltip"] = "VAALIN LOCKPICK SETTING IS REQUIRED. ALL OTHER LOCKPICKS ARE OPTIONAL.\n\nEnter the FULL name of your lockpicks, NOT including the words 'a' or 'an'.\nExample: silver lockpick\n\nIf you are using a KEYRING for your lockpicks enter the full name as they appear when you LOOK ON KEYRING.\n\nYou MUST fill out the Vaalin Lockpick setting. If you don't have a vaalin lockpick then enter the name of your highest quality lockpick.\n\nIf you don't have a particular lockpick then leave it blank and the script will enter your next best lockpick.\n\nDetrimental, Ineffectual, mein, and accurate lockpicks aren't very common, if you don't have any of those then leave those settings blank.\n\nYou can enter multiple lockpicks of the same kind by separating them with a comma.\nFor example if you have two copper lockpicks you can enter the following in the Copper Lockpick setting: dark red copper lockpick,red tinted copper lockpick.\nNote no space after the comma.",
    ["Repair Tooltip"] = "If you wish to use the repair feature of this script (automatically repairs any broken lockpicks) you need to fill out each material setting with the lockpicks that are made out of that material/can be repaired with a wire from that material.\n\nExample: if you have a lockpick that is made out of steel, regardless of the modifier of that lockpick, then enter the name of that lockpick in the 'steel' setting.\n\nUse the same instructions for filling out each setting as in the 'Lockpick' tab: enter the full name not including the words 'a' or 'an', if you have the lockpicks on a keyring use the full name as they appear when you LOOK ON KEYRING, separate multiple lockpicks with a ',' no spaces.\n\nExample: blue steel lockpick,red steel lockpick",
    ["Lockpick Container"] = "Select the container where your lockpicks will be stored." .. container_info,
    ["Broken Lockpick Container"] = "Select the container where your broken lockpicks will be stored." .. container_info,
    ["Wedge Container"] = "Note: If you won't be using wedges then it doesn't matter what you select here.\n\nSelect the container where your wedges will be stored." .. container_info,
    ["Calipers Container"] = "Note: If you won't be using calipers then it doesn't matter what you select here.\n\nSelect the container where your calipers will be stored." .. container_info,
    ["Scale Weapon Container"] = "Select the container where your weapon for disarming scale traps will be stored." .. container_info,
    ["Locksmith's Container"] = "Select the container where putty and cotton balls are found." .. container_info,
    ["Other Containers"] = "If you leave this setting blank the script will STOW everything else that is not listed above.\n\nList all other item names/item types and the containers you want them to go into. Separate the names/types and containers by ':' and separate each of these by a comma.\n\nExample: gem: sack, diamond: soft brown cloak, silver wand: ebony pack\n\nNote you can use either the full name of a container or just the noun, but if you are wearing more than one of a particular container (like two sacks) be sure to use full names.\n\nNames will be matched before types. Example if you have: \"gem: pack, diamond: cloak\" then all diamonds will be put into your cloak and all other gems will be put into your pack.\n\nAny Lich item types will work, here are the more common ones: herb, gem, armor, weapon, reagent, jewelry, uncommon, scroll, clothing, collectible, cursed, wand",
    ["Auto Deposit Silvers"] = "Enter 'yes' to auto deposit silvers when encumbered and picking pool boxes or ground picking and looting.\n\nOr enter the name and commands of your preferred selling script, ;tpick will run this script when encumbered.\n\nExample: eloot sell\n\nAfter depositing silvers/running the named script ;tpick will go back to your original spot and continue picking.",
    ["Fossil Charm"] = "If you want to use a Fossil Charm to gather silver from opened boxes then enter the ADJECTIVE and NOUN of your Fossil Charm here.\nEXAMPLE: If you can do TAP MY SILVERY CHARM then you would enter 'silvery charm' here.\n\nIf you don't want to use a Fossil Charm then leave this setting blank.",
    ["Gnomish Bracer"] = gnomish_info .. "Enter name of your gnomish bracer, not including 'a' or 'an'.",
    ["Bracer Tier 2"] = gnomish_info .. "Check this box if your Gnomish Bracer is at least tier 2 and you want the script to use your Gnomish Bracer to disarm traps.",
    ["Bracer Override"] = gnomish_info .. "Check this box if you only want the script to use your Gnomish Bracer for disarming traps and will use your 'Lockpick Container' setting to find and store lockpicks.",
    ["Bashing Weapon"] = "Only use this setting if you are a warrior who has learned Bashing in the warrior guild and you want to bash open your boxes instead of picking them.\n\nEnter the name of the weapon you use for bashing boxes.\n\nExample: glaes club",
    ["Scale Trap Weapon"] = "Enter the name of the weapon you use for disarming scale traps.\n\nExample: black iron pick",
    ["Remove Armor"] = "Enter the name of your armor if you want the script to remove your armor before casting a spell. The script will automatically wear the armor again before the script exits.\n\nExample: plate armor",
    ["Max Lock"] = "Enter the highest lock you are willing to attempt, any locks higher than this will be wedged, popped, or skipped.\n\nFor example if you enter 400 in this setting then any locks with a difficulty higher than 400 will be wedged, popped, or skipped.\n\nEntering a negative number would instead only attempt locks that are at most that value lower than your max skill with a vaalin lockpick.\n\nFor example if the highest lock you can pick with a vaalin lockpick is 700 and you enter -50 into this setting, then any locks higher than 650 will be wedged, popped, or skipped." .. default_info .. " 10000",
    ["Max Lock Roll"] = "Example: If you set this to 30 then whenever you roll lower than 30 when picking a lock the script will attempt to pick again no matter what messaging you received.\n\nSet this to 0 if you want the script to always move to a higher lockpick when receiving a message that you aren't able to pick the lock.\n\nThe script will always move on to a higher lockpick if you break your current lockpick." .. default_info .. " 0",
    ["Trap Roll"] = "Determines what difficulty boxes you want to attempt.\n\nSet to 0 to never try anything higher than your total disarm skill + lore bonus.\n\nSet to 10000 to attempt to disarm all traps.\n\nExample: Setting to 10 would attempt traps 10 points higher than your disarm skill + lore bonus.\n\nExample: Setting to -10 would only attempt traps that are a maximum of 10 points lower than your disarm skill + lore bonus.\n\nScript will always use 404/Lmaster Focus (if you know either one) if it determines you need the spell to disarm a trap." .. default_info .. " 10000",
    ["Trick"] = "Select the Lock Mastery trick you want to use when picking a box.\n\nSelect 'pick' to not use a trick.\n\nSelect 'random' to use a random trick each time you pick a lock.\n\nIMPORTANT: Script does not check whether or not you know the selected trick, be sure you have enough Lock Mastery ranks to use the selected trick. Refer to the following:\n\nSpin: 1 rank of Lock Mastery required\nTwist: 10 ranks of Lock Mastery required\nTurn: 20 ranks of Lock Mastery required\nTwirl: 30 ranks of Lock Mastery required\nToss: 40 ranks of Lock Mastery required\nBend: 50 ranks of Lock Mastery required\nFlip: 60 ranks of Lock Mastery required\nRandom: 60 ranks of Lock Mastery required",
    ["Trash Boxes"] = "Check this box to have script TRASH empty boxes if possible, if the TRASH verb can't find a proper trash bin then the script will drop the box on the ground.\n\nUncheck this box to have the script STOW all empty boxes." .. default_info .. " Checked",
    ["Calibrate On Startup"] = "Check this box to have the script calibrate your calipers whenever the script is started.",
    ["Calibrate Count"] = "IMPORTANT: Be sure to read the 'Calibrate Auto' setting below as it is related to this setting.\n\nScript will calibrate your calipers every time you pick this many boxes." .. default_info .. " 10",
    ["Calibrate Auto"] = "Check this box if you want the script to automatically calibrate your calipers when it is needed.\n\nExample of how this setting works: If this box is checked and you set the 'Calibrate Count' setting above to 100, then whenever the script notices your calipers readings are 100+ off from the actual lock difficulty it will calibrate your calipers.\n\nUncheck this box to not use the auto feature and instead use the 'Calibrate Count' for the specified use it states in its tooltip.",
    ["Auto Bundle Vials"] = "Check this box if you want the script to bundle vials into your locksmith's container after receiving a vial from disarming a vial trap.\n\nUncheck this box to have script stow the vials." .. default_info .. " Checked",
    ["Auto Repair Bent Lockpicks"] = "IMPORTANT: You learn how to repair bent lockpicks at rank 25 of Lock Mastery in the Rogue Guild, the script does not check if you have 25 ranks yet. Only check this box if you have at least 25 ranks in Lock Mastery.\n\nCheck this box to have the script automatically repair lockpciks after they have been bent.",
    ["Trap Check Count"] = "Enter how many times you want the script to manually check for traps." .. default_info .. " 1",
    ["Lock Roll"] = "Maximum roll before moving to a higher lockpick.\n\nExample: If this value is 50 and you roll higher than 50 and didn't pick the lock the script will move to the next lockpick, if you roll 50 or less then the script will keep trying with the current lockpick." .. default_info .. " 50",
    ["Vaalin Lock Roll"] = "Same as 'Lock Roll' setting above, but this setting is only when using a vaalin lockpick. Since there is no lockpick higher than vaalin, if you roll higher than this setting then the script will move on to using wedges, popping, or giving up on the box.\n\nSet to 101 to always try picking a lock with a vaalin lockpick.\n\nNOTE: This number should be equal to or higher than the 'Lock Roll' setting." .. default_info .. " 80",
    ["Lock Buffer"] = "Example: Set this to 50 and the script will add +50 to lock difficulty from all caliper readings, just in case your caliper readings aren't 100% accurate.\n\nFor example if your calipers said the lock has a difficulty of 200, then setting this to 50 would treat all calculations as if the difficulty were 250." .. default_info .. " 0",
    ["Keep Trying"] = "Check this box to have the script keep trying the current lockpick if you receive messaging indicating you can pick the lock with your current lockpick. This would override your 'Lock Roll' and 'Vaalin Lock Roll' settings.\n\nUncheck this box to have the script always follow your 'Lock Roll' and 'Vaalin Lock Roll' settings." .. default_info .. " Unchecked",
    ["Open Boxes"] = "Check this box to automatically open boxes after picking/dismaring them when doing GROUND picking.\n\nUncheck this box to not open them.\n\nNOTE: If you do the GROUND + LOOT option then you will always open and loot the box." .. default_info .. " Unchecked",
    ["Run Silently"] = "Check this box to not see most calculations feedback in the game window or in the 'Messages' tab of the Information Window while script is running. Important messages will still be shown." .. default_info .. " Unchecked",
    ["Use Monster Bold"] = "Check this box to use Monster Bold color for most messages." .. default_info .. " Unchecked",
    ["Don't Show Messages"] = "Check this box to not show ANY messages from the script in the game window, this includes what the script considers important messages.\n\nUncheck this box to show messages from the script in the game window.\n\nRegardless of this setting messages will still be shown in the 'Messages' tab of the Information Window." .. default_info .. " Unchecked",
    ["Don't Show Commands"] = "Check this box to not show commands the script is sending to the game." .. default_info .. " Unchecked",
    ["Light (205)"] = spell_info,
    ["Presence (402)"] = spell_info,
    ["Celerity (506)"] = spell_info,
    ["Rapid Fire (515)"] = "Check this box to keep Rapid Fire (515) active while casting other spells such as 407, 408, and 416.",
    ["Self Control (613)"] = spell_info,
    ["Song of Luck (1006)"] = spell_info,
    ["Song of Tonis (1035)"] = "Check this box to keep Song of Tonis (1035) active while disarming and picking boxes.\n\nScript will not wait until you have enough mana to cast 1035, it will cast if you have enough mana or move on if you don't.",
    ["Use Lmaster Focus"] = "IMPORTANT: Use the settings below to determine when you want to use Lmaster Focus for when you're picking and disarming.\n\nCheck this box to use LMASTER FOCUS instead of 403/404.",
    ["Lock Pick Enhancement (403)"] = "Enter 'yes' to keep this spell active.\n\nEnter 'no' to only use this spell when needed (after a failed pick attempt or for a very high lock.)\n\nEnter 'cancel' to have this spell STOPPED when starting a new box.\n\nEnter 'never' to NEVER use this spell.\n\nEnter a number to use this spell if the lock difficulty is above this number. Example: Entering 100 would use this spell whenever the lock difficulty is higher than 100.\n\nEnter 'auto' to have the script cast this spell when needed and to STOP the spell before picking if it isn't needed.\n\nYou can combine these options by separating each command with a space or comma, for example you can enter: auto 100 cancel",
    ["Disarm Enhancement (404)"] = "Enter 'yes' to keep this spell active.\n\nEnter 'no' to only use this spell when needed (after a failed disarm attempt or for a very difficult trap.)\n\nEnter 'cancel' to have this spell STOPPED when starting a new box.\n\nEnter 'never' to NEVER use this spell.\n\nEnter a number to use this spell if the trap difficulty is above this number. Example: Entering 100 would use this spell whenever the trap difficulty is higher than 100.\n\nEnter 'auto' to have the script cast this spell when needed and to STOP the spell before disarming if it isn't needed.\n\nEnter 'detect' to use this spell when detecting traps but will STOP this spell if it's not needed to disarm the trap.\n\nYou can combine these options by separating each command with a space or comma, for example you can enter: auto 100 detect",
    ["Unlock (407)"] = "Select 'Plate' to have the script open plated boxes (except mithril or enruned) with 407 if you have no acid vials or wedges.\n\nSelect 'Vial' to have the script use 407 to open non-mithril and non-enruned plated boxes, and will use vials on mithril and enruned plated boxes.\n\nSelect 'All' to have the script use 407 to open all boxes (except mithril and enruned.)\n\nSelect 'Never' to have the script NEVER use 407 to open any box.",
    ["Unlock (407) Mana"] = "Example: If you enter 50 here then the script will keep using 407 to attempt to open a box until you reach 50% of your maximum mana, at that point the script will give up and move on.\n\nEnter -1 to have the script keep using 407 until it successfully opens a box. This means the script might have to stop and wait for mana if you run out." .. default_info .. " 50",
    ["Disarm (408)"] = "Check this box to use 408 to disarm scarabs WHEN THEY ARE ON THE GROUND.\n\nUncheck this box to manually 'disarm' scarabs.",
    ["Percent Mana To Keep"] = "Example: If you enter 50 then the script won't cast any spells if your current mana is 50% or less than your max mana.\n\nEnter -1 to always cast spells as long as you have enough mana." .. default_info .. " -1",
    ["Use Vaalin When Fried"] = "Check this box to skip using calipers and loresinging and always use a vaalin lockpick to pick locks while your mind is fried." .. default_info .. " Checked",
    ["Rest At Percent"] = "The script will pause and wait for your mind to clear out when it reaches this mind state or higher.\n\nSelect 'Never' to never pause the script based on mind state.\n\nThis setting is ignored when you are doing 'Other' picking (when people hand you a box.)" .. default_info .. " Never",
    ["Pick At Percent"] = "The script will start picking when your mind reaches this state or lower.\n\nSelect 'Always' to always pick boxes no matter what your mind state is.\n\nThis setting is ignored when you are doing 'Other' picking (when people hand you a box.)" .. default_info .. " Always",
    ["Ready"] = "Enter what to say when you are ready to be handed boxes from another person.\n\nExample: Ready." .. default_info .. " BLANK",
    ["Can't Open Box"] = "Enter what to say when you can't open a box for another person.\n\nExample: Sorry, I can't open this box." .. default_info .. " BLANK",
    ["Scarab Found"] = "Enter what to say before you disarm a scarab trap.\n\nExample: Scarab coming down." .. default_info .. " BLANK",
    ["Scarab Safe"] = "Enter what to say after you have disarmed a scarab.\n\nExample: Scarab safe." .. default_info .. " BLANK",
    ["Phase (704)"] = "Check this box to use Phase (704) on each box to check for glyph traps." .. default_info .. " Checked",
    ["Number Of 416 Casts"] = "Enter the number of times you want to check a box for traps using Piercing Gaze (416)." .. default_info .. " 1",
    ["Only Disarm Safe"] = "Some traps have a chance of being set off when using 408.\nCheck this box to skip boxes with traps that are not 100% safe, uncheck this box to attempt disarming those traps with 408.\n\nSome traps are completely safe to use 407 on (the trap won't be triggered), and some traps are completely safe to use 408 on (the spell won't set off the trap on a failure), the script always uses 407/408 on these boxes regardless of this setting.\n\nSome traps are NEVER safe to use 408 on, the script will ALWAYS skip these boxes regardless of this setting." .. default_info .. " Checked",
    ["Pick Enruned"] = "Check this box to manually pick all enruned and mithril boxes. This of course requires lockpicks and the picking skill and requires filling out the lockpicks section of the settings and other required settings.",
    ["Max Level"] = "Enter maximum critter level of boxes you will work on, higher level boxes will be turned in." .. default_info .. " 200",
    ["Minimum Tip Start"] = min_tip_info,
    ["Minimum Tip Interval"] = min_tip_info,
    ["Minimum Tip Floor"] = min_tip_info,
    ["Time To Wait"] = "IMPORTANT: 'Time To Wait' and 'Standard Wait' settings are related. Be sure to read the tooltips for both.\n\nEnter how many seconds you want to wait before asking the pool worker for another job when the pool worker tells you they can't assign you a new job at the moment." .. default_info .. " 15",
    ["Standard Wait"] = "IMPORTANT: 'Time To Wait' and 'Standard Wait' settings are related. Be sure to read the tooltips for both.\n\nCheck this box to use the standard wait times. These wait times vary based on the message received from the pool worker. These can range from 10 seconds to 5 minutes depending on the message.\n\nUncheck this box to instead always wait the number of seconds specified in the 'Time To Wait' setting above, regardless of message received.\n\nNo matter which setting you choose, the script will still respect your 'Rest When Fried' setting below." .. default_info .. " Checked",
    ["Use 403 On Level"] = "Example: Enter 80 to always use 403 on boxes which come from critters level 80+." .. default_info .. " 200",
    ["Use 404 On Level"] = "Example: Enter 80 to always use 404 on boxes which come from critters level 80+." .. default_info .. " 200",
    ["Rest When Fried"] = "Leave this setting blank if you don't want to do anything when fried and instead will wait in the locksmith's pool room until the worker assigns you more boxes.\n\nExample: Enter '112' if you want the script to move you to Lich room number 112 when you're fried.\n\nExample: Enter '112:go table' if you want the script to move you to Lich room number 112 then after arriving in Lich room number 112 the script will enter 'GO TABLE'.\n\nThe script will move you back to the pool room when your mind reaches the level you specify in the 'Pick At Percent' setting under the 'Experience' tab.\n\nNote this setting doesn't go by when you're fried, but rather when you receive messaging from the pool worker that you can't do anymore boxes until you let your mind clear out a bit.",
    ["Picks On Level"] = "Leave this blank if you don't want to use this feature.\n\nIMPORTANT: This setting works by default for all professions except for Rogues and Bards.\n\nIf you are a Rogue and you want to use this setting be sure the setting 'Use Calipers' is NOT checked.\n\nIf you are a Bard and you want to use this setting be sure the setting 'Use Loresinging' is NOT checked.\n\nThis setting will also work for any profession if you are using the 'v' command line variable.\n\nExample of how to use this setting: 10 copper, 20 steel, 30 gold, 50 lage, 75 invar, 90 kelyn\n\nThis would use your copper lockpick for critters between levels 1-10, steel lockpick for critters between levels 11-20, gold lockpick for critters between levels 21-30, etc.\n\nVaalin is used for any levels not specified, in the above example that would be for critters 91+.\n\nDO NOT use the names of your lockpicks, use the lockpick type. Refer to the below list as a reference:\n\ncopper, steel, gold, silver, mithril, ora, glaes, laje, vultite, rolaren, veniom, invar, alum, golvern, kelyn, vaalin",
    [";rogues Lockpick"] = "WARNING: Using this setting will probably break your lockpicks more often but you will likely get reps faster.\n\nLeave this setting blank to ignore this feature and use other settings to determine which pick to use.\n\nEnter the QUALITY of the lockpick to use when doing ;rogues tasks.\n\nFor example enter 'steel' to use whatever you have listed in your steel lockpick setting.\n\nIf the script notices you can't get a rep using whatever you have set then it will change this setting to go up 1 level of quality.\n\nIt's a good idea to have one lockpick of each kind to ensure you can easily get reps with these tasks.",
    ["Profiles"] = "Select the profile you wish to load then click the 'Load' button. This will fill out all settings with the selected character's settings.\n\nNOTE: Clicking 'Save' will save the current settings to the current character's profile, regardless of which character is selected in this menu.\n\nThe current character's settings won't be saved until you click the 'Save' button.",
    ["Save"] = "Click this button to save the current settings to the current character's profile.\n\nNOTE: Some changes won't take effect until the ;tpick script is restarted.",
    ["Load"] = "Select the profile you wish to load in the menu to the left then click this button. This will fill out all settings with the selected character's settings.\n\nNOTE: Clicking 'Save' will save the current settings to the current character's profile, regardless of which character is selected in this menu.\n\nThe current character's settings won't be saved until you click the 'Save' button.",
    ["Defaults"] = "Click this button to set all settings to the default values.\n\nThe current character's settings won't be saved until you click the 'Save' button.",
    ["Reset Stats"] = "Type in the word 'reset' and then click the 'Reset Stats' button to reset ALL of the current character's stats.\n\nIMPORTANT: The script will close once you click the 'Reset Stats' button and you will need to restart it.",
    ["Use Calipers"] = "IMPORTANT: Script does not check if you are trained to use calipers from the Rogue Guild. Only check this box if you can use calipers.\n\nCheck this box to use calipers to get the lock difficulty and have the script automatically choose the best lockpick based on lock difficulty.\n\nUncheck this box to not use calipers and instead always use a vaalin lockpick on every lock.",
    ["Use Loresinging"] = "Check this box to use loresinging to get the lock difficulty and have the script automatically choose the best lockpick based on lock difficulty.\n\nUncheck this box to not use loresinging and instead always use a vaalin lockpick on every lock.",
    ["Lockpick Open"] = open_info,
    ["Lockpick Close"] = close_info,
    ["Broken Open"] = open_info,
    ["Broken Close"] = close_info,
    ["Wedge Open"] = open_info,
    ["Wedge Close"] = close_info,
    ["Calipers Open"] = open_info,
    ["Calipers Close"] = close_info,
    ["Weapon Open"] = open_info,
    ["Weapon Close"] = close_info,
    ["Scan"] = "IMPORTANT: You must have at least 24 ranks in Lock Mastery to use this feature. Also make sure your 'Lockpick Container' setting has been filled out and that you have clicked 'Save' after filling it out, then restart the script. Also be sure all of your lockpicks are currently in your 'Lockpick Container.'\n\nALSO IMPORTANT: It might take a minute or two to finish the scan (depends on how many items you have in your Lockpick Container), DO NOT interact with this setting window and do not enter any commands into the game until the process is complete.\n\nClick this button to have the script scan your lockpicks and automatically assign them to the setting where they belong based on their modifier.\n\nNOTE: You still need to click the 'Save' button after the lockpicks have been assigned if you wish to save the settings.\n\nALSO NOTE: You should probably use this feature in a private room as it will be a bit spammy.",
    ["Copy"] = "Click this button to copy over all of the settings of your lockpicks from the 'Lockpicks' tab.",
    ["Width"] = "Set the width you want for the information window." .. adjust_info,
    ["Height"] = "Set the height you want for the information window." .. adjust_info,
    ["Horizontal"] = "Set the horizontal position you want for the Information window." .. adjust_info,
    ["Vertical"] = "Set the vertical position you want for the Information window." .. adjust_info,
    ["Scarab Value"] = "Enter how many silvers the script should value scarabs.\n\nNote: This is for informational purposes only, the script will multiply how many scarabs you have received by this value to display how many silvers you have earned from finding scarabs." .. default_info .. " 5000",
    ["Show Window"] = "Check this box to have the Information Window shown when ;tpick is started.\n\nUncheck this box to not show the Information Window when ;tpick is started.\n\nYou can always have the Information Window shown when starting script if you start script with 'show' as one of the command line variables.\n\nExample: ;tpick show\n\nExample ;tpick solo show" .. default_info .. " Checked",
    ["Track Loot"] = "Note: This setting pertains to Total Loot (loot gained across all sessions of ;tpick.) Session Loot (loot gained during the most recent session of using ;tpick) is always tracked.\n\nStats for tracking Total Loot is saved to the 'Tpick Stats' file on your computer and can potentially get large over time, especially if you use this script on multiple characters.\n\nCheck this box to save Total Loot stats.\n\nUncheck this box to not save Total Loot stats.\n\nIMPORTANT: Unchecking this box then clicking the 'Save' button will delete your Total Loot stats so if you want to save this information be sure to copy it before you change this setting." .. default_info .. " Unchecked",
    ["Close Window/Script"] = "Check this box to have ;tpick stopped whenever the Information Window is closed.\n\nUncheck this box to not have ;tpick stopped when the Information Window is closed.\n\nOnce the Information Window is closed the only way to see it again is to restart ;tpick." .. default_info .. " Checked",
    ["Keep Window Open"] = "Check this box to keep the Information Window open if the ;tpick script stops.\n\nUncheck this box to have the Information Window close when the ;tpick script stops." .. default_info .. " Unchecked",
    ["One & Done"] = "Check this box to close the Information Window after the command line mode has finished.\n\nFor example with this box checked: if you started script as ;tpick ground, then as soon as the script has finished picking all of the boxes on the ground the Information Window would close.\n" .. default_info .. " Checked.",
    ["Lockpicking"] = "All stats related to picking boxes.",
    ["Loot Total"] = "This page shows all loot you have received while using this script. This includes loot you have taken out of boxes while using ground loot, while using solo, and while picking up boxes you have dropped off at the locksmith's pool.\n\nIt also tracks how many scarabs you have disarmed and picked up while using this script.",
    ["Loot Session"] = "This page shows all stats pertaining to the current session.\n\nThis includes how long the script has been running during the current session, how many silvers you have taken out of boxes, how many silvers you have received as tips from picking boxes at the locksmith's pool, as well as any other loot you have taken out of boxes during the current session.",
    ["Traps"] = "This page shows how many times you have encountered each type of trap.",
    ["Lockpicks"] = "This page shows how many locks you have picked with each type of lockpick since the last time you broke a lockpick of that type.\n\nIt also shows how many locks you have picked with any lockpick since the last time you broke any type of lockpick.",
    ["Locksmith's Pool"] = "This page shows all stats pertaining to picking boxes at the locksmith's pool, including total boxes picked, time spent actually disarming/picking boxes, time spent waiting for the worker to assign you more boxes, number of scarabs found, the value of scarabs found, and tips received.",
    ["Non-Locksmith's Pool"] = "This page shows all stats pertaining to picking boxes while not using the locksmith's pool.\n\nIt includes the time spent picking boxes and number of boxes picked.",
    ["Total"] = "This page shows all stats of Locksmith's Pool and Non-Locksmith's Pool combined.",
    ["Messages"] = "The 100 most recent messages received from the script will be displayed here.\n\nNOTE: The top message is the most recent message received and the bottom message is the oldest message.",
    ["Stats"] = "View all of your stats.",
    ["Settings"] = "Change settings related to the Information Window.",
    ["Version History"] = "List of all changes in previous versions of ;tpick.",
    ["Main"] = "This page shows what the script is currently doing and the stats of the current box being worked on.",
    ["Default Mode"] = "Leave this setting blank if you don't want to use this feature.\n\nEnter the commands you want to start the script with if you just start the script as ;tpick\n\nFor example: If you enter 'pool v' then whenever you start the script as just ;tpick the script will automatically start with the commands 'pool' which means to pick boxes at the Locksmith's Pool, and 'v' which means to always use a Vaalin lockpick.\n\nYou can enter whichever commands you want.\n\nNOTE: Even if you have commands in this setting, you can still start script with command lines to use those command lines, so starting script as ;tpick pool would pick boxes at the Locksmith's pool, regardless of what commands you have listed here.\n\nAlso starting script as ;tpick show won't use any commands and will startup the Information Window and wait for a command.\n\nCommands:\nplin: Open plinites instead of boxes.\nbash: Use Warrior Bashing instead of lockpicks.\ndisarm: Only disarm boxes and don't pick the locks.\nrelock: Relock boxes after opening them.\nc: Start with a copper lockpick and move up if the lockpick can't pick the lock\nv: Always use a Vaalin lockpick to pick locks.\nwedge: Always use a wedge to open boxes.\nloot: Loot boxes after opening them when doing ground picking.\npop: Use 416, 407, and 408 to open boxes.\nground: Pick boxes on the ground.\nother: Wait for someone to GIVE you a box, disarm/pick the box, hand it back.\npool: Pick boxes at the Locksmith's pool\nsolo: Pick all boxes in your open containers and disk.\npickup: Pickup any boxes you have waiting that you dropped off to be picked at the Locksmith's pool. Script will loot all boxes.\ndrop: Used to drop off boxes at the Locksmith's pool.\nExample how to use drop for a flat tip: drop 200\nExample how to use drop for a percent of the box's value: drop 15%",
    ["Tip Amount"] = tip_info,
    ["Tip Percent"] = tip_info,
    ["Picking Mode"] = "Pool Picking: Pick boxes at a Locksmith's Pool.\nGround Picking: Pick all boxes on the ground but do not loot any boxes.\nGround Picking + Loot: Pick and loot all boxes on the ground.\nSolo Picking: Pick all boxes in your open containers and disk.\nOther Picking: Wait for someone to hand you a box, pick box, hand it back.\nRefill Locksmith's Container: Refill all of the putty and cotton balls in your Locksmith's Container to 100\nRepair Lockpicks: Repair all of your broken lockpicks\nDrop Off Boxes: Drop off all boxes in your open containers and disk at the Locksmith's pool\nPick Up Boxes: Pick up and loot all boxes that are ready at the Locksmith's pool.",
    ["Picking Options"] = "None: Don't use any options.\nAlways Use Vaalin: Always use a Vaalin lockpick to pick any lock.\nStart With Copper: Start with a Copper lockpick and use better lockpicks as needed\nRelock Boxes: Relock boxes after picking them\nAlways Use Wedge: Always use a wedge to open boxes\nPop Boxes: Use 416, 407, and 408 to open boxes\nPlinites: Open plinites instead of boxes\nDisarm Only: Only disarm boxes, won't open the locks\nBash Only: Don't disarm boxes, will use Warrior Bash to open boxes\nBash + Disarm: Will disarm boxes then use Warrior Bash to open them",
    ["Start"] = "Choose the Picking Mode and Picking Options above then click this button to start up the selected mode.",
    ["Stop"] = "Once this button is clicked the script will finish the box it is currently working on and then stop.",
    ["Show Tooltips"] = "Check this box to not show any tooltips in both this Information Window and also the Setup Window.\n\nUncheck this box to show all tooltips.",
}

---------------------------------------------------------------------------
-- Helper: deep copy a table
---------------------------------------------------------------------------

local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deep_copy(v)
    end
    return copy
end

--- Check if a string has non-space content (equivalent to Ruby count("^ ") > 0)
local function has_content(s)
    return type(s) == "string" and s:find("%S") ~= nil
end

--- Extract spell number from a setting name like "Light (205)"
local function extract_spell_num(name)
    local num = name:match("%((%d+)%)")
    return num and tonumber(num)
end

---------------------------------------------------------------------------
-- M.load() — Load settings from CharSettings JSON (lines 419-440, 569-575)
---------------------------------------------------------------------------

function M.load()
    local data = {}
    local raw = CharSettings.tpick_settings
    if raw and raw ~= "" then
        local ok, decoded = pcall(Json.decode, raw)
        if ok and type(decoded) == "table" then
            data = decoded
        end
    end

    -- Merge with defaults: fill in any missing keys, coerce types
    local result = {}
    for setting_name, default_val in pairs(M.DEFAULTS) do
        local loaded = data[setting_name]
        if loaded ~= nil then
            if type(default_val) == "number" then
                result[setting_name] = tonumber(loaded) or default_val
            else
                result[setting_name] = loaded
            end
        else
            if type(default_val) == "number" then
                result[setting_name] = default_val
            else
                result[setting_name] = default_val
            end
        end
    end

    -- Preserve any extra keys that aren't in DEFAULTS (forward compat)
    for k, v in pairs(data) do
        if result[k] == nil then
            result[k] = v
        end
    end

    return result
end

---------------------------------------------------------------------------
-- M.save(data) — Save settings to CharSettings JSON (lines 463-525)
---------------------------------------------------------------------------

function M.save(data)
    -- Strip leading "a " / "an " from lockpick/repair names and certain entries
    local strip_prefix_keys = {}
    for _, name in ipairs(M.LOCKPICK_NAMES) do strip_prefix_keys[name] = true end
    for _, name in ipairs(M.REPAIR_NAMES) do strip_prefix_keys[name] = true end
    strip_prefix_keys["Remove Armor"] = true
    strip_prefix_keys["Gnomish Bracer"] = true

    for key in pairs(strip_prefix_keys) do
        if type(data[key]) == "string" then
            data[key] = data[key]:gsub("^a ", ""):gsub("^an ", "")
        end
    end

    CharSettings.tpick_settings = Json.encode(data)
end

---------------------------------------------------------------------------
-- M.load_stats() — Load stats from JSON file (lines 442-459)
---------------------------------------------------------------------------

function M.load_stats()
    local char_name = GameState.name
    if not char_name or char_name == "" then return {} end

    if not File.exists("data/gs/tpick_stats.json") then return {} end

    local raw = File.read("data/gs/tpick_stats.json")
    if not raw or raw == "" then return {} end

    local ok, all_stats = pcall(Json.decode, raw)
    if not ok or type(all_stats) ~= "table" then return {} end

    return all_stats[char_name] or {}
end

---------------------------------------------------------------------------
-- M.save_stats(stats) — Save stats to JSON file (lines 577-591)
---------------------------------------------------------------------------

function M.save_stats(stats)
    local char_name = GameState.name
    if not char_name or char_name == "" then return end

    local all_stats = {}
    if File.exists("data/gs/tpick_stats.json") then
        local raw = File.read("data/gs/tpick_stats.json")
        if raw and raw ~= "" then
            local ok, decoded = pcall(Json.decode, raw)
            if ok and type(decoded) == "table" then
                all_stats = decoded
            end
        end
    end

    all_stats[char_name] = stats
    File.write("data/gs/tpick_stats.json", Json.encode(all_stats))
end

---------------------------------------------------------------------------
-- M.load_profile(name, all_data) — Load another character's settings
-- (lines 677-698)
---------------------------------------------------------------------------

function M.load_profile(name, all_data)
    if not all_data or not all_data[name] then return nil end

    local profile = all_data[name]
    local result = {}

    -- Apply profile values on top of defaults
    for setting_name, default_val in pairs(M.DEFAULTS) do
        local val = profile[setting_name]
        if val ~= nil then
            if type(default_val) == "number" then
                result[setting_name] = tonumber(val) or default_val
            else
                result[setting_name] = val
            end
        else
            result[setting_name] = type(default_val) == "number" and default_val or ""
        end
    end

    return result
end

---------------------------------------------------------------------------
-- M.load_defaults() — Return a fresh copy of DEFAULTS (lines 700-718)
---------------------------------------------------------------------------

function M.load_defaults()
    return deep_copy(M.DEFAULTS)
end

---------------------------------------------------------------------------
-- M.load_all_profiles() — Load all character profiles from file
---------------------------------------------------------------------------

function M.load_all_profiles()
    if not File.exists("data/gs/tpick_profiles.json") then return {} end

    local raw = File.read("data/gs/tpick_profiles.json")
    if not raw or raw == "" then return {} end

    local ok, decoded = pcall(Json.decode, raw)
    if not ok or type(decoded) ~= "table" then return {} end

    return decoded
end

---------------------------------------------------------------------------
-- M.save_all_profiles(all_profiles) — Save all character profiles to file
---------------------------------------------------------------------------

function M.save_all_profiles(all_profiles)
    File.write("data/gs/tpick_profiles.json", Json.encode(all_profiles))
end

---------------------------------------------------------------------------
-- M.check_profession_reset(data) — Check if profession changed and reset
-- profession-specific settings (lines 527-567)
-- Returns: data, reset_type (nil if no reset)
---------------------------------------------------------------------------

function M.check_profession_reset(data)
    local prof = Stats.prof
    local reset_profession = nil

    -- Check Rogue-only settings if current profession is NOT Rogue
    if prof ~= "Rogue" then
        for _, name in ipairs(M.ROGUE_ONLY_CHECKBOXES) do
            if data[name] and data[name] ~= M.DEFAULTS[name] then
                reset_profession = "Rogue"
                break
            end
        end
        if not reset_profession then
            for _, name in ipairs(M.ROGUE_ONLY_ENTRIES) do
                if has_content(data[name]) then
                    reset_profession = "Rogue"
                    break
                end
            end
        end
        if not reset_profession then
            if data["Lock Buffer"] and tonumber(data["Lock Buffer"]) ~= M.DEFAULTS["Lock Buffer"] then
                reset_profession = "Rogue"
            end
        end
        if not reset_profession then
            if data["Calibrate Count"] and tonumber(data["Calibrate Count"]) ~= M.DEFAULTS["Calibrate Count"] then
                reset_profession = "Rogue"
            end
        end
    end

    -- Check Warrior-only settings if current profession is NOT Warrior
    if prof ~= "Warrior" then
        if has_content(data["Bashing Weapon"]) then
            reset_profession = "Warrior"
        end
    end

    -- Check Bard-only settings if current profession is NOT Bard
    if prof ~= "Bard" then
        if data["Use Loresinging"] and data["Use Loresinging"] ~= M.DEFAULTS["Use Loresinging"] then
            reset_profession = "Bard"
        end
    end

    -- Check spell settings — any spell enabled that the character doesn't know
    for _, name in ipairs(M.ALL_SPELLS) do
        local spell_num = extract_spell_num(name)
        if spell_num and Spell[spell_num] and not Spell[spell_num].known then
            if data[name] == "Yes" then
                reset_profession = reset_profession or "Spells"
                break
            end
        end
    end

    -- Check 403/404 settings for non-Rogues
    if prof ~= "Rogue" then
        if Spell[403] and not Spell[403].known then
            for _, name in ipairs(M.SETTINGS_FOR_403) do
                if data[name] and data[name] ~= M.DEFAULTS[name] then
                    reset_profession = reset_profession or "Spells"
                end
            end
        end
        if Spell[404] and not Spell[404].known then
            for _, name in ipairs(M.SETTINGS_FOR_404) do
                if data[name] and data[name] ~= M.DEFAULTS[name] then
                    reset_profession = reset_profession or "Spells"
                end
            end
        end
    end

    -- Apply resets if needed
    if reset_profession then
        if reset_profession == "Rogue" then
            for _, name in ipairs(M.ROGUE_ONLY_CHECKBOXES) do
                data[name] = M.DEFAULTS[name]
            end
            for _, name in ipairs(M.ROGUE_ONLY_ENTRIES) do
                data[name] = ""
            end
            data["Lock Buffer"] = M.DEFAULTS["Lock Buffer"]
            data["Calibrate Count"] = M.DEFAULTS["Calibrate Count"]
        elseif reset_profession == "Warrior" then
            data["Bashing Weapon"] = ""
        elseif reset_profession == "Bard" then
            data["Use Loresinging"] = M.DEFAULTS["Use Loresinging"]
        end

        -- Reset unknown spells regardless of reset type
        for _, name in ipairs(M.ALL_SPELLS) do
            local spell_num = extract_spell_num(name)
            if spell_num and Spell[spell_num] and not Spell[spell_num].known then
                if data[name] == "Yes" then
                    data[name] = M.DEFAULTS[name]
                end
            end
        end

        -- Reset 403/404 for non-Rogues who don't know the spells
        if prof ~= "Rogue" then
            if Spell[403] and not Spell[403].known then
                for _, name in ipairs(M.SETTINGS_FOR_403) do
                    data[name] = M.DEFAULTS[name]
                end
            end
            if Spell[404] and not Spell[404].known then
                for _, name in ipairs(M.SETTINGS_FOR_404) do
                    data[name] = M.DEFAULTS[name]
                end
            end
        end

        M.save(data)
    end

    return data, reset_profession
end

---------------------------------------------------------------------------
-- M.import_old() — Import from old UserVars format (lines 593-675)
---------------------------------------------------------------------------

function M.import_old()
    if not UserVars or not UserVars.tpick then return nil end
    local old = UserVars.tpick
    if type(old) ~= "table" then return nil end

    local data = M.load_defaults()

    -- String settings: old key name → new key name
    local string_mappings = {
        ["Lockpick Container"]           = "lockpick_container",
        ["Broken Lockpick Container"]    = "broken_lockpick_container",
        ["Wedge Container"]              = "wedge_container",
        ["Calipers Container"]           = "calipers_container",
        ["Scale Weapon Container"]       = "scale_weapon_container",
        ["Locksmith's Container"]        = "locksmiths_container",
        ["Other Containers"]             = "all_other_containers",
        ["Auto Deposit Silvers"]         = "auto_deposit_silvers",
        ["Bashing Weapon"]               = "bashing_weapon",
        ["Scale Trap Weapon"]            = "scale_trap_weapon",
        ["Remove Armor"]                 = "remove_armor",
        ["Lock Pick Enhancement (403)"]  = "always_use_403",
        ["Disarm Enhancement (404)"]     = "always_use_404",
        ["Ready"]                        = "ready",
        ["Can't Open Box"]               = "cant_open_box",
        ["Scarab Found"]                 = "scarab_found",
        ["Scarab Safe"]                  = "scarab_safe",
        ["Rest When Fried"]              = "pool_picking_rest_when_fried",
        ["Picks On Level"]               = "picks_to_use_based_on_critter_level",
        [";rogues Lockpick"]             = "lockpick_to_use_for_rogues_tasks",
        ["Detrimental"]                  = "detrimental",
        ["Ineffectual"]                  = "ineffectual",
        ["Copper"]                       = "copper",
        ["Steel"]                        = "steel",
        ["Gold"]                         = "gold",
        ["Silver"]                       = "silver",
        ["Mithril"]                      = "mithril",
        ["Ora"]                          = "ora",
        ["Glaes"]                        = "glaes",
        ["Laje"]                         = "laje",
        ["Vultite"]                      = "vultite",
        ["Mein"]                         = "mein",
        ["Rolaren"]                      = "rolaren",
        ["Accurate"]                     = "accurate",
        ["Veniom"]                       = "veniom",
        ["Invar"]                        = "invar",
        ["Alum"]                         = "alum",
        ["Golvern"]                      = "golvern",
        ["Kelyn"]                        = "kelyn",
        ["Vaalin"]                       = "vaalin",
    }
    for new_key, old_key in pairs(string_mappings) do
        if old[old_key] and has_content(old[old_key]) then
            data[new_key] = old[old_key]
        end
    end

    -- Numeric settings
    local numeric_mappings = {
        ["Max Lock"]              = "max_lock",
        ["Max Lock Roll"]         = "max_lock_roll",
        ["Trap Roll"]             = "trap_roll",
        ["Trap Check Count"]      = "number_of_times_to_check_for_traps",
        ["Lock Roll"]             = "lock_roll",
        ["Percent Mana To Keep"]  = "percent_mana_to_keep",
        ["Vaalin Lock Roll"]      = "vaalin_lock_roll",
        ["Number Of 416 Casts"]   = "number_of_416_casts",
        ["Max Level"]             = "max_critter_level",
        ["Use 403 On Level"]      = "use_403_based_on_critter_level",
        ["Use 404 On Level"]      = "use_404_based_on_critter_level",
        ["Lock Buffer"]           = "lock_buffer",
    }
    for new_key, old_key in pairs(numeric_mappings) do
        if old[old_key] and has_content(old[old_key]) then
            data[new_key] = tonumber(old[old_key]) or data[new_key]
        end
    end

    -- Boolean/Yes-No settings
    local bool_mappings = {
        ["Trash Boxes"]                  = "trash_boxes",
        ["Auto Bundle Vials"]            = "auto_bundle_vials",
        ["Auto Repair Bent Lockpicks"]   = "auto_repair_bent_lockpicks",
        ["Keep Trying"]                  = "keep_trying_if_within_abilities",
        ["Run Silently"]                 = "run_silently",
        ["Use Monster Bold"]             = "use_monster_bold",
        ["Don't Show Commands"]          = "do_not_show_commands",
        ["Use Lmaster Focus"]            = "use_lmaster_focus",
        ["Light (205)"]                  = "always_use_205",
        ["Presence (402)"]               = "always_use_402",
        ["Disarm (408)"]                 = "always_use_408",
        ["Celerity (506)"]               = "always_use_506",
        ["Rapid Fire (515)"]             = "always_use_515",
        ["Self Control (613)"]           = "always_use_613",
        ["Song of Luck (1006)"]          = "always_use_1006",
        ["Song of Tonis (1035)"]         = "always_use_1035",
        ["Use Vaalin When Fried"]        = "use_vaalin_when_fried",
        ["Phase (704)"]                  = "always_use_704",
        ["Only Disarm Safe"]             = "only_disarm_safe",
        ["Pick Enruned"]                 = "pick_enruned_and_mithril",
    }
    for new_key, old_key in pairs(bool_mappings) do
        if old[old_key] and type(old[old_key]) == "string" and old[old_key]:lower():find("yes") then
            data[new_key] = "Yes"
        end
    end

    -- Trick
    if old["trick"] and has_content(old["trick"]) then
        data["Trick"] = old["trick"]:lower()
    end

    -- Unlock (407) compound setting
    if old["always_use_407"] and has_content(old["always_use_407"]) then
        local parts = {}
        for part in old["always_use_407"]:gmatch("[^,]+") do
            parts[#parts + 1] = part
        end
        if parts[1] then
            local val = parts[1]
            if val:lower():find("no") then
                data["Unlock (407)"] = "Never"
            else
                data["Unlock (407)"] = val:sub(1, 1):upper() .. val:sub(2)
            end
        end
        if parts[2] then
            data["Unlock (407) Mana"] = tonumber(parts[2]) or data["Unlock (407) Mana"]
        end
    end

    -- Rest At Percent
    local rest_map = {
        [100] = "Must Rest (100%)",
        [90]  = "Numbed (90%)",
        [75]  = "Becoming Numbed (75%)",
        [62]  = "Muddled (62%)",
        [50]  = "Clear (50%)",
        [25]  = "Fresh And Clear (25%)",
        [0]   = "Clear As A Bell (0%)",
    }
    if old["rest_percent"] then
        local val = tonumber(old["rest_percent"]) or -1
        data["Rest At Percent"] = rest_map[val] or "Never"
    end

    -- Pick At Percent
    local pick_map = {
        [100] = "Must Rest (100%)",
        [90]  = "Numbed (90%)",
        [75]  = "Becoming Numbed (75%)",
        [62]  = "Muddled (62%)",
        [50]  = "Clear (50%)",
        [25]  = "Fresh And Clear (25%)",
        [0]   = "Clear As A Bell (0%)",
    }
    if old["pick_percent"] then
        local val = tonumber(old["pick_percent"]) or -1
        data["Pick At Percent"] = pick_map[val] or "Always"
    end

    -- Gnomish Bracer compound setting
    if old["gnomish_bracer"] and has_content(old["gnomish_bracer"]) then
        local parts = {}
        for part in old["gnomish_bracer"]:gmatch("[^,]+") do
            parts[#parts + 1] = part
        end
        if parts[1] then
            data["Gnomish Bracer"] = parts[1]
        end
        if old["gnomish_bracer"]:find("[23]") then
            data["Bracer Tier 2"] = "Yes"
        end
        if old["gnomish_bracer"]:lower():find("override") then
            data["Bracer Override"] = "Yes"
        end
    end

    -- Calibrate settings
    if old["calibrate"] then
        if type(old["calibrate"]) == "string" and old["calibrate"]:lower():find("yes") then
            data["Calibrate On Startup"] = "Yes"
        elseif type(old["calibrate"]) == "string" and old["calibrate"]:lower():find("never") then
            data["Use Calipers"] = "No"
            data["Use Loresinging"] = "No"
        end
    end

    if old["calibratecount"] then
        if type(old["calibratecount"]) == "string" and old["calibratecount"]:lower():find("auto") then
            local parts = {}
            for part in old["calibratecount"]:gmatch("%S+") do
                parts[#parts + 1] = part
            end
            data["Calibrate Auto"] = "Yes"
            if parts[2] then
                data["Calibrate Count"] = tonumber(parts[2]) or data["Calibrate Count"]
            end
        elseif has_content(tostring(old["calibratecount"])) then
            data["Calibrate Count"] = tonumber(old["calibratecount"]) or data["Calibrate Count"]
        end
    end

    M.save(data)
    return data
end

return M
