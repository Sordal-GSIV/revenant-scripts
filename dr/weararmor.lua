--- @revenant-script
--- name: weararmor
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Equip a gear set via EquipmentManager (default: standard)
--- tags: equipment, gear, armor
---
--- Usage:
---   ;weararmor           - Wear the "standard" gear set
---   ;weararmor <setname> - Wear the named gear set

local gearset = Script.vars[1] or "standard"

local settings = get_settings()
local equipment_manager = EquipmentManager.new(settings)
equipment_manager.wear_equipment_set(gearset)
