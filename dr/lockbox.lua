--- @revenant-script
--- name: lockbox
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Practice locksmithing on training lockbox.
--- tags: locksmithing, training, box
--- Converted from lockbox.lic

local settings = get_settings()
local box = settings.picking_lockbox or "training box"
local worn = settings.picking_worn_lockbox

DREMgr.empty_hands()
if worn then
    DRC.bput("remove my " .. box, "You take", "Remove what", "aren't wearing")
    DRC.bput("close my " .. box, "You close")
else
    DRC.bput("get my " .. box, "You get", "What were")
end

while DRSkill.getxp("Locksmithing") < 34 do
    local result = DRC.bput("pick my " .. box, "not making any progress",
        "it opens", "isn't locked", "The lock feels warm")
    if result and (result:find("opens") or result:find("isn't locked")) then
        DRC.bput("lock my " .. box, "You quickly lock", "already locked")
    elseif result and result:find("warm") then
        echo("Charges used for the day, exiting.")
        break
    end
end

if worn then
    DRC.bput("pick my " .. box, "not making", "opens", "isn't locked", "warm")
    DRC.bput("open my " .. box, "You open")
    DRC.bput("wear my " .. box, "You put")
else
    DREMgr.empty_hands()
end
