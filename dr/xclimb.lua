--- @revenant-script
--- name: xclimb
--- version: 1.0
--- author: Crannach
--- game: dr
--- description: Climb structures around Crossing for athletics training.
--- tags: athletics, climbing, training
--- Converted from xclimb.lic

local things = {
    {835, {"break", "embrasure"}}, {1035, {"wall"}}, {1039, {"wall"}},
    {1040, {"wall"}}, {691, {"wall"}}, {941, {"embrasure"}},
    {943, {"break", "embrasure"}}, {939, {"embrasure"}}, {1388, {"wall"}},
    {938, {"embrasure"}}, {940, {"break", "embrasure"}},
    {1611, {"wall"}}, {1609, {"wall"}}, {1387, {"wall"}},
}

local start_time = os.time()

while DRSkill.getxp("Athletics") <= 32 and os.time() - start_time < 1800 do
    for _, entry in ipairs(things) do
        local room_id, targets = entry[1], entry[2]
        wait_for_script_to_complete("go2", {tostring(room_id)})
        for _, target in ipairs(targets) do
            fput("climb " .. target)
            waitrt()
        end
        if DRSkill.getxp("Athletics") > 32 or os.time() - start_time > 1800 then break end
    end
end
