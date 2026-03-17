--- @revenant-script
--- name: searchdead
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Auto arrange, skin, search dead creatures.
--- tags: looting, skinning, combat
--- Converted from searchdead.lic
no_kill_all(); no_pause_all(); silence_me()
echo("=== searchdead ===")
echo("Watching for creature deaths to arrange/skin/loot...")
while true do
    local line = get()
    if line then
        if line:find("falls to the ground") or line:find("death rattle")
            or line:find("ceases all movement") or line:find("collapses") then
            waitrt(); pause(1)
            fput("arrange all"); waitrt()
            fput("skin"); waitrt()
            fput("loot")
        end
    end
end
