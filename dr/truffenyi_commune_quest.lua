--- @revenant-script
--- name: truffenyi_commune_quest
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Automate Truffenyi commune cleric quest prayers.
--- tags: cleric, quest, theurgy
--- Converted from truffenyi-commune-quest.lic

local start = os.time()
echo("This script does the Truffenyi commune Cleric quest actions.")
echo("Start after drinking the vial two times.")
DREMgr.empty_hands()

local visions = {
    {"glowing forge", "pray Divyaush"},
    {"dusty field", "pray Berengaria"},
    {"icy cavern", "pray Kuniyo"},
    {"occupied cots", "pray Peri'el"},
    {"alone on a raft", "pray Lemicus"},
    {"young child sitting in the corner", "pray Albreda"},
    {"travelling the desert", "pray Murrula"},
    {"long day of harvesting crops", "pray Rutilor"},
    {"sitting on a bar stool", "pray Saemaus"},
    {"walking through one of your grain fields", "pray Asketi"},
    {"outdoor wedding", "pray Be'ort"},
    {"sitting on a grassy hilltop", "pray Dergati"},
    {"waters pull away from the shore", "pray Drogor"},
    {"crackling fire next to the shore", "pray Drogor"},
    {"front row of a concert hall", "pray Idon"},
    {"entertaining a neighboring farmer", "pray Kerenhappuch"},
    {"battling a small peccary", "pray Trothfang"},
    {"standing in the snow peering", "pray Zachriedek"},
}

while true do
    local line = get()
    if line then
        for _, v in ipairs(visions) do
            if line:find(v[1], 1, true) then
                waitrt()
                DRC.bput(v[2], "In your")
                break
            end
        end
        if line:find("you have my attention") then
            local elapsed = math.floor((os.time() - start) / 60)
            echo("All done! Quest took " .. elapsed .. " minutes.")
            return
        end
        if line:find("stomach grumbles") then
            if checkright() or checkleft() then
                fput("drop " .. (checkright() or checkleft()))
            end
        end
    end
end
