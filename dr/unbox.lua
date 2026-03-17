--- @revenant-script
--- name: unbox
--- version: 1.0
--- author: Dan
--- game: dr
--- description: Get all lockboxes from inventory and drop them.
--- tags: boxes, locksmithing, utility
--- Converted from unbox.lic

local box_types = {"coffer", "box", "strongbox", "trunk", "chest", "skippet", "casket", "caddy", "crate"}

for _, box_type in ipairs(box_types) do
    while true do
        local result = dothistimeout("get my " .. box_type, 5,
            {"What were you referring to", box_type, "You are already"})
        if result and result:find("What were") then break end
        fput("drop my " .. box_type)
    end
end
