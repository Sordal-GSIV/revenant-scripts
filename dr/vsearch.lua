--- @revenant-script
--- name: vsearch
--- version: 1.1
--- author: Arlov/Luxelle
--- game: dr
--- description: Search vault book with container path display.
--- tags: vault, search, storage
--- Usage: ;vsearch <search_term>

local search = Script.vars[0]
if not search or search == "" then
    respond("Usage: ;vsearch <search word/s>") return
end
fput("get vault book"); fput("read my vault book")
local vault, tier = {}, {}
while true do
    local line = get()
    if not line then goto continue end
    if line:find("Done") or line:find("There are no items") then break end
    local spaces = line:match("^(%s+)")
    if spaces and line:match("^%s+%a") then
        local lvl = math.floor(#spaces / 4) - 1
        tier[lvl] = line
    end
    if line:find(search, 1, true) then
        local lvl = spaces and math.floor(#spaces / 4) or 0
        local path = line:match("^%s*(.-)%s*$")
        if lvl > 1 then
            path = path .. " -"
            for i = 0, lvl - 2 do
                if tier[i] then path = path .. " > " .. tier[i]:match("^%s*(.-)%s*$") end
            end
        end
        table.insert(vault, "    " .. path)
    end
    ::continue::
end
respond("Matches in your vault appear below.\n")
for _, item in ipairs(vault) do respond(item) end
if #vault < 1 then respond("**I found nothing matching " .. search) end
respond("")
fput("stow vault book")
