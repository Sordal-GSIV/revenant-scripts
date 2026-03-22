local M = {}

-- Ordered array of 20 lockpick material tier names (lowest to highest)
M.LOCKPICK_NAMES = {
    "Detrimental", "Ineffectual", "Copper", "Steel", "Gold",
    "Silver", "Mithril", "Ora", "Glaes", "Laje",
    "Vultite", "Mein", "Rolaren", "Accurate", "Veniom",
    "Invar", "Alum", "Golvern", "Kelyn", "Vaalin",
}

-- Pick modifier values per tier (indices match LOCKPICK_NAMES)
M.PICK_MODIFIERS = {
    0.80, 0.90, 1.00, 1.10, 1.20,
    1.30, 1.45, 1.55, 1.60, 1.75,
    1.80, 1.85, 1.90, 2.00, 2.20,
    2.25, 2.30, 2.35, 2.40, 2.50,
}

-- Loresing text -> numeric lock difficulty
M.LOCK_DIFFICULTIES = {
    ["a primitive lock"]                     = 35,
    ["a rudimentary lock"]                   = 75,
    ["an extremely easy lock"]               = 115,
    ["a very easy lock"]                     = 155,
    ["an easy lock"]                         = 195,
    ["a very basic lock"]                    = 235,
    ["a fairly easy lock"]                   = 275,
    ["a simple lock"]                        = 315,
    ["a fairly simple lock"]                 = 355,
    ["a fairly plain lock"]                  = 395,
    ["a moderately well-crafted lock"]       = 435,
    ["a well-crafted lock"]                  = 475,
    ["a tricky lock"]                        = 515,
    ["a somewhat difficult lock"]            = 555,
    ["a moderately difficult lock"]          = 595,
    ["a very well-crafted lock"]             = 635,
    ["a difficult lock"]                     = 675,
    ["an extremely well-crafted lock"]       = 715,
    ["a very difficult lock"]                = 755,
    ["a fairly complicated lock"]            = 795,
    ["an intricate lock"]                    = 835,
    ["an amazingly well-crafted lock"]       = 875,
    ["a very complex lock"]                  = 915,
    ["an impressively complicated lock"]     = 955,
    ["an amazingly intricate lock"]          = 995,
    ["an extremely difficult lock"]          = 1035,
    ["an extremely complex lock"]            = 1075,
    ["a masterfully well-crafted lock"]      = 1115,
    ["an amazingly complicated lock"]        = 1155,
    ["an astoundingly complex lock"]         = 1195,
    ["an incredibly intricate lock"]         = 1235,
    ["an absurdly well-crafted lock"]        = 1275,
    ["an exceedingly complex lock"]          = 1315,
    ["an absurdly difficult lock"]           = 1355,
    ["an unbelievably complicated lock"]     = 1395,
    ["a masterfully intricate lock"]         = 1435,
    ["an absurdly complex lock"]             = 1475,
    ["an impossibly complex lock"]           = 1515,
    ["You cannot even estimate its difficulty beyond being out of your league"] = "IMPOSSIBLE",
}

-- Box type noun pattern for matching box nouns
M.BOX_TYPES = "(strongbox|box|chest|trunk|coffer|case)"

-- All 17 trap type names
M.TRAP_NAMES = {
    "Scarab", "Needle", "Jaws", "Sphere", "Crystal",
    "Scales", "Sulphur", "Cloud", "Acid Vial", "Springs",
    "Fire Vial", "Spores", "Plate", "Glyph", "Rods",
    "Boomer", "No Trap",
}

-- 16 repair material names
M.REPAIR_NAMES = {
    "Repair Copper", "Repair Brass", "Repair Steel", "Repair Gold",
    "Repair Silver", "Repair Mithril", "Repair Ora", "Repair Laje",
    "Repair Vultite", "Repair Rolaren", "Repair Veniom", "Repair Invar",
    "Repair Alum", "Repair Golvern", "Repair Kelyn", "Repair Vaalin",
}

-- Messages indicating a lock/trap is too difficult
M.TOO_HARD_MESSAGES = {
    "Prayer would be a good start",
    "really don't have any chance",
    "jump off a cliff",
    "same shot as a snowball",
    "pitiful snowball encased",
}

-- Full version changelog from tpick.lic
M.VERSION_HISTORY = [[
Version 27:
	Update:
		-Script should now work proplery with the 'Emergency Module' of Gnomish Bracers.

Version 26:
	Update:
		-Script will only try DISARMing a plated box with vials bundled into your locksmith's container 3 times. After 3 times it will give up trying to DISARM and move on.
		-New setting 'Open Boxes' under the 'Other' tab. When checked you will automaticaly open boxes when using the GROUND option after you have disarmed/picked the box (the script has always done this.) When unchecked you will NOT open boxes after disarming/picking them. If you are using GROUND LOOT you will still open/loot the box no matter what this is set to.

Version 25:
	Bug fixes:
		-Script should no longer try to pop open boxes with glyph traps.

Version 24:
	Bug fixes:
		-Script should now properly recognize the new un-poppable box type: rune-incised

Version 23:
	Update:
		-There is now an option to use a Fossil Charm under the 'Other' tab of the setup menu.

Version 22:
	Bug fixes:
		-Script should now properly report how many vials of acid you have if you have unlimited putty and cotton.

Version 21:
	Update:
		-Script should now work with unlimited putty and cotton.

Version 20:
	Bug fixes:
		-Adding new messaging for using an acid vial on a plate trap.

Version 19:
	Bug fixes:
		-Dropping off and picking up boxes at the locksmith's pool wasn't working. Should be working now.

Version 18:
	Bug fixes:
		-Fixed issue with script not properly recognizing when you have turned in a difficult box at the locksmith's pool.

Version 17:
	Added messaging:
		-Added warning messaging about now having 20 ranks of Arcane Symbols to disarm scarabs.

Version 16:
	Added messaging:
		-The script might not work properly when working at the Locksmith's pool in Solhaven.
		-If this happens try this: set Description OFF then move to another room and back to the Locksmith's pool room.
		-I also added these instructions when starting the script at the Locksmith's pool in Solhaven.

Version 15:
	Bug Fixes:
		-The BUY feature should now work in every town, assuming the town locksmith shop has been properly tagged.

Version 14:
	Bug Fixes:
		-Fixed issue with Vaalin Lock Roll setting not working properly if you had 403 set to never.

Version 13:
	Bug Fixes:
		-The 'Start With Copper' feature wasn't working properly. This should now be working properly.

Version 12:
	Bug Fixes:
		-The POPPING feature of the script wasn't working at all. It should work now.
		-You no longer need to fill out red settings if you are popping boxes unless you have 'Pick Enruned' checked as well.

Version 11:
	Bug Fixes:
		-Fixed bug with containers with the word 'and' in them not showing up in list of containers in setup menu.

Version 10:
	Bug Fixes:
		-Fixed bug with fixing broken lockpicks task when using ;rogues.

Version 9:
	Bug Fixes:
		-Fixed bug where giving up on a box at the locksmith's pool was causing issues.

Version 8:
	Bug Fixes:
		-For real this time: Fixed issue with script not dropping an empty box if there are no trash receptacle in the current room.

Version 7:
	Bug Fixes:
		-Fixed issue with script hanging when trying to get things you can't pickup when bashing open boxes.

Version 6:
	Bug Fixes:
		-Fixed issue with Lmas Tricks not working properly when using ;rogues.

Version 5:
	Bug Fixes:
		-Fixed issue with script not dropping an empty box if there are no trash receptacle in the current room.

Version 4:
	Bug Fixes:
		-Fixed issue with script sometimes not working properly if you changed your profession.
		-Fixed issue with the 'Bash' feature not working when used as a command line variable.
		-Fixed bug with 'Picks On Level' setting only using Copper or Vaalin lockpicks.
		-Fixed bug with Trap Lore Bonus always being set to 0 if your character doesn't know 404 but they do know Lmas Focus.

Version 3:
	Bug Fixes:
		-Fixed issue with script not moving onto wedges/other options the first time you roll higher than your 'Vaalin Lock Roll' setting and don't pick the lock.

Version 2:
	Bug Fixes:
		-Fixed bug with script not properly calculating your lockpicking/disarming bonus from using Lock Mastery Focus.

Version 1:
	New and improved ;tpick!

	Cleaned up some code.

	Settings page:
		-Redid the settings page.
		-Changed some settings to be more clear in what they do.
		-If a setting doesn't pertain to your character (such as a setting only a Rogue would use and you're not a Rogue) then those settings are hidden.
		-Settings are now saved to a file in your Lich folder named 'Tpick Settings.'
		-You can now load settings from a different character.
		-Every setting has a tooltip to describe what that setting does.
		-Most of your old settings should transfer to the new settings when you first start the script.

	Stats:
		-Stats are now saved to a file in your Lich folder named 'Tpick Stats.'
		-Your old stats should save to the new stats when you first start the script.

	Information Window:
		-Created an Information Window that displays various information while the script is running.
		-The Information Window is now where you can see all of your stats.
		-You can select picking mode and options from the Information Window and start a picking session by clicking the 'Start' button.
		-You can click now click the 'Stop' button on the Information Window to finish up the current box you are working on and then stop working on anymore boxes.

	Command Line Variables:
		-You can now use the word 'pool' instead of 'worker'. Both now work and do the same thing.

	Other Things:
		-Many other things I am sure I'm forgetting.
]]

return M
