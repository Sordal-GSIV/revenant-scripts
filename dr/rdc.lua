--- @revenant-script
--- name: rdc
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Equip a gear set via EquipmentManager, pausing go2 during swap
--- tags: equipment, gear
---
--- Usage:
---   ;rdc           - Wear the "standard" gear set
---   ;rdc <setname> - Wear the named gear set

local gearset = Script.vars[1] or "standard"

pause_script("go2")

local settings = get_settings()
local equipment_manager = EquipmentManager.new(settings)
equipment_manager.wear_equipment_set(gearset)

unpause_script("go2")
