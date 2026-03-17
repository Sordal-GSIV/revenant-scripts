--- @revenant-script
--- name: pick_setup
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Configure lockpicking UserVars for pick script.
--- tags: locksmithing, setup, configuration
--- Converted from pick-setup.lic

-- Edit these values for your character
UserVars.stop_on_mindlock = false
UserVars.harvest_traps = false
UserVars.use_lockpick_ring = true
UserVars.lockpicking_armor = {"stick", "balaclava", "leathers", "targe"}
UserVars.box_source = "bag"
UserVars.box_storage = "pack"
UserVars.lockpick_type = "stout"

echo("Pick setup configured:")
echo("  box_source: " .. UserVars.box_source)
echo("  box_storage: " .. UserVars.box_storage)
echo("  lockpick_type: " .. UserVars.lockpick_type)
