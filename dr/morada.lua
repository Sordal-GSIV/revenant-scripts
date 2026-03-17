--- @revenant-script
--- name: morada
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Solve Morada murder mystery cruise.
--- tags: quest, morada, mystery
--- Converted from morada.lic

DREMgr.empty_hands()
local rooms = {"16030", "16027", "16028", "16029", "16025", "16026"}
local room_names = {["16026"]="bar",["16025"]="lounge",["16028"]="buffet",
    ["16029"]="quarterdeck",["16027"]="promenade",["16030"]="foredeck"}
local weapons = {["clean edges"]="zills",["flesh and bone"]="cleaver",
    ["internal bleeding"]="baton",["severe lacerations"]="bottle",
    ["curved puncture"]="corkscrew",["ragged edges"]="knife",
    ["criss-crossed"]="comb",["gashes and severe"]="logbook",["deep and lethal"]="paintbrush"}

-- Study corpse for weapon
local result = DRC.bput("study corpse", "clean edges","flesh and bone","internal bleeding",
    "severe lacerations","curved puncture","ragged edges","criss-crossed","gashes and severe","deep and lethal")
local weapon = "unknown"
for pattern, w in pairs(weapons) do
    if result and result:find(pattern) then weapon = w; break end
end
echo("Weapon: " .. weapon)

local murderer, crimescene = "", ""
for _, room in ipairs(rooms) do
    DRCT.walk_to(room)
    if murderer == "" then
        local suspect = DRRoom.npcs and DRRoom.npcs[1]
        if suspect then
            local alibi = DRC.bput("ask " .. suspect .. " about alibi",
                "nervous tic","trembling","shifty","tugging","flushed","pacing","blinking","tapping","coughing","says,")
            if alibi and not alibi:find("says,\"") then murderer = suspect; echo("MURDERER: " .. suspect) end
        end
    end
    if crimescene == "" then
        local search = DRC.bput("search room", "uncovers an area", "fails to turn", "could not find")
        if search and search:find("uncovers") then crimescene = room_names[room] or "unknown"; echo("SCENE: " .. crimescene) end
    end
    if murderer ~= "" and crimescene ~= "" then break end
end
DRC.bput("accuse " .. murderer .. " with the " .. weapon .. " in " .. crimescene, "coupon")
DREMgr.empty_hands()
