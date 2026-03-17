--- @revenant-script
--- name: om
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Get Meraud orb and cast Osrel Meraud.
--- tags: cleric, magic, osrel_meraud
--- Converted from OM.lic
fput("stow right"); fput("stow left")
echo("Going to get Meraud orb...")
wait_for_script_to_complete("go2", {"1420"})
fput("kneel"); fput("pray"); fput("pray"); fput("pray")
fput("say Meraud"); fput("stand"); fput("get Meraud orb")
fput("go arch")
echo("=== OM ===")
echo("Temple puzzle navigation and OM casting require full integration.")
echo("Complete the puzzle manually, then cast OM on the orb.")
