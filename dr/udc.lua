--- @revenant-script
--- name: udc
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Equip a gear set via EquipmentManager (default: stealing)
--- tags: equipment, gear, stealing
---
--- Usage:
---   ;udc           - Wear the "stealing" gear set
---   ;udc <setname> - Wear the named gear set

local gearset = Script.vars[1] or "stealing"

local settings = get_settings()
local equipment_manager = EquipmentManager.new(settings)
equipment_manager.wear_equipment_set(gearset)
