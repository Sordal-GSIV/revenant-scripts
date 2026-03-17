--- @revenant-script
--- name: chrismsort
--- version: 1.0.0
--- author: Tatterclaws
--- game: gs
--- description: Sort gems into chrism and regular containers based on cobalt liquid content
--- tags: chrism, gems, sorting, utility
---
--- Usage:
---   ;chrismsort SOURCE GEMCONTAINER CHRISMCONTAINER
---   ;chrismsort pouch cloak pouch

local source_sack = Script.vars[1]
local gem_sack    = Script.vars[2]
local chrism_sack = Script.vars[3]

if not source_sack or not gem_sack or not chrism_sack then
    respond("You didn't specify the proper settings!")
    respond("Usage: ;chrismsort <SOURCE> <GEMCONTAINER> <CHRISMCONTAINER>")
    respond("")
    respond("Example:")
    respond("   ;chrismsort pouch cloak pouch")
    return
end

local function find_container(name)
    local inv = GameObj.inv() or {}
    for _, item in ipairs(inv) do
        if item.name:lower():find("%f[%a]" .. name:lower() .. "%f[%A]") then
            return item
        end
    end
    return nil
end

local container        = find_container(source_sack)
local gem_container    = find_container(gem_sack)
local chrism_container = find_container(chrism_sack)

if not container or not gem_container or not chrism_container then
    respond("One or more containers not found.")
    return
end

local contents = container.contents or {}
local gems = {}
for _, item in ipairs(contents) do
    if item.type and item.type:find("gem") then
        table.insert(gems, item)
    end
end

silence_me()
for _, gem in ipairs(gems) do
    dothistimeout("get #" .. gem.id .. " from #" .. container.id, 0.1, "^You ")

    local result = dothistimeout("look #" .. gem.id, 1, "cobalt liquid")
    if result then
        dothistimeout("put #" .. gem.id .. " in #" .. chrism_container.id, 0.1, "^You put")
        echo("Cobalt liquid: moved to chrism container.")
    else
        dothistimeout("put #" .. gem.id .. " in #" .. gem_container.id, 0.1, "^You put")
        echo("Normal gem: moved to gem container.")
    end
end
silence_me()

respond("All gems sorted.")
