--- @revenant-script
--- name: arrowhead
--- version: 1.0
--- author: Damiza Nihshyde
--- game: dr
--- description: Shape arrowheads from materials in bundle.
--- tags: crafting, engineering, arrows
--- Converted from arrowhead.lic

local settings = get_settings()
local container = settings.crafting_container or "backpack"
local item = settings.crafting_arrowhead_item or "arrowhead"
local arrow_type = settings.crafting_arrowhead_type or "fang"
local tool = settings.crafting_arrowhead_tool or "drawknife"

while true do
    DRCI.stow_hands()
    DRC.bput("get my " .. tool, "You get", "What were")
    local result = DRC.bput("get " .. item .. " in bundle", "You carefully remove", "What were")
    if result and result:find("What were") then
        echo("No more " .. item .. "!"); DRCI.stow_hands(); fput("stow rope"); return
    end
    local count_result = DRC.bput("count my " .. item, "There are .* parts left")
    if count_result and (count_result:find("hundred") or count_result:find("ninety")) then
        fput("shape my " .. item .. " into " .. arrow_type); waitrt()
        fput("stow " .. tool)
        fput("get my " .. arrow_type .. " from my " .. container)
        fput("combine")
        fput("put " .. arrow_type .. " in my " .. container)
        waitfor("You put your")
    else
        fput("put " .. item .. " in my " .. container)
    end
end
