--- @revenant-script
--- name: newmagicwatch
--- version: 1.0
--- author: Kyle
--- game: dr
--- description: Watch for creature deaths and auto-run loot script
--- tags: combat, loot, hunting

local death_messages = {
    "falls to the ground and lies still",
    "then lies still",
    "then goes limp",
    "shuddering and moaning until it ceases all movement",
    "coils and uncoils rapidly before expiring",
    "growls one last time and collapses",
}

while true do
    local line = get()
    if line then
        for _, msg in ipairs(death_messages) do
            if line:find(msg, 1, true) then
                start_script("loot", {"newkyle", "newallpurpose"})
                wait_while(function() return Script.running("loot") end)
                break
            end
        end
    end
end
