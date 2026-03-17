--- @revenant-script
--- name: break_rift
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Break items from a rift and stow them, stopping on close/creatures/full
--- tags: rift, crafting, ana

Flags.add("rift-closed", "With a loud creak")
Flags.add("creatures", "starcrasher", "zenziz", "zenzizenzic")
Flags.add("full", "no matter how you")

while true do
    local result = DRC.bput("break rift",
        "free from the rest",
        "free from the rift",
        "eluding your grasp",
        "miss it entirely",
        "it collapses back into the center of the rift",
        "break what")

    if result then
        if result:match("free from the rest") or result:match("free from the rift") then
            DRC.bput("stow ana", "You")
        elseif result:match("break what") then
            return
        end
    end

    if Flags["rift-closed"] or Flags["creatures"] or Flags["full"] then
        break
    end
end
