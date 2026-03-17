--- @revenant-script
--- name: vault
--- version: 1.0
--- author: Luxelle
--- game: dr
--- description: Search vault book for items matching a keyword.
--- tags: vault, storage, search
---
--- Usage: ;vault <search_term>

local search = Script.vars[0]
if not search or search == "" then
    respond("Please enter a search term and re-start this script.")
    respond("Usage: ;vault <search word/s>")
    return
end

fput("get vault book")
fput("read my vault book")

local vault = {}
while true do
    local line = get()
    if line then
        if line:find("Done") or line:find("There are no items") then
            break
        end
        if line:find(search, 1, true) then
            table.insert(vault, line)
        end
    end
end

respond("Matches in your vault appear below.")
respond("")
for _, item in ipairs(vault) do
    respond(item)
end
if #vault < 1 then
    respond("**I found nothing matching " .. search)
end
respond("")
